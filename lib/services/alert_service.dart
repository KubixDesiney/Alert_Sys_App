import 'package:flutter/foundation.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/alert_model.dart';
import '../services/hierarchy_service.dart';
import 'app_logger.dart';

String _defaultDescription(String type) => switch (type) {
      'qualite' => 'Quality control issue detected on the line.',
      'maintenance' => 'Equipment requires maintenance intervention.',
      'defaut_produit' => 'Product defect identified at workstation.',
      'manque_ressource' => 'Resource shortage reported at production post.',
      _ => 'Alert raised — awaiting supervisor assessment.',
    };

class AlertService {
  final DatabaseReference _db = FirebaseDatabase.instance.ref();
  final HierarchyService? _hierarchyService;
  final AppLogger _logger;

  AlertService({
    HierarchyService? hierarchyService,
    AppLogger logger = const AppLogger(),
  })  : _hierarchyService = hierarchyService,
        _logger = logger;

  /// Get hierarchy service (may be null if not injected)
  HierarchyService? get hierarchyService => _hierarchyService;

  Stream<List<AlertModel>> getAlertsForUsine(String usine, {int? limit}) {
    return _db
        .child('alerts')
        .orderByChild('usine')
        .equalTo(usine)
        .onValue
        .map((event) => _toAlertList(event.snapshot));
  }

  Stream<List<AlertModel>> getAllAlerts({int? limit}) {
    return _db
        .child('alerts')
        .onValue
        .map((event) => _toAlertList(event.snapshot));
  }

  Stream<List<AlertModel>> getAlertsWhereAssistant(String assistantId, {int? limit}) {
    return _db
        .child('alerts')
        .orderByChild('assistantId')
        .equalTo(assistantId)
        .onValue
        .map((event) => _toAlertList(event.snapshot));
  }

  Stream<List<AlertModel>> getAlertsWhereSupervisor(String supervisorId, {int? limit}) {
    return _db
        .child('alerts')
        .orderByChild('superviseurId')
        .equalTo(supervisorId)
        .onValue
        .map((event) => _toAlertList(event.snapshot));
  }

  /// Fetch older alerts before a given timestamp
  Future<List<AlertModel>> fetchOlderAlerts({
    required DateTime before,
    int limit = 50,
  }) async {
    try {
      final snapshot = await _db
          .child('alerts')
          .orderByChild('timestamp')
          .endAt(before.toIso8601String())
          .limitToLast(limit + 1)
          .get();
      return _toAlertList(snapshot);
    } catch (e) {
      _logger.error('Error fetching older alerts: $e');
      return [];
    }
  }

