import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { randomBytes, generateKeyPairSync, verify } from 'node:crypto';
import { createServer, connect } from 'node:http2';
import { Store } from '../src/store.mjs';
import { Worker } from '../src/worker.mjs';
import { snapshot, failed, payload } from '../src/state.mjs';
import { Providers, hkTime, validateTarget, TargetError } from '../src/providers.mjs';
import { APNs } from '../src/apns.mjs';
import { createAPI } from '../src/api.mjs';

const now = 1791849600;
const target = { regionID: 'hk', providerID: 'hk', routeKey: '1A-key', route: '1A', serviceType: '1',
  operators: ['kmb'], directions: { kmb: 'O' }, stopID: 'STOP', stopSequence: 0, language: 'en' };
const input = { token: 'aabb', tokenVersion: 1, environment: 'sandbox', target, createdAtEpoch: now, expiresAtEpoch: now + 3600 };
function fixture(t) {
  const dir = mkdtempSync(join(tmpdir(), 'bus-push-')), path = join(dir, 'db.sqlite'), key = randomBytes(32);
  const store = new Store(path, key);
  t.after(() => { store.close(); rmSync(dir, { recursive: true, force: true }); });
  return { store, path, key };
}
test('full-date ETA calculation, revisions, cancellation and subsequent departures', () => {
  assert.equal(hkTime('2026-10-14 00:02:00') - hkTime('2026-10-13 23:59:00'), 180);
  const old = snapshot([{ epoch: now + 60 }, { epoch: now + 180 }], now);
  assert.equal(Math.ceil((old.arrivalEpoch - now) / 60), 1);
  assert.equal(snapshot([{ epoch: now + 61 }], now).validUntilEpoch, now + 61);
  assert.equal(snapshot([{ epoch: now + 300, observedEpoch: now - 80 }], now).validUntilEpoch, now + 10,
    'An older operator response cannot get a fresh 90-second lease');
  assert.equal(snapshot([{ epoch: now + 90 }], now, old).change, 'adjusted');
  assert.equal(snapshot([{ epoch: now + 180 }], now + 61, old).change, 'nextBus');
  const next = snapshot([{ epoch: now + 60, message: 'Service cancelled' }, { epoch: now + 180 }], now, old);
  assert.equal(next.arrivalEpoch, now + 180); assert.equal(next.change, 'nextBus');
  assert.equal(snapshot([{ message: '已取消' }], now).status, 'cancelled');
  assert.equal(snapshot([], now).status, 'unavailable');
  assert.equal(snapshot([{ epoch: now - 1 }], now).arrivalEpoch, null);
  assert.equal(snapshot([{ epoch: now + 60, message: 'Departed from terminal' }], now).status, 'live');
  const error = failed(old, now + 10);
  assert.equal(error.updatedEpoch, old.updatedEpoch); assert.equal(error.validUntilEpoch, now + 10);
  assert.equal(error.status, 'networkError');
  assert.equal(payload(old, 'update', now).aps['stale-date'], now + 60);
  assert.equal(payload(old, 'end', now).aps['dismissal-date'], now + 60);
});
test('encrypted durable subscriptions, ownership, monotonic rotation and delete-before-register tombstones', t => {
  const { store, path, key } = fixture(t);
  assert.equal(store.enroll('owner', 'secret', now), true);
  assert.equal(store.enroll('owner', 'wrong', now), false);
  assert.equal(store.register('owner', 'trip', input), 204);
  const row = store.get('owner', 'trip'); assert.notEqual(row.token, 'aabb');
  const reopened = new Store(path, key);
  assert.equal(reopened.decrypt(reopened.get('owner', 'trip').token), 'aabb'); reopened.close();
  assert.equal(store.register('owner', 'trip', { ...input, token: 'ccdd', tokenVersion: 2 }), 204);
  store.register('owner', 'trip', input);
  assert.equal(store.decrypt(store.get('owner', 'trip').token), 'ccdd');
  assert.equal(store.register('owner', 'trip', { ...input, tokenVersion: 3,
    target: Object.fromEntries(Object.entries(target).reverse()) }), 204, 'JSON key order does not change identity');
  assert.equal(store.get('another', 'trip'), undefined);
  store.revoke('owner', 'trip', now); assert.equal(store.get('owner', 'trip').token, null);
  assert.equal(store.register('owner', 'trip', { ...input, tokenVersion: 4 }), 410);
  store.revoke('owner', 'late', now); assert.equal(store.register('owner', 'late', input), 410);
});
test('server keeps fetching without an app, advances predictions and ends at TTL', async t => {
  const { store } = fixture(t); let time = now, calls = 0; const sent = [];
  store.register('owner', 'trip', input);
  const worker = new Worker({ store, clock: () => time,
    providers: { fetch: async () => { calls++; return [{ epoch: now + (calls === 1 ? 60 : 180) }]; } },
    apns: { send: async (token, body) => { assert.equal(token, 'aabb'); sent.push(body); return { status: 200 }; } } });
  await worker.tick(); time += 61; await worker.tick();
  assert.equal(calls, 2); assert.equal(sent[1].aps['content-state'].change, 'nextBus');
  assert.equal(sent[1].aps['content-state'].updateSource, 'push');
  time = now + 3601; await worker.tick();
  assert.equal(sent[2].aps.event, 'end'); assert.equal(store.get('owner', 'trip').token, null);
});
test('provider failures are stale, APNs failures retry, invalid tokens revoke and in-flight deletion wins', async t => {
  const { store } = fixture(t); let time = now, count = 0; const sent = [];
  store.register('owner', 'trip', input);
  const worker = new Worker({ store, clock: () => time,
    providers: { fetch: async () => { throw Error('offline'); } },
    apns: { send: async (_, body) => { sent.push(body); return ++count === 1 ? { status: 503 } : { status: 200 }; } } });
  await worker.tick(); assert.equal(store.get('owner', 'trip').failures, 1);
  time += 16; await worker.tick(); assert.equal(sent[1].aps['content-state'].status, 'networkError');
  assert.ok(sent[1].aps['stale-date'] <= time);
  store.register('owner', 'invalid', input);
  worker.apns.send = async () => ({ status: 410, reason: 'Unregistered' });
  await worker.tick(); assert.notEqual(store.get('owner', 'invalid').revoked, null);
  store.register('owner', 'race', input);
  worker.providers.fetch = async () => { store.revoke('owner', 'race', time); return [{ epoch: time + 60 }]; };
  worker.apns.send = async () => { assert.fail('No send after revocation'); };
  await worker.tick();
});
test('APNs HTTP/2 request carries a verifiable ES256 JWT and exact ActivityKit headers', async t => {
  const { privateKey, publicKey } = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  const server = createServer(); await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => server.close()); let received;
  server.on('stream', (stream, headers) => {
    received = headers; let body = '';
    stream.on('data', chunk => { body += chunk; });
    stream.on('end', () => { assert.equal(JSON.parse(body).aps.event, 'update'); stream.respond({ ':status': 200 }); stream.end(); });
  });
  const apns = new APNs({ teamID: 'ABCDEFGHIJ', keyID: '0123456789', bundleID: 'app.hkbus.swiftui', environment: 'sandbox',
    privateKey: privateKey.export({ type: 'pkcs8', format: 'pem' }), connectionFactory: host => {
      assert.equal(host, 'https://api.sandbox.push.apple.com'); return connect(`http://127.0.0.1:${server.address().port}`);
    } });
  t.after(() => apns.close());
  assert.equal((await apns.send('aabb', payload(snapshot([{ epoch: now + 60 }], now), 'update', now), now + 60, now)).status, 200);
  assert.equal(received['apns-topic'], 'app.hkbus.swiftui.push-type.liveactivity');
  assert.equal(received['apns-push-type'], 'liveactivity'); assert.equal(received['apns-priority'], '5');
  assert.equal(received[':path'], '/3/device/aabb'); assert.equal(received['apns-expiration'], String(now + 60));
  const jwt = received.authorization.slice(7), parts = jwt.split('.');
  assert.equal(verify('sha256', Buffer.from(parts.slice(0, 2).join('.')), { key: publicKey, dsaEncoding: 'ieee-p1363' }, Buffer.from(parts[2], 'base64url')), true);
  assert.equal(apns.jwt(now + 60), jwt); assert.notEqual(apns.jwt(now + 3001), jwt);
});
test('registration HTTP API scopes credentials, validates targets and environment, revokes safely', async t => {
  const { store } = fixture(t);
  const server = createAPI({ store, providers: { validate: async () => {} }, environment: 'sandbox', clock: () => now });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve)); t.after(() => server.close());
  const base = `http://127.0.0.1:${server.address().port}`, owner = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  const headers = { authorization: `Bearer ${owner}.${'a'.repeat(64)}`, 'content-type': 'application/json' };
  assert.equal((await fetch(`${base}/v1/activities/trip`, { method: 'PUT', headers, body: JSON.stringify(input) })).status, 403);
  assert.equal((await fetch(`${base}/v1/installations/${owner}`, { method: 'PUT', headers })).status, 204);
  assert.equal((await fetch(`${base}/v1/activities/trip`, { method: 'PUT', headers, body: JSON.stringify({ ...input, environment: 'production' }) })).status, 422);
  assert.equal((await fetch(`${base}/v1/activities/trip`, { method: 'PUT', headers, body: JSON.stringify(input) })).status, 204);
  assert.equal((await fetch(`${base}/v1/activities/trip`, { method: 'DELETE', headers })).status, 204);
  assert.equal((await fetch(`${base}/v1/activities/trip`, { method: 'PUT', headers, body: JSON.stringify(input) })).status, 410);
  assert.throws(() => validateTarget({ ...target, operators: ['ferry'] }), TargetError);
});
test('Hong Kong adapter uses operator-specific stops, direction, occurrence and full dates', async () => {
  const entry = { route: '1A', serviceType: '1', co: ['kmb'], stops: { kmb: ['STOP'] }, bound: { kmb: 'O' } };
  const providers = new Providers({ fetcher: async url => {
    if (String(url).includes('routeFareList')) return Response.json({ routeList: { '1A-key': entry } });
    assert.ok(String(url).endsWith('/eta/STOP/1A/1'));
    return Response.json({ data: [ { dir: 'O', seq: 1, service_type: 1, eta: '2026-10-14T00:02:00+08:00' },
      { dir: 'I', seq: 1, eta: '2026-10-14T00:01:00+08:00' }, { dir: 'O', seq: 3, eta: '2026-10-14T00:03:00+08:00' } ] });
  } });
  await providers.validate(target, now);
  const rows = await providers.fetch(target, now); assert.equal(rows.length, 1);
  assert.equal(rows[0].epoch, hkTime('2026-10-14 00:02:00'));
  await assert.rejects(() => providers.validate({ ...target, stopID: 'WRONG' }, now), TargetError);
});
test('CheLaile adapter resolves physicalStId to line-station sId with WGS-84 coordinates', async () => {
  const t = { ...target, regionID: 'mainland-gz', providerID: 'mainland-440100', operators: ['mainland'],
    source: 'chelaileAPI', mode: 'bus', lineID: 'LINE', realtimeCityID: '126', stopID: 'PHYSICAL' };
  const providers = new Providers({ fetcher: async url => {
    const u = new URL(url);
    if (u.pathname.endsWith('detail')) return Response.json({ stations: [{ sId: 'LINE-STATION', physicalStId: 'PHYSICAL', order: 1, wgsLat: 23.1, wgsLng: 113.2 }] });
    assert.equal(u.searchParams.get('station_id'), 'LINE-STATION'); assert.equal(u.searchParams.get('city_id'), '126');
    assert.equal(u.searchParams.get('lat'), '23.1');
    return Response.json({ buses: [{ eta: { arrivalTime: (now + 120) * 1000 } }, { eta: { travelTime: '180' } }] });
  } });
  await providers.validate(t, now); const rows = await providers.fetch(t, now);
  assert.deepEqual(rows.map(r => r.epoch), [now + 120, now + 180]);
  assert.throws(() => validateTarget({ ...t, mode: 'metro' }), TargetError);
});
test('MTR, NLB, GMB, MTR Bus and Light Rail normalize their distinct response shapes', async () => {
  for (const [op, route, stop, bound, response, expected] of [
    ['mtr', 'EAL', 'HUH', 'DT', { status: 1, data: { 'EAL-HUH': { DOWN: [{ time: '2026-10-13 23:59:00' }], UP: [{ time: '2026-10-13 23:58:00' }] } } }, hkTime('2026-10-13 23:59:00')],
    ['nlb', '3M', '1', 'O', { estimatedArrivals: [{ estimatedArrivalTime: '2026-10-14 00:02:00', departed: '0', noGPS: '1' }] }, hkTime('2026-10-14 00:02:00')],
    ['gmb', '1', '123', 'O', { data: [{ route_seq: 1, stop_seq: 1, enabled: true, eta: [{ timestamp: '2026-10-14T00:02:00+08:00' }] }] }, hkTime('2026-10-14 00:02:00')],
    ['lrtfeeder', '506', '506-D010', 'O', { busStop: [{ busStopId: '506-D010', bus: [{ arrivalTimeInSecond: '108000', departureTimeInSecond: '120' }] }] }, now + 120],
    ['lightRail', '505', 'LR920', 'O', { platform_list: [{ route_list: [{ route_no: '505', dest_ch: '兆康', stop: 0, time_en: '3 min' }] }] }, now + 180]
  ]) {
    const t = { ...target, route, operators: [op], stopID: stop, directions: { [op]: bound } };
    const entry = { route, co: [op], serviceType: 1, stops: { [op]: [stop] }, bound: { [op]: bound }, nlbId: '37', gtfsId: '1234', dest: { zh: '兆康' } };
    const providers = new Providers({ fetcher: async (url, init) => {
      if (String(url).includes('routeFareList')) return Response.json({ routeList: { '1A-key': entry } });
      if (op === 'lrtfeeder') assert.equal(JSON.parse(init.body).routeName, '506');
      return Response.json(response);
    } });
    const rows = await providers.fetch(t, now); assert.equal(rows[0].epoch, expected, op);
    if (op === 'nlb') assert.equal(rows[0].scheduled, true);
  }
});
test('cached operator predictions do not reset freshness and permanent identity failure ends tracking', async t => {
  const providers = new Providers({ fetcher: async () => Response.json({ generated_timestamp: '2026-10-13T00:00:00+08:00', data: [] }) });
  await assert.rejects(() => providers.hkRows('kmb', { stops: { kmb: ['STOP'] }, bound: { kmb: 'O' } }, target, now), /Outdated/);
  const { store } = fixture(t); store.register('owner', 'trip', input); let end;
  const worker = new Worker({ store, clock: () => now, providers: { fetch: async () => { throw new TargetError('identity'); } },
    apns: { send: async (_, body) => { end = body; return { status: 200 }; } } });
  await worker.tick(); assert.equal(end.aps.event, 'end'); assert.equal(end.aps['content-state'].status, 'ended');
});
