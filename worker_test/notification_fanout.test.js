import { afterEach, describe, expect, jest, test } from '@jest/globals';
import { getFcmTokensForFactory, processAlerts, pushSingleNotification } from '../cloudflare_notify_worker.js';

function jsonRes(data, status = 200, headers = {}) {
  return {
    ok: status >= 200 && status < 300,
    status,
    headers: {
      get: (name) => headers[String(name).toLowerCase()] ?? null,
    },
    json: async () => data,
    text: async () => JSON.stringify(data),
  };
}

function etagRes(data, etag = '"etag-1"') {
  return jsonRes(data, 200, { etag });
}

function mockCrypto() {
  jest.spyOn(globalThis.crypto.subtle, 'importKey').mockResolvedValue({});
  jest.spyOn(globalThis.crypto.subtle, 'sign').mockResolvedValue(new Uint8Array([1, 2, 3]).buffer);
}

function serviceEnv() {
  return {
    FB_DB_URL: 'https://db.test/',
    FB_API_KEY: 'key',
    FIREBASE_SERVICE_ACCOUNT: JSON.stringify({
      client_email: 'worker@test.iam.gserviceaccount.com',
      private_key: '-----BEGIN PRIVATE KEY-----\nAAAA\n-----END PRIVATE KEY-----\n',
      project_id: 'project-test',
    }),
  };
}

describe('notification recipient gates', () => {
  const usersMap = {
    freeLocal: {
      role: 'supervisor',
      status: 'active',
      usine: 'Usine A',
      fcmToken: 'tok-free-local',
    },
    busyLocal: {
      role: 'supervisor',
      status: 'active',
      usine: 'Usine A',
      fcmToken: 'tok-busy-local',
    },
    assistingLocal: {
      role: 'supervisor',
      status: 'active',
      usine: 'Usine A',
      fcmToken: 'tok-assisting-local',
    },
    otherFactory: {
      role: 'supervisor',
      status: 'active',
      usine: 'Usine B',
      fcmToken: 'tok-other-factory',
    },
    inactiveLocal: {
      role: 'supervisor',
      status: 'offline',
      usine: 'Usine A',
      fcmToken: 'tok-inactive-local',
    },
    admin: {
      role: 'admin',
      status: 'active',
      usine: 'HQ',
      fcmToken: 'tok-admin',
    },
  };

  const alertsMap = {
    claimed: { status: 'en_cours', superviseurId: 'busyLocal' },
    assisted: { status: 'en_cours', assistantId: 'assistingLocal' },
  };

  test('new-alert buzz only targets active free supervisors in the alert factory', () => {
    const tokens = getFcmTokensForFactory('Usine A', usersMap, alertsMap, {
      allSupervisors: false,
      includeAdmins: false,
      requireActiveSupervisors: true,
    });

    expect(tokens).toEqual(['tok-free-local']);
  });

  test('new-alert alert-table fallback excludes production managers/admins', () => {
    const tokens = getFcmTokensForFactory('Usine A', usersMap, alertsMap, {
      allSupervisors: false,
      includeAdmins: false,
      requireActiveSupervisors: true,
    });

    expect(tokens).toEqual(['tok-free-local']);
    expect(tokens).not.toContain('tok-admin');
  });

  test('stale active-claim rows do not block an otherwise free supervisor', () => {
    const tokens = getFcmTokensForFactory('Usine A', usersMap, alertsMap, {
      allSupervisors: false,
      includeAdmins: false,
      requireActiveSupervisors: true,
      supervisorActiveAlertsMap: {
        freeLocal: { alertId: 'missing-or-resolved-alert' },
      },
    });

    expect(tokens).toEqual(['tok-free-local']);
  });

  test('escalation fan-out bypasses busy and factory gates for active supervisors', () => {
    const tokens = getFcmTokensForFactory('Usine A', usersMap, alertsMap, {
      allSupervisors: true,
      allFactories: true,
      includeAdmins: true,
      requireActiveSupervisors: true,
    });

    expect(tokens).toEqual(expect.arrayContaining([
      'tok-free-local',
      'tok-busy-local',
      'tok-assisting-local',
      'tok-other-factory',
      'tok-admin',
    ]));
    expect(tokens).not.toContain('tok-inactive-local');
  });
});

