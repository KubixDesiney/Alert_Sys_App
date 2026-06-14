import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

import 'app_logger.dart';

/// Canonical audit action identifiers.
///
/// These strings are written to the immutable `audit_log` node and are queried
/// by compliance/reporting tooling, so treat them as a stable contract — add
/// new ones, never rename existing ones.
class AuditAction {
  AuditAction._();

  // Alert lifecycle
  static const String alertCreate = 'alert.create';
  static const String alertClaim = 'alert.claim';
  static const String alertReturn = 'alert.return';
  static const String alertResolve = 'alert.resolve';
  static const String alertValidate = 'alert.validate';
  static const String alertEscalate = 'alert.escalate';
  static const String alertCriticalToggle = 'alert.critical_toggle';

  // Collaboration / help
  static const String collaborationRequest = 'collaboration.request';
  static const String collaborationApprove = 'collaboration.approve';
  static const String collaborationReject = 'collaboration.reject';
  static const String helpRequest = 'help.request';
  static const String helpAccept = 'help.accept';

  // Account / access administration (highest-value for compliance)
  static const String accountProvision = 'account.provision';
  static const String accountRevoke = 'account.revoke';
  static const String accountRoleChange = 'account.role_change';
  static const String passwordReset = 'account.password_reset';
  static const String authSignIn = 'auth.sign_in';
  static const String authSignOut = 'auth.sign_out';

  // Configuration / AI governance
  static const String settingsChange = 'settings.change';
  static const String shiftChange = 'shift.change';
  static const String aiAgentToggle = 'ai.agent_toggle';
  static const String aiOverride = 'ai.override';
  static const String forecastDeploy = 'forecast.deploy';
}

/// Writes immutable, append-only audit records to the `audit_log` RTDB node.
///
/// Design goals:
///  * Tamper-evident: the security rules allow create-only writes (no update or
///    delete) and pin `actorId` to the authenticated uid, so a record cannot be
///    forged or quietly altered after the fact.
///  * Non-blocking: an audit failure must NEVER break the primary action. Every
///    write is wrapped — failures are logged (and therefore reach the bug
///    pipeline) rather than thrown.
///  * Cheap: the actor's role is cached in memory after the first lookup.
///
/// Usage:
/// ```dart
/// await AuditService.instance.log(
///   action: AuditAction.alertResolve,
///   targetType: 'alert',
///   targetId: alertId,
///   factoryId: usine,
///   detail: 'Resolved: belt re-tensioned',
/// );
/// ```
class AuditService {
  AuditService({
    FirebaseDatabase? database,
    FirebaseAuth? auth,
    AppLogger logger = const AppLogger(),
  })  : _databaseOverride = database,
        _authOverride = auth,
        _logger = logger;

  /// Shared instance for app-wide use. Tests can construct their own with
  /// injected Firebase mocks.
  static final AuditService instance = AuditService();

  final FirebaseDatabase? _databaseOverride;
  final FirebaseAuth? _authOverride;
  final AppLogger _logger;

  // Resolved lazily: merely referencing `AuditService.instance` must never
  // touch Firebase (so unit tests and any pre-init call site are safe). If
  // Firebase is unavailable, the getter throws *inside* log()/_resolveRole,
  // where it is caught — it never propagates to the calling action.
  FirebaseDatabase get _db => _databaseOverride ?? FirebaseDatabase.instance;
  FirebaseAuth get _auth => _authOverride ?? FirebaseAuth.instance;

  /// Cached `uid -> role`, populated lazily and refreshable at sign-in.
  final Map<String, String> _roleCache = <String, String>{};

  /// Optionally seed the actor's role at sign-in so the first audit write does
  /// not pay for a role lookup. Safe to call repeatedly.
  void setActorRole(String uid, String? role) {
    if (role != null && role.trim().isNotEmpty) {
      _roleCache[uid] = role.trim();
    }
  }

  /// Records a single audit entry. Never throws; returns once the write has
  /// been attempted (callers may `await` it or fire-and-forget).
  Future<void> log({
    required String action,
    String? targetType,
    String? targetId,
    String? factoryId,
    String? detail,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final user = _auth.currentUser;
      final actorId = user?.uid ?? 'unauthenticated';
      final actorName =
          (user?.displayName?.trim().isNotEmpty ?? false)
              ? user!.displayName!.trim()
              : (user?.email ?? actorId);
      final actorRole = await _resolveRole(actorId);

      // Build the record, omitting null/empty fields so the strict
      // schema validator in database.rules.json accepts it.
      final entry = <String, dynamic>{
        'at': DateTime.now().toUtc().toIso8601String(),
        'actorId': actorId,
        'action': action,
        'actorName': actorName,
      };
      if (actorRole != null) entry['actorRole'] = actorRole;
      if (_nonEmpty(targetType)) entry['targetType'] = targetType;
      if (_nonEmpty(targetId)) entry['targetId'] = targetId;
      if (_nonEmpty(factoryId)) entry['factoryId'] = factoryId;
      if (_nonEmpty(detail)) entry['detail'] = _clamp(detail!, 2000);
      if (metadata != null && metadata.isNotEmpty) {
        // The rules validate `metadata` as a string, so encode it.
        entry['metadata'] = _clamp(jsonEncode(metadata), 4000);
      }

      await _db.ref('audit_log').push().set(entry);
    } catch (e, st) {
      // Compliance signal worth surfacing, but must not break the caller.
      _logger.warning('Audit write failed for action "$action"', e, st);
    }
  }

  Future<String?> _resolveRole(String uid) async {
    if (uid == 'unauthenticated') return null;
    final cached = _roleCache[uid];
    if (cached != null) return cached;
    try {
      final snap = await _db.ref('users/$uid/role').get();
      final role = snap.value?.toString();
      if (role != null && role.isNotEmpty) {
        _roleCache[uid] = role;
        return role;
      }
    } catch (_) {
      // Role is best-effort context; absence must not block the audit write.
    }
    return null;
  }

  bool _nonEmpty(String? v) => v != null && v.trim().isNotEmpty;

  String _clamp(String v, int max) => v.length <= max ? v : v.substring(0, max);
}
