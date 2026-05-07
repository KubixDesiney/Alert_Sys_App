/**
 * Tests for predictive model validation.
 *
 * Covers: TP > 0 with matching alerts, TP = 0 with no matches,
 * skipping already-validated entries, and the /validate-predictions
 * HTTP endpoint shape.
 */
import { describe, test, expect, beforeEach, afterEach, jest } from '@jest/globals';
import { validatePredictions, _historyKey } from '../cloudflare_worker.js';
import worker from '../cloudflare_worker.js';

function jsonRes(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

const env = { FB_DB_URL: 'https://db.test/', FB_API_KEY: 'key' };

// Helper: produce an ISO string N hours ago.
function isoHoursAgo(h) {
  return new Date(Date.now() - h * 60 * 60 * 1000).toISOString();
}

// Build a fetch mock that captures PATCHes and PUTs.
function buildMock({ history = {}, alertsMap = {} } = {}) {
  const calls = [];
  const writes = []; // { url, method, body }
  const patchedSnapshots = {}; // snapKey → patch body
  let performanceWrite = null;
  let secondHistoryFetch = false;

  const fetchMock = jest.fn((url, opts) => {
    const u = String(url);
    const method = opts?.method ?? 'GET';
    calls.push({ url: u, method });

    if (u.includes('accounts:signUp') || u.includes('identitytoolkit')) {
      return Promise.resolve(jsonRes({ idToken: 'tok' }));
    }
    if (u.includes('/alerts.json') && method === 'GET') {
      return Promise.resolve(jsonRes(alertsMap));
    }
    if (u.includes('ai_predictions/history.json')) {
      // First call returns initial history; second call (post-patch aggregate)
      // returns the same history but with the patches applied so the
      // aggregator sees the newly-validated entries.
      if (!secondHistoryFetch) {
        secondHistoryFetch = true;
        return Promise.resolve(jsonRes(history));
      }
      const merged = {};
      for (const [k, v] of Object.entries(history)) {
        merged[k] = patchedSnapshots[k]
          ? { ...v, ...patchedSnapshots[k] }
          : v;
      }
      return Promise.resolve(jsonRes(merged));
    }
    if (u.includes('ai_predictions/history/') && method === 'PATCH') {
      const snapKey = u.match(/history\/([^.]+)\.json/)?.[1];
      try {
        patchedSnapshots[snapKey] = JSON.parse(opts.body);
      } catch (_) {}
      writes.push({ url: u, method, body: opts.body });
      return Promise.resolve(jsonRes({ ok: true }));
    }
    if (u.includes('ai_predictions/performance/latest') && method === 'PUT') {
      try { performanceWrite = JSON.parse(opts.body); } catch (_) {}
      writes.push({ url: u, method, body: opts.body });
      return Promise.resolve(jsonRes({ ok: true }));
    }
    return Promise.resolve(jsonRes(null));
  });

  return {
    fetchMock,
    calls,
    writes,
    getPatched: () => patchedSnapshots,
    getPerformance: () => performanceWrite,
  };
}

describe('validatePredictions', () => {
  beforeEach(() => {
    jest.spyOn(console, 'error').mockImplementation(() => {});
    jest.spyOn(console, 'log').mockImplementation(() => {});
  });
  afterEach(() => {
    jest.restoreAllMocks();
    delete globalThis.fetch;
  });

  test('snapshot with matching alerts yields TP > 0 and accuracy > 0', async () => {
    const genAt = isoHoursAgo(48); // 48h old → eligible
    const history = {
      snap1: {
        generatedAt: genAt,
        validated: false,
        predictions: [
          { factoryId: 'usine_a', convoyeur: 1, poste: 1, type: 'qualite', etaHours: 6 },
          { factoryId: 'usine_a', convoyeur: 2, poste: 3, type: 'maintenance', etaHours: 12 },
        ],
      },
    };
    // Two alerts: one that matches the first prediction (within 6h after gen),
    // one that does NOT match anything.
    const genMs = Date.parse(genAt);
    const alertsMap = {
      a1: {
        timestamp: new Date(genMs + 2 * 60 * 60 * 1000).toISOString(),
        usine: 'Usine A',
        convoyeur: 1,
        poste: 1,
        type: 'qualite',
      },
      a2: {
        timestamp: new Date(genMs + 4 * 60 * 60 * 1000).toISOString(),
        usine: 'Usine B',
        convoyeur: 9,
        poste: 9,
        type: 'qualite',
      },
    };

    const { fetchMock, getPatched, getPerformance } = buildMock({ history, alertsMap });
    globalThis.fetch = fetchMock;

    const processed = await validatePredictions(env, null);
    expect(processed).toBe(1);

    const patched = getPatched();
    expect(patched.snap1).toBeDefined();
    expect(patched.snap1.validated).toBe(true);
    expect(patched.snap1.validation.totalPredicted).toBe(2);
    expect(patched.snap1.validation.truePositives).toBe(1);
    expect(patched.snap1.validation.accuracy).toBeCloseTo(0.5, 4);

    const perf = getPerformance();
    expect(perf).not.toBeNull();
    expect(perf.totalSnapshots).toBeGreaterThanOrEqual(1);
    expect(perf.averageAccuracy).toBeGreaterThan(0);
  });

  test('snapshot with no matching alerts yields TP = 0 and accuracy = 0', async () => {
    const history = {
      snap1: {
        generatedAt: isoHoursAgo(30),
        validated: false,
        predictions: [
          { factoryId: 'usine_a', convoyeur: 1, poste: 1, type: 'qualite', etaHours: 6 },
        ],
      },
    };
    // No alerts at all → no matches.
    const { fetchMock, getPatched } = buildMock({ history, alertsMap: {} });
    globalThis.fetch = fetchMock;

    const processed = await validatePredictions(env, null);
    expect(processed).toBe(1);

    const patched = getPatched();
    expect(patched.snap1.validation.truePositives).toBe(0);
    expect(patched.snap1.validation.accuracy).toBe(0);
    // Still marked validated so we don't reprocess.
    expect(patched.snap1.validated).toBe(true);
  });

  test('already-validated entries are skipped', async () => {
    const history = {
      snap1: {
        generatedAt: isoHoursAgo(48),
        validated: true, // already done
        validation: { totalPredicted: 1, truePositives: 1, accuracy: 1.0, validatedAt: isoHoursAgo(1) },
        predictions: [
          { factoryId: 'usine_a', convoyeur: 1, poste: 1, type: 'qualite', etaHours: 6 },
        ],
      },
    };
    const { fetchMock, getPatched } = buildMock({ history, alertsMap: {} });
    globalThis.fetch = fetchMock;

    const processed = await validatePredictions(env, null);
    expect(processed).toBe(0);
    // No re-patch.
    expect(getPatched().snap1).toBeUndefined();
  });

  test('snapshots younger than 24h are not processed', async () => {
    const history = {
      young: {
        generatedAt: isoHoursAgo(2), // only 2h old
        validated: false,
        predictions: [
          { factoryId: 'usine_a', convoyeur: 1, poste: 1, type: 'qualite', etaHours: 6 },
        ],
      },
    };
    const { fetchMock, getPatched } = buildMock({ history, alertsMap: {} });
    globalThis.fetch = fetchMock;

    const processed = await validatePredictions(env, null);
    expect(processed).toBe(0);
    expect(getPatched().young).toBeUndefined();
  });

  test('/validate-predictions endpoint returns ok + processed count', async () => {
    const history = {
      snap1: {
        generatedAt: isoHoursAgo(48),
        validated: false,
        predictions: [
          { factoryId: 'usine_a', convoyeur: 1, poste: 1, type: 'qualite', etaHours: 6 },
        ],
      },
    };
    const { fetchMock } = buildMock({ history, alertsMap: {} });
    globalThis.fetch = fetchMock;

    const res = await worker.fetch(new Request('https://w.test/validate-predictions'), env, {
      waitUntil() {},
    });
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.ok).toBe(true);
    expect(typeof body.processed).toBe('number');
    expect(body.processed).toBe(1);
  });
});

describe('_historyKey', () => {
  test('replaces colons and dots so the ISO string is a valid Firebase path segment', () => {
    const iso = '2026-05-07T14:00:00.000Z';
    const key = _historyKey(iso);
    expect(key).not.toMatch(/[:.]/);
    expect(key).toBe('2026-05-07T14-00-00-000Z');
  });
});
