// =============================================================================
// Plant simulator — the built-in, zero-dependency demo engine.
// =============================================================================
// Generates believable machine telemetry for N machines: bearing temperatures
// with slow drift, vibration, and line speed — plus periodic fault injection
// (a bearing temp excursion above the critical threshold for a few cycles).
// `node gateway/bin/sias-gateway.mjs --sim 6 --fault-every 90s` against a real
// instance produces a live plant demo: normal telemetry is dropped by the
// ingest worker's severity gate, faults become real SIAS alerts.
// Deterministic under an injected seed/clock for tests.

/** mulberry32 — tiny deterministic PRNG. */
export function makeRng(seed = 42) {
  let a = seed >>> 0;
  return function rng() {
    a |= 0; a = (a + 0x6D2B79F5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const METRICS = [
  { metric: 'bearing_temperature', unit: '°C', base: 58, jitter: 1.2, drift: 0.35, thresholds: { warn: 80, critical: 90, direction: 'high' }, type: 'maintenance' },
  { metric: 'vibration', unit: 'mm/s', base: 2.4, jitter: 0.25, drift: 0.05, thresholds: { warn: 6, critical: 9, direction: 'high' }, type: 'maintenance' },
  { metric: 'line_speed', unit: 'm/min', base: 42, jitter: 0.8, drift: 0, thresholds: { warn: 30, critical: 22, direction: 'low' }, type: 'defaut_produit' },
];

/** Default map rules for the simulator's keys — factory/line/station/machine. */
export function simMapRules(machines, factory = 'Demo Plant') {
  const rules = [];
  for (let i = 1; i <= machines; i++) {
    const machine = `MACH-${String(i).padStart(3, '0')}`;
    for (const m of METRICS) {
      rules.push({
        match: `sim/${machine}/${m.metric}`,
        factory,
        line: `Conveyor ${((i - 1) % 3) + 1}`,
        station: String(((i - 1) % 6) + 1),
        machine,
        metric: m.metric,
        unit: m.unit,
        thresholds: m.thresholds,
        type: m.type,
      });
    }
  }
  return rules;
}

export class SimSource {
  constructor({ machines = 6, faultEveryMs = 90000, intervalMs = 2000, seed = 42, now = Date.now } = {}) {
    this.machines = Math.max(1, Math.min(500, Number(machines) || 6));
    this.faultEveryMs = Math.max(5000, Number(faultEveryMs) || 90000);
    this.intervalMs = Math.max(250, Number(intervalMs) || 2000);
    this.now = now;
    this.rng = makeRng(seed);
    this.lastFaultAt = 0;
    this.state = [];
    for (let i = 1; i <= this.machines; i++) {
      this.state.push({
        machine: `MACH-${String(i).padStart(3, '0')}`,
        values: METRICS.map((m) => m.base + (this.rng() - 0.5) * 4),
        faultCyclesLeft: 0,
        faultMetric: 0,
      });
    }
  }

  /** Injects a fault into one machine: a few cycles above critical. */
  _maybeInjectFault(nowMs) {
    if (nowMs - this.lastFaultAt < this.faultEveryMs) return null;
    this.lastFaultAt = nowMs;
    const victim = this.state[Math.floor(this.rng() * this.state.length)];
    victim.faultCyclesLeft = 3 + Math.floor(this.rng() * 3);
    victim.faultMetric = this.rng() < 0.7 ? 0 : 1; // mostly bearing temp, sometimes vibration
    return victim.machine;
  }

  /** One simulation tick → raw readings for the mapping engine. */
  tick(nowMs = this.now()) {
    const faulted = this._maybeInjectFault(nowMs);
    const readings = [];
    for (const s of this.state) {
      s.values = s.values.map((v, mi) => {
        const m = METRICS[mi];
        // slow random walk toward base + jitter
        let next = v + (m.base - v) * 0.02 + (this.rng() - 0.5) * 2 * m.jitter + (this.rng() - 0.5) * m.drift;
        if (s.faultCyclesLeft > 0 && mi === s.faultMetric) {
          const t = m.thresholds;
          next = t.direction === 'low'
            ? t.critical - 2 - this.rng() * 3
            : t.critical + 2 + this.rng() * 6;
        }
        return Math.round(next * 100) / 100;
      });
      if (s.faultCyclesLeft > 0) s.faultCyclesLeft--;
      METRICS.forEach((m, mi) => {
        readings.push({ key: `sim/${s.machine}/${m.metric}`, value: s.values[mi], ts: nowMs });
      });
    }
    return { readings, faulted };
  }

  start({ onReadings, log = console, setTimer = setInterval } = {}) {
    log.info?.(`[sias-gateway] sim source: ${this.machines} machines, fault every ${Math.round(this.faultEveryMs / 1000)}s, tick ${this.intervalMs}ms`);
    this._timer = setTimer(() => {
      const { readings, faulted } = this.tick();
      if (faulted) log.warn?.(`[sias-gateway] sim: FAULT injected on ${faulted}`);
      onReadings(readings);
    }, this.intervalMs);
    return this;
  }

  stop() {
    if (this._timer) clearInterval(this._timer);
    this._timer = null;
  }
}
