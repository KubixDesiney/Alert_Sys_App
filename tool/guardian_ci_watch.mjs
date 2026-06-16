// Guardian CI watcher — turns failed GitHub Actions runs into fix-pipeline
// signals, triaged by the shared detection brain (classifyFailure). Called from
// the autonomous bug-fix agent's signal-gathering phase. Defensive: never throws.
import { classifyFailure } from './guardian_detect.mjs';

/** Pure: map failed workflow runs -> issue signals (severity/category/model). */
export function ciSignalsFromRuns(runs = [], routing) {
  const out = [];
  for (const r of runs) {
    if (!r || r.conclusion !== 'failure') continue;
    const text = `${r.name || ''} ${r.display_title || ''} ${r.head_branch || ''} failed`;
    const c = classifyFailure(text, routing);
    out.push({
      severity: c.severity === 'high' ? 'critical' : c.severity,
      area: 'ci',
      category: c.category,
      message: `GitHub Actions failed: ${r.name || 'workflow'} on ${r.head_branch || '?'}`,
      model: c.model,
      runId: r.id,
      url: r.html_url || '',
    });
  }
  return out;
}

/** Fetch recent failed runs from GitHub and push signals onto the agent's bag. */
export async function collectCiSignals(signals, { token, repo, fetch = globalThis.fetch, routing } = {}) {
  try {
    if (!token || !repo || typeof repo !== 'string') return signals;
    const res = await fetch(
      `https://api.github.com/repos/${repo}/actions/runs?status=completed&per_page=15`,
      {
        headers: {
          Authorization: `Bearer ${token}`,
          Accept: 'application/vnd.github+json',
          'User-Agent': 'alertsys-guardian',
        },
      },
    );
    if (!res.ok) return signals;
    const data = await res.json();
    const failed = (data.workflow_runs || []).filter((r) => r && r.conclusion === 'failure');
    const sigs = ciSignalsFromRuns(failed, routing);
    if (Array.isArray(signals.issues)) signals.issues.push(...sigs);
    if (!Array.isArray(signals.ci)) signals.ci = [];
    signals.ci.push(...sigs);
  } catch (_) {
    if (signals && Array.isArray(signals.skipped)) {
      signals.skipped.push({ area: 'ci', error: 'ci_watch_failed' });
    }
  }
  return signals;
}
