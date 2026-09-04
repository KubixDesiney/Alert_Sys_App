// Cloudflare Worker - SIAS - Smart Industrial Alert System Notifications Worker
// Cron schedule: "* * * * *" (every minute)
// Responsibilities: new-alert push fan-out, queued notification fan-out, /notify.

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, x-worker-secret, X-SIAS-Worker-Secret',
};

let _fbToken = null;
let _fbTokenExpMs = 0;
let _fcmToken = null;
let _fcmTokenExpMs = 0;
const PRIVATE_KEY_BEGIN = `-----BEGIN ${'PRIVATE KEY'}-----`;
const PRIVATE_KEY_END = `-----END ${'PRIVATE KEY'}-----`;

const MAX_ALERTS_TO_PUSH = 1;
const MAX_FANOUT = 5;
const MAX_CRON_FANOUT = 5;
// Ceiling on the en_cours slice used to work out which supervisors are busy.
// Far above any real concurrent-claim count: exceeding it can only risk
// buzzing a supervisor who is in fact busy, never silencing an alert.
const MAX_EN_COURS_SCAN = 5000;
// Ceiling on the full alert-table read in this worker's loadCoreData. $key
// order is creation order (alert ids are Firebase push keys), so this keeps
// the most recent N and cannot be dodged by omitting a field.
const CORE_ALERTS_DEFAULT_CAP = 20000;
const PUSH_LOCK_TTL_MS = 2 * 60 * 1000;
const NOTIFICATION_LOCK_TTL_MS = 2 * 60 * 1000;
// A new-alert buzz is time-critical: past this age the alert has either been
// claimed, escalated, or gone stale, so the queued row is closed instead of
// buzzing someone about old news.
const NEW_ALERT_MAX_AGE_MS = 15 * 60 * 1000;
// Any queued notification we could not deliver within a day is dead weight;
// closing it keeps the /notifications backlog bounded so crons stay fast.
const QUEUED_NOTIFICATION_MAX_AGE_MS = 24 * 60 * 60 * 1000;
// Terminal skips are cheap PATCHes but still I/O; cap them per run so a large
// stale backlog cannot starve actual sends inside one invocation.
const MAX_TERMINAL_SKIPS_PER_RUN = 25;
const RATE_LIMIT_WINDOW_MS = 60 * 1000;
const RATE_LIMIT_MAX = 60;

const _rateBuckets = new Map();

function _safeTrimString(value) {
  return typeof value === 'string' ? value.trim() : '';
}

function _json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

function _fbBaseUrl(env) {
  return `${String(env?.FB_DB_URL || '').trim().replace(/\/+$/, '')}/`;
}

function _fbUrl(env, path) {
  return `${_fbBaseUrl(env)}${String(path || '').replace(/^\/+/, '')}`;
}

// ── Worker auth: Firebase ID-token verification ─────────────────────────────
// Mirrors cloudflare_ai_worker.js. Accepts the caller's Firebase ID token
// (Authorization: Bearer …) or the legacy shared secret (x-worker-secret)
// while the installed client fleet migrates. WORKER_AUTH_MODE: 'off' | 'log'
// | 'required'. `/config` stays public for uptime/status probes.
const _FIREBASE_JWKS_URL =
  'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com';
let _jwksKeys = null;
let _jwksExpMs = 0;

function _b64urlDecodeToBytes(s) {
  const pad = s.length % 4 === 0 ? '' : '='.repeat(4 - (s.length % 4));
  const bin = atob(String(s).replace(/-/g, '+').replace(/_/g, '/') + pad);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return bytes;
}

function _fbProjectId(env) {
  try {
    const sa = parseJsonSecret(env.FIREBASE_SERVICE_ACCOUNT, 'FIREBASE_SERVICE_ACCOUNT');
    if (sa.project_id) return String(sa.project_id);
  } catch (_) {}
  const m = String(env.FB_DB_URL || '').match(/https:\/\/([^.]+?)(?:-default-rtdb)?\./);
  return m ? m[1] : '';
}

async function _fetchFirebaseJwks() {
  const now = Date.now();
  if (_jwksKeys && now < _jwksExpMs) return _jwksKeys;
  const res = await fetch(_FIREBASE_JWKS_URL);
  if (!res.ok) throw new Error('jwks fetch failed: ' + res.status);
  const body = await res.json();
  _jwksKeys = Array.isArray(body?.keys) ? body.keys : [];
  const cc = res.headers.get('Cache-Control') || '';
  const maxAge = Number((cc.match(/max-age=(\d+)/) || [])[1] || 3600);
  _jwksExpMs = now + Math.min(maxAge, 6 * 3600) * 1000;
  return _jwksKeys;
}

function _validateIdTokenClaims(payload, projectId, nowSec) {
  if (!payload || typeof payload !== 'object') return { ok: false, error: 'bad_payload' };
  if (!projectId) return { ok: false, error: 'no_project' };
  if (Number(payload.exp || 0) <= nowSec) return { ok: false, error: 'expired' };
  if (Number(payload.iat || 0) > nowSec + 300) return { ok: false, error: 'issued_in_future' };
  if (payload.aud !== projectId) return { ok: false, error: 'bad_aud' };
  if (payload.iss !== `https://securetoken.google.com/${projectId}`) {
    return { ok: false, error: 'bad_iss' };
  }
  const uid = String(payload.sub || payload.user_id || '');
  if (!uid) return { ok: false, error: 'no_uid' };
  return { ok: true, uid };
}

