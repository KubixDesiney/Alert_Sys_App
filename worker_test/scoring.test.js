/**
 * Comprehensive scoring tests for scoreSupervisor.
 *
 * Each test pins an exact expected output for a known input set so that any
 * accidental change to the scoring formula is immediately caught.
 */
import { describe, test, expect } from '@jest/globals';
import { scoreSupervisor, buildSupStats } from '../cloudflare_worker.js';

const NOW = Date.UTC(2026, 4, 1, 9, 0, 0);

// ─── helpers ────────────────────────────────────────────────────────────────

const baseAlert = {
  type: 'qualite',
  usine: 'Usine A',
  convoyeur: 1,
  poste: 1,
  isCritical: false,
};

function score(supOverrides, alertOverrides, statsOverride, fbOverride, recentLoad, isCommander = false) {
  const sup = { uid: 'u1', usine: 'Usine A', ...supOverrides };
  const alert = { ...baseAlert, ...alertOverrides };
  const stats = statsOverride ?? {};
  const fb = fbOverride ?? {};
  return scoreSupervisor(sup, alert, stats, fb, recentLoad ?? 0, NOW, { isCommander });
}

function statsFor(uid, typeCounts, typeAvgRes, stationCounts, conveyorCounts) {
  return {
    [uid]: {
      typeCounts: typeCounts ?? {},
      typeAvgRes: typeAvgRes ?? {},
      stationCounts: stationCounts ?? {},
      conveyorCounts: conveyorCounts ?? {},
    },
  };
}

// ─── same / different factory bonus ─────────────────────────────────────────

describe('factory bonus / penalty', () => {
  test('same factory gives +30 with no other factors', () => {
    const r = score({ usine: 'Usine A' });
    expect(r.score).toBe(30);
    expect(r.reasons.some((x) => x.includes('Same factory (+30)'))).toBe(true);
  });

  test('different factory clamps to 0 (no commander)', () => {
    const r = score({ usine: 'Usine B' });
    expect(r.score).toBe(0);
    expect(r.reasons.some((x) => x.includes('Different factory'))).toBe(true);
  });

  test('different factory has NO penalty under commander', () => {
    const r = score({ usine: 'Usine B' }, {}, null, null, 0, true);
    // No factory penalty: score = 0 (no other factors), clamped to 0
    expect(r.score).toBe(0);
    expect(r.reasons.some((x) => x.includes('Different factory'))).toBe(false);
  });

  test('same factory still gets +30 under commander', () => {
    const r = score({ usine: 'Usine A' }, {}, null, null, 0, true);
    expect(r.score).toBe(30);
    expect(r.reasons.some((x) => x.includes('Same factory (+30)'))).toBe(true);
  });

  // CRITICAL: under commander, an experienced cross-factory sup outscores an
  // inexperienced same-factory sup (this would fail without the fix).
  test('cross-factory + commander: experienced beats inexperienced same-factory', () => {
    const experiencedCross = score(
      { usine: 'Usine B' },
      {},
      statsFor('u1', { qualite: 10 }, {}, {}, {}),
      null,
      0,
      true,  // isCommander = true
    );
    const inexperiencedSame = score(
      { usine: 'Usine A' },
      {},
      statsFor('u1', { qualite: 0 }, {}, {}, {}),
      null,
      0,
      true,
    );
    // cross-factory: 0 + min(10*4,40)=40 → 40
    // same-factory:  30 + 0 → 30
    expect(experiencedCross.score).toBe(40);
    expect(inexperiencedSame.score).toBe(30);
    expect(experiencedCross.score).toBeGreaterThan(inexperiencedSame.score);
  });

  // Same scenario WITHOUT commander: cross-factory penalty makes same-factory win.
  test('cross-factory WITHOUT commander: penalty makes same-factory win', () => {
    const experiencedCross = score(
      { usine: 'Usine B' },
      {},
      statsFor('u1', { qualite: 10 }, {}, {}, {}),
    );
    const inexperiencedSame = score(
      { usine: 'Usine A' },
      {},
      statsFor('u1', { qualite: 0 }, {}, {}, {}),
    );
    // cross-factory: -25 + 40 = 15  →  clamped to 15
    // same-factory:   30 + 0  = 30
    expect(experiencedCross.score).toBe(15);
    expect(inexperiencedSame.score).toBe(30);
    expect(inexperiencedSame.score).toBeGreaterThan(experiencedCross.score);
  });
});

// ─── type-experience bonus ───────────────────────────────────────────────────

