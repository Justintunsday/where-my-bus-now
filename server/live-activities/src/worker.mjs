import { failed, payload, snapshot, terminal } from './state.mjs';
import { TargetError } from './providers.mjs';
export class Worker {
  constructor({ store, providers, apns, clock = () => Date.now() / 1000 }) {
    Object.assign(this, { store, providers, apns, clock });
    this.metrics = { accepted: 0, providerFailures: 0, apnsFailures: 0, invalidTokens: 0, lastTickEpoch: null };
  }
  async tick() {
    if (this.running) return; // A single process owns this SQLite volume; no overlapping worker leases.
    this.running = true;
    try {
      const rows = this.store.due(this.clock());
      // Bound concurrency and reuse identical provider snapshots across subscriptions in a batch.
      const snapshots = new Map();
      for (let start = 0; start < rows.length; start += 8)
        await Promise.all(rows.slice(start, start + 8).map(row => this.update(row, snapshots)));
      this.store.cleanup(this.clock());
      this.metrics.lastTickEpoch = this.clock();
    } finally { this.running = false; }
  }
  async update(row, snapshots) {
    const now = this.clock(), previous = row.last_state ? JSON.parse(row.last_state) : undefined;
    let state, end = row.expires <= now;
    if (end) state = { arrivalEpoch: null, updatedEpoch: now, validUntilEpoch: now, status: 'ended', message: '', updateSource: 'push' };
    else {
      try {
        if (!snapshots.has(row.target)) snapshots.set(row.target, this.providers.fetch(JSON.parse(row.target), now));
        state = snapshot(await snapshots.get(row.target), now, previous);
        end = terminal.has(state.status);
      } catch (error) {
        this.metrics.providerFailures++;
        if (error instanceof TargetError) {
          end = true;
          state = { arrivalEpoch: null, updatedEpoch: now, validUntilEpoch: now, status: 'ended', message: '', updateSource: 'push' };
        } else state = failed(previous, now);
      }
    }
    if (!this.store.current(row)) return;
    // Polling is server-side only. Priority 5 is budget-friendly; no fixed device cadence is promised.
    const timestamp = Math.max(Math.floor(this.clock()), row.last_sent + 1);
    try {
      const result = await this.apns.send(this.store.decrypt(row.token), payload(state, end ? 'end' : 'update', timestamp),
        end ? timestamp + 60 : Math.floor(state.validUntilEpoch), this.clock());
      if (!this.store.current(row)) return;
      if (result.status === 200) {
        this.metrics.accepted++;
        if (end) this.store.revoke(row.owner, row.id, this.clock());
        else this.store.save(row, state, timestamp, this.clock() + 60);
      } else if (result.status === 410 || ['BadDeviceToken', 'DeviceTokenNotForTopic', 'Unregistered'].includes(result.reason)) {
        this.metrics.invalidTokens++;
        this.store.revoke(row.owner, row.id, this.clock());
      } else throw Error(`APNs ${result.status ?? 'transport'}`);
    } catch {
      this.metrics.apnsFailures++;
      // Keep the last accepted snapshot. Do not report a failed send as fresh content.
      this.store.save(row, previous ?? failed(undefined, now), row.last_sent,
        this.clock() + Math.min(300, 15 * 2 ** Math.min(row.failures, 5)), row.failures + 1);
    }
  }
}
