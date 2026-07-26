// Route-level integration tests for the store worker: real request/response
// flows through default.fetch — security headers (CSP nonce agreement, HSTS),
// security.txt, checkout error paths, redirects, and page rendering that the
// pure-helper suites don't exercise. No live network (fetch mocked where a
// route would call out).
import { jest } from '@jest/globals';
import worker from '../../cloudflare_store_worker.js';

const get = (path, env = {}) => worker.fetch(new Request(`https://sias-store.example${path}`), env);
const post = (path, body, env = {}) =>
  worker.fetch(
    new Request(`https://sias-store.example${path}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'cf-connecting-ip': `it-${Math.random()}` },
      body: typeof body === 'string' ? body : JSON.stringify(body),
    }),
    env,
  );

describe('security headers on every page', () => {
  test.each(['/', '/buy', '/copilot', '/welcome', '/success'])('%s carries the full header set', async (path) => {
    const res = await get(path);
    expect(res.status).toBe(200);
    expect(res.headers.get('Strict-Transport-Security')).toContain('max-age=31536000');
    expect(res.headers.get('X-Frame-Options')).toBe('DENY');
    expect(res.headers.get('X-Content-Type-Options')).toBe('nosniff');
    expect(res.headers.get('Referrer-Policy')).toBe('strict-origin-when-cross-origin');
    expect(res.headers.get('Permissions-Policy')).toContain('camera=()');
    const csp = res.headers.get('Content-Security-Policy');
    expect(csp).toContain("default-src 'self'");
    expect(csp).toContain('fonts.googleapis.com');
    expect(csp).toContain("frame-ancestors 'none'");
    // script-src must be nonce-based — never 'unsafe-inline'.
    expect(csp).toMatch(/script-src 'self' 'nonce-[0-9a-f]{32}'/);
    expect(csp).not.toContain("script-src 'self' 'unsafe-inline'");
  });

  test('the CSP nonce in the header matches every <script> tag in the body', async () => {
    const res = await get('/buy');
    const nonce = res.headers.get('Content-Security-Policy').match(/'nonce-([0-9a-f]{32})'/)[1];
    const body = await res.text();
    const scriptTags = body.match(/<script[^>]*>/g) ?? [];
    expect(scriptTags.length).toBeGreaterThan(0);
    for (const tag of scriptTags) expect(tag).toContain(`nonce="${nonce}"`);
    // No inline event handlers anywhere (they would be blocked by this CSP).
    expect(body).not.toMatch(/\son(click|change|submit|load|input)=/);
  });

  test('nonces differ between responses', async () => {
    const a = (await get('/')).headers.get('Content-Security-Policy');
    const b = (await get('/')).headers.get('Content-Security-Policy');
    expect(a).not.toBe(b);
  });
});

describe('/.well-known/security.txt', () => {
  test('serves RFC 9116 fields with a ~1y expiry', async () => {
    const res = await get('/.well-known/security.txt', { SALES_EMAIL: 'security@example.com' });
    expect(res.status).toBe(200);
    expect(res.headers.get('Content-Type')).toContain('text/plain');
    const text = await res.text();
    expect(text).toContain('Contact: mailto:security@example.com');
    expect(text).toContain('Preferred-Languages: en, fr');
    const expires = new Date(text.match(/Expires: (.+)/)[1]);
    const days = (expires.getTime() - Date.now()) / 86400000;
    expect(days).toBeGreaterThan(360);
    expect(days).toBeLessThan(370);
  });
});

describe('checkout error paths (card mode)', () => {
  const env = { SALES_MODE: 'card' };

  test('the B2B order form always has a durable success state', async () => {
    const res = await get('/buy?plan=growth&billing=annual', env);
    const body = await res.text();
    expect(body).toContain('id="quote-ok"');
    expect(body).toContain('name="pmEmail"');
    expect(body).toContain('name="supervisorEmail"');
  });

  test('503 when Stripe is unconfigured', async () => {
    const res = await post('/api/checkout', {
      name: 'Amine Ben Salah', email: 'a@b.example', company: 'Nagati Steel Works',
      plan: 'growth', billing: 'annual', method: 'stripe',
    }, env);
    expect(res.status).toBe(503);
  });

  test('400 on validation failure lists the problems', async () => {
    const res = await post('/api/checkout', { name: 'A', email: 'junk', plan: 'platinum' }, { ...env, STRIPE_SECRET_KEY: 'sk_test_x' });
    expect(res.status).toBe(400);
    const body = await res.json();
    expect(body.error).toContain('email');
    expect(body.error).toContain('plan');
  });

  test('400 on a non-JSON body', async () => {
    const res = await post('/api/checkout', '{oops', { ...env, STRIPE_SECRET_KEY: 'sk_test_x' });
    expect(res.status).toBe(400);
  });

  test('502 with the provider message when Stripe rejects', async () => {
    const realFetch = global.fetch;
    global.fetch = jest.fn(async () => new Response(JSON.stringify({ error: { message: 'Invalid API key provided' } }), { status: 401 }));
    try {
      const res = await post('/api/checkout', {
        name: 'Amine Ben Salah', email: 'a@b.example', company: 'Nagati Steel Works',
        plan: 'growth', billing: 'annual', method: 'stripe',
      }, { ...env, STRIPE_SECRET_KEY: 'sk_test_x' });
      expect(res.status).toBe(502);
      expect((await res.json()).error).toContain('Invalid API key');
    } finally {
      global.fetch = realFetch;
    }
  });
});

describe('misc routes', () => {
  test('/config never treats the legacy approved webhook as Accept/Paid-ready', async () => {
    const res = await get('/config', {
      N8N_APPROVED_WEBHOOK_URL: 'https://legacy.example/hook',
    });
    const body = await res.json();
    expect(body.hasConfirmedWebhook).toBe(false);
    expect(body.hasPaidWebhook).toBe(false);
  });

  test('/cancel redirects to pricing; OPTIONS answers CORS preflight', async () => {
    const res = await get('/cancel');
    expect(res.status).toBe(302);
    expect(res.headers.get('Location')).toBe('https://sias-store.example/#pricing');
    const opt = await worker.fetch(new Request('https://sias-store.example/api/kubix', { method: 'OPTIONS' }), {});
    expect(opt.status).toBe(200);
    expect(opt.headers.get('Access-Control-Allow-Methods')).toContain('POST');
  });

  test('unknown paths fall back to the landing page', async () => {
    const res = await get('/definitely-not-a-route');
    expect(res.status).toBe(200);
    expect(await res.text()).toContain('Smart Industrial Alert System');
  });

  test('/api/session rejects malformed ids before touching Stripe', async () => {
    const res = await get('/api/session?id=<script>');
    expect(res.status).toBe(400);
  });

  test('/api/ctp-order rejects malformed ids', async () => {
    const res = await get('/api/ctp-order?id=..');
    expect(res.status).toBe(400);
  });
});
