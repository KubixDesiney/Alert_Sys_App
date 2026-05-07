import 'package:alertsysapp/models/alert_model.dart';
import 'package:alertsysapp/models/user_model.dart';
import 'package:alertsysapp/services/ai/ai_scoring_engine.dart';
import 'package:alertsysapp/services/ai_assignment_service.dart' show AICandidate;
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AIScoringEngine engine;
  late UserModel supervisor;
  late AlertModel alert;
  late DateTime now;

  setUp(() {
    engine = const AIScoringEngine(cooldownDuration: Duration(minutes: 5));
    now = DateTime(2026, 5, 7, 14, 0, 0);
    supervisor = UserModel(
      id: 'sup-1',
      firstName: 'Alice',
      lastName: 'Smith',
      email: 'alice@example.com',
      phone: '+1234567890',
      role: 'supervisor',
      usine: 'Usine A',
      status: 'active',
    );
    alert = AlertModel(
      id: 'alert-1',
      alertNumber: 1001,
      type: 'critical_stop',
      usine: 'Usine A',
      convoyeur: 1,
      poste: 1,
      adresse: 'Station A',
      description: 'Test alert',
      status: 'disponible',
      isCritical: false,
      timestamp: DateTime(2026, 5, 7, 13, 55, 0),
    );
  });

  group('AIScoringEngine.evaluate', () {
    test('disqualifies supervisor who opted out', () {
      final inputs = AIScoringInputs(
        supervisor: supervisor,
        aiOptOut: true,
      );
      final candidate = engine.evaluate(
        alert: alert,
        candidate: inputs,
        allAlerts: [alert],
        now: now,
      );

      expect(candidate.score, 0);
      expect(candidate.skipReason, 'Opted out of AI auto-assignment');
      expect(candidate.reasons, isEmpty);
    });

    test('disqualifies supervisor who is not active', () {
      final inactiveSup = UserModel(
        id: 'sup-1',
        firstName: 'Alice',
        lastName: 'Smith',
        email: 'alice@example.com',
        phone: '+1234567890',
        role: 'supervisor',
        usine: 'Usine A',
        status: 'inactive',
      );
      final inputs = AIScoringInputs(
        supervisor: inactiveSup,
        aiOptOut: false,
      );
      final candidate = engine.evaluate(
        alert: alert,
        candidate: inputs,
        allAlerts: [alert],
        now: now,
      );

      expect(candidate.score, 0);
      expect(candidate.skipReason, 'Not currently active');
    });

    test('disqualifies supervisor with active alert', () {
      final activeAlert = AlertModel(
        id: 'active-1',
        alertNumber: 1002,
        type: 'quality_issue',
        usine: 'Usine A',
        convoyeur: 2,
        poste: 2,
        adresse: 'Station B',
        description: 'Test alert',
        status: 'en_cours',
        superviseurId: 'sup-1',
        isCritical: false,
        timestamp: DateTime(2026, 5, 7, 14, 0, 0),
      );
      final inputs = AIScoringInputs(
        supervisor: supervisor,
        aiOptOut: false,
      );
      final candidate = engine.evaluate(
        alert: alert,
        candidate: inputs,
        allAlerts: [alert, activeAlert],
        now: now,
      );

      expect(candidate.score, 0);
      expect(candidate.skipReason, 'Already has an active alert');
    });

    test('disqualifies supervisor in cooldown for non-critical alert', () {
      final cooldownStart = now.subtract(Duration(minutes: 3));
      final inputs = AIScoringInputs(
        supervisor: supervisor,
        aiOptOut: false,
        cooldownStart: cooldownStart,
      );
      final candidate = engine.evaluate(
        alert: alert,
        candidate: inputs,
        allAlerts: [alert],
        now: now,
      );

      expect(candidate.score, 0);
      expect(candidate.skipReason, contains('In cooldown'));
      expect(candidate.skipReason, contains('2m'));
    });

    test('allows supervisor in cooldown for critical alert', () {
      final criticalAlert = AlertModel(
        id: 'alert-1',
        alertNumber: 1001,
        type: 'critical_stop',
        usine: 'Usine A',
        convoyeur: 1,
        poste: 1,
        adresse: 'Station A',
        description: 'Test alert',
        status: 'disponible',
        isCritical: true,
        timestamp: DateTime(2026, 5, 7, 13, 55, 0),
      );
      final cooldownStart = now.subtract(Duration(minutes: 3));
      final inputs = AIScoringInputs(
        supervisor: supervisor,
        aiOptOut: false,
        cooldownStart: cooldownStart,
      );
      final candidate = engine.evaluate(
        alert: criticalAlert,
        candidate: inputs,
        allAlerts: [criticalAlert],
        now: now,
      );

      expect(candidate.skipReason, isNull);
      expect(candidate.score, greaterThan(0));
    });

    test('scores same factory bonus', () {
      final inputs = AIScoringInputs(
        supervisor: supervisor,
        aiOptOut: false,
      );
      final candidate = engine.evaluate(
        alert: alert,
        candidate: inputs,
        allAlerts: [alert],
        now: now,
      );

      expect(candidate.reasons, contains('Same factory (+30)'));
      expect(candidate.score, greaterThanOrEqualTo(30));
    });

    test('scores different factory penalty', () {
      final diffFactorySup = UserModel(
        id: 'sup-1',
        firstName: 'Bob',
        lastName: 'Jones',
        email: 'bob@example.com',
        phone: '+1234567890',
        role: 'supervisor',
        usine: 'Usine B',
        status: 'active',
      );
      final inputs = AIScoringInputs(
        supervisor: diffFactorySup,
        aiOptOut: false,
      );
      final candidate = engine.evaluate(
        alert: alert,
        candidate: inputs,
        allAlerts: [alert],
        now: now,
      );

      expect(candidate.reasons, contains('Different factory (−25)'));
      expect(candidate.score, equals(0.0));
    });

    test('scores type experience bonus', () {
      final resolvedAlert = AlertModel(
        id: 'resolved-1',
        alertNumber: 999,
        type: 'critical_stop',
        usine: 'Usine A',
        convoyeur: 1,
        poste: 1,
        adresse: 'Station A',
        description: 'Test alert',
        status: 'validee',
        superviseurId: 'sup-1',
        isCritical: false,
        timestamp: DateTime(2026, 5, 6, 10, 0, 0),
        resolvedAt: DateTime(2026, 5, 6, 10, 30, 0),
      );
      final inputs = AIScoringInputs(
        supervisor: supervisor,
        aiOptOut: false,
      );
      final candidate = engine.evaluate(
        alert: alert,
        candidate: inputs,
        allAlerts: [alert, resolvedAlert],
        now: now,
      );

      expect(candidate.reasons, contains(contains('past critical_stop alert')));
      expect(candidate.reasons, contains(contains('(+4)')));
    });

    test('scores resolution speed bonus', () {
      final fastResolveAlert = AlertModel(
        id: 'resolved-1',
        alertNumber: 999,
        type: 'critical_stop',
        usine: 'Usine A',
        convoyeur: 1,
        poste: 1,
        adresse: 'Station A',
        description: 'Test alert',
        status: 'validee',
        superviseurId: 'sup-1',
        isCritical: false,
        timestamp: DateTime(2026, 5, 6, 10, 0, 0),
        resolvedAt: DateTime(2026, 5, 6, 10, 20, 0),
        elapsedTime: 20,
      );
      final inputs = AIScoringInputs(
        supervisor: supervisor,
        aiOptOut: false,
      );
      final candidate = engine.evaluate(
        alert: alert,
        candidate: inputs,
        allAlerts: [alert, fastResolveAlert],
        now: now,
      );

      expect(candidate.reasons, contains(contains('Avg resolution')));
      expect(candidate.reasons, contains(contains('+25')));
    });

    test('scores workstation familiarity', () {
      final stationAlert = AlertModel(
        id: 'resolved-1',
        alertNumber: 999,
        type: 'quality_issue',
        usine: 'Usine A',
        convoyeur: 1,
        poste: 1,
        adresse: 'Station A',
        description: 'Test alert',
        status: 'validee',
        superviseurId: 'sup-1',
        isCritical: false,
        timestamp: DateTime(2026, 5, 6, 10, 0, 0),
        resolvedAt: DateTime(2026, 5, 6, 10, 30, 0),
      );
      final inputs = AIScoringInputs(
        supervisor: supervisor,
        aiOptOut: false,
      );
      final candidate = engine.evaluate(
        alert: alert,
        candidate: inputs,
        allAlerts: [alert, stationAlert],
        now: now,
      );

      expect(candidate.reasons, contains(contains('fix')));
      expect(candidate.reasons, contains(contains('this workstation')));
    });

    test('scores conveyor line experience', () {
      final conveyorAlert = AlertModel(
        id: 'resolved-1',
        alertNumber: 999,
        type: 'quality_issue',
        usine: 'Usine A',
        convoyeur: 1,
        poste: 3,
        adresse: 'Station C',
        description: 'Test alert',
        status: 'validee',
        superviseurId: 'sup-1',
        isCritical: false,
        timestamp: DateTime(2026, 5, 6, 10, 0, 0),
        resolvedAt: DateTime(2026, 5, 6, 10, 30, 0),
      );
      final inputs = AIScoringInputs(
        supervisor: supervisor,
        aiOptOut: false,
      );
      final candidate = engine.evaluate(
        alert: alert,
        candidate: inputs,
        allAlerts: [alert, conveyorAlert],
        now: now,
      );

      expect(candidate.reasons, contains(contains('Line 1')));
    });

    test('penalizes recent workload for non-critical alerts', () {
      // Create an alert that supervisor took recently (within 10 minutes)
      // Status must NOT be 'en_cours' or supervisor will be disqualified for having active alert
      final recentAlert = AlertModel(
        id: 'recent-1',
        alertNumber: 998,
        type: 'quality_issue',
        usine: 'Usine A',
        convoyeur: 2,
        poste: 4,
        adresse: 'Station D',
        description: 'Recent alert',
        status: 'validee',
        superviseurId: 'sup-1',
        superviseurName: 'Alice',
        takenAtTimestamp: now.subtract(Duration(minutes: 5)),
        isCritical: false,
        timestamp: DateTime(2026, 5, 7, 13, 55, 0),
      );
      final inputs = AIScoringInputs(
        supervisor: supervisor,
        aiOptOut: false,
      );
      final candidate = engine.evaluate(
        alert: alert,
        candidate: inputs,
        allAlerts: [alert, recentAlert],
        now: now,
      );

      expect(candidate.skipReason, isNull);
      expect(candidate.reasons.length, greaterThan(0));
      expect(
        candidate.reasons.any((r) => r.contains('Recent load')),
        isTrue,
      );
    });

    test('scores critical alert resolution history', () {
      final resolvedCritical = AlertModel(
        id: 'resolved-1',
        alertNumber: 997,
        type: 'system_failure',
        usine: 'Usine A',
        convoyeur: 3,
        poste: 5,
        adresse: 'Station E',
        description: 'Test alert',
        status: 'validee',
        superviseurId: 'sup-1',
        isCritical: true,
        timestamp: DateTime(2026, 5, 6, 10, 0, 0),
        resolvedAt: DateTime(2026, 5, 6, 10, 30, 0),
      );
      final criticalAlert = AlertModel(
        id: 'alert-1',
        alertNumber: 1001,
        type: 'critical_stop',
        usine: 'Usine A',
        convoyeur: 1,
        poste: 1,
        adresse: 'Station A',
        description: 'Test alert',
        status: 'disponible',
        isCritical: true,
        timestamp: DateTime(2026, 5, 7, 13, 55, 0),
      );
      final inputs = AIScoringInputs(
        supervisor: supervisor,
        aiOptOut: false,
      );
      final candidate = engine.evaluate(
        alert: criticalAlert,
        candidate: inputs,
        allAlerts: [criticalAlert, resolvedCritical],
        now: now,
      );

      expect(candidate.reasons, contains(contains('critical alert')));
      expect(candidate.reasons, contains(contains('+5')));
    });

    test('applies feedback rank adjustment', () {
      final inputs = AIScoringInputs(
        supervisor: supervisor,
        aiOptOut: false,
        feedbackRankAdjustment: 10.0,
      );
      final candidate = engine.evaluate(
        alert: alert,
        candidate: inputs,
        allAlerts: [alert],
        now: now,
      );

      expect(candidate.reasons, contains(contains('Feedback adjustment')));
      expect(candidate.reasons, contains(contains('+10')));
    });

    test('clamps score to 0-1000 range', () {
      // Create many resolved alerts to accumulate high score
      final resolvedAlerts = List.generate(20, (i) {
        return AlertModel(
          id: 'resolved-$i',
          alertNumber: 900 + i,
          type: 'critical_stop',
          usine: 'Usine A',
          convoyeur: 1,
          poste: 1,
          adresse: 'Station A',
          description: 'Test alert',
          status: 'validee',
          superviseurId: 'sup-1',
          isCritical: false,
          timestamp: DateTime(2026, 5, 6, 10 + i ~/ 4, i * 15 % 60, 0),
          resolvedAt:
              DateTime(2026, 5, 6, 10 + i ~/ 4, (i * 15 + 30) % 60, 0),
          elapsedTime: 30,
        );
      });
      final allAlerts = [alert, ...resolvedAlerts];
      final inputs = AIScoringInputs(
        supervisor: supervisor,
        aiOptOut: false,
      );
      final candidate = engine.evaluate(
        alert: alert,
        candidate: inputs,
        allAlerts: allAlerts,
        now: now,
      );

      expect(candidate.score, lessThanOrEqualTo(1000));
    });

    test('returns eligible candidate when all checks pass', () {
      final inputs = AIScoringInputs(
        supervisor: supervisor,
        aiOptOut: false,
      );
      final candidate = engine.evaluate(
        alert: alert,
        candidate: inputs,
        allAlerts: [alert],
        now: now,
      );

      expect(candidate.supervisor, supervisor);
      expect(candidate.skipReason, isNull);
      expect(candidate.score, greaterThan(0));
      expect(candidate.reasons, isNotEmpty);
    });

    test('respects explicit clock parameter for deterministic testing', () {
      final futureTime = now.add(Duration(days: 1));
      final cooldownStart = now;
      final inputs = AIScoringInputs(
        supervisor: supervisor,
        aiOptOut: false,
        cooldownStart: cooldownStart,
      );
      final candidate = engine.evaluate(
        alert: alert,
        candidate: inputs,
        allAlerts: [alert],
        now: futureTime,
      );

      expect(candidate.skipReason, isNull);
    });
  });
}
