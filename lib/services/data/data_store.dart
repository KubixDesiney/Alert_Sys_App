import '../../models/alert_model.dart';

/// Backend-agnostic data layer for SIAS's core alert lifecycle (v2 surface).
///
/// WIRED: `AlertProvider` -> `AlertActionsService` / `AlertStreamService` route
/// the core lifecycle through this interface. [FirebaseDataStore] delegates to
/// the existing services so cloud behaviour is unchanged; [PocketBaseDataStore]
/// is the on-prem/air-gapped path (`--dart-define=SIAS_BACKEND=pocketbase`)
/// and never touches Firebase.
///
/// v2 covers: watching, creating, claiming, resolving, suspending/returning,
/// critical flagging (with note), comments and audit records. Help,
/// collaboration and shift flows remain Firebase-only for now (v3 scope) —
/// see `lib/services/data/README.md` for the honest coverage table.
abstract class DataStore {
  /// Identifies the active backend (e.g. 'firebase' or 'pocketbase').
  String get backendName;

  // ── Streams / reads ───────────────────────────────────────────────────────

  /// All alerts, newest first (Production Manager dashboards).
  Stream<List<AlertModel>> watchAllAlerts({int? limit});

  Stream<List<AlertModel>> watchAlertsForUsine(String usine, {int? limit});

  /// Alerts where the user is the owner or the assistant.
  Stream<List<AlertModel>> watchAlertsForSupervisor(String supervisorId,
      {int? limit});

  /// One-shot page of alerts strictly older than [before] (pagination).
  Future<List<AlertModel>> fetchOlderAlerts({
    String? usine,
    required DateTime before,
    int limit = 100,
  });

  // ── Alert lifecycle writes ────────────────────────────────────────────────

  /// Creates a new alert; returns its id (null on failure).
  Future<String?> createAlert({
    required String type,
    required String usine,
    required int convoyeur,
    required int poste,
    required String description,
    bool isCritical = false,
  });

  Future<void> claimAlert(
      String alertId, String supervisorId, String supervisorName);

  Future<void> resolveAlert(
    String alertId,
    String reason,
    int elapsedMinutes, {
    String? assistingSupervisorId,
    String? assistingSupervisorName,
  });

  /// Suspend: put a claimed alert back in the queue, optionally with a reason.
  Future<void> returnAlertToQueue(String alertId, {String? reason});

  /// Critical flag, with an optional operator note explaining why.
  Future<void> setCritical(String alertId, bool isCritical, {String? note});

  Future<void> addComment(String alertId, String comment);

  // ── Identity / audit ──────────────────────────────────────────────────────

  Future<String?> fetchUserRole(String uid);

  /// Append-only audit record. Firebase -> `audit_log` RTDB node (via
  /// AuditService); PocketBase -> `audit_logs` collection. Must never throw:
  /// an audit failure cannot be allowed to break the primary action.
  Future<void> writeAudit({
    required String action,
    required String targetType,
    required String targetId,
    String? factoryId,
    String? detail,
  });
}
