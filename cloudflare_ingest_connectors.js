// SIAS Industrial Connector Engine (module)
// =========================================
// The logic behind cloudflare_ingest_worker.js, split into its own module so the
// pure helpers are independently unit-testable (worker_test/connectors.test.js,
// worker_test/ingest.test.js) and the deployed worker stays a thin router.
//
// Two honest ingestion modes, both flowing through the same
// normalize -> threshold -> dedup -> alert core:
//   * EDGE-PUSH  (OPC-UA / Modbus / air-gapped OT): a gateway near the PLC POSTs
//     to POST /ingest/{connectorId} with that connector's ingest key.
//   * CLOUD-PULL (PI Web API / Ignition / REST / MQTT-over-WSS): the worker reaches
//     OUT on a per-minute cron, polls each connector with its stored credential,
//     applies thresholds, and creates alerts.
//
// Non-secret config lives in RTDB `connectors/{id}`; secrets live in
// `connector_secrets/{id}` (superadmin + this worker only). The worker reads the
// vault and writes live status with a service-account JWT (same pattern as
// cloudflare_ai_worker.js / cloudflare_github_worker.js).

const DEFAULTS = Object.freeze({
  ratePerMin: 240,
  dedupWindowMs: 60000,
  maxBodyBytes: 32 * 1024,
  pollDefaultSec: 60,
  freshWindowMs: 15 * 60 * 1000, // a push connector is "linked" if a packet arrived within this window
  cronLockTtlMs: 50 * 1000,
  verifyTimeoutMs: 9000,
});

// Canonical SIAS alert types (mirror lib/services/forecast/forecast_types.dart).
const CANONICAL_TYPES = ['Mechanical', 'Electrical', 'Quality', 'Safety'];

// Heuristic mapping from a telemetry metric/signal name to a canonical alert type.
const METRIC_TYPE_HINTS = [
  [/(temp|vibrat|bearing|pressure|flow|motor|pump|torque|rpm|hydraul)/i, 'Mechanical'],
  [/(volt|current|amp|power|electr|breaker|relay|phase|earth|ground)/i, 'Electrical'],
  [/(defect|reject|tolerance|dimension|scrap|spc|cpk|quality|vision)/i, 'Quality'],
  [/(gas|smoke|fire|emergency|estop|guard|interlock|leak|toxic)/i, 'Safety'],
];

// Connector kinds. pull = worker reaches out on cron; push = gateway posts in.
const PULL_KINDS = ['rest', 'historian', 'historian_pi', 'historian_ignition', 'http'];
const PUSH_KINDS = ['opcua', 'modbus', 'microcontroller', 'custom', 'webhook'];

const _rateBucket = new Map(); // source -> [timestamps]
const _recentKeys = new Map(); // dedupeKey -> lastSeenMs

// ── Telemetry pure helpers (shared with the original push path) ──────────────
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
  const res = await fetch(`${env.FB_DB_URL.replace(/\/+$/, '')}/alerts.json`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(alert),
  });
  if (!res.ok) throw new Error(`RTDB create failed: HTTP ${res.status}`);
  const body = await res.json();
  return body && body.name;
}

async function triggerNotify(env, alertId) {
  if (!env.NOTIFY_WORKER_URL || !alertId) return;
  try {
    const headers = { 'content-type': 'application/json' };
    // The notify worker runs in WORKER_AUTH_MODE=required; worker-to-worker
    // triggers authenticate with the shared secret. (If it is unset the fast
    // path 401s and the notify cron still delivers within a minute.)
    const secret = env.WORKER_SHARED_SECRET || env.ALERTSYS_WORKER_SHARED_SECRET || '';
    if (secret) headers['x-worker-secret'] = secret;
    await fetch(env.NOTIFY_WORKER_URL, {
      method: 'POST',
      headers,
      body: JSON.stringify({ alertId }),
    });
  } catch (_) {
    // cron fallback on the notify worker will still deliver
  }
}

