// ESP32 / microcontroller HTTP adapter (READ-ONLY input).
// Boards POST tiny JSON payloads; a device map ties deviceId -> plant position.
//
//   POST /esp32   { "deviceId": "esp32-oven-3", "metric": "temperature",
//                   "value": 92.5, "ts": "2026-07-11T09:00:00Z" }
//
// deviceMap entry:
//   "esp32-oven-3": { factory, line, station, machine, type, severity?,
//                     thresholds?, scale?, offset?, description? }
import { readingToAlert } from '../mapping.mjs';

export function parseEsp32(body, deviceMap = {}, { now } = {}) {
  if (!body || typeof body !== 'object') return { ok: false, error: 'body must be JSON' };
  const deviceId = String(body.deviceId || body.device || '').trim();
  if (!deviceId) return { ok: false, error: 'deviceId is required' };
  const device = deviceMap[deviceId];
  if (!device) return { ok: false, error: `unknown device "${deviceId}"` };

  const metric = String(body.metric || device.metric || 'signal');
  const rule = { key: deviceId, metric, ...device };
  const alert = readingToAlert(
    { key: deviceId, value: body.value, timestamp: body.ts || body.timestamp },
    rule,
    { source: `esp32:${deviceId}`, ...(now ? { now } : {}) },
  );
  // Below-threshold readings are healthy telemetry, not an error.
  return { ok: true, alert, deviceId };
}
