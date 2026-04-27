// Cloudflare Worker — AlertSys
// Deploy via Cloudflare dashboard: paste into the worker editor, save and deploy.
//
// Required environment variables (set in Worker Settings → Variables):
//   FB_DB_URL              = https://alertappsys-default-rtdb.firebaseio.com/
//   FB_API_KEY             = AIzaSyAr9G-E1G_HDf2DOBoUvoqfuCXBed8mPUM
//   GEMINI_API_KEY         = <your Gemini key>
//   FIREBASE_SERVICE_ACCOUNT = <stringified JSON of your Firebase service account>

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
};

// ---------- Helper: Firebase Auth token ----------
async function getFirebaseToken(env) {
  if (env && env.FIREBASE_SERVICE_ACCOUNT) {
    try {
      const sa = JSON.parse(env.FIREBASE_SERVICE_ACCOUNT);
      const jwt = await createFirebaseAuthJWT(sa.client_email, sa.private_key);
      const url = `https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${env.FB_API_KEY}`;
      const res = await fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ token: jwt, returnSecureToken: true }),
      });
      if (!res.ok) {
        const error = await res.text();
        console.error(`Custom token auth failed: ${res.status} - ${error}`);
        throw new Error('Firebase auth failed');
      }
      const data = await res.json();
      return data.idToken;
    } catch (e) {
      console.error('Service account error, falling back to anonymous sign-up:', e);
    }
  }

  console.warn('No service account, using anonymous sign-up');
  const url = `https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${env.FB_API_KEY}`;
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ returnSecureToken: true }),
  });
  const data = await res.json();
  return data.idToken;
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
  const encodedSignature = base64UrlEncode(new Uint8Array(signature));
  return `${signatureInput}.${encodedSignature}`;
}

async function importPrivateKey(pem) {
  const pemContents = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\s/g, '');
  const binaryDer = Uint8Array.from(atob(pemContents), (c) => c.charCodeAt(0));
  return await crypto.subtle.importKey(
    'pkcs8',
    binaryDer,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
}

function base64UrlEncode(data) {
  let base64;
  if (typeof data === 'string') {
    base64 = btoa(data);
  } else {
    base64 = btoa(String.fromCharCode(...data));
  }
  return base64.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

// ---------- FCM helper: Get OAuth2 access token ----------
async function getFcmAccessToken(env) {
  const sa = JSON.parse(env.FIREBASE_SERVICE_ACCOUNT);
  const jwt = await createFcmJwt(sa);
  const url = 'https://oauth2.googleapis.com/token';
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  });
  const data = await res.json();
  if (!data.access_token) {
    throw new Error(`Failed to get FCM access token: ${JSON.stringify(data)}`);
  }
  return data.access_token;
}

async function createFcmJwt(sa) {
  const header = { alg: 'RS256', typ: 'JWT' };
  const now = Math.floor(Date.now() / 1000);
  const payload = {
    iss: sa.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    exp: now + 3600,
    iat: now,
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
  const encodedSignature = base64UrlEncode(new Uint8Array(signature));
  return `${signatureInput}.${encodedSignature}`;
}

// ---------- Alert processing (FCM push on new alert) ----------
async function fetchUnsentAlerts(authToken, env) {
  const url = `${env.FB_DB_URL}alerts.json?auth=${authToken}&orderBy="push_sent"&equalTo=false&limitToFirst=10`;
  const res = await fetch(url);
  const data = await res.json();
  if (!data) return [];
  return Object.entries(data).map(([id, alert]) => ({
    id,
    type: alert.type || 'Alert',
    usine: alert.usine || 'Unknown plant',
    description: alert.description || 'No description provided',
  }));
}

async function markAlertAsSent(alertId, authToken, env) {
  const url = `${env.FB_DB_URL}alerts/${alertId}/push_sent.json?auth=${authToken}`;
  await fetch(url, { method: 'PUT', body: JSON.stringify(true) });
}

async function getFcmTokensForFactory(authToken, env, factoryName) {
  const [usersRes, alertsRes] = await Promise.all([
    fetch(`${env.FB_DB_URL}users.json?auth=${authToken}`),
    fetch(`${env.FB_DB_URL}alerts.json?auth=${authToken}`),
  ]);
  const usersData = await usersRes.json();
  const alertsData = await alertsRes.json();

  const supervisorsWithClaimedAlerts = new Set();
  if (alertsData) {
    for (const [, alert] of Object.entries(alertsData)) {
      if (alert.status === 'en_cours' && alert.superviseurId) {
        supervisorsWithClaimedAlerts.add(alert.superviseurId);
      }
    }
  }

  const tokens = [];
  if (usersData) {
    for (const [uid, user] of Object.entries(usersData)) {
      if (!user.fcmToken) continue;
      if (user.role === 'supervisor' && supervisorsWithClaimedAlerts.has(uid)) continue;
      if (user.role === 'admin' || (user.role === 'supervisor' && user.usine === factoryName)) {
        tokens.push(user.fcmToken);
      }
    }
  }
  return [...new Set(tokens)];
}

async function sendFcmNotification(token, title, body, dataMap, env) {
  try {
    const accessToken = await getFcmAccessToken(env);
    const sa = JSON.parse(env.FIREBASE_SERVICE_ACCOUNT);
    const projectId = sa.project_id;
    const url = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;
    const fcmPayload = {
      message: {
        token,
        notification: { title, body },
        data: dataMap,
        android: { priority: 'high' },
        apns: { headers: { 'apns-priority': '10' } },
      },
    };
    const res = await fetch(url, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(fcmPayload),
    });
    return res.ok;
  } catch (err) {
    console.error(`FCM send error: ${err.message}`);
    return false;
  }
}