describe('type experience bonus', () => {
  test('0 past resolutions → no type bonus', () => {
    const r = score({ usine: 'Usine A' });
    // Only same-factory +30
    expect(r.score).toBe(30);
  });

  test('3 past resolutions → +12 type bonus (3×4)', () => {
    const r = score(
      { usine: 'Usine A' },
      {},
      statsFor('u1', { qualite: 3 }, {}, {}, {}),
    );
    // 30 + 12 = 42
    expect(r.score).toBe(42);
    expect(r.reasons.some((x) => x.includes('past qualite'))).toBe(true);
  });

  test('type bonus caps at 40 (10+ resolutions)', () => {
    const r = score(
      { usine: 'Usine A' },
      {},
      statsFor('u1', { qualite: 100 }, {}, {}, {}),
    );
    // 30 + 40 (capped) = 70
    expect(r.score).toBe(70);
  });

  test('type mismatch: experience in "maintenance" does not affect "qualite" score', () => {
    const r = score(
      { usine: 'Usine A' },
      { type: 'qualite' },
      statsFor('u1', { maintenance: 10 }, {}, {}, {}),
    );
    expect(r.score).toBe(30); // only same-factory bonus
  });
});

// ─── resolution speed bonus ──────────────────────────────────────────────────

describe('resolution speed bonus', () => {
  test('avgRes 10 min → speed bonus 25 (capped)', () => {
    const r = score(
      { usine: 'Usine A' },
      {},
      statsFor('u1', { qualite: 1 }, { qualite: 10 }, {}, {}),
    );
    // 30 + 4 + 25 = 59
    expect(r.score).toBe(59);
  });

  test('avgRes 45 min → speed bonus max(0, 60-45)=15', () => {
    const r = score(
      { usine: 'Usine A' },
      {},
      statsFor('u1', { qualite: 1 }, { qualite: 45 }, {}, {}),
    );
    // 30 + 4 + 15 = 49
    expect(r.score).toBe(49);
  });

  test('avgRes 65 min → speed bonus 0 (clamped to 0)', () => {
    const r = score(
      { usine: 'Usine A' },
      {},
      statsFor('u1', { qualite: 1 }, { qualite: 65 }, {}, {}),
    );
    // 30 + 4 + 0 = 34
    expect(r.score).toBe(34);
  });

  test('no avgRes recorded → no speed bonus', () => {
    const r = score(
      { usine: 'Usine A' },
      {},
      statsFor('u1', { qualite: 3 }, {}, {}, {}),
    );
    expect(r.score).toBe(42); // 30 + 12 only
  });
});

// ─── workstation / conveyor familiarity ──────────────────────────────────────

describe('workstation and conveyor familiarity', () => {
  test('1 station fix → +6', () => {
    const stKey = 'Usine A|1|1';
    const r = score(
      { usine: 'Usine A' },
      {},
      statsFor('u1', {}, {}, { [stKey]: 1 }, {}),
    );
    // 30 + 6 = 36
    expect(r.score).toBe(36);
  });

  test('station bonus caps at 30 (5+ fixes)', () => {
    const stKey = 'Usine A|1|1';
    const r = score(
      { usine: 'Usine A' },
      {},
      statsFor('u1', {}, {}, { [stKey]: 10 }, {}),
    );
    // 30 + 30 (cap) = 60
    expect(r.score).toBe(60);
  });

  test('3 conveyor fixes → +floor(3×1.5)=4 (rounded in final score)', () => {
    const cvKey = 'Usine A|1';
    const r = score(
      { usine: 'Usine A' },
      {},
      statsFor('u1', {}, {}, {}, { [cvKey]: 3 }),
    );
    // 30 + floor(4.5) → Math.round(30 + 4.5) = 35? Let's check:
    // score accumulates: 30 + 4.5 = 34.5 → Math.round = 35? Actually Math.round(34.5)=35 in JS.
    // But the code uses Math.round only at the final return. 30 + 4.5 → Math.round(34.5) = 35.
    // Actually let me re-check: 3 × 1.5 = 4.5 → min(4.5, 15) = 4.5
    // score = 30 + 4.5 = 34.5 → Math.max(0, Math.round(34.5)) = 35
    expect(r.score).toBe(35);
  });

  test('station from different location does not contribute', () => {
    const r = score(
      { usine: 'Usine A' },
      { usine: 'Usine A', convoyeur: 1, poste: 1 },
      statsFor('u1', {}, {}, { 'Usine A|2|9': 5 }, {}),
    );
    // 30 only (wrong station key)
    expect(r.score).toBe(30);
  });
});

// ─── load-balancing penalty ──────────────────────────────────────────────────

describe('load balancing penalty', () => {
  test('0 recent assignments → no penalty', () => {
    const r = score({ usine: 'Usine A' }, {}, null, null, 0);
    expect(r.score).toBe(30);
  });

  test('2 recent assignments → −16 penalty on non-critical', () => {
    const r = score({ usine: 'Usine A' }, { isCritical: false }, null, null, 2);
    // 30 - 16 = 14
    expect(r.score).toBe(14);
  });

  test('load penalty is NOT applied on critical alerts', () => {
    const noLoad = score({ usine: 'Usine A' }, { isCritical: true }, null, null, 0).score;
    const withLoad = score({ usine: 'Usine A' }, { isCritical: true }, null, null, 2).score;
    expect(withLoad).toBe(noLoad);
  });
});

// ─── feedback adjustment ─────────────────────────────────────────────────────