  /// Fetch older alerts for a specific usine before a given timestamp
  Future<List<AlertModel>> fetchOlderAlertsForUsine({
    required String usine,
    required DateTime before,
    int limit = 50,
  }) async {
    try {
      final snapshot = await _db
          .child('alerts')
          .orderByChild('usine')
          .equalTo(usine)
          .get();
      
      final alerts = _toAlertList(snapshot);
      final older = alerts
          .where((a) => a.timestamp.isBefore(before))
          .toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      
      return older.take(limit).toList();
    } catch (e) {
      _logger.error('Error fetching older alerts for usine: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> getHelpRequest(String requestId) async {
    final snapshot = await _db.child('help_requests/$requestId').get();
    if (!snapshot.exists) return {};
    return Map<String, dynamic>.from(snapshot.value as Map);
  }

  List<AlertModel> _toAlertList(DataSnapshot snapshot) {
    final data = snapshot.value;
    if (data == null) return [];
    final map = Map<String, dynamic>.from(data as Map);
    return map.entries
        .map((e) =>
            AlertModel.fromMap(e.key, Map<String, dynamic>.from(e.value)))
        .toList();
  }

  /// Creates an alert only if the location exists in the hierarchy.
  Future<String?> createAlertWithHierarchy({
    required String type,
    required String usine,
    required int convoyeur,
    required int poste,
    required String description,
    bool isCritical = false,
  }) async {
    // Validate against the hierarchy (use injected or create temp)
    final hierarchyService = _hierarchyService ?? HierarchyService();
    final isValid =
        await hierarchyService.validateLocation(usine, convoyeur, poste);
    if (!isValid) {
      throw Exception(
          'Invalid location: Factory "$usine", Conveyor $convoyeur, Station $poste does not exist in hierarchy.');
    }

    final alertNumber = await _reserveNextAlertNumber();

    // Create the alert
    final ref = _db.child('alerts').push();
    final now = DateTime.now().toUtc();
    final alertId = ref.key;
    final alertData = {
      'type': type,
      'usine': usine,
      'convoyeur': convoyeur,
      'poste': poste,
      'alertNumber': alertNumber,
      'adresse': '${usine.replaceAll(' ', '_')}_C${convoyeur}_P$poste',
      'timestamp': now.toIso8601String(),
      'description':
          description.trim().isEmpty ? _defaultDescription(type) : description,
      'status': 'disponible',
      'comments': [],
      'isCritical': isCritical,
      'push_sent': false,
      'superviseurId': null,
      'superviseurName': null,
      'assistantId': null,
      'assistantName': null,
      'resolutionReason': null,
      'resolvedAt': null,
      'elapsedTime': null,
    };
    await ref.set(alertData);
    // Trigger the Cloudflare Worker to send notifications immediately
    try {
      await http.post(
        Uri.parse('https://alert-notifier.aziz-nagati01.workers.dev/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'alertId': alertId}),
      );
    } catch (e) {
      debugPrint(
          'AlertService.createAlertWithHierarchy: worker trigger failed for $alertId: $e');
    }
    return alertId;
  }

  Future<int> _reserveNextAlertNumber() async {
    final result = await _db.child('alertCounter').runTransaction((current) {
      final currentValue = (current as num?)?.toInt() ?? 0;
      return Transaction.success(currentValue + 1);
    });
    final alertNumber = (result.snapshot.value as num?)?.toInt() ?? 0;
    if (!result.committed || alertNumber <= 0) {
      throw Exception('Failed to allocate alert number.');
    }
    return alertNumber;
  }

  Future<void> takeAlert(
      String alertId, String superviseurId, String superviseurName) async {
    // Auto-clean stale supervisor_active_alerts entries. This happens when an
    // alert was resolved/returned without properly clearing the node (crash,
    // network failure, or a worker-assigned alert that bypassed this path).
    await _cleanupStaleActiveClaim(superviseurId);

    final nowIso = DateTime.now().toIso8601String();
    final activeClaimRef = _db.child('supervisor_active_alerts/$superviseurId');
    final activeClaimResult = await activeClaimRef.runTransaction((current) {
      if (current == null) {
        return Transaction.success({
          'alertId': alertId,
          'claimedAt': nowIso,
        });
      }

      final currentMap = current is Map
          ? Map<String, dynamic>.from(current)
          : <String, dynamic>{};
      final currentAlertId = currentMap['alertId']?.toString();
      if (currentAlertId == alertId) {
        return Transaction.success(current);
      }

      return Transaction.abort();
    });

    if (!activeClaimResult.committed) {
      throw Exception(
        'You already have a claimed alert. Please resolve it before claiming a new one.',
      );
    }

    final alertResult = await _db.child('alerts/$alertId').runTransaction((current) {
      if (current == null) return Transaction.abort();
      final currentMap = current is Map
          ? Map<String, dynamic>.from(current)
          : <String, dynamic>{};
      final currentStatus = currentMap['status']?.toString();
      final currentSupervisorId = currentMap['superviseurId']?.toString();
      if (currentStatus != 'disponible' ||
          (currentSupervisorId != null && currentSupervisorId.isNotEmpty)) {
        return Transaction.abort();
      }

      currentMap['status'] = 'en_cours';
      currentMap['superviseurId'] = superviseurId;
      currentMap['superviseurName'] = superviseurName;
      currentMap['takenAtTimestamp'] = nowIso;
      return Transaction.success(currentMap);
    });

    if (!alertResult.committed) {
      await _clearSupervisorActiveAlert(superviseurId, alertId);
      throw Exception('This alert was already claimed by someone else.');
    }
  }

  /// Modify existing returnToQueue
  Future<void> returnToQueue(String alertId, {String? reason}) async {
    final alertSnap = await _db.child('alerts/$alertId').get();
    final alertData = alertSnap.value;
    final superviseurId = alertData is Map
        ? (alertData['superviseurId']?.toString())
        : null;
    final updates = {
      'status': 'disponible',
      'superviseurId': null,
      'superviseurName': null,
      'takenAtTimestamp': null,
    };
    if (reason != null && reason.isNotEmpty) {
      updates['suspendReason'] = reason;
    }
    await _db.child('alerts/$alertId').update(updates);
    await _clearSupervisorActiveAlert(superviseurId, alertId);
  }

  // Add this new method
  Future<void> notifyAdminsAboutSuspend(
      String alertId, String supervisorName, String? reason) async {
    final users = await getAllUsers();
    for (var entry in users.entries) {
      final role = entry.value['role'] ?? 'supervisor';
      if (role == 'admin') {
        final notification = {
          'type': 'alert_suspended',
          'alertId': alertId,
          'supervisorName': supervisorName,
          'reason': reason ?? 'No reason provided',
          'message':
              'Supervisor $supervisorName suspended an alert. ${reason != null ? "Reason: $reason" : ""}',
          'timestamp': DateTime.now().toIso8601String(),
          'status': 'pending',
          'pushSent': false,
        };
        await _db.child('notifications/${entry.key}').push().set(notification);
      }
    }
  }

  Future<void> resolveAlert(String alertId, String reason, int elapsedMinutes,
      {String? assistingSupervisorId, String? assistingSupervisorName}) async {
    final alertSnap = await _db.child('alerts/$alertId').get();
    final alertData = alertSnap.value;
    final superviseurId = alertData is Map
        ? (alertData['superviseurId']?.toString())
        : null;
    final Map<String, dynamic> updates = {
      'status': 'validee',
      'elapsedTime': elapsedMinutes,
      'resolutionReason': reason,
      'resolvedAt': DateTime.now().toIso8601String(),
    };

    // If resolved by a supervisor with assistant help, mark it as assisted for the assistant
    if (assistingSupervisorId != null && assistingSupervisorName != null) {
      updates['wasAssisted'] = true;
      updates['assistedBySupervisorId'] = assistingSupervisorId;
      updates['assistedBySupervisorName'] = assistingSupervisorName;
    }

    updates['aiAssigned'] = false;
    updates['aiAssignedAt'] = null;
    updates['aiAssignmentReason'] = null;
    updates['aiConfidence'] = null;
    updates['aiRecommendationPending'] = false;
    updates['aiRecommendationStatus'] = null;
    updates['aiRecommendedSupervisorId'] = null;
    updates['aiRecommendedSupervisorName'] = null;
    updates['aiRecommendationReason'] = null;

    await _db.child('alerts/$alertId').update(updates);
    await _clearSupervisorActiveAlert(superviseurId, alertId);
  }

  Future<void> _clearSupervisorActiveAlert(
    String? supervisorId,
    String alertId,
  ) async {
    if (supervisorId == null || supervisorId.isEmpty) return;
    await _db.child('supervisor_active_alerts/$supervisorId').runTransaction(
      (current) {
        if (current == null) return Transaction.abort();
        final currentMap = current is Map
            ? Map<String, dynamic>.from(current)
            : <String, dynamic>{};
        if (currentMap['alertId']?.toString() != alertId) {
          return Transaction.abort();
        }
        return Transaction.success(null);
      },
    );
  }

  // Removes a stale supervisor_active_alerts entry before a new claim attempt.
  // Stale entries occur when an alert was resolved/returned by the worker or when
  // the app crashed before the cleanup write completed.
  Future<void> _cleanupStaleActiveClaim(String supervisorId) async {
    if (supervisorId.isEmpty) return;
    final snap =
        await _db.child('supervisor_active_alerts/$supervisorId').get();
    if (!snap.exists || snap.value == null) return;

    final data = snap.value is Map
        ? Map<String, dynamic>.from(snap.value as Map)
        : <String, dynamic>{};
    final storedAlertId = data['alertId']?.toString() ?? '';
    if (storedAlertId.isEmpty) {
      await _db.child('supervisor_active_alerts/$supervisorId').remove();
      return;
    }

    final alertSnap = await _db.child('alerts/$storedAlertId').get();
    if (!alertSnap.exists || alertSnap.value == null) {
      await _db.child('supervisor_active_alerts/$supervisorId').remove();
      return;
    }

    final alertData = Map<String, dynamic>.from(alertSnap.value as Map);
    final status = alertData['status']?.toString() ?? '';
    final assignedTo = alertData['superviseurId']?.toString() ?? '';

    // Clear if the stored alert is no longer active for this supervisor.
    if (status == 'validee' ||
        status == 'cancelled' ||
        assignedTo != supervisorId) {
      await _db.child('supervisor_active_alerts/$supervisorId').remove();
    }
  }

  Future<void> addComment(String alertId, String comment) async {
    final commentsRef = _db.child('alerts/$alertId/comments');
    final newCommentRef = commentsRef.push();
    await newCommentRef.set(comment);
  }

  Future<void> toggleCritical(String alertId, bool isCritical) async {
    await _db.child('alerts/$alertId').update({'isCritical': isCritical});
  }

  Future<void> sendHelpRequest(
      String targetUserId, Map<String, dynamic> request) async {
    final notification = Map<String, dynamic>.from(request)
      ..putIfAbsent('pushSent', () => false);
    await _db.child('notifications/$targetUserId').push().set(notification);
  }

  Future<void> createHelpRequest(String alertId, String requesterId,
      String requesterName, String targetSupervisorId) async {
    final requestId = _db.child('help_requests').push().key!;
    final helpRequest = {
      'alertId': alertId,
      'requesterId': requesterId,
      'requesterName': requesterName,
      'targetSupervisorId': targetSupervisorId,
      'status': 'pending',
      'timestamp': DateTime.now().toIso8601String(),
    };
    await _db.child('help_requests/$requestId').set(helpRequest);
    await _db.child('alerts/$alertId').update({'helpRequestId': requestId});
    final notification = {
      'type': 'help_request',
      'alertId': alertId,
      'message': '$requesterName requested assistance on alert: $alertId',
      'helpRequestId': requestId,
      'timestamp': DateTime.now().toIso8601String(),
      'status': 'pending',
    };
    await _db
        .child('notifications/$targetSupervisorId')
        .push()
        .set(notification);
  }

  Future<void> acceptHelpRequest(String alertId, String requestId,
      String assistantId, String assistantName) async {
    print(
        'acceptHelpRequest: alertId=$alertId, requestId=$requestId, assistantId=$assistantId, assistantName=$assistantName');
    await _db.child('alerts/$alertId').update({
      'assistantId': assistantId,
      'assistantName': assistantName,
      'helpRequestId': null,
    });
    if (requestId.isNotEmpty) {
      await _db
          .child('help_requests/$requestId')
          .update({'status': 'accepted'});
      final helpRequestSnap = await _db.child('help_requests/$requestId').get();
      final requesterId = helpRequestSnap.child('requesterId').value as String;
      final notification = {
        'type': 'help_accepted',
        'alertId': alertId,
        'message': '$assistantName accepted your assistance request',
        'timestamp': DateTime.now().toIso8601String(),
        'status': 'pending',
        'pushSent': false,
      };
      await _db.child('notifications/$requesterId').push().set(notification);
    }
  }

  String createHelpRequestId() {
    return _db.child('help_requests').push().key!;
  }

  Future<void> refuseHelpRequest(String alertId, String requestId) async {
    await _db.child('alerts/$alertId').update({'helpRequestId': null});
    await _db.child('help_requests/$requestId').update({'status': 'refused'});
    final helpRequestSnap = await _db.child('help_requests/$requestId').get();
    final requesterId = helpRequestSnap.child('requesterId').value as String;
    final notification = {
      'type': 'help_refused',
      'alertId': alertId,
      'message': 'Your assistance request was declined',
      'timestamp': DateTime.now().toIso8601String(),
      'status': 'pending',
      'pushSent': false,
    };
    await _db.child('notifications/$requesterId').push().set(notification);
  }

  Future<Map<String, dynamic>> getAllUsers() async {
    final snapshot = await _db.child('users').get();
    if (!snapshot.exists) return {};
    return Map<String, dynamic>.from(snapshot.value as Map);
  }

  Future<void> setCriticalNote(String alertId, String note) async {
    await _db.child('alerts/$alertId').update({'criticalNote': note});
  }

  /// Creates in-app notifications for all supervisors and admins.
  /// OneSignal pushes are now handled by the Cloudflare Worker.
  Future<void> sendNewAlertNotification(
      String alertId, String alertType, String description) async {
    final alertSnap = await _db.child('alerts/$alertId').get();
    if (alertSnap.exists && alertSnap.child('notificationSent').value == true)
      return;

    final usine = alertSnap.child('usine').value?.toString() ?? 'Unknown plant';
    await _db.child('alerts/$alertId').update({'notificationSent': true});

    final users = await getAllUsers();

    for (var entry in users.entries) {
      final role = entry.value['role'] ?? 'supervisor';
      if (role == 'supervisor' || role == 'admin') {
        // Create in-app notification (Firebase only)
        final notification = {
          'type': 'new_alert',
          'alertId': alertId,
          'alertType': alertType,
          'alertDescription': description,
          'usine': usine,
          'message': 'New alert from $usine: $alertType',
          'timestamp': DateTime.now().toIso8601String(),
          'status': 'pending',
          'pushSent': false,
        };
        await _db.child('notifications/${entry.key}').push().set(notification);
      }
    }
  }
}
