import { getFirebaseToken } from './auth.js';
import { corsHeaders } from './config.js';
import { _AI_FALLBACK, _TYPE_LABELS } from './utils.js';

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
// Firebase keys cannot contain '.', '#', '$', '[', ']', '/' — replace ':' and '.'
// in ISO timestamps so they survive as a valid path segment.

export { _runLlama, handleAiProxy, handleAiSuggest };
