// MQTT adapter (READ-ONLY: subscribes only, never publishes to control topics).
//
// Pure part: topic matching + payload decoding, fully unit-tested.
// Runtime part: startMqtt() lazily imports the optional `mqtt` package and
// subscribes; reconnect/backoff is delegated to mqtt.js's built-ins.
import { readingToAlert, findRule, wildcardMatch } from '../mapping.mjs';

export { wildcardMatch };

/** Decodes an MQTT message body: JSON `{value, ts?}`, bare number, or text. */
export function decodePayload(buf) {
  const text = Buffer.isBuffer(buf) ? buf.toString('utf8') : String(buf);
  const trimmed = text.trim();
  try {
    const json = JSON.parse(trimmed);
    if (typeof json === 'number') return { value: json };
    if (json && typeof json === 'object') {
      return {
        value: json.value ?? json.val ?? json.v ?? null,
        timestamp: json.ts ?? json.timestamp ?? undefined,
        raw: json,
      };
    }
  } catch (_) { /* not JSON */ }
  const num = Number(trimmed);
  if (trimmed !== '' && Number.isFinite(num)) return { value: num };
  return { value: null, text: trimmed };
}

/** topic + message + rules -> canonical alert (or null when below threshold). */
export function mqttMessageToAlert(topic, message, rules, { now } = {}) {
  const rule = findRule(rules, topic);
  if (!rule) return null;
  const decoded = decodePayload(message);
  return readingToAlert(
    { key: topic, value: decoded.value, timestamp: decoded.timestamp },
    rule,
    { source: `mqtt:${topic}`, ...(now ? { now } : {}) },
  );
}

/**
 * Runtime. config: { url, username?, password?, topics: [..], rules: [..] }
 * Requires the optional `mqtt` dependency at runtime (not in tests).
 */
export async function startMqtt(config, onAlert, log) {
  let mqttLib;
  try {
    mqttLib = (await import('mqtt')).default;
  } catch (_) {
    throw new Error('mqtt adapter enabled but the "mqtt" package is not installed');
  }
  const client = mqttLib.connect(config.url, {
    username: config.username,
    password: config.password,
    reconnectPeriod: 5000, // auto-reconnect
  });
  client.on('connect', () => {
    for (const t of config.topics || []) client.subscribe(t);
    if (log) log.info('mqtt connected', { url: config.url, topics: config.topics });
  });
  client.on('message', (topic, message) => {
    const alert = mqttMessageToAlert(topic, message, config.rules || []);
    if (alert) onAlert(alert);
  });
  client.on('error', (err) => log && log.warn('mqtt error', { err: String(err) }));
  return () => client.end(true);
}
