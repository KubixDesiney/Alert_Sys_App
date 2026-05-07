/// Tests for:
///  1. ScoreAdjuster — basic arithmetic and bulk-load / clear
///  2. AIScoringEngine with a live ScoreAdjuster — positive/negative bias shifts
///  3. ScoreReinforcementService.computeReward — reward signal logic
library;

import 'package:alertsysapp/models/alert_model.dart';
import 'package:alertsysapp/models/user_model.dart';
import 'package:alertsysapp/services/ai/ai_scoring_engine.dart';
import 'package:alertsysapp/services/ai/score_adjuster.dart';
import 'package:alertsysapp/services/score_reinforcement_service.dart';
import 'package:flutter_test/flutter_test.dart';

// ─── helpers ────────────────────────────────────────────────────────────────

UserModel _sup({String id = 'u1', String usine = 'Usine A'}) => UserModel(
      id: id,
      firstName: 'Test',
      lastName: 'Sup',
      email: 'test@example.com',
      phone: '',
      role: 'supervisor',
      usine: usine,
      status: 'active',
    );

AlertModel _alert({
  String usine = 'Usine A',
  String type = 'qualite',
  bool isCritical = false,
}) =>
    AlertModel(
      id: 'a1',
      alertNumber: 1,
      type: type,
      usine: usine,
      convoyeur: 1,
      poste: 1,
      adresse: 'Station A',
      description: 'Test',
      status: 'disponible',
      isCritical: isCritical,
      timestamp: DateTime(2026, 5, 1, 9),
    );

