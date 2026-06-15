import 'package:firebase_database/firebase_database.dart';

import '../../models/alert_model.dart';
import '../alert_service.dart';
import '../service_locator.dart';
import 'data_store.dart';

/// [DataStore] backed by Firebase. It delegates to the existing [AlertService]
/// so behaviour is byte-for-byte the current cloud app — adopting it changes
/// nothing until callers are switched to use [DataStore].
class FirebaseDataStore implements DataStore {
  FirebaseDataStore({AlertService? alertService, FirebaseDatabase? database})
      : _alerts = alertService ?? ServiceLocator.instance.alertService,
        _db = database ?? FirebaseDatabase.instance;

  final AlertService _alerts;
  final FirebaseDatabase _db;

  @override
  String get backendName => 'firebase';

  @override
  Stream<List<AlertModel>> watchAlertsForUsine(String usine, {int? limit}) =>
      _alerts.getAlertsForUsine(usine, limit: limit);

  @override
  Stream<List<AlertModel>> watchAlertsForSupervisor(String supervisorId, {int? limit}) =>
      _alerts.getAlertsWhereSupervisor(supervisorId, limit: limit);

  @override
  Future<void> claimAlert(String alertId, String supervisorId, String supervisorName) =>
      _alerts.takeAlert(alertId, supervisorId, supervisorName);

  @override
  Future<void> resolveAlert(String alertId, String reason, int elapsedMinutes) =>
      _alerts.resolveAlert(alertId, reason, elapsedMinutes);

  @override
  Future<void> returnAlertToQueue(String alertId, {String? reason}) =>
      _alerts.returnToQueue(alertId, reason: reason);

  @override
  Future<void> setCritical(String alertId, bool isCritical) =>
      _alerts.toggleCritical(alertId, isCritical);

  @override
  Future<String?> fetchUserRole(String uid) async {
    final snap = await _db.ref('users/$uid').get();
    final data = snap.value;
    if (data is Map) return data['role']?.toString();
    return null;
  }
}