// ── Firebase service-account auth (vault read + status write) ────────────────
function b64url(s) { return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, ''); }
function b64urlBytes(b) { let s = ''; for (const x of b) s += String.fromCharCode(x); return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, ''); }
function pemToBuf(pem) {
  const body = pem.replace(/-----BEGIN [^-]+-----/, '').replace(/-----END [^-]+-----/, '').replace(/\s+/g, '');
  const bin = atob(body); const buf = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) buf[i] = bin.charCodeAt(i);
  return buf.buffer;
}
let _tokenCache = { at: 0, token: '' };
async function getAccessToken(env) {
  const now = Date.now();
  if (_tokenCache.token && now - _tokenCache.at < 50 * 60 * 1000) return _tokenCache.token;
  const sa = JSON.parse(env.FIREBASE_SERVICE_ACCOUNT);
  const iat = Math.floor(now / 1000);
  const header = b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claim = b64url(JSON.stringify({
    iss: sa.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.database https://www.googleapis.com/auth/userinfo.email',
    aud: 'https://oauth2.googleapis.com/token', iat, exp: iat + 3600,
  }));
  const key = await crypto.subtle.importKey('pkcs8', pemToBuf(sa.private_key),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']);
  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(`${header}.${claim}`));
  const jwt = `${header}.${claim}.${b64urlBytes(new Uint8Array(sig))}`;
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: jwt }),
  });
  const j = await res.json();
  if (!j.access_token) throw new Error('token error');
  _tokenCache = { at: now, token: j.access_token };
  return j.access_token;
}
function _dbBase(env) { return env.FB_DB_URL.endsWith('/') ? env.FB_DB_URL : env.FB_DB_URL + '/'; }
async function rtdbGet(env, token, path) {
  const r = await fetch(`${_dbBase(env)}${path}.json?access_token=${token}`);
  if (!r.ok) return null;
  return r.json();
}
async function rtdbPatch(env, token, path, obj) {
  const r = await fetch(`${_dbBase(env)}${path}.json?access_token=${token}`, {
    method: 'PATCH', headers: { 'content-type': 'application/json' }, body: JSON.stringify(obj),
  });
  return r.ok;
}
async function rtdbPut(env, token, path, obj) {
  const r = await fetch(`${_dbBase(env)}${path}.json?access_token=${token}`, {
    method: 'PUT', headers: { 'content-type': 'application/json' }, body: JSON.stringify(obj),
  });
  return r.ok;
}

// ── Connector pure helpers (unit-tested) ─────────────────────────────────────
function isPullKind(kind) { return PULL_KINDS.includes(String(kind || '').toLowerCase()); }
function isPushKind(kind) { return PUSH_KINDS.includes(String(kind || '').toLowerCase()); }
function isMqttKind(kind) { return String(kind || '').toLowerCase() === 'mqtt'; }

function getByPath(obj, path) {
  if (obj == null) return undefined;
  if (path == null || path === '') return obj;
  const parts = String(path).replace(/\[(\w+)\]/g, '.$1').split('.').filter(Boolean);
  let cur = obj;
  for (const p of parts) {
    if (cur == null || typeof cur !== 'object') return undefined;
    cur = cur[p];
  }
  return cur;
}
function extractValue(json, path) {
  let v = getByPath(json, path);
  if (v && typeof v === 'object') {
    if (v.Value !== undefined) v = v.Value;
    else if (v.value !== undefined) v = v.value;
  }
  return v;
}

function urlHost(u) {
  try { return new URL(String(u || '')).host.toLowerCase(); } catch (_) { return ''; }
}

// Stored connector credentials (bearer/basic/api-key headers, query tokens) may
// only be sent to the connector's OWN configured endpoint host. A connector
// config writer (SuperAdmin, or a compromised SuperAdmin session) can point an
// absolute `tag.url` at any host; without this gate the worker would fetch that
// attacker URL with the connector's secret attached, exfiltrating it. When the
// target host differs from the endpoint host the request still goes out, but
// credential-free.
function credentialsAllowedForUrl(connector = {}, url = '') {
  const endpointHost = urlHost(connector.endpoint);
  const targetHost = urlHost(url);
  return !!endpointHost && endpointHost === targetHost;
}

