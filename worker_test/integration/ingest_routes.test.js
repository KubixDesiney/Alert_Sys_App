// Route-level integration tests for the ingest worker: real request/response
// flows through default.fetch with a mocked network — an in-memory fake RTDB
// answers firebaseio.com, a stub token endpoint answers oauth2.googleapis.com,
// and a throwaway RSA key makes the worker's real JWT signing path run. No
// live network anywhere.
import crypto from 'node:crypto';
import { jest } from '@jest/globals';
import worker from '../../cloudflare_ingest_worker.js';

const DB_URL = 'https://fake-db.firebaseio.com';

// A real (throwaway, generated-per-run) service account so getAccessToken's
// actual RS256 signing executes instead of being stubbed out.
const { privateKey } = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
const SERVICE_ACCOUNT = JSON.stringify({
  client_email: 'test@fake.iam.gserviceaccount.com',
  private_key: privateKey.export({ type: 'pkcs8', format: 'pem' }),
});

function getPath(db, segments) {
  let node = db;
  for (const s of segments) {
    if (node == null || typeof node !== 'object') return null;
    node = node[s];
  }
  return node === undefined ? null : node;
}

function setPath(db, segments, value) {
  let node = db;
  for (const s of segments.slice(0, -1)) {
    if (typeof node[s] !== 'object' || node[s] === null) node[s] = {};
    node = node[s];
  }
  node[segments.at(-1)] = value;
}

/** In-memory fake RTDB + Google token endpoint, installed as global fetch. */
function installFakeNetwork(initialDb = {}) {
  const state = { db: structuredClone(initialDb), pushes: 0, requests: [] };
  const json = (obj, status = 200) => new Response(JSON.stringify(obj), { status });
  global.fetch = jest.fn(async (url, init = {}) => {
    const u = String(url);
    state.requests.push({ url: u, method: (init.method || 'GET').toUpperCase() });
    if (u.startsWith('https://oauth2.googleapis.com/token')) return json({ access_token: 'tok' });
    if (u.startsWith(DB_URL)) {
      const path = new URL(u).pathname.replace(/^\/+/, '').replace(/\.json$/, '');
      const segments = path ? path.split('/') : [];
      const method = (init.method || 'GET').toUpperCase();
      if (method === 'GET') return json(getPath(state.db, segments));
      const body = init.body ? JSON.parse(init.body) : null;
      if (method === 'POST') {
        const id = `-Fake${++state.pushes}`;
        setPath(state.db, [...segments, id], body);
        return json({ name: id });
      }
      if (method === 'PATCH') {
        for (const [k, v] of Object.entries(body ?? {})) setPath(state.db, [...segments, ...k.split('/')], v);
        return json(body);
      }
      if (method === 'PUT') { setPath(state.db, segments, body); return json(body); }
      return json({ error: 'unsupported' }, 405);
    }
    throw new Error(`unexpected network call in test: ${u}`);
  });
  return state;
}

const baseEnv = () => ({
  FB_DB_URL: DB_URL,
  FIREBASE_SERVICE_ACCOUNT: SERVICE_ACCOUNT,
  INGEST_RATE_PER_MIN: '10000',
});

const post = (path, body, headers = {}, env = baseEnv()) =>
  worker.fetch(
    new Request(`https://alertsys-ingest.example${path}`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', ...headers },
      body: typeof body === 'string' ? body : JSON.stringify(body),
    }),
    env,
  );

const realFetch = global.fetch;
afterEach(() => { global.fetch = realFetch; });

describe('service status routes', () => {
  test('GET / and /config answer without any backend', async () => {
    const res = await worker.fetch(new Request('https://x.example/config'), {});
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.ok).toBe(true);
    const root = await worker.fetch(new Request('https://x.example/'), {});
    expect(root.status).toBe(200);
  });

  test('non-POST to an action route is 405', async () => {
    const res = await worker.fetch(new Request('https://x.example/anything', { method: 'PUT' }), {});
    expect(res.status).toBe(405);
  });
});

