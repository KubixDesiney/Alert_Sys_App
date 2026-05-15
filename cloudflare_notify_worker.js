// Cloudflare Worker - AlertSys Notifications Worker
// Cron schedule: "* * * * *" (every minute)
// Responsibilities: new-alert push fan-out, queued notification fan-out, /notify.

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, x-worker-secret, X-AlertSys-Worker-Secret',
};

let _fbToken = null;
let _fbTokenExpMs = 0;
let _fcmToken = null;
let _fcmTokenExpMs = 0;

const MAX_ALERTS_TO_PUSH = 1;
const MAX_FANOUT = 5;
const MAX_CRON_FANOUT = 5;
const PUSH_LOCK_TTL_MS = 2 * 60 * 1000;
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
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
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

async function loadCoreData(env) {
  const token = await getFirebaseToken(env);
  const [alertsRes, usersRes, activeClaimsRes] = await Promise.all([
    fetch(`${_fbUrl(env, 'alerts.json')}?auth=${token}`),
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

function getFcmRecipientsForFactory(
  factoryName,
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
  const targetId = aiSanitizeFactoryId(factoryName);
  const busySupervisors = allSupervisors
    ? new Set()
    : engagedSupervisorIds(alertsMap, supervisorActiveAlertsMap);
  const recipientsByToken = new Map();
  for (const [uid, user] of Object.entries(usersMap || {})) {
    if (!user || !user.fcmToken) continue;
    if (user.role === 'supervisor') {
      if (requireActiveSupervisors && !isActiveSupervisorForNotification(user)) continue;
      if (busySupervisors.has(uid)) continue;
      if (!allFactories) {
        const userFid = aiResolveFactory(user);
        if (userFid !== targetId) continue;
      }
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
    const recipients = getFcmRecipientsForFactory(alert.factoryId || alert.usine, usersMap, alertsMap, {
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

const COLLAB_NOTIF_TYPES = new Set([
  'collaboration_request',
  'collaboration_assistant_accepted',
  'collaboration_assistant_removed',
  'collaboration_removed',
  'collaboration_approved',
  'collaboration_rejected',
  'collaboration_refused',
  'collaboration_request_admin',
  'assistant_assigned',
  'collab_auto_approved',
  'cross_factory_transfer',
  'help_request',
  'assistance_request',
  'alert_critical_update',
]);

const ADMIN_ONLY_NOTIF_TYPES = new Set([
  'collaboration_request_admin',
  'ai_cross_factory_recommendation',
]);

const LEGACY_SKIPPED_NOTIF_TYPES = new Set(['', 'new_alert']);

function notificationTargetFactory(notif, alertsMap = {}) {
  const directFactory =
    notif?.usine || notif?.alertUsine || notif?.factoryName || notif?.factoryId || '';
  if (String(directFactory || '').trim()) {
    return aiSanitizeFactoryId(directFactory);
  }
  const alertId = String(notif?.alertId || '').trim();
  if (!alertId) return null;
  return aiResolveFactory(alertsMap?.[alertId] || null);
}

function notifTitle(type) {
  switch (String(type || '')) {
    case 'ai_assigned': return 'AI Assignment';
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
    case 'ai_cross_factory_recommendation': return 'AI recommendation';
    case 'ai_rejection': return 'AI rejection';
    case 'alert_suspended': return 'Alert suspended';
    default: return 'AlertSys';
  }
}

async function fanOutPendingNotifications(env, ctx, options = {}) {
  const { token, usersMap, alertsMap, supervisorActiveAlertsMap } = ctx;
  const limit = Math.max(0, Number(options.limit ?? MAX_FANOUT) || 0);
  if (limit <= 0) return 0;
  const nowIso = new Date().toISOString();
  const busySupervisors = engagedSupervisorIds(alertsMap, supervisorActiveAlertsMap);
  const notifRes = await fetch(`${_fbUrl(env, 'notifications.json')}?auth=${token}`);
  if (!notifRes.ok) return 0;
  const allNotifs = (await readJsonResponse(notifRes, 'notifications.json')) || {};
  const candidates = [];

  for (const [uid, bucket] of Object.entries(allNotifs)) {
    const user = usersMap[uid];
    const fcmToken = user?.fcmToken;
    const userRole = String(user?.role || '');
    const isSupervisor = userRole === 'supervisor';
    const isAdmin = userRole === 'admin';
    const isBusySupervisor = isSupervisor && busySupervisors.has(uid);
    const userFactoryId = aiResolveFactory(user || null);

    for (const [notifId, notif] of Object.entries(bucket || {})) {
      if (!notif || notif.pushSent === true || notif.pushSending === true) continue;
      const notifType = String(notif.type || '');
      if (LEGACY_SKIPPED_NOTIF_TYPES.has(notifType)) continue;
      if (!user || !fcmToken || uid === 'undefined') continue;
      const isCollabNotification = COLLAB_NOTIF_TYPES.has(notifType);
      if (isBusySupervisor && !isCollabNotification) continue;
      if (ADMIN_ONLY_NOTIF_TYPES.has(notifType) && !isAdmin) continue;
      if (isSupervisor && !isCollabNotification) {
        const targetFactoryId = notificationTargetFactory(notif, alertsMap);
        if (targetFactoryId && targetFactoryId !== userFactoryId) continue;
      }
      candidates.push({
        uid,
        notifId,
        notif,
        user,
        fcmToken,
        isAdmin,
        isSupervisor,
        userFactoryId,
      });
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
      const { uid, notifId, user, fcmToken, isAdmin, isSupervisor, userFactoryId } = candidate;
    try {
      const url = `${_fbUrl(env, `notifications/${uid}/${notifId}.json`)}?auth=${token}`;
      const getRes = await fetch(url, { headers: { 'X-Firebase-ETag': 'true' } });
      if (!getRes.ok) continue;
      const etag = getRes.headers.get('ETag');
      const current = await readJsonResponse(getRes, `notifications/${uid}/${notifId}.json`);
      if (!current || current.pushSent === true || current.pushSending === true) continue;
      const currentType = String(current.type || '');
      if (LEGACY_SKIPPED_NOTIF_TYPES.has(currentType)) continue;
      const currentIsCollab = COLLAB_NOTIF_TYPES.has(currentType);
      if (ADMIN_ONLY_NOTIF_TYPES.has(currentType) && !isAdmin) continue;
      if (isSupervisor && !currentIsCollab) {
        const targetFactoryId = notificationTargetFactory(current, alertsMap);
        if (targetFactoryId && targetFactoryId !== userFactoryId) continue;
      }

      const claimRes = await fetch(url, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json', 'if-match': etag },
        body: JSON.stringify({ ...current, pushSending: true }),
      });
      if (claimRes.status === 412 || !claimRes.ok) continue;

      const result = await sendFcmDetailed(
        fcmToken,
        notifTitle(current.type),
        String(current.message || current.type || 'AlertSys notification'),
        {
          notificationId: notifId,
          recipientId: uid,
          alertId: String(current.alertId || ''),
          collabRequestId: String(current.collabRequestId || ''),
          type: currentType,
          usine: String(current.usine || current.alertUsine || ''),
        },
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
            ? { pushSent: true, pushSentAt: nowIso, pushSending: null }
            : { pushSending: null, pushLastErrorAt: nowIso },
        ),
      });
      processed++;
      if (result.unregistered) break;
    } catch (e) {
      console.error(`[NOTIFY] Fan-out candidate ${uid}/${notifId} failed: ${e.message}`);
    }
  }
  return processed;
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
// • Users + active-claims fetches run IN PARALLEL with the claim retries so
//   the slowest of {claim, users, claims} sets the wall time, not the sum.
// • FCM fan-out runs in parallel (Promise.all) — 10 recipients ≈ same wall
//   time as 1.
// • Busy supervisors (those with any entry in supervisor_active_alerts) are
//   excluded so they do not buzz while already handling another alert.
//   Collab notifications take a different path (fanOutPendingNotifications)
//   which intentionally bypasses this filter.
async function pushSingleAlert(env, alertId) {
  if (!alertId) return false;
  const token = await getFirebaseToken(env);

  // Speculatively start the users + active-claims fetches now; they almost
  // always finish before the claim loop does, so we pay zero extra wall time.
  const usersP = fetch(`${_fbUrl(env, 'users.json')}?auth=${token}`)
    .then(r => r.ok ? readJsonResponse(r, 'users.json') : null)
    .then(v => v || {})
    .catch(() => ({}));
  const claimsP = fetch(`${_fbUrl(env, 'supervisor_active_alerts.json')}?auth=${token}`)
    .then(r => r.ok ? readJsonResponse(r, 'supervisor_active_alerts.json') : null)
    .then(v => v || {})
    .catch(() => ({}));

  let claimed = null;
  for (let attempt = 0; attempt < 3 && !claimed; attempt++) {
    if (attempt > 0) await new Promise(r => setTimeout(r, 400));
    claimed = await claimAlertPush(env, token, alertId);
  }
  if (!claimed) return false;

  const { alertUrl, alert } = claimed;
  const usersMap = await usersP;
  const supervisorActiveAlertsMap = await claimsP;

  // A supervisor is "busy" iff they have any entry in supervisor_active_alerts
  // (the entry is created on claim and removed when the alert is finished or
  // returned). engagedSupervisorIds needs a full alertsMap to cross-reference;
  // the fast path doesn't load that, so we compute busy directly here.
  const busySupervisorUids = new Set();
  for (const [uid, claim] of Object.entries(supervisorActiveAlertsMap || {})) {
    if (!claim) continue;
    const claimAlertId = typeof claim === 'string'
      ? claim
      : String(claim.alertId || claim.id || '').trim();
    if (claimAlertId) busySupervisorUids.add(String(uid));
  }

  // allSupervisors:true bypasses the built-in engagedSupervisorIds filter (we
  // apply our own busy filter below). Factory filter still applies.
  const allRecipients = getFcmRecipientsForFactory(
    alert.factoryId || alert.usine,
    usersMap,
    { [alertId]: alert },
    { allSupervisors: true, includeAdmins: false, requireActiveSupervisors: false, supervisorActiveAlertsMap },
  );
  const recipients = allRecipients.filter(r => !busySupervisorUids.has(r.uid));

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
  const notificationsProcessed = await fanOutPendingNotifications(env, ctx, {
    limit: options.limit ?? MAX_FANOUT,
  });
  await writeNotifyHealth(env, ctx.token, {
    durationMs: Date.now() - runStart,
    alertsProcessed,
    notificationsProcessed,
  });
  return { alertsProcessed, notificationsProcessed };
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

    if (url.pathname === '/config') {
      return _json({
        service: 'alertsys-notifications-worker',
        status: 'ok',
        responsibilities: ['processAlerts', 'fanOutPendingNotifications'],
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
      if (request.method === 'POST') {
        try { const b = await request.clone().json(); alertId = b?.alertId || null; } catch (_) {}
      }
      ctx.waitUntil(
        (alertId
          ? pushSingleAlert(env, alertId).then(sent => {
              if (!sent) return runNotificationCycle(env, { limit: MAX_FANOUT });
            })
          : runNotificationCycle(env, { limit: MAX_FANOUT })
        ).catch(async (e) => {
          console.error('[NOTIFY MANUAL] ' + e.message);
          await recordNotifyError(env, e);
        }),
      );
      return _json({ queued: true });
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
};