describe('feedback adjustment', () => {
  test('positive feedback adds up to +20 cap', () => {
    const r = scoreSupervisor(
      { uid: 'u1', usine: 'Usine A' },
      baseAlert,
      {},
      { u1: { acceptedAssignments: 100, resolvedOutcomes: 100, rejectedAssignments: 0, abortedAssignments: 0 } },
      0,
      NOW,
    );
    // cap at +20 → 30 + 20 = 50
    expect(r.score).toBe(50);
    expect(r.reasons.some((x) => x.includes('+20'))).toBe(true);
  });

  test('negative feedback reduces up to −20 cap', () => {
    const r = scoreSupervisor(
      { uid: 'u1', usine: 'Usine A' },
      baseAlert,
      {},
      { u1: { acceptedAssignments: 0, resolvedOutcomes: 0, rejectedAssignments: 100, abortedAssignments: 100 } },
      0,
      NOW,
    );
    // cap at −20 → 30 - 20 = 10
    expect(r.score).toBe(10);
  });

  test('no feedback record → zero adjustment', () => {
    const r = score({ usine: 'Usine A' }, {}, null, {});
    expect(r.score).toBe(30);
    expect(r.reasons.some((x) => x.includes('Feedback'))).toBe(false);
  });
});

// ─── score floor ─────────────────────────────────────────────────────────────

describe('score floor', () => {
  test('score is never negative even with heavy penalties', () => {
    const r = scoreSupervisor(
      { uid: 'u1', usine: 'Usine X' },
      baseAlert,
      {},
      { u1: { acceptedAssignments: 0, resolvedOutcomes: 0, rejectedAssignments: 999, abortedAssignments: 999 } },
      99,
      NOW,
    );
    expect(r.score).toBeGreaterThanOrEqual(0);
  });
});

// ─── full known I/O fixture ──────────────────────────────────────────────────

describe('full fixture: known input → known output', () => {
  // Inputs:
  //   same factory (+30)
  //   typeCount=3 (+12), typeAvgRes=10 (+25)
  //   stationCount=2 (+12), conveyorCount=3 (+4.5)
  //   recentLoad=2, isCritical=false (−16)
  //   feedback: accepted=5, resolved=5, rejected=0, aborted=0
  //     → raw = 5*2 + 5*3 = 25, capped to +20
  // Total = 30+12+25+12+4.5-16+20 = 87.5 → Math.round(87.5) = 88
  test('complete input set produces score 88', () => {
    const stKey = 'Usine A|1|1';
    const cvKey = 'Usine A|1';
    const stats = {
      u1: {
        typeCounts: { qualite: 3 },
        typeAvgRes: { qualite: 10 },
        stationCounts: { [stKey]: 2 },
        conveyorCounts: { [cvKey]: 3 },
      },
    };
    const fb = { u1: { acceptedAssignments: 5, resolvedOutcomes: 5, rejectedAssignments: 0, abortedAssignments: 0 } };
    const r = scoreSupervisor(
      { uid: 'u1', usine: 'Usine A' },
      baseAlert,
      stats,
      fb,
      2,
      NOW,
    );
    expect(r.score).toBe(88);
  });

  // Same as above but commander mode + cross-factory: penalty removed.
  // Total = 0+12+25+12+4.5-16+20 = 57.5 → Math.round = 58
  test('commander mode cross-factory fixture produces score 58', () => {
    const stKey = 'Usine A|1|1';
    const cvKey = 'Usine A|1';
    const stats = {
      u1: {
        typeCounts: { qualite: 3 },
        typeAvgRes: { qualite: 10 },
        stationCounts: { [stKey]: 2 },
        conveyorCounts: { [cvKey]: 3 },
      },
    };
    const fb = { u1: { acceptedAssignments: 5, resolvedOutcomes: 5, rejectedAssignments: 0, abortedAssignments: 0 } };
    const r = scoreSupervisor(
      { uid: 'u1', usine: 'Usine B' }, // cross-factory
      baseAlert,
      stats,
      fb,
      2,
      NOW,
      { isCommander: true },
    );
    expect(r.score).toBe(58);
  });
});

// ─── buildSupStats integration ────────────────────────────────────────────────

describe('buildSupStats + scoreSupervisor pipeline', () => {
  test('stats built from alert history are used correctly in scoring', () => {
    const alertsMap = {
      a1: { status: 'validee', superviseurId: 'u1', type: 'qualite', elapsedTime: 10, usine: 'Usine A', convoyeur: 1, poste: 1 },
      a2: { status: 'validee', superviseurId: 'u1', type: 'qualite', elapsedTime: 30, usine: 'Usine A', convoyeur: 1, poste: 1 },
    };
    const stats = buildSupStats(alertsMap);
    // typeCount=2, avgRes=20
    const r = scoreSupervisor(
      { uid: 'u1', usine: 'Usine A' },
      baseAlert,
      stats,
      {},
      0,
      NOW,
    );
    // 30 + min(2*4,40) + min(max(0,60-20),25) + min(2*6,30) + min(2*1.5,15)
    // = 30 + 8 + 25 + 12 + 3 = 78
    expect(r.score).toBe(78);
  });
});
