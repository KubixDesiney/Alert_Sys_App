// Config loading + validation for gateway.config.json.
import fs from 'node:fs';

const SOURCE_TYPES = ['opcua', 'modbus', 's7', 'mqtt', 'sim'];

/** "90s" | "5m" | "2000" (ms) | number → milliseconds. */
export function parseDuration(v, fallbackMs) {
  if (v === undefined || v === null || v === '') return fallbackMs;
  if (typeof v === 'number') return v;
  const m = String(v).trim().match(/^(\d+(?:\.\d+)?)(ms|s|m|h)?$/);
  if (!m) return fallbackMs;
  const n = Number(m[1]);
  const unit = m[2] || 'ms';
  return Math.round(n * { ms: 1, s: 1000, m: 60000, h: 3600000 }[unit]);
}

/** Validates a parsed config; returns { ok, errors, config }. */
export function validateConfig(raw) {
  const errors = [];
  const cfg = raw && typeof raw === 'object' ? raw : {};
  if (!cfg.ingestUrl || !/^https?:\/\//.test(cfg.ingestUrl)) {
    errors.push('ingestUrl must be the full per-connector endpoint, e.g. https://<ingest-worker>/ingest/<connectorId>');
  }
  if (!cfg.ingestKey || String(cfg.ingestKey).length < 8) {
    errors.push('ingestKey must be the connector ingest key from your SIAS console (Infrastructure → Connectors)');
  }
  const sources = Array.isArray(cfg.sources) ? cfg.sources : [];
  if (!sources.length) errors.push('sources must contain at least one source');
  sources.forEach((s, i) => {
    if (!SOURCE_TYPES.includes(s?.type)) {
      errors.push(`sources[${i}].type must be one of: ${SOURCE_TYPES.join(', ')}`);
    }
    if (s?.type !== 'sim' && (!Array.isArray(s?.map) || s.map.length === 0)) {
      errors.push(`sources[${i}].map must bind readings to factory/line/station/machine (sim provides defaults)`);
    }
  });
  return { ok: errors.length === 0, errors, config: cfg };
}

export function loadConfig(path) {
  if (!fs.existsSync(path)) {
    throw new Error(`Config not found: ${path} (copy gateway.config.example.json and fill in your instance)`);
  }
  let raw;
  try {
    raw = JSON.parse(fs.readFileSync(path, 'utf8'));
  } catch (e) {
    throw new Error(`Config is not valid JSON: ${e.message}`);
  }
  const v = validateConfig(raw);
  if (!v.ok) throw new Error(`Invalid config:\n  - ${v.errors.join('\n  - ')}`);
  return v.config;
}
