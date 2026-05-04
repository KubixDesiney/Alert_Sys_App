import 'package:alertsysapp/models/alert_model.dart';
import 'package:alertsysapp/services/ai_service.dart';
import 'package:alertsysapp/services/alert_actions_service.dart';
import 'package:alertsysapp/services/alert_service.dart';
import 'package:alertsysapp/services/app_logger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockAlertService extends Mock implements AlertService {}

class _MockAIService extends Mock implements AIService {}

void main() {
  late _MockAlertService alertService;
  late _MockAIService aiService;
  late AlertActionsService service;

  setUp(() {
    alertService = _MockAlertService();
    aiService = _MockAIService();
    service = AlertActionsService(
      alertService: alertService,
      aiService: aiService,
      logger: const AppLogger(),
    );
  });

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
      timestamp: DateTime(2025, 1, 1, 10),
      description: 'Needs service',
      status: status,
      superviseurId: supervisorId,
      superviseurName: supervisorName,
      takenAtTimestamp: DateTime(2025, 1, 1, 10),
      comments: const [],
    );
  }

  test('takeAlert updates local state and delegates to AlertService', () async {
    AlertModel? updated;
    when(() => alertService.takeAlert(any(), any(), any()))
        .thenAnswer((_) async {});

    await service.takeAlert(
      alerts: [buildAlert()],
      alertId: 'a1',
      superviseurId: 'sup-1',
      superviseurName: 'Sam',
      updateLocal: (_, fn) => updated = fn(buildAlert()),
    );

    expect(updated?.status, 'en_cours');
    expect(updated?.superviseurId, 'sup-1');
    verify(() => alertService.takeAlert('a1', 'sup-1', 'Sam')).called(1);
  });

  test('takeAlert rejects when supervisor already has an in-progress alert', () {
    expect(
      () => service.takeAlert(
        alerts: [
          buildAlert(id: 'a1', status: 'en_cours', supervisorId: 'sup-1'),
        ],
        alertId: 'a2',
        superviseurId: 'sup-1',
        superviseurName: 'Sam',
        updateLocal: (_, __) {},
      ),
      throwsException,
    );
  });

  test('addComment appends a formatted comment locally and remotely', () async {
    AlertModel? updated;
    when(() => alertService.addComment(any(), any())).thenAnswer((_) async {});

    await service.addComment(
      alerts: [buildAlert()],
      alertId: 'a1',
      comment: 'Checked motor',
      currentSuperviseurName: 'Sam',
      updateLocal: (_, fn) => updated = fn(buildAlert()),
    );

    expect(updated?.comments.single, contains('Sam: Checked motor'));
    verify(() => alertService.addComment('a1', any(that: contains('Sam'))))
        .called(1);
  });
}