function connectorAuthHeaders(connector = {}, secret = {}) {
  const a = connector.auth || {};
  const scheme = String(a.scheme || 'none').toLowerCase();
  const headers = {};
  const token = secret.token || '';
  if (scheme === 'bearer' && token) headers['Authorization'] = `Bearer ${token}`;
  else if (scheme === 'basic') {
    const u = secret.username || a.username || '';
    const p = secret.password || '';
    headers['Authorization'] = 'Basic ' + btoa(`${u}:${p}`);
  } else if (scheme === 'header' && token) {
    headers[a.headerName || 'X-API-Key'] = token;
  }
  return headers;
}

function buildRestUrl(connector = {}, tag = {}, secret = {}) {
  let base = String(connector.endpoint || '').replace(/\/+$/, '');
  let url;
  if (tag.url) url = String(tag.url);
  else if (String(connector.kind).toLowerCase() === 'historian_pi' && tag.webId) {
    url = `${base}/streams/${encodeURIComponent(tag.webId)}/value`;
  } else if (tag.path) {
    url = base + String(tag.path).replace('{tag}', encodeURIComponent(tag.tag || ''));
  } else if (tag.tag) {
    url = `${base}${base.includes('?') ? '&' : '?'}tag=${encodeURIComponent(tag.tag)}`;
  } else {
    url = base;
  }
  const a = connector.auth || {};
  if (String(a.scheme).toLowerCase() === 'query' && (secret.token || a.queryValue)
      && credentialsAllowedForUrl(connector, url)) {
    const k = a.queryParam || 'api_key';
    const v = secret.token || a.queryValue;
    url += `${url.includes('?') ? '&' : '?'}${encodeURIComponent(k)}=${encodeURIComponent(v)}`;
  }
  return url;
}

function mergeConnectorDefaults(reading = {}, connector = {}, tag = {}) {
  const out = { ...reading };
  out.source = out.source || connector.kind || 'connector';
  out.factory = out.factory ?? reading.usine ?? reading.site ?? connector.factory;
  out.line = out.line ?? reading.conveyor ?? reading.convoyeur ?? tag.line ?? connector.line;
  out.station = out.station ?? reading.poste ?? reading.point ?? tag.station ?? connector.station;
  out.machine = out.machine ?? reading.asset ?? reading.tag ?? tag.machine ?? tag.tag;
  out.metric = out.metric ?? reading.signal ?? tag.metric ?? tag.tag;
  out.unit = out.unit ?? tag.unit;
  if (out.type == null && tag.type) out.type = tag.type;
  if (out.thresholds == null && tag.thresholds) out.thresholds = tag.thresholds;
  return out;
}

function pollDue(connector, now = Date.now()) {
  if (!connector || connector.enabled === false) return false;
  if (!isPullKind(connector.kind)) return false;
  const interval = Math.max(15, Number(connector.pollIntervalSec || DEFAULTS.pollDefaultSec)) * 1000;
  const last = Number((connector.runtime && connector.runtime.lastPollAt) || 0);
  return now - last >= interval;
}

function verifyPushStatus(connector, now = Date.now(), freshWindowMs = DEFAULTS.freshWindowMs) {
  const last = Number((connector && connector.runtime && connector.runtime.lastIngestAt) || 0);
  if (last && now - last <= freshWindowMs) {
    return { ok: true, status: 'linked', message: 'Live data is flowing from your gateway.' };
  }
  return {
    ok: false,
    status: 'waiting',
    message: 'Endpoint armed. Point your gateway at the ingest URL with the key below — verify flips to LINKED on the first packet.',
  };
}