async function _verifyFirebaseIdToken(env, idToken) {
  try {
    const parts = String(idToken || '').split('.');
    if (parts.length !== 3) return { ok: false, error: 'malformed' };
    const header = JSON.parse(new TextDecoder().decode(_b64urlDecodeToBytes(parts[0])));
    if (header.alg !== 'RS256') return { ok: false, error: 'bad_alg' };
    const payload = JSON.parse(new TextDecoder().decode(_b64urlDecodeToBytes(parts[1])));
    const claims = _validateIdTokenClaims(payload, _fbProjectId(env), Math.floor(Date.now() / 1000));
    if (!claims.ok) return claims;

    const jwks = await _fetchFirebaseJwks();
    const jwk = jwks.find((k) => k.kid === header.kid);
    if (!jwk) return { ok: false, error: 'unknown_kid' };
    const key = await crypto.subtle.importKey(
      'jwk',
      jwk,
      { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
      false,
      ['verify'],
    );
    const valid = await crypto.subtle.verify(
      'RSASSA-PKCS1-v1_5',
      key,
      _b64urlDecodeToBytes(parts[2]),
      new TextEncoder().encode(`${parts[0]}.${parts[1]}`),
    );
    return valid ? { ok: true, uid: claims.uid } : { ok: false, error: 'bad_signature' };
  } catch (e) {
    return { ok: false, error: 'verify_error: ' + e.message };
  }
}

function _constantTimeEquals(a, b) {
  const sa = String(a || '');
  const sb = String(b || '');
  if (sa.length !== sb.length || sa.length === 0) return false;
  let diff = 0;
  for (let i = 0; i < sa.length; i++) diff |= sa.charCodeAt(i) ^ sb.charCodeAt(i);
  return diff === 0;
}

async function _workerAuthCheck(request, env) {
  const rawMode = String(env.WORKER_AUTH_MODE ?? '').trim().toLowerCase();
  // Default to the strict mode: an unset or blank var must never mean "no auth".
  const mode = rawMode === '' ? 'required' : rawMode;
  // An unrecognised value (typo, stray whitespace) fails closed rather than
  // falling through to the permissive branches below.
  if (mode !== 'off' && mode !== 'log' && mode !== 'required') {
    return { ok: false, mode, error: 'invalid_worker_auth_mode' };
  }
  if (mode === 'off') return { ok: true, mode, method: 'none' };

  const secret = String(env.WORKER_SHARED_SECRET || env.SIA_WORKER_SHARED_SECRET || '').trim();
  const presented = String(request.headers.get('x-worker-secret') || '').trim();
  if (secret && _constantTimeEquals(presented, secret)) {
    return { ok: true, mode, method: 'secret' };
  }

  const authHeader = String(request.headers.get('Authorization') || '');
  const idToken = authHeader.startsWith('Bearer ')
    ? authHeader.slice(7).trim()
    : String(request.headers.get('x-firebase-token') || '').trim();
  if (idToken) {
    const verified = await _verifyFirebaseIdToken(env, idToken);
    if (verified.ok) return { ok: true, mode, method: 'id_token', uid: verified.uid };
    if (mode === 'required') return { ok: false, mode, error: verified.error };
    return { ok: true, mode, method: 'invalid_token_logged', error: verified.error };
  }

  return mode === 'required'
    ? { ok: false, mode, error: 'no_credentials' }
    : { ok: true, mode, method: 'unauthenticated_logged' };
}

function _securityGuard(request, endpoint = 'default') {
  const now = Date.now();
  const ip =
    request.headers.get('cf-connecting-ip') ||
    request.headers.get('x-forwarded-for') ||
    'local';
  const key = `${endpoint}:${ip}`;
  const bucket = _rateBuckets.get(key) || { start: now, count: 0 };
  if (now - bucket.start > RATE_LIMIT_WINDOW_MS) {
    bucket.start = now;
    bucket.count = 0;
  }
  bucket.count++;
  _rateBuckets.set(key, bucket);
  if (bucket.count > RATE_LIMIT_MAX) {
    return {
      ok: false,
      response: _json({ ok: false, error: 'rate_limited' }, 429),
    };
  }
  return { ok: true };
}

function base64UrlEncode(input) {
  const bytes =
    typeof input === 'string'
      ? new TextEncoder().encode(input)
      : input instanceof Uint8Array
        ? input
        : new Uint8Array(input);
  let binary = '';
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
}

function parseJsonSecret(raw, label) {
  if (raw && typeof raw === 'object') return raw;
  let text = _safeTrimString(raw);
  if (!text) throw new Error(`${label} is empty`);

  const firstBrace = text.indexOf('{');
  const lastBrace = text.lastIndexOf('}');
  if (firstBrace >= 0 && lastBrace > firstBrace) {
    text = text.slice(firstBrace, lastBrace + 1);
  }

  try {
    return JSON.parse(text);
  } catch (firstError) {
    try {
      const unwrapped = JSON.parse(text);
      if (typeof unwrapped === 'string') {
        return JSON.parse(unwrapped);
      }
      return unwrapped;
    } catch (_) {
      throw new Error(`${label} parse failed: ${firstError.message}`);
    }
  }
}

async function readJsonResponse(res, label) {
  const text = await res.text();
  if (!text || !text.trim()) return null;
  try {
    return JSON.parse(text);
  } catch (e) {
    throw new Error(`${label}: ${e.message}`);
  }
}

async function importPrivateKey(pem) {
  const pemContents = pem
    .replace(PRIVATE_KEY_BEGIN, '')
    .replace(PRIVATE_KEY_END, '')
    .replace(/\s/g, '');
  const binaryDer = Uint8Array.from(atob(pemContents), (c) => c.charCodeAt(0));
  return crypto.subtle.importKey(
    'pkcs8',
    binaryDer,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
}

async function createFirebaseAuthJWT(clientEmail, privateKeyPem) {
  const header = { alg: 'RS256', typ: 'JWT' };
  const now = Math.floor(Date.now() / 1000);
  const payload = {
    iss: clientEmail,
    sub: clientEmail,
    aud: 'https://identitytoolkit.googleapis.com/google.identity.identitytoolkit.v1.IdentityToolkit',
    iat: now,
    exp: now + 3600,
    uid: 'worker-notifications',
    claims: { role: 'admin' },
  };
  const encodedHeader = base64UrlEncode(JSON.stringify(header));
  const encodedPayload = base64UrlEncode(JSON.stringify(payload));
  const signatureInput = `${encodedHeader}.${encodedPayload}`;
  const privateKey = await importPrivateKey(privateKeyPem);
  const signature = await crypto.subtle.sign(
    { name: 'RSASSA-PKCS1-v1_5' },
    privateKey,
    new TextEncoder().encode(signatureInput),
  );
  return `${signatureInput}.${base64UrlEncode(new Uint8Array(signature))}`;
}

async function getFirebaseToken(env) {
  const now = Date.now();
  if (_fbToken && now < _fbTokenExpMs) return _fbToken;

  if (env?.FIREBASE_SERVICE_ACCOUNT) {
    const sa = parseJsonSecret(env.FIREBASE_SERVICE_ACCOUNT, 'FIREBASE_SERVICE_ACCOUNT');
    const jwt = await createFirebaseAuthJWT(sa.client_email, sa.private_key);
    const url = `https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${env.FB_API_KEY}`;
    const res = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ token: jwt, returnSecureToken: true }),
    });
    if (!res.ok) throw new Error(`Firebase auth failed: ${res.status}`);
    const data = await readJsonResponse(res, 'Firebase auth response');
    _fbToken = data.idToken;
    _fbTokenExpMs = now + 50 * 60 * 1000;
    return _fbToken;
  }

  const url = `https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${env.FB_API_KEY}`;
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ returnSecureToken: true }),
  });
  const data = await readJsonResponse(res, 'Firebase anonymous auth response');
  _fbToken = data.idToken;
  _fbTokenExpMs = now + 50 * 60 * 1000;
  return _fbToken;
}