void main() {
  // ── 1. ScoreAdjuster unit tests ─────────────────────────────────────────

  group('ScoreAdjuster', () {
    late ScoreAdjuster adjuster;

    setUp(() => adjuster = ScoreAdjuster());

    test('returns 0.0 for an unknown supervisor', () {
      expect(adjuster.adjustmentFor('nobody'), 0.0);
    });

    test('stores and retrieves an adjustment', () {
      adjuster.setAdjustment('u1', 5.0);
      expect(adjuster.adjustmentFor('u1'), 5.0);
    });

    test('overwrites an existing adjustment', () {
      adjuster.setAdjustment('u1', 3.0);
      adjuster.setAdjustment('u1', -2.5);
      expect(adjuster.adjustmentFor('u1'), -2.5);
    });

    test('loadAll replaces all existing entries', () {
      adjuster.setAdjustment('u1', 99.0);
      adjuster.loadAll({'u2': 1.0, 'u3': -1.0});
      expect(adjuster.adjustmentFor('u1'), 0.0); // cleared
      expect(adjuster.adjustmentFor('u2'), 1.0);
      expect(adjuster.adjustmentFor('u3'), -1.0);
    });

    test('clear removes all stored values', () {
      adjuster.setAdjustment('u1', 5.0);
      adjuster.setAdjustment('u2', 3.0);
      adjuster.clear();
      expect(adjuster.adjustmentFor('u1'), 0.0);
      expect(adjuster.adjustmentFor('u2'), 0.0);
      expect(adjuster.all, isEmpty);
    });

    test('all returns an unmodifiable view', () {
      adjuster.setAdjustment('u1', 1.0);
      expect(() => adjuster.all['u1'] = 999.0, throwsA(anything));
    });
  });

  // ── 2. AIScoringEngine with ScoreAdjuster ─────────────────────────────

  group('AIScoringEngine with ScoreAdjuster', () {
    final now = DateTime(2026, 5, 1, 9);

    test('no adjuster: baseline score is unaffected', () {
      const engine = AIScoringEngine();
      final result = engine.evaluate(
        alert: _alert(),
        candidate: AIScoringInputs(supervisor: _sup(), aiOptOut: false),
        allAlerts: [],
        now: now,
      );
      expect(result.score, 30.0); // same factory only → 30
      expect(result.reasons.any((r) => r.contains('learning bias')), isFalse);
    });

    test('positive adjustment shifts score up (clamped to +15% of base)', () {
      final adj = ScoreAdjuster()..setAdjustment('u1', 100.0); // far above cap
      final engine = AIScoringEngine(adjuster: adj);
      final result = engine.evaluate(
        alert: _alert(),
        candidate: AIScoringInputs(supervisor: _sup(), aiOptOut: false),
        allAlerts: [],
        now: now,
      );
      // base=30, maxAdj=30×0.15=4.5, total ≤34.5 → rounds to ≤35
      expect(result.score, greaterThan(30));
      expect(result.score, lessThanOrEqualTo(35));
      expect(result.reasons.any((r) => r.contains('AI learning bias')), isTrue);
    });

    test('negative adjustment shifts score down (clamped to -15% of base)', () {
      final adj = ScoreAdjuster()..setAdjustment('u1', -100.0);
      final engine = AIScoringEngine(adjuster: adj);
      final result = engine.evaluate(
        alert: _alert(),
        candidate: AIScoringInputs(supervisor: _sup(), aiOptOut: false),
        allAlerts: [],
        now: now,
      );
      // base=30, maxAdj=-4.5, total ≥25.5 → rounds to ≥26
      expect(result.score, lessThan(30));
      expect(result.score, greaterThanOrEqualTo(25));
    });

    test('over-cap and at-cap positive adjustments produce identical score', () {
      final adjOver = ScoreAdjuster()..setAdjustment('u1', 10.0);
      final adjAt = ScoreAdjuster()..setAdjustment('u1', 4.5);

      double run(ScoreAdjuster a) => AIScoringEngine(adjuster: a).evaluate(
            alert: _alert(),
            candidate: AIScoringInputs(supervisor: _sup(), aiOptOut: false),
            allAlerts: [],
            now: now,
          ).score;

      expect(run(adjOver), run(adjAt)); // both clamped to 4.5
    });

    test('adjuster has no effect when base score is 0', () {
      // Different factory → base after all factors = 0 after clamping.
      final adj = ScoreAdjuster()..setAdjustment('u1', 50.0);
      final engine = AIScoringEngine(adjuster: adj);
      final result = engine.evaluate(
        alert: _alert(usine: 'Usine A'),
        candidate: AIScoringInputs(
          supervisor: _sup(usine: 'Usine B'),
          aiOptOut: false,
        ),
        allAlerts: [],
        now: now,
      );
      // -25 before clamp → base=0 → maxAdj=0 → no bias
      expect(result.score, 0.0);
      expect(result.reasons.any((r) => r.contains('learning bias')), isFalse);
    });

    test('zero stored adjustment produces no bias reason entry', () {
      final adj = ScoreAdjuster(); // all zero
      final engine = AIScoringEngine(adjuster: adj);
      final result = engine.evaluate(
        alert: _alert(),
        candidate: AIScoringInputs(supervisor: _sup(), aiOptOut: false),
        allAlerts: [],
        now: now,
      );
      expect(result.reasons.any((r) => r.contains('learning bias')), isFalse);
    });

    test('final score never exceeds 1000 with large positive adjustment', () {
      final adj = ScoreAdjuster()..setAdjustment('u1', 999.0);
      final engine = AIScoringEngine(adjuster: adj);
      final history = List.generate(
        20,
        (i) => AlertModel(
          id: 'h$i',
          alertNumber: i,
          type: 'qualite',
          usine: 'Usine A',
          convoyeur: 1,
          poste: 1,
          adresse: '',
          description: '',
          status: 'validee',
          isCritical: false,
          superviseurId: 'u1',
          elapsedTime: 5,
          timestamp: DateTime(2026, 1, i + 1),
        ),
      );
      final result = engine.evaluate(
        alert: _alert(),
        candidate: AIScoringInputs(supervisor: _sup(), aiOptOut: false),
        allAlerts: history,
        now: now,
      );
      expect(result.score, lessThanOrEqualTo(1000));
    });
  });

  // ── 3. ScoreReinforcementService.computeReward ────────────────────────

  group('ScoreReinforcementService.computeReward', () {
    // Tests only the pure reward-calculation method — no Firebase involved.
    late ScoreReinforcementService service;

    setUp(() {
      service = ScoreReinforcementService(
        adjuster: ScoreAdjuster(),
      );
    });

    tearDown(() => service.dispose());

    test('returns 0 for a non-resolved alert', () {
      expect(
        service.computeReward({'status': 'disponible', 'superviseurId': 'u1'}),
        0.0,
      );
      expect(
        service.computeReward({'status': 'en_cours', 'superviseurId': 'u1'}),
        0.0,
      );
    });

    test('AI-assigned resolved alert gives +0.2', () {
      expect(
        service.computeReward({
          'status': 'validee',
          'superviseurId': 'u1',
          'aiAssigned': true,
        }),
        closeTo(0.2, 0.001),
      );
    });

    test('rejected assignment gives -1.0', () {
      expect(
        service.computeReward({
          'status': 'validee',
          'superviseurId': 'u1',
          'aiRejected': true,
        }),
        closeTo(-1.0, 0.001),
      );
    });

    test('AI-assigned AND rejected: net = -0.8', () {
      expect(
        service.computeReward({
          'status': 'validee',
          'superviseurId': 'u1',
          'aiAssigned': true,
          'aiRejected': true,
        }),
        closeTo(-0.8, 0.001),
      );
    });

    test('resolved faster than ETA gives +0.5', () {
      final taken = DateTime(2026, 5, 1, 9, 0);
      final resolved = DateTime(2026, 5, 1, 9, 30); // 0.5 h actual vs 2 h ETA
      expect(
        service.computeReward({
          'status': 'validee',
          'superviseurId': 'u1',
          'aiEtaHours': 2.0,
          'takenAtTimestamp': taken.toIso8601String(),
          'resolvedAt': resolved.toIso8601String(),
        }),
        closeTo(0.5, 0.001),
      );
    });

    test('resolved slower than ETA gives -0.5', () {
      final taken = DateTime(2026, 5, 1, 9, 0);
      final resolved = DateTime(2026, 5, 1, 12, 0); // 3 h actual vs 1 h ETA
      expect(
        service.computeReward({
          'status': 'validee',
          'superviseurId': 'u1',
          'aiEtaHours': 1.0,
          'takenAtTimestamp': taken.toIso8601String(),
          'resolvedAt': resolved.toIso8601String(),
        }),
        closeTo(-0.5, 0.001),
      );
    });

    test('AI-assigned + fast: combined reward = 0.7', () {
      final taken = DateTime(2026, 5, 1, 9, 0);
      final resolved = DateTime(2026, 5, 1, 9, 20); // ~0.33 h vs 2 h ETA
      expect(
        service.computeReward({
          'status': 'validee',
          'superviseurId': 'u1',
          'aiAssigned': true,
          'aiEtaHours': 2.0,
          'takenAtTimestamp': taken.toIso8601String(),
          'resolvedAt': resolved.toIso8601String(),
        }),
        closeTo(0.7, 0.001),
      );
    });

    test('no ETA field: only aiAssigned/rejection signals apply', () {
      expect(
        service.computeReward({
          'status': 'validee',
          'superviseurId': 'u1',
          'aiAssigned': true,
          // no aiEtaHours
        }),
        closeTo(0.2, 0.001),
      );
    });

    test('resolved alert with no signals returns 0', () {
      expect(
        service.computeReward({
          'status': 'validee',
          'superviseurId': 'u1',
          // no aiAssigned, no aiRejected, no ETA
        }),
        0.0,
      );
    });
  });
}