async function processAlerts(env) {
  console.log('Checking for unsent alerts...');
  let authToken;
  try {
    authToken = await getFirebaseToken(env);
  } catch (e) {
    console.error('Auth failed for processAlerts:', e);
    return;
  }
  const unsentAlerts = await fetchUnsentAlerts(authToken, env);
  if (unsentAlerts.length === 0) return;

  for (const alert of unsentAlerts) {
    const tokens = await getFcmTokensForFactory(authToken, env, alert.usine);
    if (tokens.length === 0) continue;
    let allOk = true;
    for (const token of tokens) {
      const ok = await sendFcmNotification(
        token,
        `🚨 New Alert: ${alert.type}`,
        `${alert.usine} - ${alert.description}`,
        { alertId: alert.id, type: alert.type, usine: alert.usine },
        env,
      );
      if (!ok) allOk = false;
    }
    if (allOk) await markAlertAsSent(alert.id, authToken, env);
  }
}

// ---------- Escalation checking ----------
async function fetchEscalationSettings(authToken, env) {
  const url = `${env.FB_DB_URL}escalation_settings.json?auth=${authToken}`;
  const res = await fetch(url);
  if (!res.ok) return null;
  return res.json();
}

async function fetchAllAlerts(authToken, env) {
  const url = `${env.FB_DB_URL}alerts.json?auth=${authToken}`;
  const res = await fetch(url);
  if (!res.ok) return [];
  const data = await res.json();
  if (!data) return [];
  return Object.entries(data).map(([id, alert]) => ({ id, ...alert }));
}

async function markAlertAsEscalated(alertId, authToken, env) {
  const now = new Date().toISOString();
  const url = `${env.FB_DB_URL}alerts/${alertId}.json?auth=${authToken}`;
  await fetch(url, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ isEscalated: true, escalatedAt: now }),
  });
}

