// SIA Industrial Telemetry Ingestion Worker
// =========================================
// Turns SIA into a layer that sits ON TOP of an existing SCADA / PLC / historian
// estate instead of competing with it. A site's edge gateway (OPC-UA bridge, MQTT
// broker rule, Modbus poller, or any REST client) POSTs telemetry here; this worker
// normalizes it, applies severity thresholds, and creates a SIA alert in the
// minimal first-write shape that `database.rules.json` already permits — then nudges
// the notification worker for real-time fan-out.
//
// Design notes:
//   * Severity mapping + normalization are PURE and unit-tested (worker_test/ingest.test.js).
//   * Inbound auth = shared secret (constant-time compare). Per-source rate limiting.
//   * Best-effort in-memory dedup collapses telemetry storms into one alert per
//     machine/metric per dedup window (default 60 s).
//   * No control-loop responsibility: this is an alerting/intelligence layer. SCADA
//     keeps real-time process control; SIA adds mobile dispatch, AI assignment, and
//     forecasting on top (see docs/integrations/SCADA_INTEGRATION.md).
//
// Config (wrangler.ingest.toml vars + secrets):
//   FB_DB_URL                  Realtime Database base URL (required)
//   NOTIFY_WORKER_URL          notify worker /notify URL (optional; enables fast push)
//   INGEST_SHARED_SECRET       required inbound secret (x-alertsys-ingest header)
//   INGEST_RATE_PER_MIN        per-source cap, default 240
//   INGEST_DEDUP_WINDOW_MS     dedup window, default 60000

const DEFAULTS = Object.freeze({
  ratePerMin: 240,
  dedupWindowMs: 60000,
  maxBodyBytes: 32 * 1024,
});

// Canonical SIA alert types (mirror lib/services/forecast/forecast_types.dart).
const CANONICAL_TYPES = ['Mechanical', 'Electrical', 'Quality', 'Safety'];

// Heuristic mapping from a telemetry metric/signal name to a canonical alert type.
const METRIC_TYPE_HINTS = [
  [/(temp|vibrat|bearing|pressure|flow|motor|pump|torque|rpm|hydraul)/i, 'Mechanical'],
  [/(volt|current|amp|power|electr|breaker|relay|phase|earth|ground)/i, 'Electrical'],
  [/(defect|reject|tolerance|dimension|scrap|spc|cpk|quality|vision)/i, 'Quality'],
  [/(gas|smoke|fire|emergency|estop|guard|interlock|leak|toxic)/i, 'Safety'],
];

const _rateBucket = new Map(); // source -> [timestamps]
const _recentKeys = new Map(); // dedupeKey -> lastSeenMs

// Drop control / zero-width / bidi characters by code point (no regex literals so
// the source stays pure ASCII), trim, and clamp length.
function sanitizeStr(v, max = 200) {
  if (v == null) return '';
  const s = String(v);
  let out = '';
  for (let i = 0; i < s.length && out.length < max; i++) {
    const c = s.charCodeAt(i);
    const bad =
      c < 0x20 ||
      c === 0x7f ||
      (c >= 0x200b && c <= 0x200f) ||
      (c >= 0x202a && c <= 0x202e) ||
      c === 0xfeff;
    if (!bad) out += s[i];
  }
  return out.trim();
}

function timingSafeEqual(a, b) {
  a = a == null ? '' : String(a);
  b = b == null ? '' : String(b);
  if (a.length !== b.length) return false;
  let out = 0;
  for (let i = 0; i < a.length; i++) out |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return out === 0;
}

function rateLimit(bucket, key, limit, windowMs, now = Date.now()) {
  const arr = (bucket.get(key) || []).filter((t) => now - t < windowMs);
  if (arr.length >= limit) {
    bucket.set(key, arr);
    return { allowed: false, remaining: 0 };
  }
  arr.push(now);
  bucket.set(key, arr);
  return { allowed: true, remaining: Math.max(0, limit - arr.length) };
}

