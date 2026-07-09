// End-to-end tests for the GitHub proxy worker's request lifecycle.
// Drives the real `fetch` handler with a mock env + stubbed GitHub API.
//
// Auth model (hardened 2026-07-09): the public route requires a SuperAdmin
// Firebase ID token in `X-Firebase-Auth: Bearer …`; the worker authorizes it by
// reading users/{uid}/role from RTDB with that same token. The legacy
// client-shipped WORKER_SHARED_SECRET is no longer accepted on this route.
import gh, { resetGithubCredCache } from '../cloudflare_github_worker.js';

const ENV = {
  WORKER_SHARED_SECRET: 'wsec',
  GITHUB_REPO: 'owner/repo',
  GITHUB_TOKEN: 'ghtoken',
  GITHUB_RATE_LIMIT: '100000',
  FB_DB_URL: 'https://db.example',
};

// Fake (unsigned) Firebase ID token — the worker only decodes the payload for
// the uid and then trusts the RTDB read, which we stub per-uid below.
function b64url(obj) {
  return Buffer.from(JSON.stringify(obj))
    .toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}
function fakeToken(uid) {
  return `hdr.${b64url({ user_id: uid })}.sig`;
}
const SUPERADMIN = `Bearer ${fakeToken('sa1')}`; // sa1 → role superadmin (stub)
const SUPERVISOR = `Bearer ${fakeToken('sup9')}`; // sup9 → role supervisor (stub)

let ghCalls;
beforeEach(() => {
  resetGithubCredCache();
  ghCalls = [];
  globalThis.fetch = async (url, opts) => {
    const u = String(url);
    ghCalls.push({ url: u, opts });
    // Stubbed RTDB role reads (the SuperAdmin gate).
    if (u.startsWith('https://db.example/users/')) {
      const role = u.includes('/users/sa1/') ? 'superadmin' : 'supervisor';
      return { ok: true, status: 200, json: async () => role };
    }
    if (u.endsWith('/dispatches')) return { ok: true, status: 204, text: async () => '' };
    if (u.includes('/actions/runs')) {
      return {
        ok: true,
        status: 200,
        json: async () => ({
          workflow_runs: [
            { id: 11, name: 'CI', head_branch: 'main', event: 'push', status: 'completed', conclusion: 'success', run_number: 5, html_url: 'https://gh/run/11' },
          ],
        }),
      };
    }
    return { ok: true, status: 200, json: async () => ({}) };
  };
});

let ipSeq = 0;
function req(method, path, { fbAuth, body } = {}) {
  ipSeq += 1;
  const h = new Map();
  if (fbAuth) h.set('x-firebase-auth', fbAuth);
  h.set('cf-connecting-ip', `10.0.0.${ipSeq}`);
  return {
    method,
    url: `https://ghproxy.example${path}`,
    headers: { get: (k) => (h.has(k.toLowerCase()) ? h.get(k.toLowerCase()) : null) },
    json: async () => body,
  };
}

