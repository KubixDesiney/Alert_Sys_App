// =============================================================================
// Sparkplug B — pure transform from a DECODED Sparkplug payload to readings.
// =============================================================================
// The protobuf decode itself is done by the optional `sparkplug-payload` peer
// (lazy-loaded in the MQTT source); this module is the pure, unit-tested part:
// decoded payload -> [{ key, value, ts }] readings for the mapping engine.
// Keys are `<topic>/<metric name>` so map rules can bind Sparkplug metrics the
// same way they bind plain MQTT topics.

/** Extracts a usable numeric/boolean value from a Sparkplug metric. */
export function sparkplugMetricValue(metric) {
  if (!metric || metric.value === undefined || metric.value === null) return null;
  const v = metric.value;
  if (typeof v === 'boolean') return v ? 1 : 0;
  if (typeof v === 'number') return Number.isFinite(v) ? v : null;
  if (typeof v === 'bigint') return Number(v);
  if (typeof v === 'object' && v !== null) {
    // Long-style objects from protobuf decoders ({ low, high, unsigned }).
    if (typeof v.toNumber === 'function') return v.toNumber();
    if (Number.isFinite(Number(v.low)) && v.high === 0) return Number(v.low);
    return null;
  }
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}

/**
 * Flattens a decoded Sparkplug B payload (NDATA/DDATA/NBIRTH/DBIRTH) into
 * mapping-engine readings. Metrics without a name or usable value are skipped.
 */
export function sparkplugMetricsToReadings(payload, topic, { now = Date.now } = {}) {
  const metrics = Array.isArray(payload?.metrics) ? payload.metrics : [];
  const baseTs = Number.isFinite(Number(payload?.timestamp)) ? Number(payload.timestamp) : now();
  const out = [];
  for (const m of metrics) {
    const name = typeof m?.name === 'string' ? m.name.trim() : '';
    if (!name) continue;
    const value = sparkplugMetricValue(m);
    if (value === null) continue;
    out.push({
      key: `${topic}/${name}`,
      value,
      ts: Number.isFinite(Number(m.timestamp)) ? Number(m.timestamp) : baseTs,
    });
  }
  return out;
}

/** True for Sparkplug data/birth message types (spBv1.0/<group>/<TYPE>/...). */
export function isSparkplugDataTopic(topic) {
  const parts = String(topic || '').split('/');
  return parts[0] === 'spBv1.0' && ['NDATA', 'DDATA', 'NBIRTH', 'DBIRTH'].includes(parts[2]);
}
