// SIA Industrial Telemetry Ingestion + Connector Engine (thin router)
// ===================================================================
// Deployed Cloudflare worker. All logic lives in ./cloudflare_ingest_connectors.js
// (split out so the pure helpers are independently unit-testable and this file
// stays a small, reviewable router). wrangler bundles the import at deploy.
//
// Routes:
//   GET  /                    service status
//   GET  /config              service status
//   POST /verify              app "Verify link test" (Bearer WORKER_SHARED_SECRET)
//   POST /control             app actions e.g. { action:'poll', connectorId } (Bearer)
//   POST /ingest/{id}         per-connector edge-push (header x-alertsys-ingest = key)
//   POST /                    legacy / generic global push (header x-alertsys-ingest)
// Cron (every minute): poll all due cloud-pull connectors; refresh MQTT link status.
//
// Config (wrangler.ingest.toml vars + secrets):
//   FB_DB_URL                  Realtime Database base URL (required)
//   FIREBASE_SERVICE_ACCOUNT   service-account JSON (required for verify/pull/vault)
//   WORKER_SHARED_SECRET       bearer the app sends on /verify + /control
//   NOTIFY_WORKER_URL          notify worker /notify URL (optional; enables fast push)
//   INGEST_SHARED_SECRET       optional global inbound secret (x-alertsys-ingest header)
//   INGEST_RATE_PER_MIN        per-source cap, default 240
//   INGEST_DEDUP_WINDOW_MS     dedup window, default 60000

import {
  sanitizeStr,
  jsonResponse,
  ingestStatus,
  handleVerify,
  handleControl,
  handleConnectorIngest,
  handleGlobalPush,
  runConnectorCron,
} from './cloudflare_ingest_connectors.js';

export default {
  async scheduled(event, env, ctx) {
    ctx.waitUntil(runConnectorCron(env).catch(() => {}));
  },

  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname.replace(/\/+$/, '') || '/';

    if (request.method === 'GET' && (path === '/' || path === '/config')) {
      return ingestStatus(env);
    }
    if (request.method === 'POST' && path === '/verify') return handleVerify(env, request);
    if (request.method === 'POST' && path === '/control') return handleControl(env, request);
    if (request.method === 'POST' && path.startsWith('/ingest/')) {
      const id = sanitizeStr(decodeURIComponent(path.slice('/ingest/'.length)), 80);
      if (!id) return jsonResponse({ error: 'missing_connector' }, 400);
      return handleConnectorIngest(env, request, id);
    }
    if (request.method !== 'POST') return jsonResponse({ error: 'method_not_allowed' }, 405);

    // Legacy / generic global push (POST /).
    return handleGlobalPush(env, request);
  },
};

// Re-export pure helpers so existing imports (worker_test/ingest.test.js) keep working.
export {
  timingSafeEqual,
  rateLimit,
  mapSeverity,
  typeFromMetric,
  parseTimestamp,
  normalizeTelemetry,
  dedupeKey,
  isDuplicate,
  CANONICAL_TYPES,
} from './cloudflare_ingest_connectors.js';
