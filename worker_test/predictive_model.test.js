import { describe, test, expect } from '@jest/globals';
import { buildPredictiveModel, _toMs } from '../cloudflare_worker.js';

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