async function getFcmAccessToken(env) {
  const now = Date.now();
  if (_fcmToken && now < _fcmTokenExpMs) return _fcmToken;
  const sa = parseJsonSecret(env.FIREBASE_SERVICE_ACCOUNT, 'FIREBASE_SERVICE_ACCOUNT');
  const header = { alg: 'RS256', typ: 'JWT' };
  const payload = {
    iss: sa.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: Math.floor(now / 1000),
    exp: Math.floor(now / 1000) + 3600,
  };
  const encodedHeader = base64UrlEncode(JSON.stringify(header));
  const encodedPayload = base64UrlEncode(JSON.stringify(payload));
  const signatureInput = `${encodedHeader}.${encodedPayload}`;
  const privateKey = await importPrivateKey(sa.private_key);
  const signature = await crypto.subtle.sign(
    { name: 'RSASSA-PKCS1-v1_5' },
    privateKey,
    new TextEncoder().encode(signatureInput),
  );
  const jwt = `${signatureInput}.${base64UrlEncode(new Uint8Array(signature))}`;
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  });
  const data = await readJsonResponse(res, 'FCM access token response');
  if (!data.access_token) throw new Error(`FCM token failed: ${JSON.stringify(data)}`);
  _fcmToken = data.access_token;
  _fcmTokenExpMs = now + Math.max(60, Number(data.expires_in || 3600) - 60) * 1000;
  return _fcmToken;
}

function _toMs(value) {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (typeof value === 'string' && value.trim()) {
    const parsed = Date.parse(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function aiSanitizeFactoryId(input) {
  return String(input || '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '');
}

function aiResolveFactory(obj) {
  if (!obj || typeof obj !== 'object') return null;
  const fid = String(obj.factoryId || '').trim();
  if (fid) return aiSanitizeFactoryId(fid);
  const usine = String(obj.usine || '').trim();
  return usine ? aiSanitizeFactoryId(usine) : null;
}

// Alerts and users identify their factory inconsistently: some records carry a
// `factoryId`, some only the plant name in `usine`, some a `factoryName`.
// Comparing a single resolved value silently drops every recipient when the two
// sides use different fields, so both sides are expanded into a candidate set
// and matched on any intersection.
function factoryCandidates(source) {
  const out = new Set();
  if (!source) return out;
  if (typeof source === 'string') {
    const id = aiSanitizeFactoryId(source);
    if (id) out.add(id);
    return out;
  }
  if (typeof source !== 'object') return out;
  for (const key of ['factoryId', 'usine', 'factoryName', 'alertUsine']) {
    const id = aiSanitizeFactoryId(source[key] || '');
    if (id) out.add(id);
  }
  return out;
}

// True when the user belongs to the target factory. An empty target set means
// the record carries no factory information at all; blocking there would
// silently drop the notification for everyone, so it passes instead.
function factoryMatches(targetSet, userSet) {
  if (!targetSet || targetSet.size === 0) return true;
  if (!userSet || userSet.size === 0) return false;
  for (const id of userSet) {
    if (targetSet.has(id)) return true;
  }
  return false;
}

async function loadCoreData(env) {
  const token = await getFirebaseToken(env);
  const [alertsRes, usersRes, activeClaimsRes] = await Promise.all([
    fetch(
      `${_fbUrl(env, 'alerts.json')}?auth=${token}`
      + `&orderBy=${encodeURIComponent('"$key"')}`
      + `&limitToLast=${Number(env.CORE_ALERTS_MAX || CORE_ALERTS_DEFAULT_CAP)}`,
    ),
    fetch(`${_fbUrl(env, 'users.json')}?auth=${token}`),
    fetch(`${_fbUrl(env, 'supervisor_active_alerts.json')}?auth=${token}`),
  ]);
  return {
    token,
    alertsMap: alertsRes.ok ? ((await readJsonResponse(alertsRes, 'alerts.json')) || {}) : {},
    usersMap: usersRes.ok ? ((await readJsonResponse(usersRes, 'users.json')) || {}) : {},
    supervisorActiveAlertsMap: activeClaimsRes.ok ? ((await readJsonResponse(activeClaimsRes, 'supervisor_active_alerts.json')) || {}) : {},
  };
}

function parseFcmFailure(status, text) {
  let errorCode = '';
  let message = text || '';
  try {
    const parsed = JSON.parse(text || '{}');
    const error = parsed?.error || {};
    message = error.message || message;
    errorCode = String(error.status || '');
    const detail = Array.isArray(error.details)
      ? error.details.find((d) => d && d.errorCode)
      : null;
    if (detail?.errorCode) errorCode = String(detail.errorCode);
  } catch (_) {
    errorCode = '';
  }
  const unregistered =
    status === 404 &&
    (errorCode === 'UNREGISTERED' ||
      errorCode === 'NOT_FOUND' ||
      /UNREGISTERED|Device unregistered/i.test(text || ''));
  return { errorCode, message, unregistered };
}

async function clearUnregisteredFcmToken(env, firebaseAuthToken, uid, staleToken) {
  if (!env?.FB_DB_URL || !firebaseAuthToken || !uid || !staleToken) return false;
  const tokenUrl = `${_fbUrl(env, `users/${uid}/fcmToken.json`)}?auth=${firebaseAuthToken}`;
  try {
    const currentRes = await fetch(tokenUrl, { headers: { 'X-Firebase-ETag': 'true' } });
    if (!currentRes.ok) return false;
    const etag = currentRes.headers.get('ETag');
    const current = await readJsonResponse(currentRes, `users/${uid}/fcmToken.json`);
    if (current !== staleToken) return false;
    const clearRes = await fetch(tokenUrl, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json', 'if-match': etag ?? '*' },
      body: 'null',
    });
    return clearRes.ok;
  } catch (e) {
    console.warn('[FCM] Failed to clear unregistered token: ' + e.message);
    return false;
  }
}

function normalizeFcmData(data, title, body) {
  const out = {};
  for (const [key, value] of Object.entries({ ...data, title, body })) {
    out[key] = value == null ? '' : String(value);
  }
  return out;
}

async function sendFcmDetailed(token, title, body, data, env, options = {}) {
  try {
    const accessToken = await getFcmAccessToken(env);
    const sa = parseJsonSecret(env.FIREBASE_SERVICE_ACCOUNT, 'FIREBASE_SERVICE_ACCOUNT');
    const url = `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`;
    const res = await fetch(url, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        message: {
          token,
          data: normalizeFcmData(data, title, body),
          android: { priority: 'high' },
          apns: {
            headers: { 'apns-priority': '10' },
            payload: { aps: { 'content-available': 1, sound: 'default' } },
          },
          webpush: {
            headers: { Urgency: 'high' },
            notification: {
              title,
              body,
              icon: '/icons/icon-192.png',
              badge: '/icons/icon-192.png',
              vibrate: [200, 100, 200, 100, 200],
              requireInteraction: false,
            },
          },
        },
      }),
    });
    if (!res.ok) {
      const err = await res.text();
      const failure = parseFcmFailure(res.status, err);
      if (failure.unregistered) {
        const uid = String(options.uid || data?.recipientId || '').trim();
        console.warn(`[FCM] Dropping unregistered token${uid ? ` for ${uid}` : ''}`);
        await clearUnregisteredFcmToken(env, options.firebaseAuthToken, uid, token);
      } else {
        console.error(`[FCM] Send failed (${res.status}):` + err);
      }
      return { ok: false, status: res.status, ...failure };
    }
    return { ok: true, status: res.status, errorCode: '', message: '', unregistered: false };
  } catch (e) {
    console.error('[FCM] Error:' + e.message);
    return { ok: false, status: 0, errorCode: 'EXCEPTION', message: e.message, unregistered: false };
  }
}

