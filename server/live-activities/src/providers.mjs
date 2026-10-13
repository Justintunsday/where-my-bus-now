const HK_OPERATORS = new Set(['kmb', 'ctb', 'nlb', 'gmb', 'mtr', 'lrtfeeder', 'lightRail']);
export class TargetError extends Error { constructor(message) { super(message); this.status = 422; } }
const requireValue = (condition, message) => { if (!condition) throw new TargetError(message); };
const segment = value => encodeURIComponent(String(value));
const sourceEpoch = (data, now) => {
  const value = data.generated_timestamp ?? data.sys_time ?? data.current_time;
  return value ? Math.min(now, hkTime(value)) : now;
};
export function validateTarget(t) {
  requireValue(t && typeof t === 'object' && !Array.isArray(t), 'Invalid target');
  for (const key of ['regionID', 'providerID', 'routeKey', 'route', 'serviceType', 'stopID', 'language'])
    requireValue(typeof t[key] === 'string' && t[key].length > 0 && t[key].length <= 300, `Invalid ${key}`);
  requireValue(Number.isInteger(t.stopSequence) && t.stopSequence >= 0 && t.stopSequence < 2000, 'Invalid sequence');
  requireValue(Array.isArray(t.operators) && t.operators.length > 0 && t.operators.length <= 4 &&
    t.operators.every(op => typeof op === 'string'), 'Invalid operators');
  requireValue(t.directions && typeof t.directions === 'object' && !Array.isArray(t.directions), 'Invalid directions');
  requireValue(['en', 'zh', 'zhHans'].includes(t.language), 'Invalid language');
  if (t.providerID === 'hk') {
    requireValue(t.regionID === 'hk' && t.operators.every(op => HK_OPERATORS.has(op)), 'No remote adapter for this Hong Kong service');
  } else {
    requireValue(/^(chelaile-api|mainland)-\d+$/.test(t.providerID) && /^\d{1,8}$/.test(t.realtimeCityID ?? '') && t.mode !== 'metro' && t.source === 'chelaileAPI' &&
      typeof t.lineID === 'string' && t.lineID.length > 0 && t.lineID.length <= 200, 'No remote adapter for this provider');
  }
  return t;
}
export const hkTime = value => {
  if (typeof value !== 'string' || !value) return NaN;
  // Hong Kong operator local timestamps always refer to a full calendar date, including after midnight.
  const text = value.replace(' ', 'T');
  return Date.parse(/[zZ]|[+-]\d\d:\d\d$/.test(text) ? text : `${text}+08:00`) / 1000;
};
export class Providers {
  constructor({ fetcher = fetch, chelaileURL = 'https://ts-api.tundrey.com/v1/', chelaileKey } = {}) {
    this.fetcher = fetcher;
    this.chelaileURL = new URL(chelaileURL.endsWith('/') ? chelaileURL : chelaileURL + '/');
    if (this.chelaileURL.protocol !== 'https:') throw Error('CheLaile URL requires HTTPS');
    this.chelaileKey = chelaileKey;
    this.cache = new Map();
  }
  async json(url, init = {}) {
    const response = await this.fetcher(url, { ...init, redirect: 'error', signal: AbortSignal.timeout(10000),
      headers: { 'cache-control': 'no-cache', ...init.headers } });
    if (!response.ok) throw Error(`Upstream HTTP ${response.status}`);
    const text = await response.text();
    if (text.length > 40_000_000) throw Error('Upstream response too large');
    return JSON.parse(text);
  }
  async cached(key, now, loader) {
    const old = this.cache.get(key);
    if (old && old.until > now) return old.value;
    const value = await loader();
    if (this.cache.size > 500) this.cache.clear();
    this.cache.set(key, { value, until: now + 3600 });
    return value;
  }
  async hkEntry(t, now) {
    const db = await this.cached('hk', now, () => this.json('https://data.hkbus.app/routeFareList.min.json'));
    const entry = db.routeList?.[t.routeKey];
    const stops = (entry?.co ?? []).map(op => entry.stops[op]).filter(Boolean)
      .reduce((best, list) => list.length > best.length ? list : best, []);
    requireValue(entry && entry.route === t.route && String(entry.serviceType ?? 1) === t.serviceType &&
      JSON.stringify([...entry.co].sort()) === JSON.stringify([...t.operators].sort()) &&
      Object.keys(entry.bound).length === Object.keys(t.directions).length &&
      Object.entries(entry.bound).every(([op, bound]) => t.directions[op] === bound) &&
      stops?.[t.stopSequence] === t.stopID, 'Boarding identity no longer matches the Hong Kong database');
    return entry;
  }
  async chelaile(path, params) {
    const url = new URL(path, this.chelaileURL);
    Object.entries(params).forEach(([key, value]) => url.searchParams.set(key, String(value)));
    const result = await this.json(url, { headers: this.chelaileKey ? { 'x-api-key': this.chelaileKey } : {} });
    if (result.error) throw Error('CheLaile upstream error');
    return result.data ?? result;
  }
  async mainlandStation(t, now) {
    const city_id = t.realtimeCityID;
    const detail = await this.cached(`${city_id}/${t.lineID}`, now,
      () => this.chelaile('lines/detail', { city_id, line_id: t.lineID }));
    const station = detail.stations?.find(s => s.physicalStId === t.stopID || s.sId === t.stopID);
    requireValue(station?.sId && Number(station.order) === t.stopSequence + 1 &&
      station.wgsLat != null && station.wgsLng != null && Number.isFinite(Number(station.wgsLat)) &&
      Number.isFinite(Number(station.wgsLng)), 'CheLaile boarding station no longer matches');
    requireValue(!detail.line?.isSubway, 'Metro realtime is unsupported');
    return { city_id, station };
  }
  async validate(t, now) {
    validateTarget(t);
    if (t.providerID === 'hk') await this.hkEntry(t, now);
    else await this.mainlandStation(t, now);
  }
  async fetch(t, now) {
    if (t.providerID !== 'hk') {
      const { city_id, station } = await this.mainlandStation(t, now);
      const data = await this.chelaile('lines/realtime', { city_id, line_id: t.lineID,
        target_order: station.order, station_id: station.sId, lat: station.wgsLat, lng: station.wgsLng });
      if (!Array.isArray(data.buses)) throw Error('Invalid CheLaile prediction');
      return data.buses.map(b => ({ epoch: Number(b.eta?.arrivalTime) > 0 ? Number(b.eta.arrivalTime) / 1000 :
        (b.eta?.travelTime != null && Number(b.eta.travelTime) >= 0 ? now + Number(b.eta.travelTime) : NaN) }));
    }
    const entry = await this.hkEntry(t, now);
    const results = await Promise.allSettled(t.operators.map(op => this.hkRows(op, entry, t, now)));
    // Partial operator failures must not silently promote a later joint-route departure.
    const failure = results.find(r => r.status === 'rejected');
    if (failure) throw failure.reason;
    return results.flatMap(r => r.value);
  }
  async hkRows(op, entry, t, now) {
    const stop = entry.stops[op]?.[t.stopSequence], bound = entry.bound[op], seq = t.stopSequence + 1;
    requireValue(stop, 'Missing operator stop');
    const chinese = t.language !== 'en';
    const assertFresh = data => {
      const raw = data.generated_timestamp ?? data.sys_time ?? data.current_time;
      if (raw) {
        const stamp = hkTime(raw);
        if (!Number.isFinite(stamp) || stamp > now + 30 || now - stamp >= 90) throw Error('Outdated operator snapshot');
      }
      return data;
    };
    const get = async (url, init) => assertFresh(await this.json(url, init));
    const row = r => {
      if (r.data_timestamp) assertFresh({ generated_timestamp: r.data_timestamp });
      return { epoch: hkTime(r.eta), observedEpoch: Math.min(sourceEpoch(data, now), r.data_timestamp ? hkTime(r.data_timestamp) : now), message: r[chinese ? 'rmk_tc' : 'rmk_en'] ?? '',
        scheduled: /scheduled|預定|计划/i.test(r.rmk_en ?? r.rmk_tc ?? '') };
    };
    let data;
    switch (op) {
    case 'kmb':
      data = await get(`https://data.etabus.gov.hk/v1/transport/kmb/eta/${segment(stop)}/${segment(t.route)}/${segment(t.serviceType)}`);
      if (!Array.isArray(data.data)) throw Error('Invalid KMB data');
      return data.data.filter(r => r.dir === bound && r.seq === seq && (r.service_type == null || String(r.service_type) === t.serviceType)).map(row);
    case 'ctb':
      data = await get(`https://rt.data.gov.hk/v2/transport/citybus/eta/CTB/${segment(stop)}/${segment(t.route)}`);
      if (!Array.isArray(data.data)) throw Error('Invalid Citybus data');
      return data.data.filter(r => r.dir && bound.includes(r.dir) && r.seq === seq).map(row);
    case 'mtr': {
      data = await get(`https://rt.data.gov.hk/v1/transport/mtr/getSchedule.php?line=${segment(t.route)}&sta=${segment(stop)}`);
      if (data.status !== 1) throw Error('MTR prediction temporarily unavailable');
      const line = data.data?.[`${t.route}-${stop}`];
      if (!line) throw Error('Missing MTR station');
      return (line[bound.endsWith('UT') ? 'UP' : 'DOWN'] ?? []).map(r => ({ epoch: hkTime(r.time), observedEpoch: sourceEpoch(data, now), message: '' }));
    }
    case 'nlb':
      requireValue(entry.nlbId != null, 'Missing NLB route identifier');
      data = await get(`https://rt.data.gov.hk/v2/transport/nlb/stop.php?action=estimatedArrivals&routeId=${segment(entry.nlbId)}&stopId=${segment(stop)}&language=${chinese ? 'zh' : 'en'}`);
      if (!Array.isArray(data.estimatedArrivals)) throw Error('NLB prediction unavailable');
      return data.estimatedArrivals.map(r => ({ epoch: hkTime(r.estimatedArrivalTime), observedEpoch: sourceEpoch(data, now), scheduled: r.departed !== '1' || r.noGPS === '1', message: '' }));
    case 'gmb':
      requireValue(entry.gtfsId != null, 'Missing GMB route identifier');
      data = await get(`https://data.etagmb.gov.hk/eta/route-stop/${segment(entry.gtfsId)}/${segment(stop)}`);
      if (!Array.isArray(data.data)) throw Error('Invalid GMB data');
      return data.data.filter(r => r.stop_seq === seq && r.route_seq === (bound === 'O' ? 1 : 2) && r.enabled)
        .flatMap(r => r.eta ?? []).map(r => ({ epoch: hkTime(r.timestamp), observedEpoch: sourceEpoch(data, now), message: r[chinese ? 'remarks_tc' : 'remarks_en'] ?? '' }));
    case 'lrtfeeder':
      data = await get('https://rt.data.gov.hk/v1/transport/mtr/bus/getSchedule', { method: 'POST',
        headers: { 'content-type': 'application/json' }, body: JSON.stringify({ language: chinese ? 'zh' : 'en', routeName: t.route }) });
      if (!Array.isArray(data.busStop)) throw Error('Invalid MTR Bus data');
      return data.busStop.filter(r => r.busStopId === stop).flatMap(r => r.bus ?? []).map(r => {
        const seconds = Number(r.arrivalTimeInSecond === '108000' ? r.departureTimeInSecond : r.arrivalTimeInSecond);
        return { epoch: Number.isFinite(seconds) && seconds >= 0 ? sourceEpoch(data, now) + seconds : NaN, observedEpoch: sourceEpoch(data, now), scheduled: r.isScheduled === '1' };
      });
    case 'lightRail':
      data = await get(`https://rt.data.gov.hk/v1/transport/mtr/lrt/getSchedule?station_id=${segment(stop.slice(2))}&with_special=1`);
      if (!Array.isArray(data.platform_list)) throw Error('Invalid Light Rail data');
      return data.platform_list.flatMap(p => p.route_list ?? []).filter(r =>
        (r.route_no === t.route || r.additionalInfo1 === t.route) && r.stop === 0 &&
        (r.dest_ch === entry.dest.zh || r.dest_en?.includes('Circular'))).map(r => {
        const minutes = /^(\d+)/.exec(r.time_en ?? '');
        return { epoch: minutes ? sourceEpoch(data, now) + Number(minutes[1]) * 60 : NaN, observedEpoch: sourceEpoch(data, now) };
      });
    default: throw new TargetError('Unsupported operator');
    }
  }
}
