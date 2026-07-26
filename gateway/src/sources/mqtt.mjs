// MQTT source — subscribes to topics via the optional `mqtt` peer, with
// Sparkplug B payload decode (optional `sparkplug-payload` peer) when
// `sparkplug: true`. Reading keys are topics (plain) or topic/metricName
// (Sparkplug) — the same wildcard grammar as the map rules.
import { lazyImport } from '../lazy.mjs';
import { sparkplugMetricsToReadings, isSparkplugDataTopic } from '../sparkplug.mjs';

/** Pure: plain-MQTT message buffer → readings (JSON object/number payloads). */
export function mqttMessageToReadings(topic, payloadBuf, { now = Date.now } = {}) {
  const text = payloadBuf.toString('utf8').trim();
  const asNumber = Number(text);
  if (text !== '' && Number.isFinite(asNumber)) {
    return [{ key: topic, value: asNumber, ts: now() }];
  }
  try {
    const obj = JSON.parse(text);
    if (obj && typeof obj === 'object') {
      const value = Number(obj.value ?? obj.v);
      if (Number.isFinite(value)) {
        const ts = Number.isFinite(Number(obj.ts ?? obj.timestamp)) ? Number(obj.ts ?? obj.timestamp) : now();
        return [{ key: topic, value, ts }];
      }
    }
  } catch { /* not JSON — ignored */ }
  return [];
}

export async function createMqttSource(cfg, { onReadings, log = console }) {
  const mqtt = await lazyImport('mqtt', { protocol: 'mqtt' });
  const url = cfg.url;
  if (!url) throw new Error('mqtt source needs "url" (e.g. mqtt://broker:1883)');
  const topics = Array.isArray(cfg.topics) && cfg.topics.length
    ? cfg.topics
    : (cfg.map || []).map((r) => r.match).filter(Boolean);
  if (!topics.length) throw new Error('mqtt source needs "topics" or map rules');

  let decodeSparkplug = null;
  if (cfg.sparkplug) {
    const sp = await lazyImport('sparkplug-payload', { protocol: 'mqtt (sparkplug)' });
    const codec = (sp.default || sp).get('spBv1.0');
    decodeSparkplug = (buf) => codec.decodePayload(buf);
  }

  const client = (mqtt.default || mqtt).connect(url, {
    username: cfg.username,
    password: cfg.password,
    reconnectPeriod: 5000,
    clientId: cfg.clientId || `sias-gateway-${Math.random().toString(36).slice(2, 8)}`,
  });
  client.on('connect', () => {
    log.info?.(`[sias-gateway] mqtt source: connected to ${url}, subscribing to ${topics.length} topic filter(s)`);
    for (const t of topics) client.subscribe(t, { qos: Number(cfg.qos) || 0 });
  });
  client.on('error', (e) => log.warn?.(`[sias-gateway] mqtt error: ${e?.message || e}`));
  client.on('message', (topic, payload) => {
    let readings = [];
    if (decodeSparkplug && isSparkplugDataTopic(topic)) {
      try {
        readings = sparkplugMetricsToReadings(decodeSparkplug(payload), topic);
      } catch (e) {
        log.warn?.(`[sias-gateway] sparkplug decode failed on ${topic}: ${e?.message || e}`);
      }
    } else {
      readings = mqttMessageToReadings(topic, payload);
    }
    if (readings.length) onReadings(readings);
  });
  return { stop: async () => new Promise((resolve) => client.end(false, {}, resolve)) };
}
