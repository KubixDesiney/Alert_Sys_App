// Generic REST webhook adapter (READ-ONLY input).
// Third-party systems (MES, CMMS, historians with webhook support) POST their
// own JSON; a per-webhook field map extracts the canonical fields using
// dotted paths ("data.plant.name", "readings.0.value").
import { readingToAlert } from '../mapping.mjs';

export function pick(obj, path) {
  if (path == null) return undefined;
  return String(path).split('.').reduce(
    (acc, k) => (acc == null ? undefined : acc[k]),
    obj,
  );
}

/**
 * webhookConfig:
 * { fields: { factory, line, station, machine?, metric?, value?, type?,
 *             severity?, description?, timestamp? }   // dotted paths OR
 *   constants: { factory?, line?, ... }               // fixed values
 *   type: 'maintenance', thresholds?, scale?, offset? }
 */
export function parseWebhook(body, webhookConfig = {}, { source = 'webhook', now } = {}) {
  if (!body || typeof body !== 'object') return { ok: false, error: 'body must be JSON' };
  const fields = webhookConfig.fields || {};
  const constants = webhookConfig.constants || {};
  const get = (name) => {
    if (constants[name] !== undefined) return constants[name];
    return pick(body, fields[name]);
  };

  const factory = get('factory');
  const type = get('type') ?? webhookConfig.type;
  if (!factory) return { ok: false, error: 'factory could not be extracted' };
  if (!type) return { ok: false, error: 'type could not be extracted' };

  const rule = {
    key: source,
    factory: String(factory),
    line: get('line') ?? 0,
    station: get('station') ?? 0,
    machine: get('machine') != null ? String(get('machine')) : undefined,
    metric: get('metric') != null ? String(get('metric')) : undefined,
    type: String(type),
    severity: get('severity') != null ? String(get('severity')) : webhookConfig.severity,
    thresholds: webhookConfig.thresholds,
    scale: webhookConfig.scale,
    offset: webhookConfig.offset,
    description: get('description') != null ? String(get('description')) : webhookConfig.description,
  };
  const alert = readingToAlert(
    { key: source, value: get('value'), timestamp: get('timestamp') },
    rule,
    { source, ...(now ? { now } : {}) },
  );
  return { ok: true, alert };
}