// MQTT 3.1.1 CONNECT/CONNACK (pure) — for the MQTT-over-WebSocket verify handshake.
function mqttString(s) {
  const enc = new TextEncoder().encode(String(s == null ? '' : s));
  const out = new Uint8Array(enc.length + 2);
  out[0] = (enc.length >> 8) & 0xff;
  out[1] = enc.length & 0xff;
  out.set(enc, 2);
  return out;
}
function mqttRemainingLength(n) {
  const bytes = [];
  do {
    let b = n % 128;
    n = Math.floor(n / 128);
    if (n > 0) b |= 0x80;
    bytes.push(b);
  } while (n > 0);
  return bytes;
}
function buildMqttConnect(clientId = 'sia-verify', username = '', password = '', keepAlive = 30) {
  const proto = mqttString('MQTT');
  const level = 0x04; // 3.1.1
  let flags = 0x02; // clean session
  const hasUser = !!username;
  const hasPass = !!password;
  if (hasUser) flags |= 0x80;
  if (hasPass) flags |= 0x40;
  const payloadParts = [mqttString(clientId)];
  if (hasUser) payloadParts.push(mqttString(username));
  if (hasPass) payloadParts.push(mqttString(password));
  const varHeader = [...proto, level, flags, (keepAlive >> 8) & 0xff, keepAlive & 0xff];
  let payloadLen = 0;
  for (const p of payloadParts) payloadLen += p.length;
  const remaining = varHeader.length + payloadLen;
  const rl = mqttRemainingLength(remaining);
  const total = 1 + rl.length + remaining;
  const out = new Uint8Array(total);
  let o = 0;
  out[o++] = 0x10; // CONNECT
  for (const b of rl) out[o++] = b;
  for (const b of varHeader) out[o++] = b;
  for (const p of payloadParts) { out.set(p, o); o += p.length; }
  return out;
}
function parseConnack(bytes) {
  if (!bytes || bytes.length < 4) return { ok: false, code: -1, reason: 'short' };
  if ((bytes[0] & 0xf0) !== 0x20) return { ok: false, code: -1, reason: 'not_connack' };
  const code = bytes[3];
  const reasons = {
    0: 'accepted', 1: 'unacceptable protocol version', 2: 'identifier rejected',
    3: 'server unavailable', 4: 'bad username or password', 5: 'not authorized',
  };
  return { ok: code === 0, code, reason: reasons[code] || `refused (${code})` };
}

// ── Connector runtime (impure) ───────────────────────────────────────────────
async function loadConnectors(env, token) {
  const map = await rtdbGet(env, token, 'connectors');
  if (!map || typeof map !== 'object') return [];
  return Object.entries(map).map(([id, c]) => ({ id, ...(c || {}) }));
}
async function loadConnectorSecret(env, token, id) {
  const s = await rtdbGet(env, token, `connector_secrets/${id}`);
  return s && typeof s === 'object' ? s : {};
}
async function writeConnectorRuntime(env, token, id, patch) {
  return rtdbPatch(env, token, `connectors/${id}/runtime`, { ...patch, updatedAt: new Date().toISOString() });
}

async function fetchTagValue(connector, tag, secret, timeoutMs = DEFAULTS.verifyTimeoutMs) {
  const url = buildRestUrl(connector, tag, secret);
  if (!/^https?:\/\//i.test(url)) return { ok: false, status: 0, detail: 'endpoint must be an absolute http(s) URL' };
  // Withhold stored credentials unless the target host is the connector's own
  // endpoint host (see credentialsAllowedForUrl).
  const headers = { accept: 'application/json' };
  if (credentialsAllowedForUrl(connector, url)) {
    Object.assign(headers, connectorAuthHeaders(connector, secret));
  }
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    const res = await fetch(url, { headers, signal: ctrl.signal });
    const text = await res.text();
    if (!res.ok) return { ok: false, status: res.status, detail: text.slice(0, 200) };
    let json;
    try { json = JSON.parse(text); } catch (_) { json = text; }
    const valuePath = tag.valuePath
      || (String(connector.kind).toLowerCase() === 'historian_pi' ? 'Value' : 'value');
    let value = extractValue(json, valuePath);
    if (value === undefined && typeof json !== 'object') value = json;
    return { ok: true, status: res.status, value, raw: json };
  } catch (e) {
    return { ok: false, status: 0, detail: String((e && e.message) || e) };
  } finally {
    clearTimeout(timer);
  }
}

