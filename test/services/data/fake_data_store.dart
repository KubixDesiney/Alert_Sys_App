import 'dart:async';

import 'package:alertsysapp/models/alert_model.dart';
import 'package:alertsysapp/services/data/data_store.dart';

/// In-memory [DataStore] test double. Behaves like a tiny backend: lifecycle
/// writes mutate the alert list and every watcher re-emits, so provider /
/// widget tests can exercise the full claim→resolve→comment flow without any
/// network or Firebase.
class FakeDataStore implements DataStore {
  FakeDataStore({
    this.backendName = 'pocketbase',
    List<AlertModel>? seed,
  }) : alerts = [...?seed];

  @override
  final String backendName;

  final List<AlertModel> alerts;
  final List<String> calls = [];
  final List<Map<String, String?>> auditRecords = [];
  final Map<String, String> userRoles = {};

  final List<StreamController<List<AlertModel>>> _watchers = [];

  void _log(String call) => calls.add(call);

  void _emitAll() {
    final snapshot = List<AlertModel>.unmodifiable(alerts);
    for (final c in _watchers) {
      if (!c.isClosed) c.add(snapshot);
    }
  }

  /// Simulates a server-side change arriving on the wire.
  void serverPush(List<AlertModel> next) {
    alerts
      ..clear()
      ..addAll(next);
    _emitAll();
  }

  AlertModel _byId(String id) => alerts.firstWhere((a) => a.id == id);

  void _replace(String id, AlertModel Function(AlertModel) update) {
    for (var i = 0; i < alerts.length; i++) {
      if (alerts[i].id == id) {
        alerts[i] = update(alerts[i]);
        break;
      }
    }
    _emitAll();
  }

  Stream<List<AlertModel>> _watch(bool Function(AlertModel) predicate) {
    late StreamController<List<AlertModel>> controller;
    controller = StreamController<List<AlertModel>>(
      onListen: () =>
          controller.add(List.unmodifiable(alerts.where(predicate))),
      onCancel: () => _watchers.remove(controller),
    );
    _watchers.add(controller);
    return controller.stream
        .map((all) => List.unmodifiable(all.where(predicate)));
  }

  @override
  Stream<List<AlertModel>> watchAllAlerts({int? limit}) => _watch((_) => true);

  @override
  Stream<List<AlertModel>> watchAlertsForUsine(String usine, {int? limit}) =>
      _watch((a) => a.usine == usine);

  @override
  Stream<List<AlertModel>> watchAlertsForSupervisor(String supervisorId,
          {int? limit}) =>
      _watch((a) =>
          a.superviseurId == supervisorId || a.assistantId == supervisorId);

  @override
  Future<List<AlertModel>> fetchOlderAlerts({
    String? usine,
    required DateTime before,
    int limit = 100,
  }) async {
    _log('fetchOlderAlerts($usine, $before)');
    return alerts
        .where((a) =>
            a.timestamp.isBefore(before) && (usine == null || a.usine == usine))
        .take(limit)
        .toList();
  }

  @override
  Future<String?> createAlert({
    required String type,
    required String usine,
    required int convoyeur,
    required int poste,
    required String description,
    bool isCritical = false,
  }) async {
    _log('createAlert($type, $usine)');
    final id = 'fake-${alerts.length + 1}';
    alerts.add(AlertModel(
      id: id,
      type: type,
      usine: usine,
      convoyeur: convoyeur,
      poste: poste,
      adresse: '${usine}_C${convoyeur}_P$poste',
      timestamp: DateTime.now(),
      description: description,
      status: 'disponible',
      isCritical: isCritical,
      comments: const [],
    ));
    _emitAll();
    return id;
  }

  @override
  Future<void> claimAlert(
      String alertId, String supervisorId, String supervisorName) async {
    _log('claimAlert($alertId, $supervisorId)');
    _replace(
      alertId,
      (a) => a.copyWith(
        status: 'en_cours',
        superviseurId: supervisorId,
        superviseurName: supervisorName,
        takenAtTimestamp: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> resolveAlert(
    String alertId,
    String reason,
    int elapsedMinutes, {
    String? assistingSupervisorId,
    String? assistingSupervisorName,
  }) async {
    _log('resolveAlert($alertId, $reason)');
    _replace(
      alertId,
      (a) => a.copyWith(
        status: 'validee',
        resolutionReason: reason,
        elapsedTime: elapsedMinutes,
        resolvedAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> returnAlertToQueue(String alertId, {String? reason}) async {
    _log('returnAlertToQueue($alertId, $reason)');
    _replace(
      alertId,
      (a) => a.copyWith(
        status: 'disponible',
        clearSuperviseur: true,
        clearTakenAt: true,
      ),
    );
  }

  @override
  Future<void> setCritical(String alertId, bool isCritical,
      {String? note}) async {
    _log('setCritical($alertId, $isCritical, $note)');
    _replace(alertId, (a) => a.copyWith(isCritical: isCritical, criticalNote: note));
  }

  @override
  Future<void> addComment(String alertId, String comment) async {
    _log('addComment($alertId)');
    final existing = _byId(alertId);
    _replace(alertId,
        (a) => a.copyWith(comments: [...existing.comments, comment]));
  }

  @override
  Future<String?> fetchUserRole(String uid) async => userRoles[uid];

  @override
  Future<void> writeAudit({
    required String action,
    required String targetType,
    required String targetId,
    String? factoryId,
    String? detail,
  }) async {
    auditRecords.add({
      'action': action,
      'targetType': targetType,
      'targetId': targetId,
      'factoryId': factoryId,
      'detail': detail,
    });
  }

  void dispose() {
    for (final c in _watchers) {
      c.close();
    }
    _watchers.clear();
  }
}
