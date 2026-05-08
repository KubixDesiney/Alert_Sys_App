import { corsHeaders } from './config.js';
import { loadCoreData } from './load_core.js';
import { buildSupStats, scoreSupervisor } from './scoring.js';
import { aiResolveFactory } from './utils.js';

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

export { handleSuggestAssignee };