async function verifyMqtt(connector, secret, timeoutMs = DEFAULTS.verifyTimeoutMs) {
  let url = String(connector.endpoint || '').trim();
  if (!url) return { ok: false, status: 'error', message: 'No broker URL configured.' };
  if (/^mqtts?:\/\//i.test(url)) url = url.replace(/^mqtt(s)?:\/\//i, (_m, s) => (s ? 'wss://' : 'ws://'));
  if (!/^wss?:\/\//i.test(url)) return { ok: false, status: 'error', message: 'Use an MQTT-over-WebSocket URL (wss://host:port/mqtt).' };
  try {
    const resp = await fetch(url, { headers: { Upgrade: 'websocket', 'Sec-WebSocket-Protocol': 'mqtt' } });
    const ws = resp.webSocket;
    if (!ws) return { ok: false, status: 'error', message: `Broker did not accept a WebSocket upgrade (HTTP ${resp.status}).` };
    ws.accept();
    return await new Promise((resolve) => {
      const done = (r) => { try { ws.close(); } catch (_) {} resolve(r); };
      const t = setTimeout(() => done({ ok: false, status: 'error', message: 'Broker handshake timed out.' }), timeoutMs);
      ws.addEventListener('message', (ev) => {
        clearTimeout(t);
        const data = ev.data;
        const bytes = data instanceof ArrayBuffer ? new Uint8Array(data)
          : (typeof data === 'string' ? new TextEncoder().encode(data) : new Uint8Array(data));
        const ack = parseConnack(bytes);
        done(ack.ok
          ? { ok: true, status: 'linked', message: 'Broker accepted the MQTT connection (CONNACK 0).' }
          : { ok: false, status: 'error', message: `Broker refused the MQTT connection: ${ack.reason}.` });
      });
      ws.addEventListener('close', () => { clearTimeout(t); done({ ok: false, status: 'error', message: 'Broker closed the connection during handshake.' }); });
      ws.addEventListener('error', () => { clearTimeout(t); done({ ok: false, status: 'error', message: 'WebSocket error during MQTT handshake.' }); });
      const clientId = (connector.mqtt && connector.mqtt.clientId) || `sia-verify-${Math.random().toString(16).slice(2, 8)}`;
      ws.send(buildMqttConnect(clientId, secret.username || '', secret.token || secret.password || ''));
    });
  } catch (e) {
    return { ok: false, status: 'error', message: `Could not reach the broker: ${String((e && e.message) || e)}.` };
  }
}

async function verifyConnector(env, token, connector) {
  const id = connector.id;
  const secret = await loadConnectorSecret(env, token, id);
  const now = Date.now();
  let result;

  if (isMqttKind(connector.kind)) {
    result = await verifyMqtt(connector, secret);
  } else if (isPullKind(connector.kind)) {
    const tag = (Array.isArray(connector.tags) && connector.tags[0]) || {};
    const r = await fetchTagValue(connector, tag, secret);
    if (r.ok) {
      const num = Number(r.value);
      const shown = Number.isFinite(num) ? num : (r.value === undefined ? '(no value at path)' : String(r.value));
      result = {
        ok: true, status: 'linked',
        message: `Linked. Live read of ${tag.metric || tag.tag || 'endpoint'} = ${shown}${tag.unit ? ' ' + tag.unit : ''}.`,
        sample: Number.isFinite(num) ? num : null,
      };
    } else {
      result = {
        ok: false, status: 'error',
        message: r.status ? `Endpoint returned HTTP ${r.status}. ${r.detail || ''}`.trim() : `Could not reach endpoint: ${r.detail || 'network error'}.`,
      };
    }
  } else {
    result = verifyPushStatus(connector, now);
  }

  await writeConnectorRuntime(env, token, id, {
    status: result.status,
    lastVerifyAt: new Date(now).toISOString(),
    lastVerifyOk: !!result.ok,
    lastVerifyMessage: result.message,
    ...(result.sample != null ? { lastValue: result.sample } : {}),
  });
  return result;
}

async function pollConnector(env, token, connector) {
  const id = connector.id;
  const secret = await loadConnectorSecret(env, token, id);
  const tags = Array.isArray(connector.tags) ? connector.tags : [];
  const now = Date.now();
  let created = 0, readOk = 0, errors = 0, lastValue = null, lastError = '';

  for (const tag of tags.slice(0, 50)) {
    const r = await fetchTagValue(connector, tag, secret);
    if (!r.ok) { errors++; lastError = r.detail || `HTTP ${r.status}`; continue; }
    readOk++;
    const num = Number(r.value);
    if (Number.isFinite(num)) lastValue = num;
    const reading = mergeConnectorDefaults({ value: r.value, timestamp: now }, connector, tag);
    const alert = normalizeTelemetry(reading, { source: connector.kind });
    if (!alert) continue;
    if (isDuplicate(alert, Number(env.INGEST_DEDUP_WINDOW_MS || DEFAULTS.dedupWindowMs))) continue;
    try {
      const aid = await createAlert(env, alert);
      if (aid) { created++; await triggerNotify(env, aid); }
    } catch (e) { errors++; lastError = String((e && e.message) || e); }
  }

  await writeConnectorRuntime(env, token, id, {
    lastPollAt: now,
    ...(readOk > 0 ? { lastIngestAt: now } : {}),
    eventsIngested: Number((connector.runtime && connector.runtime.eventsIngested) || 0) + created,
    status: errors && !readOk ? 'error' : (readOk ? 'linked' : (connector.runtime && connector.runtime.status) || 'idle'),
    ...(lastValue != null ? { lastValue } : {}),
    ...(lastError ? { lastError } : {}),
  });
  return { created, readOk, errors };
}

// ── HTTP handlers (called by the thin worker router) ─────────────────────────
function ingestStatus(env) {
  return jsonResponse({
    ok: true, service: 'sia-ingest',
    accepts: 'POST telemetry JSON (/, /ingest/{id}) · POST /verify · POST /control',
    connectorsConfigured: !!(env.FIREBASE_SERVICE_ACCOUNT && env.FB_DB_URL),
  });
}

function adminAuthorized(env, request) {
  const want = env.WORKER_SHARED_SECRET || '';
  // Fail closed: /verify and /control drive live connector actions with the
  // worker service account. If no secret is configured the routes are denied
  // (never "open in dev"), so a misconfigured deploy cannot be driven anonymously.
  if (!want) return false;
  const got = (request.headers.get('authorization') || '').replace(/^Bearer\s+/i, '');
  return timingSafeEqual(got, want);
}

async function handleConnectorIngest(env, request, connectorId) {
  if (!env.FIREBASE_SERVICE_ACCOUNT || !env.FB_DB_URL) return jsonResponse({ error: 'ingest_not_configured' }, 503);
  let token;
  try { token = await getAccessToken(env); } catch (_) { return jsonResponse({ error: 'auth_failed' }, 502); }

  const cfg = await rtdbGet(env, token, `connectors/${connectorId}`);
  if (!cfg) return jsonResponse({ error: 'unknown_connector' }, 404);
  const connector = { id: connectorId, ...cfg };
  if (connector.enabled === false) return jsonResponse({ error: 'connector_disabled' }, 403);

  const secret = await loadConnectorSecret(env, token, connectorId);
  const provided = request.headers.get('x-alertsys-ingest') || '';
  const keyOk = secret.ingestKey && timingSafeEqual(provided, secret.ingestKey);
  const globalOk = env.INGEST_SHARED_SECRET && timingSafeEqual(provided, env.INGEST_SHARED_SECRET);
  if (!keyOk && !globalOk) return jsonResponse({ error: 'unauthorized' }, 401);

  const len = Number(request.headers.get('content-length') || 0);
  if (len > DEFAULTS.maxBodyBytes) return jsonResponse({ error: 'payload_too_large' }, 413);

  const rl = rateLimit(_rateBucket, `c:${connectorId}`, Number(env.INGEST_RATE_PER_MIN || DEFAULTS.ratePerMin), 60000);
  if (!rl.allowed) return jsonResponse({ error: 'rate_limited' }, 429);

  let payload;
  try { payload = await request.json(); } catch (_) { return jsonResponse({ error: 'invalid_json' }, 400); }
  const items = Array.isArray(payload) ? payload
    : Array.isArray(payload.readings) ? payload.readings : [payload];
  const dedupWindow = Number(env.INGEST_DEDUP_WINDOW_MS || DEFAULTS.dedupWindowMs);

  const created = [];
  let accepted = 0, skipped = 0;
  for (const item of items.slice(0, 100)) {
    accepted++;
    const tag = (item && item.tag && Array.isArray(connector.tags))
      ? connector.tags.find((t) => t.tag === item.tag) || {}
      : {};
    const reading = mergeConnectorDefaults(item || {}, connector, tag);
    const alert = normalizeTelemetry(reading, { source: connector.kind });
    if (!alert) { skipped++; continue; }
    if (isDuplicate(alert, dedupWindow)) { skipped++; continue; }
    try {
      const aid = await createAlert(env, alert);
      if (aid) { created.push(aid); await triggerNotify(env, aid); }
    } catch (e) {
      return jsonResponse({ error: 'create_failed', detail: String((e && e.message) || e), created }, 502);
    }
  }

  const now = Date.now();
  await writeConnectorRuntime(env, token, connectorId, {
    lastIngestAt: now,
    status: 'linked',
    eventsIngested: Number((connector.runtime && connector.runtime.eventsIngested) || 0) + accepted,
  });
  return jsonResponse({ ok: true, created: created.length, skipped, alertIds: created });
}

async function handleVerify(env, request) {
  if (!adminAuthorized(env, request)) return jsonResponse({ error: 'unauthorized' }, 401);
  if (!env.FIREBASE_SERVICE_ACCOUNT || !env.FB_DB_URL) return jsonResponse({ error: 'verify_not_configured' }, 503);
  let body;
  try { body = await request.json(); } catch (_) { return jsonResponse({ error: 'invalid_json' }, 400); }
  const id = sanitizeStr(body && body.connectorId, 80);
  if (!id) return jsonResponse({ error: 'missing_connectorId' }, 400);
  let token;
  try { token = await getAccessToken(env); } catch (_) { return jsonResponse({ error: 'auth_failed' }, 502); }
  const cfg = await rtdbGet(env, token, `connectors/${id}`);
  if (!cfg) return jsonResponse({ error: 'unknown_connector' }, 404);
  const result = await verifyConnector(env, token, { id, ...cfg });
  return jsonResponse({ ok: result.ok, status: result.status, message: result.message, sample: result.sample ?? null });
}

async function handleControl(env, request) {
  if (!adminAuthorized(env, request)) return jsonResponse({ error: 'unauthorized' }, 401);
  if (!env.FIREBASE_SERVICE_ACCOUNT || !env.FB_DB_URL) return jsonResponse({ error: 'control_not_configured' }, 503);
  let body;
  try { body = await request.json(); } catch (_) { return jsonResponse({ error: 'invalid_json' }, 400); }
  const action = sanitizeStr(body && body.action, 24);
  const id = sanitizeStr(body && body.connectorId, 80);
  let token;
  try { token = await getAccessToken(env); } catch (_) { return jsonResponse({ error: 'auth_failed' }, 502); }
  if (action === 'poll' && id) {
    const cfg = await rtdbGet(env, token, `connectors/${id}`);
    if (!cfg) return jsonResponse({ error: 'unknown_connector' }, 404);
    const r = await pollConnector(env, token, { id, ...cfg });
    return jsonResponse({ ok: true, ...r });
  }
  return jsonResponse({ error: 'unknown_action' }, 400);
}

// Legacy / generic global push (kept identical to the original worker behavior).
async function handleGlobalPush(env, request) {
  const secret = env.INGEST_SHARED_SECRET || '';
  if (secret) {
    const got = request.headers.get('x-alertsys-ingest') || '';
    if (!timingSafeEqual(got, secret)) return jsonResponse({ error: 'unauthorized' }, 401);
  }
  const len = Number(request.headers.get('content-length') || 0);
  if (len > DEFAULTS.maxBodyBytes) return jsonResponse({ error: 'payload_too_large' }, 413);

  let payload;
  try { payload = await request.json(); } catch (_) { return jsonResponse({ error: 'invalid_json' }, 400); }

  const source = sanitizeStr((payload && payload.source) || 'webhook', 24).toLowerCase();
  const limit = Number(env.INGEST_RATE_PER_MIN || DEFAULTS.ratePerMin);
  const rl = rateLimit(_rateBucket, source, limit, 60000);
  if (!rl.allowed) return jsonResponse({ error: 'rate_limited', source }, 429);

  const items = Array.isArray(payload) ? payload
    : Array.isArray(payload.readings) ? payload.readings : [payload];
  const dedupWindow = Number(env.INGEST_DEDUP_WINDOW_MS || DEFAULTS.dedupWindowMs);

  const created = [];
  let skipped = 0;
  for (const item of items.slice(0, 100)) {
    const alert = normalizeTelemetry(item, { source });
    if (!alert) { skipped++; continue; }
    if (isDuplicate(alert, dedupWindow)) { skipped++; continue; }
    if (!env.FB_DB_URL) { skipped++; continue; }
    try {
      const id = await createAlert(env, alert);
      if (id) { created.push(id); await triggerNotify(env, id); }
    } catch (e) {
      return jsonResponse({ error: 'create_failed', detail: String(e.message || e), created }, 502);
    }
  }
  return jsonResponse({ ok: true, created: created.length, skipped, alertIds: created });
}

// Cron: poll all due pull connectors + refresh MQTT link status.
async function runConnectorCron(env) {
  if (!env.FIREBASE_SERVICE_ACCOUNT || !env.FB_DB_URL) return { polled: 0, created: 0 };
  let token;
  try { token = await getAccessToken(env); } catch (_) { return { polled: 0, created: 0, error: 'auth' }; }

  const lock = await rtdbGet(env, token, 'cron_lock/ingest');
  const now = Date.now();
  if (lock && lock.ts && now - Number(lock.ts) < DEFAULTS.cronLockTtlMs) return { polled: 0, created: 0, skipped: 'locked' };
  await rtdbPut(env, token, 'cron_lock/ingest', { ts: now, by: 'cron' });

  let polled = 0, created = 0;
  try {
    const connectors = await loadConnectors(env, token);
    for (const c of connectors) {
      if (pollDue(c, now)) {
        const r = await pollConnector(env, token, c);
        polled++; created += r.created;
      } else if (isMqttKind(c.kind) && c.enabled !== false) {
        const last = Number((c.runtime && c.runtime.lastVerifyAt && Date.parse(c.runtime.lastVerifyAt)) || 0);
        if (now - last > 5 * 60 * 1000) { try { await verifyConnector(env, token, c); } catch (_) {} }
      }
    }
  } finally {
    try { await fetch(`${_dbBase(env)}cron_lock/ingest.json?access_token=${token}`, { method: 'DELETE' }); } catch (_) {}
  }
  return { polled, created };
}

export {
  DEFAULTS,
  CANONICAL_TYPES,
  PULL_KINDS,
  PUSH_KINDS,
  // telemetry pure helpers
  sanitizeStr,
  timingSafeEqual,
  rateLimit,
  mapSeverity,
  typeFromMetric,
  parseTimestamp,
  normalizeTelemetry,
  dedupeKey,
  isDuplicate,
  jsonResponse,
  // connector pure helpers
  isPullKind,
  isPushKind,
  isMqttKind,
  getByPath,
  extractValue,
  connectorAuthHeaders,
  credentialsAllowedForUrl,
  buildRestUrl,
  mergeConnectorDefaults,
  pollDue,
  verifyPushStatus,
  buildMqttConnect,
  parseConnack,
  mqttRemainingLength,
  // runtime + handlers
  verifyConnector,
  pollConnector,
  runConnectorCron,
  ingestStatus,
  adminAuthorized,
  handleConnectorIngest,
  handleVerify,
  handleControl,
  handleGlobalPush,
};
