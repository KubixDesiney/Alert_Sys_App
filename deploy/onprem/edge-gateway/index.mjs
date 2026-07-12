// SIAS Edge Gateway — modular, read-only industrial input adapters.
// Converts ESP32 / REST webhook / MQTT / OPC UA / Modbus TCP inputs into the
// canonical SIAS alert payload and forwards them to the worker-runner's
// /ingest endpoint (which owns dedup, storm protection and persistence).
//
// READ-ONLY GUARANTEE: no adapter in this service issues writes toward PLC or
// SCADA systems — the Modbus builder only knows read function codes and the
// OPC UA adapter only creates monitored-item subscriptions.
import http from 'node:http';
import { readFileSync } from 'node:fs';
import { makeLogger } from '../worker-runner/logger.mjs';
import { Forwarder } from './forward.mjs';
import { authenticate, RateLimiter, payloadTooLarge, MAX_PAYLOAD_BYTES } from './security.mjs';
import { parseEsp32 } from './adapters/esp32.mjs';
import { parseWebhook } from './adapters/webhook.mjs';
import { startMqtt } from './adapters/mqtt.mjs';
import { startOpcua } from './adapters/opcua.mjs';
import { startModbus } from './adapters/modbus.mjs';

const log = makeLogger('edge-gateway');

/** Plan gating: which configured adapters may start given licence features. */
export function allowedAdapters(config = {}, features = null) {
  const wanted = Object.entries(config.adapters || {})
    .filter(([, c]) => c && c.enabled)
    .map(([name]) => name);
  if (!features) return wanted; // no licence info -> do not brick ingestion
  const need = { mqtt: 'gateway.mqtt', opcua: 'gateway.opcua', modbus: 'gateway.modbus' };
  return wanted.filter((name) => !need[name] || features.includes(need[name]));
}

export function loadConfig(path = process.env.GATEWAY_CONFIG || './gateway.config.json') {
  return JSON.parse(readFileSync(path, 'utf8'));
}

async function main() {
  const config = loadConfig();
  const ingestUrl = process.env.INGEST_URL || config.ingestUrl || 'http://worker-runner:8787/ingest';
  const sharedSecret = process.env.WORKER_SHARED_SECRET || config.sharedSecret || '';
  const apiKeys = { ...(config.apiKeys || {}) };
  if (process.env.GATEWAY_API_KEYS) {
    for (const pair of process.env.GATEWAY_API_KEYS.split(',')) {
      const [name, key] = pair.split(':').map((s) => (s || '').trim());
      if (name && key) apiKeys[name] = key;
    }
  }

  const forwarder = new Forwarder({ ingestUrl, sharedSecret, log });
  const limiter = new RateLimiter({
    capacity: Number(config.rateLimit?.capacity || 120),
    refillPerSec: Number(config.rateLimit?.refillPerSec || 2),
  });

  // Licence features (best effort): asks the runner which plan is active so
  // Industrial-only protocol adapters stay off on Standard plans.
  let features = null;
  try {
    const r = await fetch(`${new URL(ingestUrl).origin}/license-status`);
    if (r.ok) features = (await r.json()).features || null;
  } catch (_) { /* runner not up yet — HTTP adapters still work */ }

  const stops = [];
  const active = allowedAdapters(config, features);
  const skipped = Object.keys(config.adapters || {})
    .filter((n) => config.adapters[n]?.enabled && !active.includes(n));
  for (const name of skipped) {
    log.warn(`adapter "${name}" is enabled in config but not licensed (Industrial plan required) — skipped`);
  }
  const onAlert = (alert) => forwarder.send(alert);
  for (const name of active) {
    const c = config.adapters[name];
    try {
      if (name === 'mqtt') stops.push(await startMqtt(c, onAlert, log));
      if (name === 'opcua') stops.push(await startOpcua(c, onAlert, log));
      if (name === 'modbus') stops.push(await startModbus(c, onAlert, log));
      if (name === 'mqtt' || name === 'opcua' || name === 'modbus') {
        log.info(`adapter started: ${name}`);
      }
    } catch (err) {
      log.error(`adapter "${name}" failed to start`, { err: String((err && err.message) || err) });
    }
  }

  const server = http.createServer(async (req, res) => {
    const respond = (status, body) => {
      res.writeHead(status, { 'content-type': 'application/json' });
      res.end(JSON.stringify(body));
    };
    try {
      if (req.url === '/health') {
        return respond(200, {
          ok: true,
          adapters: { active, skippedUnlicensed: skipped },
          forward: forwarder.stats,
          queue: forwarder.queue.length,
        });
      }
      if (req.method !== 'POST') return respond(404, { error: 'not found' });

      const caller = authenticate(req.headers, apiKeys);
      if (!caller) return respond(401, { error: 'unauthorized' });
      if (!limiter.allow(caller)) return respond(429, { error: 'rate limited' });

      let raw = '';
      req.on('data', (c) => {
        raw += c;
        if (payloadTooLarge(raw)) { respond(413, { error: `payload > ${MAX_PAYLOAD_BYTES}B` }); req.destroy(); }
      });
      req.on('end', async () => {
        if (res.writableEnded) return;
        let body;
        try { body = JSON.parse(raw || '{}'); } catch (_) { return respond(400, { error: 'invalid JSON' }); }

        let parsed;
        if (req.url === '/esp32') {
          parsed = parseEsp32(body, config.devices || {});
        } else if (req.url.startsWith('/webhook/')) {
          const id = req.url.split('/')[2] || '';
          const wc = (config.webhooks || {})[id];
          if (!wc) return respond(404, { error: `unknown webhook "${id}"` });
          parsed = parseWebhook(body, wc, { source: `webhook:${id}` });
        } else {
          return respond(404, { error: 'not found' });
        }

        if (!parsed.ok) return respond(422, { error: parsed.error });
        if (!parsed.alert) return respond(200, { status: 'below_threshold' });
        await forwarder.send(parsed.alert);
        return respond(202, { status: 'forwarded' });
      });
      return undefined;
    } catch (err) {
      log.error('request failed', { err: String((err && err.message) || err) });
      return respond(500, { error: 'internal' });
    }
  });

  server.listen(Number(process.env.PORT || 8788), () => log.info('listening', { port: 8788 }));

  const shutdown = async () => {
    for (const stop of stops) { try { await stop(); } catch (_) { /* closing */ } }
    server.close(() => process.exit(0));
  };
  process.on('SIGTERM', shutdown);
  process.on('SIGINT', shutdown);
}

// Only run when executed directly (tests import the pure helpers).
if (import.meta.url === `file://${process.argv[1]?.replace(/\\/g, '/')}`) {
  main().catch((err) => {
    log.error('fatal', { err: String((err && err.message) || err) });
    process.exit(1);
  });
}
