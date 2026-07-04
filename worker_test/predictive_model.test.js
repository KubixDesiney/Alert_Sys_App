import { describe, test, expect, afterEach, jest } from '@jest/globals';
import worker, { buildPredictiveModel, _toMs } from '../cloudflare_worker.js';
import workerV2, {
  buildPredictiveModel as buildPredictiveModelV2,
} from '../cloudflare_ai_worker.js';

const recentAlert = (overrides = {}) => ({
  status: 'validee',
  type: 'qualite',
  usine: 'Usine A',
  convoyeur: 1,
  poste: 1,
  isCritical: false,
  timestamp: new Date(Date.now() - 86400000).toISOString(),
  ...overrides,
});

const datedAlert = (daysAgo, overrides = {}) => ({
  status: 'validee',
  type: 'qualite',
  usine: 'Usine A',
  convoyeur: 1,
  poste: 1,
  isCritical: false,
  timestamp: new Date(Date.now() - daysAgo * 86400000).toISOString(),
  ...overrides,
});

function jsonRes(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

function buildPredictEndpointMock(alertsMap = {}) {
  const writes = [];
  const fetchMock = jest.fn((url, opts = {}) => {
    const u = String(url);
    const method = opts.method ?? 'GET';

    if (u.includes('identitytoolkit')) {
      return Promise.resolve(jsonRes({ idToken: 'tok' }));
    }
    if (u.includes('/alerts.json') && method === 'GET') {
      return Promise.resolve(jsonRes(alertsMap));
    }
    if (u.includes('/users.json') && method === 'GET') {
      return Promise.resolve(jsonRes({}));
    }
    if (u.includes('/shifts.json') && method === 'GET') {
      return Promise.resolve(jsonRes({}));
    }
    if (u.includes('/factories.json') && method === 'GET') {
      return Promise.resolve(jsonRes({}));
    }
    if (u.includes('ai_predictions/') && method === 'PUT') {
      writes.push({
        url: u,
        method,
        body: JSON.parse(opts.body),
      });
      return Promise.resolve(jsonRes({ ok: true }));
    }
    return Promise.resolve(jsonRes({}));
  });

  return { fetchMock, writes };
}

describe('_toMs', () => {
  test('returns numeric timestamps unchanged', () => {
    expect(_toMs(1234567890)).toBe(1234567890);
  });

  test('parses ISO strings to ms since epoch', () => {
    const ms = Date.parse('2026-05-01T00:00:00.000Z');
    expect(_toMs('2026-05-01T00:00:00.000Z')).toBe(ms);
  });

  test('returns null for unparseable strings', () => {
    expect(_toMs('not a date')).toBeNull();
  });

  test('returns null for null / undefined', () => {
    expect(_toMs(null)).toBeNull();
    expect(_toMs(undefined)).toBeNull();
  });
});

describe('buildPredictiveModel', () => {
  test('returns a model with curves for each known alert type', () => {
    const model = buildPredictiveModel({});
    expect(Object.keys(model.curves)).toEqual(
      expect.arrayContaining([
        'qualite',
        'maintenance',
        'defaut_produit',
        'manque_ressource',
      ]),
    );
  });

  test('includes generatedAt as an ISO string', () => {
    const model = buildPredictiveModel({});
    expect(typeof model.generatedAt).toBe('string');
    expect(() => new Date(model.generatedAt).toISOString()).not.toThrow();
  });

  test('predictions list is empty when there is no history', () => {
    const model = buildPredictiveModel({});
    expect(model.predictions).toEqual([]);
    expect(model.factoryRisk).toEqual([]);
  });

  test('produces predictions sorted by score (descending)', () => {
    const alerts = {};
    for (let i = 0; i < 5; i++) {
      alerts[`a${i}`] = recentAlert({ poste: 1 });
    }
    for (let i = 0; i < 2; i++) {
      alerts[`b${i}`] = recentAlert({ poste: 2 });
    }

    const model = buildPredictiveModel(alerts);
    expect(model.predictions.length).toBeGreaterThan(0);
    for (let i = 1; i < model.predictions.length; i++) {
      expect(model.predictions[i - 1].score).toBeGreaterThanOrEqual(
        model.predictions[i].score,
      );
    }
  });

  test('factory risk ranking sums activity per factory', () => {
    const alerts = {
      a1: recentAlert({ usine: 'Usine A' }),
      a2: recentAlert({ usine: 'Usine A' }),
      a3: recentAlert({ usine: 'Usine B' }),
    };
    const model = buildPredictiveModel(alerts);
    const a = model.factoryRisk.find((f) => f.id === 'usine_a');
    const b = model.factoryRisk.find((f) => f.id === 'usine_b');
    expect(a.count).toBe(2);
    expect(b.count).toBe(1);
    expect(a.score).toBeGreaterThanOrEqual(b.score);
  });

  test('skips alerts older than the prediction horizon', () => {
    const old = new Date(Date.now() - 365 * 86400000).toISOString();
    const model = buildPredictiveModel({
      a1: recentAlert({ timestamp: old }),
    });
    expect(model.predictions).toEqual([]);
  });

  test('skips unknown alert types', () => {
    const model = buildPredictiveModel({
      a1: recentAlert({ type: 'unknown_type_xx' }),
    });
    expect(model.predictions).toEqual([]);
  });

  test('curve buckets are ordered by offsetHours', () => {
    const alerts = { a1: recentAlert() };
    const model = buildPredictiveModel(alerts);
    const buckets = model.curves.qualite.buckets;
    expect(buckets).toHaveLength(12);
    for (let i = 0; i < buckets.length; i++) {
      expect(buckets[i].offsetHours).toBe(i * 2);
    }
  });

  test('curve probability values are in [0, 1]', () => {
    const alerts = {};
    for (let i = 0; i < 30; i++) {
      alerts[`a${i}`] = recentAlert({
        timestamp: new Date(Date.now() - i * 3600000).toISOString(),
      });
    }
    const model = buildPredictiveModel(alerts);
    for (const bucket of model.curves.qualite.buckets) {
      expect(bucket.probability).toBeGreaterThanOrEqual(0);
      expect(bucket.probability).toBeLessThanOrEqual(1);
    }
  });
});

describe.each([
  ['modular worker', worker],
  ['monolithic worker', workerV2],
])('%s predict endpoint factory scoping', (_label, targetWorker) => {
  test('writes a factory-scoped snapshot and excludes other factories from the model', async () => {
    const alerts = {
      a1: recentAlert({ usine: 'Usine A', convoyeur: 1, poste: 1 }),
      b1: recentAlert({ usine: 'Usine B', convoyeur: 9, poste: 9 }),
    };
    const { fetchMock, writes } = buildPredictEndpointMock(alerts);
    globalThis.fetch = fetchMock;

    const res = await targetWorker.fetch(
      new Request('https://w.test/predict?factory=Usine%20A'),
      { FB_DB_URL: 'https://db.test/', FB_API_KEY: 'key' },
      { waitUntil() {} },
    );

    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.factoryScope).toBe('Usine A');
    expect(body.predictions).toHaveLength(1);
    expect(body.predictions[0].usine).toBe('Usine A');
    expect(body.factoryRisk).toHaveLength(1);
    expect(body.factoryRisk[0].name).toBe('Usine A');
    expect(
      writes.some((w) => w.url.includes('ai_predictions/latest.json')),
    ).toBe(false);
    expect(
      writes.some((w) =>
        w.url.includes('ai_predictions/factory/usine_a/latest.json'),
      ),
    ).toBe(true);
    expect(
      writes.some((w) =>
        w.url.includes('ai_predictions/factory/usine_a/history/'),
      ),
    ).toBe(true);
  });
});