async function sendFcm(token, title, body, data, env, options = {}) {
  const result = await sendFcmDetailed(token, title, body, data, env, options);
  return result.ok;
}

const NOTIFICATION_ACTIVE_SUPERVISOR_STATUSES = new Set(['active', 'available', 'online', 'ready']);

function isActiveSupervisorForNotification(user) {
  const status = String(user?.status || '').toLowerCase();
  return NOTIFICATION_ACTIVE_SUPERVISOR_STATUSES.has(status) ||
    user?.active === true ||
    user?.isActive === true;
}

function engagedSupervisorIds(alertsMap = {}, supervisorActiveAlertsMap = {}) {
  const ids = new Set();
  for (const a of Object.values(alertsMap || {})) {
    if (!a || a.status !== 'en_cours') continue;
    if (a.superviseurId) ids.add(String(a.superviseurId));
    if (a.assistantId) ids.add(String(a.assistantId));
  }
  for (const [uid, claim] of Object.entries(supervisorActiveAlertsMap || {})) {
    if (!claim) continue;
    const alertId =
      typeof claim === 'string'
        ? claim
        : String(claim.alertId || claim.id || '').trim();
    const alert = alertId ? alertsMap?.[alertId] : null;
    if (alert && alert.status === 'en_cours') ids.add(String(uid));
  }
  return ids;
}

// `factoryRef` accepts either a factory name/id string or a whole alert-like
// object; the object form matches on any of factoryId/usine/factoryName so a
// factoryId-only alert still reaches usine-keyed users (and vice versa).
function getFcmRecipientsForFactory(
  factoryRef,
  usersMap,
  alertsMap,
  {
    allSupervisors = false,
    allFactories = false,
    includeAdmins = true,
    requireActiveSupervisors = false,
    supervisorActiveAlertsMap = {},
  } = {},
) {
  const targetFactories = factoryCandidates(factoryRef);
  const busySupervisors = allSupervisors
    ? new Set()
    : engagedSupervisorIds(alertsMap, supervisorActiveAlertsMap);
  const recipientsByToken = new Map();
  for (const [uid, user] of Object.entries(usersMap || {})) {
    if (!user || !user.fcmToken) continue;
    if (user.role === 'supervisor') {
      if (requireActiveSupervisors && !isActiveSupervisorForNotification(user)) continue;
      if (busySupervisors.has(uid)) continue;
      if (!allFactories && !factoryMatches(targetFactories, factoryCandidates(user))) continue;
    } else if (user.role !== 'admin') {
      continue;
    } else if (!includeAdmins) {
      continue;
    }
    const fcmToken = String(user.fcmToken);
    if (!recipientsByToken.has(fcmToken)) {
      recipientsByToken.set(fcmToken, { uid, token: fcmToken, role: String(user.role || '') });
    }
  }
  return [...recipientsByToken.values()];
}

function getFcmTokensForFactory(factoryName, usersMap, alertsMap, options = {}) {
  return getFcmRecipientsForFactory(factoryName, usersMap, alertsMap, options)
    .map((recipient) => recipient.token);
}

function _alertNotifId(alertId) {
  let h = 0;
  for (let i = 0; i < alertId.length; i++) {
    h = (h * 31 + alertId.charCodeAt(i)) % 0x7FFFFFFF;
  }
  return h || 1;
}

function _pushLockIsFresh(alert) {
  if (!alert || alert.push_sending !== true) return false;
  const started = _toMs(alert.push_sending_at);
  return started != null && Date.now() - started < PUSH_LOCK_TTL_MS;
}

async function claimAlertPush(env, token, alertId) {
  const alertUrl = `${_fbUrl(env, `alerts/${alertId}.json`)}?auth=${token}`;
  const getRes = await fetch(alertUrl, { headers: { 'X-Firebase-ETag': 'true' } });
  if (!getRes.ok) return null;
  const etag = getRes.headers.get('ETag');
  const current = await readJsonResponse(getRes, `alerts/${alertId}.json`);
  if (!current || current.push_sent !== false || current.status !== 'disponible') return null;
  if (_pushLockIsFresh(current)) return null;

  const nowIso = new Date().toISOString();
  const claimRes = await fetch(alertUrl, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json', 'if-match': etag },
    body: JSON.stringify({
      ...current,
      push_sending: true,
      push_sending_at: nowIso,
    }),
  });
  if (claimRes.status === 412 || !claimRes.ok) return null;
  return { alertUrl, alert: { id: alertId, ...current } };
}

async function finishAlertPush(alertUrl, sent) {
  const nowIso = new Date().toISOString();
  await fetch(alertUrl, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(
      sent
        ? {
            push_sent: true,
            push_sent_at: nowIso,
            push_sending: null,
            push_sending_at: null,
            push_last_error_at: null,
          }
        : {
            push_sent: false,
            push_sending: null,
            push_sending_at: null,
            push_last_error_at: nowIso,
          },
    ),
  });
}

async function skipAlertPush(alertUrl, reason) {
  const nowIso = new Date().toISOString();
  await fetch(alertUrl, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      push_sent: true,
      push_sent_at: nowIso,
      push_sending: null,
      push_sending_at: null,
      push_last_error_at: null,
      push_skip_reason: String(reason || 'skipped'),
    }),
  });
}

async function processAlerts(env, ctx) {
  const { token, alertsMap, usersMap, supervisorActiveAlertsMap } = ctx;
  const unsent = Object.entries(alertsMap || {})
    .filter(([, a]) => a && a.status === 'disponible' && a.push_sent === false && !_pushLockIsFresh(a))
    .sort((a, b) => (_toMs(b[1]?.timestamp) ?? 0) - (_toMs(a[1]?.timestamp) ?? 0))
    .slice(0, Math.max(MAX_ALERTS_TO_PUSH, 5))
    .map(([id]) => id);
  if (!unsent.length) return 0;

  let processed = 0;
  for (const alertId of unsent) {
    if (processed >= MAX_ALERTS_TO_PUSH) break;
    const claimed = await claimAlertPush(env, token, alertId);
    if (!claimed) continue;
    const { alertUrl, alert } = claimed;
    const recipients = getFcmRecipientsForFactory(alert, usersMap, alertsMap, {
      allSupervisors: false,
      includeAdmins: false,
      requireActiveSupervisors: false,
      supervisorActiveAlertsMap,
    });
    if (recipients.length === 0) {
      // No send was attempted, so close the alert push cycle without treating it
      // as a retryable FCM failure.
      await skipAlertPush(alertUrl, 'no_recipients');
      continue;
    }

    const title = `New Alert: ${alert.type || 'Alert'}`;
    const body = `${alert.usine || ''} - ${alert.description || ''}`;
    let sentCount = 0;
    let retryableFailure = false;
    for (const recipient of recipients) {
      const result = await sendFcmDetailed(
        recipient.token,
        title,
        body,
        {
          alertId: alert.id,
          recipientId: recipient.uid,
          type: alert.type || 'Alert',
          usine: alert.usine || '',
          factoryId: String(alert.factoryId || ''),
          notifType: 'new_alert',
          notificationId: String(_alertNotifId(alert.id)),
        },
        env,
        { firebaseAuthToken: token, uid: recipient.uid },
      );
      if (result.ok) {
        sentCount++;
      } else if (result.unregistered) {
        if (usersMap?.[recipient.uid]?.fcmToken === recipient.token) {
          usersMap[recipient.uid].fcmToken = null;
        }
      } else {
        retryableFailure = true;
      }
    }
    await finishAlertPush(alertUrl, sentCount > 0 || !retryableFailure);
    processed++;
  }
  return processed;
}

