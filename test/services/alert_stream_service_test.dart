import 'dart:async';

import 'package:alertsysapp/models/alert_model.dart';
import 'package:alertsysapp/services/alert_service.dart';
import 'package:alertsysapp/services/alert_stream_service.dart';
import 'package:alertsysapp/services/app_logger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockAlertService extends Mock implements AlertService {}

void main() {
  late _MockAlertService alertService;
  late AlertStreamService service;
  late StreamController<List<AlertModel>> controller;

  setUp(() {
    alertService = _MockAlertService();
    service = AlertStreamService(
      alertService: alertService,
      logger: const AppLogger(),
    );
    controller = StreamController<List<AlertModel>>();

    when(() => alertService.getAllAlerts(limit: any(named: 'limit')))
        .thenAnswer((_) => controller.stream);
    when(
      () => alertService.sendNewAlertNotification(any(), any(), any()),
    ).thenAnswer((_) async {});
  });

  tearDown(() async {
    service.reset();
    await controller.close();
  });

  AlertModel buildAlert(String id, DateTime timestamp) {
    return AlertModel(
      id: id,
      type: 'maintenance',
      usine: 'Usine A',
      convoyeur: 1,
      poste: 1,
      adresse: 'A',
      timestamp: timestamp,
      description: 'desc',
      status: 'disponible',
      comments: const [],
    );
  }

  test('initForProductionManager pushes initial alerts to consumer', () async {
    final seen = <List<AlertModel>>[];

    service.initForProductionManager(
      onAlerts: seen.add,
      onLoading: () {},
    );

    controller.add([buildAlert('a1', DateTime(2025, 1, 1))]);
    await Future<void>.delayed(Duration.zero);

    expect(seen, hasLength(1));
    expect(seen.single.single.id, 'a1');
  });

  test('subsequent new alerts trigger in-app notification fanout', () async {
    service.initForProductionManager(
      onAlerts: (_) {},
      onLoading: () {},
    );

    controller.add([buildAlert('a1', DateTime(2025, 1, 1))]);
    await Future<void>.delayed(Duration.zero);
    controller.add([
      buildAlert('a2', DateTime(2025, 1, 2)),
      buildAlert('a1', DateTime(2025, 1, 1)),
    ]);
    await Future<void>.delayed(Duration.zero);

    verify(
      () => alertService.sendNewAlertNotification('a2', 'maintenance', 'desc'),
    ).called(1);
  });
}
