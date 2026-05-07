/// In-memory bookkeeping for the AI assignment loop. Owns four pieces of
/// transient state that previously lived as private fields on
/// `AIAssignmentService`:
///
/// * **In-flight set** — alert IDs currently being processed, used to avoid
///   double-assignment when multiple cron ticks overlap.
/// * **Skipped-alerts map** — alert IDs that the engine could not assign
///   (no eligible candidate or cross-factory) plus the wall-clock instant the
///   skip TTL expires. Acts as a short-lived deny list so the engine doesn't
///   re-evaluate the same alert every tick.
/// * **Supervisor cooldown map** — per-supervisor timestamps used by the
///   scoring engine to skip recently-rejected supervisors.
/// * **Processed history set** — `aiHistory` action IDs already replayed on
///   reconnect, guarding against duplicate processing.
///
/// The class is deliberately Firebase- and singleton-free so it can be unit
/// tested. Callers pass the TTL in instead of reading from preferences.
class AIStateManager {
  AIStateManager({Duration skippedAlertTtl = const Duration(minutes: 20)})
      : _skippedAlertTtl = skippedAlertTtl;

  Duration _skippedAlertTtl;

  final Set<String> _inFlight = {};
  final Map<String, DateTime> _skippedAlertIds = {};
  final Map<String, DateTime> _supervisorCooldown = {};
  final Set<String> _processedHistoryIds = {};

  Duration get skippedAlertTtl => _skippedAlertTtl;
  set skippedAlertTtl(Duration value) => _skippedAlertTtl = value;

  // ── In-flight ───────────────────────────────────────────────────────────
  bool isInFlight(String alertId) => _inFlight.contains(alertId);
  void markInFlight(String alertId) => _inFlight.add(alertId);
  void clearInFlight(String alertId) => _inFlight.remove(alertId);

  // ── Skipped alerts ──────────────────────────────────────────────────────
  bool isSkipped(String alertId, {DateTime? now}) {
    final until = _skippedAlertIds[alertId];
    if (until == null) return false;
    final clock = now ?? DateTime.now();
    if (clock.isAfter(until)) {
      _skippedAlertIds.remove(alertId);
      return false;
    }
    return true;
  }

  void markSkipped(String alertId, {DateTime? now}) {
    _skippedAlertIds[alertId] = (now ?? DateTime.now()).add(_skippedAlertTtl);
  }

  void clearExpiredSkipped({DateTime? now}) {
    final clock = now ?? DateTime.now();
    final expired = _skippedAlertIds.entries
        .where((e) => clock.isAfter(e.value))
        .map((e) => e.key)
        .toList();
    for (final id in expired) {
      _skippedAlertIds.remove(id);
    }
  }

  // ── Supervisor cooldowns ────────────────────────────────────────────────
  DateTime? cooldownStart(String supervisorId) =>
      _supervisorCooldown[supervisorId];

  void recordCooldown(String supervisorId, {DateTime? at}) {
    _supervisorCooldown[supervisorId] = at ?? DateTime.now();
  }

  // ── Processed AI history ────────────────────────────────────────────────
  bool isHistoryProcessed(String actionId) =>
      _processedHistoryIds.contains(actionId);

  void markHistoryProcessed(String actionId) =>
      _processedHistoryIds.add(actionId);

  /// Reset everything. Used by tests and when the user signs out.
  void clearAll() {
    _inFlight.clear();
    _skippedAlertIds.clear();
    _supervisorCooldown.clear();
    _processedHistoryIds.clear();
  }
}
