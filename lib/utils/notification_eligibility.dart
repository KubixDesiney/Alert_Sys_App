/// Pure recipient-eligibility logic for new-alert push fan-out.
///
/// Mirrors the send-time gates in `cloudflare_notify_worker.js`
/// (`factoryCandidates` / `factoryMatches` / `engagedSupervisorIds` /
/// `evaluateNotificationDelivery`) so the producer only queues rows the worker
/// would actually deliver. The worker remains the authoritative enforcement
/// point: if anything here cannot be computed (offline, permission), callers
/// fall back to permissive targeting and the worker filters at send time.
library;

/// Firebase-safe factory identifier — mirrors `aiSanitizeFactoryId` in the
/// workers: lowercase, non-alphanumerics collapsed to `_`, trimmed.
String sanitizeFactoryId(Object? input) {
  final collapsed = (input?.toString() ?? '')
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  return collapsed.replaceAll(RegExp(r'^_+|_+$'), '');
}

/// Candidate factory ids of an alert/user record. Records identify their
/// factory inconsistently (factoryId vs usine vs factoryName), so all present
/// fields are expanded and matching is done on any intersection.
Set<String> factoryCandidates(Object? source) {
  final out = <String>{};
  if (source == null) return out;
  if (source is String) {
    final id = sanitizeFactoryId(source);
    if (id.isNotEmpty) out.add(id);
    return out;
  }
  if (source is Map) {
    for (final key in const ['factoryId', 'usine', 'factoryName', 'alertUsine']) {
      final id = sanitizeFactoryId(source[key] ?? '');
      if (id.isNotEmpty) out.add(id);
    }
  }
  return out;
}

/// True when the user belongs to the target factory. An empty target set means
/// the record carries no factory information; blocking there would silently
/// drop the notification for everyone, so it passes instead. An empty user set
/// means the user has no factory assignment and cannot match a factory-scoped
/// alert.
bool factoryMatches(Set<String> targetSet, Set<String> userSet) {
  if (targetSet.isEmpty) return true;
  if (userSet.isEmpty) return false;
  return userSet.any(targetSet.contains);
}

/// Supervisors currently engaged on an in-progress alert: owners and
/// assistants of `en_cours` alerts, plus `supervisor_active_alerts` entries
/// whose claimed alert is still `en_cours`. Stale claim entries pointing at
/// resolved/deleted alerts do NOT mark a supervisor busy — mirrors the
/// worker's `engagedSupervisorIds`.
Set<String> busySupervisorIds({
  required Map<Object?, Object?> enCoursAlerts,
  required Map<Object?, Object?> activeClaims,
}) {
  final ids = <String>{};
  for (final alert in enCoursAlerts.values) {
    if (alert is! Map) continue;
    if (alert['status']?.toString() != 'en_cours') continue;
    final owner = alert['superviseurId']?.toString() ?? '';
    final assistant = alert['assistantId']?.toString() ?? '';
    if (owner.isNotEmpty) ids.add(owner);
    if (assistant.isNotEmpty) ids.add(assistant);
  }
  for (final entry in activeClaims.entries) {
    final claim = entry.value;
    String claimedAlertId = '';
    if (claim is String) {
      claimedAlertId = claim;
    } else if (claim is Map) {
      claimedAlertId = (claim['alertId'] ?? claim['id'] ?? '').toString();
    }
    if (claimedAlertId.isEmpty) continue;
    final alert = enCoursAlerts[claimedAlertId];
    if (alert is Map && alert['status']?.toString() == 'en_cours') {
      ids.add(entry.key.toString());
    }
  }
  return ids;
}

/// Whether one user should receive a new-alert buzz: supervisor role, a
/// registered FCM token, not busy, and assigned to the alert's factory.
bool isEligibleNewAlertRecipient({
  required String uid,
  required Map<Object?, Object?> user,
  required Set<String> targetFactories,
  required Set<String> busyIds,
}) {
  if (user['role']?.toString() != 'supervisor') return false;
  if ((user['fcmToken']?.toString() ?? '').trim().isEmpty) return false;
  if (busyIds.contains(uid)) return false;
  return factoryMatches(targetFactories, factoryCandidates(user));
}