// `new_alert` rows are broadcast fan-out rows: no matter who queued them, the
// busy + factory gates are enforced here at send time. Every other queued type
// (collaboration, help, AI assignment/recommendation, presence, handover,
// critical updates) is personally addressed by its producer, so those deliver
// to their exact recipient regardless of busy state or factory.
const BUSY_FACTORY_GATED_NOTIF_TYPES = new Set(['new_alert']);

const ADMIN_ONLY_NOTIF_TYPES = new Set([
  'collaboration_request_admin',
  'ai_cross_factory_recommendation',
]);

const SUPERVISOR_ONLY_NOTIF_TYPES = new Set(['new_alert']);

const LEGACY_SKIPPED_NOTIF_TYPES = new Set(['']);

function _notificationLockIsFresh(notif) {
  if (!notif || notif.pushSending !== true) return false;
  const started = _toMs(notif.pushSendingAt);
  return started != null && Date.now() - started < NOTIFICATION_LOCK_TTL_MS;
}

// Candidate factory ids the notification targets: from its own fields first,
// enriched by the referenced alert record when available.
function notificationTargetFactory(notif, alertsMap = {}) {
  const candidates = factoryCandidates(notif);
  const alertId = String(notif?.alertId || '').trim();
  if (alertId && alertsMap?.[alertId]) {
    for (const id of factoryCandidates(alertsMap[alertId])) candidates.add(id);
  }
  return candidates;
}

// Single source of truth for "may this queued notification be pushed to this
// user right now". Returns one of:
//   { action: 'send' }                  — deliver via FCM
//   { action: 'skip', reason: '...' }   — permanently ineligible: close the row
//                                          (pushSent:true + pushSkipReason)
//   { action: 'defer' }                 — transient: leave the row for a retry
function evaluateNotificationDelivery(
  uid,
  user,
  notif,
  alertsMap = {},
  supervisorActiveAlertsMap = {},
  busySupervisors = null,
) {
  if (!notif || notif.pushSent === true || _notificationLockIsFresh(notif)) {
    return { action: 'defer' };
  }
  const notifType = String(notif.type || '');
  if (LEGACY_SKIPPED_NOTIF_TYPES.has(notifType)) return { action: 'defer' };
  if (!uid || uid === 'undefined' || !user) return { action: 'skip', reason: 'unknown_user' };

  const userRole = String(user.role || '');
  const isSupervisor = userRole === 'supervisor';
  const isAdmin = userRole === 'admin';
  if (!isSupervisor && !isAdmin) return { action: 'skip', reason: 'role_mismatch' };
  if (ADMIN_ONLY_NOTIF_TYPES.has(notifType) && !isAdmin) return { action: 'skip', reason: 'role_mismatch' };
  if (SUPERVISOR_ONLY_NOTIF_TYPES.has(notifType) && !isSupervisor) return { action: 'skip', reason: 'role_mismatch' };

  // Freshness: rows that outlived their usefulness are closed instead of being
  // rescanned by every future cron. Rows without a timestamp are kept.
  const createdMs = _toMs(notif.timestamp);
  if (createdMs != null) {
    const maxAge = notifType === 'new_alert' ? NEW_ALERT_MAX_AGE_MS : QUEUED_NOTIFICATION_MAX_AGE_MS;
    if (Date.now() - createdMs > maxAge) return { action: 'skip', reason: 'expired' };
  }

  if (BUSY_FACTORY_GATED_NOTIF_TYPES.has(notifType) && isSupervisor) {
    const busy = busySupervisors ?? engagedSupervisorIds(alertsMap, supervisorActiveAlertsMap);
    if (busy.has(uid)) return { action: 'skip', reason: 'busy_supervisor' };
    const targetFactories = notificationTargetFactory(notif, alertsMap);
    if (!factoryMatches(targetFactories, factoryCandidates(user))) {
      return { action: 'skip', reason: 'factory_mismatch' };
    }
  }

  if (!user.fcmToken) {
    // A buzz for a new alert is dead without a registered device; other types
    // wait for the token to re-register (bounded by the expiry above).
    return notifType === 'new_alert'
      ? { action: 'skip', reason: 'no_fcm_token' }
      : { action: 'defer' };
  }
  return { action: 'send' };
}

function notifTitle(type) {
  switch (String(type || '')) {
    case 'new_alert': return 'New Alert';
    case 'ai_assigned': return 'AI Assignment';
    case 'confirm_presence': return 'AI Shift Commander';
    case 'shift_handover': return 'Shift handover';
    case 'collaboration_request': return 'Collaboration request';
    case 'collaboration_assistant_accepted':
    case 'collaboration_assistant_removed':
    case 'collaboration_removed':
    case 'collaboration_approved':
    case 'collaboration_rejected':
    case 'collaboration_refused':
    case 'collab_auto_approved': return 'Collaboration update';
    case 'assistant_assigned': return 'Assistant assigned';
    case 'cross_factory_transfer': return 'Cross-factory transfer';
    case 'help_request':
    case 'assistance_request': return 'Help request';
    case 'help_accepted': return 'Help accepted';
    case 'help_refused': return 'Help declined';
    case 'ai_cross_factory_recommendation': return 'AI recommendation';
    case 'ai_rejection': return 'AI rejection';
    case 'alert_suspended': return 'Alert suspended';
    default: return 'SIAS - Smart Industrial Alert System';
  }
}

function notificationBody(notif) {
  return String(
    notif?.message ||
      notif?.alertDescription ||
      notif?.summary ||
      notif?.type ||
      'SIAS - Smart Industrial Alert System notification',
  );
}

