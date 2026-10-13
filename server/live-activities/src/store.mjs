import { DatabaseSync } from 'node:sqlite';
import { createCipheriv, createDecipheriv, createHash, randomBytes, timingSafeEqual } from 'node:crypto';

export const hash = value => createHash('sha256').update(value).digest('hex');
export const canonicalJSON = value => JSON.stringify(value, (_, item) =>
  item && typeof item === 'object' && !Array.isArray(item)
    ? Object.fromEntries(Object.keys(item).sort().map(key => [key, item[key]])) : item);
export class Store {
  constructor(path, key) {
    if (key.length !== 32) throw Error('TOKEN_ENCRYPTION_KEY must be 32 bytes');
    this.key = key;
    this.db = new DatabaseSync(path);
    this.db.exec(`PRAGMA journal_mode=WAL; PRAGMA busy_timeout=5000;
      CREATE TABLE IF NOT EXISTS installations(id TEXT PRIMARY KEY, secret_hash TEXT NOT NULL, created REAL NOT NULL);
      CREATE TABLE IF NOT EXISTS subscriptions(owner TEXT NOT NULL, id TEXT NOT NULL, token TEXT,
        version INTEGER NOT NULL DEFAULT 0, environment TEXT, target TEXT, created REAL, expires REAL,
        revoked REAL, next_poll REAL NOT NULL DEFAULT 0, last_state TEXT, last_sent INTEGER NOT NULL DEFAULT 0,
        failures INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(owner,id));
      CREATE INDEX IF NOT EXISTS due ON subscriptions(next_poll) WHERE revoked IS NULL;`);
  }
  encrypt(token) {
    const iv = randomBytes(12), cipher = createCipheriv('aes-256-gcm', this.key, iv);
    const bytes = Buffer.concat([cipher.update(token, 'utf8'), cipher.final()]);
    return Buffer.concat([iv, cipher.getAuthTag(), bytes]).toString('base64');
  }
  decrypt(value) {
    const bytes = Buffer.from(value, 'base64'), cipher = createDecipheriv('aes-256-gcm', this.key, bytes.subarray(0, 12));
    cipher.setAuthTag(bytes.subarray(12, 28));
    return Buffer.concat([cipher.update(bytes.subarray(28)), cipher.final()]).toString('utf8');
  }
  enroll(id, secret, now) {
    const old = this.db.prepare('SELECT secret_hash FROM installations WHERE id=?').get(id);
    if (old) return this.authenticate(id, secret);
    this.db.prepare('INSERT INTO installations VALUES(?,?,?)').run(id, hash(secret), now);
    return true;
  }
  authenticate(id, secret) {
    const row = this.db.prepare('SELECT secret_hash FROM installations WHERE id=?').get(id);
    return !!row && timingSafeEqual(Buffer.from(row.secret_hash), Buffer.from(hash(secret)));
  }
  get(owner, id) { return this.db.prepare('SELECT * FROM subscriptions WHERE owner=? AND id=?').get(owner, id); }
  register(owner, id, input) {
    const old = this.get(owner, id);
    if (old?.revoked != null) return 410;
    if (old && input.tokenVersion <= old.version) return 204; // An obsolete upload must not undo rotation.
    if (old && (old.target !== canonicalJSON(input.target) || old.created !== input.createdAtEpoch)) return 409;
    this.db.prepare(`INSERT INTO subscriptions(owner,id,token,version,environment,target,created,expires)
      VALUES(?,?,?,?,?,?,?,?) ON CONFLICT(owner,id) DO UPDATE SET token=excluded.token,version=excluded.version,
      environment=excluded.environment,next_poll=0,failures=0`).run(owner, id, this.encrypt(input.token),
      input.tokenVersion, input.environment, canonicalJSON(input.target), input.createdAtEpoch, input.expiresAtEpoch);
    return 204;
  }
  revoke(owner, id, now) {
    // Tombstone even before PUT: a late token upload cannot resurrect an ended trip.
    this.db.prepare(`INSERT INTO subscriptions(owner,id,revoked) VALUES(?,?,?)
      ON CONFLICT(owner,id) DO UPDATE SET token=NULL,target=NULL,last_state=NULL,revoked=excluded.revoked`).run(owner, id, now);
  }
  due(now) { return this.db.prepare('SELECT * FROM subscriptions WHERE revoked IS NULL AND next_poll<=? LIMIT 100').all(now); }
  current(row) { const value = this.get(row.owner, row.id); return value?.revoked == null && value?.version === row.version; }
  save(row, state, sent, next, failures = 0) {
    this.db.prepare(`UPDATE subscriptions SET last_state=?,last_sent=?,next_poll=?,failures=?
      WHERE owner=? AND id=? AND version=? AND revoked IS NULL`).run(JSON.stringify(state), sent, next, failures, row.owner, row.id, row.version);
  }
  cleanup(now) {
    this.db.prepare('DELETE FROM subscriptions WHERE revoked IS NOT NULL AND revoked<?').run(now - 172800);
    this.db.prepare(`DELETE FROM installations WHERE created<? AND id NOT IN
      (SELECT owner FROM subscriptions)`).run(now - 2592000);
  }
  close() { this.db.close(); }
}
