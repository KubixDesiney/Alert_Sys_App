/**
 * GitHub proxy worker for the SuperAdmin / Guardian console.
 *
 * Holds the GitHub token SERVER-SIDE; the app authenticates with WORKER_SHARED_SECRET.
 * Per-company repo + token can come from EITHER env vars OR the RTDB vault that the
 * IT team fills in via the Guardian console (so they self-serve, no redeploy):
 *   ai_agents/guardian/repo            (owner/name)
 *   ai_agent_secrets/guardian/githubToken
 *
 * Deploy:  npx wrangler deploy --config wrangler.github.toml
 * Secrets: WORKER_SHARED_SECRET (required); GITHUB_TOKEN (optional if set via vault);
 *          FIREBASE_SERVICE_ACCOUNT + FB_DB_URL (optional, enable the vault fallback).
 * Vars:    GITHUB_REPO (optional default); GITHUB_RATE_LIMIT (req/min/ip, default 120).
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

// ── Firebase service-account auth (for the RTDB vault fallback) ─────────────
function b64url(s) { return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, ''); }
function b64urlBytes(b) { let s = ''; for (const x of b) s += String.fromCharCode(x); return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, ''); }
function pemToBuf(pem) {
  const body = pem.replace(/-----BEGIN [^-]+-----/, '').replace(/-----END [^-]+-----/, '').replace(/\s+/g, '');
  const bin = atob(body); const buf = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) buf[i] = bin.charCodeAt(i);
  return buf.buffer;
}
async function getAccessToken(env) {
  const sa = JSON.parse(env.FIREBASE_SERVICE_ACCOUNT);
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claim = b64url(JSON.stringify({
    iss: sa.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.database https://www.googleapis.com/auth/userinfo.email',
    aud: 'https://oauth2.googleapis.com/token', iat: now, exp: now + 3600,
  }));
  const key = await crypto.subtle.importKey('pkcs8', pemToBuf(sa.private_key),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']);
  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(`${header}.${claim}`));
  const jwt = `${header}.${claim}.${b64urlBytes(new Uint8Array(sig))}`;
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: jwt }),
  });
  const j = await res.json();
  if (!j.access_token) throw new Error('token error');
  return j.access_token;
}
async function rtdbGet(env, token, path) {
  const base = env.FB_DB_URL.endsWith('/') ? env.FB_DB_URL : env.FB_DB_URL + '/';
  const r = await fetch(`${base}${path}.json?access_token=${token}`);
  if (!r.ok) return null;
  return r.json();
}

let _credCache = { at: 0, repo: '', token: '' };
async function resolveCreds(env) {
  const envRepo = env.GITHUB_REPO || '';
  const envTok = env.GITHUB_TOKEN || '';
  if (envRepo && envTok) return { repo: envRepo, token: envTok };
  const now = Date.now();
  if (now - _credCache.at < 60000) {
    return { repo: envRepo || _credCache.repo, token: envTok || _credCache.token };
  }
  if (env.FIREBASE_SERVICE_ACCOUNT && env.FB_DB_URL) {
    try {
      const t = await getAccessToken(env);
      const repo = envRepo || (await rtdbGet(env, t, 'ai_agents/guardian/repo')) || '';
      const token = envTok || (await rtdbGet(env, t, 'ai_agent_secrets/guardian/githubToken')) || '';
      _credCache = { at: now, repo: String(repo || ''), token: String(token || '') };
      return { repo: _credCache.repo, token: _credCache.token };
    } catch (_) { /* fall through to env */ }
  }
  return { repo: envRepo, token: envTok };
}