async function checkEscalations(env) {
  console.log('Checking for alerts to escalate...');
  let authToken;
  try {
    authToken = await getFirebaseToken(env);
  } catch (e) {
    console.error('Auth failed for escalation check:', e);
    return;
  }

  const settings = await fetchEscalationSettings(authToken, env);
  if (!settings) return;

  const alerts = await fetchAllAlerts(authToken, env);
  const now = Date.now();
  let escalatedCount = 0;

  for (const alert of alerts) {
    if (alert.isEscalated === true) continue;
    if (alert.status === 'validee' || alert.status === 'cancelled') continue;

    let createdAtMs;
    if (typeof alert.timestamp === 'number') {
      createdAtMs = alert.timestamp;
    } else if (typeof alert.timestamp === 'string') {
      let parsed = Date.parse(alert.timestamp);
      if (isNaN(parsed)) continue;
      createdAtMs = parsed > now ? parsed - 3600000 : parsed;
    } else {
      continue;
    }

    const type = alert.type;
    const threshold = settings[type];
    if (!threshold) continue;

    let minutesPassed = 0;
    let shouldEscalate = false;
    let reason = '';

    if (alert.status === 'disponible') {
      minutesPassed = (now - createdAtMs) / 60000;
      if (minutesPassed >= threshold.unclaimedMinutes) {
        shouldEscalate = true;
        reason = `Unclaimed for ${Math.floor(minutesPassed)} minutes`;
      }
    } else if (alert.status === 'en_cours' && alert.takenAtTimestamp) {
      let takenAtMs;
      if (typeof alert.takenAtTimestamp === 'number') {
        takenAtMs = alert.takenAtTimestamp;
      } else if (typeof alert.takenAtTimestamp === 'string') {
        let parsed = Date.parse(alert.takenAtTimestamp);
        if (isNaN(parsed)) continue;
        takenAtMs = parsed > now ? parsed - 3600000 : parsed;
      } else {
        continue;
      }
      minutesPassed = (now - takenAtMs) / 60000;
      if (minutesPassed >= threshold.claimedMinutes) {
        shouldEscalate = true;
        reason = `Claimed but not fixed for ${Math.floor(minutesPassed)} minutes`;
      }
    }

    if (shouldEscalate) {
      await markAlertAsEscalated(alert.id, authToken, env);
      const tokens = await getFcmTokensForFactory(authToken, env, alert.usine);
      for (const token of tokens) {
        await sendFcmNotification(
          token,
          `⚠️ Alert Escalated: ${alert.type}`,
          `${alert.usine} - ${alert.description}\nReason: ${reason}`,
          { alertId: alert.id, type: alert.type, usine: alert.usine, escalated: 'true' },
          env,
        );
      }
      escalatedCount++;
    }
  }
  console.log(`Escalation check done. Escalated ${escalatedCount} alerts.`);
}

