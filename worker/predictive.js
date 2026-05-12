import { getFirebaseToken } from './auth.js';
import { corsHeaders } from './config.js';
import { loadCoreData } from './load_core.js';
import { _briefingFactorySlug, _historyKey, _toMs, aiSanitizeFactoryId } from './utils.js';

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

function _filterAlertsMapByFactorySlug(alertsMap = {}, factorySlug = null) {
  if (!factorySlug) return alertsMap || {};
  return Object.fromEntries(
    Object.entries(alertsMap || {}).filter(([, alert]) => {
      return _briefingFactorySlug(alert?.usine || '') === factorySlug;
    }),
  );
}

async function handlePredictions(request, env) {
  try {
    const url = new URL(request.url);
    const factoryParam = url.searchParams.get('factory') || null;
    const factorySlug = factoryParam ? _briefingFactorySlug(factoryParam) : null;

    const coreCtx = await loadCoreData(env);
    const scopedAlertsMap = _filterAlertsMapByFactorySlug(
      coreCtx.alertsMap || {},
      factorySlug,
    );
    const model = buildPredictiveModel(scopedAlertsMap);
    const payload = factoryParam ? { ...model, factoryScope: factoryParam } : model;
    // Snapshot to history first (fire-and-forget) so we never lose it even if
    // the latest write somehow fails afterwards.
    const histKey = _historyKey(model.generatedAt);
    const latestPath = factorySlug
      ? `ai_predictions/factory/${factorySlug}/latest.json`
      : 'ai_predictions/latest.json';
    const historyPath = factorySlug
      ? `ai_predictions/factory/${factorySlug}/history/${histKey}.json`
      : `ai_predictions/history/${histKey}.json`;
    fetch(`${env.FB_DB_URL}${historyPath}?auth=${coreCtx.token}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ ...payload, validated: false }),
    }).catch(() => {});
    await fetch(`${env.FB_DB_URL}${latestPath}?auth=${coreCtx.token}`, {
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

// ============ Predictive validation ============

const MIN_VALIDATION_AGE_HOURS = 24;
const DEFAULT_VALIDATION_WINDOW_HOURS = 24;
const MAX_VALIDATION_PER_RUN = 10;

// Cross-references each historical prediction snapshot against alerts created
// during its validation window to compute hit rate (TP / total predicted).
// Snapshots already marked validated=true are skipped. Updates each snapshot
// in place with a `validation` sub-object and writes a rolling aggregate to
// ai_predictions/performance/latest.

async function validatePredictions(env, ctx) {
  const token = ctx?.token ?? (await getFirebaseToken(env));
  let alertsMap = ctx?.alertsMap;
  if (!alertsMap) {
    try {
      const ar = await fetch(`${env.FB_DB_URL}alerts.json?auth=${token}`);
      alertsMap = ar.ok ? ((await ar.json()) || {}) : {};
    } catch (_) { alertsMap = {}; }
  }

  let history = {};
  try {
    const hr = await fetch(`${env.FB_DB_URL}ai_predictions/history.json?auth=${token}`);
    if (hr.ok) history = (await hr.json()) || {};
  } catch (e) {
    console.error('[VALIDATE] Failed to fetch history: ' + e.message);
    return 0;
  }
  if (!history || typeof history !== 'object') return 0;

  const nowMs = Date.now();
  const minAgeMs = MIN_VALIDATION_AGE_HOURS * 60 * 60 * 1000;

  // Pre-compute a lookup of alerts by location+type for fast TP scoring.
  const alertIndex = {}; // key → list of {tsMs}
  for (const [, a] of Object.entries(alertsMap || {})) {
    if (!a) continue;
    const ts = _toMs(a.timestamp);
    if (ts == null) continue;
    const fid = aiSanitizeFactoryId(a.usine || a.factoryId || '');
    const conv = a.convoyeur ?? 0;
    const post = a.poste ?? 0;
    const type = String(a.type || '');
    const k = `${fid}|${conv}|${post}|${type}`;
    if (!alertIndex[k]) alertIndex[k] = [];
    alertIndex[k].push(ts);
  }

  // Eligible snapshots: not yet validated, generatedAt at least 24h old.
  const candidates = [];
  for (const [snapKey, snap] of Object.entries(history)) {
    if (!snap || typeof snap !== 'object') continue;
    if (snap.validated === true) continue;
    const genMs = _toMs(snap.generatedAt);
    if (genMs == null) continue;
    if (nowMs - genMs < minAgeMs) continue;
    candidates.push([genMs, snapKey, snap]);
  }
  candidates.sort((a, b) => a[0] - b[0]); // oldest-first

  let processed = 0;
  for (const [genMs, snapKey, snap] of candidates) {
    if (processed >= MAX_VALIDATION_PER_RUN) break;
    try {
      const preds = Array.isArray(snap.predictions) ? snap.predictions : [];
      const totalPredicted = preds.length;

      // Window = max ETA across predictions, defaulted to 24h.
      let windowHours = DEFAULT_VALIDATION_WINDOW_HOURS;
      for (const p of preds) {
        const eta = Number(p?.etaHours);
        if (Number.isFinite(eta) && eta > windowHours) windowHours = eta;
      }
      const windowMs = windowHours * 60 * 60 * 1000;
      const winStart = genMs;
      const winEnd = genMs + windowMs;

      let truePositives = 0;
      for (const p of preds) {
        const fid = aiSanitizeFactoryId(p?.factoryId || p?.usine || '');
        const conv = p?.convoyeur ?? 0;
        const post = p?.poste ?? 0;
        const type = String(p?.type || '');
        const k = `${fid}|${conv}|${post}|${type}`;
        const matches = alertIndex[k] || [];
        const hit = matches.some((ts) => ts >= winStart && ts <= winEnd);
        if (hit) truePositives++;
      }
      const accuracy = totalPredicted > 0 ? truePositives / totalPredicted : 0;
      const validatedAt = new Date().toISOString();

      // Patch snapshot in place.
      await fetch(`${env.FB_DB_URL}ai_predictions/history/${snapKey}.json?auth=${token}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          validated: true,
          validation: {
            totalPredicted,
            truePositives,
            accuracy: Number(accuracy.toFixed(4)),
            validatedAt,
          },
        }),
      }).catch((e) => console.error('[VALIDATE] PATCH failed: ' + e.message));

      processed++;
    } catch (e) {
      console.error('[VALIDATE] Snapshot ' + snapKey + ' failed: ' + e.message);
    }
  }

  // Aggregate macro-average across all validated snapshots (after this pass).
  try {
    const hr2 = await fetch(`${env.FB_DB_URL}ai_predictions/history.json?auth=${token}`);
    if (hr2.ok) {
      const allHist = (await hr2.json()) || {};
      let totalSnapshots = 0;
      let accSum = 0;
      let lastValidatedUtc = null;
      for (const snap of Object.values(allHist)) {
        if (!snap || snap.validated !== true || !snap.validation) continue;
        const acc = Number(snap.validation.accuracy);
        if (!Number.isFinite(acc)) continue;
        totalSnapshots++;
        accSum += acc;
        const v = String(snap.validation.validatedAt || '');
        if (!lastValidatedUtc || v > lastValidatedUtc) lastValidatedUtc = v;
      }
      const averageAccuracy = totalSnapshots > 0 ? accSum / totalSnapshots : 0;
      await fetch(`${env.FB_DB_URL}ai_predictions/performance/latest.json?auth=${token}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          totalSnapshots,
          averageAccuracy: Number(averageAccuracy.toFixed(4)),
          lastValidatedUtc,
        }),
      }).catch(() => {});
    }
  } catch (e) {
    console.error('[VALIDATE] Aggregate failed: ' + e.message);
  }

  return processed;
}

async function handleValidatePredictions(env) {
  try {
    const processed = await validatePredictions(env, null);
    return new Response(JSON.stringify({ ok: true, processed }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (e) {
    return new Response(JSON.stringify({ ok: false, error: String(e?.message || e) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
}

// ============ Briefing endpoint (Llama 3.2 via Workers AI) ============

export {
  buildPredictiveModel,
  handlePredictions,
  validatePredictions,
  handleValidatePredictions,
  MIN_VALIDATION_AGE_HOURS,
  DEFAULT_VALIDATION_WINDOW_HOURS,
  MAX_VALIDATION_PER_RUN,
};
