import { afterEach, describe, expect, jest, test } from '@jest/globals';
import {
  evaluateNotificationDelivery,
  factoryCandidates,
  factoryMatches,
  getFcmTokensForFactory,
  processAlerts,
  pushSingleAlert,
  pushSingleNotification,
} from '../cloudflare_notify_worker.js';

const privateKeyBegin = ['-----', 'BEGIN', 'PRIVATE', 'KEY-----'].join(' ');
const privateKeyEnd = ['-----', 'END', 'PRIVATE', 'KEY-----'].join(' ');
const fakePrivateKey = `${privateKeyBegin}\nAAAA\n${privateKeyEnd}\n`;

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
      private_key: fakePrivateKey,
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
      timestamp: new Date(Date.now() - 60 * 1000).toISOString(),
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
      usine: 'Usine A',
      message: 'New alert from Usine A: maintenance',
      timestamp: new Date(Date.now() - 60 * 1000).toISOString(),
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

    // The admin row is closed terminally so no future cron rescans it.
    const adminSkip = calls.find(
      (c) => c.url.includes('/notifications/admin1/n1.json') && c.method === 'PATCH',
    );
    expect(adminSkip.body).toMatchObject({
      pushSent: true,
      pushSkipReason: 'role_mismatch',
    });
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

describe('new_alert send-time gates (busy + factory + freshness)', () => {
  afterEach(() => {
    jest.restoreAllMocks();
    delete globalThis.fetch;
  });

  function queuedNewAlertHarness({ notif, usersMap, alertsMap = {}, claimsMap = {} }) {
    const calls = [];
    globalThis.fetch = jest.fn((url, opts = {}) => {
      const method = opts.method || 'GET';
      const u = String(url);
      const body = opts.body && String(opts.body).trim().startsWith('{') ? JSON.parse(opts.body) : null;
      calls.push({ url: u, method, body });
      if (u.includes('accounts:signInWithCustomToken')) return Promise.resolve(jsonRes({ idToken: 'fb-token' }));
      if (u === 'https://db.test/alerts.json?auth=fb-token') return Promise.resolve(jsonRes(alertsMap));
      if (u === 'https://db.test/users.json?auth=fb-token') return Promise.resolve(jsonRes(usersMap));
      if (u === 'https://db.test/supervisor_active_alerts.json?auth=fb-token') return Promise.resolve(jsonRes(claimsMap));
      if (u.includes('/notifications/') && method === 'GET') return Promise.resolve(etagRes(notif));
      if (u.includes('oauth2.googleapis.com/token')) return Promise.resolve(jsonRes({ access_token: 'fcm-access', expires_in: 3600 }));
      if (u.includes('fcm.googleapis.com')) return Promise.resolve(jsonRes({ name: 'msg-1' }));
      return Promise.resolve(jsonRes(body ?? {}));
    });
    return calls;
  }

  function freshNewAlertNotif(overrides = {}) {
    return {
      type: 'new_alert',
      alertId: 'a1',
      alertType: 'maintenance',
      usine: 'Usine A',
      message: 'New alert from Usine A: maintenance',
      timestamp: new Date(Date.now() - 60 * 1000).toISOString(),
      pushSent: false,
      ...overrides,
    };
  }

  test('busy owner of an en_cours alert is skipped terminally', async () => {
    mockCrypto();
    const calls = queuedNewAlertHarness({
      notif: freshNewAlertNotif(),
      usersMap: {
        busySup: { role: 'supervisor', usine: 'Usine A', fcmToken: 'fcm-busy' },
      },
      alertsMap: {
        a9: { status: 'en_cours', superviseurId: 'busySup' },
      },
    });

    await expect(pushSingleNotification(serviceEnv(), 'busySup', 'n1')).resolves.toBe(false);
    expect(calls.some((c) => c.url.includes('fcm.googleapis.com'))).toBe(false);
    const skip = calls.find((c) => c.url.includes('/notifications/busySup/n1.json') && c.method === 'PATCH');
    expect(skip.body).toMatchObject({ pushSent: true, pushSkipReason: 'busy_supervisor' });
  });

  test('assisting supervisor is busy too and never buzzed', async () => {
    mockCrypto();
    const calls = queuedNewAlertHarness({
      notif: freshNewAlertNotif(),
      usersMap: {
        helper: { role: 'supervisor', usine: 'Usine A', fcmToken: 'fcm-helper' },
      },
      alertsMap: {
        a9: { status: 'en_cours', superviseurId: 'someoneElse', assistantId: 'helper' },
      },
    });

    await expect(pushSingleNotification(serviceEnv(), 'helper', 'n1')).resolves.toBe(false);
    expect(calls.some((c) => c.url.includes('fcm.googleapis.com'))).toBe(false);
    const skip = calls.find((c) => c.url.includes('/notifications/helper/n1.json') && c.method === 'PATCH');
    expect(skip.body).toMatchObject({ pushSkipReason: 'busy_supervisor' });
  });

  test('supervisor from another factory is skipped terminally', async () => {
    mockCrypto();
    const calls = queuedNewAlertHarness({
      notif: freshNewAlertNotif(),
      usersMap: {
        farAway: { role: 'supervisor', usine: 'Usine B', fcmToken: 'fcm-far' },
      },
    });

    await expect(pushSingleNotification(serviceEnv(), 'farAway', 'n1')).resolves.toBe(false);
    expect(calls.some((c) => c.url.includes('fcm.googleapis.com'))).toBe(false);
    const skip = calls.find((c) => c.url.includes('/notifications/farAway/n1.json') && c.method === 'PATCH');
    expect(skip.body).toMatchObject({ pushSkipReason: 'factory_mismatch' });
  });

  test('factoryId-keyed user still matches a usine-keyed alert', async () => {
    mockCrypto();
    const calls = queuedNewAlertHarness({
      notif: freshNewAlertNotif(),
      usersMap: {
        idKeyed: { role: 'supervisor', factoryId: 'Usine A', fcmToken: 'fcm-id-keyed' },
      },
    });

    await expect(pushSingleNotification(serviceEnv(), 'idKeyed', 'n1')).resolves.toBe(true);
    const fcm = calls.find((c) => c.url.includes('fcm.googleapis.com'));
    expect(fcm.body.message.token).toBe('fcm-id-keyed');
  });

  test('a stale new_alert row (>15 min) is closed instead of buzzing late', async () => {
    mockCrypto();
    const calls = queuedNewAlertHarness({
      notif: freshNewAlertNotif({
        timestamp: new Date(Date.now() - 16 * 60 * 1000).toISOString(),
      }),
      usersMap: {
        freeSup: { role: 'supervisor', usine: 'Usine A', fcmToken: 'fcm-free' },
      },
    });

    await expect(pushSingleNotification(serviceEnv(), 'freeSup', 'n1')).resolves.toBe(false);
    expect(calls.some((c) => c.url.includes('fcm.googleapis.com'))).toBe(false);
    const skip = calls.find((c) => c.url.includes('/notifications/freeSup/n1.json') && c.method === 'PATCH');
    expect(skip.body).toMatchObject({ pushSkipReason: 'expired' });
  });

  test('personally-addressed types still bypass busy and factory gates', () => {
    const busyAlertsMap = { a9: { status: 'en_cours', superviseurId: 'busySup' } };
    const verdict = evaluateNotificationDelivery(
      'busySup',
      { role: 'supervisor', usine: 'Usine B', fcmToken: 'tok' },
      {
        type: 'help_request',
        usine: 'Usine A',
        timestamp: new Date().toISOString(),
        pushSent: false,
      },
      busyAlertsMap,
      {},
    );
    expect(verdict).toEqual({ action: 'send' });
  });

  test('factory candidate matching handles mixed identifier styles', () => {
    expect(factoryMatches(
      factoryCandidates({ usine: 'Usine A' }),
      factoryCandidates({ factoryId: 'usine_a' }),
    )).toBe(true);
    expect(factoryMatches(
      factoryCandidates({ factoryId: 'plant-7', usine: 'North Plant' }),
      factoryCandidates({ usine: 'north plant' }),
    )).toBe(true);
    expect(factoryMatches(
      factoryCandidates({ usine: 'Usine A' }),
      factoryCandidates({ usine: 'Usine B' }),
    )).toBe(false);
    // No factory info on the alert → no constraint; none on the user → block.
    expect(factoryMatches(new Set(), factoryCandidates({ usine: 'Usine A' }))).toBe(true);
    expect(factoryMatches(factoryCandidates({ usine: 'Usine A' }), new Set())).toBe(false);
  });
});