describe('processAlerts push lock', () => {
  afterEach(() => {
    jest.restoreAllMocks();
    delete globalThis.fetch;
  });

  test('uses boolean-safe alert push lock fields instead of writing a string to push_sent', async () => {
    const calls = [];
    const alert = {
      status: 'disponible',
      push_sent: false,
      type: 'maintenance',
      usine: 'Usine A',
      description: 'Motor overload',
    };

    globalThis.fetch = jest.fn((url, opts = {}) => {
      const method = opts.method || 'GET';
      const body = opts.body ? JSON.parse(opts.body) : null;
      calls.push({ url: String(url), method, body });
      if (method === 'GET' && String(url).includes('/alerts/a1.json')) {
        return Promise.resolve(etagRes(alert));
      }
      return Promise.resolve(jsonRes(body ?? {}));
    });

    await processAlerts(
      { FB_DB_URL: 'https://db.test/' },
      {
        token: 'token',
        alertsMap: { a1: alert },
        usersMap: {},
        supervisorActiveAlertsMap: {},
      },
    );

    const claim = calls.find((c) => c.url.includes('/alerts/a1.json') && c.method === 'PUT');
    const finish = calls.find((c) => c.url.includes('/alerts/a1.json') && c.method === 'PATCH');

    expect(claim.body.push_sent).toBe(false);
    expect(claim.body.push_sending).toBe(true);
    expect(typeof claim.body.push_sending_at).toBe('string');
    expect(finish.body).toMatchObject({
      push_sent: true,
      push_sending: null,
      push_sending_at: null,
    });
  });

  test('new-alert alert-table fallback excludes production managers/admins', async () => {
    mockCrypto();
    const calls = [];
    const alert = {
      status: 'disponible',
      push_sent: false,
      type: 'maintenance',
      usine: 'Usine A',
      description: 'Motor overload',
    };

    globalThis.fetch = jest.fn((url, opts = {}) => {
      const method = opts.method || 'GET';
      const body = opts.body && String(opts.body).trim().startsWith('{') ? JSON.parse(opts.body) : null;
      const u = String(url);
      calls.push({ url: u, method, body });
      if (method === 'GET' && u.includes('/alerts/a1.json')) {
        return Promise.resolve(etagRes(alert));
      }
      if (u.includes('oauth2.googleapis.com/token')) return Promise.resolve(jsonRes({ access_token: 'fcm-access', expires_in: 3600 }));
      if (u.includes('fcm.googleapis.com')) return Promise.resolve(jsonRes({ name: 'msg-1' }));
      return Promise.resolve(jsonRes(body ?? {}));
    });

    await processAlerts(
      serviceEnv(),
      {
        token: 'token',
        alertsMap: { a1: alert },
        usersMap: {
          admin: { role: 'admin', fcmToken: 'fcm-admin' },
        },
        supervisorActiveAlertsMap: {},
      },
    );

    const fcm = calls.find((c) => c.url.includes('fcm.googleapis.com'));
    expect(fcm).toBeUndefined();
  });
});