// ── pure mappers (trim GitHub payloads to what the console renders) ─────────
export function mapRun(r = {}) {
  return {
    id: r.id, name: r.name || r.display_title || '', workflow: r.path || '',
    status: r.status || '', conclusion: r.conclusion || null,
    branch: r.head_branch || '', event: r.event || '',
    actor: (r.actor && r.actor.login) || (r.triggering_actor && r.triggering_actor.login) || '',
    runNumber: r.run_number, createdAt: r.created_at || '', updatedAt: r.updated_at || '', url: r.html_url || '',
  };
}
export function mapPull(p = {}) {
  return {
    number: p.number, title: p.title || '', state: p.merged_at ? 'merged' : (p.state || ''),
    draft: !!p.draft, user: (p.user && p.user.login) || '', branch: (p.head && p.head.ref) || '',
    createdAt: p.created_at || '', url: p.html_url || '',
  };
}
export function mapDeployment(d = {}) {
  return {
    id: d.id, environment: d.environment || '', ref: d.ref || '', sha: (d.sha || '').slice(0, 7),
    creator: (d.creator && d.creator.login) || '', createdAt: d.created_at || '', description: d.description || '',
  };
}
export function mapJob(j = {}) {
  return {
    id: j.id, name: j.name || '', status: j.status || '', conclusion: j.conclusion || null,
    startedAt: j.started_at || '', completedAt: j.completed_at || '',
    steps: Array.isArray(j.steps) ? j.steps.map((s) => ({ name: s.name, status: s.status, conclusion: s.conclusion, number: s.number })) : [],
  };
}

// ── http ───────────────────────────────────────────────────────────────────
const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
};
function json(obj, status = 200, extra = {}) {
  return new Response(JSON.stringify(obj), { status, headers: { 'Content-Type': 'application/json', ...CORS, ...extra } });
}
async function ghGet(token, repo, path) {
  const res = await fetch(`${GH}/repos/${repo}${path}`, {
    headers: { Authorization: `Bearer ${token}`, Accept: 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28', 'User-Agent': UA },
  });
  if (!res.ok) throw new Error(`github ${path}: ${res.status}`);
  return res.json();
}
async function ghPost(token, repo, path, body) {
  const res = await fetch(`${GH}/repos/${repo}${path}`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, Accept: 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28', 'User-Agent': UA, 'Content-Type': 'application/json' },
    body: JSON.stringify(body || {}),
  });
  if (!res.ok) throw new Error(`github ${path}: ${res.status} ${String(await res.text()).slice(0, 200)}`);
  return res.status;
}

export default {
  async fetch(req, env) {
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
    const creds = await resolveCreds(env);
    const repo = url.searchParams.get('repo') || creds.repo || '';
    const token = creds.token || '';
    const path = url.pathname.replace(/\/+$/, '');
    try {
      if (path === '/config') return json({ ok: true, repo, connected: !!token, canDispatch: !!token });
      if (!token || !repo) return json({ error: 'not_configured', repo, connected: !!token }, 503);
      if (req.method === 'POST' && path === '/dispatch') {
        // Trigger a repository_dispatch (e.g. the Guardian drill). Token stays server-side.
        let body = {};
        try { body = await req.json(); } catch (_) { /* empty body ok */ }
        const eventType = (body && body.event_type) || 'guardian_drill';
        const clientPayload = (body && typeof body.client_payload === 'object' && body.client_payload) || {};
        await ghPost(token, repo, '/dispatches', { event_type: eventType, client_payload: clientPayload });
        return json({ ok: true, dispatched: eventType });
      }
      if (path === '/runs') return json({ runs: ((await ghGet(token, repo, '/actions/runs?per_page=20')).workflow_runs || []).map(mapRun) });
      if (path === '/pulls') return json({ pulls: ((await ghGet(token, repo, '/pulls?state=all&per_page=20&sort=updated&direction=desc')) || []).map(mapPull) });
      if (path === '/deployments') return json({ deployments: ((await ghGet(token, repo, '/deployments?per_page=20')) || []).map(mapDeployment) });
      if (path === '/run-jobs') {
        const id = url.searchParams.get('id');
        if (!id) return json({ error: 'missing id' }, 400);
        return json({ jobs: ((await ghGet(token, repo, `/actions/runs/${encodeURIComponent(id)}/jobs`)).jobs || []).map(mapJob) });
      }
      return json({ error: 'not_found' }, 404);
    } catch (e) {
      return json({ error: String((e && e.message) || e) }, 502);
    }
  },
};
