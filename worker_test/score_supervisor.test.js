import { describe, test, expect } from '@jest/globals';
import {
  buildSupStats,
  scoreSupervisor,
} from '../cloudflare_worker.js';

const NOW = Date.UTC(2026, 4, 1, 9, 0, 0);

const validAlert = (overrides = {}) => ({
  status: 'validee',
  superviseurId: 'u1',
  type: 'qualite',
  elapsedTime: 12,
  usine: 'Usine A',
  convoyeur: 1,
  poste: 1,
  ...overrides,
});

describe('buildSupStats', () => {
  test('returns empty stats for empty alerts map', () => {
    expect(buildSupStats({})).toEqual({});
  });

  test('skips alerts that are not yet resolved', () => {
    const stats = buildSupStats({
      a1: { status: 'en_cours', superviseurId: 'u1', type: 'qualite' },
    });
    expect(stats).toEqual({});
  });

  test('skips resolved alerts without elapsedTime', () => {
    const stats = buildSupStats({
      a1: { status: 'validee', superviseurId: 'u1', type: 'qualite' },
    });
    expect(stats).toEqual({});
  });

  test('aggregates type counts and average resolution time per supervisor', () => {
    const stats = buildSupStats({
      a1: validAlert({ elapsedTime: 10 }),
      a2: validAlert({ elapsedTime: 20 }),
      a3: validAlert({ elapsedTime: 30, type: 'maintenance' }),
    });
    expect(stats.u1.typeCounts.qualite).toBe(2);
    expect(stats.u1.typeCounts.maintenance).toBe(1);
    expect(stats.u1.typeAvgRes.qualite).toBe(15);
    expect(stats.u1.typeAvgRes.maintenance).toBe(30);
  });

  test('credits both superviseur and assistant', () => {
    const stats = buildSupStats({
      a1: validAlert({ superviseurId: 'u1', assistantId: 'u2' }),
    });
    expect(stats.u1).toBeDefined();
    expect(stats.u2).toBeDefined();
    expect(stats.u2.typeCounts.qualite).toBe(1);
  });

  test('counts station and conveyor occurrences', () => {
    const stats = buildSupStats({
      a1: validAlert({ convoyeur: 2, poste: 5 }),
      a2: validAlert({ convoyeur: 2, poste: 5 }),
      a3: validAlert({ convoyeur: 2, poste: 7 }),
    });
    expect(stats.u1.stationCounts['Usine A|2|5']).toBe(2);
    expect(stats.u1.stationCounts['Usine A|2|7']).toBe(1);
    expect(stats.u1.conveyorCounts['Usine A|2']).toBe(3);
  });
});

describe('scoreSupervisor', () => {
  const baseAlert = {
    type: 'qualite',
    usine: 'Usine A',
    convoyeur: 1,
    poste: 1,
    isCritical: false,
  };

  test('rewards a same-factory supervisor with no history', () => {
    const r = scoreSupervisor(
      { uid: 'u1', usine: 'Usine A' },
      baseAlert,
      {},
      {},
      0,
      NOW,
    );
    expect(r.score).toBeGreaterThanOrEqual(30);
    expect(r.reasons.some((x) => x.includes('Same factory'))).toBe(true);
  });

  test('penalizes a cross-factory supervisor', () => {
    const r = scoreSupervisor(
      { uid: 'u1', usine: 'Usine B' },
      baseAlert,
      {},
      {},
      0,
      NOW,
    );
    expect(r.score).toBe(0);
    expect(r.reasons.some((x) => x.includes('Different factory'))).toBe(true);
  });

  test('adds a bonus per past resolution of the same alert type', () => {
    const stats = {
      u1: {
        typeCounts: { qualite: 3 },
        typeTotalTimes: { qualite: 30 },
        typeAvgRes: { qualite: 10 },
        stationCounts: {},
        conveyorCounts: {},
      },
    };
    const r = scoreSupervisor(
      { uid: 'u1', usine: 'Usine A' },
      baseAlert,
      stats,
      {},
      0,
      NOW,
    );
    expect(r.reasons.some((x) => x.includes('past qualite'))).toBe(true);
  });

  test('caps the past-experience bonus at 40', () => {
    const stats = {
      u1: {
        typeCounts: { qualite: 100 },
        typeTotalTimes: { qualite: 0 },
        typeAvgRes: {},
        stationCounts: {},
        conveyorCounts: {},
      },
    };
    const r = scoreSupervisor(
      { uid: 'u1', usine: 'Usine A' },
      baseAlert,
      stats,
      {},
      0,
      NOW,
    );
    // Same-factory bonus (30) + capped past bonus (40) = 70 minimum.
    expect(r.score).toBeGreaterThanOrEqual(70);
  });

  test('penalizes recent assignment load on non-critical alerts only', () => {
    const noLoad = scoreSupervisor(
      { uid: 'u1', usine: 'Usine A' },
      baseAlert,
      {},
      {},
      0,
      NOW,
    ).score;
    const withLoad = scoreSupervisor(
      { uid: 'u1', usine: 'Usine A' },
      baseAlert,
      {},
      {},
      2,
      NOW,
    ).score;
    expect(withLoad).toBeLessThan(noLoad);

    const criticalNoPenalty = scoreSupervisor(
      { uid: 'u1', usine: 'Usine A' },
      { ...baseAlert, isCritical: true },
      {},
      {},
      2,
      NOW,
    ).score;
    expect(criticalNoPenalty).toBe(noLoad);
  });

  test('applies feedback adjustment within ±20 cap', () => {
    const fb = {
      u1: {
        acceptedAssignments: 100,
        rejectedAssignments: 0,
        abortedAssignments: 0,
        resolvedOutcomes: 100,
      },
    };
    const r = scoreSupervisor(
      { uid: 'u1', usine: 'Usine A' },
      baseAlert,
      {},
      fb,
      0,
      NOW,
    );
    const adjustReason = r.reasons.find((x) => x.includes('Feedback adjustment'));
    expect(adjustReason).toBeDefined();
    expect(adjustReason).toContain('+20');
  });

  test('never returns a negative score', () => {
    const r = scoreSupervisor(
      { uid: 'u1', usine: 'Usine X' },
      baseAlert,
      {},
      { u1: { rejectedAssignments: 999, abortedAssignments: 999 } },
      99,
      NOW,
    );
    expect(r.score).toBeGreaterThanOrEqual(0);
  });
});
