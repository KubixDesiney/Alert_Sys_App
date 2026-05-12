import { describe, test, expect, afterEach, jest } from '@jest/globals';
import worker, { buildPredictiveModel, _toMs } from '../cloudflare_worker.js';
import workerV2, {
  buildPredictiveModel as buildPredictiveModelV2,
  _buildDailyFeatures,
  _fitGlobalScaler,
  _scaleFeatures,
  _runLstmForecast,
} from '../cloudflare_workerV2.js';

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

describe('_buildDailyFeatures', () => {
  test('returns contiguous per-day rows with the expected LSTM feature columns', () => {
    const alerts = {
      a1: {
        usine: 'Usine A',
        convoyeur: 1,
        poste: 2,
        type: 'qualite',
        isCritical: false,
        timestamp: '2026-05-01T06:00:00.000Z',
      },
      a2: {
        usine: 'Usine A',
        convoyeur: 1,
        poste: 2,
        type: 'maintenance',
        isCritical: true,
        timestamp: '2026-05-01T18:00:00.000Z',
      },
      a3: {
        usine: 'Usine A',
        convoyeur: 1,
        poste: 2,
        type: 'defaut_produit',
        isCritical: true,
        timestamp: '2026-05-03T12:00:00.000Z',
      },
    };

    const rows = _buildDailyFeatures(alerts);

    expect(rows).toEqual([
      {
        usine: 'Usine A',
        convoyeur: 1,
        poste: 2,
        date: '2026-05-01',
        is_qualite: 1,
        is_maintenance: 1,
        is_defaut_produit: 0,
        is_manque_ressource: 0,
        critical_count: 1,
        days_since_failure: 0,
        hour: 12,
        dayofweek: 4,
      },
      {
        usine: 'Usine A',
        convoyeur: 1,
        poste: 2,
        date: '2026-05-02',
        is_qualite: 0,
        is_maintenance: 0,
        is_defaut_produit: 0,
        is_manque_ressource: 0,
        critical_count: 0,
        days_since_failure: 1,
        hour: 0,
        dayofweek: 5,
      },
      {
        usine: 'Usine A',
        convoyeur: 1,
        poste: 2,
        date: '2026-05-03',
        is_qualite: 0,
        is_maintenance: 0,
        is_defaut_produit: 1,
        is_manque_ressource: 0,
        critical_count: 1,
        days_since_failure: 0,
        hour: 12,
        dayofweek: 6,
      },
    ]);
  });
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

describe('LSTM scaling helpers', () => {
  test('fitGlobalScaler and scaleFeatures perform min-max scaling with a 0.5 fallback for constant columns', () => {
    const rows = [
      { a: 0, b: 10, c: 7 },
      { a: 5, b: 10, c: 7 },
      { a: 10, b: 20, c: 7 },
    ];

    const scaler = _fitGlobalScaler(rows, ['a', 'b', 'c']);
    expect(scaler).toEqual({
      a: { min: 0, max: 10 },
      b: { min: 10, max: 20 },
      c: { min: 7, max: 7 },
    });

    expect(_scaleFeatures(rows, scaler, ['a', 'b', 'c'])).toEqual([
      { a: 0, b: 0, c: 0.5 },
      { a: 0.5, b: 0, c: 0.5 },
      { a: 1, b: 1, c: 0.5 },
    ]);
  });
});

describe('_runLstmForecast', () => {
  test('accepts a single prediction object when exactly one machine was sent', async () => {
    const alerts = {};
    for (let i = 0; i < 14; i++) {
      alerts[`a${i}`] = {
        usine: 'Usine A',
        convoyeur: 1,
        poste: 1,
        type: 'qualite',
        isCritical: i % 2 === 0,
        timestamp: new Date(Date.UTC(2026, 4, i + 1, 8, 0, 0)).toISOString(),
      };
    }

    globalThis.fetch = jest.fn(async (_url, opts) => {
      const body = JSON.parse(opts.body);
      expect(body.features).toHaveLength(1);
      expect(body.features[0]).toHaveLength(14);

      return new Response(JSON.stringify({
        ok: true,
        predictions: [
          {
            qualite: 0.72,
            maintenance: 0.08,
            defaut_produit: 0.1,
            manque_ressource: 0.1,
            top: [['qualite', 0.72]],
          },
        ],
      }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      });
    });

    const predictions = await _runLstmForecast({}, { alertsMap: alerts });

    expect(globalThis.fetch).toHaveBeenCalledTimes(1);
    expect(predictions).toHaveLength(1);
    expect(predictions[0]).toMatchObject({
      factoryId: 'usine_a',
      usine: 'Usine A',
      convoyeur: 1,
      poste: 1,
    });
    expect(predictions[0].lstmProbs.qualite).toBe(0.72);
  });

  test('batches multiple eligible machines into a single external request', async () => {
    const alerts = {};
    for (let i = 0; i < 14; i++) {
      alerts[`a${i}`] = {
        usine: 'Usine A',
        convoyeur: 1,
        poste: 1,
        type: 'qualite',
        isCritical: i % 3 === 0,
        timestamp: new Date(Date.UTC(2026, 4, i + 1, 8, 0, 0)).toISOString(),
      };
      alerts[`b${i}`] = {
        usine: 'Usine B',
        convoyeur: 2,
        poste: 3,
        type: 'maintenance',
        isCritical: i % 4 === 0,
        timestamp: new Date(Date.UTC(2026, 4, i + 1, 16, 0, 0)).toISOString(),
      };
    }

    globalThis.fetch = jest.fn(async (_url, opts) => {
      const body = JSON.parse(opts.body);
      expect(Array.isArray(body.features)).toBe(true);
      expect(body.features).toHaveLength(2);
      expect(body.features[0]).toHaveLength(14);
      expect(body.features[1]).toHaveLength(14);
      expect(body.features[0][0]).toHaveLength(8);
      expect(body.features[1][0]).toHaveLength(8);

      return new Response(JSON.stringify({
        ok: true,
        predictions: [
          {
            qualite: 0.91,
            maintenance: 0.03,
            defaut_produit: 0.04,
            manque_ressource: 0.02,
            top: [['qualite', 0.91]],
          },
          {
            qualite: 0.05,
            maintenance: 0.88,
            defaut_produit: 0.04,
            manque_ressource: 0.03,
            top: [['maintenance', 0.88]],
          },
        ],
      }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      });
    });

    const predictions = await _runLstmForecast({}, { alertsMap: alerts });

    expect(globalThis.fetch).toHaveBeenCalledTimes(1);
    expect(predictions).toHaveLength(2);
    expect(predictions[0]).toMatchObject({
      factoryId: 'usine_a',
      usine: 'Usine A',
      convoyeur: 1,
      poste: 1,
    });
    expect(predictions[0].lstmProbs.qualite).toBe(0.91);
    expect(predictions[1]).toMatchObject({
      factoryId: 'usine_b',
      usine: 'Usine B',
      convoyeur: 2,
      poste: 3,
    });
    expect(predictions[1].lstmProbs.maintenance).toBe(0.88);
  });

  test('warns on batch length mismatch and only maps aligned predictions by index', async () => {
    const alerts = {};
    for (let i = 0; i < 14; i++) {
      alerts[`a${i}`] = {
        usine: 'Usine A',
        convoyeur: 1,
        poste: 1,
        type: 'qualite',
        isCritical: false,
        timestamp: new Date(Date.UTC(2026, 4, i + 1, 8, 0, 0)).toISOString(),
      };
      alerts[`b${i}`] = {
        usine: 'Usine B',
        convoyeur: 2,
        poste: 2,
        type: 'maintenance',
        isCritical: false,
        timestamp: new Date(Date.UTC(2026, 4, i + 1, 9, 0, 0)).toISOString(),
      };
    }

    const warn = jest.spyOn(console, 'warn').mockImplementation(() => {});
    globalThis.fetch = jest.fn(async () => new Response(JSON.stringify({
      ok: true,
      predictions: [
        {
          qualite: 0.2,
          maintenance: 0.3,
          defaut_produit: 0.1,
          manque_ressource: 0.4,
        },
      ],
    }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    }));

    const predictions = await _runLstmForecast({}, { alertsMap: alerts });

    expect(globalThis.fetch).toHaveBeenCalledTimes(1);
    expect(warn).toHaveBeenCalledWith(
      '[LSTM] Batch response length mismatch: predictions=1, machines=2',
    );
    expect(predictions).toHaveLength(1);
    expect(predictions[0]).toMatchObject({
      factoryId: 'usine_a',
      usine: 'Usine A',
      convoyeur: 1,
      poste: 1,
    });
    expect(predictions[0].lstmProbs.maintenance).toBe(0.3);
  });

  test('skips machines with fewer than 14 days of history', async () => {
    const alerts = {};
    for (let i = 0; i < 13; i++) {
      alerts[`a${i}`] = {
        usine: 'Usine A',
        convoyeur: 1,
        poste: 1,
        type: 'qualite',
        isCritical: false,
        timestamp: new Date(Date.UTC(2026, 4, i + 1, 8, 0, 0)).toISOString(),
      };
    }

    globalThis.fetch = jest.fn();

    const predictions = await _runLstmForecast({}, { alertsMap: alerts });

    expect(predictions).toEqual([]);
    expect(globalThis.fetch).not.toHaveBeenCalled();
  });
});
