// Exercises the modular worker FCM implementation directly.  The production
// notify worker has its own suite; these tests keep the shared worker module
// honest as well, with no Firebase or FCM network access.
import { afterEach, describe, expect, jest, test } from '@jest/globals';

const getFcmAccessToken = jest.fn();
jest.unstable_mockModule('../worker/auth.js', () => ({ getFcmAccessToken }));

const {
  _alertNotifId,
  parseFcmFailure,
  clearUnregisteredFcmToken,
  isActiveSupervisorForNotification,
  engagedSupervisorIds,
  sendFcmDetailed,
  getFcmRecipientsForFactory,
  getFcmTokensForFactory,
  fanOutPendingNotifications,
  evaluateQueuedNotification,
  notifTitle,
} = await import('../worker/fcm.js');

const realFetch = globalThis.fetch;

function response(body = {}, status = 200, headers = {}) {
  return new Response(typeof body === 'string' ? body : JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json', ...headers },
  });
}

afterEach(() => {
  globalThis.fetch = realFetch;
  getFcmAccessToken.mockReset();
});

describe('FCM recipient and queue policy', () => {
  const users = {
    free: { role: 'supervisor', usine: 'Plant A', status: 'active', fcmToken: 'free-token' },
    busy: { role: 'supervisor', usine: 'Plant A', status: 'available', fcmToken: 'busy-token' },
    away: { role: 'supervisor', usine: 'Plant B', status: 'active', fcmToken: 'away-token' },
    inactive: { role: 'supervisor', usine: 'Plant A', status: 'offline', fcmToken: 'inactive-token' },
    admin: { role: 'admin', fcmToken: 'admin-token' },
    duplicate: { role: 'supervisor', usine: 'Plant A', active: true, fcmToken: 'free-token' },
    operator: { role: 'operator', usine: 'Plant A', fcmToken: 'operator-token' },
  };
  const alerts = { held: { status: 'en_cours', superviseurId: 'busy' } };

  test('deduplicates matching recipients and honors active/factory/busy gates', () => {
    const recipients = getFcmRecipientsForFactory({ usine: 'Plant A' }, users, alerts, {
      includeAdmins: false,
      requireActiveSupervisors: true,
    });
    expect(recipients).toEqual([{ uid: 'free', token: 'free-token', role: 'supervisor' }]);

    const escalated = getFcmTokensForFactory('Plant A', users, alerts, {
      allSupervisors: true,
      allFactories: true,
      includeAdmins: true,
    });
    expect(escalated).toEqual(expect.arrayContaining([
      'free-token', 'busy-token', 'away-token', 'inactive-token', 'admin-token',
    ]));
    expect(escalated).not.toContain('operator-token');
  });

  test.each([
    ['unknown user', 'missing', null, { type: 'help_request' }, { action: 'skip', reason: 'unknown_user' }],
    ['role mismatch', 'operator', { role: 'operator', fcmToken: 'x' }, { type: 'help_request' }, { action: 'skip', reason: 'role_mismatch' }],
    ['new alert for admin', 'admin', { role: 'admin', fcmToken: 'x' }, { type: 'new_alert' }, { action: 'skip', reason: 'role_mismatch' }],
    ['expired alert', 'free', users.free, { type: 'new_alert', timestamp: new Date(Date.now() - 16 * 60 * 1000).toISOString() }, { action: 'skip', reason: 'expired' }],
    ['busy supervisor', 'busy', users.busy, { type: 'new_alert', usine: 'Plant A' }, { action: 'skip', reason: 'busy_supervisor' }],
    ['wrong factory', 'away', users.away, { type: 'new_alert', usine: 'Plant A' }, { action: 'skip', reason: 'factory_mismatch' }],
    ['new alert with no token', 'free', { ...users.free, fcmToken: '' }, { type: 'new_alert', usine: 'Plant A' }, { action: 'skip', reason: 'no_fcm_token' }],
    ['personal notification without token', 'free', { ...users.free, fcmToken: '' }, { type: 'help_request' }, { action: 'defer' }],
  ])('%s is classified deterministically', (_, uid, user, notification, expected) => {
    expect(evaluateQueuedNotification(uid, user, notification, new Set(['busy']))).toEqual(expected);
  });

  test('all documented notification types have a human title', () => {
    expect(notifTitle('new_alert')).toBe('New Alert');
    expect(notifTitle('ai_assigned')).toBe('AI Assignment');
    expect(notifTitle('collaboration_approved')).toBe('Collaboration update');
    expect(notifTitle('assistant_assigned')).toBe('Assistant assigned');
    expect(notifTitle('cross_factory_transfer')).toBe('Cross-factory transfer');
    expect(notifTitle('help_request')).toBe('Help request');
    expect(notifTitle('ai_cross_factory_recommendation')).toBe('AI recommendation');
    expect(notifTitle('ai_rejection')).toBe('AI rejection');
    expect(notifTitle('alert_suspended')).toBe('Alert suspended');
    expect(notifTitle('unexpected')).toBe('SIAS - Smart Industrial Alert System');
  });

  test('normalizes active status and active-claim representations', () => {
    expect(isActiveSupervisorForNotification({ status: 'ONLINE' })).toBe(true);
    expect(isActiveSupervisorForNotification({ active: true })).toBe(true);
    expect(isActiveSupervisorForNotification({ isActive: true })).toBe(true);
    expect(isActiveSupervisorForNotification({ status: 'offline' })).toBe(false);

    const ids = engagedSupervisorIds({
      ignored: null,
      resolved: { status: 'validee', superviseurId: 'not-busy' },
      owned: { status: 'en_cours', superviseurId: 'owner', assistantId: 'helper' },
    }, {
      fromString: 'owned',
      fromObject: { id: 'owned' },
      empty: {},
      stale: { alertId: 'resolved' },
    });
    expect([...ids].sort()).toEqual(['fromObject', 'fromString', 'helper', 'owner']);
  });

  test('parses provider failures without relying on provider wording', () => {
    expect(_alertNotifId('alert-1')).toBe(_alertNotifId('alert-1'));
    expect(_alertNotifId('')).toBe(1);
    expect(parseFcmFailure(404, JSON.stringify({
      error: { status: 'NOT_FOUND', message: 'gone', details: [{ errorCode: 'UNREGISTERED' }] },
    }))).toEqual({ errorCode: 'UNREGISTERED', message: 'gone', unregistered: true });
    expect(parseFcmFailure(500, 'not JSON')).toEqual({ errorCode: '', message: 'not JSON', unregistered: false });
    expect(parseFcmFailure(404, JSON.stringify({ error: { status: 'SOMETHING_ELSE' } }))).toMatchObject({
      errorCode: 'SOMETHING_ELSE', unregistered: false,
    });
    expect(parseFcmFailure(404, JSON.stringify({ error: { message: 'Device unregistered' } }))).toMatchObject({
      errorCode: '', message: 'Device unregistered', unregistered: true,
    });
    expect(parseFcmFailure(404, '')).toEqual({ errorCode: '', message: '', unregistered: false });
  });

  test('defers terminal and malformed rows before attempting any delivery', () => {
    const user = { role: 'supervisor', usine: 'Plant A', fcmToken: 'token' };
    expect(evaluateQueuedNotification('u1', user, null, new Set())).toEqual({ action: 'defer' });
    expect(evaluateQueuedNotification('u1', user, { type: 'help_request', pushSent: true }, new Set())).toEqual({ action: 'defer' });
    expect(evaluateQueuedNotification('u1', user, { type: 'help_request', pushSending: true }, new Set())).toEqual({ action: 'defer' });
    expect(evaluateQueuedNotification('u1', user, {}, new Set())).toEqual({ action: 'defer' });
    expect(evaluateQueuedNotification('undefined', user, { type: 'help_request' }, new Set())).toEqual({
      action: 'skip', reason: 'unknown_user',
    });
    expect(evaluateQueuedNotification('u1', user, {
      type: 'help_request', timestamp: new Date(Date.now() - 25 * 60 * 60 * 1000).toISOString(),
    }, new Set())).toEqual({ action: 'skip', reason: 'expired' });
  });
});