// ---------- Gemini proxy ----------
async function handleGeminiRequest(request, env) {
  try {
    const { prompt } = await request.json();
    const GEMINI_API_KEY = env.GEMINI_API_KEY;
    if (!GEMINI_API_KEY) {
      const fallback = '• Check equipment status.\n• Verify sensor connections.\n• Restart the affected machine.';
      return new Response(JSON.stringify({ suggestion: fallback, note: 'Fallback (no API key)' }), {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }
    const url = `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=${GEMINI_API_KEY}`;
    const response = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ contents: [{ parts: [{ text: prompt }] }] }),
    });
    if (!response.ok) {
      const fallback = '• Check the equipment status.\n• Verify sensor connections.\n• Restart the affected machine.';
      return new Response(JSON.stringify({ suggestion: fallback, note: 'Gemini API error' }), {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }
    const data = await response.json();
    const suggestion = data.candidates?.[0]?.content?.parts?.[0]?.text ?? 'No suggestion available';
    return new Response(JSON.stringify({ suggestion }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch {
    const fallback = '• Check equipment status.\n• Verify sensor connections.\n• Restart the affected machine.';
    return new Response(JSON.stringify({ suggestion: fallback, note: 'Internal error' }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
}

// ---------- /config (legacy) ----------
function handleConfigRequest() {
  return new Response(JSON.stringify({ message: 'FCM enabled, config endpoint deprecated' }), {
    status: 200,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

// ======================================================================
// AI Assignment Engine
// ======================================================================

const AI_COOLDOWN_MS = 5 * 60 * 1000; // 5 minutes
const AI_ACTIVE_STATUSES = new Set(['active', 'available']);

function aiSanitizeFactoryId(input) {
  return String(input || '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '');
}

// Mirrors resolveFactoryId from Cloud Functions: prefers factoryId, falls back to usine.
function aiResolveFactory(obj) {
  if (!obj || typeof obj !== 'object') return null;
  const fid = String(obj.factoryId || '').trim();
  if (fid) return aiSanitizeFactoryId(fid);
  const usine = String(obj.usine || '').trim();
  if (usine) return aiSanitizeFactoryId(usine);
  return null;
}

// Pick the most-recently-seen eligible supervisor for a factory.
// Mirrors pickEligibleSupervisor from Cloud Functions.
function aiPickSupervisor(usersMap, factoryId, busySet, now) {
  const candidates = [];
  for (const [uid, u] of Object.entries(usersMap || {})) {
    if (!u || typeof u !== 'object') continue;
    if (u.role !== 'supervisor') continue;
    if (u.aiOptOut === true) continue;
    if (!AI_ACTIVE_STATUSES.has(String(u.status || '').toLowerCase())) continue;
    if (busySet.has(uid)) continue;

    const cooldown = Date.parse(String(u.aiCooldownUntil || ''));
    if (!isNaN(cooldown) && cooldown > now) continue;

    const userFactory = aiResolveFactory(u);
    if (!userFactory || userFactory !== factoryId) continue;

    const lastSeen = Date.parse(String(u.lastSeen || '')) || 0;
    const name =
      String(u.fullName || '').trim() ||
      `${String(u.firstName || '')} ${String(u.lastName || '')}`.trim() ||
      'Supervisor';

    candidates.push({ uid, name, lastSeen });
  }
  // Most recently seen first (mirrors Cloud Function behaviour)
  candidates.sort((a, b) => b.lastSeen - a.lastSeen);
  return candidates[0] || null;
}

// Atomically assign an alert using ETag-based conditional write (RTDB REST).
// Returns true on success, false if the alert was already taken or write failed.
async function aiAssignAlert(alertId, supervisor, authToken, env) {
  const alertUrl = `${env.FB_DB_URL}alerts/${alertId}.json?auth=${authToken}`;

  // GET current state + ETag
  const getRes = await fetch(alertUrl, { headers: { 'X-Firebase-ETag': 'true' } });
  if (!getRes.ok) return false;

  const etag = getRes.headers.get('ETag');
  const current = await getRes.json();

  // Guard: only proceed if still unassigned
  if (!current || current.status !== 'disponible' || current.superviseurId) {
    console.log(`[AI] Alert ${alertId} already taken — skipping`);
    return false;
  }

  const nowIso = new Date().toISOString();

  // Conditional PUT — fails with 412 if another client modified the alert first
  const putRes = await fetch(alertUrl, {
    method: 'PUT',
    headers: {
      'Content-Type': 'application/json',
      'if-match': etag,
    },
    body: JSON.stringify({
      ...current,
      status: 'en_cours',
      superviseurId: supervisor.uid,
      superviseurName: supervisor.name,
      takenAtTimestamp: nowIso,
      aiAssigned: true,
      aiAssignmentReason: 'Worker retry',
      aiAssignedAt: nowIso,
    }),
  });

  if (putRes.status === 412) {
    console.log(`[AI] Alert ${alertId} was modified concurrently — skipping`);
    return false;
  }
  if (!putRes.ok) {
    console.error(`[AI] Assignment PUT failed: ${putRes.status}`);
    return false;
  }

  const cooldownUntil = new Date(Date.now() + AI_COOLDOWN_MS).toISOString();

  // Post-assignment writes (non-blocking — we don't fail if these error)
  await Promise.allSettled([
    // In-app notification for assigned supervisor
    fetch(`${env.FB_DB_URL}notifications/${supervisor.uid}.json?auth=${authToken}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        type: 'ai_assigned',
        alertId,
        alertType: current.type || 'alert',
        alertDescription: current.description || '',
        alertUsine: current.usine || '',
        message: `Auto-assigned by AI`,
        aiAssigned: true,
        timestamp: nowIso,
        status: 'pending',
      }),
    }),
    // Audit trail in aiHistory
    fetch(`${env.FB_DB_URL}alerts/${alertId}/aiHistory.json?auth=${authToken}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        event: 'assigned_worker',
        supervisorId: supervisor.uid,
        supervisorName: supervisor.name,
        timestamp: nowIso,
      }),
    }),
    // Decision snapshot
    fetch(`${env.FB_DB_URL}ai_decisions/${alertId}.json?auth=${authToken}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        alertId,
        assignedTo: supervisor.uid,
        assignedToName: supervisor.name,
        decisionMode: 'worker_retry',
        timestamp: nowIso,
      }),
    }),
    // Write aiCooldownUntil so the cron respects cooldown on next tick
    fetch(`${env.FB_DB_URL}users/${supervisor.uid}/aiCooldownUntil.json?auth=${authToken}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(cooldownUntil),
    }),
  ]);

  return true;
}

// Main AI assignment routine.
// - Reads all alerts and users once.
// - Groups unassigned (disponible, no superviseurId) alerts by factory.
// - For each factory: checks AI enabled, picks oldest/most-critical alert,
//   picks best eligible supervisor, assigns one alert.
// - Assigns at most one alert per factory per invocation (prevents spam).
async function runAIAssignments(env) {
  console.log('[AI] Assignment check start');
  let token;
  try {
    token = await getFirebaseToken(env);
  } catch (e) {
    console.error('[AI] Auth error:', e);
    return;
  }

  const [alertsRes, usersRes] = await Promise.all([
    fetch(`${env.FB_DB_URL}alerts.json?auth=${token}`),
    fetch(`${env.FB_DB_URL}users.json?auth=${token}`),
  ]);

  if (!alertsRes.ok || !usersRes.ok) {
    console.error('[AI] Failed to load data');
    return;
  }

  const alertsMap = (await alertsRes.json()) || {};
  const usersMap = (await usersRes.json()) || {};

  // Build the set of supervisors already handling an alert
  const busy = new Set();
  for (const a of Object.values(alertsMap)) {
    if (a.status === 'en_cours') {
      if (a.superviseurId) busy.add(a.superviseurId);
      if (a.assistantId) busy.add(a.assistantId);
    }
  }

  // Group unassigned disponible alerts by factory
  const byFactory = {};
  for (const [id, a] of Object.entries(alertsMap)) {
    if (a.status !== 'disponible' || a.superviseurId) continue;
    const fid = aiResolveFactory(a);
    if (!fid) continue;
    if (!byFactory[fid]) byFactory[fid] = [];
    byFactory[fid].push({ id, ...a });
  }

  if (Object.keys(byFactory).length === 0) {
    console.log('[AI] No unassigned alerts');
    return;
  }

  const now = Date.now();

  for (const [factoryId, factoryAlerts] of Object.entries(byFactory)) {
    // Check if AI is enabled for this factory
    const enaRes = await fetch(
      `${env.FB_DB_URL}factories/${factoryId}/aiConfig/enabled.json?auth=${token}`,
    );
    const enabled = enaRes.ok ? await enaRes.json() : false;
    if (enabled !== true) {
      console.log(`[AI] Disabled for factory ${factoryId}`);
      continue;
    }

    // Sort: critical first, then oldest by timestamp
    factoryAlerts.sort((a, b) => {
      if (!!a.isCritical !== !!b.isCritical) return a.isCritical ? -1 : 1;
      const tsA = Date.parse(a.timestamp || a.createdAt || '') || 0;
      const tsB = Date.parse(b.timestamp || b.createdAt || '') || 0;
      return tsA - tsB;
    });

    const oldest = factoryAlerts[0];
    const sup = aiPickSupervisor(usersMap, factoryId, busy, now);

    if (!sup) {
      console.log(`[AI] No eligible supervisor for factory ${factoryId} (alert ${oldest.id})`);
      continue;
    }

    const ok = await aiAssignAlert(oldest.id, sup, token, env);
    if (ok) {
      busy.add(sup.uid); // Prevent assigning same supervisor to another factory this tick
      console.log(`[AI] ✅ Assigned ${oldest.id} → ${sup.name} (factory: ${factoryId})`);
    }
  }

  console.log('[AI] Assignment check done');
}

// ======================================================================
// Main export
// ======================================================================

export default {
  // Runs on the cron schedule defined in wrangler.toml.
  // Recommended schedule: every 1 minute → "* * * * *"
  // This covers cooldown expiry within 60 seconds of it happening.
  async scheduled(event, env, ctx) {
    console.log('Cron started');
    ctx.waitUntil(
      Promise.all([
        processAlerts(env),
        checkEscalations(env),
        runAIAssignments(env),
      ]),
    );
  },

  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: corsHeaders });
    }

    if (url.pathname === '/config') {
      return handleConfigRequest();
    }

    if (url.pathname === '/gemini-proxy') {
      return handleGeminiRequest(request, env);
    }

    // Event-driven trigger from the Flutter app.
    // Called on: supervisor login, alert resolved, alert returned to queue.
    // Fire-and-forget from client side — responds immediately.
    if (url.pathname === '/ai-retry') {
      ctx.waitUntil(runAIAssignments(env));
      return new Response(JSON.stringify({ queued: true }), {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // Default: manual trigger runs everything
    await Promise.all([
      processAlerts(env),
      checkEscalations(env),
      runAIAssignments(env),
    ]);
    return new Response('OK', { status: 200, headers: corsHeaders });
  },
};
