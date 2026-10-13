// Unix seconds, identical to Shared/BusActivityAttributes.swift. No JS Date JSON encoding.
export const terminal = new Set(['cancelled', 'arrived', 'departed', 'ended']);
export function reportedStatus(message = '') {
  const text = message.trim().toLowerCase();
  if (['cancelled', 'canceled', 'service cancelled', 'service canceled', '班次取消', '已取消', '取消'].includes(text)) return 'cancelled';
  if (['arrived at stop', 'bus arrived', '已到站', '班次已到站'].includes(text)) return 'arrived';
  if (['departed from this stop', 'bus departed', '班次已離站', '班次已离站'].includes(text)) return 'departed';
  return null;
}
export function snapshot(rows, now, previous) {
  const upcoming = rows.filter(r => Number.isFinite(r.epoch) && r.epoch > now && !reportedStatus(r.message))
    .sort((a, b) => a.epoch - b.epoch);
  const first = upcoming[0];
  const observed = Number.isFinite(first?.observedEpoch) ? Math.min(now, first.observedEpoch) : now;
  const state = { arrivalEpoch: first?.epoch ?? null, updatedEpoch: observed,
    validUntilEpoch: first ? Math.min(observed + 90, first.epoch) : now,
    status: first ? (first.scheduled ? 'scheduled' : 'live') :
      (rows.map(r => reportedStatus(r.message)).find(Boolean) ?? 'unavailable'),
    message: String(first?.message ?? rows[0]?.message ?? '').slice(0, 160), updateSource: 'push' };
  if (upcoming[1]) state.secondArrivalEpoch = upcoming[1].epoch;
  if (previous?.arrivalEpoch != null && first) {
    if (previous.arrivalEpoch <= now || rows.some(r => terminal.has(reportedStatus(r.message)) && Math.abs(r.epoch - previous.arrivalEpoch) < 15)) state.change = 'nextBus';
    else if (Math.abs(previous.arrivalEpoch - first.epoch) >= 15) state.change = 'adjusted';
  }
  // An empty board is not proof of end of service. Keep monitoring for subsequent departures.
  return state;
}
export function failed(previous, now) {
  return { ...previous, arrivalEpoch: previous?.arrivalEpoch ?? null,
    updatedEpoch: previous?.updatedEpoch ?? now, validUntilEpoch: Math.min(previous?.validUntilEpoch ?? now, now),
    status: 'networkError', message: '', change: null, updateSource: 'push' };
}
export function payload(state, event, timestamp) {
  const aps = { timestamp, event, 'content-state': state, 'stale-date': Math.floor(state.validUntilEpoch) };
  if (event === 'end') aps['dismissal-date'] = timestamp + 60;
  const value = { aps };
  if (Buffer.byteLength(JSON.stringify(value)) > 4096) throw Error('APNs payload exceeds 4 KB');
  return value;
}
