// End-to-end tests for the SCADA ingestion worker's request lifecycle.
// Drives the real `fetch` handler with a mock env and a stubbed global fetch,
// so RTDB writes + notify triggers are captured without any network.
import ingest from '../cloudflare_ingest_worker.js';

const ENV = {
  FB_DB_URL: 'https://db.example.com',
  NOTIFY_WORKER_URL: 'https://notify.example/notify',
  INGEST_SHARED_SECRET: 's3cret',
  INGEST_RATE_PER_MIN: '100000',
  INGEST_DEDUP_WINDOW_MS: '60000',
};

let calls;
beforeEach(() => {
  calls = [];
  globalThis.fetch = async (url, opts) => {
    const u = String(url);
    calls.push({ url: u, opts });
    if (u.includes('/alerts.json')) {
      return { ok: true, status: 200, json: async () => ({ name: '-NewAlertId' }) };
    }
    return { ok: true, status: 200, json: async () => ({}) };
  };
});

function req(method, { secret, body, contentLength } = {}) {
  const h = new Map();
  if (secret) h.set('x-alertsys-ingest', secret);
  if (contentLength != null) h.set('content-length', String(contentLength));
  return {
    method,
    url: 'https://ingest.example/',
    headers: { get: (k) => (h.has(k.toLowerCase()) ? h.get(k.toLowerCase()) : null) },
    json: async () => (typeof body === 'string' ? JSON.parse(body) : body),
  };
}

const alertCalls = () => calls.filter((c) => c.url.includes('/alerts.json'));
const notifyCalls = () => calls.filter((c) => c.url.startsWith('https://notify.example'));

describe('ingest worker e2e', () => {
  test('GET returns service banner', async () => {
    const res = await ingest.fetch(req('GET'), ENV);
    expect(res.status).toBe(200);
    const b = await res.json();
    expect(b.service).toBe('sia-ingest');
  });

  test('rejects without the shared secret (401)', async () => {
    const res = await ingest.fetch(req('POST', { body: { factory: 'P', machine: 'M' } }), ENV);
    expect(res.status).toBe(401);
    expect(alertCalls().length).toBe(0);
  });

  test('a normal reading creates no alert', async () => {
    const body = { source: 'opcua', factory: 'P-normal', line: 'L1', metric: 'temp', value: 40, thresholds: { warn: 70, critical: 90 } };
    const res = await ingest.fetch(req('POST', { secret: 's3cret', body }), ENV);
    expect(res.status).toBe(200);
    const b = await res.json();
    expect(b.created).toBe(0);
    expect(alertCalls().length).toBe(0);
  });

  test('a critical reading creates an alert and triggers notify', async () => {
    const body = { source: 'opcua', factory: 'P-crit', line: 'L2', station: 'S3', metric: 'bearing_temp', value: 95, thresholds: { warn: 70, critical: 90 } };
    const res = await ingest.fetch(req('POST', { secret: 's3cret', body }), ENV);
    expect(res.status).toBe(200);
    const b = await res.json();
    expect(b.created).toBe(1);
    expect(b.alertIds).toEqual(['-NewAlertId']);
    expect(alertCalls().length).toBe(1);
    expect(notifyCalls().length).toBe(1);
    // the alert body posted to RTDB carries the normalized shape
    const posted = JSON.parse(alertCalls()[0].opts.body);
    expect(posted.type).toBe('Mechanical');
    expect(posted.usine).toBe('P-crit');
    expect(posted.isCritical).toBe(true);
    expect(posted.push_sent).toBe(false);
  });

  test('duplicate critical readings collapse within the dedup window', async () => {
    const body = { source: 'mqtt', factory: 'P-dedup', line: 'L9', metric: 'bearing_temp', value: 99, thresholds: { critical: 90 } };
    const first = await (await ingest.fetch(req('POST', { secret: 's3cret', body }), ENV)).json();
    const second = await (await ingest.fetch(req('POST', { secret: 's3cret', body }), ENV)).json();
    expect(first.created).toBe(1);
    expect(second.created).toBe(0); // deduped
  });

  test('batch payload processes multiple readings', async () => {
    const body = {
      readings: [
        { source: 'modbus', factory: 'P-batch', line: 'A', metric: 'phase_current', value: 120, thresholds: { critical: 100 } },
        { source: 'modbus', factory: 'P-batch', line: 'B', metric: 'smoke', alert: true, type: 'Safety' },
        { source: 'modbus', factory: 'P-batch', line: 'C', metric: 'temp', value: 10, thresholds: { critical: 90 } }, // normal
      ],
    };
    const res = await ingest.fetch(req('POST', { secret: 's3cret', body }), ENV);
    const b = await res.json();
    expect(b.created).toBe(2); // electrical + safety; the normal one is skipped
    expect(b.skipped).toBeGreaterThanOrEqual(1);
  });

  test('invalid JSON returns 400', async () => {
    const bad = { method: 'POST', url: 'https://ingest.example/', headers: { get: (k) => (k.toLowerCase() === 'x-alertsys-ingest' ? 's3cret' : null) }, json: async () => { throw new Error('bad'); } };
    const res = await ingest.fetch(bad, ENV);
    expect(res.status).toBe(400);
  });
});
