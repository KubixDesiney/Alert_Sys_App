import { corsHeaders } from './config.js';
import { loadCoreData } from './load_core.js';
import { _aggregateWeek, _briefingDateKey, _briefingFactorySlug, _topSupervisorWeek, _typeName } from './utils.js';

async function handleBriefing(request, env) {
  try {
    const url = new URL(request.url);
    const force = url.searchParams.get('force') === '1';
    // Optional factory scope — when set the briefing covers only that plant.
    const factoryParam = url.searchParams.get('factory') || null;
    const factorySlug = factoryParam ? _briefingFactorySlug(factoryParam) : null;

    const coreCtx = await loadCoreData(env);
    const today = _briefingDateKey(new Date());

    // Factory-scoped briefings are stored under a sub-path; global ones at root.
    const latestPath = factorySlug
      ? `ai_briefing/factory/${factorySlug}/latest.json`
      : 'ai_briefing/latest.json';
    const historyPath = factorySlug
      ? `ai_briefing/factory/${factorySlug}/history/${today}.json`
      : `ai_briefing/history/${today}.json`;

    if (!force) {
      const existing = await fetch(`${env.FB_DB_URL}${latestPath}?auth=${coreCtx.token}`);
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

    const stats = _aggregateWeek(coreCtx.alertsMap || {}, factoryParam);
    const topType = Object.entries(stats.byType || {}).sort((a, b) => b[1] - a[1])[0];
    const topFactory = Object.entries(stats.byFactory || {}).sort((a, b) => b[1] - a[1])[0];
    const resolutionRate = stats.total > 0 ? Math.round((stats.solved / stats.total) * 100) : 0;

    // --- Predictive accuracy & top prediction for this factory ---
    let accuracyPct = null;
    let predictiveInsight = null;
    try {
      const [accRes, predRes] = await Promise.all([
        fetch(`${env.FB_DB_URL}ai_predictions/performance/latest.json?auth=${coreCtx.token}`),
        fetch(`${env.FB_DB_URL}ai_predictions/latest.json?auth=${coreCtx.token}`),
      ]);
      if (accRes.ok) {
        const accData = await accRes.json();
        if (accData?.averageAccuracy != null && accData?.totalSnapshots > 0) {
          accuracyPct = Math.round(accData.averageAccuracy * 100);
        }
      }
      if (predRes.ok) {
        const predData = await predRes.json();
        const preds = Array.isArray(predData?.predictions) ? predData.predictions : [];
        // Pick highest-confidence prediction scoped to factory (or global top if no factory).
        const scopedPreds = factoryParam
          ? preds.filter(p => String(p?.usine || '') === factoryParam)
          : preds;
        scopedPreds.sort((a, b) => (b.confidence || 0) - (a.confidence || 0));
        if (scopedPreds.length > 0) {
          const top = scopedPreds[0];
          predictiveInsight = {
            type: top.type || null,
            convoyeur: top.convoyeur ?? null,
            confidence: top.confidence ?? null,
          };
        }
      }
    } catch (e) {
      console.warn('[BRIEFING] Predictive fetch failed: ' + e.message);
    }

    // --- Top performing supervisor this week ---
    const topSup = _topSupervisorWeek(coreCtx.alertsMap || {}, coreCtx.usersMap || {}, factoryParam);

    // --- Build AI prompt ---
    const factoryLine = factoryParam ? `\n- Plant scope: ${factoryParam}` : '';
    const accuracyLine = accuracyPct != null ? `\n- AI predictive model accuracy (validated): ${accuracyPct}%` : '';
    const predLine = predictiveInsight?.type
      ? `\n- AI expects a possible ${_typeName(predictiveInsight.type)} issue${predictiveInsight.convoyeur != null ? ` on Line ${predictiveInsight.convoyeur}` : ''} today (confidence: ${predictiveInsight.confidence ?? '?'}%)`
      : '';
    const supLine = topSup
      ? `\n- Top supervisor this week: ${topSup.name} resolved ${topSup.count} alerts${topSup.topType ? ` (fastest for ${_typeName(topSup.topType)} issues)` : ''}`
      : '';

    const prompt = `You are an industrial operations briefing officer addressing the production manager at the start of the day. Write a single, warm, concise paragraph (3 to 4 sentences, no bullets, no headers, no markdown, no lists). Use these facts from the past 7 days:${factoryLine}
- Total alerts: ${stats.total}
- Resolved: ${stats.solved} (${resolutionRate}% resolution rate)
- Critical alerts: ${stats.critical}
- Currently claimed: ${stats.inProgress}, pending: ${stats.pending}
- Average resolution time: ${stats.avgResolutionMin} minutes
- Fastest fix: ${stats.fastestMin ?? 'n/a'} min · slowest: ${stats.slowestMin ?? 'n/a'} min
- Most frequent alert type: ${topType ? `${_typeName(topType[0])} (${topType[1]})` : 'none'}
- Most active site: ${topFactory ? `${topFactory[0]} (${topFactory[1]})` : 'none'}
- AI auto-assignments: ${stats.aiAssigned}${accuracyLine}${predLine}${supLine}

Begin with "Good morning". Acknowledge what is going well, name the top supervisor by name if present, weave in the AI prediction if present, and close with a forward-looking sentence about today. Sound calm, professional, and human — not a press release.`;

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
      factoryScope: factoryParam || null,
      accuracyPct,
      predictiveInsight,
      topSupervisor: topSup,
    };

    await fetch(`${env.FB_DB_URL}${latestPath}?auth=${coreCtx.token}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    });
    await fetch(`${env.FB_DB_URL}${historyPath}?auth=${coreCtx.token}`, {
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

export { handleBriefing };
