import { writeFileSync } from 'node:fs';
import { snapshot, payload } from '../src/state.mjs';
const now = 1791849600;
writeFileSync(process.argv[2], JSON.stringify(payload(snapshot([{ epoch: now + 61 }, { epoch: now + 180, scheduled: true }], now), 'update', now)));
