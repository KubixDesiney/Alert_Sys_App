import '../models/alert_model.dart';
import 'alert_service.dart';
import 'app_logger.dart';
import 'worker_trigger_queue.dart';

class NotificationService {
  NotificationService({
    required AlertService alertService,
    required AppLogger logger,
  })  : _alertService = alertService,
        _logger = logger;

  final AlertService _alertService;
  final AppLogger _logger;

  Future<void> requestAssistanceForAlert({
    required List<AlertModel> alerts,
    required String alertId,
    required String currentUserId,
    required String currentSuperviseurName,
  }) async {
    final alert = alerts.firstWhere((a) => a.id == alertId);
    if (alert.superviseurId == null) {
      return;
    }
    final users = await _alertService.getAllUsers();
    for (final entry in users.entries) {
      final userId = entry.key;
      if (userId == currentUserId) {
        continue;
      }
      final userData = entry.value as Map;
      final role = userData['role'] ?? 'supervisor';
      if (role == 'supervisor' || role == 'admin') {
        final notification = {
          'type': 'assistance_request',
          'alertId': alertId,
          'alertType': alert.type,
          'alertDescription': alert.description,
          'requesterName': currentSuperviseurName,
          'message':
              '$currentSuperviseurName needs assistance on alert: ${alert.type}',
          'timestamp': DateTime.now().toIso8601String(),
          'status': 'pending',
        };
        await _alertService.sendHelpRequest(userId, notification);
      }
    }
    await WorkerTriggerQueue.instance.enqueueNotify();
  }

  Future<void> acceptAssistance({
    required String alertId,
    required String currentId,
    required String currentName,
    required void Function(String, AlertModel Function(AlertModel))
        updateLocal,
  }) async {
    await _alertService.acceptHelpRequest(alertId, '', currentId, currentName);
    updateLocal(
      alertId,
      (a) => a.copyWith(
        assistantId: currentId,
        assistantName: currentName,
        helpRequestId: null,
      ),
    );
  }

  Future<void> acceptHelp({
    required String alertId,
    required String requestId,
    required String currentId,
    required String currentName,
    required void Function(String, AlertModel Function(AlertModel))
        updateLocal,
  }) async {
    await _alertService.acceptHelpRequest(
      alertId,
      requestId,
      currentId,
      currentName,
    );
    updateLocal(
      alertId,
      (a) => a.copyWith(
        assistantId: currentId,
        assistantName: currentName,
        helpRequestId: null,
      ),
    );
  }

  Future<void> refuseHelp({
    required String alertId,
    required String requestId,
    required void Function(String, AlertModel Function(AlertModel))
        updateLocal,
  }) async {
    await _alertService.refuseHelpRequest(alertId, requestId);
    updateLocal(alertId, (a) => a.copyWith(helpRequestId: null));
  }

  Future<void> requestHelp({
    required List<AlertModel> alerts,
    required String alertId,
    required String requesterId,
    required String requesterName,
  }) async {
    final alert = alerts.firstWhere((a) => a.id == alertId);
    if (alert.superviseurId == null) {
      return;
    }
    await _alertService.createHelpRequest(
      alertId,
      requesterId,
      requesterName,
      alert.superviseurId!,
    );
  }

  Future<void> notifyAllUsers({
    required List<AlertModel> alerts,
    required String alertId,
    required bool isCritical,
    String? customMessage,
  }) async {
    final alert = alerts.firstWhere((a) => a.id == alertId);
    final users = await _alertService.getAllUsers();
    for (final entry in users.entries) {
      final userId = entry.key;
      final userData = entry.value as Map;
      if (userData['role'] == 'admin' || userData['role'] == 'supervisor') {
        final message = customMessage ??
            (isCritical
                ? 'Alert marked as CRITICAL: ${alert.type}'
                : 'Alert critical flag removed: ${alert.type}');
        final notification = {
          'type': 'alert_critical_update',
          'alertId': alertId,
          'alertType': alert.type,
          'alertDescription': alert.description,
          'message': message,
          'timestamp': DateTime.now().toIso8601String(),
          'status': 'pending',
        };
        await _alertService.sendHelpRequest(userId, notification);
      }
    }
    _logger.info('Critical update broadcast for alert $alertId');
  }
}