describe('pushSingleAlert fast path busy semantics', () => {
  afterEach(() => {
    jest.restoreAllMocks();
    delete globalThis.fetch;
  });

  test('excludes en_cours owners/assistants and other factories; stale claims do not block', async () => {
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
      const u = String(url);
      const body = opts.body && String(opts.body).trim().startsWith('{') ? JSON.parse(opts.body) : null;
      calls.push({ url: u, method, body });
      if (u.includes('accounts:signInWithCustomToken')) return Promise.resolve(jsonRes({ idToken: 'fb-token' }));
      if (u.includes('/alerts/a1.json') && method === 'GET') return Promise.resolve(etagRes(alert));
      if (u === 'https://db.test/users.json?auth=fb-token') {
        return Promise.resolve(jsonRes({
          freeSup: { role: 'supervisor', usine: 'Usine A', fcmToken: 'fcm-free' },
          staleSup: { role: 'supervisor', usine: 'Usine A', fcmToken: 'fcm-stale' },
          busyOwner: { role: 'supervisor', usine: 'Usine A', fcmToken: 'fcm-owner' },
          busyAssistant: { role: 'supervisor', usine: 'Usine A', fcmToken: 'fcm-assist' },
          otherFactory: { role: 'supervisor', usine: 'Usine B', fcmToken: 'fcm-other' },
          admin: { role: 'admin', usine: 'Usine A', fcmToken: 'fcm-admin' },
        }));
      }
      if (u === 'https://db.test/supervisor_active_alerts.json?auth=fb-token') {
        return Promise.resolve(jsonRes({
          staleSup: { alertId: 'long-resolved-alert' },
          busyOwner: { alertId: 'a0' },
        }));
      }
      if (u.startsWith('https://db.test/alerts.json?auth=fb-token&orderBy=')) {
        return Promise.resolve(jsonRes({
          a0: { status: 'en_cours', superviseurId: 'busyOwner' },
          a2: { status: 'en_cours', superviseurId: 'someoneElse', assistantId: 'busyAssistant' },
        }));
      }
      if (u.includes('oauth2.googleapis.com/token')) return Promise.resolve(jsonRes({ access_token: 'fcm-access', expires_in: 3600 }));
      if (u.includes('fcm.googleapis.com')) return Promise.resolve(jsonRes({ name: 'msg-1' }));
      return Promise.resolve(jsonRes(body ?? {}));
    });

    await expect(pushSingleAlert(serviceEnv(), 'a1')).resolves.toBe(true);

    const fcmTokens = calls
      .filter((c) => c.url.includes('fcm.googleapis.com'))
      .map((c) => c.body.message.token)
      .sort();
    expect(fcmTokens).toEqual(['fcm-free', 'fcm-stale']);

    const finish = calls.filter((c) => c.url.includes('/alerts/a1.json') && c.method === 'PATCH').pop();
    expect(finish.body).toMatchObject({ push_sent: true });
  });
});