describe('FCM transport and pending fan-out', () => {
  const env = {
    FB_DB_URL: 'https://db.example/',
    FIREBASE_SERVICE_ACCOUNT: JSON.stringify({ project_id: 'project-1' }),
  };

  test('sends a data-only message on success', async () => {
    getFcmAccessToken.mockResolvedValue('access-token');
    const calls = [];
    globalThis.fetch = jest.fn(async (url, init = {}) => {
      calls.push({ url: String(url), init });
      return response({ name: 'projects/project-1/messages/m1' });
    });

    await expect(sendFcmDetailed('device-token', 'Title', 'Body', { alertId: 'a1' }, env))
      .resolves.toMatchObject({ ok: true, status: 200, unregistered: false });
    const payload = JSON.parse(calls[0].init.body);
    expect(payload.message).toMatchObject({
      token: 'device-token',
      data: { alertId: 'a1', title: 'Title', body: 'Body' },
      android: { priority: 'high' },
    });
    expect(payload.message).not.toHaveProperty('notification');
  });

  test('clears a still-current unregistered device token', async () => {
    getFcmAccessToken.mockResolvedValue('access-token');
    const calls = [];
    globalThis.fetch = jest.fn(async (url, init = {}) => {
      const u = String(url);
      calls.push({ url: u, init });
      if (u.includes('fcm.googleapis.com')) {
        return response({ error: { status: 'UNREGISTERED', message: 'Device unregistered' } }, 404);
      }
      if (u.endsWith('/users/u1/fcmToken.json?auth=firebase-token') && !init.method) {
        return response('"stale-token"', 200, { etag: '"token-etag"' });
      }
      if (u.endsWith('/users/u1/fcmToken.json?auth=firebase-token') && init.method === 'PUT') {
        return response(null);
      }
      throw new Error(`Unexpected fetch: ${u}`);
    });

    const result = await sendFcmDetailed('stale-token', 'Title', 'Body', { recipientId: 'u1' }, env, {
      firebaseAuthToken: 'firebase-token', uid: 'u1',
    });
    expect(result).toMatchObject({ ok: false, status: 404, unregistered: true, errorCode: 'UNREGISTERED' });
    const clear = calls.find((c) => c.init.method === 'PUT');
    expect(clear).toBeDefined();
    expect(clear.init.body).toBe('null');
  });

  test('does not erase a replaced token and fails closed on an unavailable token record', async () => {
    const calls = [];
    globalThis.fetch = jest.fn(async (url, init = {}) => {
      calls.push({ url: String(url), init });
      return response('"new-token"', 200, { etag: '"new-etag"' });
    });
    await expect(clearUnregisteredFcmToken(env, 'firebase-token', 'u1', 'old-token')).resolves.toBe(false);
    expect(calls).toHaveLength(1);

    globalThis.fetch = jest.fn(async () => response({}, 500));
    await expect(clearUnregisteredFcmToken(env, 'firebase-token', 'u1', 'old-token')).resolves.toBe(false);
    await expect(clearUnregisteredFcmToken({}, 'firebase-token', 'u1', 'old-token')).resolves.toBe(false);

    globalThis.fetch = jest.fn(async () => { throw new Error('database unreachable'); });
    const warnSpy = jest.spyOn(console, 'warn').mockImplementation(() => {});
    await expect(clearUnregisteredFcmToken(env, 'firebase-token', 'u1', 'old-token')).resolves.toBe(false);
    warnSpy.mockRestore();
  });

  test('clears a matching token even when Firebase supplies no ETag header', async () => {
    const calls = [];
    globalThis.fetch = jest.fn(async (url, init = {}) => {
      calls.push({ url: String(url), init });
      if (!init.method) return response('"old-token"');
      if (init.method === 'PUT') return response({});
      throw new Error('unexpected request');
    });
    await expect(clearUnregisteredFcmToken(env, 'firebase-token', 'u1', 'old-token')).resolves.toBe(true);
    expect(calls.at(-1).init.headers['if-match']).toBe('*');
  });

  test('returns structured failures for rejected or exceptional FCM sends', async () => {
    getFcmAccessToken.mockResolvedValue('access-token');
    const errorSpy = jest.spyOn(console, 'error').mockImplementation(() => {});
    globalThis.fetch = jest.fn(async () => response({ error: { status: 'INVALID_ARGUMENT', message: 'bad payload' } }, 400));
    await expect(sendFcmDetailed('device-token', 'Title', 'Body', {}, env)).resolves.toMatchObject({
      ok: false, status: 400, errorCode: 'INVALID_ARGUMENT', unregistered: false,
    });

    globalThis.fetch = jest.fn(async () => { throw new Error('network down'); });
    await expect(sendFcmDetailed('device-token', 'Title', 'Body', {}, env)).resolves.toMatchObject({
      ok: false, status: 0, errorCode: 'EXCEPTION', message: 'network down',
    });
    errorSpy.mockRestore();
  });

  test('identifies a missing-token FCM failure even without recipient context', async () => {
    getFcmAccessToken.mockResolvedValue('access-token');
    const warnSpy = jest.spyOn(console, 'warn').mockImplementation(() => {});
    globalThis.fetch = jest.fn(async () => response({ error: { status: 'NOT_FOUND' } }, 404));
    await expect(sendFcmDetailed('device-token', 'Title', 'Body', {}, env)).resolves.toMatchObject({
      ok: false, status: 404, unregistered: true, errorCode: 'NOT_FOUND',
    });
    warnSpy.mockRestore();
  });

  test('handles no-work, unavailable queue reads, and stale queue claims without sending', async () => {
    globalThis.fetch = jest.fn();
    await fanOutPendingNotifications(env, { token: 't', usersMap: {}, alertsMap: {}, supervisorActiveAlertsMap: {} }, { limit: 0 });
    expect(globalThis.fetch).not.toHaveBeenCalled();

    globalThis.fetch = jest.fn(async () => response({}, 503));
    await fanOutPendingNotifications(env, { token: 't', usersMap: {}, alertsMap: {}, supervisorActiveAlertsMap: {} }, { limit: 1 });

    globalThis.fetch = jest.fn(async (url, init = {}) => {
      const u = String(url);
      if (u.endsWith('/notifications.json?auth=t')) return response({
        free: { alreadySent: { type: 'help_request', pushSent: true } },
      });
      throw new Error(`Unexpected fetch ${init.method || 'GET'} ${u}`);
    });
    await fanOutPendingNotifications(env, {
      token: 't',
      usersMap: { free: { role: 'supervisor', usine: 'Plant A', fcmToken: 'token' } },
      alertsMap: {}, supervisorActiveAlertsMap: {},
    }, { limit: 1 });
  });

  test('leaves rejected claims and current in-flight rows for a later retry', async () => {
    const sendSpy = jest.spyOn(console, 'error').mockImplementation(() => {});
    getFcmAccessToken.mockResolvedValue('access-token');
    const writes = [];
    globalThis.fetch = jest.fn(async (url, init = {}) => {
      const u = String(url);
      const method = init.method || 'GET';
      if (u.endsWith('/notifications.json?auth=t')) {
        return response({
          free: {
            unreadable: { type: 'help_request', pushSent: false },
            current: { type: 'help_request', pushSent: false },
            denied: { type: 'help_request', pushSent: false },
            fallbackBody: { type: 'help_request', pushSent: false },
          },
        });
      }
      if (method === 'GET' && u.includes('/unreadable.json')) return response({}, 503);
      if (method === 'GET' && u.includes('/current.json')) return response({ type: 'help_request', pushSending: true }, 200, { etag: '"c"' });
      if (method === 'GET' && u.includes('/denied.json')) return response({ type: 'help_request', pushSent: false }, 200, { etag: '"d"' });
      if (method === 'PUT' && u.includes('/denied.json')) return response({}, 412);
      if (method === 'GET' && u.includes('/fallbackBody.json')) return response({ type: 'help_request', pushSent: false }, 200, { etag: '"f"' });
      if (method === 'PUT' && u.includes('/fallbackBody.json')) return response({});
      if (u.includes('fcm.googleapis.com')) return response({ error: { status: 'INVALID_ARGUMENT', message: 'reject' } }, 400);
      if (method === 'PATCH') {
        writes.push(JSON.parse(init.body));
        return response({});
      }
      throw new Error(`Unexpected fetch ${method} ${u}`);
    });

    await fanOutPendingNotifications(env, {
      token: 't',
      usersMap: { free: { role: 'supervisor', usine: 'Plant A', fcmToken: 'device-token' } },
      alertsMap: {}, supervisorActiveAlertsMap: {},
    }, { limit: 5 });
    expect(writes).toEqual([expect.objectContaining({ pushSending: null, pushLastErrorAt: expect.any(String) })]);
    sendSpy.mockRestore();
  });

  test('uses stable alert notification ids and stops a user bucket after an unregistered token', async () => {
    getFcmAccessToken.mockResolvedValue('access-token');
    const warning = jest.spyOn(console, 'warn').mockImplementation(() => {});
    const sends = [];
    const writes = [];
    globalThis.fetch = jest.fn(async (url, init = {}) => {
      const u = String(url);
      const method = init.method || 'GET';
      if (u.endsWith('/notifications.json?auth=t')) {
        return response({
          free: {
            newAlert: { type: 'new_alert', alertId: 'a-77', usine: 'Plant A', pushSent: false },
            shouldNotRun: { type: 'help_request', pushSent: false },
          },
        });
      }
      if (u.includes('/notifications/free/newAlert.json') && method === 'GET') {
        return response({ type: 'new_alert', alertId: 'a-77', usine: 'Plant A', pushSent: false }, 200, { etag: '"n"' });
      }
      if (u.includes('/notifications/free/newAlert.json') && method === 'PUT') return response({});
      if (u.includes('/notifications/free/newAlert.json') && method === 'PATCH') {
        writes.push(JSON.parse(init.body));
        return response({});
      }
      if (u.endsWith('/users/free/fcmToken.json?auth=t') && method === 'GET') return response('"device-token"', 200, { etag: '"u"' });
      if (u.endsWith('/users/free/fcmToken.json?auth=t') && method === 'PUT') return response({});
      if (u.includes('fcm.googleapis.com')) {
        sends.push(JSON.parse(init.body));
        return response({ error: { status: 'UNREGISTERED', message: 'gone' } }, 404);
      }
      if (u.includes('shouldNotRun')) throw new Error('bucket was not stopped after unregistration');
      throw new Error(`Unexpected fetch ${method} ${u}`);
    });

    const users = { free: { role: 'supervisor', usine: 'Plant A', fcmToken: 'device-token' } };
    await fanOutPendingNotifications(env, { token: 't', usersMap: users, alertsMap: {}, supervisorActiveAlertsMap: {} }, { limit: 5 });
    expect(sends).toHaveLength(1);
    expect(sends[0].message.data.notificationId).toBe(String(_alertNotifId('a-77')));
    expect(users.free.fcmToken).toBeNull();
    expect(writes).toEqual([expect.objectContaining({ pushSending: null, pushLastErrorAt: expect.any(String) })]);
    warning.mockRestore();
  });

  test('falls back to safe fields if a queue record changes after initial validation', async () => {
    getFcmAccessToken.mockResolvedValue('access-token');
    const sends = [];
    globalThis.fetch = jest.fn(async (url, init = {}) => {
      const u = String(url);
      const method = init.method || 'GET';
      if (u.endsWith('/notifications.json?auth=t')) return response({ free: { n1: { type: 'help_request', pushSent: false } } });
      if (u.includes('/notifications/free/n1.json') && method === 'GET') return response({ pushSent: false }, 200, { etag: '"n"' });
      if (u.includes('/notifications/free/n1.json') && method === 'PUT') return response({});
      if (u.includes('/notifications/free/n1.json') && method === 'PATCH') return response({});
      if (u.includes('fcm.googleapis.com')) {
        sends.push(JSON.parse(init.body));
        return response({});
      }
      throw new Error(`Unexpected fetch ${method} ${u}`);
    });
    await fanOutPendingNotifications(env, {
      token: 't',
      usersMap: { free: { role: 'supervisor', usine: 'Plant A', fcmToken: 'device-token' } },
      alertsMap: null, supervisorActiveAlertsMap: null,
    }, {});
    expect(sends[0].message.data).toMatchObject({ notificationId: 'n1', alertId: '', collabRequestId: '', type: '' });
    expect(sends[0].message.data.body).toBe('SIAS - Smart Industrial Alert System notification');
  });

  test('marks skipped and sent queue rows using the correct terminal state', async () => {
    getFcmAccessToken.mockResolvedValue('access-token');
    const writes = [];
    globalThis.fetch = jest.fn(async (url, init = {}) => {
      const u = String(url);
      const method = init.method || 'GET';
      if (u === 'https://db.example/notifications.json?auth=firebase-token') {
        return response({
          busy: { stale: { type: 'new_alert', usine: 'Plant A', pushSent: false } },
          free: { fresh: { type: 'help_request', message: 'Please help', pushSent: false } },
        });
      }
      if (u.includes('/notifications/busy/stale.json') && method === 'PATCH') {
        writes.push(JSON.parse(init.body));
        return response({});
      }
      if (u.includes('/notifications/free/fresh.json') && method === 'GET') {
        return response({ type: 'help_request', message: 'Please help', pushSent: false }, 200, { etag: '"n1"' });
      }
      if (u.includes('/notifications/free/fresh.json') && method === 'PUT') return response({});
      if (u.includes('/notifications/free/fresh.json') && method === 'PATCH') {
        writes.push(JSON.parse(init.body));
        return response({});
      }
      if (u.includes('fcm.googleapis.com')) return response({ name: 'sent' });
      throw new Error(`Unexpected fetch ${method} ${u}`);
    });

    await fanOutPendingNotifications(env, {
      token: 'firebase-token',
      usersMap: {
        busy: { role: 'supervisor', usine: 'Plant A', fcmToken: 'busy-token' },
        free: { role: 'supervisor', usine: 'Plant A', fcmToken: 'free-token' },
      },
      alertsMap: { held: { status: 'en_cours', superviseurId: 'busy' } },
      supervisorActiveAlertsMap: {},
    }, { limit: 5 });

    expect(writes).toEqual(expect.arrayContaining([
      expect.objectContaining({ pushSent: true, pushSkipReason: 'busy_supervisor' }),
      expect.objectContaining({ pushSent: true, pushSending: null }),
    ]));
  });
});