describe('github proxy e2e', () => {
  test('CORS preflight returns 204', async () => {
    const res = await gh.fetch(req('OPTIONS', '/config'), ENV);
    expect(res.status).toBe(204);
  });

  test('missing Firebase token is 401', async () => {
    expect((await gh.fetch(req('GET', '/config'), ENV)).status).toBe(401);
  });

  test('non-SuperAdmin Firebase token is 403', async () => {
    expect((await gh.fetch(req('GET', '/config', { fbAuth: SUPERVISOR }), ENV)).status).toBe(403);
  });

  test('the client-shipped shared secret alone does NOT authorize', async () => {
    // Present the shared secret the old way (Authorization) and no Firebase token.
    const r = { ...req('GET', '/config'), };
    // Inject an Authorization: Bearer wsec header — must be ignored now.
    const h = new Map([['authorization', 'Bearer wsec'], ['cf-connecting-ip', '10.9.9.9']]);
    r.headers = { get: (k) => (h.has(k.toLowerCase()) ? h.get(k.toLowerCase()) : null) };
    expect((await gh.fetch(r, ENV)).status).toBe(401);
  });

  test('/config reports repo + connected for a SuperAdmin', async () => {
    const res = await gh.fetch(req('GET', '/config', { fbAuth: SUPERADMIN }), ENV);
    expect(res.status).toBe(200);
    const b = await res.json();
    expect(b).toMatchObject({ ok: true, repo: 'owner/repo', connected: true, canDispatch: true });
  });

  test('/config is not connected when the repo is missing', async () => {
    const res = await gh.fetch(
      req('GET', '/config', { fbAuth: SUPERADMIN }),
      { ...ENV, GITHUB_REPO: '' },
    );
    expect(res.status).toBe(200);
    const b = await res.json();
    expect(b).toMatchObject({
      ok: true,
      repo: '',
      connected: false,
      hasToken: true,
      canDispatch: false,
    });
  });

  test('normalizes GitHub URLs before calling the API', async () => {
    const res = await gh.fetch(req('GET', '/runs?repo=https%3A%2F%2Fgithub.com%2Fowner%2Frepo.git', { fbAuth: SUPERADMIN }), ENV);
    expect(res.status).toBe(200);
    const runsCall = ghCalls.find((c) => c.url.includes('/actions/runs'));
    expect(runsCall.url).toBe('https://api.github.com/repos/owner/repo/actions/runs?per_page=20');
  });

  test('rejects a repo query that differs from the configured repo (403)', async () => {
    const res = await gh.fetch(req('GET', '/runs?repo=attacker/secret', { fbAuth: SUPERADMIN }), ENV);
    expect(res.status).toBe(403);
    const b = await res.json();
    expect(b).toMatchObject({ error: 'repo_not_allowed', repo: 'owner/repo' });
    // The server-side token must never have reached attacker/secret.
    expect(ghCalls.some((c) => c.url.includes('attacker/secret'))).toBe(false);
  });

  test('POST /dispatch forwards a repository_dispatch with the server-side token', async () => {
    const res = await gh.fetch(
      req('POST', '/dispatch', { fbAuth: SUPERADMIN, body: { event_type: 'guardian_drill', client_payload: { mode: 'automatic', target: 'tool/guardian_drill_target.mjs' } } }),
      ENV,
    );
    expect(res.status).toBe(200);
    const b = await res.json();
    expect(b).toEqual({ ok: true, dispatched: 'guardian_drill' });

    const dispatch = ghCalls.find((c) => c.url.endsWith('/dispatches'));
    expect(dispatch).toBeDefined();
    expect(dispatch.url).toBe('https://api.github.com/repos/owner/repo/dispatches');
    expect(dispatch.opts.method).toBe('POST');
    const sent = JSON.parse(dispatch.opts.body);
    expect(sent.event_type).toBe('guardian_drill');
    expect(sent.client_payload).toEqual({ mode: 'automatic', target: 'tool/guardian_drill_target.mjs' });
    // token is attached server-side, never exposed to the caller
    expect(dispatch.opts.headers.Authorization).toBe('Bearer ghtoken');
  });

  test('/runs maps GitHub payloads to the trimmed shape', async () => {
    const res = await gh.fetch(req('GET', '/runs', { fbAuth: SUPERADMIN }), ENV);
    expect(res.status).toBe(200);
    const b = await res.json();
    expect(b.runs).toHaveLength(1);
    expect(b.runs[0]).toMatchObject({ id: 11, name: 'CI', branch: 'main', event: 'push', conclusion: 'success', runNumber: 5 });
  });

  test('unknown route is 404', async () => {
    const res = await gh.fetch(req('GET', '/nope', { fbAuth: SUPERADMIN }), ENV);
    expect(res.status).toBe(404);
  });

  test('the internal service binding (skipAuth) bypasses the Firebase gate', async () => {
    const { handleGithubProxyRequest } = await import('../cloudflare_github_worker.js');
    const res = await handleGithubProxyRequest(req('GET', '/config'), ENV, { skipAuth: true });
    expect(res.status).toBe(200);
  });
});
