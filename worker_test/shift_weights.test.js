import { describe, test, expect } from '@jest/globals';
import {
  buildSupStats,
  scoreSupervisor,
  _shiftAssignmentWeights,
} from '../cloudflare_ai_worker.js';

const NOW = Date.UTC(2026, 5, 1, 9, 0, 0);

const sup = { uid: 'u1', usine: 'Usine A' };
const alert = (overrides = {}) => ({
  type: 'qualite',
  usine: 'Usine A',
  convoyeur: 1,
  poste: 1,
  ...overrides,
});

describe('_shiftAssignmentWeights', () => {
  test('returns null when no weights node is configured', () => {
    expect(_shiftAssignmentWeights(undefined)).toBeNull();
    expect(_shiftAssignmentWeights({})).toBeNull();
    expect(_shiftAssignmentWeights({ shift: { settings: {} } })).toBeNull();
  });

  test('maps stored 0..1 weights to userWeight/defaultWeight multipliers', () => {
    const control = {
      shift: { settings: { weights: { assignments: { factory: 0.95, type: 0.40 } } } },
    };
    const m = _shiftAssignmentWeights(control);
    expect(m).not.toBeNull();
    // factory at its default 0.95 -> multiplier 1.0 (unchanged)
    expect(m.factory).toBeCloseTo(1.0, 6);
    // type halved from its 0.80 default -> 0.5x
    expect(m.type).toBeCloseTo(0.5, 6);
    // untouched factors default to 1.0
    expect(m.load).toBe(1);
    expect(m.reinforcement).toBe(1);
  });

  test('clamps extreme multipliers to [0, 3]', () => {
    const control = {
      shift: { settings: { weights: { assignments: { critical: 1.0, factory: 0 } } } },
    };
    const m = _shiftAssignmentWeights(control);
    // critical default 0.50 -> 1/0.5 = 2x (within range)
    expect(m.critical).toBeCloseTo(2.0, 6);
    // factory dragged to zero -> 0x
    expect(m.factory).toBe(0);
  });
});

describe('scoreSupervisor with live weights', () => {
  test('identical score whether weights are absent or all at default', () => {
    const stats = buildSupStats({
      a1: { status: 'validee', superviseurId: 'u1', type: 'qualite', elapsedTime: 10, usine: 'Usine A', convoyeur: 1, poste: 1 },
    });
    const baseline = scoreSupervisor(sup, alert(), stats, {}, 0, NOW);
    const atDefault = scoreSupervisor(sup, alert(), stats, {}, 0, NOW, {
      weights: _shiftAssignmentWeights({
        shift: { settings: { weights: { assignments: { factory: 0.95, type: 0.80, speed: 0.62, station: 0.55, load: 0.70, critical: 0.50, reinforcement: 0.65 } } } },
      }),
    });
    expect(atDefault.score).toBe(baseline.score);
  });

  test('boosting the factory weight raises the same-factory contribution', () => {
    const stats = buildSupStats({});
    const baseline = scoreSupervisor(sup, alert(), stats, {}, 0, NOW);
    const boosted = scoreSupervisor(sup, alert(), stats, {}, 0, NOW, {
      weights: _shiftAssignmentWeights({
        shift: { settings: { weights: { assignments: { factory: 1.0 } } } },
      }),
    });
    // factory 0.95 -> 1.0 multiplies the +30 same-factory bonus up.
    expect(boosted.score).toBeGreaterThan(baseline.score);
    expect(boosted.reasons.join(' ')).toMatch(/Same factory/);
  });

  test('suppressing the load weight softens the recent-load penalty', () => {
    const stats = buildSupStats({});
    const a = alert({ isCritical: false });
    const baseline = scoreSupervisor(sup, a, stats, {}, 2, NOW); // recentAssignments=2
    const softened = scoreSupervisor(sup, a, stats, {}, 2, NOW, {
      weights: _shiftAssignmentWeights({
        shift: { settings: { weights: { assignments: { load: 0 } } } },
      }),
    });
    // Penalty removed -> higher score.
    expect(softened.score).toBeGreaterThan(baseline.score);
  });

  test('critical track record only fires for critical alerts when boosted above default', () => {
    const stats = buildSupStats({
      c1: { status: 'validee', superviseurId: 'u1', type: 'qualite', elapsedTime: 8, usine: 'Usine A', convoyeur: 1, poste: 1, isCritical: true },
      c2: { status: 'validee', superviseurId: 'u1', type: 'qualite', elapsedTime: 9, usine: 'Usine A', convoyeur: 1, poste: 1, isCritical: true },
    });
    expect(stats.u1.criticalCount).toBe(2);

    const critAlert = alert({ isCritical: true });
    // At default weight -> no critical boost (no-op).
    const atDefault = scoreSupervisor(sup, critAlert, stats, {}, 0, NOW, {
      weights: _shiftAssignmentWeights({ shift: { settings: { weights: { assignments: { critical: 0.50 } } } } }),
    });
    const noWeights = scoreSupervisor(sup, critAlert, stats, {}, 0, NOW);
    expect(atDefault.score).toBe(noWeights.score);

    // Boosted -> critical track record adds.
    const boosted = scoreSupervisor(sup, critAlert, stats, {}, 0, NOW, {
      weights: _shiftAssignmentWeights({ shift: { settings: { weights: { assignments: { critical: 1.0 } } } } }),
    });
    expect(boosted.score).toBeGreaterThan(noWeights.score);
    expect(boosted.reasons.join(' ')).toMatch(/Critical track record/);

    // Non-critical alert never triggers the critical boost.
    const boostedNonCritical = scoreSupervisor(sup, alert({ isCritical: false }), stats, {}, 0, NOW, {
      weights: _shiftAssignmentWeights({ shift: { settings: { weights: { assignments: { critical: 1.0 } } } } }),
    });
    expect(boostedNonCritical.reasons.join(' ')).not.toMatch(/Critical track record/);
  });
});
