import 'package:alertsysapp/models/alert_model.dart';
import 'package:alertsysapp/services/alert_service.dart';
import 'package:alertsysapp/services/audit_service.dart';
import 'package:alertsysapp/services/data/data_store.dart';
import 'package:alertsysapp/services/data/firebase_data_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockAlertService extends Mock implements AlertService {}

class _MockAuditService extends Mock implements AuditService {}

/// SIAS_BACKEND=firebase parity guarantee: every DataStore call must be a pure
/// delegation to the existing AlertService/AuditService methods with the same
/// arguments — so routing the app through DataStore changes nothing on cloud.
void main() {
  late _MockAlertService alerts;
  late _MockAuditService audit;
  late FirebaseDataStore store;

  setUpAll(() {
    registerFallbackValue(DateTime(2026));
  });

  setUp(() {
    alerts = _MockAlertService();
    audit = _MockAuditService();
    store = FirebaseDataStore(alertService: alerts, auditService: audit);
  });

  final sample = AlertModel(
    id: 'a1',
    type: 'maintenance',
    usine: 'Usine A',
    convoyeur: 1,
    poste: 2,
    adresse: 'Usine_A_C1_P2',
    timestamp: DateTime(2026, 1, 1),
    description: 'test',
  );

  test('is a DataStore and reports firebase', () {
    expect(store, isA<DataStore>());
    expect(store.backendName, 'firebase');
  });

  test('watchAllAlerts delegates to getAllAlerts with the limit', () {
    when(() => alerts.getAllAlerts(limit: 50))
        .thenAnswer((_) => Stream.value([sample]));
    expect(store.watchAllAlerts(limit: 50), emits([sample]));
    verify(() => alerts.getAllAlerts(limit: 50)).called(1);
  });

  test('watchAlertsForUsine delegates to getAlertsForUsine', () {
    when(() => alerts.getAlertsForUsine('Usine A', limit: 10))
        .thenAnswer((_) => Stream.value([sample]));
    expect(store.watchAlertsForUsine('Usine A', limit: 10), emits([sample]));
  });

  test('watchAlertsForSupervisor delegates to getAlertsWhereSupervisor', () {
    when(() => alerts.getAlertsWhereSupervisor('sup1', limit: null))
        .thenAnswer((_) => Stream.value([sample]));
    expect(store.watchAlertsForSupervisor('sup1'), emits([sample]));
  });

  test('fetchOlderAlerts without usine uses the global pager', () async {
    final before = DateTime(2026, 2, 2);
    when(() => alerts.fetchOlderAlerts(before: before, limit: 25))
        .thenAnswer((_) async => [sample]);
    expect(await store.fetchOlderAlerts(before: before, limit: 25), [sample]);
  });

  test('fetchOlderAlerts with usine uses the factory pager', () async {
    final before = DateTime(2026, 2, 2);
    when(() => alerts.fetchOlderAlertsForUsine(
        usine: 'Usine A', before: before, limit: 25))
        .thenAnswer((_) async => [sample]);
    expect(
      await store.fetchOlderAlerts(usine: 'Usine A', before: before, limit: 25),
      [sample],
    );
  });

  test('createAlert delegates to createAlertWithHierarchy', () async {
    when(() => alerts.createAlertWithHierarchy(
          type: 'maintenance',
          usine: 'Usine A',
          convoyeur: 1,
          poste: 2,
          description: 'belt noise',
          isCritical: true,
        )).thenAnswer((_) async => 'new-id');

    final id = await store.createAlert(
      type: 'maintenance',
      usine: 'Usine A',
      convoyeur: 1,
      poste: 2,
      description: 'belt noise',
      isCritical: true,
    );

    expect(id, 'new-id');
  });

  test('claimAlert delegates to takeAlert', () async {
    when(() => alerts.takeAlert('a1', 'sup1', 'Sam'))
        .thenAnswer((_) async {});
    await store.claimAlert('a1', 'sup1', 'Sam');
    verify(() => alerts.takeAlert('a1', 'sup1', 'Sam')).called(1);
  });

  test('resolveAlert delegates with assisting supervisor fields', () async {
    when(() => alerts.resolveAlert('a1', 'done', 15,
        assistingSupervisorId: 'sup2',
        assistingSupervisorName: 'Alex')).thenAnswer((_) async {});
    await store.resolveAlert('a1', 'done', 15,
        assistingSupervisorId: 'sup2', assistingSupervisorName: 'Alex');
    verify(() => alerts.resolveAlert('a1', 'done', 15,
        assistingSupervisorId: 'sup2', assistingSupervisorName: 'Alex'))
        .called(1);
  });

  test('returnAlertToQueue delegates with the suspend reason', () async {
    when(() => alerts.returnToQueue('a1', reason: 'shift end'))
        .thenAnswer((_) async {});
    await store.returnAlertToQueue('a1', reason: 'shift end');
    verify(() => alerts.returnToQueue('a1', reason: 'shift end')).called(1);
  });

  test('setCritical delegates toggle and writes the note only when given',
      () async {
    when(() => alerts.toggleCritical('a1', true)).thenAnswer((_) async {});
    when(() => alerts.setCriticalNote('a1', 'gas leak'))
        .thenAnswer((_) async {});

    await store.setCritical('a1', true, note: 'gas leak');
    verify(() => alerts.toggleCritical('a1', true)).called(1);
    verify(() => alerts.setCriticalNote('a1', 'gas leak')).called(1);

    when(() => alerts.toggleCritical('a1', false)).thenAnswer((_) async {});
    await store.setCritical('a1', false);
    verifyNever(() => alerts.setCriticalNote('a1', any()));
  });

  test('addComment delegates verbatim', () async {
    when(() => alerts.addComment('a1', 'hello')).thenAnswer((_) async {});
    await store.addComment('a1', 'hello');
    verify(() => alerts.addComment('a1', 'hello')).called(1);
  });

  test('writeAudit delegates to AuditService.log', () async {
    when(() => audit.log(
          action: any(named: 'action'),
          targetType: any(named: 'targetType'),
          targetId: any(named: 'targetId'),
          factoryId: any(named: 'factoryId'),
          detail: any(named: 'detail'),
        )).thenAnswer((_) async {});

    await store.writeAudit(
      action: 'alert.claim',
      targetType: 'alert',
      targetId: 'a1',
      factoryId: 'Usine A',
      detail: 'Claimed by Sam',
    );

    verify(() => audit.log(
          action: 'alert.claim',
          targetType: 'alert',
          targetId: 'a1',
          factoryId: 'Usine A',
          detail: 'Claimed by Sam',
        )).called(1);
  });
}