describe('POST /ingest/{connectorId}', () => {
  test('503 when the worker has no Firebase configuration', async () => {
    const res = await post('/ingest/c1', [{}], {}, {});
    expect(res.status).toBe(503);
  });

  test('404 unknown connector · 403 disabled · 401 wrong key', async () => {
    installFakeNetwork({
      connectors: {
        dead: { kind: 'custom', enabled: false },
        live: { kind: 'custom', enabled: true },
      },
      connector_secrets: { live: { ingestKey: 'k'.repeat(16) }, dead: { ingestKey: 'k'.repeat(16) } },
    });
    expect((await post('/ingest/nope', [{}], { 'x-alertsys-ingest': 'k'.repeat(16) })).status).toBe(404);
    expect((await post('/ingest/dead', [{}], { 'x-alertsys-ingest': 'k'.repeat(16) })).status).toBe(403);
    expect((await post('/ingest/live', [{}], { 'x-alertsys-ingest': 'wrong-key-000000' })).status).toBe(401);
  });

  test('400 on invalid JSON with a valid key', async () => {
    installFakeNetwork({
      connectors: { c400: { kind: 'custom', enabled: true } },
      connector_secrets: { c400: { ingestKey: 'k'.repeat(16) } },
    });
    const res = await post('/ingest/c400', '{not json', { 'x-alertsys-ingest': 'k'.repeat(16) });
    expect(res.status).toBe(400);
  });

  test('missing connector id is 400', async () => {
    const res = await post('/ingest/%20', [{}], {}, baseEnv());
    expect(res.status).toBe(400);
  });

  test('happy path: breaching telemetry becomes a normalized alert, normal telemetry is absorbed', async () => {
    const state = installFakeNetwork({
      connectors: { okc: { kind: 'opcua', enabled: true, factory: 'Usine X' } },
      connector_secrets: { okc: { ingestKey: 'k'.repeat(16) } },
    });
    const res = await post(
      '/ingest/okc',
      {
        readings: [
          { machine: 'MACH-101', line: 'L1', station: 'S1', metric: 'temperature', value: 97, unit: '°C', thresholds: { warn: 80, critical: 90 } },
          { machine: 'MACH-102', line: 'L1', station: 'S2', metric: 'temperature', value: 40, thresholds: { warn: 80, critical: 90 } },
        ],
      },
      { 'x-alertsys-ingest': 'k'.repeat(16) },
    );
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.ok).toBe(true);
    expect(body.created).toBe(1);
    expect(body.skipped).toBe(1);
    expect(body.alertIds).toHaveLength(1);

    // The alert landed in the (fake) database with the worker's normalized shape.
    const alerts = Object.values(state.db.alerts ?? {});
    expect(alerts).toHaveLength(1);
    expect(alerts[0]).toMatchObject({
      usine: 'Usine X',
      convoyeur: 'L1',
      poste: 'S1',
      isCritical: true,
      source: 'scada:opcua',
      value: 97,
      push_sent: false,
    });
    // Connector runtime was stamped for the console's live status card.
    expect(state.db.connectors.okc.runtime.status).toBe('linked');
    expect(state.db.connectors.okc.runtime.eventsIngested).toBe(2);
  });

  test('exact duplicates inside the dedup window are skipped, not double-alerted', async () => {
    const state = installFakeNetwork({
      connectors: { dupc: { kind: 'mqtt', enabled: true, factory: 'Usine Dup' } },
      connector_secrets: { dupc: { ingestKey: 'k'.repeat(16) } },
    });
    const reading = { machine: 'MACH-201', line: 'L9', station: 'S9', metric: 'vibration', value: 99, thresholds: { warn: 5, critical: 9 } };
    const res = await post('/ingest/dupc', [reading, { ...reading }], { 'x-alertsys-ingest': 'k'.repeat(16) });
    const body = await res.json();
    expect(body.created).toBe(1);
    expect(body.skipped).toBe(1);
    expect(Object.values(state.db.alerts ?? {})).toHaveLength(1);
  });

  test('a created alert triggers the notify worker fast path when configured', async () => {
    const notifyCalls = [];
    const state = installFakeNetwork({
      connectors: { ntfy: { kind: 'custom', enabled: true, factory: 'Usine N' } },
      connector_secrets: { ntfy: { ingestKey: 'k'.repeat(16) } },
    });
    const inner = global.fetch;
    global.fetch = jest.fn(async (url, init) => {
      if (String(url).startsWith('https://notify.example')) {
        notifyCalls.push(JSON.parse(init.body));
        return new Response('{}', { status: 200 });
      }
      return inner(url, init);
    });
    const res = await post(
      '/ingest/ntfy',
      [{ machine: 'MACH-301', line: 'L2', station: 'S3', metric: 'temperature', value: 999, thresholds: { warn: 80, critical: 90 } }],
      { 'x-alertsys-ingest': 'k'.repeat(16) },
      { ...baseEnv(), NOTIFY_WORKER_URL: 'https://notify.example/notify', WORKER_SHARED_SECRET: 's'.repeat(16) },
    );
    expect((await res.json()).created).toBe(1);
    expect(notifyCalls).toHaveLength(1);
    expect(notifyCalls[0].alertId).toMatch(/^-Fake/);
    expect(Object.keys(state.db.alerts)).toHaveLength(1);
  });
});
