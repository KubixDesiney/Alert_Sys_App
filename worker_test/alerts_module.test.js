// Exercises the modular worker's alert push pipeline (worker/alerts.js)
// directly: ETag-guarded claiming, lock-fresh skip, finish/skip bookkeeping
// writes, and the full processAlerts fan-out loop. No live network — every
// fetch is a local double against an in-memory alert store.
import { afterEach, describe, expect, jest, test } from '@jest/globals';

jest.unstable_mockModule('../worker/fcm.js', () => ({
  getFcmRecipientsForFactory: jest.fn(),
  sendFcmDetailed: jest.fn(),
}));

const { getFcmRecipientsForFactory, sendFcmDetailed } = await import('../worker/fcm.js');
const { claimAlertPush, finishAlertPush, skipAlertPush, processAlerts } = await import('../worker/alerts.js');

const realFetch = globalThis.fetch;
function response(body, status = 200, headers = {}) {
  return new Response(typeof body === 'string' ? body : JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json', ETag: 'W/"1"', ...headers },
  });
}

afterEach(() => {
  globalThis.fetch = realFetch;
  getFcmRecipientsForFactory.mockReset();
  sendFcmDetailed.mockReset();
});

describe('claimAlertPush', () => {
  const env = { FB_DB_URL: 'https://db.example/' };

  test('claims an unsent, unlocked, disponible alert via ETag PUT', async () => {
    const alert = { status: 'disponible', push_sent: false, usine: 'Plant A' };
    const calls = [];
    globalThis.fetch = jest.fn(async (url, init = {}) => {
      calls.push({ url: String(url), method: init.method || 'GET' });
      if (!init.method) return response(alert, 200, { ETag: 'W/"9"' });
      expect(init.method).toBe('PUT');
      expect(init.headers['if-match']).toBe('W/"9"');
      const body = JSON.parse(init.body);
      expect(body.push_sending).toBe(true);
      expect(body.push_sending_at).toBeTruthy();
      return response(body, 200);
    });
    const claimed = await claimAlertPush(env, 'tok', 'a1');
    expect(claimed).toMatchObject({ alertUrl: expect.stringContaining('alerts/a1.json'), alert: { id: 'a1', status: 'disponible' } });
    expect(calls[0].method).toBe('GET');
    expect(calls[1].method).toBe('PUT');
  });

  test('returns null when the GET fails, the alert is already sent, or not disponible', async () => {
    globalThis.fetch = jest.fn(async () => new Response('nope', { status: 500 }));
    expect(await claimAlertPush(env, 't', 'x')).toBeNull();

    globalThis.fetch = jest.fn(async () => response({ status: 'disponible', push_sent: true }));
    expect(await claimAlertPush(env, 't', 'x')).toBeNull();

    globalThis.fetch = jest.fn(async () => response({ status: 'en_cours', push_sent: false }));
    expect(await claimAlertPush(env, 't', 'x')).toBeNull();
  });

  test('returns null when a push lock is fresh (someone else is mid-send)', async () => {
    globalThis.fetch = jest.fn(async () => response({
      status: 'disponible', push_sent: false, push_sending: true, push_sending_at: new Date().toISOString(),
    }));
    expect(await claimAlertPush(env, 't', 'x')).toBeNull();
  });

  test('a stale push lock (older than the TTL) is claimable again', async () => {
    const stale = new Date(Date.now() - 10 * 60 * 1000).toISOString(); // well past PUSH_LOCK_TTL_MS
    globalThis.fetch = jest.fn(async (url, init = {}) => {
      if (!init.method) return response({ status: 'disponible', push_sent: false, push_sending: true, push_sending_at: stale }, 200, { ETag: 'W/"2"' });
      return response(JSON.parse(init.body));
    });
    expect(await claimAlertPush(env, 't', 'x')).not.toBeNull();
  });

  test('a 412 (ETag conflict) on the claiming PUT returns null', async () => {
    globalThis.fetch = jest.fn(async (url, init = {}) => {
      if (!init.method) return response({ status: 'disponible', push_sent: false }, 200, { ETag: 'W/"1"' });
      return new Response('conflict', { status: 412 });
    });
    expect(await claimAlertPush(env, 't', 'x')).toBeNull();
  });
});

describe('finishAlertPush / skipAlertPush', () => {
  test('finishAlertPush(true) clears the lock and marks sent', async () => {
    let patched;
    globalThis.fetch = jest.fn(async (url, init) => { patched = JSON.parse(init.body); return response({}); });
    await finishAlertPush('https://db.example/alerts/a1.json?auth=t', true);
    expect(patched).toMatchObject({ push_sent: true, push_sending: null, push_sending_at: null, push_last_error_at: null });
    expect(patched.push_sent_at).toBeTruthy();
  });

  test('finishAlertPush(false) releases the lock but keeps push_sent false for retry', async () => {
    let patched;
    globalThis.fetch = jest.fn(async (url, init) => { patched = JSON.parse(init.body); return response({}); });
    await finishAlertPush('https://db.example/alerts/a1.json?auth=t', false);
    expect(patched).toMatchObject({ push_sent: false, push_sending: null });
    expect(patched.push_last_error_at).toBeTruthy();
  });

  test('skipAlertPush marks sent (terminal) with a skip reason', async () => {
    let patched;
    globalThis.fetch = jest.fn(async (url, init) => { patched = JSON.parse(init.body); return response({}); });
    await skipAlertPush('https://db.example/alerts/a1.json?auth=t', 'no_recipients');
    expect(patched).toMatchObject({ push_sent: true, push_sending: null, push_skip_reason: 'no_recipients' });
  });
});

