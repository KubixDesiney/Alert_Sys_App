// =============================================================================
// Mapping engine — turns raw source readings into the SIAS ingest contract.
// =============================================================================
// A source emits { key, value, ts? }. A map rule binds a key (exact or MQTT-
// style wildcard) to a plant location (factory/line/station/machine), a metric,
// unit conversion (scale/offset) and alert thresholds. The output shape is
// exactly what the ingest worker's normalizeTelemetry() consumes — the
// conformance test in worker_test/gateway_contract.test.js runs gateway output
// through the real worker normalizer to keep the two from ever drifting.

const clip = (v, n) => String(v ?? '').trim().slice(0, n);

/** MQTT-style wildcard match: `+` = one level, `#` = the rest. */
export function wildcardMatch(pattern, key) {
  if (pattern === key) return true;
  const p = String(pattern).split('/');
  const k = String(key).split('/');
  for (let i = 0; i < p.length; i++) {
    if (p[i] === '#') return true;
    if (k[i] === undefined) return false;
    if (p[i] === '+') continue;
    if (p[i] !== k[i]) return false;
  }
  return p.length === k.length;
}

/** Rule lookup: exact match wins, then the first wildcard that matches. */
export function findMapRule(rules, key) {
  const list = Array.isArray(rules) ? rules : [];
  const exact = list.find((r) => r && r.match === key);
  if (exact) return exact;
  return list.find((r) => r && typeof r.match === 'string' && /[+#]/.test(r.match) && wildcardMatch(r.match, key)) || null;
}

/** Applies scale/offset unit conversion. Non-numeric input → null. */
export function scaleReading(value, rule = {}) {
  const n = Number(value);
  if (!Number.isFinite(n)) return null;
  const scaled = n * (rule.scale !== undefined ? Number(rule.scale) : 1) +
    (rule.offset !== undefined ? Number(rule.offset) : 0);
  return Math.round(scaled * 1000) / 1000;
}

/** Sanitized thresholds block (warn/critical/direction) or undefined. */
export function ruleThresholds(rule = {}) {
  const t = rule.thresholds;
  if (!t || typeof t !== 'object') return undefined;
  const out = {};
  if (Number.isFinite(Number(t.warn))) out.warn = Number(t.warn);
  if (Number.isFinite(Number(t.critical))) out.critical = Number(t.critical);
  if (t.direction === 'low' || t.direction === 'high') out.direction = t.direction;
  return Object.keys(out).length ? out : undefined;
}

/** Mirrors the ingest worker's threshold semantics: breached at warn-or-worse. */
export function breachesThresholds(value, thresholds) {
  if (!thresholds) return false;
  const v = Number(value);
  if (!Number.isFinite(v)) return false;
  const cmp = (limit) => (thresholds.direction === 'low' ? v <= limit : v >= limit);
  if (Number.isFinite(thresholds.critical) && cmp(thresholds.critical)) return true;
  if (Number.isFinite(thresholds.warn) && cmp(thresholds.warn)) return true;
  return false;
}

/**
 * Maps one raw reading through its rule into a SIAS ingest payload.
 * Returns null when the reading has no rule or no usable location. The ingest
 * worker makes the alert/no-alert decision (thresholds ride along and are
 * re-evaluated server-side). One contract subtlety handled here: the worker
 * treats an explicit `type` as FORCED alert creation, so a threshold rule's
 * type is attached only when the reading actually breaches — otherwise idle
 * telemetry with a typed rule would flood alerts. Event rules (`alert: true`)
 * and threshold-less typed rules keep their type on every reading by design.
 */
export function toIngestReading(reading, rule, { source = 'gateway', now = Date.now } = {}) {
  if (!reading || !rule) return null;
  const factory = clip(rule.factory, 80);
  const machine = clip(rule.machine, 80);
  const line = rule.line !== undefined ? clip(rule.line, 80) : '';
  const station = rule.station !== undefined ? clip(rule.station, 80) : '';
  if (!factory || (!line && !station && !machine)) return null;

  const value = scaleReading(reading.value, rule);
  const out = {
    source: clip(rule.source || source, 24),
    factory,
    metric: clip(rule.metric, 60),
    timestamp: Number.isFinite(Number(reading.ts)) ? Number(reading.ts) : now(),
  };
  if (machine) out.machine = machine;
  if (line) out.line = line;
  if (station) out.station = station;
  if (value !== null) out.value = value;
  if (rule.unit) out.unit = clip(rule.unit, 16);
  const thresholds = ruleThresholds(rule);
  if (thresholds) out.thresholds = thresholds;
  const typed = rule.alert === true || !thresholds || breachesThresholds(value, thresholds);
  if (rule.type && typed) out.type = clip(rule.type, 24);
  if (rule.alert === true) out.alert = true;
  if (rule.message) out.message = clip(rule.message, 240);
  return out;
}

/** Maps a batch of raw readings; unmapped/unusable readings are counted, not sent. */
export function mapReadings(readings, rules, opts = {}) {
  const mapped = [];
  let unmapped = 0;
  for (const r of Array.isArray(readings) ? readings : []) {
    const rule = findMapRule(rules, r?.key);
    const payload = rule ? toIngestReading(r, rule, opts) : null;
    if (payload) mapped.push(payload);
    else unmapped++;
  }
  return { mapped, unmapped };
}
