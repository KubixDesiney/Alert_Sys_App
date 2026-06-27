import '../../models/alert_model.dart';

/// Backend-agnostic data layer for SIAS's core alert lifecycle (v1 surface).
///
/// ADDITIVE: nothing in the app uses this yet. It exists so the app can run
/// against an on-prem PocketBase backend (see `deploy/onprem/`) with no cloud
/// dependency. [FirebaseDataStore] delegates to the existing services so cloud
/// behaviour is identical; [PocketBaseDataStore] is the air-gapped path.
///
/// v1 covers the operational lifecycle. Comments, help, collaboration and shift
/// flows are intentionally out of scope until v2.
abstract class DataStore {
  /// Identifies the active backend (e.g. 'firebase' or 'pocketbase').
  String get backendName;

  Stream<List<AlertModel>> watchAlertsForUsine(String usine, {int? limit});
  Stream<List<AlertModel>> watchAlertsForSupervisor(String supervisorId, {int? limit});

  Future<void> claimAlert(String alertId, String supervisorId, String supervisorName);
  Future<void> resolveAlert(String alertId, String reason, int elapsedMinutes);
  Future<void> returnAlertToQueue(String alertId, {String? reason});
  Future<void> setCritical(String alertId, bool isCritical);

  Future<String?> fetchUserRole(String uid);
}