// Map a numeric reading to a severity given thresholds {warn, critical, direction}.
// direction 'high' (default): larger = worse. direction 'low': smaller = worse.
function mapSeverity(value, thresholds = {}) {
  const { warn, critical, direction = 'high' } = thresholds;
  const v = Number(value);
  if (!Number.isFinite(v)) return { severity: 'unknown', isCritical: false };
  const hasWarn = Number.isFinite(Number(warn));
  const hasCrit = Number.isFinite(Number(critical));
  const cmp = (a, b) => (direction === 'low' ? a <= b : a >= b);
  if (hasCrit && cmp(v, Number(critical))) return { severity: 'critical', isCritical: true };
  if (hasWarn && cmp(v, Number(warn))) return { severity: 'warning', isCritical: false };
  return { severity: 'normal', isCritical: false };
}

function typeFromMetric(metric, explicit) {
  if (explicit && CANONICAL_TYPES.includes(explicit)) return explicit;
  const m = sanitizeStr(metric, 60);
  for (const [re, t] of METRIC_TYPE_HINTS) if (re.test(m)) return t;
  return 'Mechanical';
}

function parseTimestamp(ts) {
  if (ts == null || ts === '') return Date.now();
  if (typeof ts === 'number') return ts < 1e12 ? Math.round(ts * 1000) : Math.round(ts);
  const n = Number(ts);
  if (Number.isFinite(n)) return n < 1e12 ? Math.round(n * 1000) : Math.round(n);
  const d = Date.parse(ts);
  return Number.isFinite(d) ? d : Date.now();
}

// Normalize a flexible telemetry payload into a minimal SIA alert-create object,
// or null when the reading is normal (no alert warranted).
function normalizeTelemetry(payload, opts = {}) {
  if (!payload || typeof payload !== 'object') return null;
  const source = sanitizeStr(payload.source || opts.source || 'webhook', 24).toLowerCase();
  const usine = sanitizeStr(payload.factory ?? payload.site ?? payload.usine, 80);
  const machine = sanitizeStr(payload.machine ?? payload.asset ?? payload.tag ?? payload.node, 80);
  const convoyeur = sanitizeStr(payload.line ?? payload.conveyor ?? payload.convoyeur ?? machine, 80);
  const poste = sanitizeStr(payload.station ?? payload.poste ?? payload.point, 80);
  const metric = sanitizeStr(payload.metric ?? payload.signal ?? payload.measurement, 60);
  const unit = sanitizeStr(payload.unit, 16);
  const explicitType = sanitizeStr(payload.type, 24);

  if (!usine || (!convoyeur && !poste && !machine)) return null; // not enough location context

  const thresholds = payload.thresholds || opts.thresholds || {};
  const hasValue = payload.value !== undefined && payload.value !== null && payload.value !== '';
  const sev = hasValue ? mapSeverity(payload.value, thresholds) : null;

  // Decide whether this telemetry should raise an alert at all.
  const forced = !!explicitType || payload.alert === true;
  if (!forced) {
    if (!sev || sev.severity === 'normal' || sev.severity === 'unknown') return null;
  }

  const type = typeFromMetric(metric, explicitType);
  const valuePart = hasValue ? ` ${Number(payload.value)}${unit ? ' ' + unit : ''}` : '';
  const adresse = sanitizeStr(
    payload.message ?? payload.description ??
      `${metric || type}${valuePart} at ${[usine, convoyeur, poste].filter(Boolean).join(' / ')}`,
    240,
  );

  return {
    type,
    usine,
    convoyeur: convoyeur || machine || 'unknown',
    poste: poste || 'unknown',
    adresse,
    timestamp: parseTimestamp(payload.timestamp ?? payload.ts),
    isCritical: !!(sev && sev.isCritical),
    source: `scada:${source}`,
    metric: metric || undefined,
    value: hasValue ? Number(payload.value) : undefined,
    unit: unit || undefined,
    push_sent: false,
    notificationSent: false,
  };
}

