import { readFileSync, mkdirSync } from 'node:fs';
import { dirname } from 'node:path';
import { Store } from './store.mjs';
import { Providers } from './providers.mjs';
import { APNs } from './apns.mjs';
import { Worker } from './worker.mjs';
import { createAPI } from './api.mjs';

const required = key => { const value = process.env[key]; if (!value) throw Error(`Missing ${key}`); return value; };
const environment = required('APNS_ENVIRONMENT');
const apns = new APNs({ environment, teamID: required('APNS_TEAM_ID'), keyID: required('APNS_KEY_ID'),
  bundleID: required('APNS_BUNDLE_ID'), privateKey: readFileSync(required('APNS_KEY_PATH')) });
const path = process.env.DATABASE_PATH ?? '/data/live-activities.sqlite';
mkdirSync(dirname(path), { recursive: true });
const store = new Store(path, Buffer.from(required('TOKEN_ENCRYPTION_KEY'), 'hex'));
const providers = new Providers({ chelaileURL: process.env.CHELAILE_URL, chelaileKey: process.env.CHELAILE_API_KEY });
const worker = new Worker({ store, providers, apns });
const maxSubscriptions = Number(process.env.MAX_SUBSCRIPTIONS ?? 1000);
if (!Number.isSafeInteger(maxSubscriptions) || maxSubscriptions < 1 || maxSubscriptions > 10000) throw Error('Invalid MAX_SUBSCRIPTIONS');
const server = createAPI({ store, providers, environment, maxSubscriptions, metrics: () => worker.metrics });
server.listen(Number(process.env.PORT ?? 8080), '0.0.0.0');
const timer = setInterval(() => worker.tick().catch(() => console.error('Worker failed')), 5000);
async function shutdown() {
  clearInterval(timer);
  server.close();
  while (worker.running) await new Promise(resolve => setTimeout(resolve, 100));
  apns.close(); store.close();
}
process.once('SIGTERM', shutdown);
process.once('SIGINT', shutdown);
