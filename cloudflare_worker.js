// Cloudflare Worker — AlertSys (optimised)
// Deploy via Cloudflare dashboard: paste into the worker editor, save and deploy.
//
// Required environment variables (set in Worker Settings → Variables):
//   FB_DB_URL                = https://alertappsys-default-rtdb.firebaseio.com/
//   FB_API_KEY               = AIzaSyAr9G-E1G_HDf2DOBoUvoqfuCXBed8mPUM
//   GEMINI_API_KEY           = <your Gemini key>
//   FIREBASE_SERVICE_ACCOUNT = <stringified JSON of your Firebase service account>
//
// Cron schedule: "* * * * *" (every minute)
// ============================================================

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers':
    'Content-Type, Authorization, X-AlertSys-Worker-Secret, X-Firebase-ID-Token',
};

const WORKER_SECRET_HEADER = 'X-AlertSys-Worker-Secret';

function jsonResponse(payload, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

function timingSafeEqual(a, b) {
  const left = String(a || '');
  const right = String(b || '');
  const max = Math.max(left.length, right.length);
  let diff = left.length ^ right.length;
  for (let i = 0; i < max; i++) {
    diff |= left.charCodeAt(i % Math.max(left.length, 1)) ^
      right.charCodeAt(i % Math.max(right.length, 1));
  }
  return diff === 0;
}

function requestSharedSecret(request) {
  const explicit = request.headers.get(WORKER_SECRET_HEADER);
  if (explicit) return explicit;
  const auth = request.headers.get('Authorization') || '';
  return auth.toLowerCase().startsWith('bearer ') ? auth.slice(7).trim() : '';
}

function requireSharedSecret(request, env) {
  const expected = env.WORKER_SHARED_SECRET || env.ALERTSYS_WORKER_SECRET;
  if (!expected) {
    console.error('[AUTHZ] WORKER_SHARED_SECRET is not configured');
    return jsonResponse({ error: 'Worker authentication is not configured.' }, 503);
  }
  if (!timingSafeEqual(requestSharedSecret(request), expected)) {
    return jsonResponse({ error: 'Unauthorized' }, 401);
  }
  return null;
}

async function lookupFirebaseUser(idToken, env) {
  if (!idToken) return null;
  const res = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=${env.FB_API_KEY}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ idToken }),
    },
  );
  if (!res.ok) return null;
  const data = await res.json();
  return data.users?.[0] || null;
}

async function requireAdminCaller(request, env, token) {
  const idToken = request.headers.get('X-Firebase-ID-Token') || '';
  const user = await lookupFirebaseUser(idToken, env);
  const uid = user?.localId;
  if (!uid) return { ok: false, response: jsonResponse({ error: 'Firebase user token required.' }, 401) };

  const roleRes = await fetch(`${env.FB_DB_URL}users/${uid}/role.json?auth=${token}`);
  const role = roleRes.ok ? await roleRes.json() : null;
  if (role !== 'admin') {
    return { ok: false, response: jsonResponse({ error: 'Admin role required.' }, 403) };
  }
  return { ok: true, uid };
}

// Per‑isolate caches
let _fbToken = null;
let _fbTokenExpMs = 0;
let _fcmToken = null;
let _fcmTokenExpMs = 0;

// ============================================================
// Subrequest budgets (keep well below 50)
const MAX_ALERTS_TO_PUSH = 1;          // process max 1 new alert per cron tick
const MAX_ESCALATION_CHECKS = 5;       // check up to 5 alerts for escalation
const MAX_AI_FACTORIES = 1;            // assign AI only for one factory per tick
const MAX_FANOUT = 2;                  // max notifications to push via fan-out (cron will skip fan‑out)

// ============================================================
// Firebase auth
// ============================================================
async function getFirebaseToken(env) {
  const now = Date.now();
  if (_fbToken && now < _fbTokenExpMs) return _fbToken;

  if (env?.FIREBASE_SERVICE_ACCOUNT) {
    try {
      const sa = JSON.parse(env.FIREBASE_SERVICE_ACCOUNT);
      const jwt = await createFirebaseAuthJWT(sa.client_email, sa.private_key);
      const url = `https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${env.FB_API_KEY}`;
      const res = await fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ token: jwt, returnSecureToken: true }),
      });
      if (!res.ok) throw new Error(`Auth ${res.status}`);
      const data = await res.json();
      _fbToken = data.idToken;
      _fbTokenExpMs = now + 50 * 60 * 1000; // 50 min
      return _fbToken;
    } catch (e) {
      console.error('[AUTH] Service account failed: ' + e.message);
    }
  }

  // Fallback anonymous
  const url = `https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${env.FB_API_KEY}`;
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ returnSecureToken: true }),
  });
  const data = await res.json();
  _fbToken = data.idToken;
  _fbTokenExpMs = now + 50 * 60 * 1000;
  return _fbToken;
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
    uid: 'worker-escalation',
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

function base64UrlEncode(data) {
  const b64 =
    typeof data === 'string'
      ? btoa(data)
      : btoa(String.fromCharCode(...data));
  return b64.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

// ============================================================
// FCM access token
// ============================================================
async function getFcmAccessToken(env) {
  const now = Date.now();
  if (_fcmToken && now < _fcmTokenExpMs) return _fcmToken;

  const sa = JSON.parse(env.FIREBASE_SERVICE_ACCOUNT);
  const header = { alg: 'RS256', typ: 'JWT' };
  const nowSec = Math.floor(now / 1000);
  const payload = {
    iss: sa.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    exp: nowSec + 3600,
    iat: nowSec,
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
  const data = await res.json();
  if (!data.access_token) throw new Error(`FCM token failed: ${JSON.stringify(data)}`);

  const expiresIn = Number(data.expires_in || 3600);
  _fcmToken = data.access_token;
  _fcmTokenExpMs = now + Math.max(60, expiresIn - 60) * 1000;
  return _fcmToken;
}

// ============================================================
// Core data loader – called ONCE per cron tick, shared across tasks
// ============================================================
async function loadCoreData(env) {
  const token = await getFirebaseToken(env);
  const [alertsRes, usersRes] = await Promise.all([
    fetch(`${env.FB_DB_URL}alerts.json?auth=${token}`),
    fetch(`${env.FB_DB_URL}users.json?auth=${token}`),
  ]);
  return {
    token,
    alertsMap: alertsRes.ok ? ((await alertsRes.json()) || {}) : {},
    usersMap: usersRes.ok ? ((await usersRes.json()) || {}) : {},
  };
}

// ============================================================
// FCM send helper
// ============================================================
async function sendFcm(token, title, body, data, env) {
  try {
    const accessToken = await getFcmAccessToken(env);
    const sa = JSON.parse(env.FIREBASE_SERVICE_ACCOUNT);
    const url = `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`;
    const stringData = Object.fromEntries(
      Object.entries(data || {}).map(([key, value]) => [key, String(value ?? '')]),
    );
    const res = await fetch(url, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        message: {
          token,
          notification: { title, body },
          data: stringData,
          android: {
            priority: 'high',
            notification: { channel_id: 'alerts_high' },
          },
          apns: {
            headers: { 'apns-priority': '10' },
            payload: { aps: { sound: 'default' } },
          },
        },
      }),
    });
    if (!res.ok) {
      const err = await res.text();
      console.error(`[FCM] Send failed (${res.status}):` + err);
    }
    return res.ok;
  } catch (e) {
    console.error('[FCM] Error:' + e.message);
    return false;
  }
}

