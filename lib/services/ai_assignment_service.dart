// lib/services/ai_assignment_service.dart
//
// Rule-based AI assignment engine for the Production Manager Alerts tab.
// When enabled, scans unassigned alerts and assigns the best supervisor based
// on a weighted scoring model. Records every decision with a confidence score,
// reason breakdown, and "why not others" snapshot. Supports cooldown,
// throttling, opt-out, abort, and rejection feedback.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/alert_model.dart';
import '../models/user_model.dart';
import '../utils/factory_id.dart';

enum AILogStatus { success, skipped, recommended, rejected, aborted }

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
  static const String _prefFactoryKeyPrefix = 'ai_assignment_enabled_factory_';
  static const Duration _throttleInterval = Duration(milliseconds: 800);
  static const Duration _cooldownDuration = Duration(minutes: 5);
  static const Duration _defaultSkippedTtl = Duration(minutes: 20);
  static const int _maxLogs = 100;

  final DatabaseReference _db = FirebaseDatabase.instance.ref();

  bool _enabled = false;
  bool _initialized = false;
  bool _processing = false;
  bool _remoteSettingsAvailable = true;
  bool _feedbackAvailable = true;
  bool _decisionStoreAvailable = true;
  Duration _skippedAlertTtl = _defaultSkippedTtl;

  final List<AILogEntry> _logs = [];
  final Set<String> _inFlight = {};
  final Map<String, DateTime> _skippedAlertIds = {};
  final Map<String, DateTime> _supervisorCooldown = {};
  final Set<String> _capturedResolvedFeedback = {};
  final Map<String, _FeedbackSummary> _feedbackSummary = {};
  final Map<String, bool> _factoryEnabledCache = {};
  StreamSubscription<DatabaseEvent>? _masterSubscription;
  StreamSubscription<DatabaseEvent>? _settingsSubscription;
  DateTime? _lastAssignmentTime;
  String? _factoryId;
  String? _settingsPath;

  bool get enabled => _enabled;
  bool get isUsingBackendSettings => _remoteSettingsAvailable;

  /// Logs ordered newest-first.
  List<AILogEntry> get logs => List.unmodifiable(_logs.reversed);

  static String confidenceLabel(double confidence) {
    if (confidence < 0.50) return 'Weak match';
    if (confidence <= 0.70) return 'Acceptable match';
    if (confidence <= 0.85) return 'Strong match';
    return 'Excellent match';
  }

  static String confidenceScaleDescription(double confidence) {
    if (confidence < 0.50) {
      return 'Below 0.50: weak match';
    }
    if (confidence <= 0.70) {
      return '0.50 to 0.70: acceptable match';
    }
    if (confidence <= 0.85) {
      return '0.70 to 0.85: strong match';
    }
    return 'Above 0.85: excellent match';
  }

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    final prefs = await SharedPreferences.getInstance();
    final fallbackCachedEnabled = prefs.getBool(_prefKey) ?? false;

    try {
      final masterSnap = await _db.child('ai_master').get();
      if (masterSnap.exists && masterSnap.value is Map) {
        final map = Map<String, dynamic>.from(masterSnap.value as Map);
        _enabled = map['enabled'] == true;
      } else {
        _enabled = fallbackCachedEnabled;
        await _db.child('ai_master').set({
          'enabled': _enabled,
          'enabledBy': FirebaseAuth.instance.currentUser?.uid ?? 'unknown',
          'enabledAt': DateTime.now().toIso8601String(),
          'updatedAt': DateTime.now().toIso8601String(),
        });
      }
      _remoteSettingsAvailable = true;
    } catch (e) {
      _enabled = fallbackCachedEnabled;
      if (_isPermissionDenied(e)) {
        _remoteSettingsAvailable = false;
      }
    }

    _masterSubscription?.cancel();
    if (_remoteSettingsAvailable) {
      _masterSubscription = _db.child('ai_master').onValue.listen(
        (event) {
          final value = event.snapshot.value;
          if (value == null || value is! Map) return;
          final map = Map<String, dynamic>.from(value);
          _enabled = map['enabled'] == true;
          prefs.setBool(_prefKey, _enabled);
          notifyListeners();
        },
        onError: (Object e) {
          if (_isPermissionDenied(e)) {
            _remoteSettingsAvailable = false;
            _masterSubscription?.cancel();
            _masterSubscription = null;
          }
        },
      );
    }

    final resolvedFactory = await _resolveCurrentFactoryIds();
    if (resolvedFactory == null || resolvedFactory.canonicalId.isEmpty) {
      notifyListeners();
      return;
    }

    _factoryId = resolvedFactory.canonicalId;
    _settingsPath = 'factories/${resolvedFactory.canonicalId}/aiConfig';
    final cachedEnabled =
        prefs.getBool('$_prefFactoryKeyPrefix${resolvedFactory.canonicalId}') ??
            fallbackCachedEnabled;

    try {
      final settingsSnap = await _db.child(_settingsPath!).get();
      if (settingsSnap.exists) {
        final map = Map<String, dynamic>.from(settingsSnap.value as Map);
        _factoryEnabledCache[resolvedFactory.canonicalId] =
            map['enabled'] == true;
        final ttl = (map['skippedAlertTtlMinutes'] as num?)?.toInt() ??
            _defaultSkippedTtl.inMinutes;
        _skippedAlertTtl = Duration(minutes: ttl.clamp(1, 240));
        await prefs.setBool(
            '$_prefFactoryKeyPrefix${resolvedFactory.canonicalId}',
            map['enabled'] == true);
      } else if (resolvedFactory.legacyId != null) {
        final legacySnap = await _db
            .child('factories/${resolvedFactory.legacyId}/aiConfig')
            .get();
        if (legacySnap.exists) {
          final map = Map<String, dynamic>.from(legacySnap.value as Map);
          _factoryEnabledCache[resolvedFactory.canonicalId] =
              map['enabled'] == true;
          final ttl = (map['skippedAlertTtlMinutes'] as num?)?.toInt() ??
              _defaultSkippedTtl.inMinutes;
          _skippedAlertTtl = Duration(minutes: ttl.clamp(1, 240));
          await prefs.setBool(
              '$_prefFactoryKeyPrefix${resolvedFactory.canonicalId}',
              map['enabled'] == true);
        } else {
          _factoryEnabledCache[resolvedFactory.canonicalId] = cachedEnabled;
          await _db.child(_settingsPath!).set({
            'enabled': cachedEnabled,
            'enabledBy': FirebaseAuth.instance.currentUser?.uid ?? 'unknown',
            'enabledAt': DateTime.now().toIso8601String(),
            'skippedAlertTtlMinutes': _skippedAlertTtl.inMinutes,
            'updatedAt': DateTime.now().toIso8601String(),
          });
        }
      } else {
        _factoryEnabledCache[resolvedFactory.canonicalId] = cachedEnabled;
        await _db.child(_settingsPath!).set({
          'enabled': cachedEnabled,
          'enabledBy': FirebaseAuth.instance.currentUser?.uid ?? 'unknown',
          'enabledAt': DateTime.now().toIso8601String(),
          'skippedAlertTtlMinutes': _skippedAlertTtl.inMinutes,
          'updatedAt': DateTime.now().toIso8601String(),
        });
      }
    } catch (e) {
      // Backend read failed for current-factory config only.
      if (_isPermissionDenied(e)) {
        _remoteSettingsAvailable = false;
      }
    }

    _settingsSubscription?.cancel();
    if (_remoteSettingsAvailable && _settingsPath != null) {
      _settingsSubscription = _db.child(_settingsPath!).onValue.listen(
        (event) {
          final value = event.snapshot.value;
          if (value == null) return;
          final map = Map<String, dynamic>.from(value as Map);
          final factoryEnabled = map['enabled'] == true;
          if (_factoryId != null) {
            _factoryEnabledCache[_factoryId!] = factoryEnabled;
          }
          final ttl = (map['skippedAlertTtlMinutes'] as num?)?.toInt() ??
              _skippedAlertTtl.inMinutes;
          _skippedAlertTtl = Duration(minutes: ttl.clamp(1, 240));
          prefs.setBool('$_prefFactoryKeyPrefix${_factoryId!}', factoryEnabled);
          notifyListeners();
        },
        onError: (Object e) {
          if (_isPermissionDenied(e)) {
            _remoteSettingsAvailable = false;
            _settingsSubscription?.cancel();
            _settingsSubscription = null;
          }
        },
      );
    }

    notifyListeners();
  }

  Future<void> setEnabled(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    if (_remoteSettingsAvailable) {
      try {
        final nowIso = DateTime.now().toIso8601String();
        final actor = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
        final factoryIds = await _loadFactoryIdsForBulkToggle();

        final updates = <String, dynamic>{
          'ai_master/enabled': v,
          'ai_master/enabledBy': actor,
          'ai_master/enabledAt': nowIso,
          'ai_master/updatedAt': nowIso,
        };

        for (final factoryId in factoryIds) {
          updates['factories/$factoryId/aiConfig/enabled'] = v;
          updates['factories/$factoryId/aiConfig/enabledBy'] = actor;
          updates['factories/$factoryId/aiConfig/enabledAt'] = nowIso;
          updates['factories/$factoryId/aiConfig/updatedAt'] = nowIso;
        }

        await _db.update(updates);
        _enabled = v;
        for (final id in factoryIds) {
          _factoryEnabledCache[id] = v;
          await prefs.setBool('$_prefFactoryKeyPrefix$id', v);
        }
        await prefs.setBool(_prefKey, v);
      } catch (e) {
        debugPrint('AI master toggle failed: $e');
        _enabled = v;
        await prefs.setBool(_prefKey, v);
        if (_isPermissionDenied(e)) {
          _remoteSettingsAvailable = false;
          _masterSubscription?.cancel();
          _masterSubscription = null;
          _settingsSubscription?.cancel();
          _settingsSubscription = null;
        }
      }
    } else {
      // No backend path resolved: temporary local fallback only.
      _enabled = v;
      await prefs.setBool(_prefKey, v);
    }
    notifyListeners();
  }

  Future<void> setSkippedAlertTtlMinutes(int minutes) async {
    final bounded = minutes.clamp(1, 240);
    _skippedAlertTtl = Duration(minutes: bounded);
    if (_remoteSettingsAvailable && _settingsPath != null) {
      try {
        await _db.child(_settingsPath!).update({
          'skippedAlertTtlMinutes': bounded,
          'updatedAt': DateTime.now().toIso8601String(),
        });
      } catch (e) {
        if (_isPermissionDenied(e)) {
          _remoteSettingsAvailable = false;
          _settingsSubscription?.cancel();
          _settingsSubscription = null;
        }
      }
    }
    notifyListeners();
  }

  Future<_ResolvedFactoryIds?> _resolveCurrentFactoryIds() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    try {
      final userSnap = await _db.child('users/${user.uid}').get();
      if (!userSnap.exists || userSnap.value is! Map) return null;

      final userData =
          Map<String, dynamic>.from(userSnap.value as Map<dynamic, dynamic>);

      final rawFactoryId = userData['factoryId']?.toString().trim() ?? '';
      if (rawFactoryId.isNotEmpty) {
        return _ResolvedFactoryIds(
          canonicalId: sanitizeFactoryId(rawFactoryId),
          legacyId: rawFactoryId == sanitizeFactoryId(rawFactoryId)
              ? null
              : rawFactoryId,
        );
      }

      final usine = userData['usine']?.toString().trim() ?? '';
      if (usine.isEmpty) return null;

      final hierarchySnap = await _db.child('hierarchy/factories').get();
      if (hierarchySnap.exists && hierarchySnap.value is Map) {
        final factories = Map<dynamic, dynamic>.from(
            hierarchySnap.value as Map<dynamic, dynamic>);
        for (final entry in factories.entries) {
          final value = entry.value;
          if (value is! Map) continue;
          final factoryMap = Map<dynamic, dynamic>.from(value);
          final name = factoryMap['name']?.toString().trim() ?? '';
          if (name.isNotEmpty && name.toLowerCase() == usine.toLowerCase()) {
            final legacyId = entry.key.toString();
            return _ResolvedFactoryIds(
              canonicalId: sanitizeFactoryId(legacyId),
              legacyId:
                  legacyId == sanitizeFactoryId(legacyId) ? null : legacyId,
            );
          }
        }
      }

      return _ResolvedFactoryIds(
        canonicalId: sanitizeFactoryId(usine),
        legacyId: usine == sanitizeFactoryId(usine) ? null : usine,
      );
    } catch (_) {
      return null;
    }
  }

  /// Called every time the alerts stream emits. Re-evaluates unassigned alerts.
  Future<void> processAlerts(List<AlertModel> alerts) async {
    _clearExpiredSkipped();
    await _captureResolvedOutcomes(alerts);

    if (!_enabled) return;
    if (_processing) return;
    _processing = true;
    try {
      await _refreshFeedbackSummary();

      final candidates = alerts.where((a) {
        return a.status == 'disponible' &&
            (a.superviseurId == null || a.superviseurId!.isEmpty) &&
            !_inFlight.contains(a.id) &&
            !_isSkipped(alertId: a.id);
      }).toList()
        ..sort((a, b) {
          if (a.isCritical != b.isCritical) return a.isCritical ? -1 : 1;
          return a.timestamp.compareTo(b.timestamp);
        });

      if (candidates.isEmpty) return;

      final supervisors = await _fetchActiveSupervisors();

      for (final alert in candidates) {
        final factoryId = _factoryIdForAlert(alert);
        if (!await _isFactoryEnabled(factoryId)) {
          _addLog(_skipLog(alert, 'AI disabled for factory $factoryId'));
          continue;
        }
        await _processOne(alert, supervisors, alerts);
      }
    } catch (e, st) {
      debugPrint('AI processAlerts error: $e\n$st');
    } finally {
      _processing = false;
    }
  }

  Future<void> _processOne(AlertModel alert, List<_SupRecord> supervisors,
      List<AlertModel> allAlerts) async {
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
        _markAlertSkipped(alert.id);
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
      final confidence =
          topSum > 0 ? (best.score / topSum).clamp(0.0, 1.0) : 1.0;

      // Never auto-assign across factories regardless of criticality —
      // always route to PM for review instead.
      if (best.supervisor.usine != alert.usine) {
        await _recordCrossFactoryRecommendation(
          alert: alert,
          best: best,
          confidence: confidence,
          all: candidates,
        );
        _markAlertSkipped(alert.id);
        return;
      }

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
      'pushSent': false,
    });

    if (_decisionStoreAvailable) {
      try {
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
      } catch (e) {
        if (_isPermissionDenied(e)) {
          _decisionStoreAvailable = false;
        }
      }
    }

    await _db.child('alerts/${alert.id}/aiHistory').push().set({
      'event': 'assigned',
      'supervisorId': best.supervisor.id,
      'supervisorName': best.supervisor.fullName,
      'reason': reasonSummary,
      'confidenceLabel': confidenceLabel(confidence),
      'confidenceScale': confidenceScaleDescription(confidence),
      'confidence': confidence,
      'timestamp': now.toIso8601String(),
    });

    // Write aiCooldownUntil so the backend Cloud Function can detect when this
    // supervisor's cooldown expires and retry any waiting unassigned alerts.
    // Without this, only Cloud-Function-initiated assignments trigger the retry.
    await _db
        .child('users/${best.supervisor.id}/aiCooldownUntil')
        .set(now.add(_cooldownDuration).toIso8601String());

    await _recordFeedback(
      eventType: 'accepted_assignment',
      alertId: alert.id,
      supervisorId: best.supervisor.id,
      supervisorName: best.supervisor.fullName,
      details: {
        'confidence': confidence,
        'confidenceLabel': confidenceLabel(confidence),
      },
    );

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
    _markAlertSkipped(log.alertId);
    _logs[idx] = log.copyWith(status: AILogStatus.aborted);
    await _recordFeedback(
      eventType: 'aborted_assignment',
      alertId: log.alertId,
      supervisorId: log.assignedSupervisorId,
      supervisorName: log.assignedSupervisorName,
    );
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
    _markAlertSkipped(alertId);

    try {
      await _db.child('alerts/$alertId/aiHistory').push().set({
        'event': 'rejected',
        'supervisorId': supervisorId,
        'supervisorName': supervisorName,
        'reason': reason ?? 'No reason provided',
        'timestamp': DateTime.now().toIso8601String(),
      });
      await _recordFeedback(
        eventType: 'rejected_assignment',
        alertId: alertId,
        supervisorId: supervisorId,
        supervisorName: supervisorName,
        details: {
          'reason': reason ?? 'No reason provided',
        },
      );
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
              'pushSent': false,
            });
          }
        }
      }
    } catch (e) {
      debugPrint('handleSupervisorRejection error: $e');
    }
  }

  /// PM approval for cross-factory recommendation.
  /// Returns true when the recommendation was applied.
  Future<bool> approveCrossFactoryRecommendation({
    required String alertId,
    String? approverId,
    String? approverName,
  }) async {
    try {
      final snap = await _db.child('alerts/$alertId').get();
      if (!snap.exists || snap.value == null) return false;

      final data = Map<String, dynamic>.from(snap.value as Map);
      final pending = data['aiRecommendationPending'] == true;
      final status = '${data['status'] ?? ''}';
      final currentSupervisor = '${data['superviseurId'] ?? ''}'.trim();
      final recommendedId = '${data['aiRecommendedSupervisorId'] ?? ''}'.trim();
      final recommendedName =
          '${data['aiRecommendedSupervisorName'] ?? ''}'.trim();

      if (!pending || recommendedId.isEmpty) return false;
      if (status != 'disponible' || currentSupervisor.isNotEmpty) {
        debugPrint(
            'approveCrossFactoryRecommendation skipped: alert is no longer assignable ($alertId)');
        return false;
      }

      final actorId = approverId ?? FirebaseAuth.instance.currentUser?.uid;
      final actorName = approverName ??
          FirebaseAuth.instance.currentUser?.email?.split('@').first ??
          'Production Manager';
      final now = DateTime.now();
      final nowIso = now.toIso8601String();

      await _db.child('alerts/$alertId').update({
        'status': 'en_cours',
        'superviseurId': recommendedId,
        'superviseurName':
            recommendedName.isNotEmpty ? recommendedName : 'Supervisor',
        'takenAtTimestamp': nowIso,
        'aiAssigned': true,
        'aiAssignedAt': nowIso,
        'aiRecommendationPending': false,
        'aiRecommendationStatus': 'approved',
        'aiRecommendationApprovedBy': actorName,
        'aiRecommendationApprovedById': actorId,
        'aiRecommendationApprovedAt': nowIso,
      });

      await _db.child('alerts/$alertId/aiHistory').push().set({
        'event': 'recommended_cross_factory_approved',
        'recommendedSupervisorId': recommendedId,
        'recommendedSupervisorName':
            recommendedName.isNotEmpty ? recommendedName : null,
        'approvedBy': actorName,
        'approvedById': actorId,
        'timestamp': nowIso,
      });

      if (_decisionStoreAvailable) {
        try {
          await _db.child('ai_decisions/$alertId').update({
            'decisionMode': 'recommendation_pm_approved',
            'requiresPmApproval': false,
            'assignedTo': recommendedId,
            'assignedToName': recommendedName,
            'approvedBy': actorName,
            'approvedById': actorId,
            'approvedAt': nowIso,
            'timestamp': nowIso,
          });
        } catch (e) {
          if (_isPermissionDenied(e)) {
            _decisionStoreAvailable = false;
          }
        }
      }

      if (recommendedId.isNotEmpty) {
        await _db.child('notifications/$recommendedId').push().set({
          'type': 'ai_assigned',
          'alertId': alertId,
          'message':
              'PM approved AI cross-factory transfer. Alert assigned to you.',
          'timestamp': nowIso,
          'status': 'pending',
          'pushSent': false,
        });
      }

      await _recordFeedback(
        eventType: 'accepted_assignment',
        alertId: alertId,
        supervisorId: recommendedId,
        supervisorName: recommendedName,
        details: {
          'acceptedByPm': true,
          'approvedBy': actorName,
          'approvedById': actorId,
        },
      );

      final idx = _logs.lastIndexWhere(
          (l) => l.alertId == alertId && l.status == AILogStatus.recommended);
      if (idx >= 0) {
        _logs[idx] = _logs[idx].copyWith(status: AILogStatus.success);
      }

      _supervisorCooldown[recommendedId] = now;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('approveCrossFactoryRecommendation error: $e');
      return false;
    }
  }

  /// PM rejection for cross-factory recommendation.
  /// Returns true when the recommendation was declined.
  Future<bool> declineCrossFactoryRecommendation({
    required String alertId,
    String? reason,
    String? approverId,
    String? approverName,
  }) async {
    try {
      final snap = await _db.child('alerts/$alertId').get();
      if (!snap.exists || snap.value == null) return false;

      final data = Map<String, dynamic>.from(snap.value as Map);
      final pending = data['aiRecommendationPending'] == true;
      final recommendedId = '${data['aiRecommendedSupervisorId'] ?? ''}'.trim();
      final recommendedName =
          '${data['aiRecommendedSupervisorName'] ?? ''}'.trim();
      if (!pending) return false;

      final actorId = approverId ?? FirebaseAuth.instance.currentUser?.uid;
      final actorName = approverName ??
          FirebaseAuth.instance.currentUser?.email?.split('@').first ??
          'Production Manager';
      final now = DateTime.now();
      final nowIso = now.toIso8601String();
      final rejectionReason =
          (reason != null && reason.trim().isNotEmpty) ? reason.trim() : null;

      await _db.child('alerts/$alertId').update({
        'aiAssigned': false,
        'aiRecommendationPending': false,
        'aiRecommendationStatus': 'declined',
        'aiRecommendationDeclinedBy': actorName,
        'aiRecommendationDeclinedById': actorId,
        'aiRecommendationDeclinedAt': nowIso,
        'aiRecommendationDeclineReason': rejectionReason,
      });

      await _db.child('alerts/$alertId/aiHistory').push().set({
        'event': 'recommended_cross_factory_declined',
        'recommendedSupervisorId': recommendedId,
        'recommendedSupervisorName':
            recommendedName.isNotEmpty ? recommendedName : null,
        'declinedBy': actorName,
        'declinedById': actorId,
        'reason': rejectionReason,
        'timestamp': nowIso,
      });

      if (_decisionStoreAvailable) {
        try {
          await _db.child('ai_decisions/$alertId').update({
            'decisionMode': 'recommendation_pm_declined',
            'requiresPmApproval': false,
            'declinedBy': actorName,
            'declinedById': actorId,
            'declineReason': rejectionReason,
            'declinedAt': nowIso,
            'timestamp': nowIso,
          });
        } catch (e) {
          if (_isPermissionDenied(e)) {
            _decisionStoreAvailable = false;
          }
        }
      }

      final idx = _logs.lastIndexWhere(
          (l) => l.alertId == alertId && l.status == AILogStatus.recommended);
      if (idx >= 0) {
        _logs[idx] = _logs[idx].copyWith(
          status: AILogStatus.rejected,
          rejectionReason: rejectionReason ?? 'Declined by PM',
        );
      }

      _markAlertSkipped(alertId);
      await _recordFeedback(
        eventType: 'rejected_assignment',
        alertId: alertId,
        supervisorId: recommendedId,
        supervisorName: recommendedName,
        details: {
          'rejectedByPm': true,
          'declinedBy': actorName,
          'declinedById': actorId,
          'reason': rejectionReason,
        },
      );
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('declineCrossFactoryRecommendation error: $e');
      return false;
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
    if (!alert.isCritical) {
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
    final typeResolved = allAlerts
        .where((a) =>
            a.type == alert.type &&
            a.status == 'validee' &&
            (a.superviseurId == sup.id || a.assistantId == sup.id))
        .length;
    if (typeResolved > 0) {
      final bonus = (typeResolved * 4).clamp(0, 40).toDouble();
      score += bonus;
      reasons.add(
          '$typeResolved past ${alert.type} alert${typeResolved > 1 ? 's' : ''} resolved (+${bonus.toStringAsFixed(0)})');
    } else {
      reasons.add('No prior ${alert.type} experience (0)');
    }

    // Best avg resolution time for this type
    final supTypeAlerts = allAlerts
        .where((a) =>
            a.type == alert.type &&
            a.status == 'validee' &&
            a.elapsedTime != null &&
            a.superviseurId == sup.id)
        .toList();
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
    final stationResolved = allAlerts
        .where((a) =>
            a.usine == alert.usine &&
            a.convoyeur == alert.convoyeur &&
            a.poste == alert.poste &&
            a.status == 'validee' &&
            (a.superviseurId == sup.id || a.assistantId == sup.id))
        .length;
    if (stationResolved > 0) {
      final bonus = (stationResolved * 6).clamp(0, 30).toDouble();
      score += bonus;
      reasons.add(
          '$stationResolved fix${stationResolved > 1 ? 'es' : ''} at this workstation (+${bonus.toStringAsFixed(0)})');
    }

    // Conveyor familiarity (lighter weight)
    final conveyorResolved = allAlerts
        .where((a) =>
            a.usine == alert.usine &&
            a.convoyeur == alert.convoyeur &&
            a.status == 'validee' &&
            (a.superviseurId == sup.id || a.assistantId == sup.id))
        .length;
    if (conveyorResolved > 0) {
      final bonus = (conveyorResolved * 1.5).clamp(0, 15).toDouble();
      score += bonus;
      reasons.add(
          '${conveyorResolved} fix${conveyorResolved > 1 ? 'es' : ''} on Line ${alert.convoyeur} (+${bonus.toStringAsFixed(0)})');
    }

    // Recent load balancing — penalize anyone who already received an AI
    // assignment within the last 10 minutes.
    final recentAssignments = allAlerts
        .where((a) =>
            a.superviseurId == sup.id &&
            a.takenAtTimestamp != null &&
            DateTime.now().difference(a.takenAtTimestamp!) <
                const Duration(minutes: 10))
        .length;
    if (!alert.isCritical && recentAssignments > 0) {
      final penalty = (recentAssignments * 8).toDouble();
      score -= penalty;
      reasons.add(
          'Recent load: $recentAssignments assignment${recentAssignments > 1 ? 's' : ''} in 10min (−${penalty.toStringAsFixed(0)})');
    }

    // Critical alerts: prefer supervisors with critical-resolution history
    if (alert.isCritical) {
      final criticalResolved = allAlerts
          .where((a) =>
              a.isCritical == true &&
              a.status == 'validee' &&
              a.superviseurId == sup.id)
          .length;
      if (criticalResolved > 0) {
        final bonus = (criticalResolved * 5).clamp(0, 20).toDouble();
        score += bonus;
        reasons.add(
            'Resolved $criticalResolved critical alert${criticalResolved > 1 ? 's' : ''} (+${bonus.toStringAsFixed(0)})');
      }
    }

    final fb = _feedbackSummary[sup.id];
    if (fb != null) {
      final bonus = fb.rankAdjustment;
      if (bonus != 0) {
        score += bonus;
        reasons.add(
            'Feedback adjustment (${bonus >= 0 ? '+' : ''}${bonus.toStringAsFixed(0)})');
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

  String _factoryIdForAlert(AlertModel alert) => sanitizeFactoryId(alert.usine);

  Future<bool> _isFactoryEnabled(String factoryId) async {
    final cached = _factoryEnabledCache[factoryId];
    if (factoryId == _factoryId && cached != null) return cached;

    try {
      final snap =
          await _db.child('factories/$factoryId/aiConfig/enabled').get();
      final enabled = snap.exists && snap.value == true;
      if (factoryId == _factoryId) {
        _factoryEnabledCache[factoryId] = enabled;
      }
      return enabled;
    } catch (e) {
      if (_isPermissionDenied(e)) {
        debugPrint(
            'AI factory read permission denied at factories/$factoryId/aiConfig/enabled');
      }
      return false;
    }
  }

  Future<Set<String>> _loadFactoryIdsForBulkToggle() async {
    final ids = <String>{};

    final hierarchySnap = await _db.child('hierarchy/factories').get();
    if (hierarchySnap.exists && hierarchySnap.value is Map) {
      final map = Map<dynamic, dynamic>.from(hierarchySnap.value as Map);
      for (final entry in map.entries) {
        ids.add(sanitizeFactoryId(entry.key.toString()));
      }
    }

    final factoriesSnap = await _db.child('factories').get();
    if (factoriesSnap.exists && factoriesSnap.value is Map) {
      final map = Map<dynamic, dynamic>.from(factoriesSnap.value as Map);
      for (final entry in map.entries) {
        final id = sanitizeFactoryId(entry.key.toString());
        if (id.isNotEmpty) ids.add(id);
      }
    }

    if (_factoryId != null && _factoryId!.isNotEmpty) {
      ids.add(_factoryId!);
    }

    return ids;
  }

  bool _isSkipped({required String alertId}) {
    final until = _skippedAlertIds[alertId];
    if (until == null) return false;
    if (DateTime.now().isAfter(until)) {
      _skippedAlertIds.remove(alertId);
      return false;
    }
    return true;
  }

  void _markAlertSkipped(String alertId) {
    _skippedAlertIds[alertId] = DateTime.now().add(_skippedAlertTtl);
  }

  void _clearExpiredSkipped() {
    final now = DateTime.now();
    final expired = _skippedAlertIds.entries
        .where((e) => now.isAfter(e.value))
        .map((e) => e.key)
        .toList();
    for (final id in expired) {
      _skippedAlertIds.remove(id);
    }
  }

  Future<void> _recordCrossFactoryRecommendation({
    required AlertModel alert,
    required AICandidate best,
    required double confidence,
    required List<AICandidate> all,
  }) async {
    final now = DateTime.now();
    final reasonSummary = best.reasons.join(' • ');
    await _db.child('alerts/${alert.id}').update({
      'aiAssigned': false,
      'aiRecommendationPending': true,
      'aiRecommendationStatus': 'pending_pm_approval',
      'aiRecommendedSupervisorId': best.supervisor.id,
      'aiRecommendedSupervisorName': best.supervisor.fullName,
      'aiRecommendationReason':
          'Critical cross-factory recommendation requires PM confirmation',
      'aiAssignmentReason': reasonSummary,
      'aiConfidence': confidence,
      'aiAssignedAt': now.toIso8601String(),
    });

    if (_decisionStoreAvailable) {
      try {
        await _db.child('ai_decisions/${alert.id}').set({
          'alertId': alert.id,
          'decisionMode': 'recommendation_only',
          'requiresPmApproval': true,
          'assignedTo': null,
          'recommendedTo': best.supervisor.id,
          'recommendedToName': best.supervisor.fullName,
          'confidence': confidence,
          'confidenceLabel': confidenceLabel(confidence),
          'confidenceScale': confidenceScaleDescription(confidence),
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
      } catch (e) {
        if (_isPermissionDenied(e)) {
          debugPrint(
              'AI decision write permission denied at ai_decisions/${alert.id}');
          _decisionStoreAvailable = false;
        }
      }
    }

    await _db.child('alerts/${alert.id}/aiHistory').push().set({
      'event': 'recommended_cross_factory',
      'recommendedSupervisorId': best.supervisor.id,
      'recommendedSupervisorName': best.supervisor.fullName,
      'reason': reasonSummary,
      'requiresPmApproval': true,
      'confidence': confidence,
      'confidenceLabel': confidenceLabel(confidence),
      'confidenceScale': confidenceScaleDescription(confidence),
      'timestamp': now.toIso8601String(),
    });

    final usersSnap = await _db.child('users').get();
    if (usersSnap.exists) {
      final users = Map<String, dynamic>.from(usersSnap.value as Map);
      for (final entry in users.entries) {
        final u = Map<String, dynamic>.from(entry.value as Map);
        if (u['role'] == 'admin') {
          await _db.child('notifications/${entry.key}').push().set({
            'type': 'ai_cross_factory_recommendation',
            'alertId': alert.id,
            'recommendedSupervisorId': best.supervisor.id,
            'recommendedSupervisorName': best.supervisor.fullName,
            'message':
                'AI recommends cross-factory assignment for critical alert ${alert.id}. PM confirmation required.',
            'reason': reasonSummary,
            'confidence': confidence,
            'confidenceLabel': confidenceLabel(confidence),
            'timestamp': now.toIso8601String(),
            'status': 'pending',
            'pushSent': false,
          });
        }
      }
    }

    _addLog(AILogEntry(
      id: _genId(),
      alertId: alert.id,
      alertLabel: _alertLabel(alert),
      alertType: alert.type,
      alertUsine: alert.usine,
      assignedSupervisorId: best.supervisor.id,
      assignedSupervisorName: best.supervisor.fullName,
      reason:
          'Cross-factory critical recommendation queued for PM approval (not auto-finalized)',
      reasonBreakdown: [
        ...best.reasons,
        'Policy: critical cross-factory assignment requires PM confirmation'
      ],
      consideredCandidates: all,
      confidence: confidence,
      timestamp: now,
      status: AILogStatus.recommended,
      rejectionReason: null,
    ));
  }

  Future<void> _recordFeedback({
    required String eventType,
    required String alertId,
    String? supervisorId,
    String? supervisorName,
    Map<String, dynamic>? details,
  }) async {
    if (!_feedbackAvailable) return;
    final now = DateTime.now();
    final event = {
      'eventType': eventType,
      'alertId': alertId,
      'supervisorId': supervisorId,
      'supervisorName': supervisorName,
      'timestamp': now.toIso8601String(),
      'details': details ?? <String, dynamic>{},
    };
    try {
      await _db.child('ai_feedback/events').push().set(event);

      if (supervisorId != null && supervisorId.isNotEmpty) {
        final summaryRef = _db.child('ai_feedback/summary/$supervisorId');
        final summarySnap = await summaryRef.get();
        final summary = summarySnap.exists
            ? Map<String, dynamic>.from(summarySnap.value as Map)
            : <String, dynamic>{};

        int current(String k) => (summary[k] as num?)?.toInt() ?? 0;
        final updates = <String, dynamic>{
          'supervisorId': supervisorId,
          'supervisorName': supervisorName,
          'updatedAt': now.toIso8601String(),
        };
        switch (eventType) {
          case 'accepted_assignment':
            updates['acceptedAssignments'] = current('acceptedAssignments') + 1;
            break;
          case 'rejected_assignment':
            updates['rejectedAssignments'] = current('rejectedAssignments') + 1;
            break;
          case 'aborted_assignment':
            updates['abortedAssignments'] = current('abortedAssignments') + 1;
            break;
          case 'resolved_outcome':
            updates['resolvedOutcomes'] = current('resolvedOutcomes') + 1;
            break;
        }
        await summaryRef.update(updates);
      }
    } catch (e) {
      if (_isPermissionDenied(e)) {
        debugPrint('AI feedback write permission denied at ai_feedback/events');
        _feedbackAvailable = false;
      }
    }
  }

  Future<void> _captureResolvedOutcomes(List<AlertModel> alerts) async {
    if (!_feedbackAvailable) return;
    for (final alert in alerts) {
      if (alert.status != 'validee' || alert.superviseurId == null) continue;
      if (!alert.aiAssigned) continue;
      if (_capturedResolvedFeedback.contains(alert.id)) continue;

      try {
        await _recordFeedback(
          eventType: 'resolved_outcome',
          alertId: alert.id,
          supervisorId: alert.superviseurId,
          supervisorName: alert.superviseurName,
          details: {
            'elapsedTime': alert.elapsedTime,
            'resolutionReason': alert.resolutionReason,
          },
        );

        await _db.child('alerts/${alert.id}/aiHistory').push().set({
          'event': 'resolved_outcome',
          'supervisorId': alert.superviseurId,
          'supervisorName': alert.superviseurName,
          'elapsedTime': alert.elapsedTime,
          'timestamp': DateTime.now().toIso8601String(),
        });
        _capturedResolvedFeedback.add(alert.id);
      } catch (e) {
        if (_isPermissionDenied(e)) {
          debugPrint(
              'AI feedback write permission denied at ai_feedback/summary');
          _feedbackAvailable = false;
          return;
        }
      }
    }
  }

  Future<void> _refreshFeedbackSummary() async {
    if (!_feedbackAvailable) {
      _feedbackSummary.clear();
      return;
    }
    try {
      final snap = await _db.child('ai_feedback/summary').get();
      if (!snap.exists) {
        _feedbackSummary.clear();
        return;
      }
      final map = Map<String, dynamic>.from(snap.value as Map);
      _feedbackSummary
        ..clear()
        ..addEntries(map.entries.map((e) {
          return MapEntry(
            e.key,
            _FeedbackSummary.fromMap(Map<String, dynamic>.from(e.value as Map)),
          );
        }));
    } catch (e) {
      if (_isPermissionDenied(e)) {
        debugPrint('AI feedback read permission denied at ai_feedback/summary');
        _feedbackAvailable = false;
        _feedbackSummary.clear();
      }
    }
  }

  bool _isPermissionDenied(Object error) {
    final msg = error.toString().toLowerCase();
    return msg.contains('permission-denied') ||
        msg.contains('permission_denied') ||
        msg.contains('permission denied');
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

  String _genId() => '${DateTime.now().microsecondsSinceEpoch}_${_logs.length}';

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

  @override
  void dispose() {
    _masterSubscription?.cancel();
    _settingsSubscription?.cancel();
    super.dispose();
  }
}

class _ResolvedFactoryIds {
  final String canonicalId;
  final String? legacyId;

  _ResolvedFactoryIds({required this.canonicalId, this.legacyId});
}

class _SupRecord {
  final UserModel user;
  final bool aiOptOut;
  _SupRecord({required this.user, required this.aiOptOut});
}

class _FeedbackSummary {
  final int acceptedAssignments;
  final int rejectedAssignments;
  final int abortedAssignments;
  final int resolvedOutcomes;

  _FeedbackSummary({
    required this.acceptedAssignments,
    required this.rejectedAssignments,
    required this.abortedAssignments,
    required this.resolvedOutcomes,
  });

  factory _FeedbackSummary.fromMap(Map<String, dynamic> map) {
    return _FeedbackSummary(
      acceptedAssignments: (map['acceptedAssignments'] as num?)?.toInt() ?? 0,
      rejectedAssignments: (map['rejectedAssignments'] as num?)?.toInt() ?? 0,
      abortedAssignments: (map['abortedAssignments'] as num?)?.toInt() ?? 0,
      resolvedOutcomes: (map['resolvedOutcomes'] as num?)?.toInt() ?? 0,
    );
  }

  double get rankAdjustment {
    final value = (acceptedAssignments * 2.0) +
        (resolvedOutcomes * 3.0) -
        (rejectedAssignments * 2.0) -
        (abortedAssignments * 1.5);
    return value.clamp(-20.0, 20.0);
  }
}
