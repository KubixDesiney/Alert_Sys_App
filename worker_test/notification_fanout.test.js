import { afterEach, describe, expect, jest, test } from '@jest/globals';
import { getFcmTokensForFactory, processAlerts } from '../cloudflare_notify_worker.js';

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
      push_sent: false,
      push_sending: null,
      push_sending_at: null,
    });
  });
});