describe('targeted queued notification push', () => {
  afterEach(() => {
    jest.restoreAllMocks();
    delete globalThis.fetch;
  });

  test('pushes one queued notification by uid/id and includes notifType', async () => {
    mockCrypto();
    const calls = [];
    const notif = {
      type: 'help_request',
      alertId: 'a1',
      message: 'Need help on alert a1',
      timestamp: '2026-05-20T10:00:00.000Z',
      pushSent: false,
    };

    globalThis.fetch = jest.fn((url, opts = {}) => {
      const method = opts.method || 'GET';
      const u = String(url);
      const body = opts.body && String(opts.body).trim().startsWith('{') ? JSON.parse(opts.body) : null;
      calls.push({ url: u, method, body });
      if (u.includes('accounts:signInWithCustomToken')) return Promise.resolve(jsonRes({ idToken: 'fb-token' }));
      if (u === 'https://db.test/alerts.json?auth=fb-token') return Promise.resolve(jsonRes({}));
      if (u === 'https://db.test/users.json?auth=fb-token') {
        return Promise.resolve(jsonRes({
          u1: { role: 'supervisor', usine: 'Usine A', status: 'active', fcmToken: 'fcm-u1' },
        }));
      }
      if (u === 'https://db.test/supervisor_active_alerts.json?auth=fb-token') return Promise.resolve(jsonRes({}));
      if (u === 'https://db.test/notifications/u1/n1.json?auth=fb-token' && method === 'GET') {
        return Promise.resolve(etagRes(notif));
      }
      if (u.includes('oauth2.googleapis.com/token')) return Promise.resolve(jsonRes({ access_token: 'fcm-access', expires_in: 3600 }));
      if (u.includes('fcm.googleapis.com')) return Promise.resolve(jsonRes({ name: 'msg-1' }));
      return Promise.resolve(jsonRes(body ?? {}));
    });

    const sent = await pushSingleNotification(serviceEnv(), 'u1', 'n1');
    expect(sent).toBe(true);

    const fcm = calls.find((c) => c.url.includes('fcm.googleapis.com'));
    expect(fcm.body.message.data).toMatchObject({
      notificationId: 'n1',
      recipientId: 'u1',
      alertId: 'a1',
      type: 'help_request',
      notifType: 'help_request',
    });

    const patch = calls.find((c) => c.url.includes('/notifications/u1/n1.json') && c.method === 'PATCH');
    expect(patch.body).toMatchObject({
      pushSent: true,
      pushSending: null,
      pushSendingAt: null,
      pushLastErrorAt: null,
    });
  });

  test('pushes queued new-alert notifications to supervisors only', async () => {
    mockCrypto();
    const calls = [];
    const notif = {
      type: 'new_alert',
      alertId: 'a1',
      alertType: 'maintenance',
      message: 'New alert from Usine A: maintenance',
      timestamp: '2026-05-20T10:00:00.000Z',
      pushSent: false,
    };

    globalThis.fetch = jest.fn((url, opts = {}) => {
      const method = opts.method || 'GET';
      const u = String(url);
      const body = opts.body && String(opts.body).trim().startsWith('{') ? JSON.parse(opts.body) : null;
      calls.push({ url: u, method, body });
      if (u.includes('accounts:signInWithCustomToken')) return Promise.resolve(jsonRes({ idToken: 'fb-token' }));
      if (u === 'https://db.test/alerts.json?auth=fb-token') return Promise.resolve(jsonRes({}));
      if (u === 'https://db.test/users.json?auth=fb-token') {
        return Promise.resolve(jsonRes({
          sup1: { role: 'supervisor', usine: 'Usine A', status: 'active', fcmToken: 'fcm-sup1' },
          admin1: { role: 'admin', usine: 'Usine A', status: 'active', fcmToken: 'fcm-admin1' },
        }));
      }
      if (u === 'https://db.test/supervisor_active_alerts.json?auth=fb-token') return Promise.resolve(jsonRes({}));
      if (u === 'https://db.test/notifications/sup1/n1.json?auth=fb-token' && method === 'GET') {
        return Promise.resolve(etagRes(notif));
      }
      if (u === 'https://db.test/notifications/admin1/n1.json?auth=fb-token' && method === 'GET') {
        return Promise.resolve(etagRes(notif));
      }
      if (u.includes('oauth2.googleapis.com/token')) return Promise.resolve(jsonRes({ access_token: 'fcm-access', expires_in: 3600 }));
      if (u.includes('fcm.googleapis.com')) return Promise.resolve(jsonRes({ name: 'msg-1' }));
      return Promise.resolve(jsonRes(body ?? {}));
    });

    await expect(pushSingleNotification(serviceEnv(), 'sup1', 'n1')).resolves.toBe(true);
    await expect(pushSingleNotification(serviceEnv(), 'admin1', 'n1')).resolves.toBe(false);

    const fcmCalls = calls.filter((c) => c.url.includes('fcm.googleapis.com'));
    expect(fcmCalls).toHaveLength(1);
    expect(fcmCalls[0].body.message.token).toBe('fcm-sup1');
    expect(fcmCalls[0].body.message.data).toMatchObject({
      recipientId: 'sup1',
      alertId: 'a1',
      type: 'new_alert',
      notifType: 'new_alert',
      alertType: 'maintenance',
      queueNotificationId: 'n1',
    });
    expect(fcmCalls[0].body.message.data.notificationId).not.toBe('n1');
  });

  test('retries a stale notification lock and sends confirm presence shift id', async () => {
    mockCrypto();
    const calls = [];
    const notif = {
      type: 'confirm_presence',
      shiftId: 'shift-1',
      shiftName: 'Night Shift',
      message: 'Are you still on shift?',
      pushSent: false,
      pushSending: true,
      pushSendingAt: '2026-05-20T08:00:00.000Z',
    };

    jest.spyOn(Date, 'now').mockReturnValue(Date.parse('2026-05-20T08:05:00.000Z'));
    globalThis.fetch = jest.fn((url, opts = {}) => {
      const method = opts.method || 'GET';
      const u = String(url);
      const body = opts.body && String(opts.body).trim().startsWith('{') ? JSON.parse(opts.body) : null;
      calls.push({ url: u, method, body });
      if (u.includes('accounts:signInWithCustomToken')) return Promise.resolve(jsonRes({ idToken: 'fb-token' }));
      if (u === 'https://db.test/alerts.json?auth=fb-token') return Promise.resolve(jsonRes({}));
      if (u === 'https://db.test/users.json?auth=fb-token') {
        return Promise.resolve(jsonRes({
          u1: { role: 'supervisor', usine: 'Usine A', status: 'active', fcmToken: 'fcm-u1' },
        }));
      }
      if (u === 'https://db.test/supervisor_active_alerts.json?auth=fb-token') return Promise.resolve(jsonRes({}));
      if (u === 'https://db.test/notifications/u1/n1.json?auth=fb-token' && method === 'GET') {
        return Promise.resolve(etagRes(notif));
      }
      if (u.includes('oauth2.googleapis.com/token')) return Promise.resolve(jsonRes({ access_token: 'fcm-access', expires_in: 3600 }));
      if (u.includes('fcm.googleapis.com')) return Promise.resolve(jsonRes({ name: 'msg-1' }));
      return Promise.resolve(jsonRes(body ?? {}));
    });

    const sent = await pushSingleNotification(serviceEnv(), 'u1', 'n1');
    expect(sent).toBe(true);

    const claim = calls.find((c) => c.url.includes('/notifications/u1/n1.json') && c.method === 'PUT');
    expect(claim.body.pushSending).toBe(true);
    expect(typeof claim.body.pushSendingAt).toBe('string');

    const fcm = calls.find((c) => c.url.includes('fcm.googleapis.com'));
    expect(fcm.body.message.data).toMatchObject({
      notifType: 'confirm_presence',
      shiftId: 'shift-1',
      shiftName: 'Night Shift',
    });
  });

  test('skips a fresh notification lock', async () => {
    mockCrypto();
    const calls = [];
    const notif = {
      type: 'help_request',
      message: 'Already locked',
      pushSent: false,
      pushSending: true,
      pushSendingAt: '2026-05-20T08:04:30.000Z',
    };

    jest.spyOn(Date, 'now').mockReturnValue(Date.parse('2026-05-20T08:05:00.000Z'));
    globalThis.fetch = jest.fn((url, opts = {}) => {
      const method = opts.method || 'GET';
      const u = String(url);
      const body = opts.body && String(opts.body).trim().startsWith('{') ? JSON.parse(opts.body) : null;
      calls.push({ url: u, method, body });
      if (u.includes('accounts:signInWithCustomToken')) return Promise.resolve(jsonRes({ idToken: 'fb-token' }));
      if (u === 'https://db.test/alerts.json?auth=fb-token') return Promise.resolve(jsonRes({}));
      if (u === 'https://db.test/users.json?auth=fb-token') {
        return Promise.resolve(jsonRes({
          u1: { role: 'supervisor', usine: 'Usine A', status: 'active', fcmToken: 'fcm-u1' },
        }));
      }
      if (u === 'https://db.test/supervisor_active_alerts.json?auth=fb-token') return Promise.resolve(jsonRes({}));
      if (u === 'https://db.test/notifications/u1/n1.json?auth=fb-token' && method === 'GET') {
        return Promise.resolve(etagRes(notif));
      }
      return Promise.resolve(jsonRes(body ?? {}));
    });

    const sent = await pushSingleNotification(serviceEnv(), 'u1', 'n1');
    expect(sent).toBe(false);
    expect(calls.some((c) => c.url.includes('fcm.googleapis.com'))).toBe(false);
    expect(calls.some((c) => c.url.includes('/notifications/u1/n1.json') && c.method === 'PUT')).toBe(false);
  });
});
