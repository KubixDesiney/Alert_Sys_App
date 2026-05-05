// Cloudflare Worker – AlertSys (full scoring, predictions, briefing, no auth)
// Cron schedule: "* * * * *" (every minute)
// Required env vars: FB_DB_URL, FB_API_KEY, FIREBASE_SERVICE_ACCOUNT, optional GEMINI_API_KEY
// Optional: enable Workers AI binding (env.AI) for Llama 3.2 3B

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
};

let _fbToken = null;
let _fbTokenExpMs = 0;
let _fcmToken = null;
let _fcmTokenExpMs = 0;

const MAX_ALERTS_TO_PUSH = 1;
const MAX_ESCALATION_CHECKS = 5;
const MAX_FANOUT = 2;

// ============ Firebase Auth ============
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

// ============ Helper functions ============
function _briefingDateKey(date) {
  const d = new Date(date);
  const year = d.getUTCFullYear();
  const month = String(d.getUTCMonth() + 1).padStart(2, '0');
  const day = String(d.getUTCDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

function _typeName(type) {
  switch (String(type || '')) {
    case 'qualite': return 'Quality';
    case 'maintenance': return 'Maintenance';
    case 'defaut_produit': return 'Damaged Product';
    case 'manque_ressource': return 'Resource Deficiency';
    default: return String(type || '');
  }
}

function _toMs(value) {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (typeof value === 'string') {
    const parsed = Date.parse(value);
    return Number.isNaN(parsed) ? null : parsed;
  }
  return null;
}

function _aggregateWeek(alertsMap = {}) {
  const cutoff = Date.now() - 7 * 24 * 60 * 60 * 1000;
  const stats = {
    total: 0,
    solved: 0,
    inProgress: 0,
    pending: 0,
    critical: 0,
    aiAssigned: 0,
    fastestMin: 0,
    slowestMin: 0,
    avgResolutionMin: 0,
  };
  let resolutionCount = 0;
  let resolutionTotal = 0;
  for (const alert of Object.values(alertsMap || {})) {
    const ts = _toMs(alert?.timestamp);
    if (ts == null || ts < cutoff) continue;
    stats.total++;
    if (alert?.isCritical === true) stats.critical++;
    if (alert?.aiAssigned === true) stats.aiAssigned++;
    if (alert?.status === 'validee') {
      stats.solved++;
      const elapsed = Number(alert?.elapsedTime);
      if (Number.isFinite(elapsed)) {
        resolutionCount++;
        resolutionTotal += elapsed;
        if (stats.fastestMin === 0 || elapsed < stats.fastestMin) stats.fastestMin = elapsed;
        if (elapsed > stats.slowestMin) stats.slowestMin = elapsed;
      }
    } else if (alert?.status === 'en_cours') {
      stats.inProgress++;
    } else if (alert?.status === 'disponible') {
      stats.pending++;
    }
  }
  if (resolutionCount > 0) {
    stats.avgResolutionMin = Math.round(resolutionTotal / resolutionCount);
  }
  return stats;
}

// ============ Scoring helpers ============
function buildSupStats(alertsMap = {}) {
  const stats = {};
  const ensure = (uid) => {
    if (!stats[uid]) {
      stats[uid] = {
        typeCounts: {},
        typeTotalTimes: {},
        stationCounts: {},
        conveyorCounts: {},
      };
    }
    return stats[uid];
  };
  for (const alert of Object.values(alertsMap || {})) {
    if (!alert || alert.status !== 'validee') continue;
    if (typeof alert.elapsedTime !== 'number' || !Number.isFinite(alert.elapsedTime)) continue;
    const ids = [alert.superviseurId, alert.assistantId].filter(Boolean);
    if (ids.length === 0) continue;
    const type = String(alert.type || 'unknown');
    const factory = String(alert.usine || '');
    const stationKey = `${factory}|${alert.convoyeur}|${alert.poste}`;
    const conveyorKey = `${factory}|${alert.convoyeur}`;
    for (const uid of ids) {
      const entry = ensure(uid);
      entry.typeCounts[type] = (entry.typeCounts[type] || 0) + 1;
      entry.typeTotalTimes[type] = (entry.typeTotalTimes[type] || 0) + alert.elapsedTime;
      entry.stationCounts[stationKey] = (entry.stationCounts[stationKey] || 0) + 1;
      entry.conveyorCounts[conveyorKey] = (entry.conveyorCounts[conveyorKey] || 0) + 1;
    }
  }
  for (const id of Object.keys(stats)) {
    const s = stats[id];
    s.typeAvgRes = {};
    for (const type of Object.keys(s.typeTotalTimes)) {
      if (s.typeCounts[type] > 0) {
        s.typeAvgRes[type] = Math.round(s.typeTotalTimes[type] / s.typeCounts[type]);
      }
    }
  }
  return stats;
}

function scoreSupervisor(sup, alert, stats, feedbackSummary, recentAssignments, now) {
  let score = 0;
  const reasons = [];
  const supFactory = aiSanitizeFactoryId(sup?.usine || sup?.factoryId || '');
  const alertFactory = aiSanitizeFactoryId(alert?.usine || alert?.factoryId || '');
  const supStats = stats[sup.uid] || {};
  const type = alert.type || '';
  const typeCount = supStats.typeCounts?.[type] || 0;

  if (alertFactory && supFactory && alertFactory === supFactory) {
    score += 30;
    reasons.push('Same factory (+30)');
  } else {
    score -= 25;
    reasons.push('Different factory (−25)');
  }

  if (typeCount > 0) {
    const bonus = Math.min(typeCount * 4, 40);
    score += bonus;
    reasons.push(`${typeCount} past ${type} resolved (+${bonus})`);
  } else {
    reasons.push(`No prior ${type} experience`);
  }

  const avgTime = supStats.typeAvgRes?.[type];
  if (avgTime !== undefined && avgTime !== null) {
    const speedBonus = Math.min(Math.max(0, 60 - avgTime), 25);
    score += speedBonus;
    reasons.push(`Avg resolution ${Math.floor(avgTime)}min (+${Math.floor(speedBonus)})`);
  }

  const stationKey = `${alert.usine || ''}|${alert.convoyeur}|${alert.poste}`;
  const stationCount = supStats.stationCounts?.[stationKey] || 0;
  if (stationCount > 0) {
    const bonus = Math.min(stationCount * 6, 30);
    score += bonus;
    reasons.push(`${stationCount} fixes at workstation (+${bonus})`);
  }

  const convKey = `${alert.usine || ''}|${alert.convoyeur}`;
  const convCount = supStats.conveyorCounts?.[convKey] || 0;
  if (convCount > 0) {
    const bonus = Math.min(convCount * 1.5, 15);
    score += bonus;
    reasons.push(`${convCount} fixes on line (+${bonus})`);
  }

  if (!alert.isCritical && recentAssignments > 0) {
    const penalty = recentAssignments * 8;
    score -= penalty;
    reasons.push(`Recent load (−${penalty})`);
  }

  const fb = feedbackSummary[sup.uid] || {};
  const adjustment = Math.min(Math.max(
    (fb.acceptedAssignments || 0) * 2 +
    (fb.resolvedOutcomes || 0) * 3 -
    (fb.rejectedAssignments || 0) * 2 -
    (fb.abortedAssignments || 0) * 1.5,
    -20
  ), 20);
  if (adjustment !== 0) {
    score += adjustment;
    reasons.push(`Feedback adjustment (${adjustment > 0 ? '+' : ''}${adjustment})`);
  }

  return { score: Math.max(0, Math.round(score)), reasons };
}

// ============ Predictive model ============
function buildPredictiveModel(alertsMap = {}) {
  const now = Date.now();
  const horizonMs = 180 * 24 * 60 * 60 * 1000;
  const hodCounts = {};
  const dowCounts = {};
  const recentCounts = {};
  const machineHistory = {};
  const factoryRisk = {};

  for (const t of ['qualite', 'maintenance', 'defaut_produit', 'manque_ressource']) {
    hodCounts[t] = new Array(24).fill(0);
    dowCounts[t] = new Array(7).fill(0);
    recentCounts[t] = 0;
  }

  for (const [, a] of Object.entries(alertsMap || {})) {
    if (!a) continue;
    const tsMs = _toMs(a.timestamp);
    if (!tsMs || (now - tsMs) > horizonMs || tsMs > now) continue;
    const type = String(a.type || '');
    if (!['qualite', 'maintenance', 'defaut_produit', 'manque_ressource'].includes(type)) continue;

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
    const decay = Math.exp(-ageDays / 14);
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

  const startHour = new Date(now).getUTCHours();
  const curves = {};
  for (const type of ['qualite', 'maintenance', 'defaut_produit', 'manque_ressource']) {
    const buckets = [];
    let total = 0;
    for (let i = 0; i < 12; i++) {
      const h1 = (startHour + i * 2) % 24;
      const h2 = (startHour + i * 2 + 1) % 24;
      const cnt = hodCounts[type][h1] + hodCounts[type][h2];
      const lambda = cnt / 30;
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
    const dailyAvg = totalRecent / 30;
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

  const factoryRanked = Object.entries(factoryRisk)
    .map(([id, v]) => ({ id, name: v.name, score: Number(v.score.toFixed(3)), count: v.count }))
    .sort((a, b) => b.score - a.score)
    .slice(0, 6);

  return {
    curves,
    predictions,
    factoryRisk: factoryRanked,
    generatedAt: new Date().toISOString(),
    horizonDays: 30,
    halflifeDays: 14,
  };
}

// ============ FCM access token and send helper ============
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
          // Data-only message: no top-level "notification" field.
          // This guarantees firebaseMessagingBackgroundHandler is invoked even
          // when the app is terminated, so flutter_local_notifications can show
          // a fullScreenIntent notification that bypasses the Android lock screen.
          // Title/body are carried in the data map and read by the Flutter handler.
          data: { ...data, title, body },
          android: { priority: 'high' },
          apns: {
            headers: { 'apns-priority': '10' },
            payload: { aps: { 'content-available': 1 } },
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

// ============ Core data loader ============
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

// ============ FCM tokens for a factory ============
// allSupervisors=true → notify every supervisor in the factory (new alerts).
// allSupervisors=false → skip supervisors who already own an in-progress alert
//                        (used for escalations / AI-assignment notifications).
function getFcmTokensForFactory(factoryName, usersMap, alertsMap, { allSupervisors = false } = {}) {
  const targetId = aiSanitizeFactoryId(factoryName);
  const busySupervisors = new Set();
  if (!allSupervisors) {
    for (const a of Object.values(alertsMap)) {
      if (a.status === 'en_cours') {
        if (a.superviseurId) busySupervisors.add(a.superviseurId);
        if (a.assistantId) busySupervisors.add(a.assistantId);
      }
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

// ============ New‑alert FCM push ============
async function processAlerts(env, ctx) {
  const { token, alertsMap, usersMap } = ctx;
  // Filter directly from the already-loaded alertsMap – avoids a second
  // Firebase REST round-trip and removes the dependency on a Firebase
  // ".indexOn: push_sent" rule (missing index returns 400 → silent failure).
  const unsent = Object.entries(alertsMap || {})
    .filter(([, a]) => a && a.push_sent === false)
    .slice(0, MAX_ALERTS_TO_PUSH)
    .map(([id, a]) => ({
      id,
      type: a.type || 'Alert',
      usine: a.usine || '',
      description: a.description || '',
    }));
  if (!unsent.length) return;
  for (const alert of unsent) {
    const flagUrl = `${env.FB_DB_URL}alerts/${alert.id}/push_sent.json?auth=${token}`;
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
    // New-alert push: notify ALL supervisors in this factory, regardless of
    // whether they are currently handling another alert.
    const fcmTokens = getFcmTokensForFactory(alert.usine, usersMap, alertsMap, { allSupervisors: true });
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
    await fetch(flagUrl, { method: 'PUT', body: JSON.stringify(allOk ? true : false) });
  }
}

// ============ Escalation check ============
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

  // Pre-filter to only active, unescalated alerts so the MAX_ESCALATION_CHECKS
  // budget is not consumed by already-handled entries.
  const candidates = Object.entries(alertsMap).filter(
    ([, a]) => a && !a.isEscalated && a.status !== 'validee' && a.status !== 'cancelled',
  );

  let escalated = 0;
  for (const [alertId, alert] of candidates) {
    if (escalated >= MAX_ESCALATION_CHECKS) break;
    try {
      let threshold = settings[alert.type] || settings[String(alert.type || '').toLowerCase()];
      if (!threshold && settings.default) threshold = settings.default;
      if (!threshold) continue;

      let createdAtMs;
      if (typeof alert.timestamp === 'number') {
        createdAtMs = alert.timestamp;
      } else if (typeof alert.timestamp === 'string') {
        const parsed = Date.parse(alert.timestamp);
        if (isNaN(parsed)) continue;
        createdAtMs = parsed;
      } else { continue; }

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
          if (isNaN(parsed)) continue;
          takenMs = parsed;
        }
        const mins = (now - takenMs) / 60000;
        if (typeof threshold.claimedMinutes === 'number' && mins >= threshold.claimedMinutes) {
          shouldEscalate = true;
          reason = `Claimed but not resolved for ${Math.floor(mins)} minutes`;
        }
      } else { continue; }

      if (!shouldEscalate) continue;

      const patchRes = await fetch(`${env.FB_DB_URL}alerts/${alertId}.json?auth=${token}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ isEscalated: true, escalatedAt: new Date().toISOString() }),
      });
      if (!patchRes.ok) {
        console.error(`[ESCALATION] Failed to patch alert ${alertId}: ${patchRes.status}`);
        continue;
      }
      try {
        await fetch(`${env.FB_DB_URL}alerts/${alertId}/aiHistory.json?auth=${token}`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ event: 'escalated_worker', reason, timestamp: new Date().toISOString() }),
        });
      } catch (e) { console.error('[ESCALATION] Failed to write aiHistory: ' + e.message); }

      const escalMsg = `⚠️ Alert Escalated: ${alert.type}`;
      const escalBody = `${alert.usine} — ${alert.description}\n${reason}`;
      const escalData = { alertId, type: alert.type || '', usine: alert.usine || '', escalated: 'true' };
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
      escalated++;
    } catch (e) {
      console.error('[ESCALATION] Error processing alert: ' + e.message);
    }
  }
}

// ============ Workers AI helpers ============
const _AI_FALLBACK = '• Check equipment status.\n• Verify sensor connections.\n• Restart the affected machine.';

const _TYPE_LABELS = {
  qualite: 'Quality',
  maintenance: 'Maintenance',
  defaut_produit: 'Damaged Product',
  manque_ressource: 'Resource Deficiency',
};

async function _runLlama(prompt, env) {
  if (!env.AI) return null;
  try {
    const resp = await env.AI.run('@cf/meta/llama-3.2-3b-instruct', {
      messages: [{ role: 'user', content: prompt }],
    });
    return (resp.response || '').trim() || null;
  } catch (e) {
    console.error('[AI] Llama run failed: ' + e.message);
    return null;
  }
}

// /ai-proxy – generic prompt relay (used by auto-fix features)
async function handleAiProxy(request, env) {
  try {
    const { prompt } = await request.json();
    const suggestion = await _runLlama(String(prompt || ''), env) ?? _AI_FALLBACK;
    return new Response(JSON.stringify({ suggestion }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (e) {
    return new Response(JSON.stringify({ suggestion: _AI_FALLBACK }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
}

// /ai-suggest – context-aware alert resolution suggestion.
// Reads the last 10 resolved alerts at the same factory/conveyor/station/type
// from Firebase so Llama can learn from real past fixes.
async function handleAiSuggest(request, env) {
  try {
    const { type, usine, convoyeur, poste, description } = await request.json();
    if (!type || !usine) {
      return new Response(JSON.stringify({ suggestion: _AI_FALLBACK }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // Fetch resolved alerts for this factory so we can extract past fixes.
    let pastResolutions = [];
    try {
      const token = await getFirebaseToken(env);
      const res = await fetch(
        `${env.FB_DB_URL}alerts.json?auth=${token}&orderBy="usine"&equalTo=${encodeURIComponent(usine)}`,
      );
      if (res.ok) {
        const data = (await res.json()) || {};
        pastResolutions = Object.values(data)
          .filter(
            (a) =>
              a &&
              a.status === 'validee' &&
              a.type === type &&
              Number(a.convoyeur) === Number(convoyeur) &&
              Number(a.poste) === Number(poste) &&
              a.resolutionReason,
          )
          .sort((a, b) => (String(b.resolvedAt || '') > String(a.resolvedAt || '') ? 1 : -1))
          .slice(0, 10)
          .map((a) => a.resolutionReason);
      }
    } catch (e) {
      console.error('[AI-SUGGEST] History fetch failed: ' + e.message);
    }

    const typeLabel = _TYPE_LABELS[type] || type;
    const historyBlock =
      pastResolutions.length > 0
        ? `Past resolutions for this exact location (most recent first):\n${pastResolutions.map((r) => `- ${r}`).join('\n')}`
        : 'No past resolutions on record for this specific location.';

    const prompt = `You are an industrial operations assistant. A supervisor needs a resolution suggestion.

Alert type: ${typeLabel}
Description: ${description}
Location: Factory: ${usine}, Conveyor line: ${convoyeur}, Workstation: #${poste}

${historyBlock}

Provide a concise, actionable resolution in 2-3 bullet points. Base it on the past fixes when available; otherwise suggest the most likely root cause and immediate action.`;

    const suggestion = await _runLlama(prompt, env) ?? _AI_FALLBACK;
    return new Response(JSON.stringify({ suggestion }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (e) {
    return new Response(JSON.stringify({ suggestion: _AI_FALLBACK }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
}

// ============ Predictions endpoint ============
async function handlePredictions(env) {
  try {
    const coreCtx = await loadCoreData(env);
    const model = buildPredictiveModel(coreCtx.alertsMap || {});
    await fetch(`${env.FB_DB_URL}ai_predictions/latest.json?auth=${coreCtx.token}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(model),
    });
    return new Response(JSON.stringify(model), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e?.message || e) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
}

// ============ Briefing endpoint (Llama 3.2 via Workers AI) ============
async function handleBriefing(request, env) {
  try {
    const url = new URL(request.url);
    const force = url.searchParams.get('force') === '1';
    const coreCtx = await loadCoreData(env);
    const today = _briefingDateKey(new Date());
    if (!force) {
      const existing = await fetch(`${env.FB_DB_URL}ai_briefing/latest.json?auth=${coreCtx.token}`);
      if (existing.ok) {
        const data = await existing.json();
        if (data?.date === today) {
          return new Response(JSON.stringify(data), {
            status: 200,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          });
        }
      }
    }
    const stats = _aggregateWeek(coreCtx.alertsMap || {});
    const topType = Object.entries(stats.byType || {}).sort((a, b) => b[1] - a[1])[0];
    const topFactory = Object.entries(stats.byFactory || {}).sort((a, b) => b[1] - a[1])[0];
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
    await fetch(`${env.FB_DB_URL}ai_briefing/latest.json?auth=${coreCtx.token}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    });
    await fetch(`${env.FB_DB_URL}ai_briefing/history/${today}.json?auth=${coreCtx.token}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    });
    return new Response(JSON.stringify(payload), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e?.message || e) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
}

// ============ Auto‑fix endpoints ============
async function handleAutoFix(request, env) {
  try {
    const { code = '', errors = '' } = await request.json();
    const prompt =
      'Fix this Dart/Flutter code using the error list. Return only the fixed source code.\n\n' +
      `Errors:\n${errors}\n\nCode:\n${code}`;
    const suggestion = await _runLlama(prompt, env) ?? '';
    return new Response(JSON.stringify({ fixedCode: suggestion }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (e) {
    return new Response(JSON.stringify({ fixedCode: '', error: String(e?.message || e) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
}

async function handleAutoFixFull(request, env) {
  try {
    const { files = [], errors = '' } = await request.json();
    const combined = Array.isArray(files)
      ? files.map((f) => `=== ${f?.path || 'file'} ===\n${f?.content || ''}`).join('\n\n')
      : '';
    const prompt =
      'Fix the provided project files based on the errors. Return only a JSON array of objects with path and content.\n\n' +
      `Errors:\n${errors}\n\nFiles:\n${combined}`;
    const raw = await _runLlama(prompt, env) ?? '[]';
    let fixedFiles = [];
    try {
      fixedFiles = JSON.parse(raw);
      if (!Array.isArray(fixedFiles)) fixedFiles = [];
    } catch (_) {
      fixedFiles = [];
    }
    return new Response(JSON.stringify({ fixedFiles }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (e) {
    return new Response(JSON.stringify({ fixedFiles: [], error: String(e?.message || e) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
}

// ============ Fan‑out notifications ============
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
}

// ============ AI Assignment Engine (FULL SCORING) ============
const AI_COOLDOWN_MS = 10 * 60 * 1000;
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
      push_sent: true,
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
      {
        type: 'ai_assigned',
        alertId: String(alertId),
        recipientId: String(supervisor.uid),
        reason: reasonSummary,
      },
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
  let assignedCount = 0;
  for (let i = 0; i < Math.min(factoryIds.length, 20); i++) {
    if (assignedCount >= 1) break;
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
      candidates.push({ ...u, uid });
    }
    if (candidates.length === 0) continue;
    const recentCounts = {};
    for (const a of Object.values(alertsMap)) {
      if (a.superviseurId && a.takenAtTimestamp && (now - new Date(a.takenAtTimestamp).getTime()) < 10 * 60 * 1000) {
        recentCounts[a.superviseurId] = (recentCounts[a.superviseurId] || 0) + 1;
      }
    }
    const scored = candidates.map((u) => {
      const recent = recentCounts[u.uid] || 0;
      const { score, reasons } = scoreSupervisor(
        { ...u, uid: u.uid, name: u.fullName || `${u.firstName || ''} ${u.lastName || ''}`.trim(), fcmToken: u.fcmToken },
        alert,
        supStats,
        feedbackSummary,
        recent,
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
    if (ok) { busy.add(best.uid); assignedCount++; }
  }
}

// ============ /suggest-assignee (scoring restored) ============
async function handleSuggestAssignee(request, env) {
  try {
    const url = new URL(request.url);
    const alertId = String(url.searchParams.get('alertId') || '').trim();
    if (!alertId) {
      return new Response(JSON.stringify({ error: 'alertId required' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }
    const coreCtx = await loadCoreData(env);
    const alert = coreCtx.alertsMap?.[alertId];
    if (!alert) {
      return new Response(JSON.stringify({ error: 'alert not found' }), {
        status: 404,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }
    let feedbackSummary = {};
    try {
      const fbRes = await fetch(`${env.FB_DB_URL}ai_feedback/summary.json?auth=${coreCtx.token}`);
      if (fbRes.ok) feedbackSummary = (await fbRes.json()) || {};
    } catch (e) {}
    const supStats = buildSupStats(coreCtx.alertsMap || {});
    const busy = new Set();
    for (const a of Object.values(coreCtx.alertsMap || {})) {
      if (a?.status === 'en_cours') {
        if (a.superviseurId) busy.add(a.superviseurId);
        if (a.assistantId) busy.add(a.assistantId);
      }
    }
    const targetFid = aiResolveFactory(alert);
    const now = Date.now();
    const candidates = [];
    for (const [uid, u] of Object.entries(coreCtx.usersMap || {})) {
      if (!u || u.role !== 'supervisor') continue;
      if (u.aiOptOut === true) continue;
      const userFid = aiResolveFactory(u);
      if (!targetFid || !userFid || userFid !== targetFid) continue;
      const recent = Object.values(coreCtx.alertsMap || {}).filter(
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
    const confidence = best && topSum > 0 ? Math.min(1.0, best.score / topSum) : 0;
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
      {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      },
    );
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e?.message || e) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
}

// ============ /config placeholder ============
function handleConfigRequest() {
  return new Response(JSON.stringify({ message: 'Config endpoint deprecated' }), {
    status: 200,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

// ============ Main export ============
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
      })(),
    );
  },

  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: corsHeaders });
    }
    if (url.pathname === '/config') return handleConfigRequest();
    if (url.pathname === '/ai-proxy') return handleAiProxy(request, env);
    if (url.pathname === '/ai-suggest') return handleAiSuggest(request, env);
    if (url.pathname === '/predict') return handlePredictions(env);
    if (url.pathname === '/briefing') return handleBriefing(request, env);
    if (url.pathname === '/suggest-assignee') return handleSuggestAssignee(request, env);
    if (url.pathname === '/auto-fix') return handleAutoFix(request, env);
    if (url.pathname === '/auto-fix-full') return handleAutoFixFull(request, env);

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
          } catch (e) {}
        })(),
      );
      return new Response(JSON.stringify({ queued: true }), {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // Default trigger: AI first, then broadcast
    try {
      const coreCtx = await loadCoreData(env);
      await runAIAssignments(env, coreCtx);
      await processAlerts(env, coreCtx);
      await checkEscalations(env, coreCtx);
    } catch (e) {
      console.error('[MANUAL] Error: ' + e.message);
    }
    return new Response('OK', { status: 200, headers: corsHeaders });
  },
};

// Test-only named exports
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