function notificationFcmData(uid, notifId, notif) {
  const type = String(notif?.type || '');
  const alertId = String(notif?.alertId || '');
  const notificationId =
    type === 'new_alert' && alertId ? String(_alertNotifId(alertId)) : notifId;
  return {
    notificationId,
    queueNotificationId: notifId,
    recipientId: uid,
    alertId,
    collabRequestId: String(notif?.collabRequestId || notif?.collaborationId || ''),
    collaborationId: String(notif?.collaborationId || notif?.collabRequestId || ''),
    helpRequestId: String(notif?.helpRequestId || ''),
    shiftId: String(notif?.shiftId || ''),
    shiftName: String(notif?.shiftName || ''),
    type,
    notifType: type,
    usine: String(notif?.usine || notif?.alertUsine || ''),
    factoryId: String(notif?.factoryId || ''),
    factoryName: String(notif?.factoryName || ''),
    alertType: String(notif?.alertType || ''),
    alertNumber: String(notif?.alertNumber || ''),
  };
}

function normalizeNotificationRefs(payload) {
  const refs = [];
  const pushRef = (value) => {
    if (!value || typeof value !== 'object') return;
    const uid = String(value.uid || value.userId || value.recipientId || '').trim();
    const notifId = String(value.notifId || value.notificationId || value.id || '').trim();
    if (uid && notifId) refs.push({ uid, notifId });
  };
  pushRef(payload?.notification);
  pushRef(payload);
  if (Array.isArray(payload?.notifications)) {
    payload.notifications.forEach(pushRef);
  }

  const seen = new Set();
  return refs.filter((ref) => {
    const key = `${ref.uid}/${ref.notifId}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

async function claimNotificationPush(env, token, uid, notifId) {
  const url = `${_fbUrl(env, `notifications/${uid}/${notifId}.json`)}?auth=${token}`;
  const getRes = await fetch(url, { headers: { 'X-Firebase-ETag': 'true' } });
  if (!getRes.ok) return null;
  const etag = getRes.headers.get('ETag');
  const current = await readJsonResponse(getRes, `notifications/${uid}/${notifId}.json`);
  if (!current || current.pushSent === true || _notificationLockIsFresh(current)) return null;
  const currentType = String(current.type || '');
  if (LEGACY_SKIPPED_NOTIF_TYPES.has(currentType)) return null;

  const nowIso = new Date().toISOString();
  const claimRes = await fetch(url, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json', 'if-match': etag ?? '*' },
    body: JSON.stringify({
      ...current,
      pushSending: true,
      pushSendingAt: nowIso,
    }),
  });
  if (claimRes.status === 412 || !claimRes.ok) return null;
  return { url, notif: current };
}

async function releaseNotificationPush(url) {
  await fetch(url, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      pushSending: null,
      pushSendingAt: null,
    }),
  });
}

// Terminal close for a queued notification that must never be pushed
// (busy/wrong-factory/expired/…). Marks it delivered-with-reason so no future
// cron rescans it; also clears any push lock we hold.
async function skipNotificationPush(url, reason) {
  const nowIso = new Date().toISOString();
  await fetch(url, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      pushSent: true,
      pushSentAt: nowIso,
      pushSending: null,
      pushSendingAt: null,
      pushLastErrorAt: null,
      pushSkipReason: String(reason || 'skipped'),
    }),
  });
}

async function finishNotificationPush(url, sent) {
  const nowIso = new Date().toISOString();
  await fetch(url, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(
      sent
        ? {
            pushSent: true,
            pushSentAt: nowIso,
            pushSending: null,
            pushSendingAt: null,
            pushLastErrorAt: null,
          }
        : {
            pushSending: null,
            pushSendingAt: null,
            pushLastErrorAt: nowIso,
          },
    ),
  });
}

async function pushSingleNotificationWithCtx(env, ctx, uid, notifId) {
  if (!uid || !notifId) return false;
  const { token, usersMap, alertsMap, supervisorActiveAlertsMap } = ctx;
  const claimed = await claimNotificationPush(env, token, uid, notifId);
  if (!claimed) return false;

  const { url, notif } = claimed;
  const user = usersMap?.[uid];
  const verdict = evaluateNotificationDelivery(
    uid,
    user,
    notif,
    alertsMap,
    supervisorActiveAlertsMap,
  );
  if (verdict.action === 'skip') {
    await skipNotificationPush(url, verdict.reason);
    return false;
  }
  if (verdict.action !== 'send') {
    await releaseNotificationPush(url);
    return false;
  }

  const result = await sendFcmDetailed(
    String(user.fcmToken),
    notifTitle(notif.type),
    notificationBody(notif),
    notificationFcmData(uid, notifId, notif),
    env,
    { firebaseAuthToken: token, uid },
  );
  if (result.unregistered && user?.fcmToken) {
    user.fcmToken = null;
  }
  await finishNotificationPush(url, result.ok);
  return result.ok;
}

async function pushSingleNotification(env, uid, notifId) {
  const ctx = await loadCoreData(env);
  return pushSingleNotificationWithCtx(env, ctx, uid, notifId);
}

async function pushNotificationRefs(env, refs, options = {}) {
  const cleanRefs = (refs || []).filter((ref) => ref?.uid && ref?.notifId);
  if (!cleanRefs.length) return { attempted: 0, sent: 0 };
  const limit = Math.max(1, Number(options.limit ?? MAX_FANOUT) || MAX_FANOUT);
  const ctx = await loadCoreData(env);
  let attempted = 0;
  let sent = 0;
  for (const ref of cleanRefs.slice(0, limit)) {
    attempted++;
    if (await pushSingleNotificationWithCtx(env, ctx, ref.uid, ref.notifId)) {
      sent++;
    }
  }
  return { attempted, sent };
}

async function fanOutPendingNotifications(env, ctx, options = {}) {
  const { token, usersMap, alertsMap, supervisorActiveAlertsMap } = ctx;
  const limit = Math.max(0, Number(options.limit ?? MAX_FANOUT) || 0);
  if (limit <= 0) return { sent: 0, skipped: 0 };
  const nowIso = new Date().toISOString();
  const busySupervisors = engagedSupervisorIds(alertsMap, supervisorActiveAlertsMap);
  const notifRes = await fetch(`${_fbUrl(env, 'notifications.json')}?auth=${token}`);
  if (!notifRes.ok) return { sent: 0, skipped: 0 };
  const allNotifs = (await readJsonResponse(notifRes, 'notifications.json')) || {};
  const candidates = [];
  const ineligible = [];

  for (const [uid, bucket] of Object.entries(allNotifs)) {
    const user = usersMap[uid];
    for (const [notifId, notif] of Object.entries(bucket || {})) {
      const verdict = evaluateNotificationDelivery(
        uid,
        user,
        notif,
        alertsMap,
        supervisorActiveAlertsMap,
        busySupervisors,
      );
      if (verdict.action === 'send') {
        candidates.push({ uid, notifId, notif, user });
      } else if (verdict.action === 'skip') {
        ineligible.push({ uid, notifId, reason: verdict.reason });
      }
    }
  }

  // Terminally close rows that can never be pushed so they stop occupying the
  // backlog. Bounded per run; leftovers are closed by subsequent crons.
  let skipped = 0;
  for (const dead of ineligible.slice(0, MAX_TERMINAL_SKIPS_PER_RUN)) {
    try {
      await skipNotificationPush(
        `${_fbUrl(env, `notifications/${dead.uid}/${dead.notifId}.json`)}?auth=${token}`,
        dead.reason,
      );
      skipped++;
    } catch (e) {
      console.error(`[NOTIFY] Skip-close ${dead.uid}/${dead.notifId} failed: ${e.message}`);
    }
  }

  candidates.sort((a, b) => {
    const aMs = _toMs(a.notif?.timestamp) ?? 0;
    const bMs = _toMs(b.notif?.timestamp) ?? 0;
    return bMs - aMs;
  });

  let processed = 0;
  for (const candidate of candidates) {
    if (processed >= limit) break;
    const { uid, notifId, user } = candidate;
    try {
      const url = `${_fbUrl(env, `notifications/${uid}/${notifId}.json`)}?auth=${token}`;
      const getRes = await fetch(url, { headers: { 'X-Firebase-ETag': 'true' } });
      if (!getRes.ok) continue;
      const etag = getRes.headers.get('ETag');
      const current = await readJsonResponse(getRes, `notifications/${uid}/${notifId}.json`);
      // Re-evaluate against the fresh row: another worker may have sent or
      // mutated it between the bulk scan and now.
      const verdict = evaluateNotificationDelivery(
        uid,
        user,
        current,
        alertsMap,
        supervisorActiveAlertsMap,
        busySupervisors,
      );
      if (verdict.action === 'skip') {
        await skipNotificationPush(url, verdict.reason);
        skipped++;
        continue;
      }
      if (verdict.action !== 'send') continue;

      const claimRes = await fetch(url, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json', 'if-match': etag ?? '*' },
        body: JSON.stringify({ ...current, pushSending: true, pushSendingAt: nowIso }),
      });
      if (claimRes.status === 412 || !claimRes.ok) continue;

      const fcmToken = String(user.fcmToken);
      const result = await sendFcmDetailed(
        fcmToken,
        notifTitle(current.type),
        notificationBody(current),
        notificationFcmData(uid, notifId, current),
        env,
        { firebaseAuthToken: token, uid },
      );
      if (result.unregistered && user?.fcmToken === fcmToken) {
        user.fcmToken = null;
      }

      await fetch(url, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(
          result.ok
            ? { pushSent: true, pushSentAt: nowIso, pushSending: null, pushSendingAt: null, pushLastErrorAt: null }
            : { pushSending: null, pushSendingAt: null, pushLastErrorAt: nowIso },
        ),
      });
      processed++;
      if (result.unregistered) break;
    } catch (e) {
      console.error(`[NOTIFY] Fan-out candidate ${uid}/${notifId} failed: ${e.message}`);
    }
  }
  return { sent: processed, skipped };
}

async function writeNotifyHealth(env, token, data) {
  if (!env?.FB_DB_URL || !token) return;
  try {
    await fetch(`${_fbUrl(env, 'workers/health/notifyLastRun.json')}?auth=${token}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        at: new Date().toISOString(),
        ...data,
      }),
    });
  } catch (e) {
    console.error('[NOTIFY] Health write failed: ' + e.message);
  }
}

