/**
 * GitHub proxy worker for the SuperAdmin / Guardian console.
 *
 * Holds the GitHub token SERVER-SIDE; the app authenticates with WORKER_SHARED_SECRET.
 * Per-company repo + token come from the RTDB vault once the IT team fills them
 * in via the Guardian console (so they self-serve, no redeploy). Env vars are
 * only bootstrap fallbacks before the vault is populated:
 *   ai_agents/guardian/repo            (owner/name)
 *   ai_agent_secrets/guardian/githubToken
 *
 * Deploy:  npx wrangler deploy --config wrangler.github.toml
 * Secrets: WORKER_SHARED_SECRET (required); GITHUB_TOKEN (optional bootstrap fallback);
 *          FIREBASE_SERVICE_ACCOUNT + FB_DB_URL (optional, enable the UI-managed vault).
 * Vars:    GITHUB_REPO (optional bootstrap fallback); GITHUB_RATE_LIMIT (req/min/ip, default 120).
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

// ── Firebase service-account auth (for the UI-managed RTDB vault) ───────────
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

export function normalizeRepo(value) {
  let raw = String(value == null ? '' : value).trim();
  if (!raw) return '';
  if (raw.startsWith('git@github.com:')) {
    raw = raw.slice('git@github.com:'.length);
  } else {
    try {
      const url = new URL(raw);
      raw = url.pathname;
    } catch (_) {
      // Keep non-URL owner/name input as-is.
    }
  }
  let parts = raw.replace(/^\/+|\/+$/g, '').split('/').filter(Boolean);
  if (parts[0] && parts[0].toLowerCase().replace(/^www\./, '').endsWith('github.com')) {
    parts = parts.slice(1);
  }
  if (parts[0] && parts[0].toLowerCase() === 'repos') parts = parts.slice(1);
  if (parts.length < 2) return '';
  const owner = String(parts[0] || '').trim();
  const repo = String(parts[1] || '').trim().replace(/\.git$/, '');
  if (!owner || !repo || /\s/.test(owner) || /\s/.test(repo)) return '';
  return `${owner}/${repo}`;
}

const CRED_CACHE_TTL_MS = 60000;
let _credCache = { at: 0, repo: '', token: '' };

function hasText(value) {
  return String(value == null ? '' : value).trim().length > 0;
}

export function chooseGithubCreds({
  envRepo = '',
  envToken = '',
  vaultRepo = '',
  vaultToken = '',
} = {}) {
  const vaultTouched = hasText(vaultRepo) || hasText(vaultToken);
  if (vaultTouched) {
    return {
      repo: normalizeRepo(vaultRepo),
      token: String(vaultToken == null ? '' : vaultToken).trim(),
    };
  }
  return {
    repo: normalizeRepo(envRepo),
    token: String(envToken == null ? '' : envToken).trim(),
  };
}

export function resetGithubCredCache() {
  _credCache = { at: 0, repo: '', token: '' };
}

async function resolveCreds(env, options = {}) {
  const envRepo = normalizeRepo(env.GITHUB_REPO || '');
  const envTok = env.GITHUB_TOKEN || '';
  const now = Date.now();
  if (!options.bypassCache && now - _credCache.at < CRED_CACHE_TTL_MS) {
    return { repo: _credCache.repo, token: _credCache.token };
  }
  if (env.FIREBASE_SERVICE_ACCOUNT && env.FB_DB_URL) {
    try {
      const t = await getAccessToken(env);
      const vaultRepo = await rtdbGet(env, t, 'ai_agents/guardian/repo');
      const vaultToken = await rtdbGet(env, t, 'ai_agent_secrets/guardian/githubToken');
      const creds = chooseGithubCreds({ envRepo, envToken: envTok, vaultRepo, vaultToken });
      _credCache = { at: now, repo: creds.repo, token: creds.token };
      return { repo: _credCache.repo, token: _credCache.token };
    } catch (_) { /* fall through to env */ }
  }
  const creds = chooseGithubCreds({ envRepo, envToken: envTok });
  _credCache = { at: now, repo: creds.repo, token: creds.token };
  return { repo: _credCache.repo, token: _credCache.token };
}