function dedupeKey(alert, windowMs = DEFAULTS.dedupWindowMs, now = Date.now()) {
  const bucket = Math.floor(now / windowMs);
  return [alert.source, alert.usine, alert.convoyeur, alert.poste, alert.type, bucket].join('~');
}

function isDuplicate(alert, windowMs = DEFAULTS.dedupWindowMs, now = Date.now()) {
  const key = dedupeKey(alert, windowMs, now);
  const last = _recentKeys.get(key);
  if (last && now - last < windowMs) return true;
  _recentKeys.set(key, now);
  if (_recentKeys.size > 5000) {
    for (const [k, t] of _recentKeys) if (now - t > windowMs) _recentKeys.delete(k);
  }
  return false;
}

function jsonResponse(obj, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { 'content-type': 'application/json', 'cache-control': 'no-store' },
  });
}

async function createAlert(env, alert) {
  // The minimal first-write shape is permitted by database.rules.json without auth.
  const res = await fetch(`${env.FB_DB_URL.replace(/\/+$/, '')}/alerts.json`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(alert),
  });
  if (!res.ok) throw new Error(`RTDB create failed: HTTP ${res.status}`);
  const body = await res.json(); // { name: "<alertId>" }
  return body && body.name;
}

async function triggerNotify(env, alertId) {
  if (!env.NOTIFY_WORKER_URL || !alertId) return;
  try {
    await fetch(env.NOTIFY_WORKER_URL, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ alertId }),
    });
  } catch (_) {
    // cron fallback on the notify worker will still deliver
  }
}

export default {
  async fetch(request, env) {
    if (request.method === 'GET') {
      return jsonResponse({ ok: true, service: 'sia-ingest', accepts: 'POST telemetry JSON' });
    }
    if (request.method !== 'POST') return jsonResponse({ error: 'method_not_allowed' }, 405);

    const secret = env.INGEST_SHARED_SECRET || '';
    if (secret) {
      const got = request.headers.get('x-alertsys-ingest') || '';
      if (!timingSafeEqual(got, secret)) return jsonResponse({ error: 'unauthorized' }, 401);
    }

    const len = Number(request.headers.get('content-length') || 0);
    if (len > DEFAULTS.maxBodyBytes) return jsonResponse({ error: 'payload_too_large' }, 413);

    let payload;
    try {
      payload = await request.json();
    } catch (_) {
      return jsonResponse({ error: 'invalid_json' }, 400);
    }

    const source = sanitizeStr((payload && payload.source) || 'webhook', 24).toLowerCase();
    const limit = Number(env.INGEST_RATE_PER_MIN || DEFAULTS.ratePerMin);
    const rl = rateLimit(_rateBucket, source, limit, 60000);
    if (!rl.allowed) return jsonResponse({ error: 'rate_limited', source }, 429);

    // Accept a single reading or a batch.
    const items = Array.isArray(payload)
      ? payload
      : Array.isArray(payload.readings)
        ? payload.readings
        : [payload];
    const dedupWindow = Number(env.INGEST_DEDUP_WINDOW_MS || DEFAULTS.dedupWindowMs);

    const created = [];
    let skipped = 0;
    for (const item of items.slice(0, 100)) {
      const alert = normalizeTelemetry(item, { source });
      if (!alert) {
        skipped++;
        continue;
      }
      if (isDuplicate(alert, dedupWindow)) {
        skipped++;
        continue;
      }
      if (!env.FB_DB_URL) {
        skipped++;
        continue;
      }
      try {
        const id = await createAlert(env, alert);
        if (id) {
          created.push(id);
          await triggerNotify(env, id);
        }
      } catch (e) {
        return jsonResponse({ error: 'create_failed', detail: String(e.message || e), created }, 502);
      }
    }

    return jsonResponse({ ok: true, created: created.length, skipped, alertIds: created });
  },
};

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
};