// Fast-path: push one specific alert by ID.
// • Users + active-claims + in-progress-alerts fetches run IN PARALLEL with
//   the claim retries so the slowest fetch sets the wall time, not the sum.
// • FCM fan-out runs in parallel (Promise.all) — 10 recipients ≈ same wall
//   time as 1.
// • Busy supervisors are excluded with the exact same semantics as the cron
//   path (engagedSupervisorIds): owners AND assistants of en_cours alerts,
//   plus active-claim entries that point at an en_cours alert. Stale
//   supervisor_active_alerts rows (pointing at resolved/deleted alerts) do
//   NOT block an otherwise-free supervisor.
async function pushSingleAlert(env, alertId) {
  if (!alertId) return false;
  const token = await getFirebaseToken(env);

  // Speculatively start the fetches now; they almost always finish before the
  // claim loop does, so we pay zero extra wall time. The en_cours query is an
  // indexed shallow slice — far cheaper than loading the whole alerts table.
  const usersP = fetch(`${_fbUrl(env, 'users.json')}?auth=${token}`)
    .then(r => r.ok ? readJsonResponse(r, 'users.json') : null)
    .then(v => v || {})
    .catch(() => ({}));
  const claimsP = fetch(`${_fbUrl(env, 'supervisor_active_alerts.json')}?auth=${token}`)
    .then(r => r.ok ? readJsonResponse(r, 'supervisor_active_alerts.json') : null)
    .then(v => v || {})
    .catch(() => ({}));
  const enCoursP = fetch(
    `${_fbUrl(env, 'alerts.json')}?auth=${token}&orderBy=${encodeURIComponent('"status"')}`
    + `&equalTo=${encodeURIComponent('"en_cours"')}&limitToFirst=${MAX_EN_COURS_SCAN}`,
  )
    .then(r => r.ok ? readJsonResponse(r, 'alerts en_cours query') : null)
    .catch(() => null);

  let claimed = null;
  for (let attempt = 0; attempt < 3 && !claimed; attempt++) {
    if (attempt > 0) await new Promise(r => setTimeout(r, 400));
    claimed = await claimAlertPush(env, token, alertId);
  }
  if (!claimed) return false;

  const { alertUrl, alert } = claimed;
  const usersMap = await usersP;
  const supervisorActiveAlertsMap = await claimsP;
  const enCoursMap = await enCoursP;

  let recipients;
  if (enCoursMap !== null) {
    recipients = getFcmRecipientsForFactory(
      alert,
      usersMap,
      enCoursMap || {},
      { allSupervisors: false, includeAdmins: false, requireActiveSupervisors: false, supervisorActiveAlertsMap },
    );
  } else {
    // The indexed query failed — fail safe: treat every active-claim entry as
    // busy (may over-exclude, never buzzes a genuinely busy supervisor).
    const busySupervisorUids = new Set();
    for (const [uid, claim] of Object.entries(supervisorActiveAlertsMap || {})) {
      if (!claim) continue;
      const claimAlertId = typeof claim === 'string'
        ? claim
        : String(claim.alertId || claim.id || '').trim();
      if (claimAlertId) busySupervisorUids.add(String(uid));
    }
    recipients = getFcmRecipientsForFactory(
      alert,
      usersMap,
      {},
      { allSupervisors: true, includeAdmins: false, requireActiveSupervisors: false, supervisorActiveAlertsMap },
    ).filter(r => !busySupervisorUids.has(r.uid));
  }

  if (recipients.length === 0) {
    await skipAlertPush(alertUrl, 'no_recipients');
    return false;
  }

  const title = `New Alert: ${alert.type || 'Alert'}`;
  const body = `${alert.usine || ''} - ${alert.description || ''}`;
  const data = {
    alertId,
    type: alert.type || 'Alert',
    usine: alert.usine || '',
    factoryId: String(alert.factoryId || ''),
    notifType: 'new_alert',
    notificationId: String(_alertNotifId(alertId)),
  };

  const results = await Promise.all(recipients.map(recipient =>
    sendFcmDetailed(
      recipient.token, title, body,
      { ...data, recipientId: recipient.uid },
      env,
      { firebaseAuthToken: token, uid: recipient.uid },
    )
  ));

  let sentCount = 0;
  let retryableFailure = false;
  results.forEach((result, i) => {
    if (result.ok) {
      sentCount++;
    } else if (result.unregistered) {
      const uid = recipients[i].uid;
      if (usersMap?.[uid]?.fcmToken === recipients[i].token) usersMap[uid].fcmToken = null;
    } else {
      retryableFailure = true;
    }
  });

  await finishAlertPush(alertUrl, sentCount > 0 || !retryableFailure);
  return sentCount > 0;
}

