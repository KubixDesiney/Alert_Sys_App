import { afterEach, describe, expect, jest, test } from '@jest/globals';
import {
  haversineDistance,
  inferFactoryLocation,
  runAIAssignments,
} from '../cloudflare_workerV2.js';

function jsonRes(data, init = {}) {
  return new Response(JSON.stringify(data), {
    status: init.status || 200,
    headers: init.headers || { 'Content-Type': 'application/json' },
  });
}

function etagRes(data, etag = '"etag-1"') {
  return new Response(JSON.stringify(data), {
    status: 200,
    headers: { 'Content-Type': 'application/json', ETag: etag },
  });
}

function buildTransferFixture({ insufficientCritical = false, donorBusy = false, staleGps = false, includeFar = false } = {}) {
  const now = Date.now();
  const alertsMap = {
    c1: {
      status: 'disponible',
      type: 'qualite',
      usine: 'Factory A',
      factoryId: 'factory_a',
      convoyeur: 1,
      poste: 1,
      timestamp: '2026-05-11T08:00:00.000Z',
      isCritical: true,
    },
    ...(insufficientCritical
      ? {}
      : {
          c2: {
            status: 'disponible',
            type: 'maintenance',
            usine: 'Factory A',
            factoryId: 'factory_a',
            convoyeur: 2,
            poste: 2,
            timestamp: '2026-05-11T08:01:00.000Z',
            isCritical: true,
          },
        }),
    ...(donorBusy
      ? {
          b1: { status: 'disponible', usine: 'Factory B', factoryId: 'factory_b', isCritical: false },
          b2: { status: 'en_cours', usine: 'Factory B', factoryId: 'factory_b', isCritical: false, superviseurId: 'buddyB' },
          b3: { status: 'disponible', usine: 'Factory B', factoryId: 'factory_b', isCritical: false },
        }
      : {}),
    ...(includeFar
      ? {
          farHistory: {
            status: 'validee',
            superviseurId: 'far',
            type: 'qualite',
            elapsedTime: 10,
            usine: 'Factory A',
            factoryId: 'factory_a',
            convoyeur: 1,
            poste: 1,
          },
        }
      : {}),
  };

  const usersMap = {
    near: {
      role: 'supervisor',
      status: 'active',
      usine: 'Factory B',
      factoryId: 'factory_b',
      fullName: 'Near Supervisor',
      fcmToken: 'token-near',
      currentLocation: {
        lat: 0,
        lng: 0.1,
        updatedAt: staleGps ? now - 11 * 60 * 1000 : now,
      },
    },
    buddyB: {
      role: 'supervisor',
      status: 'active',
      usine: 'Factory B',
      factoryId: 'factory_b',
      fullName: 'Buddy B',
    },
    ...(includeFar
      ? {
          far: {
            role: 'supervisor',
            status: 'active',
            usine: 'Factory C',
            factoryId: 'factory_c',
            fullName: 'Far Supervisor',
            currentLocation: { lat: 0, lng: 1, updatedAt: now },
          },
          buddyC: {
            role: 'supervisor',
            status: 'active',
            usine: 'Factory C',
            factoryId: 'factory_c',
            fullName: 'Buddy C',
          },
        }
      : {}),
  };

  const activeShift = {
    id: 'shift-1',
    name: 'Morning',
    aiCommander: true,
    handleAssignments: true,
    handleCrossFactoryTransfer: true,
    supervisors: {
      near: { ready: true },
      ...(includeFar ? { far: { ready: true } } : {}),
    },
  };

  return {
    alertsMap,
    usersMap,
    activeShift,
    factoriesMap: {
      factory_a: { location: { lat: 0, lng: 0 }, address: 'Factory A' },
    },
  };
}

async function runWithMockedFetch(fixture) {
  const fetchCalls = [];
  const alertData = { ...fixture.alertsMap.c1, push_sent: false };

  globalThis.fetch = jest.fn((url, opts = {}) => {
    const u = String(url);
    const method = opts.method || 'GET';
    let body = null;
    try {
      body = opts.body ? JSON.parse(opts.body) : null;
    } catch (_) {}
    fetchCalls.push({ url: u, method, body });

    if (u.includes('ai_feedback/summary.json')) return Promise.resolve(jsonRes({}));
    if (u.includes('ai_feedback/adjustments.json')) return Promise.resolve(jsonRes({}));
    if (u.includes('ai_decisions/c1/actionId.json')) return Promise.resolve(jsonRes(null));
    if (u.includes('/alerts/c1.json') && method === 'GET') return Promise.resolve(etagRes(alertData));
    if (u.includes('/alerts/c1.json') && method === 'PUT') return Promise.resolve(jsonRes({ ...alertData, ...body }));
    if (u.includes('users/') && u.includes('/aiCooldownUntil.json')) return Promise.resolve(jsonRes('ok'));
    if (u.includes('alerts/c1/aiHistory.json')) return Promise.resolve(jsonRes({ name: 'hist1' }));
    if (u.includes('ai_decisions/c1.json')) return Promise.resolve(jsonRes({ ok: true }));
    if (u.includes('notifications/')) return Promise.resolve(jsonRes({ name: 'notif1' }));
    if (u.includes('shift_ai_logs/shift-1.json')) return Promise.resolve(jsonRes({ name: 'log1' }));
    return Promise.resolve(jsonRes({}));
  });

  jest.spyOn(console, 'error').mockImplementation(() => {});
  const assigned = await runAIAssignments(
    { FB_DB_URL: 'https://db.test/', FB_API_KEY: 'key' },
    { token: 'tok', ...fixture },
  );
  return { assigned, fetchCalls };
}