// ============================================================
// Get FCM tokens for a factory (uses pre‑loaded data, no extra fetch)
// ============================================================
function getFcmTokensForFactory(factoryName, usersMap, alertsMap) {
  const targetId = aiSanitizeFactoryId(factoryName);

  const busySupervisors = new Set();
  for (const a of Object.values(alertsMap)) {
    if (a.status === 'en_cours') {
      if (a.superviseurId) busySupervisors.add(a.superviseurId);
    }
  }

  const tokens = new Set();
  for (const [uid, user] of Object.entries(usersMap)) {
    if (!user || !user.fcmToken) continue;
    if (user.role === 'supervisor') {
      if (busySupervisors.has(uid)) continue;
      const userFid = aiSanitizeFactoryId(user.usine || user.factoryId || '');
      if (userFid !== targetId) continue;
    } else if (user.role !== 'admin') {
      continue;
    }
    tokens.add(user.fcmToken);
  }
  return [...tokens];
}

// ============================================================
// New‑alert FCM push (push_sent flag, ETag‑safe, capped)
// ============================================================
async function processAlerts(env, ctx) {
  const { token, alertsMap, usersMap } = ctx;
  const url = `${env.FB_DB_URL}alerts.json?auth=${token}&orderBy="push_sent"&equalTo=false&limitToFirst=${MAX_ALERTS_TO_PUSH}`;
  const res = await fetch(url);
  if (!res.ok) return;
  const unsentData = await res.json();
  if (!unsentData) return;

  const unsent = Object.entries(unsentData).map(([id, a]) => ({
    id,
    type: a.type || 'Alert',
    usine: a.usine || '',
    description: a.description || '',
  }));

  for (const alert of unsent) {
    const flagUrl = `${env.FB_DB_URL}alerts/${alert.id}/push_sent.json?auth=${token}`;
    const getRes = await fetch(flagUrl, { headers: { 'X-Firebase-ETag': 'true' } });
    if (!getRes.ok) continue;
    const etag = getRes.headers.get('ETag');
    if (!etag) {
      console.error(`[PUSH] Missing ETag for alert ${alert.id}; skipping claim`);
      continue;
    }
    const current = await getRes.json();
    if (current !== false) continue;

    // Firebase RTDB REST ETags give us a compare-and-swap claim. If another
    // worker has already claimed this flag, Firebase returns 412 and this
    // isolate skips the send instead of duplicating the push.
    const claimRes = await fetch(flagUrl, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json', 'if-match': etag },
      body: JSON.stringify('sending'),
    });
    if (claimRes.status === 412 || !claimRes.ok) continue;

    const fcmTokens = getFcmTokensForFactory(alert.usine, usersMap, alertsMap);
    if (fcmTokens.length === 0) {
      await fetch(flagUrl, { method: 'PUT', body: JSON.stringify(false) });
      continue;
    }

    let allOk = true;
    for (const tok of fcmTokens) {
      const ok = await sendFcm(
        tok,
        `🚨 New Alert: ${alert.type}`,
        `${alert.usine} — ${alert.description}`,
        { alertId: alert.id, type: alert.type, usine: alert.usine },
        env,
      );
      if (!ok) allOk = false;
    }

    await fetch(flagUrl, {
      method: 'PUT',
      body: JSON.stringify(allOk ? true : false),
    });
  }
}