async function runNotificationCycle(env, options = {}) {
  const runStart = Date.now();
  const ctx = await loadCoreData(env);
  const alertsProcessed = await processAlerts(env, ctx);
  const fanout = await fanOutPendingNotifications(env, ctx, {
    limit: options.limit ?? MAX_FANOUT,
  });
  await writeNotifyHealth(env, ctx.token, {
    durationMs: Date.now() - runStart,
    alertsProcessed,
    notificationsProcessed: fanout.sent,
    notificationsSkipped: fanout.skipped,
  });
  return {
    alertsProcessed,
    notificationsProcessed: fanout.sent,
    notificationsSkipped: fanout.skipped,
  };
}

async function recordNotifyError(env, error) {
  try {
    const token = await getFirebaseToken(env);
    await writeNotifyHealth(env, token, { error: String(error?.message || error) });
  } catch (_) {
    // Ignore secondary diagnostics failures.
  }
}

async function acquireNotifyLock(env, token) {
  const lockUrl = `${_fbUrl(env, 'cron_lock/notify.json')}?auth=${token}`;
  const lockGet = await fetch(lockUrl, { headers: { 'X-Firebase-ETag': 'true' } });
  const lockEtag = lockGet.ok ? lockGet.headers.get('ETag') : null;
  const lockData = lockGet.ok ? (await readJsonResponse(lockGet, 'cron_lock/notify.json')) : null;
  if (lockData && typeof lockData.ts === 'number' && Date.now() - lockData.ts < 45000) {
    return null;
  }
  const lockPut = await fetch(lockUrl, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json', 'if-match': lockEtag ?? '*' },
    body: JSON.stringify({ ts: Date.now() }),
  });
  if (lockPut.status === 412 || !lockPut.ok) return null;
  return lockUrl;
}

export default {
  async scheduled(event, env, ctx) {
    ctx.waitUntil(
      (async () => {
        let token;
        let lockUrl;
        try {
          token = await getFirebaseToken(env);
          lockUrl = await acquireNotifyLock(env, token);
          if (!lockUrl) {
            await writeNotifyHealth(env, token, { skipped: true, reason: 'lock_held' });
            return;
          }
          await runNotificationCycle(env, { limit: MAX_CRON_FANOUT });
        } catch (e) {
          console.error('[NOTIFY CRON] ' + e.message);
          if (token) await writeNotifyHealth(env, token, { error: e.message });
        } finally {
          if (lockUrl) {
            try { await fetch(lockUrl, { method: 'DELETE' }); } catch (_) {}
          }
        }
      })(),
    );
  },

  async fetch(request, env, ctx) {
    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: corsHeaders });
    }
    const url = new URL(request.url);
    const guard = _securityGuard(request, url.pathname === '/notify' ? 'notify' : 'default');
    if (!guard.ok) return guard.response;

    // Caller authentication (Firebase ID token or legacy shared secret).
    // `/config` stays public for uptime/status probes.
    if (url.pathname !== '/config') {
      const auth = await _workerAuthCheck(request, env);
      if (!auth.ok) return _json({ ok: false, error: 'unauthorized' }, 401);
      if (auth.mode === 'log' && (auth.method === 'unauthenticated_logged' || auth.method === 'invalid_token_logged')) {
        console.warn(`[AUTH] ${url.pathname}: caller without valid credentials (${auth.error || 'none presented'})`);
      }
    }

    if (url.pathname === '/config') {
      return _json({
        service: 'alertsys-notifications-worker',
        status: 'ok',
        responsibilities: ['processAlerts', 'pushSingleAlert', 'pushSingleNotification', 'fanOutPendingNotifications'],
      });
    }

    if (url.pathname === '/notify-sync' || (url.pathname === '/notify' && url.searchParams.get('sync') === '1')) {
      try {
        const result = await runNotificationCycle(env, { limit: MAX_FANOUT });
        return _json({ ok: true, ...result });
      } catch (e) {
        await recordNotifyError(env, e);
        return _json({ ok: false, error: String(e?.message || e) }, 500);
      }
    }

    if (url.pathname === '/notify' || url.pathname === '/') {
      let alertId = null;
      let notificationRefs = [];
      if (request.method === 'POST') {
        try {
          const b = await request.clone().json();
          alertId = b?.alertId || null;
          notificationRefs = normalizeNotificationRefs(b);
        } catch (_) {}
      }
      ctx.waitUntil(
        (async () => {
          let alertSent = false;
          let refsResult = { attempted: 0, sent: 0 };
          if (alertId) {
            alertSent = await pushSingleAlert(env, alertId);
          }
          if (notificationRefs.length) {
            refsResult = await pushNotificationRefs(env, notificationRefs, { limit: MAX_FANOUT });
          }
          if (!alertId && notificationRefs.length === 0) {
            await runNotificationCycle(env, { limit: MAX_FANOUT });
            return;
          }
          if (alertId && !alertSent) {
            await runNotificationCycle(env, { limit: MAX_FANOUT });
          }
        })().catch(async (e) => {
          console.error('[NOTIFY MANUAL] ' + e.message);
          await recordNotifyError(env, e);
        }),
      );
      return _json({ queued: true, alertId: alertId || null, notifications: notificationRefs.length });
    }

    return _json({ ok: false, error: 'not_found' }, 404);
  },
};

export {
  base64UrlEncode,
  getFirebaseToken,
  sendFcm,
  getFcmTokensForFactory,
  processAlerts,
  fanOutPendingNotifications,
  pushSingleAlert,
  pushSingleNotification,
  pushNotificationRefs,
  normalizeNotificationRefs,
  evaluateNotificationDelivery,
  factoryCandidates,
  factoryMatches,
  engagedSupervisorIds,
  _validateIdTokenClaims,
  _constantTimeEquals,
  _workerAuthCheck,
};
