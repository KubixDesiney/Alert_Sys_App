// lib/services/ai_assignment_service.dart
//
// Rule-based AI assignment engine for the Production Manager Alerts tab.
// When enabled, scans unassigned alerts and assigns the best supervisor based
// on a weighted scoring model. Records every decision with a confidence score,
// reason breakdown, and "why not others" snapshot. Supports cooldown,
// throttling, opt-out, abort, and rejection feedback.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/alert_model.dart';
import '../models/user_model.dart';

enum AILogStatus { success, skipped, rejected, aborted }

class AICandidate {
  final UserModel supervisor;
  final double score;
  final List<String> reasons;
  final String? skipReason;

  AICandidate({
    required this.supervisor,
    required this.score,
    required this.reasons,
    this.skipReason,
  });

  bool get eligible => skipReason == null;
}

class AILogEntry {
  final String id;
  final String alertId;
  final String alertLabel;
  final String alertType;
  final String alertUsine;
  final String? assignedSupervisorId;
  final String? assignedSupervisorName;
  final String reason;
  final List<String> reasonBreakdown;
  final List<AICandidate> consideredCandidates;
  final double confidence;
  final DateTime timestamp;
  final AILogStatus status;
  final String? rejectionReason;

  AILogEntry({
    required this.id,
    required this.alertId,
    required this.alertLabel,
    required this.alertType,
    required this.alertUsine,
    this.assignedSupervisorId,
    this.assignedSupervisorName,
    required this.reason,
    required this.reasonBreakdown,
    required this.consideredCandidates,
    required this.confidence,
    required this.timestamp,
    required this.status,
    this.rejectionReason,
  });

  AILogEntry copyWith({AILogStatus? status, String? rejectionReason}) =>
      AILogEntry(
        id: id,
        alertId: alertId,
        alertLabel: alertLabel,
        alertType: alertType,
        alertUsine: alertUsine,
        assignedSupervisorId: assignedSupervisorId,
        assignedSupervisorName: assignedSupervisorName,
        reason: reason,
        reasonBreakdown: reasonBreakdown,
        consideredCandidates: consideredCandidates,
        confidence: confidence,
        timestamp: timestamp,
        status: status ?? this.status,
        rejectionReason: rejectionReason ?? this.rejectionReason,
      );
}

class AIAssignmentService extends ChangeNotifier {
  AIAssignmentService._();
  static final AIAssignmentService instance = AIAssignmentService._();

  static const String _prefKey = 'ai_assignment_enabled';
  static const Duration _throttleInterval = Duration(milliseconds: 800);
  static const Duration _cooldownDuration = Duration(minutes: 5);
  static const int _maxLogs = 100;

  final DatabaseReference _db = FirebaseDatabase.instance.ref();

  bool _enabled = false;
  bool _initialized = false;
  bool _processing = false;

  final List<AILogEntry> _logs = [];
  final Set<String> _inFlight = {};
  final Set<String> _skippedAlertIds = {};
  final Map<String, DateTime> _supervisorCooldown = {};
  DateTime? _lastAssignmentTime;

  bool get enabled => _enabled;

