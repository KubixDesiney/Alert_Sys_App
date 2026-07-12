// Tag/register mapping + threshold engine (pure).
//
// Every adapter reduces its protocol input to a `reading`:
//   { key, value, timestamp?, params? }        (key = topic / nodeId / tag / register name)
// A MappingRule then decides whether that reading becomes a canonical SIAS
// alert, and how it maps onto factory / line / station / machine / metric.

/**
 * @typedef {object} MappingRule
 * @property {string}  key        reading key this rule applies to (exact match
 *                                or template params already resolved)
 * @property {string}  factory
 * @property {number|string} line
 * @property {number|string} station
 * @property {string} [machine]
 * @property {string} [metric]
 * @property {string}  type       SIAS alert type code (qualite, maintenance, …)
 * @property {string} [severity]  'normal' | 'critical' (default normal)
 * @property {number} [scale]     value' = value * scale + offset
 * @property {number} [offset]
 * @property {object} [thresholds] { gt, gte, lt, lte, eq, notEq } — alert fires
 *                                when ANY configured comparison is breached.
 *                                No thresholds = every reading alerts (events).
 * @property {string} [description] template, {value}/{metric}/{machine} filled in
 */

export function scaleValue(raw, rule = {}) {
  const num = Number(raw);
  if (!Number.isFinite(num)) return null;
  return num * (rule.scale ?? 1) + (rule.offset ?? 0);
}

/** @returns {{breached: boolean, reason: string|null}} */
export function applyThresholds(value, thresholds) {
  if (!thresholds || typeof thresholds !== 'object' || !Object.keys(thresholds).length) {
    return { breached: true, reason: null }; // event-style rule: always fires
  }
  if (value == null || !Number.isFinite(Number(value))) {
    return { breached: false, reason: null };
  }
  const v = Number(value);
  const checks = [
    ['gt', (t) => v > t, (t) => `> ${t}`],
    ['gte', (t) => v >= t, (t) => `>= ${t}`],
    ['lt', (t) => v < t, (t) => `< ${t}`],
    ['lte', (t) => v <= t, (t) => `<= ${t}`],
    ['eq', (t) => v === t, (t) => `== ${t}`],
    ['notEq', (t) => v !== t, (t) => `!= ${t}`],
  ];
  for (const [name, cmp, label] of checks) {
    const t = thresholds[name];
    if (t != null && cmp(Number(t))) {
      return { breached: true, reason: `${v} ${label(Number(t))}` };
    }
  }
  return { breached: false, reason: null };
}

function fillTemplate(tpl, vars) {
  return String(tpl).replace(/\{(\w+)\}/g, (_, k) => (vars[k] ?? ''));
}

/**
 * Turns a reading into a canonical SIAS alert payload — or null when the
 * value does not breach the rule's thresholds.
 */
export function readingToAlert(reading, rule, { source = 'edge-gateway', now = () => new Date() } = {}) {
  if (!rule) return null;
  const value = scaleValue(reading.value, rule);
  const { breached, reason } = applyThresholds(value ?? reading.value, rule.thresholds);
  if (!breached) return null;
  const vars = {
    value: value ?? reading.value,
    metric: rule.metric || reading.key,
    machine: rule.machine || '',
    reason: reason || 'event',
  };
  return {
    factory: rule.factory,
    line: Number(rule.line ?? 0),
    station: Number(rule.station ?? 0),
    machine: rule.machine || undefined,
    metric: rule.metric || reading.key,
    value: value ?? undefined,
    severity: (rule.severity || 'normal').toLowerCase(),
    type: rule.type,
    description: rule.description
      ? fillTemplate(rule.description, vars)
      : `${vars.metric}${reason ? ` ${reason}` : ''}${vars.machine ? ` on ${vars.machine}` : ''}`,
    timestamp: (reading.timestamp ? new Date(reading.timestamp) : now()).toISOString(),
    source,
  };
}

/** Exact-key lookup with a one-level wildcard fallback (`plant/+/temp`). */
export function findRule(rules, key) {
  if (!Array.isArray(rules)) return null;
  const exact = rules.find((r) => r.key === key);
  if (exact) return exact;
  return rules.find((r) => r.key && r.key.includes('+') && wildcardMatch(r.key, key)) || null;
}

export function wildcardMatch(pattern, key) {
  const p = String(pattern).split('/');
  const k = String(key).split('/');
  if (p.length !== k.length && !p.includes('#')) return false;
  for (let i = 0; i < p.length; i++) {
    if (p[i] === '#') return true;
    if (p[i] === '+') continue;
    if (p[i] !== k[i]) return false;
  }
  return p.length === k.length;
}
