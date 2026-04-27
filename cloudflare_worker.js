// Cloudflare Worker — AlertSys
// Deploy via Cloudflare dashboard: paste into the worker editor, save and deploy.
//
// Required environment variables (set in Worker Settings → Variables):
//   FB_DB_URL                = https://alertappsys-default-rtdb.firebaseio.com/
//   FB_API_KEY               = AIzaSyAr9G-E1G_HDf2DOBoUvoqfuCXBed8mPUM
//   GEMINI_API_KEY           = <your Gemini key>
//   FIREBASE_SERVICE_ACCOUNT = <stringified JSON of your Firebase service account>
//
// Cron schedule: "* * * * *" (every minute)
// Free-plan subrequest budget: 50 per invocation.
// Worst-case cron budget:
//   1 (auth) + 2 (data) + 7 (processAlerts 1 alert) + 5 (checkEscalations 1)
//   + 17 (runAIAssignments 2 factories) + 13 (fanOut 3 notifs) = 45 ✅

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
};

// Per-isolate caches — survive across requests in the same isolate.
let _fbToken = null;
let _fbTokenExpMs = 0;
let _fcmToken = null;
let _fcmTokenExpMs = 0;

// ============================================================
// Firebase auth — cached per isolate (50-minute TTL)
// ============================================================
async function getFirebaseToken(env) {
  const now = Date.now();
  if (_fbToken && now < _fbTokenExpMs) return _fbToken;

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
      if (!res.ok) throw new Error(`Auth ${res.status}`);
      const data = await res.json();
      _fbToken = data.idToken;
      _fbTokenExpMs = now + 50 * 60 * 1000; // 50 min
      return _fbToken;
    } catch (e) {
      console.error('[AUTH] Service account failed, trying anon:', e.message);
    }
  }

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
// FCM access token — cached per isolate
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
// Core data loader — call ONCE per cron tick, share the result
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
// FCM send
// ============================================================
async function sendFcm(token, title, body, data, env) {
  try {
    const accessToken = await getFcmAccessToken(env);
    const sa = JSON.parse(env.FIREBASE_SERVICE_ACCOUNT);
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
          notification: { title, body },
          data,
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
      console.error(`[FCM] Send failed (${res.status}):`, err);
    }
    return res.ok;
  } catch (e) {
    console.error('[FCM] Error:', e.message);
    return false;
  }
}

