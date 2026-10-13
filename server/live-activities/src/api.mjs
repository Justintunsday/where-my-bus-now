import { createServer } from 'node:http';
import { validateTarget } from './providers.mjs';

export function createAPI({ store, providers, environment, metrics = () => ({}), clock = () => Date.now() / 1000, maxSubscriptions = 1000 }) {
  // Put this single instance behind an HTTPS reverse proxy. Do not trust caller-supplied forwarding headers.
  const limits = new Map();
  return createServer({ requestTimeout: 15000, headersTimeout: 10000, maxHeaderSize: 8192 }, async (req, res) => {
    const reply = (status, body) => {
      res.writeHead(status, { 'content-type': 'application/json', 'cache-control': 'no-store' });
      res.end(body ? JSON.stringify(body) : undefined);
    };
    try {
      if (req.method === 'GET' && req.url === '/health') return reply(200, { status: 'ok', environment, worker: metrics() });
      const now = clock(), ip = req.socket.remoteAddress;
      let rate = limits.get(ip);
      if (!rate || rate.until < now) { rate = { until: now + 60, count: 0 }; limits.set(ip, rate); }
      if (limits.size > 10000) for (const [key, value] of limits) if (value.until < now) limits.delete(key);
      if (++rate.count > 120) return reply(429);
      const auth = /^Bearer ([a-f0-9-]{36})\.([a-f0-9]{64})$/.exec(req.headers.authorization ?? '');
      if (!auth) return reply(401);
      const [, owner, secret] = auth;
      const match = /^\/v1\/(installations|activities)\/([A-Za-z0-9_-]{1,160})$/.exec(req.url ?? '');
      if (!match) return reply(404);
      const [, resource, id] = match;
      if (resource === 'installations' && req.method === 'PUT' && id === owner) {
        const count = store.db.prepare('SELECT COUNT(*) AS count FROM installations').get().count;
        if (count >= maxSubscriptions * 4 && !store.authenticate(owner, secret)) return reply(503);
        return reply(store.enroll(owner, secret, now) ? 204 : 403);
      }
      if (!store.authenticate(owner, secret)) return reply(403);
      if (resource !== 'activities') return reply(405);
      if (req.method === 'DELETE') { store.revoke(owner, id, now); return reply(204); }
      if (req.method !== 'PUT') return reply(405);
      if (!req.headers['content-type']?.startsWith('application/json')) return reply(415);
      const chunks = []; let size = 0;
      for await (const chunk of req) {
        size += chunk.length;
        if (size > 12000) { reply(413); req.destroy(); return; }
        chunks.push(chunk);
      }
      const value = JSON.parse(Buffer.concat(chunks).toString('utf8'));
      if (typeof value.token !== 'string' || !/^[a-f0-9]{2,1024}$/.test(value.token) || value.token.length % 2 ||
        value.environment !== environment || !Number.isSafeInteger(value.tokenVersion) || value.tokenVersion <= 0 ||
        !Number.isFinite(value.createdAtEpoch) || !Number.isFinite(value.expiresAtEpoch) ||
        value.createdAtEpoch > now + 30 || value.expiresAtEpoch <= now || value.createdAtEpoch < now - 3600 ||
        value.expiresAtEpoch > value.createdAtEpoch + 3600) return reply(422);
      validateTarget(value.target);
      // Existing records are immutable except for token rotation; check before an expensive provider request.
      const existing = store.get(owner, id);
      if (existing?.revoked != null) return reply(410);
      if (!existing) {
        if (store.db.prepare('SELECT COUNT(*) AS count FROM subscriptions WHERE revoked IS NULL').get().count >= maxSubscriptions) return reply(503);
        if (store.db.prepare('SELECT COUNT(*) AS count FROM subscriptions WHERE owner=? AND revoked IS NULL').get(owner).count >= 4) return reply(429);
        await providers.validate(value.target, now);
      }
      reply(store.register(owner, id, value));
    } catch (error) {
      // Never include credentials, tokens, provider bodies, or target locations in logs or errors.
      reply(error.status ?? (error instanceof SyntaxError ? 400 : 502));
    }
  });
}