// ── Firebase SuperAdmin gate for the public (non-service-binding) route ─────
// The Guardian console holds a server-side GitHub token; a caller who merely
// recovers the client-shipped WORKER_SHARED_SECRET must NOT be able to drive
// token-backed reads/dispatches. The client always sends the signed-in user's
// Firebase ID token as `X-Firebase-Auth: Bearer …`; the direct route requires
// it to belong to a SuperAdmin (mirrors deploy/pages/guardian-proxy). The
// RTDB read is authorized by the ID token itself, so an invalid/expired token
// cannot read the role. Requests through the internal service binding
// (Pages proxy) already did this check and call with { skipAuth: true }.
function bearerToken(header) {
  const value = String(header || '');
  return value.toLowerCase().startsWith('bearer ') ? value.slice(7).trim() : '';
}
function decodeJwtPayload(token) {
  const parts = String(token || '').split('.');
  if (parts.length < 2 || !parts[1]) return {};
  const normalized = parts[1].replace(/-/g, '+').replace(/_/g, '/');
  const padded = normalized.padEnd(Math.ceil(normalized.length / 4) * 4, '=');
  try { return JSON.parse(atob(padded)); } catch (_) { return {}; }
}
async function isSuperadminFirebaseToken(env, token) {
  if (!token || !env.FB_DB_URL) return false;
  const payload = decodeJwtPayload(token);
  const uid = String(payload.user_id || payload.sub || '');
  if (!uid) return false;
  const base = env.FB_DB_URL.endsWith('/') ? env.FB_DB_URL.slice(0, -1) : env.FB_DB_URL;
  let res;
  try {
    res = await fetch(
      `${base}/users/${encodeURIComponent(uid)}/role.json?auth=${encodeURIComponent(token)}`,
      { headers: { Accept: 'application/json' } },
    );
  } catch (_) {
    return false;
  }
  if (!res.ok) return false;
  const role = String((await res.json()) || '');
  return role === 'superadmin' || role === 'SuperAdmin';
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

/**
 * Keep only the last [max] characters of a raw log, trimmed to a clean line
 * boundary so the live terminal never starts mid-line. GitHub job logs can be
 * megabytes; the console only renders a live tail.
 */
export function tailText(text, max = 16000) {
  const s = String(text == null ? '' : text);
  if (s.length <= max) return s;
  const cut = s.slice(s.length - max);
  const nl = cut.indexOf('\n');
  return nl >= 0 && nl < cut.length - 1 ? cut.slice(nl + 1) : cut;
}

/**
 * Strip the leading "2026-06-18T12:00:01.1234567Z " ISO timestamp GitHub prefixes
 * on every raw-log line, so the terminal can render its own clock and the real
 * command output (`$ npm test`, etc.) reads cleanly.
 */
export function stripLogTimestamps(text) {
  return String(text == null ? '' : text)
    .split('\n')
    .map((l) => l.replace(/^\d{4}-\d{2}-\d{2}T[\d:.]+Z\s/, ''))
    .join('\n');
}

// ── http ───────────────────────────────────────────────────────────────────
const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type, x-firebase-auth',
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
// Raw text fetch (GitHub returns job logs as a 302 -> signed blob URL). We follow
// the redirect manually and drop the Authorization header on the second hop so the
// signed URL accepts it. Returns '' (not throw) when logs aren't ready yet (404).
async function ghGetText(token, repo, path) {
  const res = await fetch(`${GH}/repos/${repo}${path}`, {
    headers: { Authorization: `Bearer ${token}`, Accept: 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28', 'User-Agent': UA },
    redirect: 'manual',
  });
  if (res.status >= 300 && res.status < 400) {
    const loc = res.headers.get('location');
    if (!loc) return '';
    const follow = await fetch(loc, { headers: { 'User-Agent': UA } });
    if (!follow.ok) return '';
    return follow.text();
  }
  if (res.status === 404) return '';
  if (!res.ok) throw new Error(`github ${path}: ${res.status}`);
  return res.text();
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

export async function handleGithubProxyRequest(req, env, options = {}) {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: CORS });
  const url = new URL(req.url);
  const ip = req.headers.get('cf-connecting-ip') || 'unknown';
  if (!rateLimit(RL, ip, Number(env.GITHUB_RATE_LIMIT || 120), 60000)) {
    return json({ error: 'rate_limited' }, 429, { 'Retry-After': '60' });
  }
  if (!options.skipAuth) {
    // Public route: require a valid SuperAdmin Firebase ID token. The legacy
    // client-shipped shared secret is NOT accepted here — recovering it from a
    // build must not grant access to the server-side GitHub token.
    const fbToken = bearerToken(req.headers.get('x-firebase-auth'));
    if (!fbToken) {
      return json({ error: 'unauthorized' }, 401, { 'WWW-Authenticate': 'Bearer' });
    }
    if (!(await isSuperadminFirebaseToken(env, fbToken))) {
      return json({ error: 'forbidden' }, 403);
    }
  }
  const cacheControl = req.headers.get('cache-control') || '';
  const bypassCache =
    url.searchParams.get('fresh') === '1' ||
    cacheControl.toLowerCase().includes('no-cache');
  const creds = await resolveCreds(env, { bypassCache });
  const token = creds.token || '';
  const requestedRepo = normalizeRepo(url.searchParams.get('repo'));
  const path = url.pathname.replace(/\/+$/, '');
  try {
    if (path === '/config') {
      return json({
        ok: true,
        repo: creds.repo,
        connected: !!token && !!creds.repo,
        hasToken: !!token,
        canDispatch: !!token && !!creds.repo,
      });
    }
    // Bind every token-backed route to the configured Guardian repo. A caller
    // may not redirect the server-side token at a different repository (the
    // stored PAT/App token can have broader scope than the intended repo).
    if (requestedRepo && creds.repo && requestedRepo !== creds.repo) {
      return json({ error: 'repo_not_allowed', repo: creds.repo }, 403);
    }
    const repo = creds.repo || requestedRepo || '';
    if (!token || !repo) {
      return json({
        error: 'not_configured',
        repo,
        connected: !!token && !!repo,
        hasToken: !!token,
      }, 503);
    }
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
    if (path === '/job-logs') {
      // Raw stdout of one job (the real `$ npm test` / build output) for the
      // live Guardian terminal. Best-effort: empty while the job is warming up.
      const id = url.searchParams.get('id');
      if (!id) return json({ error: 'missing id' }, 400);
      let text = '';
      try { text = await ghGetText(token, repo, `/actions/jobs/${encodeURIComponent(id)}/logs`); } catch (_) { text = ''; }
      return json({ id, logs: tailText(stripLogTimestamps(text)) });
    }
    return json({ error: 'not_found' }, 404);
  } catch (e) {
    return json({ error: String((e && e.message) || e) }, 502);
  }
}

export default {
  async fetch(req, env) {
    return handleGithubProxyRequest(req, env);
  },
};