// ============================================================
// Get FCM tokens for a factory (uses pre-loaded data — no extra fetches)
// Excludes supervisors who already have a claimed alert.
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
// New-alert FCM push (push_sent flag, ETag-safe)
// Cap: 2 alerts per cron tick so they don't blow the budget.
// ============================================================
async function processAlerts(env, ctx) {
  const { token, alertsMap, usersMap } = ctx;

  // Fetch only alerts with push_sent === false (separate ordered query)
  const url = `${env.FB_DB_URL}alerts.json?auth=${token}&orderBy="push_sent"&equalTo=false&limitToFirst=2`;
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
    // ETag-claim to avoid double-sending
    const flagUrl = `${env.FB_DB_URL}alerts/${alert.id}/push_sent.json?auth=${token}`;
    const getRes = await fetch(flagUrl, { headers: { 'X-Firebase-ETag': 'true' } });
    if (!getRes.ok) continue;
    const etag = getRes.headers.get('ETag');
    const current = await getRes.json();
    if (current !== false) continue; // already claimed or sent

    const claimRes = await fetch(flagUrl, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json', 'if-match': etag },
      body: JSON.stringify('sending'),
    });
    if (claimRes.status === 412 || !claimRes.ok) continue;

    const fcmTokens = getFcmTokensForFactory(alert.usine, usersMap, alertsMap);
    if (fcmTokens.length === 0) {
      // Release claim so next tick tries again
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
// Escalation check (uses pre-loaded data)
// ============================================================
async function checkEscalations(env, ctx) {
  const { token, alertsMap, usersMap } = ctx;

  const settingsRes = await fetch(`${env.FB_DB_URL}escalation_settings.json?auth=${token}`);
  if (!settingsRes.ok) return;
  const settings = await settingsRes.json();
  if (!settings) return;

  const now = Date.now();
  let escalatedCount = 0;

  for (const [alertId, alert] of Object.entries(alertsMap)) {
    if (alert.isEscalated === true) continue;
    if (alert.status === 'validee' || alert.status === 'cancelled') continue;

    const threshold = settings[alert.type];
    if (!threshold) continue;

    let createdAtMs;
    if (typeof alert.timestamp === 'number') {
      createdAtMs = alert.timestamp;
    } else if (typeof alert.timestamp === 'string') {
      const parsed = Date.parse(alert.timestamp);
      if (isNaN(parsed)) continue;
      createdAtMs = parsed > now ? parsed - 3600000 : parsed;
    } else {
      continue;
    }

    let shouldEscalate = false;
    let reason = '';

    if (alert.status === 'disponible') {
      const mins = (now - createdAtMs) / 60000;
      if (mins >= threshold.unclaimedMinutes) {
        shouldEscalate = true;
        reason = `Unclaimed for ${Math.floor(mins)} minutes`;
      }
    } else if (alert.status === 'en_cours' && alert.takenAtTimestamp) {
      let takenMs;
      if (typeof alert.takenAtTimestamp === 'number') {
        takenMs = alert.takenAtTimestamp;
      } else {
        const parsed = Date.parse(alert.takenAtTimestamp);
        if (isNaN(parsed)) continue;
        takenMs = parsed > now ? parsed - 3600000 : parsed;
      }
      const mins = (now - takenMs) / 60000;
      if (mins >= threshold.claimedMinutes) {
        shouldEscalate = true;
        reason = `Claimed but not resolved for ${Math.floor(mins)} minutes`;
      }
    }

    if (!shouldEscalate) continue;

    await fetch(`${env.FB_DB_URL}alerts/${alertId}.json?auth=${token}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ isEscalated: true, escalatedAt: new Date().toISOString() }),
    });

    const fcmTokens = getFcmTokensForFactory(alert.usine || '', usersMap, alertsMap);
    for (const tok of fcmTokens) {
      await sendFcm(
        tok,
        `⚠️ Alert Escalated: ${alert.type}`,
        `${alert.usine} — ${alert.description}\n${reason}`,
        { alertId, type: alert.type || '', usine: alert.usine || '', escalated: 'true' },
        env,
      );
    }
    escalatedCount++;
  }

  if (escalatedCount > 0) console.log(`[ESCALATION] Escalated ${escalatedCount} alert(s).`);
}

// ============================================================
// Gemini proxy
// ============================================================
async function handleGeminiRequest(request, env) {
  try {
    const { prompt } = await request.json();
    const key = env.GEMINI_API_KEY;
    const fallback = '• Check equipment status.\n• Verify sensor connections.\n• Restart the affected machine.';
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
    const fallback = '• Check equipment status.\n• Verify sensor connections.\n• Restart the affected machine.';
    return new Response(JSON.stringify({ suggestion: fallback, note: 'Error' }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
}

// ============================================================
// Fan-out: scan notifications/{uid}/{notifId} for pushSent !== true
// and send FCM. Cap: 3 per invocation to stay under subrequest limit.
// Called from cron and from /notify endpoint.
// ============================================================
const MAX_FANOUT = 3;

async function fanOutPendingNotifications(env, ctx) {
  const { token, usersMap } = ctx;
  const nowIso = new Date().toISOString();

  const notifRes = await fetch(`${env.FB_DB_URL}notifications.json?auth=${token}`);
  if (!notifRes.ok) return;
  const allNotifs = (await notifRes.json()) || {};

  let processed = 0;

  outer: for (const [uid, bucket] of Object.entries(allNotifs)) {
    if (processed >= MAX_FANOUT) break;
    const user = usersMap[uid];
    const fcmToken = user?.fcmToken;
    if (!fcmToken) continue;

    for (const [notifId, notif] of Object.entries(bucket || {})) {
      if (processed >= MAX_FANOUT) break outer;
      if (!notif || notif.pushSent === true || notif.pushSending === true) continue;

      // ETag-claim to prevent double-send
      const url = `${env.FB_DB_URL}notifications/${uid}/${notifId}.json?auth=${token}`;
      const getRes = await fetch(url, { headers: { 'X-Firebase-ETag': 'true' } });
      if (!getRes.ok) continue;
      const etag = getRes.headers.get('ETag');
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

  if (processed >= MAX_FANOUT) {
    console.log(`[NOTIFY] Fan-out capped at ${MAX_FANOUT} — next tick continues`);
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
// AI Assignment Engine
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

// Pick most-recently-seen eligible supervisor for a factory (same-factory only).
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

// Atomic ETag-based assignment. Uses PATCH on separate fields after the PUT
// to avoid overwriting aiHistory (which is a child node, not a scalar).
async function aiAssignAlert(alertId, supervisor, token, env) {
  const alertUrl = `${env.FB_DB_URL}alerts/${alertId}.json?auth=${token}`;

  const getRes = await fetch(alertUrl, { headers: { 'X-Firebase-ETag': 'true' } });
  if (!getRes.ok) return false;
  const etag = getRes.headers.get('ETag');
  const current = await getRes.json();

  if (!current || current.status !== 'disponible' || current.superviseurId) {
    console.log(`[AI] Alert ${alertId} already taken — skipping`);
    return false;
  }

  const nowIso = new Date().toISOString();

  // PATCH only the fields we want to change — leaves aiHistory child intact.
  const patchRes = await fetch(alertUrl, {
    method: 'PATCH',
    headers: {
      'Content-Type': 'application/json',
      'if-match': etag,
    },
    body: JSON.stringify({
      status: 'en_cours',
      superviseurId: supervisor.uid,
      superviseurName: supervisor.name,
      takenAtTimestamp: nowIso,
      aiAssigned: true,
      aiAssignmentReason: 'Worker auto-assignment',
      aiAssignedAt: nowIso,
    }),
  });

  if (patchRes.status === 412) {
    console.log(`[AI] Alert ${alertId} concurrently modified — skipping`);
    return false;
  }
  if (!patchRes.ok) {
    console.error(`[AI] Assignment PATCH failed: ${patchRes.status}`);
    return false;
  }

  const cooldownUntil = new Date(Date.now() + AI_COOLDOWN_MS).toISOString();

  // Write in-app notification + push FCM immediately.
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
  } catch (e) {
    console.error('[AI] Notification write failed:', e.message);
  }

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

  // Non-blocking audit trail
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

// Main AI routine. Accepts an optional pre-loaded ctx to save subrequests in cron.
// When called from /ai-retry (no ctx), fetches its own fresh data.
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
    if (!ar.ok || !ur.ok) { console.error('[AI] Failed to load data'); return; }
    alertsMap = (await ar.json()) || {};
    usersMap = (await ur.json()) || {};
  }

  // Supervisors busy with an in-progress alert
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
    const enaRes = await fetch(
      `${env.FB_DB_URL}factories/${factoryId}/aiConfig/enabled.json?auth=${token}`,
    );
    const enabled = enaRes.ok ? await enaRes.json() : false;
    if (enabled !== true) {
      console.log(`[AI] Disabled for factory ${factoryId}`);
      continue;
    }

    factoryAlerts.sort((a, b) => {
      if (!!a.isCritical !== !!b.isCritical) return a.isCritical ? -1 : 1;
      return (Date.parse(a.timestamp || '') || 0) - (Date.parse(b.timestamp || '') || 0);
    });

    const sup = aiPickSupervisor(usersMap, factoryId, busy, now);
    if (!sup) {
      console.log(`[AI] No eligible supervisor for ${factoryId}`);
      continue;
    }

    const ok = await aiAssignAlert(factoryAlerts[0].id, sup, token, env);
    if (ok) {
      busy.add(sup.uid);
      console.log(`[AI] ✅ Assigned ${factoryAlerts[0].id} → ${sup.name} (factory: ${factoryId})`);
    }
  }
}

// ============================================================
// /config legacy
// ============================================================
function handleConfigRequest() {
  return new Response(
    JSON.stringify({ message: 'Config endpoint deprecated' }),
    { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
  );
}

// ============================================================
// Main export
// ============================================================
export default {
  // Cron: every minute ("* * * * *" in wrangler.toml)
  // Loads data ONCE, shares across all functions to stay under 50 subrequests.
  async scheduled(event, env, ctx) {
    ctx.waitUntil(
      (async () => {
        let coreCtx;
        try {
          coreCtx = await loadCoreData(env);
        } catch (e) {
          console.error('[CRON] Failed to load core data:', e.message);
          return;
        }
        await processAlerts(env, coreCtx);
        await checkEscalations(env, coreCtx);
        await runAIAssignments(env, coreCtx);
        await fanOutPendingNotifications(env, coreCtx);
      })(),
    );
  },

  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: corsHeaders });
    }

    if (url.pathname === '/config') return handleConfigRequest();

    if (url.pathname === '/gemini-proxy') return handleGeminiRequest(request, env);

    // Event-driven AI retry (lean — no fan-out, no processAlerts).
    // Called by Flutter on: login, alert resolved, alert returned to queue.
    if (url.pathname === '/ai-retry') {
      ctx.waitUntil(runAIAssignments(env, null));
      return new Response(JSON.stringify({ queued: true }), {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // On-demand notification fan-out — called by Flutter after writing a
    // cross-user notification (collaboration request, help request, etc.).
    if (url.pathname === '/notify') {
      ctx.waitUntil(
        (async () => {
          try {
            const coreCtx = await loadCoreData(env);
            await fanOutPendingNotifications(env, coreCtx);
          } catch (e) {
            console.error('[NOTIFY] Fan-out error:', e.message);
          }
        })(),
      );
      return new Response(JSON.stringify({ queued: true }), {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // Default / manual trigger: run everything.
    try {
      const coreCtx = await loadCoreData(env);
      await processAlerts(env, coreCtx);
      await checkEscalations(env, coreCtx);
      await runAIAssignments(env, coreCtx);
      await fanOutPendingNotifications(env, coreCtx);
    } catch (e) {
      console.error('[MANUAL] Error:', e.message);
    }
    return new Response('OK', { status: 200, headers: corsHeaders });
  },
};
