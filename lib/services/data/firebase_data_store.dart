import 'package:firebase_database/firebase_database.dart';

import '../../models/alert_model.dart';
import '../alert_service.dart';
import '../audit_service.dart';
import '../service_locator.dart';
import 'data_store.dart';

/// [DataStore] backed by Firebase. It delegates to the existing [AlertService]
/// and [AuditService] so behaviour is byte-for-byte the current cloud app —
/// routing the lifecycle through it changes nothing on the Firebase backend.
class FirebaseDataStore implements DataStore {
  FirebaseDataStore({
    AlertService? alertService,
    FirebaseDatabase? database,
    AuditService? auditService,
  })  : _alerts = alertService ?? ServiceLocator.instance.alertService,
        _dbOverride = database,
        _auditOverride = auditService;

  final AlertService _alerts;
  // Lazy: FirebaseDatabase.instance throws without an initialized Firebase
  // app, and unit tests construct this store with only a mock AlertService.
  final FirebaseDatabase? _dbOverride;
  final AuditService? _auditOverride;

  FirebaseDatabase get _db => _dbOverride ?? FirebaseDatabase.instance;
  AuditService get _audit => _auditOverride ?? AuditService.instance;

  @override
  String get backendName => 'firebase';

  @override
  Stream<List<AlertModel>> watchAllAlerts({int? limit}) =>
      _alerts.getAllAlerts(limit: limit);

  @override
  Stream<List<AlertModel>> watchAlertsForUsine(String usine, {int? limit}) =>
      _alerts.getAlertsForUsine(usine, limit: limit);

  @override
  Stream<List<AlertModel>> watchAlertsForSupervisor(String supervisorId,
          {int? limit}) =>
      _alerts.getAlertsWhereSupervisor(supervisorId, limit: limit);

  @override
  Future<List<AlertModel>> fetchOlderAlerts({
    String? usine,
    required DateTime before,
    int limit = 100,
  }) {
    if (usine == null) {
      return _alerts.fetchOlderAlerts(before: before, limit: limit);
    }
    return _alerts.fetchOlderAlertsForUsine(
        usine: usine, before: before, limit: limit);
  }

  @override
  Future<String?> createAlert({
    required String type,
    required String usine,
    required int convoyeur,
    required int poste,
    required String description,
    bool isCritical = false,
  }) =>
      _alerts.createAlertWithHierarchy(
        type: type,
        usine: usine,
        convoyeur: convoyeur,
        poste: poste,
        description: description,
        isCritical: isCritical,
      );

  @override
  Future<void> claimAlert(
          String alertId, String supervisorId, String supervisorName) =>
      _alerts.takeAlert(alertId, supervisorId, supervisorName);

  @override
  Future<void> resolveAlert(
    String alertId,
    String reason,
    int elapsedMinutes, {
    String? assistingSupervisorId,
    String? assistingSupervisorName,
  }) =>
      _alerts.resolveAlert(
        alertId,
        reason,
        elapsedMinutes,
        assistingSupervisorId: assistingSupervisorId,
        assistingSupervisorName: assistingSupervisorName,
      );

  @override
  Future<void> returnAlertToQueue(String alertId, {String? reason}) =>
      _alerts.returnToQueue(alertId, reason: reason);

  @override
  Future<void> setCritical(String alertId, bool isCritical,
      {String? note}) async {
    await _alerts.toggleCritical(alertId, isCritical);
    if (note != null) {
      await _alerts.setCriticalNote(alertId, note);
    }
  }

  @override
  Future<void> addComment(String alertId, String comment) =>
      _alerts.addComment(alertId, comment);

  @override
  Future<String?> fetchUserRole(String uid) async {
    final snap = await _db.ref('users/$uid').get();
    final data = snap.value;
    if (data is Map) return data['role']?.toString();
    return null;
  }

  @override
  Future<void> writeAudit({
    required String action,
    required String targetType,
    required String targetId,
    String? factoryId,
    String? detail,
  }) =>
      _audit.log(
        action: action,
        targetType: targetType,
        targetId: targetId,
        factoryId: factoryId,
        detail: detail,
      );
}
