// Deduplication + alert-storm protection for on-prem ingestion.
//
// Two layers:
//  1. per-signal dedup: the same (factory, line, station, type) within
//     `dedupWindowMs` collapses into one alert (chattering sensors, PLC
//     retries, double-posting gateways);
//  2. storm protection: a global and per-source ceiling per minute. When a
//     source blows the ceiling the guard SUPPRESSES further alerts from it
//     and reports the transition once, so the runner can raise a single
//     "alert storm" meta-alert instead of a thousand buzzes.

export function dedupKeyFor(a = {}) {
  const norm = (v) => String(v ?? '').trim().toLowerCase();
  return [norm(a.usine), norm(a.convoyeur), norm(a.poste), norm(a.type)].join('|');
}

export class DedupGuard {
  constructor({
    dedupWindowMs = 5 * 60_000,
    maxPerMinuteGlobal = 60,
    maxPerMinutePerSource = 20,
  } = {}) {
    this.dedupWindowMs = dedupWindowMs;
    this.maxPerMinuteGlobal = maxPerMinuteGlobal;
    this.maxPerMinutePerSource = maxPerMinutePerSource;
    this.lastSeen = new Map(); // dedupKey -> ts
    this.globalHits = []; // accepted timestamps (1-min sliding window)
    this.sourceHits = new Map(); // source -> timestamps
    this.stormActive = new Set(); // sources currently in storm (incl. '' = global)
  }

  _slide(arr, now) {
    const cutoff = now - 60_000;
    while (arr.length && arr[0] <= cutoff) arr.shift();
  }

  /**
   * @returns {{action:'accept'|'duplicate'|'suppress', stormStarted?:string}}
   *  `stormStarted` is set exactly once per storm, with the offending source
   *  ('' means the global ceiling), so callers can emit ONE meta-alert.
   */
  check(alert, now = Date.now()) {
    const source = String(alert.source ?? '').trim();

    // 1. duplicate window
    const key = dedupKeyFor(alert);
    const last = this.lastSeen.get(key);
    if (last != null && now - last < this.dedupWindowMs) {
      return { action: 'duplicate', key };
    }

    // 2. storm ceilings (checked before accepting)
    this._slide(this.globalHits, now);
    const perSource = this.sourceHits.get(source) || [];
    this._slide(perSource, now);
    this.sourceHits.set(source, perSource);

    if (perSource.length >= this.maxPerMinutePerSource) {
      const started = !this.stormActive.has(source);
      this.stormActive.add(source);
      return started
        ? { action: 'suppress', key, stormStarted: source }
        : { action: 'suppress', key };
    }
    if (this.globalHits.length >= this.maxPerMinuteGlobal) {
      const started = !this.stormActive.has('');
      this.stormActive.add('');
      return started
        ? { action: 'suppress', key, stormStarted: '' }
        : { action: 'suppress', key };
    }

    // accepted
    this.lastSeen.set(key, now);
    this.globalHits.push(now);
    perSource.push(now);
    if (perSource.length < this.maxPerMinutePerSource) this.stormActive.delete(source);
    if (this.globalHits.length < this.maxPerMinuteGlobal) this.stormActive.delete('');
    // housekeeping so lastSeen cannot grow unboundedly
    if (this.lastSeen.size > 10_000) {
      for (const [k, ts] of this.lastSeen) {
        if (now - ts >= this.dedupWindowMs) this.lastSeen.delete(k);
      }
    }
    return { action: 'accept', key };
  }
}