describe('proximity helpers', () => {
  afterEach(() => {
    delete globalThis.fetch;
    jest.restoreAllMocks();
  });

  test('inferFactoryLocation averages multiple fresh supervisor GPS positions', () => {
    const now = Date.now();
    const result = inferFactoryLocation(
      {
        u1: { role: 'supervisor', factoryId: 'factory_a', currentLocation: { lat: 10, lng: 20, updatedAt: now } },
        u2: { role: 'supervisor', factoryId: 'factory_a', currentLocation: { lat: 14, lng: 24, updatedAt: now } },
        u3: { role: 'supervisor', factoryId: 'factory_b', currentLocation: { lat: 0, lng: 0, updatedAt: now } },
      },
      'factory_a',
      10 * 60 * 1000,
    );

    expect(result.lat).toBe(12);
    expect(result.lng).toBe(22);
    expect(result.source).toBe('supervisor_average');
  });

  test('inferFactoryLocation returns null with no fresh data', () => {
    const result = inferFactoryLocation(
      {
        u1: {
          role: 'supervisor',
          factoryId: 'factory_a',
          currentLocation: { lat: 10, lng: 20, updatedAt: Date.now() - 11 * 60 * 1000 },
        },
      },
      'factory_a',
      10 * 60 * 1000,
    );

    expect(result).toBeNull();
  });

  test('haversineDistance matches a known coordinate pair', () => {
    const londonToParisKm = haversineDistance(51.5074, -0.1278, 48.8566, 2.3522);
    expect(londonToParisKm).toBeCloseTo(343.6, 0);
  });
});

describe('proximity-based cross-factory transfer gates', () => {
  afterEach(() => {
    delete globalThis.fetch;
    jest.restoreAllMocks();
  });

  test('Gate 1 blocks transfer with insufficient critical alerts', async () => {
    const { assigned, fetchCalls } = await runWithMockedFetch(buildTransferFixture({ insufficientCritical: true }));

    expect(assigned).toBe(0);
    expect(fetchCalls.some((c) => c.url.includes('/alerts/c1.json') && c.method === 'PUT')).toBe(false);
    expect(fetchCalls.some((c) => c.body?.kind === 'cross_factory_blocked' && c.body?.gate === 'gate_1_alert_factory_overwhelmed')).toBe(true);
  });

  test('Gate 2 blocks transfer when donor factory is too busy', async () => {
    const { assigned, fetchCalls } = await runWithMockedFetch(buildTransferFixture({ donorBusy: true }));

    expect(assigned).toBe(0);
    expect(fetchCalls.some((c) => c.url.includes('/alerts/c1.json') && c.method === 'PUT')).toBe(false);
    expect(fetchCalls.some((c) => c.body?.kind === 'cross_factory_blocked' && c.body?.gate === 'gate_2_donor_factory_quiet')).toBe(true);
  });

  test('Gate 3 picks the closer supervisor by GPS distance', async () => {
    const { assigned, fetchCalls } = await runWithMockedFetch(buildTransferFixture({ includeFar: true }));
    const put = fetchCalls.find((c) => c.url.includes('/alerts/c1.json') && c.method === 'PUT');

    expect(assigned).toBe(1);
    expect(put.body.superviseurId).toBe('near');
  });

  test('successful transfer writes notification and transfer log when all gates pass', async () => {
    const { assigned, fetchCalls } = await runWithMockedFetch(buildTransferFixture());
    const put = fetchCalls.find((c) => c.url.includes('/alerts/c1.json') && c.method === 'PUT');
    const notification = fetchCalls.find((c) => c.url.includes('notifications/near.json') && c.method === 'POST');
    const transferLog = fetchCalls.find((c) => c.body?.kind === 'cross_factory_transfer');

    expect(assigned).toBe(1);
    expect(put.body.superviseurId).toBe('near');
    expect(notification.body.type).toBe('cross_factory_transfer');
    expect(notification.body.buzz).toBe(true);
    expect(transferLog.body.details.distanceKm).toBeGreaterThan(0);
    expect(transferLog.body.details.supervisorName).toBe('Near Supervisor');
    expect(transferLog.body.details.alertFactory).toBe('Factory A');
    expect(transferLog.body.details.donorFactory).toBe('Factory B');
    expect(transferLog.body.details.criticalAlertCount).toBe(2);
  });

  test('supervisor with stale GPS is skipped', async () => {
    const { assigned, fetchCalls } = await runWithMockedFetch(buildTransferFixture({ staleGps: true }));

    expect(assigned).toBe(0);
    expect(fetchCalls.some((c) => c.url.includes('/alerts/c1.json') && c.method === 'PUT')).toBe(false);
    expect(fetchCalls.some((c) => c.body?.kind === 'cross_factory_blocked' && c.body?.gate === 'gate_3_proximity_scoring')).toBe(true);
  });
});