// ============================================================
// Escalation check (capped at MAX_ESCALATION_CHECKS)
// ============================================================
async function checkEscalations(env, ctx) {
  const { token, alertsMap, usersMap } = ctx;

  const settingsRes = await fetch(`${env.FB_DB_URL}escalation_settings.json?auth=${token}`);
  if (!settingsRes.ok) {
    console.error('[ESCALATION] Failed to fetch escalation_settings');
    return;
  }
  const settings = await settingsRes.json();
  if (!settings || typeof settings !== 'object') {
    console.error('[ESCALATION] escalation_settings empty or invalid');
    return;
  }

  const now = Date.now();
  let processed = 0;

  for (const [alertId, alert] of Object.entries(alertsMap)) {
    if (processed >= MAX_ESCALATION_CHECKS) break;
    try {
      if (alert.isEscalated === true) { processed++; continue; }
      if (alert.status === 'validee' || alert.status === 'cancelled') { processed++; continue; }

      // Resolve threshold robustly: exact key, lowercase, or default
      let threshold = settings[alert.type] || settings[String(alert.type || '').toLowerCase()];
      if (!threshold && settings.default) threshold = settings.default;
      if (!threshold) { processed++; continue; }

      // Parse creation timestamp
      let createdAtMs;
      if (typeof alert.timestamp === 'number') {
        createdAtMs = alert.timestamp;
      } else if (typeof alert.timestamp === 'string') {
        const parsed = Date.parse(alert.timestamp);
        if (isNaN(parsed)) { processed++; continue; }
        createdAtMs = parsed;
      } else {
        processed++; continue;
      }

      let shouldEscalate = false;
      let reason = '';

      if (alert.status === 'disponible') {
        const mins = (now - createdAtMs) / 60000;
        if (typeof threshold.unclaimedMinutes === 'number' && mins >= threshold.unclaimedMinutes) {
          shouldEscalate = true;
          reason = `Unclaimed for ${Math.floor(mins)} minutes`;
        }
        console.log(`[ESC] check alert=${alertId} status=disponible mins=${Math.floor(mins)} threshold=${threshold.unclaimedMinutes} shouldEsc=${shouldEscalate}`);
      } else if (alert.status === 'en_cours' && alert.takenAtTimestamp) {
        let takenMs;
        if (typeof alert.takenAtTimestamp === 'number') {
          takenMs = alert.takenAtTimestamp;
        } else {
          const parsed = Date.parse(alert.takenAtTimestamp);
          if (isNaN(parsed)) { processed++; continue; }
          takenMs = parsed;
        }
        const mins = (now - takenMs) / 60000;
        if (typeof threshold.claimedMinutes === 'number' && mins >= threshold.claimedMinutes) {
          shouldEscalate = true;
          reason = `Claimed but not resolved for ${Math.floor(mins)} minutes`;
        }
        console.log(`[ESC] check alert=${alertId} status=en_cours mins=${Math.floor(mins)} threshold=${threshold.claimedMinutes} shouldEsc=${shouldEscalate}`);
      } else {
        // Not applicable
        processed++; continue;
      }

      if (!shouldEscalate) { processed++; continue; }

      // Mark escalated and write escalatedAt
      const patchRes = await fetch(`${env.FB_DB_URL}alerts/${alertId}.json?auth=${token}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ isEscalated: true, escalatedAt: new Date().toISOString() }),
      });
      if (!patchRes.ok) {
        console.error(`[ESCALATION] Failed to patch alert ${alertId}: ${patchRes.status}`);
        processed++; continue;
      }

      // Add an aiHistory audit entry to make escalation visible to clients
      try {
        await fetch(`${env.FB_DB_URL}alerts/${alertId}/aiHistory.json?auth=${token}`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ event: 'escalated_worker', reason, timestamp: new Date().toISOString() }),
        });
      } catch (e) {
        console.error('[ESCALATION] Failed to write aiHistory: ' + e.message);
      }

      const escalMsg = `⚠️ Alert Escalated: ${alert.type}`;
      const escalBody = `${alert.usine} — ${alert.description}\n${reason}`;
      const escalData = { alertId, type: alert.type || '', usine: alert.usine || '', escalated: 'true' };

      // Notify idle supervisors + admins in the factory.
      const fcmTokens = getFcmTokensForFactory(alert.usine || '', usersMap, alertsMap);
      for (const tok of fcmTokens) {
        await sendFcm(tok, escalMsg, escalBody, escalData, env);
      }

      // For claimed alerts: also push directly to the claiming supervisor —
      // they are excluded from getFcmTokensForFactory (busy), but they need
      // to know their own alert has escalated.
      if (alert.status === 'en_cours' && alert.superviseurId) {
        const claimant = usersMap[alert.superviseurId];
        const claimantToken = claimant?.fcmToken;
        if (claimantToken && !fcmTokens.includes(claimantToken)) {
          await sendFcm(claimantToken, escalMsg, escalBody, escalData, env);
        }
      }

      console.log(`[ESCALATION] Escalated alert ${alertId} (${alert.type}) reason=${reason}`);
      processed++;
    } catch (e) {
      console.error('[ESCALATION] Error processing alert: ' + e.message);
      processed++;
    }
  }
}

// ============================================================
// Predictive failure engine and morning briefing helpers
// ============================================================
const PREDICT_TYPES = ['qualite', 'maintenance', 'defaut_produit', 'manque_ressource'];
const PREDICT_HORIZON_DAYS = 30;
const PREDICT_HALFLIFE_DAYS = 14;

function _toMs(ts) {
  if (typeof ts === 'number') return ts;
  if (typeof ts === 'string') {
    const parsed = Date.parse(ts);
    return Number.isNaN(parsed) ? null : parsed;
  }
  return null;
}

function buildPredictiveModel(alertsMap) {
  const now = Date.now();
  const horizonMs = PREDICT_HORIZON_DAYS * 86400000;
  const hodCounts = {};
  const recentCounts = {};
  const machineHistory = {};
  const factoryRisk = {};

  for (const type of PREDICT_TYPES) {
    hodCounts[type] = new Array(24).fill(0);
    recentCounts[type] = 0;
  }

  for (const [, alert] of Object.entries(alertsMap || {})) {
    if (!alert) continue;
    const tsMs = _toMs(alert.timestamp);
    if (!tsMs || now - tsMs > horizonMs || tsMs > now) continue;

    const type = String(alert.type || '');
    if (!PREDICT_TYPES.includes(type)) continue;

    const date = new Date(tsMs);
    hodCounts[type][date.getUTCHours()]++;
    recentCounts[type]++;

    const factoryId = aiSanitizeFactoryId(alert.usine || '');
    const conv = alert.convoyeur ?? 0;
    const post = alert.poste ?? 0;
    const key = `${factoryId}|${conv}|${post}|${type}`;
    const ageDays = (now - tsMs) / 86400000;
    const decay = Math.exp(-ageDays / PREDICT_HALFLIFE_DAYS);

    if (!machineHistory[key]) {
      machineHistory[key] = {
        factoryId,
        usine: alert.usine || '',
        convoyeur: conv,
        poste: post,
        type,
        score: 0,
        count: 0,
        lastTs: tsMs,
        firstTs: tsMs,
        critical: 0,
      };
    }

    const machine = machineHistory[key];
    machine.score += decay;
    machine.count++;
    if (alert.isCritical) machine.critical++;
    if (tsMs > machine.lastTs) machine.lastTs = tsMs;
    if (tsMs < machine.firstTs) machine.firstTs = tsMs;

    if (!factoryRisk[factoryId]) {
      factoryRisk[factoryId] = { name: alert.usine || factoryId, score: 0, count: 0 };
    }
    factoryRisk[factoryId].score += decay;
    factoryRisk[factoryId].count++;
  }

  const startHour = new Date(now).getUTCHours();
  const curves = {};
  for (const type of PREDICT_TYPES) {
    const buckets = [];
    let total = 0;
    for (let i = 0; i < 12; i++) {
      const h1 = (startHour + i * 2) % 24;
      const h2 = (startHour + i * 2 + 1) % 24;
      const count = hodCounts[type][h1] + hodCounts[type][h2];
      const lambda = count / PREDICT_HORIZON_DAYS;
      const probability = lambda > 0 ? 1 - Math.exp(-lambda) : 0;
      total += probability;
      buckets.push({
        offsetHours: i * 2,
        startHour: h1,
        endHour: h2,
        probability: Number(probability.toFixed(4)),
        expected: Number(lambda.toFixed(4)),
      });
    }

    const totalRecent = recentCounts[type];
    const dailyAvg = totalRecent / PREDICT_HORIZON_DAYS;
    const peak = buckets.reduce(
      (previous, current) =>
        current.probability > previous.probability ? current : previous,
      buckets[0],
    );

    curves[type] = {
      buckets,
      total24h: Number((1 - Math.exp(-dailyAvg)).toFixed(4)),
      hourlyRate: Number((dailyAvg / 24).toFixed(4)),
      peakHour: peak.startHour,
      peakProbability: peak.probability,
      avgProbability: Number((total / 12).toFixed(4)),
      sampleSize: totalRecent,
    };
  }

  const ranked = Object.values(machineHistory)
    .filter((machine) => machine.count >= 1)
    .sort((a, b) => b.score - a.score)
    .slice(0, 10);
  const maxScore = ranked[0]?.score || 1;
  const predictions = ranked.map((machine) => {
    const ageDays = (now - machine.lastTs) / 86400000;
    const span = Math.max(1, (machine.lastTs - machine.firstTs) / 86400000);
    const meanGap = machine.count > 1 ? span / (machine.count - 1) : null;
    const etaHours = meanGap !== null ? Math.max(0, (meanGap - ageDays) * 24) : null;
    const confidence = Math.min(96, Math.round((machine.score / maxScore) * 88 + 8));
    return {
      factoryId: machine.factoryId,
      usine: machine.usine,
      convoyeur: machine.convoyeur,
      poste: machine.poste,
      type: machine.type,
      confidence,
      pastCount: machine.count,
      criticalCount: machine.critical,
      lastTs: new Date(machine.lastTs).toISOString(),
      etaHours: etaHours !== null ? Number(etaHours.toFixed(1)) : null,
      score: Number(machine.score.toFixed(3)),
    };
  });

  const factoryRanked = Object.entries(factoryRisk)
    .map(([id, value]) => ({
      id,
      name: value.name,
      score: Number(value.score.toFixed(3)),
      count: value.count,
    }))
    .sort((a, b) => b.score - a.score)
    .slice(0, 6);

  return {
    curves,
    predictions,
    factoryRisk: factoryRanked,
    generatedAt: new Date().toISOString(),
    horizonDays: PREDICT_HORIZON_DAYS,
    halflifeDays: PREDICT_HALFLIFE_DAYS,
  };
}

async function refreshPredictionsIfStale(env, ctx, maxAgeMin = 30) {
  const { token, alertsMap } = ctx;
  try {
    const current = await fetch(`${env.FB_DB_URL}ai_predictions/latest.json?auth=${token}`);
    if (current.ok) {
      const data = await current.json();
      if (data?.generatedAt) {
        const age = (Date.now() - Date.parse(data.generatedAt)) / 60000;
        if (!Number.isNaN(age) && age < maxAgeMin) return data;
      }
    }
  } catch (e) {}

  const model = buildPredictiveModel(alertsMap);
  await fetch(`${env.FB_DB_URL}ai_predictions/latest.json?auth=${token}`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(model),
  });
  return model;
}

function _briefingDateKey(date) {
  return `${date.getUTCFullYear()}-${(date.getUTCMonth() + 1)
    .toString()
    .padStart(2, '0')}-${date.getUTCDate().toString().padStart(2, '0')}`;
}

function _aggregateWeek(alertsMap) {
  const now = Date.now();
  const weekMs = 7 * 86400000;
  const stats = {
    total: 0,
    solved: 0,
    pending: 0,
    inProgress: 0,
    critical: 0,
    aiAssigned: 0,
    byType: {},
    byFactory: {},
    avgResolutionMin: 0,
    fastestMin: null,
    slowestMin: null,
  };
  let totalElapsed = 0;
  let solvedCount = 0;

  for (const alert of Object.values(alertsMap || {})) {
    if (!alert) continue;
    const tsMs = _toMs(alert.timestamp);
    if (!tsMs || now - tsMs > weekMs) continue;

    stats.total++;
    if (alert.status === 'validee') {
      stats.solved++;
      if (typeof alert.elapsedTime === 'number' && alert.elapsedTime > 0) {
        totalElapsed += alert.elapsedTime;
        solvedCount++;
        if (stats.fastestMin === null || alert.elapsedTime < stats.fastestMin) {
          stats.fastestMin = alert.elapsedTime;
        }
        if (stats.slowestMin === null || alert.elapsedTime > stats.slowestMin) {
          stats.slowestMin = alert.elapsedTime;
        }
      }
    } else if (alert.status === 'en_cours') {
      stats.inProgress++;
    } else {
      stats.pending++;
    }

    if (alert.isCritical) stats.critical++;
    if (alert.aiAssigned) stats.aiAssigned++;
    const type = String(alert.type || 'other');
    const factory = String(alert.usine || 'unknown');
    stats.byType[type] = (stats.byType[type] || 0) + 1;
    stats.byFactory[factory] = (stats.byFactory[factory] || 0) + 1;
  }

  stats.avgResolutionMin = solvedCount > 0 ? Math.round(totalElapsed / solvedCount) : 0;
  return stats;
}

function _typeName(type) {
  return ({
    qualite: 'Quality',
    maintenance: 'Maintenance',
    defaut_produit: 'Damaged Product',
    manque_ressource: 'Resource Deficiency',
  })[type] || type;
}

async function generateMorningBriefing(env, ctx, force = false) {
  const { token, alertsMap } = ctx;
  const today = _briefingDateKey(new Date());
  if (!force) {
    try {
      const current = await fetch(`${env.FB_DB_URL}ai_briefing/latest.json?auth=${token}`);
      if (current.ok) {
        const data = await current.json();
        if (data?.date === today) return data;
      }
    } catch (e) {}
  }

  const stats = _aggregateWeek(alertsMap);
  const topType = Object.entries(stats.byType).sort((a, b) => b[1] - a[1])[0];
  const topFactory = Object.entries(stats.byFactory).sort((a, b) => b[1] - a[1])[0];
  const resolutionRate =
    stats.total > 0 ? Math.round((stats.solved / stats.total) * 100) : 0;
  const summary =
    `Good morning. Last week the team handled ${stats.total} alerts with a ` +
    `${resolutionRate}% resolution rate and an average response of ` +
    `${stats.avgResolutionMin} minutes. Stay sharp on critical signals today.`;

  const payload = {
    date: today,
    summary,
    generatedAt: new Date().toISOString(),
    model: 'fallback',
    stats,
    topType: topType ? { type: topType[0], count: topType[1] } : null,
    topFactory: topFactory ? { name: topFactory[0], count: topFactory[1] } : null,
    resolutionRate,
  };

  if (env.AI) {
    try {
      const prompt =
        `You are an industrial operations briefing officer. Write one calm, ` +
        `professional paragraph, no bullets. Facts: total alerts ${stats.total}, ` +
        `resolved ${stats.solved}, critical ${stats.critical}, in progress ` +
        `${stats.inProgress}, pending ${stats.pending}, average resolution ` +
        `${stats.avgResolutionMin} minutes, most frequent type ` +
        `${topType ? _typeName(topType[0]) : 'none'}, most active site ` +
        `${topFactory ? topFactory[0] : 'none'}. Begin with Good morning.`;
      const response = await env.AI.run('@cf/meta/llama-3.2-3b-instruct', {
        messages: [{ role: 'user', content: prompt }],
      });
      const output = (response.response || '').trim();
      if (output) {
        payload.summary = output;
        payload.model = '@cf/meta/llama-3.2-3b-instruct';
      }
    } catch (e) {
      console.error('[BRIEFING] AI failed: ' + e.message);
    }
  }

  await fetch(`${env.FB_DB_URL}ai_briefing/latest.json?auth=${token}`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  });
  await fetch(`${env.FB_DB_URL}ai_briefing/history/${today}.json?auth=${token}`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  });
  return payload;
}

async function handlePredictions(env) {
  try {
    const ctx = await loadCoreData(env);
    return jsonResponse(await refreshPredictionsIfStale(env, ctx, 30));
  } catch (e) {
    return jsonResponse({ error: String(e) }, 500);
  }
}

async function handleBriefing(request, env) {
  try {
    const url = new URL(request.url);
    const force = url.searchParams.get('force') === '1';
    const ctx = await loadCoreData(env);
    return jsonResponse(await generateMorningBriefing(env, ctx, force));
  } catch (e) {
    return jsonResponse({ error: String(e) }, 500);
  }
}

// ============================================================
// AI proxy and CI auto-fix endpoints
// ============================================================
async function handleAIRequest(request, env) {
  const fallback = '• Check equipment status.\n• Verify sensor connections.\n• Restart the affected machine.';
  try {
    const { prompt } = await request.json();
    if (!env.AI) return jsonResponse({ suggestion: fallback, note: 'AI binding not configured' });
    const response = await env.AI.run('@cf/meta/llama-3.2-3b-instruct', {
      messages: [{ role: 'user', content: prompt }],
    });
    return jsonResponse({ suggestion: response.response?.trim() || 'No suggestion available' });
  } catch (e) {
    return jsonResponse({ suggestion: fallback, note: String(e) });
  }
}

async function handleAutoFix(request, env) {
  try {
    const { testFile, code, errors } = await request.json();
    if (!env.AI) return jsonResponse({ fixedCode: '', note: 'AI binding not configured' });

    const prompt =
      `You are a Dart/Flutter test repair expert.\n` +
      `Return only the complete fixed Dart source file. No markdown.\n\n` +
      `File: ${testFile}\n\n=== ERRORS ===\n${errors}\n\n` +
      `=== CURRENT FILE ===\n${code}\n\n=== FIXED FILE ===\n`;

    const response = await env.AI.run('@cf/meta/llama-3.2-3b-instruct', {
      messages: [{ role: 'user', content: prompt }],
      max_tokens: 4096,
    });
    return jsonResponse({ fixedCode: (response.response || '').trim() });
  } catch (e) {
    return jsonResponse({ fixedCode: '', note: String(e) }, 500);
  }
}

function extractJsonArray(text) {
  const raw = String(text || '').trim().replace(/^```(?:json)?/i, '').replace(/```$/i, '').trim();
  const start = raw.indexOf('[');
  const end = raw.lastIndexOf(']');
  if (start < 0 || end < start) return [];
  try {
    const parsed = JSON.parse(raw.slice(start, end + 1));
    return Array.isArray(parsed) ? parsed : [];
  } catch (e) {
    return [];
  }
}

async function handleAutoFixFull(request, env) {
  try {
    const { failingTest, errors, files } = await request.json();
    const suppliedFiles = Array.isArray(files) ? files : [];
    const allowedPaths = new Set(
      suppliedFiles
        .map((file) => String(file?.path || ''))
        .filter((path) => path.endsWith('.dart') && !path.includes('..')),
    );

    if (!env.AI || allowedPaths.size === 0) {
      return jsonResponse({ fixedFiles: [], note: 'AI binding not configured or no files supplied' });
    }

    const fileBlock = suppliedFiles
      .filter((file) => allowedPaths.has(String(file.path || '')))
      .map((file) => `=== FILE: ${file.path} ===\n${file.content || ''}`)
      .join('\n\n');

    const prompt =
      `You fix Flutter tests by editing only supplied Dart files.\n` +
      `Return strict JSON only: [{"path":"relative/path.dart","content":"full file content"}].\n` +
      `Do not include markdown. Do not invent file paths.\n\n` +
      `Failing test: ${failingTest}\n\n=== ERRORS ===\n${errors}\n\n${fileBlock}`;

    const response = await env.AI.run('@cf/meta/llama-3.2-3b-instruct', {
      messages: [{ role: 'user', content: prompt }],
      max_tokens: 8192,
    });

    const fixedFiles = extractJsonArray(response.response)
      .filter((file) => allowedPaths.has(String(file?.path || '')) && typeof file.content === 'string')
      .map((file) => ({ path: file.path, content: file.content }));

    return jsonResponse({ fixedFiles });
  } catch (e) {
    return jsonResponse({ fixedFiles: [], note: String(e) }, 500);
  }
}

// ============================================================
// Secured admin account creation
// ============================================================
function requiredString(value) {
  const text = String(value || '').trim();
  return text.isEmpty ? null : text;
}

async function handleCreateSupervisor(request, env) {
  if (request.method !== 'POST') return jsonResponse({ error: 'POST required' }, 405);

  try {
    const token = await getFirebaseToken(env);
    const admin = await requireAdminCaller(request, env, token);
    if (!admin.ok) return admin.response;

    const body = await request.json();
    const firstName = requiredString(body.firstName);
    const lastName = requiredString(body.lastName);
    const email = requiredString(body.email);
    const password = requiredString(body.password);
    const phone = requiredString(body.phone);
    const usine = requiredString(body.usine);
    const hiredDate = requiredString(body.hiredDate) || new Date().toISOString();

    if (!firstName || !lastName || !email || !password || !phone || !usine) {
      return jsonResponse({ error: 'Missing required supervisor fields.' }, 400);
    }

    const createRes = await fetch(
      `https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${env.FB_API_KEY}`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email, password, returnSecureToken: true }),
      },
    );
    const created = await createRes.json();
    if (!createRes.ok || !created.localId) {
      const message = created?.error?.message || `Auth create failed (${createRes.status})`;
      return jsonResponse({ error: message }, 400);
    }

    const uid = created.localId;
    const nowIso = new Date().toISOString();
    const userData = {
      firstName,
      lastName,
      fullName: `${firstName} ${lastName}`,
      email,
      phone,
      role: 'supervisor',
      usine,
      status: 'absent',
      hiredDate,
      lastSeen: nowIso,
      createdAt: nowIso,
      createdBy: admin.uid,
    };

    const writeRes = await fetch(`${env.FB_DB_URL}users/${uid}.json?auth=${token}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(userData),
    });

    if (!writeRes.ok) {
      if (created.idToken) {
        await fetch(
          `https://identitytoolkit.googleapis.com/v1/accounts:delete?key=${env.FB_API_KEY}`,
          {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ idToken: created.idToken }),
          },
        );
      }
      return jsonResponse({ error: 'Supervisor auth user was rolled back after database write failed.' }, 500);
    }

    return jsonResponse({ uid });
  } catch (e) {
    return jsonResponse({ error: String(e) }, 500);
  }
}

