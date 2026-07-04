import { describe, test, expect } from '@jest/globals';
import { selectPrunableAlerts } from '../cloudflare_backup_worker.js';

const DAY = 24 * 60 * 60 * 1000;
const NOW = Date.parse('2026-07-01T00:00:00.000Z');
const CUTOFF = NOW - 365 * DAY;

const alert = (daysAgo, overrides = {}) => ({
  status: 'validee',
  type: 'qualite',
  usine: 'Usine A',
  timestamp: new Date(NOW - daysAgo * DAY).toISOString(),
  ...overrides,
});

describe('selectPrunableAlerts (alert retention policy)', () => {
  test('selects only terminal alerts older than the cutoff', () => {
    const picked = selectPrunableAlerts(
      {
        oldResolved: alert(400),
        oldCancelled: alert(500, { status: 'cancelled' }),
        oldOpen: alert(400, { status: 'disponible' }),
        oldClaimed: alert(400, { status: 'en_cours' }),
        recentResolved: alert(10),
      },
      CUTOFF,
    );
    expect(picked.map((p) => p.id).sort()).toEqual(['oldCancelled', 'oldResolved']);
  });

  test('never prunes open alerts regardless of age', () => {
    const picked = selectPrunableAlerts(
      { ancient: alert(3000, { status: 'en_cours' }) },
      CUTOFF,
    );
    expect(picked).toEqual([]);
  });

  test('leaves alerts with missing or unparseable timestamps alone', () => {
    const picked = selectPrunableAlerts(
      {
        noTs: { status: 'validee' },
        badTs: alert(400, { timestamp: 'not-a-date' }),
        good: alert(400),
      },
      CUTOFF,
    );
    expect(picked.map((p) => p.id)).toEqual(['good']);
  });

  test('caps the batch and prunes oldest first', () => {
    const map = {};
    for (let i = 0; i < 10; i++) map[`a${i}`] = alert(370 + i);
    const picked = selectPrunableAlerts(map, CUTOFF, 3);
    expect(picked.map((p) => p.id)).toEqual(['a9', 'a8', 'a7']);
  });

  test('handles null/empty input safely', () => {
    expect(selectPrunableAlerts(null, CUTOFF)).toEqual([]);
    expect(selectPrunableAlerts({}, CUTOFF)).toEqual([]);
  });
});
