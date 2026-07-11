import 'dart:async';

import '../models/alert_model.dart';
import 'ai_service.dart';
import 'alert_service.dart';
import 'app_logger.dart';
import 'data/data_store.dart';
import 'data/firebase_data_store.dart';
import 'worker_trigger_queue.dart';

class AlertActionsService {
  AlertActionsService({
    required AlertService alertService,
    required AIService aiService,
    required AppLogger logger,
    DataStore? dataStore,
  })  : _alertService = alertService,
        _aiService = aiService,
        _logger = logger,
        // Default preserves cloud behaviour exactly: FirebaseDataStore is a
        // pure delegation layer over the same AlertService instance.
        _store = dataStore ?? FirebaseDataStore(alertService: alertService);

  final AlertService _alertService;
  final AIService _aiService;
  final AppLogger _logger;
  final DataStore _store;

  bool get _isFirebase => _store.backendName == 'firebase';

  Future<void> takeAlert({
    required List<AlertModel> alerts,
    required String alertId,
    required String superviseurId,
    required String superviseurName,
    required void Function(String, AlertModel Function(AlertModel))
        updateLocal,
  }) async {
    final existingInProgress = alerts
        .any((a) => a.status == 'en_cours' && a.superviseurId == superviseurId);
    if (existingInProgress) {
      throw Exception(
        'You already have a claimed alert. Please resolve it before claiming a new one.',
      );
    }

    await _store.claimAlert(alertId, superviseurId, superviseurName);
    updateLocal(
      alertId,
      (a) => a.copyWith(
        status: 'en_cours',
        superviseurId: superviseurId,
        superviseurName: superviseurName,
        takenAtTimestamp: DateTime.now(),
      ),
    );
    unawaited(_store.writeAudit(
      action: 'alert.claim',
      targetType: 'alert',
      targetId: alertId,
      detail: 'Claimed by $superviseurName',
    ));
  }

  Future<void> returnToQueue({
    required List<AlertModel> alerts,
    required String alertId,
    required void Function(String, AlertModel Function(AlertModel))
        updateLocal,
    String? reason,
  }) async {
    final alert = alerts.firstWhere((a) => a.id == alertId);
    final supervisorName = alert.superviseurName ?? 'A supervisor';
    updateLocal(
      alertId,
      (a) => a.copyWith(
        status: 'disponible',
        clearSuperviseur: true,
        clearTakenAt: true,
      ),
    );
    await _store.returnAlertToQueue(alertId, reason: reason);
    if (_isFirebase) {
      // Firebase: client fans out the suspend notification. On-prem the
      // worker-runner detects the status transition and pushes over LAN SSE.
      await _alertService.notifyAdminsAboutSuspend(
        alertId,
        supervisorName,
        reason,
      );
    }
    unawaited(_store.writeAudit(
      action: 'alert.return',
      targetType: 'alert',
      targetId: alertId,
      factoryId: alert.usine,
      detail: reason == null ? 'Returned to queue' : 'Returned to queue: $reason',
    ));
  }

  Future<void> resolveAlert({
    required List<AlertModel> alerts,
    required String alertId,
    required String reason,
    required void Function(String, AlertModel Function(AlertModel))
        updateLocal,
  }) async {
    final alert = alerts.firstWhere((a) => a.id == alertId);
    final elapsed = alert.takenAtTimestamp != null
        ? DateTime.now().difference(alert.takenAtTimestamp!).inMinutes
        : 0;
    updateLocal(
      alertId,
      (a) => a.copyWith(
        status: 'validee',
        elapsedTime: elapsed,
        resolutionReason: reason,
        resolvedAt: DateTime.now(),
      ),
    );

    await _store.resolveAlert(
      alertId,
      reason,
      elapsed,
      assistingSupervisorId: alert.superviseurId,
      assistingSupervisorName: alert.superviseurName,
    );
    if (_isFirebase) {
      // Cloud-only: nudges the Cloudflare AI worker. On-prem assignment runs
      // on its own cron inside the worker-runner.
      await WorkerTriggerQueue.instance.enqueueAiRetry();
    }
    unawaited(_store.writeAudit(
      action: 'alert.resolve',
      targetType: 'alert',
      targetId: alertId,
      factoryId: alert.usine,
      detail: 'Resolved ($elapsed min): $reason',
    ));
  }

  Future<void> addComment({
    required List<AlertModel> alerts,
    required String alertId,
    required String comment,
    required String currentSuperviseurName,
    required void Function(String, AlertModel Function(AlertModel))
        updateLocal,
  }) async {
    final newComment =
        '[${_formatTime(DateTime.now())}] $currentSuperviseurName: $comment';
    final alert = alerts.firstWhere((a) => a.id == alertId);
    final updatedComments = [...alert.comments, newComment];
    updateLocal(alertId, (a) => a.copyWith(comments: updatedComments));
    await _store.addComment(alertId, newComment);
  }

  Future<void> toggleCritical({
    required String alertId,
    required bool isCritical,
    required void Function(String, AlertModel Function(AlertModel))
        updateLocal,
    String? note,
  }) async {
    updateLocal(
      alertId,
      (a) => a.copyWith(isCritical: isCritical, criticalNote: note),
    );
    await _store.setCritical(alertId, isCritical, note: note);
    unawaited(_store.writeAudit(
      action: 'alert.critical_toggle',
      targetType: 'alert',
      targetId: alertId,
      detail: isCritical
          ? (note != null ? 'Flagged critical: $note' : 'Flagged critical')
          : 'Cleared critical',
    ));
  }

  Future<List<String>> getPastResolutionsForType(
    List<AlertModel> alerts,
    String type,
    int limit,
  ) async {
    final similar = alerts
        .where(
          (a) =>
              a.type == type &&
              a.status == 'validee' &&
              a.resolutionReason != null,
        )
        .toList()
      ..sort((a, b) => b.resolvedAt!.compareTo(a.resolvedAt!));
    return similar.take(limit).map((a) => a.resolutionReason!).toList();
  }

  Future<List<String>> getPastResolutionsForLocation({
    required List<AlertModel> alerts,
    required String type,
    required String usine,
    required int convoyeur,
    required int poste,
    int limit = 3,
  }) async {
    final similar = alerts
        .where(
          (a) =>
              a.type == type &&
              a.status == 'validee' &&
              a.resolutionReason != null &&
              a.usine == usine &&
              a.convoyeur == convoyeur &&
              a.poste == poste,
        )
        .toList()
      ..sort((a, b) => b.resolvedAt!.compareTo(a.resolvedAt!));
    return similar.take(limit).map((a) => a.resolutionReason!).toList();
  }

  Future<String> getAiSuggestionForAlert(
    AlertModel alert,
    List<AlertModel> alerts,
  ) async {
    final pastResolutions = await getPastResolutionsForLocation(
      alerts: alerts,
      type: alert.type,
      usine: alert.usine,
      convoyeur: alert.convoyeur,
      poste: alert.poste,
      limit: 3,
    );
    _logger.debug('Generating AI resolution suggestion for ${alert.id}');
    return _aiService.getResolutionSuggestion(
      alertType: alert.type,
      alertDescription: alert.description,
      usine: alert.usine,
      convoyeur: alert.convoyeur,
      poste: alert.poste,
      pastResolutions: pastResolutions,
    );
  }

  String _formatTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}
