import 'package:alertsysapp/services/collaboration_service.dart';
import 'package:alertsysapp/services/app_logger.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeDatabaseReference extends Fake implements DatabaseReference {}

void main() {
  late CollaborationService service;

  setUp(() {
    service = CollaborationService(
      logger: const AppLogger(),
      database: _FakeDatabaseReference(),
    );
  });

  test('buildApprovalPlan detects cross-factory transfers and claimed alerts', () {
    final plan = service.buildApprovalPlan(
      alertUsine: 'Usine A',
      candidates: const [
        CollaborationApprovalCandidate(
          supervisorId: 'sup-1',
          supervisorName: 'Sam',
          supervisorUsine: 'Usine B',
          claimedAlerts: [
            CollaborationClaimedAlert(alertId: 'a-old', usine: 'Usine B'),
          ],
        ),
        CollaborationApprovalCandidate(
          supervisorId: 'sup-2',
          supervisorName: 'Mira',
          supervisorUsine: 'Usine A',
          claimedAlerts: [],
        ),
      ],
    );

    expect(plan.requiresTransferConfirmation, isTrue);
    expect(plan.requiresOriginalAlertConfirmation, isTrue);
    expect(plan.crossFactoryTransfers, [
      {'name': 'Sam', 'fromUsine': 'Usine B'},
    ]);
    expect(plan.existingClaimedAlerts, [
      {'alertId': 'a-old', 'usine': 'Usine B'},
    ]);
  });

  test('buildApprovalPlan stays empty when all candidates already match factory', () {
    final plan = service.buildApprovalPlan(
      alertUsine: 'Usine A',
      candidates: const [
        CollaborationApprovalCandidate(
          supervisorId: 'sup-1',
          supervisorName: 'Sam',
          supervisorUsine: 'Usine A',
          claimedAlerts: [],
        ),
      ],
    );

    expect(plan.requiresTransferConfirmation, isFalse);
    expect(plan.requiresOriginalAlertConfirmation, isFalse);
    expect(plan.crossFactoryTransfers, isEmpty);
    expect(plan.existingClaimedAlerts, isEmpty);
  });
}
