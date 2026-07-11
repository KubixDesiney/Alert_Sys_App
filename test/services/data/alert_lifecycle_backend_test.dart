import 'package:alertsysapp/models/alert_model.dart';
import 'package:alertsysapp/services/ai_service.dart';
import 'package:alertsysapp/services/alert_actions_service.dart';
import 'package:alertsysapp/services/alert_service.dart';
import 'package:alertsysapp/services/app_logger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'fake_data_store.dart';

class _MockAlertService extends Mock implements AlertService {}

class _MockAIService extends Mock implements AIService {}

/// The core lifecycle (claim / resolve / suspend / critical / comment) runs
/// through AlertActionsService against BOTH backends:
///  * firebase-shaped store  -> Firebase-only side effects still fire
///    (admin suspend notification), preserving cloud behaviour;
///  * pocketbase-shaped store -> the lifecycle works end-to-end with ZERO
///    calls into AlertService (i.e. zero Firebase reads/writes).
void main() {
  late _MockAlertService alertService;
  late FakeDataStore store;
  late AlertActionsService service;

  AlertModel buildAlert({
    String id = 'a1',
    String status = 'disponible',
    String? supervisorId,
    String? supervisorName,
  }) {
    return AlertModel(
      id: id,
      type: 'maintenance',
      usine: 'Usine A',
      convoyeur: 1,
      poste: 2,
      adresse: 'Usine_A_C1_P2',
      timestamp: DateTime(2026, 1, 1, 10),
      description: 'Needs service',
      status: status,
      superviseurId: supervisorId,
      superviseurName: supervisorName,
      takenAtTimestamp:
          status == 'en_cours' ? DateTime(2026, 1, 1, 10) : null,
      comments: const [],
    );
  }

  group('pocketbase backend', () {
    setUp(() {
      alertService = _MockAlertService();
      store = FakeDataStore(backendName: 'pocketbase', seed: [buildAlert()]);
      service = AlertActionsService(
        alertService: alertService,
        aiService: _MockAIService(),
        logger: const AppLogger(),
        dataStore: store,
      );
    });

    test('claim -> resolve lifecycle runs without touching AlertService',
        () async {
      await service.takeAlert(
        alerts: store.alerts,
        alertId: 'a1',
        superviseurId: 'sup1',
        superviseurName: 'Sam',
        updateLocal: (_, __) {},
      );
      expect(store.alerts.single.status, 'en_cours');
      expect(store.alerts.single.superviseurId, 'sup1');

      await service.resolveAlert(
        alerts: store.alerts,
        alertId: 'a1',
        reason: 'belt re-tensioned',
        updateLocal: (_, __) {},
      );
      expect(store.alerts.single.status, 'validee');
      expect(store.alerts.single.resolutionReason, 'belt re-tensioned');

      // Audit trail captured by the store (goes to PocketBase audit_logs).
      expect(
        store.auditRecords.map((r) => r['action']),
        containsAll(['alert.claim', 'alert.resolve']),
      );
      verifyZeroInteractions(alertService);
    });

    test('suspend returns the alert to queue without the Firebase admin '
        'notification path', () async {
      store.serverPush([
        buildAlert(status: 'en_cours', supervisorId: 'sup1', supervisorName: 'Sam'),
      ]);

      await service.returnToQueue(
        alerts: store.alerts,
        alertId: 'a1',
        reason: 'shift over',
        updateLocal: (_, __) {},
      );

      expect(store.alerts.single.status, 'disponible');
      expect(store.alerts.single.superviseurId, isNull);
      expect(store.calls, contains('returnAlertToQueue(a1, shift over)'));
      // notifyAdminsAboutSuspend is Firebase-only: never called here.
      verifyZeroInteractions(alertService);
    });

    test('critical toggle with note persists both fields', () async {
      await service.toggleCritical(
        alertId: 'a1',
        isCritical: true,
        note: 'oil on floor',
        updateLocal: (_, __) {},
      );
      expect(store.alerts.single.isCritical, isTrue);
      expect(store.alerts.single.criticalNote, 'oil on floor');
      verifyZeroInteractions(alertService);
    });

    test('comments append through the store', () async {
      await service.addComment(
        alerts: store.alerts,
        alertId: 'a1',
        comment: 'Checked motor',
        currentSuperviseurName: 'Sam',
        updateLocal: (_, __) {},
      );
      expect(store.alerts.single.comments.single, contains('Sam: Checked motor'));
      verifyZeroInteractions(alertService);
    });
  });

  group('firebase backend keeps its side effects', () {
    setUp(() {
      alertService = _MockAlertService();
      store = FakeDataStore(backendName: 'firebase', seed: [
        buildAlert(status: 'en_cours', supervisorId: 'sup1', supervisorName: 'Sam'),
      ]);
      service = AlertActionsService(
        alertService: alertService,
        aiService: _MockAIService(),
        logger: const AppLogger(),
        dataStore: store,
      );
    });

    test('suspend still notifies admins on the firebase backend', () async {
      when(() => alertService.notifyAdminsAboutSuspend('a1', 'Sam', 'why'))
          .thenAnswer((_) async {});

      await service.returnToQueue(
        alerts: store.alerts,
        alertId: 'a1',
        reason: 'why',
        updateLocal: (_, __) {},
      );

      verify(() => alertService.notifyAdminsAboutSuspend('a1', 'Sam', 'why'))
          .called(1);
    });
  });
}