describe('processAlerts', () => {
  const baseCtx = (overrides = {}) => ({
    token: 't',
    alertsMap: {
      a1: { status: 'disponible', push_sent: false, usine: 'Plant A', timestamp: new Date().toISOString(), type: 'maintenance', description: 'Bearing hot' },
    },
    usersMap: { sup: { fcmToken: 'tok-1', role: 'supervisor' } },
    supervisorActiveAlertsMap: {},
    ...overrides,
  });

  test('no unsent alerts short-circuits without touching the network', async () => {
    globalThis.fetch = jest.fn();
    await processAlerts({}, baseCtx({ alertsMap: {} }));
    expect(globalThis.fetch).not.toHaveBeenCalled();
  });

  const fullAlert = { status: 'disponible', push_sent: false, usine: 'Plant A', type: 'maintenance', description: 'Bearing hot' };

  test('skips the alert as no_recipients when nobody is eligible', async () => {
    getFcmRecipientsForFactory.mockReturnValue([]);
    const patches = [];
    globalThis.fetch = jest.fn(async (url, init = {}) => {
      if (!init.method) return response(fullAlert, 200, { ETag: 'W/"1"' });
      if (init.method === 'PUT') return response(JSON.parse(init.body));
      if (init.method === 'PATCH') { patches.push(JSON.parse(init.body)); return response({}); }
      return response({});
    });
    await processAlerts({}, baseCtx());
    expect(patches.at(-1)).toMatchObject({ push_sent: true, push_skip_reason: 'no_recipients' });
  });

  test('sends to eligible recipients and finishes the push as successful', async () => {
    getFcmRecipientsForFactory.mockReturnValue([{ uid: 'sup', token: 'tok-1' }]);
    sendFcmDetailed.mockResolvedValue({ ok: true });
    const patches = [];
    globalThis.fetch = jest.fn(async (url, init = {}) => {
      if (!init.method) return response(fullAlert, 200, { ETag: 'W/"1"' });
      if (init.method === 'PUT') return response(JSON.parse(init.body));
      if (init.method === 'PATCH') { patches.push(JSON.parse(init.body)); return response({}); }
      return response({});
    });
    await processAlerts({}, baseCtx());
    expect(sendFcmDetailed).toHaveBeenCalledWith(
      'tok-1',
      expect.stringContaining('New Alert'),
      expect.stringContaining('Bearing hot'),
      expect.objectContaining({ alertId: 'a1', notifType: 'new_alert' }),
      {},
      expect.objectContaining({ uid: 'sup' }),
    );
    expect(patches.at(-1)).toMatchObject({ push_sent: true });
  });

  test('clears a stale fcmToken when the send reports the token unregistered', async () => {
    getFcmRecipientsForFactory.mockReturnValue([{ uid: 'sup', token: 'tok-1' }]);
    sendFcmDetailed.mockResolvedValue({ ok: false, unregistered: true });
    globalThis.fetch = jest.fn(async (url, init = {}) => {
      if (!init.method) return response(fullAlert, 200, { ETag: 'W/"1"' });
      return response(init.method === 'PUT' ? JSON.parse(init.body) : {});
    });
    const ctx = baseCtx();
    await processAlerts({}, ctx);
    expect(ctx.usersMap.sup.fcmToken).toBeNull();
  });

  test('a retryable send failure finishes the push as not-sent (retry next cron)', async () => {
    getFcmRecipientsForFactory.mockReturnValue([{ uid: 'sup', token: 'tok-1' }]);
    sendFcmDetailed.mockResolvedValue({ ok: false, unregistered: false });
    const patches = [];
    globalThis.fetch = jest.fn(async (url, init = {}) => {
      if (!init.method) return response(fullAlert, 200, { ETag: 'W/"1"' });
      if (init.method === 'PUT') return response(JSON.parse(init.body));
      if (init.method === 'PATCH') { patches.push(JSON.parse(init.body)); return response({}); }
      return response({});
    });
    await processAlerts({}, baseCtx());
    expect(patches.at(-1)).toMatchObject({ push_sent: false });
  });

  test('an alert that fails to claim (already locked) is skipped entirely', async () => {
    globalThis.fetch = jest.fn(async () => response({ status: 'disponible', push_sent: false, push_sending: true, push_sending_at: new Date().toISOString() }));
    await processAlerts({}, baseCtx());
    expect(getFcmRecipientsForFactory).not.toHaveBeenCalled();
  });
});
