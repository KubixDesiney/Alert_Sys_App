/**
 * GitHub proxy worker for the SuperAdmin Infrastructure + Guardian console.
 *
 * Holds the GitHub token SERVER-SIDE; the app authenticates with WORKER_SHARED_SECRET
 * and never sees the token. Per-company: pass ?repo=owner/name or set GITHUB_REPO.
 *
 * Deploy:  npx wrangler deploy --config wrangler.github.toml
 * Secrets: GITHUB_TOKEN (fine-grained PAT or GitHub App token, read-only: actions, pulls, deployments)
 *          WORKER_SHARED_SECRET (bearer the app authenticates with)
 * Vars:    GITHUB_REPO (default "owner/name"); GITHUB_RATE_LIMIT (req/min/ip, default 120)
 */
const GH = 'https://api.github.com';
const UA = 'alertsys-guardian';

// ── auth / rate limit ─────────────────────────────────────────────────────
export function timingSafeEqual(a, b) {
  const sa = String(a == null ? '' : a);
  const sb = String(b == null ? '' : b);
  let diff = sa.length ^ sb.length;
  const n = Math.max(sa.length, sb.length);
  for (let i = 0; i < n; i++) diff |= (sa.charCodeAt(i) || 0) ^ (sb.charCodeAt(i) || 0);
  return diff === 0;
}
const RL = new Map();
export function rateLimit(buckets, key, limit, windowMs, now = Date.now()) {
  const arr = (buckets.get(key) || []).filter((t) => now - t < windowMs);
  arr.push(now);
  buckets.set(key, arr);
  if (buckets.size > 5000) {
    const oldest = buckets.keys().next().value;
    if (oldest !== key) buckets.delete(oldest);
  }
  return arr.length <= limit;
}

// ── pure mappers (trim GitHub payloads to what the console renders) ─────────
export function mapRun(r = {}) {
  return {
    id: r.id,
    name: r.name || r.display_title || '',
    workflow: r.path || '',
    status: r.status || '',            // queued | in_progress | completed
    conclusion: r.conclusion || null,  // success | failure | cancelled | null
    branch: r.head_branch || '',
    event: r.event || '',
    actor: (r.actor && r.actor.login) || (r.triggering_actor && r.triggering_actor.login) || '',
    runNumber: r.run_number,
    createdAt: r.created_at || '',
    updatedAt: r.updated_at || '',
    url: r.html_url || '',
  };
}
export function mapPull(p = {}) {
  return {
    number: p.number,
    title: p.title || '',
    state: p.merged_at ? 'merged' : (p.state || ''),
    draft: !!p.draft,
    user: (p.user && p.user.login) || '',
    branch: (p.head && p.head.ref) || '',
    createdAt: p.created_at || '',
    url: p.html_url || '',
  };
}
export function mapDeployment(d = {}) {
  return {
    id: d.id,
    environment: d.environment || '',
    ref: d.ref || '',
    sha: (d.sha || '').slice(0, 7),
    creator: (d.creator && d.creator.login) || '',
    createdAt: d.created_at || '',
    description: d.description || '',
  };
}
export function mapJob(j = {}) {
  return {
    id: j.id,
    name: j.name || '',
    status: j.status || '',
    conclusion: j.conclusion || null,
    startedAt: j.started_at || '',
    completedAt: j.completed_at || '',
    steps: Array.isArray(j.steps)
      ? j.steps.map((s) => ({ name: s.name, status: s.status, conclusion: s.conclusion, number: s.number }))
      : [],
  };
}

// ── http ───────────────────────────────────────────────────────────────────
const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type',
  'Access-Control-Allow-Methods': 'GET, OPTIONS',
};
function json(obj, status = 200, extra = {}) {
  return new Response(JSON.stringify(obj), {
    status, headers: { 'Content-Type': 'application/json', ...CORS, ...extra },
  });
}
async function ghGet(env, repo, path) {
  const res = await fetch(`${GH}/repos/${repo}${path}`, {
    headers: {
      Authorization: `Bearer ${env.GITHUB_TOKEN}`,
      Accept: 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
      'User-Agent': UA,
    },
  });
  if (!res.ok) throw new Error(`github ${path}: ${res.status}`);
  return res.json();
}

export default {
  async fetch(req, env, ctx) {
    if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: CORS });
    const url = new URL(req.url);
    const ip = req.headers.get('cf-connecting-ip') || 'unknown';
    if (!rateLimit(RL, ip, Number(env.GITHUB_RATE_LIMIT || 120), 60000)) {
      return json({ error: 'rate_limited' }, 429, { 'Retry-After': '60' });
    }
    const auth = req.headers.get('authorization') || '';
    const presented = auth.startsWith('Bearer ') ? auth.slice(7) : '';
    if (!env.WORKER_SHARED_SECRET || !timingSafeEqual(presented, env.WORKER_SHARED_SECRET)) {
      return json({ error: 'unauthorized' }, 401, { 'WWW-Authenticate': 'Bearer' });
    }
    const repo = url.searchParams.get('repo') || env.GITHUB_REPO || '';
    const path = url.pathname.replace(/\/+$/, '');
    try {
      if (path === '/config') {
        return json({ ok: true, repo, connected: !!env.GITHUB_TOKEN });
      }
      if (!env.GITHUB_TOKEN || !repo) return json({ error: 'not_configured', repo }, 503);

      if (path === '/runs') {
        const d = await ghGet(env, repo, '/actions/runs?per_page=20');
        return json({ runs: (d.workflow_runs || []).map(mapRun) });
      }
      if (path === '/pulls') {
        const d = await ghGet(env, repo, '/pulls?state=all&per_page=20&sort=updated&direction=desc');
        return json({ pulls: (d || []).map(mapPull) });
      }
      if (path === '/deployments') {
        const d = await ghGet(env, repo, '/deployments?per_page=20');
        return json({ deployments: (d || []).map(mapDeployment) });
      }
      if (path === '/run-jobs') {
        const id = url.searchParams.get('id');
        if (!id) return json({ error: 'missing id' }, 400);
        const d = await ghGet(env, repo, `/actions/runs/${encodeURIComponent(id)}/jobs`);
        return json({ jobs: (d.jobs || []).map(mapJob) });
      }
      return json({ error: 'not_found' }, 404);
    } catch (e) {
      return json({ error: String((e && e.message) || e) }, 502);
    }
  },
};