// ============================================================
// Gemini proxy
// ============================================================
async function handleGeminiRequest(request, env) {
  const fallback = '• Check equipment status.\n• Verify sensor connections.\n• Restart the affected machine.';
  try {
    const { prompt } = await request.json();
    const key = env.GEMINI_API_KEY;
    if (!key) {
      return new Response(JSON.stringify({ suggestion: fallback, note: 'No API key' }), {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }
    const url = `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=${key}`;
    const res = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ contents: [{ parts: [{ text: prompt }] }] }),
    });
    if (!res.ok) {
      return new Response(JSON.stringify({ suggestion: fallback, note: 'Gemini error' }), {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }
    const data = await res.json();
    const suggestion = data.candidates?.[0]?.content?.parts?.[0]?.text ?? 'No suggestion available';
    return new Response(JSON.stringify({ suggestion }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch {
    return new Response(JSON.stringify({ suggestion: fallback, note: 'Error' }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
}

// Notification types that always reach a supervisor even when they have an
// active alert claimed. Everything else is suppressed while they are busy.
const COLLAB_NOTIF_TYPES = new Set([
  'collaboration_request',
  'collaboration_assistant_accepted',
  'collaboration_assistant_removed',
  'collaboration_removed',
  'collaboration_approved',
  'collaboration_rejected',
  'collaboration_request_admin',
  'assistant_assigned',
]);

// ============================================================
// Fan‑out pending notifications (used only by /notify endpoint, not cron)
// ============================================================
async function fanOutPendingNotifications(env, ctx) {
  const { token, usersMap, alertsMap } = ctx;
  const nowIso = new Date().toISOString();

  // Build the set of supervisors currently handling a claimed alert so we can
  // suppress irrelevant pushes (new alerts, AI assignments, etc.) for them.
  const busySupervisors = new Set();
  for (const a of Object.values(alertsMap || {})) {
    if (a.status === 'en_cours' && a.superviseurId) busySupervisors.add(a.superviseurId);
  }

  const notifRes = await fetch(`${env.FB_DB_URL}notifications.json?auth=${token}`);
  if (!notifRes.ok) return;
  const allNotifs = (await notifRes.json()) || {};

  let processed = 0;

  outer: for (const [uid, bucket] of Object.entries(allNotifs)) {
    if (processed >= MAX_FANOUT) break;
    const user = usersMap[uid];
    const fcmToken = user?.fcmToken;
    if (!fcmToken) continue;

    const isBusySupervisor = user.role === 'supervisor' && busySupervisors.has(uid);

    for (const [notifId, notif] of Object.entries(bucket || {})) {
      if (processed >= MAX_FANOUT) break outer;
      if (!notif || notif.pushSent === true || notif.pushSending === true) continue;

      // Busy supervisors only receive collaboration-related pushes.
      if (isBusySupervisor && !COLLAB_NOTIF_TYPES.has(String(notif.type || ''))) continue;

      const url = `${env.FB_DB_URL}notifications/${uid}/${notifId}.json?auth=${token}`;
      const getRes = await fetch(url, { headers: { 'X-Firebase-ETag': 'true' } });
      if (!getRes.ok) continue;
      const etag = getRes.headers.get('ETag');
      if (!etag) continue;
      const current = await getRes.json();
      if (!current || current.pushSent === true || current.pushSending === true) continue;

      const claimRes = await fetch(url, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json', 'if-match': etag },
        body: JSON.stringify({ ...current, pushSending: true }),
      });
      if (claimRes.status === 412 || !claimRes.ok) continue;

      const title = notifTitle(current.type);
      const body = String(current.message || current.type || 'AlertSys notification');
      const sent = await sendFcm(
        fcmToken,
        title,
        body,
        {
          notificationId: notifId,
          recipientId: uid,
          alertId: String(current.alertId || ''),
          collabRequestId: String(current.collabRequestId || ''),
          type: String(current.type || ''),
        },
        env,
      );

      await fetch(url, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(
          sent
            ? { pushSent: true, pushSentAt: nowIso, pushSending: null }
            : { pushSending: null, pushLastErrorAt: nowIso },
        ),
      });

      processed++;
    }
  }
}

function notifTitle(type) {
  switch (String(type || '')) {
    case 'ai_assigned': return 'AI Assignment';
    case 'collaboration_request': return 'Collaboration request';
    case 'collaboration_assistant_accepted':
    case 'collaboration_assistant_removed':
    case 'collaboration_removed':
    case 'collaboration_approved':
    case 'collaboration_rejected': return 'Collaboration update';
    case 'assistant_assigned': return 'Assistant assigned';
    case 'help_request':
    case 'assistance_request': return 'Help request';
    case 'ai_cross_factory_recommendation': return 'AI recommendation';
    case 'ai_rejection': return 'AI rejection';
    case 'alert_suspended': return 'Alert suspended';
    default: return 'AlertSys';
  }
}

// ============================================================
// Supervisor scoring shared by AI assignment and suggestion endpoints
// ============================================================
function buildSupStats(alertsMap) {
  const stats = {};
  for (const alert of Object.values(alertsMap || {})) {
    if (!alert || alert.status !== 'validee' || alert.elapsedTime == null) continue;
    for (const role of ['superviseurId', 'assistantId']) {
      const id = alert[role];
      if (!id) continue;
      if (!stats[id]) {
        stats[id] = {
          typeCounts: {},
          typeTotalTimes: {},
          stationCounts: {},
          conveyorCounts: {},
        };
      }

      const supStats = stats[id];
      const type = alert.type || '';
      supStats.typeCounts[type] = (supStats.typeCounts[type] || 0) + 1;
      supStats.typeTotalTimes[type] =
        (supStats.typeTotalTimes[type] || 0) + (alert.elapsedTime || 0);
      const stationKey = `${alert.usine || ''}|${alert.convoyeur}|${alert.poste}`;
      const conveyorKey = `${alert.usine || ''}|${alert.convoyeur}`;
      supStats.stationCounts[stationKey] = (supStats.stationCounts[stationKey] || 0) + 1;
      supStats.conveyorCounts[conveyorKey] = (supStats.conveyorCounts[conveyorKey] || 0) + 1;
    }
  }

  for (const id of Object.keys(stats)) {
    const supStats = stats[id];
    supStats.typeAvgRes = {};
    for (const type of Object.keys(supStats.typeTotalTimes)) {
      if (supStats.typeCounts[type] > 0) {
        supStats.typeAvgRes[type] =
          supStats.typeTotalTimes[type] / supStats.typeCounts[type];
      }
    }
  }
  return stats;
}

function scoreSupervisor(sup, alert, stats, feedbackSummary, recentAssignments, now) {
  let score = 0;
  const reasons = [];

  const supFactory = aiResolveFactory(sup);
  const alertFactory = aiResolveFactory(alert);
  if (supFactory && alertFactory && supFactory === alertFactory) {
    score += 30;
    reasons.push('Same factory (+30)');
  } else {
    score -= 25;
    reasons.push('Different factory (-25)');
  }

  const supStats = stats[sup.uid];
  const type = alert.type || '';
  const typeCount = supStats?.typeCounts[type] || 0;
  if (typeCount > 0) {
    const bonus = Math.min(typeCount * 4, 40);
    score += bonus;
    reasons.push(`${typeCount} past ${type} alert${typeCount > 1 ? 's' : ''} resolved (+${bonus})`);
  } else {
    reasons.push(`No prior ${type} experience (0)`);
  }

  const avgTime = supStats?.typeAvgRes?.[type];
  if (avgTime !== undefined && avgTime !== null) {
    const speedBonus = Math.min(Math.max(0, 60 - avgTime), 25);
    score += speedBonus;
    reasons.push(`Avg resolution ${Math.floor(avgTime)}min for ${type} (+${Math.floor(speedBonus)})`);
  }

  const stationKey = `${alert.usine || ''}|${alert.convoyeur}|${alert.poste}`;
  const stationCount = supStats?.stationCounts[stationKey] || 0;
  if (stationCount > 0) {
    const bonus = Math.min(stationCount * 6, 30);
    score += bonus;
    reasons.push(`${stationCount} fix${stationCount > 1 ? 'es' : ''} at this workstation (+${bonus})`);
  }

  const conveyorKey = `${alert.usine || ''}|${alert.convoyeur}`;
  const conveyorCount = supStats?.conveyorCounts[conveyorKey] || 0;
  if (conveyorCount > 0) {
    const bonus = Math.min(conveyorCount * 1.5, 15);
    score += bonus;
    reasons.push(`${conveyorCount} fix${conveyorCount > 1 ? 'es' : ''} on Line ${alert.convoyeur} (+${bonus})`);
  }

  if (!alert.isCritical && recentAssignments > 0) {
    const penalty = recentAssignments * 8;
    score -= penalty;
    reasons.push(`Recent load: ${recentAssignments} assignment${recentAssignments > 1 ? 's' : ''} in 10min (-${penalty})`);
  }

  const feedback = feedbackSummary[sup.uid];
  if (feedback) {
    const accepted = feedback.acceptedAssignments || 0;
    const rejected = feedback.rejectedAssignments || 0;
    const aborted = feedback.abortedAssignments || 0;
    const resolved = feedback.resolvedOutcomes || 0;
    const adjustment = Math.min(
      Math.max(accepted * 2 + resolved * 3 - rejected * 2 - aborted * 1.5, -20),
      20,
    );
    score += adjustment;
    if (adjustment !== 0) {
      reasons.push(`Feedback adjustment (${adjustment > 0 ? '+' : ''}${adjustment})`);
    }
  }

  return { score: Math.max(0, score), reasons };
}

async function handleSuggestAssignee(request, env) {
  try {
    const url = new URL(request.url);
    const alertId = url.searchParams.get('alertId');
    if (!alertId) return jsonResponse({ error: 'alertId required' }, 400);

    const coreCtx = await loadCoreData(env);
    const { token, alertsMap, usersMap } = coreCtx;
    const alert = alertsMap[alertId];
    if (!alert) return jsonResponse({ error: 'alert not found' }, 404);

    let feedbackSummary = {};
    try {
      const feedbackRes = await fetch(`${env.FB_DB_URL}ai_feedback/summary.json?auth=${token}`);
      if (feedbackRes.ok) feedbackSummary = (await feedbackRes.json()) || {};
    } catch (e) {}

    const supStats = buildSupStats(alertsMap);
    const busy = new Set();
    for (const current of Object.values(alertsMap || {})) {
      if (current.status === 'en_cours') {
        if (current.superviseurId) busy.add(current.superviseurId);
        if (current.assistantId) busy.add(current.assistantId);
      }
    }

    const targetFactory = aiResolveFactory(alert);
    const now = Date.now();
    const candidates = [];

    for (const [uid, user] of Object.entries(usersMap || {})) {
      if (!user || user.role !== 'supervisor') continue;
      if (user.aiOptOut === true) continue;
      const userFactory = aiResolveFactory(user);
      if (!targetFactory || !userFactory || userFactory !== targetFactory) continue;

      const recent = Object.values(alertsMap || {}).filter(
        (current) =>
          current.superviseurId === uid &&
          current.takenAtTimestamp &&
          now - new Date(current.takenAtTimestamp).getTime() < 10 * 60 * 1000,
      ).length;

      const name =
        String(user.fullName || '').trim() ||
        `${String(user.firstName || '')} ${String(user.lastName || '')}`.trim();
      const candidate = {
        uid,
        name,
        fcmToken: user.fcmToken,
        usine: user.usine,
        factoryId: user.factoryId,
        status: user.status,
        busy: busy.has(uid),
        avatar: user.avatar || null,
      };
      const { score, reasons } = scoreSupervisor(
        { ...candidate, uid },
        alert,
        supStats,
        feedbackSummary,
        recent,
        now,
      );
      candidates.push({ ...candidate, score, reasons });
    }

    candidates.sort((a, b) => b.score - a.score);
    const top3 = candidates.slice(0, 3);
    const topSum = top3.reduce((sum, candidate) => sum + candidate.score, 0);
    const best = top3[0];
    const confidence = best && topSum > 0 ? Math.min(1.0, best.score / topSum) : 0;

    return jsonResponse({
      alertId,
      best: best
        ? {
            uid: best.uid,
            name: best.name,
            score: best.score,
            reasons: best.reasons,
            busy: best.busy,
            status: best.status,
            avatar: best.avatar,
          }
        : null,
      confidence: Number(confidence.toFixed(2)),
      confidencePct: Math.round(confidence * 100),
      runners: top3.slice(1).map((candidate) => ({
        uid: candidate.uid,
        name: candidate.name,
        score: candidate.score,
        busy: candidate.busy,
      })),
      candidateCount: candidates.length,
      generatedAt: new Date().toISOString(),
    });
  } catch (e) {
    return jsonResponse({ error: String(e) }, 500);
  }
}

// ============================================================
// AI Assignment Engine (capped at MAX_AI_FACTORIES)
// ============================================================
const AI_COOLDOWN_MS = 5 * 60 * 1000;
const AI_ACTIVE_STATUSES = new Set(['active', 'available']);

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

function aiPickSupervisor(usersMap, factoryId, busySet, now) {
  const candidates = [];
  for (const [uid, u] of Object.entries(usersMap || {})) {
    if (!u || u.role !== 'supervisor') continue;
    if (u.aiOptOut === true) continue;
    if (!AI_ACTIVE_STATUSES.has(String(u.status || '').toLowerCase())) continue;
    if (busySet.has(uid)) continue;
    const cooldown = Date.parse(String(u.aiCooldownUntil || ''));
    if (!isNaN(cooldown) && cooldown > now) continue;
    const userFactory = aiResolveFactory(u);
    if (!userFactory || userFactory !== factoryId) continue;
    candidates.push({
      uid,
      name:
        String(u.fullName || '').trim() ||
        `${String(u.firstName || '')} ${String(u.lastName || '')}`.trim() ||
        'Supervisor',
      lastSeen: Date.parse(String(u.lastSeen || '')) || 0,
      fcmToken: String(u.fcmToken || '').trim() || null,
    });
  }
  candidates.sort((a, b) => b.lastSeen - a.lastSeen);
  return candidates[0] || null;
}

async function aiAssignAlert(alertId, supervisor, token, env) {
  const alertUrl = `${env.FB_DB_URL}alerts/${alertId}.json?auth=${token}`;
  const getRes = await fetch(alertUrl, { headers: { 'X-Firebase-ETag': 'true' } });
  if (!getRes.ok) return false;
  const etag = getRes.headers.get('ETag');
  if (!etag) return false;
  const current = await getRes.json();

  if (!current || current.status !== 'disponible' || current.superviseurId) return false;

  const nowIso = new Date().toISOString();
  const putRes = await fetch(alertUrl, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json', 'if-match': etag },
    body: JSON.stringify({
      ...current,
      status: 'en_cours',
      superviseurId: supervisor.uid,
      superviseurName: supervisor.name,
      takenAtTimestamp: nowIso,
      aiAssigned: true,
      aiAssignmentReason: 'Worker auto-assignment',
      aiAssignedAt: nowIso,
    }),
  });

  if (putRes.status === 412 || !putRes.ok) return false;

  // Cooldown starts only after the ETag-protected assignment write succeeds.
  // Failed/raced attempts must not sideline the supervisor.
  const cooldownUntil = new Date(Date.now() + AI_COOLDOWN_MS).toISOString();

  // Write in-app notification + send FCM
  let notifId = null;
  try {
    const notifRes = await fetch(
      `${env.FB_DB_URL}notifications/${supervisor.uid}.json?auth=${token}`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          type: 'ai_assigned',
          alertId,
          alertType: current.type || 'alert',
          alertDescription: current.description || '',
          alertUsine: current.usine || '',
          message: `Auto-assigned by AI: ${current.type || 'alert'}${current.usine ? ` (${current.usine})` : ''}`,
          timestamp: nowIso,
          status: 'pending',
          pushSent: false,
        }),
      },
    );
    if (notifRes.ok) {
      const payload = await notifRes.json();
      notifId = payload?.name ?? null;
    }
  } catch (e) { /* ignore */ }

  if (supervisor.fcmToken) {
    const pushed = await sendFcm(
      supervisor.fcmToken,
      'AI Assignment',
      `Auto-assigned: ${current.type || 'alert'}${current.usine ? ` at ${current.usine}` : ''}`,
      { type: 'ai_assigned', alertId: String(alertId), recipientId: String(supervisor.uid) },
      env,
    );
    if (pushed && notifId) {
      await fetch(
        `${env.FB_DB_URL}notifications/${supervisor.uid}/${notifId}.json?auth=${token}`,
        {
          method: 'PATCH',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ pushSent: true, pushSentAt: nowIso }),
        },
      );
    }
  }

  // Non‑blocking audit
  await Promise.allSettled([
    fetch(`${env.FB_DB_URL}alerts/${alertId}/aiHistory.json?auth=${token}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        event: 'assigned_worker',
        supervisorId: supervisor.uid,
        supervisorName: supervisor.name,
        timestamp: nowIso,
      }),
    }),
    fetch(`${env.FB_DB_URL}ai_decisions/${alertId}.json?auth=${token}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        alertId,
        assignedTo: supervisor.uid,
        assignedToName: supervisor.name,
        decisionMode: 'worker_auto',
        timestamp: nowIso,
      }),
    }),
    fetch(`${env.FB_DB_URL}users/${supervisor.uid}/aiCooldownUntil.json?auth=${token}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(cooldownUntil),
    }),
  ]);

  return true;
}

async function runAIAssignments(env, ctx) {
  const token = ctx?.token ?? (await getFirebaseToken(env));
  let alertsMap, usersMap;

  if (ctx) {
    alertsMap = ctx.alertsMap;
    usersMap = ctx.usersMap;
  } else {
    const [ar, ur] = await Promise.all([
      fetch(`${env.FB_DB_URL}alerts.json?auth=${token}`),
      fetch(`${env.FB_DB_URL}users.json?auth=${token}`),
    ]);
    if (!ar.ok || !ur.ok) return;
    alertsMap = (await ar.json()) || {};
    usersMap = (await ur.json()) || {};
  }

  const busy = new Set();
  for (const a of Object.values(alertsMap)) {
    if (a.status === 'en_cours') {
      if (a.superviseurId) busy.add(a.superviseurId);
      if (a.assistantId) busy.add(a.assistantId);
    }
  }

  const byFactory = {};
  for (const [id, a] of Object.entries(alertsMap)) {
    if (a.status !== 'disponible' || a.superviseurId) continue;
    const fid = aiResolveFactory(a);
    if (!fid) continue;
    if (!byFactory[fid]) byFactory[fid] = [];
    byFactory[fid].push({ id, ...a });
  }

  if (Object.keys(byFactory).length === 0) return;

  const now = Date.now();
  const factoryIds = Object.keys(byFactory);

  // Only process up to MAX_AI_FACTORIES
  for (let i = 0; i < Math.min(factoryIds.length, MAX_AI_FACTORIES); i++) {
    const factoryId = factoryIds[i];
    const enaRes = await fetch(
      `${env.FB_DB_URL}factories/${factoryId}/aiConfig/enabled.json?auth=${token}`,
    );
    const enabled = enaRes.ok ? await enaRes.json() : false;
    if (enabled !== true) continue;

    const factoryAlerts = byFactory[factoryId];
    // Priority: escalated (2) > critical (1) > normal (0), then oldest first.
    factoryAlerts.sort((a, b) => {
      const ap = a.isEscalated ? 2 : (a.isCritical ? 1 : 0);
      const bp = b.isEscalated ? 2 : (b.isCritical ? 1 : 0);
      if (ap !== bp) return bp - ap;
      return (Date.parse(a.timestamp || '') || 0) - (Date.parse(b.timestamp || '') || 0);
    });

    const sup = aiPickSupervisor(usersMap, factoryId, busy, now);
    if (!sup) continue;

    const ok = await aiAssignAlert(factoryAlerts[0].id, sup, token, env);
    if (ok) busy.add(sup.uid);
  }
}

// ============================================================
// /config placeholder
// ============================================================
function handleConfigRequest() {
  return new Response(
    JSON.stringify({ message: 'Config endpoint deprecated' }),
    { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
  );
}

// ============================================================
// Main export — cron does NOT fan‑out notifications
// ============================================================
export default {
  async scheduled(event, env, ctx) {
    ctx.waitUntil(
      (async () => {
        let coreCtx;
        try {
          coreCtx = await loadCoreData(env);
        } catch (e) {
          console.error('[CRON] Failed to load core data: ' + e.message);
          return;
        }
        await processAlerts(env, coreCtx);
        await checkEscalations(env, coreCtx);
        await runAIAssignments(env, coreCtx);
        try { await refreshPredictionsIfStale(env, coreCtx, 30); } catch (e) { console.error('[PREDICT] ' + e.message); }
        try { await generateMorningBriefing(env, coreCtx, false); } catch (e) { console.error('[BRIEFING] ' + e.message); }
        // fan‑out is only called via /notify endpoint now
      })(),
    );
  },

  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: corsHeaders });
    }

    if (url.pathname === '/config') return handleConfigRequest();

    const authError = requireSharedSecret(request, env);
    if (authError) return authError;

    if (url.pathname === '/ai-proxy') return handleAIRequest(request, env);
    if (url.pathname === '/gemini-proxy') return handleGeminiRequest(request, env);
    if (url.pathname === '/auto-fix') return handleAutoFix(request, env);
    if (url.pathname === '/auto-fix-full') return handleAutoFixFull(request, env);
    if (url.pathname === '/predict') return handlePredictions(env);
    if (url.pathname === '/briefing') return handleBriefing(request, env);
    if (url.pathname === '/suggest-assignee') return handleSuggestAssignee(request, env);
    if (url.pathname === '/admin/create-supervisor') return handleCreateSupervisor(request, env);

    if (url.pathname === '/ai-retry') {
      ctx.waitUntil(runAIAssignments(env, null));
      return jsonResponse({ queued: true });
    }

    if (url.pathname === '/notify') {
      ctx.waitUntil(
        (async () => {
          try {
            const coreCtx = await loadCoreData(env);
            await fanOutPendingNotifications(env, coreCtx);
          } catch (e) {
            console.error('[NOTIFY] Fan-out error: ' + e.message);
          }
        })(),
      );
      return jsonResponse({ queued: true });
    }

    // Default / manual trigger: full run except fan‑out (call /notify separately if needed)
    try {
      const coreCtx = await loadCoreData(env);
      await processAlerts(env, coreCtx);
      await checkEscalations(env, coreCtx);
      await runAIAssignments(env, coreCtx);
    } catch (e) {
      console.error('[MANUAL] Error: ' + e.message);
    }
    return jsonResponse({ ok: true });
  },
};

// Test-only named exports. Cloudflare Workers consume only the default export;
// Jest imports these pure helpers directly.
export {
  aiSanitizeFactoryId,
  aiResolveFactory,
  buildSupStats,
  scoreSupervisor,
  buildPredictiveModel,
  notifTitle,
  base64UrlEncode,
  getFcmTokensForFactory,
  _toMs,
  _briefingDateKey,
  _aggregateWeek,
  _typeName,
};