  /// Logs ordered newest-first.
  List<AILogEntry> get logs => List.unmodifiable(_logs.reversed);

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_prefKey) ?? false;
    notifyListeners();
  }

  Future<void> setEnabled(bool v) async {
    _enabled = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, v);
    notifyListeners();
  }

  /// Called every time the alerts stream emits. Re-evaluates unassigned alerts.
  Future<void> processAlerts(List<AlertModel> alerts) async {
    if (!_enabled) return;
    if (_processing) return;
    _processing = true;
    try {
      final candidates = alerts.where((a) {
        return a.status == 'disponible' &&
            (a.superviseurId == null || a.superviseurId!.isEmpty) &&
            !_inFlight.contains(a.id) &&
            !_skippedAlertIds.contains(a.id);
      }).toList()
        ..sort((a, b) {
          if (a.isCritical != b.isCritical) return a.isCritical ? -1 : 1;
          return a.timestamp.compareTo(b.timestamp);
        });

      if (candidates.isEmpty) return;

      final supervisors = await _fetchActiveSupervisors();

      for (final alert in candidates) {
        if (!_enabled) break;
        await _processOne(alert, supervisors, alerts);
      }
    } catch (e, st) {
      debugPrint('AI processAlerts error: $e\n$st');
    } finally {
      _processing = false;
    }
  }

  Future<void> _processOne(AlertModel alert,
      List<_SupRecord> supervisors, List<AlertModel> allAlerts) async {
    if (_lastAssignmentTime != null) {
      final elapsed = DateTime.now().difference(_lastAssignmentTime!);
      if (elapsed < _throttleInterval) {
        await Future.delayed(_throttleInterval - elapsed);
      }
    }
    _inFlight.add(alert.id);

    try {
      // Re-check fresh state to avoid racing manual claim.
      final fresh = await _db.child('alerts/${alert.id}').get();
      if (!fresh.exists) {
        _addLog(_skipLog(alert, 'Alert no longer exists'));
        return;
      }
      final data = Map<String, dynamic>.from(fresh.value as Map);
      if (data['status'] != 'disponible' ||
          (data['superviseurId'] != null &&
              data['superviseurId'].toString().isNotEmpty)) {
        _addLog(_skipLog(alert, 'Alert was claimed before AI could assign'));
        return;
      }

      final candidates = _evaluateAll(alert, supervisors, allAlerts);
      final eligible = candidates.where((c) => c.eligible).toList()
        ..sort((a, b) => b.score.compareTo(a.score));

      if (eligible.isEmpty) {
        _addLog(AILogEntry(
          id: _genId(),
          alertId: alert.id,
          alertLabel: _alertLabel(alert),
          alertType: alert.type,
          alertUsine: alert.usine,
          reason:
              'No eligible supervisor available (busy, opted-out, or in cooldown)',
          reasonBreakdown: candidates
              .map((c) =>
                  '${c.supervisor.fullName}: ${c.skipReason ?? "score ${c.score.toStringAsFixed(0)}"}')
              .toList(),
          consideredCandidates: candidates,
          confidence: 0,
          timestamp: DateTime.now(),
          status: AILogStatus.skipped,
        ));
        return;
      }

      final best = eligible.first;
      final topSum = eligible.take(3).fold<double>(0, (s, c) => s + c.score);
      final confidence = topSum > 0 ? (best.score / topSum).clamp(0.0, 1.0) : 1.0;

      await _assignToSupervisor(alert, best, confidence, candidates);
      _supervisorCooldown[best.supervisor.id] = DateTime.now();
      _lastAssignmentTime = DateTime.now();
    } catch (e, st) {
      debugPrint('AI assign error for ${alert.id}: $e\n$st');
      _addLog(_skipLog(alert, 'Internal error: $e'));
    } finally {
      _inFlight.remove(alert.id);
    }
  }

  Future<void> _assignToSupervisor(AlertModel alert, AICandidate best,
      double confidence, List<AICandidate> all) async {
    final reasonSummary = best.reasons.join(' • ');
    final now = DateTime.now();

    await _db.child('alerts/${alert.id}').update({
      'status': 'en_cours',
      'superviseurId': best.supervisor.id,
      'superviseurName': best.supervisor.fullName,
      'takenAtTimestamp': now.toIso8601String(),
      'aiAssigned': true,
      'aiAssignmentReason': reasonSummary,
      'aiConfidence': confidence,
      'aiAssignedAt': now.toIso8601String(),
    });

    await _db.child('notifications/${best.supervisor.id}').push().set({
      'type': 'ai_assigned',
      'alertId': alert.id,
      'alertType': alert.type,
      'alertDescription': alert.description,
      'alertUsine': alert.usine,
      'message':
          'Auto-assigned by AI: ${alert.type} at ${alert.usine} (Line ${alert.convoyeur}, Post ${alert.poste})',
      'aiAssigned': true,
      'aiReason': reasonSummary,
      'aiConfidence': confidence,
      'timestamp': now.toIso8601String(),
      'status': 'pending',
    });

    await _db.child('ai_decisions/${alert.id}').set({
      'alertId': alert.id,
      'assignedTo': best.supervisor.id,
      'assignedToName': best.supervisor.fullName,
      'confidence': confidence,
      'reasonSummary': reasonSummary,
      'breakdown': best.reasons,
      'consideredCandidates': all
          .map((c) => {
                'supervisorId': c.supervisor.id,
                'name': c.supervisor.fullName,
                'usine': c.supervisor.usine,
                'score': c.score,
                'reasons': c.reasons,
                'skipReason': c.skipReason,
              })
          .toList(),
      'timestamp': now.toIso8601String(),
    });

    await _db.child('alerts/${alert.id}/aiHistory').push().set({
      'event': 'assigned',
      'supervisorId': best.supervisor.id,
      'supervisorName': best.supervisor.fullName,
      'reason': reasonSummary,
      'confidence': confidence,
      'timestamp': now.toIso8601String(),
    });

    _addLog(AILogEntry(
      id: _genId(),
      alertId: alert.id,
      alertLabel: _alertLabel(alert),
      alertType: alert.type,
      alertUsine: alert.usine,
      assignedSupervisorId: best.supervisor.id,
      assignedSupervisorName: best.supervisor.fullName,
      reason: reasonSummary,
      reasonBreakdown: best.reasons,
      consideredCandidates: all,
      confidence: confidence,
      timestamp: now,
      status: AILogStatus.success,
    ));
  }

  /// Aborts a successful AI assignment: returns the alert to disponible and
  /// keeps AI running for future alerts.
  Future<void> abort(String logId) async {
    final idx = _logs.indexWhere((l) => l.id == logId);
    if (idx < 0) return;
    final log = _logs[idx];
    if (log.status != AILogStatus.success) return;

    try {
      final snap = await _db.child('alerts/${log.alertId}').get();
      if (snap.exists) {
        final data = Map<String, dynamic>.from(snap.value as Map);
        if (data['status'] == 'en_cours' &&
            data['superviseurId'] == log.assignedSupervisorId) {
          await _db.child('alerts/${log.alertId}').update({
            'status': 'disponible',
            'superviseurId': null,
            'superviseurName': null,
            'takenAtTimestamp': null,
            'aiAssigned': false,
            'aiAborted': true,
            'aiAbortedAt': DateTime.now().toIso8601String(),
          });
          await _db.child('alerts/${log.alertId}/aiHistory').push().set({
            'event': 'aborted',
            'previousSupervisorId': log.assignedSupervisorId,
            'timestamp': DateTime.now().toIso8601String(),
          });
        }
      }
    } catch (e) {
      debugPrint('AI abort error: $e');
    }

    // Don't re-pick this alert automatically (operator already intervened).
    _skippedAlertIds.add(log.alertId);
    _logs[idx] = log.copyWith(status: AILogStatus.aborted);
    notifyListeners();
  }

  /// Called by the supervisor reject flow. Keeps AI running.
  Future<void> recordRejection({
    required String alertId,
    required String supervisorId,
    required String supervisorName,
    String? reason,
  }) async {
    final idx = _logs.indexWhere(
        (l) => l.alertId == alertId && l.status == AILogStatus.success);
    if (idx >= 0) {
      _logs[idx] = _logs[idx].copyWith(
        status: AILogStatus.rejected,
        rejectionReason: reason ?? 'No reason provided',
      );
      notifyListeners();
    }
    _skippedAlertIds.add(alertId);

    try {
      await _db.child('alerts/$alertId/aiHistory').push().set({
        'event': 'rejected',
        'supervisorId': supervisorId,
        'supervisorName': supervisorName,
        'reason': reason ?? 'No reason provided',
        'timestamp': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('AI rejection log error: $e');
    }
  }

  /// Resumes the alert as available so other supervisors can claim. Notifies PMs.
  Future<void> handleSupervisorRejection({
    required String alertId,
    required String supervisorId,
    required String supervisorName,
    String? reason,
  }) async {
    try {
      final snap = await _db.child('alerts/$alertId').get();
      if (!snap.exists) return;
      final data = Map<String, dynamic>.from(snap.value as Map);
      if (data['superviseurId'] != supervisorId) return;

      await _db.child('alerts/$alertId').update({
        'status': 'disponible',
        'superviseurId': null,
        'superviseurName': null,
        'takenAtTimestamp': null,
        'aiAssigned': false,
        'aiRejected': true,
        'aiRejectionReason': reason ?? 'No reason provided',
      });

      await recordRejection(
        alertId: alertId,
        supervisorId: supervisorId,
        supervisorName: supervisorName,
        reason: reason,
      );

      // Notify all admins / PMs
      final usersSnap = await _db.child('users').get();
      if (usersSnap.exists) {
        final users = Map<String, dynamic>.from(usersSnap.value as Map);
        for (final entry in users.entries) {
          final u = Map<String, dynamic>.from(entry.value as Map);
          if (u['role'] == 'admin') {
            await _db.child('notifications/${entry.key}').push().set({
              'type': 'ai_rejection',
              'alertId': alertId,
              'message':
                  '$supervisorName rejected an AI auto-assignment${reason != null && reason.isNotEmpty ? ': $reason' : ''}',
              'rejectionReason': reason ?? 'No reason provided',
              'rejectedBy': supervisorName,
              'timestamp': DateTime.now().toIso8601String(),
              'status': 'pending',
            });
          }
        }
      }
    } catch (e) {
      debugPrint('handleSupervisorRejection error: $e');
    }
  }

  // ── Scoring ───────────────────────────────────────────────────────────────

  List<AICandidate> _evaluateAll(AlertModel alert, List<_SupRecord> supervisors,
      List<AlertModel> allAlerts) {
    return supervisors.map((s) => _evaluateOne(alert, s, allAlerts)).toList();
  }

  AICandidate _evaluateOne(
      AlertModel alert, _SupRecord rec, List<AlertModel> allAlerts) {
    final sup = rec.user;

    // ── Disqualifiers ─────────────────────────────────────────────────────
    if (rec.aiOptOut) {
      return AICandidate(
        supervisor: sup,
        score: 0,
        reasons: const [],
        skipReason: 'Opted out of AI auto-assignment',
      );
    }
    if (sup.status != 'active') {
      return AICandidate(
        supervisor: sup,
        score: 0,
        reasons: const [],
        skipReason: 'Not currently active',
      );
    }
    final hasInProgress = allAlerts.any((a) =>
        a.status == 'en_cours' &&
        (a.superviseurId == sup.id || a.assistantId == sup.id));
    if (hasInProgress) {
      return AICandidate(
        supervisor: sup,
        score: 0,
        reasons: const [],
        skipReason: 'Already has an active alert',
      );
    }
    final cd = _supervisorCooldown[sup.id];
    if (cd != null && DateTime.now().difference(cd) < _cooldownDuration) {
      final remaining = _cooldownDuration - DateTime.now().difference(cd);
      return AICandidate(
        supervisor: sup,
        score: 0,
        reasons: const [],
        skipReason:
            'In cooldown (${remaining.inMinutes}m ${remaining.inSeconds % 60}s remaining)',
      );
    }

    // ── Scoring ───────────────────────────────────────────────────────────
    double score = 0;
    final reasons = <String>[];

    // Same factory → big bonus, different factory → strong penalty
    if (sup.usine == alert.usine) {
      score += 30;
      reasons.add('Same factory (+30)');
    } else {
      score -= 25;
      reasons.add('Different factory (−25)');
    }

    // Type experience: count of resolved alerts of this type
    final typeResolved = allAlerts.where((a) =>
        a.type == alert.type &&
        a.status == 'validee' &&
        (a.superviseurId == sup.id || a.assistantId == sup.id)).length;
    if (typeResolved > 0) {
      final bonus = (typeResolved * 4).clamp(0, 40).toDouble();
      score += bonus;
      reasons.add(
          '$typeResolved past ${alert.type} alert${typeResolved > 1 ? 's' : ''} resolved (+${bonus.toStringAsFixed(0)})');
    } else {
      reasons.add('No prior ${alert.type} experience (0)');
    }

    // Best avg resolution time for this type
    final supTypeAlerts = allAlerts.where((a) =>
        a.type == alert.type &&
        a.status == 'validee' &&
        a.elapsedTime != null &&
        a.superviseurId == sup.id).toList();
    if (supTypeAlerts.isNotEmpty) {
      final avg = supTypeAlerts.fold<int>(0, (s, a) => s + a.elapsedTime!) /
          supTypeAlerts.length;
      // Faster is better; bonus capped at 25.
      final speedBonus = (60 - avg).clamp(0, 25).toDouble();
      score += speedBonus;
      reasons.add(
          'Avg resolution ${avg.toStringAsFixed(0)}min for ${alert.type} (+${speedBonus.toStringAsFixed(0)})');
    }

    // Workstation familiarity
    final stationResolved = allAlerts.where((a) =>
        a.usine == alert.usine &&
        a.convoyeur == alert.convoyeur &&
        a.poste == alert.poste &&
        a.status == 'validee' &&
        (a.superviseurId == sup.id || a.assistantId == sup.id)).length;
    if (stationResolved > 0) {
      final bonus = (stationResolved * 6).clamp(0, 30).toDouble();
      score += bonus;
      reasons.add(
          '$stationResolved fix${stationResolved > 1 ? 'es' : ''} at this workstation (+${bonus.toStringAsFixed(0)})');
    }

    // Conveyor familiarity (lighter weight)
    final conveyorResolved = allAlerts.where((a) =>
        a.usine == alert.usine &&
        a.convoyeur == alert.convoyeur &&
        a.status == 'validee' &&
        (a.superviseurId == sup.id || a.assistantId == sup.id)).length;
    if (conveyorResolved > 0) {
      final bonus = (conveyorResolved * 1.5).clamp(0, 15).toDouble();
      score += bonus;
      reasons.add(
          '${conveyorResolved} fix${conveyorResolved > 1 ? 'es' : ''} on Line ${alert.convoyeur} (+${bonus.toStringAsFixed(0)})');
    }

    // Recent load balancing — penalize anyone who already received an AI
    // assignment within the last 10 minutes.
    final recentAssignments = allAlerts.where((a) =>
        a.superviseurId == sup.id &&
        a.takenAtTimestamp != null &&
        DateTime.now().difference(a.takenAtTimestamp!) <
            const Duration(minutes: 10)).length;
    if (recentAssignments > 0) {
      final penalty = (recentAssignments * 8).toDouble();
      score -= penalty;
      reasons.add(
          'Recent load: $recentAssignments assignment${recentAssignments > 1 ? 's' : ''} in 10min (−${penalty.toStringAsFixed(0)})');
    }

    // Critical alerts: prefer supervisors with critical-resolution history
    if (alert.isCritical) {
      final criticalResolved = allAlerts.where((a) =>
          a.isCritical == true &&
          a.status == 'validee' &&
          a.superviseurId == sup.id).length;
      if (criticalResolved > 0) {
        final bonus = (criticalResolved * 5).clamp(0, 20).toDouble();
        score += bonus;
        reasons.add(
            'Resolved $criticalResolved critical alert${criticalResolved > 1 ? 's' : ''} (+${bonus.toStringAsFixed(0)})');
      }
    }

    return AICandidate(
      supervisor: sup,
      score: score.clamp(0, 1000),
      reasons: reasons,
      skipReason: null,
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<List<_SupRecord>> _fetchActiveSupervisors() async {
    final snap = await _db
        .child('users')
        .orderByChild('role')
        .equalTo('supervisor')
        .get();
    if (!snap.exists) return [];
    final map = Map<String, dynamic>.from(snap.value as Map);
    final out = <_SupRecord>[];
    for (final entry in map.entries) {
      final m = Map<String, dynamic>.from(entry.value as Map);
      m['id'] = entry.key;
      out.add(_SupRecord(
        user: UserModel.fromMap(entry.key, m),
        aiOptOut: m['aiOptOut'] == true,
      ));
    }
    return out;
  }

  void _addLog(AILogEntry entry) {
    _logs.add(entry);
    if (_logs.length > _maxLogs) {
      _logs.removeRange(0, _logs.length - _maxLogs);
    }
    notifyListeners();
  }

  AILogEntry _skipLog(AlertModel alert, String reason) => AILogEntry(
        id: _genId(),
        alertId: alert.id,
        alertLabel: _alertLabel(alert),
        alertType: alert.type,
        alertUsine: alert.usine,
        reason: reason,
        reasonBreakdown: const [],
        consideredCandidates: const [],
        confidence: 0,
        timestamp: DateTime.now(),
        status: AILogStatus.skipped,
      );

  String _alertLabel(AlertModel a) =>
      '${a.type.toUpperCase()} • ${a.usine} L${a.convoyeur}/P${a.poste}';

  String _genId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${_logs.length}';

  AILogEntry? logForAlert(String alertId) {
    for (var i = _logs.length - 1; i >= 0; i--) {
      if (_logs[i].alertId == alertId) return _logs[i];
    }
    return null;
  }

  void clearLogs() {
    _logs.clear();
    notifyListeners();
  }
}

class _SupRecord {
  final UserModel user;
  final bool aiOptOut;
  _SupRecord({required this.user, required this.aiOptOut});
}
