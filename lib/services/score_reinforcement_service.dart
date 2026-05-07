import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

import 'ai/score_adjuster.dart';

/// Watches Firebase for resolved alerts and continuously tunes the
/// [ScoreAdjuster] that feeds into [AIScoringEngine].
///
/// Reward signals:
/// | Event                             | Signal |
/// |-----------------------------------|--------|
/// | Resolved faster than ETA          |  +0.5  |
/// | Resolved slower than ETA          |  -0.5  |
/// | aiRejected == true                |  -1.0  |
/// | AI-assigned and resolved          |  +0.2  |
///
/// Accumulated rewards are stored under
/// `ai_feedback/summary/{supervisorId}/reinforcementScore`
/// and the derived scalar adjustment is written to
/// `ai_feedback/adjustments/{supervisorId}` every [recalcInterval].
///
/// The derived adjustment is then pushed into the in-memory [adjuster] so
/// [AIScoringEngine] picks it up on the next scoring call.
class ScoreReinforcementService extends ChangeNotifier {
  ScoreReinforcementService({
    FirebaseDatabase? database,
    required this.adjuster,
    this.recalcInterval = const Duration(minutes: 30),
  }) : _db = database?.ref();

  /// Null only in pure unit-test contexts where no Firebase is available.
  /// All Firebase I/O methods guard on this being non-null before executing.
  final DatabaseReference? _db;
  final ScoreAdjuster adjuster;
  final Duration recalcInterval;

  // Reward weights (kept as named constants for transparency).
  static const double rewardFast = 0.5;
  static const double penaltySlow = -0.5;
  static const double penaltyReject = -1.0;
  static const double rewardAiAssign = 0.2;

  StreamSubscription<DatabaseEvent>? _alertSub;
  Timer? _recalcTimer;
  bool _initialized = false;

  /// Starts the service: loads existing adjustments, subscribes to alert
  /// resolutions, and schedules periodic recalculation.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    await _loadAdjustments();

    if (_db == null) return; // no Firebase in pure-test contexts

    // Listen for individual alert resolution events.
    _alertSub = _db!
        .child('alerts')
        .onChildChanged
        .listen(_onAlertChanged, onError: _onError);

    _recalcTimer = Timer.periodic(recalcInterval, (_) => _recalcAdjustments());
  }

  @override
  void dispose() {
    _alertSub?.cancel();
    _recalcTimer?.cancel();
    super.dispose();
  }

  // ── Reward calculation (public for testability) ─────────────────────────

  /// Computes the reward signal for a single resolved alert data map.
  /// Returns 0.0 if the alert should not produce any signal (e.g. not yet
  /// resolved, or no supervisor attached).
  double computeReward(Map<String, dynamic> alert) {
    if (alert['status'] != 'validee') return 0.0;
    double reward = 0.0;

    // Rejection signal — supervisor declined the AI assignment.
    if (alert['aiRejected'] == true) {
      reward += penaltyReject;
    }

    // AI-assignment positive signal — reward when an AI-assigned alert
    // is eventually resolved (confirms the assignment was useful).
    if (alert['aiAssigned'] == true) {
      reward += rewardAiAssign;
    }

    // Speed signal — compare actual resolution time vs predicted ETA.
    final etaHours = (alert['aiEtaHours'] as num?)?.toDouble();
    if (etaHours != null && etaHours > 0) {
      final takenAtStr = alert['takenAtTimestamp'] as String?;
      final resolvedAtStr = alert['resolvedAt'] as String?;
      if (takenAtStr != null && resolvedAtStr != null) {
        final taken = DateTime.tryParse(takenAtStr);
        final resolved = DateTime.tryParse(resolvedAtStr);
        if (taken != null && resolved != null && resolved.isAfter(taken)) {
          final actualHours = resolved.difference(taken).inMinutes / 60.0;
          reward += actualHours < etaHours ? rewardFast : penaltySlow;
        }
      }
    }

    return reward;
  }

  // ── Firebase I/O ─────────────────────────────────────────────────────────

  void _onAlertChanged(DatabaseEvent event) {
    try {
      final data = event.snapshot.value;
      if (data == null) return;
      final map = Map<String, dynamic>.from(data as Map);
      if (map['status'] != 'validee') return;

      final supId = map['superviseurId'] as String?;
      if (supId == null || supId.isEmpty) return;

      final reward = computeReward(map);
      if (reward == 0.0) return;

      _accumulateReward(supId, reward);
    } catch (e) {
      debugPrint('[Reinforce] _onAlertChanged error: $e');
    }
  }

  /// Increments `ai_feedback/summary/{supervisorId}/reinforcementScore` in
  /// Firebase by [reward], then immediately refreshes the in-memory adjuster.
  Future<void> _accumulateReward(String supervisorId, double reward) async {
    if (_db == null) return;
    try {
      final ref = _db!.child('ai_feedback/summary/$supervisorId');
      final snap = await ref.get();
      final current = snap.exists
          ? Map<String, dynamic>.from(snap.value as Map)
          : <String, dynamic>{};
      final prev =
          (current['reinforcementScore'] as num?)?.toDouble() ?? 0.0;
      final next = prev + reward;
      await ref.update({
        'reinforcementScore': next,
        'updatedAt': DateTime.now().toIso8601String(),
      });
      // Update in-memory adjuster immediately so the next scoring call
      // benefits without waiting for the next periodic recalculation.
      adjuster.setAdjustment(supervisorId, next);
      notifyListeners();
    } catch (e) {
      debugPrint('[Reinforce] _accumulateReward error: $e');
    }
  }

  /// Reads all `reinforcementScore` values from Firebase and writes the
  /// derived scalar to `ai_feedback/adjustments/{supervisorId}`, then syncs
  /// the [adjuster] map.
  Future<void> _recalcAdjustments() async {
    if (_db == null) return;
    try {
      final snap = await _db!.child('ai_feedback/summary').get();
      if (!snap.exists) return;
      final summaries = Map<String, dynamic>.from(snap.value as Map);
      final updates = <String, Object>{};

      for (final entry in summaries.entries) {
        final uid = entry.key;
        final data =
            Map<String, dynamic>.from(entry.value as Map? ?? {});
        final rs = (data['reinforcementScore'] as num?)?.toDouble() ?? 0.0;
        updates[uid] = rs;
        adjuster.setAdjustment(uid, rs);
      }

      if (updates.isNotEmpty) {
        // Write all adjustments in one multi-path update.
        final adjRef = _db!.child('ai_feedback/adjustments');
        await adjRef.set(updates);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[Reinforce] _recalcAdjustments error: $e');
    }
  }

  /// Loads `ai_feedback/adjustments` into the [adjuster] on startup so the
  /// engine benefits from previously computed biases immediately.
  Future<void> _loadAdjustments() async {
    if (_db == null) return;
    try {
      final snap = await _db!.child('ai_feedback/adjustments').get();
      if (!snap.exists) return;
      final raw = Map<String, dynamic>.from(snap.value as Map);
      final parsed = {
        for (final e in raw.entries)
          e.key: (e.value as num?)?.toDouble() ?? 0.0,
      };
      adjuster.loadAll(parsed);
    } catch (e) {
      debugPrint('[Reinforce] _loadAdjustments error: $e');
    }
  }

  void _onError(Object error) {
    debugPrint('[Reinforce] Firebase stream error: $error');
  }

  /// Triggers an immediate recalculation outside the normal timer cadence.
  /// Useful after a manual feedback event or on app foreground resume.
  Future<void> recalcNow() => _recalcAdjustments();
}