afterEach(() => {
  jest.restoreAllMocks();
  delete globalThis.fetch;
});

describe('buildPredictiveModel V2 recency-weighted risk curves', () => {
  test('keeps stale high-volume history from pegging 24h risk at 100%', () => {
    const alerts = {};
    for (let i = 0; i < 90; i++) {
      alerts[`old${i}`] = datedAlert(90 + i);
    }

    const model = buildPredictiveModelV2(alerts);

    expect(model.horizonDays).toBe(180);
    expect(model.curves.qualite.sampleSize).toBe(90);
    expect(model.curves.qualite.total24h).toBeLessThan(0.1);
  });

  test('raises 24h risk when the same alert volume is recent', () => {
    const oldAlerts = {};
    const recentAlerts = {};
    for (let i = 0; i < 30; i++) {
      oldAlerts[`old${i}`] = datedAlert(120 + i);
      recentAlerts[`recent${i}`] = datedAlert(i / 24);
    }

    const oldModel = buildPredictiveModelV2(oldAlerts);
    const recentModel = buildPredictiveModelV2(recentAlerts);

    expect(recentModel.curves.qualite.total24h).toBeGreaterThan(0.6);
    expect(oldModel.curves.qualite.total24h).toBeLessThan(0.02);
  });

  test('uses recency-weighted rates for 2-hour buckets instead of flattening all bars', () => {
    const alerts = {};
    for (let i = 0; i < 120; i++) {
      alerts[`old${i}`] = datedAlert(60 + i, {
        timestamp: new Date(Date.now() - (60 + i) * 86400000)
          .toISOString()
          .replace(/T\d\d:/, 'T08:'),
      });
    }

    const buckets = buildPredictiveModelV2(alerts).curves.qualite.buckets;
    const probabilities = buckets.map((b) => b.probability);

    expect(Math.max(...probabilities)).toBeLessThan(0.25);
    expect(new Set(probabilities).size).toBeGreaterThan(1);
  });
});

