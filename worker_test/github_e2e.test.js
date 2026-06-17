// End-to-end tests for the GitHub proxy worker's request lifecycle.
// Drives the real `fetch` handler with a mock env + stubbed GitHub API.
import gh from '../cloudflare_github_worker.js';

const ENV = {
  WORKER_SHARED_SECRET: 'wsec',
  GITHUB_REPO: 'owner/repo',
  GITHUB_TOKEN: 'ghtoken',
  GITHUB_RATE_LIMIT: '100000',
};

let ghCalls;
beforeEach(() => {
  ghCalls = [];
  globalThis.fetch = async (url, opts) => {
    const u = String(url);
    ghCalls.push({ url: u, opts });
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
function req(method, path, { auth, body } = {}) {
  ipSeq += 1;
  const h = new Map();
  if (auth) h.set('authorization', auth);
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

  test('missing/invalid bearer is 401', async () => {
    expect((await gh.fetch(req('GET', '/config'), ENV)).status).toBe(401);
    expect((await gh.fetch(req('GET', '/config', { auth: 'Bearer nope' }), ENV)).status).toBe(401);
  });

  test('/config reports repo + connected', async () => {
    const res = await gh.fetch(req('GET', '/config', { auth: 'Bearer wsec' }), ENV);
    expect(res.status).toBe(200);
    const b = await res.json();
    expect(b).toMatchObject({ ok: true, repo: 'owner/repo', connected: true, canDispatch: true });
  });

  test('POST /dispatch forwards a repository_dispatch with the server-side token', async () => {
    const res = await gh.fetch(
      req('POST', '/dispatch', { auth: 'Bearer wsec', body: { event_type: 'guardian_drill', client_payload: { mode: 'automatic', target: 'tool/guardian_drill_target.mjs' } } }),
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
    const res = await gh.fetch(req('GET', '/runs', { auth: 'Bearer wsec' }), ENV);
    expect(res.status).toBe(200);
    const b = await res.json();
    expect(b.runs).toHaveLength(1);
    expect(b.runs[0]).toMatchObject({ id: 11, name: 'CI', branch: 'main', event: 'push', conclusion: 'success', runNumber: 5 });
  });

  test('unknown route is 404', async () => {
    const res = await gh.fetch(req('GET', '/nope', { auth: 'Bearer wsec' }), ENV);
    expect(res.status).toBe(404);
  });
});
