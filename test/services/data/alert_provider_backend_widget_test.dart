import 'dart:async';

import 'package:alertsysapp/models/alert_model.dart';
import 'package:alertsysapp/providers/alert_provider.dart';
import 'package:alertsysapp/services/ai_service.dart';
import 'package:alertsysapp/services/alert_actions_service.dart';
import 'package:alertsysapp/services/alert_service.dart';
import 'package:alertsysapp/services/alert_stream_service.dart';
import 'package:alertsysapp/services/app_logger.dart';
import 'package:alertsysapp/services/data/firebase_data_store.dart';
import 'package:alertsysapp/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

import 'fake_data_store.dart';

class _MockAlertService extends Mock implements AlertService {}

class _MockAIService extends Mock implements AIService {}

AlertModel _alert(String id,
        {String status = 'disponible', String? supervisorId}) =>
    AlertModel(
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
      takenAtTimestamp: status == 'en_cours' ? DateTime(2026, 1, 1, 10) : null,
      comments: const [],
    );

/// Minimal dashboard: renders "id:status" per alert so the widget tree
/// observes the provider exactly like the real screens do.
Widget _harness(AlertProvider provider) => ChangeNotifierProvider.value(
      value: provider,
      child: MaterialApp(
        home: Scaffold(
          body: Consumer<AlertProvider>(
            builder: (_, p, __) => Column(
              children: [
                for (final a in p.allAlerts) Text('${a.id}:${a.status}'),
              ],
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets(
      'pocketbase backend: alerts stream in and claim/resolve update the UI '
      'with zero AlertService (Firebase) calls', (tester) async {
    final alertService = _MockAlertService();
    final store = FakeDataStore(
      backendName: 'pocketbase',
      seed: [_alert('a1'), _alert('a2')],
    );
    final provider = AlertProvider(
      alertStreamService: AlertStreamService(
        alertService: alertService,
        logger: const AppLogger(),
        dataStore: store,
      ),
      alertActionsService: AlertActionsService(
        alertService: alertService,
        aiService: _MockAIService(),
        logger: const AppLogger(),
        dataStore: store,
      ),
      notificationService: NotificationService(
        alertService: alertService,
        logger: const AppLogger(),
      ),
    );

    await tester.pumpWidget(_harness(provider));
    provider.initForProductionManager();
    await tester.pump();
    await tester.pump();

    expect(find.text('a1:disponible'), findsOneWidget);
    expect(find.text('a2:disponible'), findsOneWidget);

    await provider.takeAlert('a1', 'sup1', 'Sam');
    await tester.pump();
    expect(find.text('a1:en_cours'), findsOneWidget);

    await provider.resolveAlert('a1', 'belt fixed');
    await tester.pump();
    expect(find.text('a1:validee'), findsOneWidget);

    // A new alert arriving over the wire reaches the UI without any
    // Firebase notification side path.
    store.serverPush([_alert('a1', status: 'validee'), _alert('a2'), _alert('a3')]);
    await tester.pump();
    await tester.pump();
    expect(find.text('a3:disponible'), findsOneWidget);

    verifyZeroInteractions(alertService);

    await tester.pumpWidget(const SizedBox());
    provider.dispose();
    store.dispose();
  });

  testWidgets(
      'firebase backend: same provider flow delegates to AlertService and '
      'keeps the new-alert notification side effect', (tester) async {
    final alertService = _MockAlertService();
    final controller = StreamController<List<AlertModel>>.broadcast();
    when(() => alertService.getAllAlerts(limit: any(named: 'limit')))
        .thenAnswer((_) => controller.stream);
    when(() => alertService.takeAlert('a1', 'sup1', 'Sam'))
        .thenAnswer((_) async {});
    when(() => alertService.sendNewAlertNotification(any(), any(), any()))
        .thenAnswer((_) async {});

    final store = FirebaseDataStore(alertService: alertService);
    final provider = AlertProvider(
      alertStreamService: AlertStreamService(
        alertService: alertService,
        logger: const AppLogger(),
        dataStore: store,
      ),
      alertActionsService: AlertActionsService(
        alertService: alertService,
        aiService: _MockAIService(),
        logger: const AppLogger(),
        dataStore: store,
      ),
      notificationService: NotificationService(
        alertService: alertService,
        logger: const AppLogger(),
      ),
    );

    await tester.pumpWidget(_harness(provider));
    provider.initForProductionManager();
    controller.add([_alert('a1')]);
    await tester.pump();
    expect(find.text('a1:disponible'), findsOneWidget);

    await provider.takeAlert('a1', 'sup1', 'Sam');
    await tester.pump();
    expect(find.text('a1:en_cours'), findsOneWidget);
    verify(() => alertService.takeAlert('a1', 'sup1', 'Sam')).called(1);

    // New alert appears on the stream -> cloud fan-out side effect fires.
    controller.add([_alert('a1', status: 'en_cours'), _alert('a2')]);
    await tester.pump();
    verify(() => alertService.sendNewAlertNotification('a2', any(), any()))
        .called(1);

    await tester.pumpWidget(const SizedBox());
    provider.dispose();
    await controller.close();
  });
}
