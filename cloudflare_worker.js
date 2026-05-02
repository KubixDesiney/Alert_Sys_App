// Cloudflare Worker – AlertSys (Full AI scoring, escalation, push, fan-out)
// Schedule: * * * * * (every minute)

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
};

// ---------- Auth cache ----------
let _fbToken = null;
let _fbTokenExpMs = 0;
let _fcmToken = null;
let _fcmTokenExpMs = 0;

const MAX_ALERTS_TO_PUSH = 1;
const MAX_ESCALATION_CHECKS = 5;
const MAX_AI_FACTORIES = 1;
const MAX_FANOUT = 2;

// ============================================================
// Firebase Auth
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
      _fbTokenExpMs = now + 50 * 60 * 1000;
      return _fbToken;
    } catch (e) {
      console.error('[AUTH] Service account failed: ' + e.message);
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
          data: { ...stringData, title, body },
          android: {
            priority: 'high',
          },
          apns: {
            headers: { 'apns-priority': '10' },
            payload: {
              aps: {
                contentAvailable: true,
                sound: 'default',
              },
            },
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
// Core data loader (shared across tasks)
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
// FCM tokens for a factory
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
// New-alert FCM push
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
    const flagUrl = `${env.FB_DB_URL}alerts/${alert.id}/push_sent.json?auth=${env.FB_DB_SECRET}`;

    const getRes = await fetch(flagUrl, { headers: { 'X-Firebase-ETag': 'true' } });
    if (!getRes.ok) continue;
    const etag = getRes.headers.get('ETag');
    const current = await getRes.json();
    if (current !== false) continue;

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
        {
          alertId: alert.id,
          type: alert.type,
          usine: alert.usine,
          voiceAction: 'true',
        },
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
// Escalation check
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

      let threshold = settings[alert.type] || settings[String(alert.type || '').toLowerCase()];
      if (!threshold && settings.default) threshold = settings.default;
      if (!threshold) { processed++; continue; }

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
      } else {
        processed++; continue;
      }

      if (!shouldEscalate) { processed++; continue; }

      const patchRes = await fetch(`${env.FB_DB_URL}alerts/${alertId}.json?auth=${token}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ isEscalated: true, escalatedAt: new Date().toISOString() }),
      });
      if (!patchRes.ok) {
        console.error(`[ESCALATION] Failed to patch alert ${alertId}: ${patchRes.status}`);
        processed++; continue;
      }

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
      const escalData = { alertId, type: alert.type || '', usine: alert.usine || '', escalated: 'true', voiceAction: 'true' };

      const fcmTokens = getFcmTokensForFactory(alert.usine || '', usersMap, alertsMap);
      for (const tok of fcmTokens) {
        await sendFcm(tok, escalMsg, escalBody, escalData, env);
      }

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
// PREDICTIVE FAILURE ENGINE — historical pattern ML
// Uses Poisson + exponential-decay model on the last 30 days of alerts
// to forecast the next 24h risk per type and per (factory, line, station).
// ============================================================
const PREDICT_TYPES = ['qualite', 'maintenance', 'defaut_produit', 'manque_ressource'];
const PREDICT_HORIZON_DAYS = 30;
const PREDICT_HALFLIFE_DAYS = 14;

function _toMs(ts) {
  if (typeof ts === 'number') return ts;
  if (typeof ts === 'string') {
    const p = Date.parse(ts);
    return isNaN(p) ? null : p;
  }
  return null;
}

function buildPredictiveModel(alertsMap) {
  const now = Date.now();
  const horizonMs = PREDICT_HORIZON_DAYS * 86400000;

  const hodCounts = {};
  const dowCounts = {};
  const recentCounts = {};
  const machineHistory = {};
  const factoryRisk = {};

  for (const t of PREDICT_TYPES) {
    hodCounts[t] = new Array(24).fill(0);
    dowCounts[t] = new Array(7).fill(0);
    recentCounts[t] = 0;
  }

  for (const [, a] of Object.entries(alertsMap || {})) {
    if (!a) continue;
    const tsMs = _toMs(a.timestamp);
    if (!tsMs || (now - tsMs) > horizonMs || tsMs > now) continue;
    const type = String(a.type || '');
    if (!PREDICT_TYPES.includes(type)) continue;

    const d = new Date(tsMs);
    const hod = d.getUTCHours();
    const dow = d.getUTCDay();
    hodCounts[type][hod]++;
    dowCounts[type][dow]++;
    recentCounts[type]++;

    const factoryId = aiSanitizeFactoryId(a.usine || '');
    const conv = a.convoyeur ?? 0;
    const post = a.poste ?? 0;
    const mKey = `${factoryId}|${conv}|${post}|${type}`;
    const ageDays = (now - tsMs) / 86400000;
    const decay = Math.exp(-ageDays / PREDICT_HALFLIFE_DAYS);
    if (!machineHistory[mKey]) {
      machineHistory[mKey] = {
        factoryId,
        usine: a.usine || '',
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
    const m = machineHistory[mKey];
    m.score += decay;
    m.count++;
    if (a.isCritical) m.critical++;
    if (tsMs > m.lastTs) m.lastTs = tsMs;
    if (tsMs < m.firstTs) m.firstTs = tsMs;

    if (!factoryRisk[factoryId]) factoryRisk[factoryId] = { name: a.usine || factoryId, score: 0, count: 0 };
    factoryRisk[factoryId].score += decay;
    factoryRisk[factoryId].count++;
  }

  // Build 24h prediction curve per type — 12 buckets × 2h
  const startHour = new Date(now).getUTCHours();
  const curves = {};
  for (const type of PREDICT_TYPES) {
    const buckets = [];
    let total = 0;
    for (let i = 0; i < 12; i++) {
      const h1 = (startHour + i * 2) % 24;
      const h2 = (startHour + i * 2 + 1) % 24;
      const cnt = hodCounts[type][h1] + hodCounts[type][h2];
      const lambda = cnt / PREDICT_HORIZON_DAYS;
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
    const peak = buckets.reduce((p, c) => (c.probability > p.probability ? c : p), buckets[0]);
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

  // Top-N predicted machine failures
  const ranked = Object.values(machineHistory)
    .filter((m) => m.count >= 1)
    .sort((a, b) => b.score - a.score)
    .slice(0, 10);

  const maxScore = ranked[0]?.score || 1;
  const predictions = ranked.map((m) => {
    const ageDays = (now - m.lastTs) / 86400000;
    const span = Math.max(1, (m.lastTs - m.firstTs) / 86400000);
    const meanGap = m.count > 1 ? span / (m.count - 1) : null;
    const etaHours = meanGap !== null ? Math.max(0, (meanGap - ageDays) * 24) : null;
    const confidence = Math.min(96, Math.round((m.score / maxScore) * 88 + 8));
    return {
      factoryId: m.factoryId,
      usine: m.usine,
      convoyeur: m.convoyeur,
      poste: m.poste,
      type: m.type,
      confidence,
      pastCount: m.count,
      criticalCount: m.critical,
      lastTs: new Date(m.lastTs).toISOString(),
      etaHours: etaHours !== null ? Number(etaHours.toFixed(1)) : null,
      score: Number(m.score.toFixed(3)),
    };
  });

  // Factory ranking
  const factoryRanked = Object.entries(factoryRisk)
    .map(([id, v]) => ({ id, name: v.name, score: Number(v.score.toFixed(3)), count: v.count }))
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
    const cur = await fetch(`${env.FB_DB_URL}ai_predictions/latest.json?auth=${token}`);
    if (cur.ok) {
      const data = await cur.json();
      if (data?.generatedAt) {
        const age = (Date.now() - Date.parse(data.generatedAt)) / 60000;
        if (!isNaN(age) && age < maxAgeMin) return data;
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

// ============================================================
// MORNING BRIEFING — Llama 3.2 3B summary, written daily
// ============================================================
function _briefingDateKey(d) {
  return `${d.getUTCFullYear()}-${(d.getUTCMonth() + 1).toString().padStart(2, '0')}-${d.getUTCDate().toString().padStart(2, '0')}`;
}

function _aggregateWeek(alertsMap) {
  const now = Date.now();
  const WEEK = 7 * 86400000;
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
  for (const a of Object.values(alertsMap || {})) {
    if (!a) continue;
    const tsMs = _toMs(a.timestamp);
    if (!tsMs || (now - tsMs) > WEEK) continue;
    stats.total++;
    if (a.status === 'validee') {
      stats.solved++;
      if (typeof a.elapsedTime === 'number' && a.elapsedTime > 0) {
        totalElapsed += a.elapsedTime;
        solvedCount++;
        if (stats.fastestMin === null || a.elapsedTime < stats.fastestMin) stats.fastestMin = a.elapsedTime;
        if (stats.slowestMin === null || a.elapsedTime > stats.slowestMin) stats.slowestMin = a.elapsedTime;
      }
    } else if (a.status === 'en_cours') stats.inProgress++;
    else stats.pending++;
    if (a.isCritical) stats.critical++;
    if (a.aiAssigned) stats.aiAssigned++;
    const t = String(a.type || 'other');
    stats.byType[t] = (stats.byType[t] || 0) + 1;
    const f = String(a.usine || 'unknown');
    stats.byFactory[f] = (stats.byFactory[f] || 0) + 1;
  }
  stats.avgResolutionMin = solvedCount > 0 ? Math.round(totalElapsed / solvedCount) : 0;
  return stats;
}

function _typeName(t) {
  return ({
    qualite: 'Quality',
    maintenance: 'Maintenance',
    defaut_produit: 'Damaged Product',
    manque_ressource: 'Resource Deficiency',
  })[t] || t;
}

async function generateMorningBriefing(env, ctx, force = false) {
  const { token, alertsMap } = ctx;
  const today = _briefingDateKey(new Date());
  if (!force) {
    try {
      const cur = await fetch(`${env.FB_DB_URL}ai_briefing/latest.json?auth=${token}`);
      if (cur.ok) {
        const data = await cur.json();
        if (data?.date === today) return data;
      }
    } catch (e) {}
  }

  const stats = _aggregateWeek(alertsMap);
  const topType = Object.entries(stats.byType).sort((a, b) => b[1] - a[1])[0];
  const topFactory = Object.entries(stats.byFactory).sort((a, b) => b[1] - a[1])[0];
  const resolutionRate = stats.total > 0 ? Math.round((stats.solved / stats.total) * 100) : 0;

  const prompt = `You are an industrial operations briefing officer addressing the production manager at the start of the day. Write a single, warm, concise paragraph (3 to 4 sentences, no bullets, no headers, no markdown, no lists). Use these facts from the past 7 days:
- Total alerts: ${stats.total}
- Resolved: ${stats.solved} (${resolutionRate}% resolution rate)
- Critical alerts: ${stats.critical}
- Currently in progress: ${stats.inProgress}, pending: ${stats.pending}
- Average resolution time: ${stats.avgResolutionMin} minutes
- Fastest fix: ${stats.fastestMin ?? 'n/a'} min · slowest: ${stats.slowestMin ?? 'n/a'} min
- Most frequent alert type: ${topType ? `${_typeName(topType[0])} (${topType[1]})` : 'none'}
- Most active site: ${topFactory ? `${topFactory[0]} (${topFactory[1]})` : 'none'}
- AI auto-assignments: ${stats.aiAssigned}

Begin with "Good morning". Acknowledge what is going well, name one specific area to watch, and close with a forward-looking sentence about today. Sound calm, professional, and human — not a press release.`;

  let summary = `Good morning. Last week the team handled ${stats.total} alerts with a ${resolutionRate}% resolution rate and an average response of ${stats.avgResolutionMin} minutes. Stay sharp on critical signals today.`;
  let model = 'fallback';
  try {
    if (env.AI) {
      const resp = await env.AI.run('@cf/meta/llama-3.2-3b-instruct', {
        messages: [{ role: 'user', content: prompt }],
      });
      const out = (resp.response || '').trim();
      if (out) {
        summary = out;
        model = '@cf/meta/llama-3.2-3b-instruct';
      }
    }
  } catch (e) {
    console.error('[BRIEFING] AI failed: ' + e.message);
  }

  const payload = {
    date: today,
    summary,
    generatedAt: new Date().toISOString(),
    model,
    stats,
    topType: topType ? { type: topType[0], count: topType[1] } : null,
    topFactory: topFactory ? { name: topFactory[0], count: topFactory[1] } : null,
    resolutionRate,
  };
  await fetch(`${env.FB_DB_URL}ai_briefing/latest.json?auth=${token}`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  });
  // Archive
  await fetch(`${env.FB_DB_URL}ai_briefing/history/${today}.json?auth=${token}`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  });
  return payload;
}

// ============================================================
// AI proxy – Gemma 3 1B via Cloudflare Workers AI (edge inference)
// ============================================================
async function handleAIRequest(request, env) {
  const fallback = '• Check equipment status.\n• Verify sensor connections.\n• Restart the affected machine.';
  try {
    const { prompt } = await request.json();
    if (!env.AI) {
      return new Response(JSON.stringify({ suggestion: fallback, note: 'AI binding not configured' }), {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }
    // Llama 3.2 3B Instruct – better quality, still free on Workers AI
    const response = await env.AI.run('@cf/meta/llama-3.2-3b-instruct', {
      messages: [{ role: 'user', content: prompt }],
    });
    const suggestion = response.response?.trim() ?? 'No suggestion available';
    return new Response(JSON.stringify({ suggestion }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (e) {
    return new Response(JSON.stringify({ suggestion: fallback, note: String(e) }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
}

// ============================================================
// Fan‑out pending notifications (used only by /notify endpoint)
// ============================================================
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

async function fanOutPendingNotifications(env, ctx) {
  const { token, usersMap, alertsMap } = ctx;
  const nowIso = new Date().toISOString();

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

      if (isBusySupervisor && !COLLAB_NOTIF_TYPES.has(String(notif.type || ''))) continue;

      const url = `${env.FB_DB_URL}notifications/${uid}/${notifId}.json?auth=${env.FB_DB_SECRET}`;
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
// AI Assignment Engine (FULL SCORING)
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

function buildSupStats(alertsMap) {
  const stats = {};
  for (const a of Object.values(alertsMap)) {
    if (!a || a.status !== 'validee' || a.elapsedTime == null) continue;
    for (const role of ['superviseurId', 'assistantId']) {
      const id = a[role];
      if (!id) continue;
      if (!stats[id]) {
        stats[id] = {
          typeCounts: {},
          typeTotalTimes: {},
          stationCounts: {},
          conveyorCounts: {},
        };
      }
      const s = stats[id];
      const type = a.type || '';
      s.typeCounts[type] = (s.typeCounts[type] || 0) + 1;
      s.typeTotalTimes[type] = (s.typeTotalTimes[type] || 0) + (a.elapsedTime || 0);
      const stationKey = `${a.usine || ''}|${a.convoyeur}|${a.poste}`;
      s.stationCounts[stationKey] = (s.stationCounts[stationKey] || 0) + 1;
      const convKey = `${a.usine || ''}|${a.convoyeur}`;
      s.conveyorCounts[convKey] = (s.conveyorCounts[convKey] || 0) + 1;
    }
  }
  for (const id of Object.keys(stats)) {
    const s = stats[id];
    s.typeAvgRes = {};
    for (const type of Object.keys(s.typeTotalTimes)) {
      if (s.typeCounts[type] > 0) {
        s.typeAvgRes[type] = s.typeTotalTimes[type] / s.typeCounts[type];
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
    reasons.push('Different factory (−25)');
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

  const convKey = `${alert.usine || ''}|${alert.convoyeur}`;
  const convCount = supStats?.conveyorCounts[convKey] || 0;
  if (convCount > 0) {
    const bonus = Math.min(convCount * 1.5, 15);
    score += bonus;
    reasons.push(`${convCount} fix${convCount > 1 ? 'es' : ''} on Line ${alert.convoyeur} (+${bonus})`);
  }

  if (!alert.isCritical && recentAssignments > 0) {
    const penalty = recentAssignments * 8;
    score -= penalty;
    reasons.push(`Recent load: ${recentAssignments} assignment${recentAssignments > 1 ? 's' : ''} in 10min (−${penalty})`);
  }

  const fb = feedbackSummary[sup.uid];
  if (fb) {
    const accepted = fb.acceptedAssignments || 0;
    const rejected = fb.rejectedAssignments || 0;
    const aborted = fb.abortedAssignments || 0;
    const resolved = fb.resolvedOutcomes || 0;
    const adjustment = Math.min(Math.max(accepted * 2 + resolved * 3 - rejected * 2 - aborted * 1.5, -20), 20);
    score += adjustment;
    if (adjustment !== 0) {
      reasons.push(`Feedback adjustment (${adjustment > 0 ? '+' : ''}${adjustment})`);
    }
  }

  return { score: Math.max(0, score), reasons };
}

async function aiAssignAlert(alertId, supervisor, reasonSummary, confidence, env, token) {
  const alertUrl = `${env.FB_DB_URL}alerts/${alertId}.json?auth=${token}`;
  const getRes = await fetch(alertUrl, { headers: { 'X-Firebase-ETag': 'true' } });
  if (!getRes.ok) return false;
  const etag = getRes.headers.get('ETag');
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
      aiAssignmentReason: reasonSummary,
      aiConfidence: confidence,
      aiAssignedAt: nowIso,
    }),
  });
  if (putRes.status === 412 || !putRes.ok) return false;

  const cooldownUntil = new Date(Date.now() + AI_COOLDOWN_MS).toISOString();
  await Promise.allSettled([
    fetch(`${env.FB_DB_URL}users/${supervisor.uid}/aiCooldownUntil.json?auth=${token}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(cooldownUntil),
    }),
    fetch(`${env.FB_DB_URL}alerts/${alertId}/aiHistory.json?auth=${token}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        event: 'assigned_worker',
        supervisorId: supervisor.uid,
        supervisorName: supervisor.name,
        reason: reasonSummary,
        confidence,
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
        confidence,
        reasonSummary,
        decisionMode: 'worker_auto',
        timestamp: nowIso,
      }),
    }),
  ]);

  if (supervisor.fcmToken) {
    await sendFcm(
      supervisor.fcmToken,
      'AI Assignment',
      `Auto-assigned: ${current.type || 'alert'}${current.usine ? ` at ${current.usine}` : ''}`,
      { type: 'ai_assigned', alertId: String(alertId), recipientId: String(supervisor.uid), reason: reasonSummary },
      env,
    );
  }
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

  let feedbackSummary = {};
  try {
    const fbRes = await fetch(`${env.FB_DB_URL}ai_feedback/summary.json?auth=${token}`);
    if (fbRes.ok) feedbackSummary = (await fbRes.json()) || {};
  } catch (e) {}

  const supStats = buildSupStats(alertsMap);

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

  for (let i = 0; i < Math.min(factoryIds.length, MAX_AI_FACTORIES); i++) {
    const factoryId = factoryIds[i];
    const enaRes = await fetch(`${env.FB_DB_URL}factories/${factoryId}/aiConfig/enabled.json?auth=${token}`);
    const enabled = enaRes.ok ? await enaRes.json() : false;
    if (enabled !== true) continue;

    let factoryAlerts = byFactory[factoryId];
    factoryAlerts.sort((a, b) => {
      const ap = a.isEscalated ? 2 : (a.isCritical ? 1 : 0);
      const bp = b.isEscalated ? 2 : (b.isCritical ? 1 : 0);
      if (ap !== bp) return bp - ap;
      return (Date.parse(a.timestamp || '') || 0) - (Date.parse(b.timestamp || '') || 0);
    });

    const alert = factoryAlerts[0];
    if (!alert) continue;

    const candidates = [];
    for (const [uid, u] of Object.entries(usersMap)) {
      if (!u || u.role !== 'supervisor') continue;
      if (u.aiOptOut === true) continue;
      if (!AI_ACTIVE_STATUSES.has(String(u.status || '').toLowerCase())) continue;
      if (busy.has(uid)) continue;
      const cooldown = Date.parse(String(u.aiCooldownUntil || ''));
      if (!isNaN(cooldown) && cooldown > now) continue;
      const userFactory = aiResolveFactory(u);
      if (!userFactory || userFactory !== factoryId) continue;
      candidates.push(u);
    }

    if (candidates.length === 0) continue;

    const scored = candidates.map((u) => {
      const recentAssignments = Object.values(alertsMap).filter(a =>
        a.superviseurId === u.uid &&
        a.takenAtTimestamp &&
        (now - new Date(a.takenAtTimestamp).getTime()) < 10 * 60 * 1000
      ).length;

      const { score, reasons } = scoreSupervisor(
        { ...u, uid: u.uid, name: u.fullName || `${u.firstName || ''} ${u.lastName || ''}`.trim(), fcmToken: u.fcmToken },
        alert,
        supStats,
        feedbackSummary,
        recentAssignments,
        now,
      );
      return { uid: u.uid, name: u.fullName || `${u.firstName || ''} ${u.lastName || ''}`.trim(), fcmToken: u.fcmToken, score, reasons };
    });

    scored.sort((a, b) => b.score - a.score);
    const best = scored[0];

    const topSum = scored.slice(0, 3).reduce((s, c) => s + c.score, 0);
    const confidence = topSum > 0 ? Math.min(best.score / topSum, 1.0) : 1.0;
    const reasonSummary = best.reasons.join(' • ');

    const ok = await aiAssignAlert(alert.id, best, reasonSummary, confidence, env, token);
    if (ok) busy.add(best.uid);
  }
}

// ============================================================
// One-Tap Resolution suggestion (top supervisor for an alert)
// Reuses the AI scoring engine to score every eligible candidate.
// ============================================================
async function handleSuggestAssignee(request, env) {
  try {
    const url = new URL(request.url);
    const alertId = url.searchParams.get('alertId');
    if (!alertId) {
      return new Response(JSON.stringify({ error: 'alertId required' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const ctx = await loadCoreData(env);
    const { token, alertsMap, usersMap } = ctx;
    const alert = alertsMap[alertId];
    if (!alert) {
      return new Response(JSON.stringify({ error: 'alert not found' }), {
        status: 404,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    let feedbackSummary = {};
    try {
      const fbRes = await fetch(`${env.FB_DB_URL}ai_feedback/summary.json?auth=${token}`);
      if (fbRes.ok) feedbackSummary = (await fbRes.json()) || {};
    } catch (e) {}

    const supStats = buildSupStats(alertsMap);
    const busy = new Set();
    for (const a of Object.values(alertsMap)) {
      if (a.status === 'en_cours') {
        if (a.superviseurId) busy.add(a.superviseurId);
        if (a.assistantId) busy.add(a.assistantId);
      }
    }

    const targetFid = aiResolveFactory(alert);
    const now = Date.now();
    const candidates = [];
    for (const [uid, u] of Object.entries(usersMap)) {
      if (!u || u.role !== 'supervisor') continue;
      if (u.aiOptOut === true) continue;
      const userFid = aiResolveFactory(u);
      if (!targetFid || !userFid || userFid !== targetFid) continue;
      const recent = Object.values(alertsMap).filter(
        (a) =>
          a.superviseurId === uid &&
          a.takenAtTimestamp &&
          now - new Date(a.takenAtTimestamp).getTime() < 10 * 60 * 1000,
      ).length;
      const cand = {
        uid,
        name: u.fullName || `${u.firstName || ''} ${u.lastName || ''}`.trim(),
        fcmToken: u.fcmToken,
        usine: u.usine,
        factoryId: u.factoryId,
        status: u.status,
        busy: busy.has(uid),
        avatar: u.avatar || null,
      };
      const { score, reasons } = scoreSupervisor(
        { ...cand, uid },
        alert,
        supStats,
        feedbackSummary,
        recent,
        now,
      );
      candidates.push({ ...cand, score, reasons });
    }

    candidates.sort((a, b) => b.score - a.score);
    const top3 = candidates.slice(0, 3);
    const topSum = top3.reduce((s, c) => s + c.score, 0);
    const best = top3[0];
    const confidence =
      best && topSum > 0 ? Math.min(1.0, best.score / topSum) : 0;

    return new Response(
      JSON.stringify({
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
        runners: top3.slice(1).map((c) => ({
          uid: c.uid,
          name: c.name,
          score: c.score,
          busy: c.busy,
        })),
        candidateCount: candidates.length,
        generatedAt: new Date().toISOString(),
      }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
}

// ============================================================
// Predictions / Briefing fetch endpoints
// ============================================================
async function handlePredictions(env) {
  try {
    const ctx = await loadCoreData(env);
    const data = await refreshPredictionsIfStale(env, ctx, 30);
    return new Response(JSON.stringify(data), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
}

async function handleBriefing(request, env) {
  try {
    const url = new URL(request.url);
    const force = url.searchParams.get('force') === '1';
    const ctx = await loadCoreData(env);
    const data = await generateMorningBriefing(env, ctx, force);
    return new Response(JSON.stringify(data), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
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
// Main export
// ============================================================
export default {
  async scheduled(event, env, ctx) {
    ctx.waitUntil(
      (async () => {
        let coreCtx;
        try {
          coreCtx = await loadCoreData(env);
        } catch (e) {
          console.error('[CRON] Load error: ' + e.message);
          return;
        }
        await processAlerts(env, coreCtx);
        await checkEscalations(env, coreCtx);
        await runAIAssignments(env, coreCtx);
        // Refresh prediction cache every ~30 min and ensure today's briefing exists.
        try { await refreshPredictionsIfStale(env, coreCtx, 30); } catch (e) { console.error('[PREDICT] ' + e.message); }
        try { await generateMorningBriefing(env, coreCtx, false); } catch (e) { console.error('[BRIEFING] ' + e.message); }
      })(),
    );
  },

  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: corsHeaders });
    }

    if (url.pathname === '/config') return handleConfigRequest();
    if (url.pathname === '/ai-proxy') return handleAIRequest(request, env);
    if (url.pathname === '/predict') return handlePredictions(env);
    if (url.pathname === '/briefing') return handleBriefing(request, env);
    if (url.pathname === '/suggest-assignee') return handleSuggestAssignee(request, env);

    if (url.pathname === '/ai-retry') {
      ctx.waitUntil(runAIAssignments(env, null));
      return new Response(JSON.stringify({ queued: true }), {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    if (url.pathname === '/notify') {
      ctx.waitUntil(
        (async () => {
          try {
            const coreCtx = await loadCoreData(env);
            await fanOutPendingNotifications(env, coreCtx);
          } catch (e) {
            console.error('[NOTIFY] Error: ' + e.message);
          }
        })(),
      );
      return new Response(JSON.stringify({ queued: true }), {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // Default / manual trigger
    try {
      const coreCtx = await loadCoreData(env);
      await processAlerts(env, coreCtx);
      await checkEscalations(env, coreCtx);
      await runAIAssignments(env, coreCtx);
    } catch (e) {
      console.error('[MANUAL] Error: ' + e.message);
    }
    return new Response('OK', { status: 200, headers: corsHeaders });
  },
};
