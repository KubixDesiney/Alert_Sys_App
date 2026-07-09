import 'dart:async';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:firebase_database/firebase_database.dart';
import 'package:rxdart/rxdart.dart';
import '../models/alert_model.dart';
import '../services/hierarchy_service.dart';
import '../utils/notification_eligibility.dart';
import 'app_logger.dart';
import 'fcm_service.dart';
import 'worker_trigger_queue.dart';

String _defaultDescription(String type) => switch (type) {
  'qualite' => 'Quality control issue detected on the line.',
  'maintenance' => 'Equipment requires maintenance intervention.',
  'defaut_produit' => 'Product defect identified at workstation.',
  'manque_ressource' => 'Resource shortage reported at production post.',
  _ => 'Alert raised — awaiting supervisor assessment.',
};

class AlertService {
  final DatabaseReference _db;
  final HierarchyService? _hierarchyService;
  final AppLogger _logger;

  AlertService({
    DatabaseReference? database,
    HierarchyService? hierarchyService,
    AppLogger logger = const AppLogger(),
  }) : _db = database ?? FirebaseDatabase.instance.ref(),
       _hierarchyService = hierarchyService,
       _logger = logger;

  /// Get hierarchy service (may be null if not injected)
  HierarchyService? get hierarchyService => _hierarchyService;

  Future<WorkerNotificationRef?> _writeNotification(
    String uid,
    Map<String, dynamic> notification,
  ) async {
    final ref = _db.child('notifications/$uid').push();
    final notifId = ref.key;
    if (notifId == null || notifId.isEmpty) return null;
    final payload = Map<String, dynamic>.from(notification)
      ..putIfAbsent('pushSent', () => false);
    await ref.set(payload);
    return WorkerNotificationRef(uid: uid, notifId: notifId);
  }

  Future<void> _triggerNotificationRefs(Iterable<WorkerNotificationRef?> refs) {
    return WorkerTriggerQueue.instance.enqueueNotificationTriggers(
      refs.whereType<WorkerNotificationRef>(),
    );
  }

  /// Supervisors currently engaged on an in-progress alert (owner, assistant,
  /// or valid active claim). Best-effort: on any failure returns an empty set
  /// so targeting stays permissive — the notify worker re-checks busy state at
  /// send time and is the authoritative gate.
  Future<Set<String>> _busySupervisorIds() async {
    try {
      final results = await Future.wait([
        _db.child('alerts').orderByChild('status').equalTo('en_cours').get(),
        _db.child('supervisor_active_alerts').get(),
      ]);
      final enCours = results[0].value;
      final claims = results[1].value;
      return busySupervisorIds(
        enCoursAlerts: enCours is Map ? enCours : const {},
        activeClaims: claims is Map ? claims : const {},
      );
    } catch (e) {
      _logger.warning('Busy-supervisor lookup failed; worker will filter', e);
      return const {};
    }
  }

  /// Idempotent create of one queued new-alert row. The key is deterministic
  /// (`new_alert_<alertId>`) so racing producers converge on a single row:
  /// supervisors hit the create-only database rule on the second write, and
  /// admin producers skip when the row already exists — a duplicate producer
  /// can never reset `pushSent` on a row that already delivered.
  Future<WorkerNotificationRef?> _createNewAlertNotificationRow(
    String uid,
    String alertId,
    Map<String, dynamic> payload,
  ) async {
    final notifId = 'new_alert_$alertId';
    final ref = _db.child('notifications/$uid/$notifId');
    try {
      try {
        final existing = await ref.get();
        if (existing.exists) return null;
      } on FirebaseException {
        // Supervisors cannot read other users' queues; the create-only rule
        // below still guarantees idempotency.
      }
      await ref.set(payload);
      return WorkerNotificationRef(uid: uid, notifId: notifId);
    } on FirebaseException catch (e) {
      if (e.code.toLowerCase().contains('permission')) {
        return null; // create-only rule refused the write: row already exists
      }
      rethrow;
    }
  }

  Future<int> _queueNewAlertPushNotifications({
    required String alertId,
    required String alertType,
    required String description,
    required String usine,
    required int? alertNumber,
    String? factoryId,
  }) async {
    final users = await getAllUsers();
    final busyIds = await _busySupervisorIds();
    final targetFactories = factoryCandidates({
      'usine': usine,
      'factoryId': factoryId,
    });
    final refs = <WorkerNotificationRef>[];
    final nowIso = DateTime.now().toUtc().toIso8601String();
    var alreadyQueued = 0;

    for (final entry in users.entries) {
      final rawUser = entry.value;
      if (rawUser is! Map) continue;
      if (!isEligibleNewAlertRecipient(
        uid: entry.key,
        user: rawUser,
        targetFactories: targetFactories,
        busyIds: busyIds,
      )) {
        continue;
      }

      final ref = await _createNewAlertNotificationRow(entry.key, alertId, {
        'type': 'new_alert',
        'alertId': alertId,
        'alertType': alertType,
        'alertDescription': description,
        'alertNumber': alertNumber,
        'usine': usine,
        if (factoryId != null && factoryId.isNotEmpty) 'factoryId': factoryId,
        'message': 'New alert from $usine: $alertType',
        'timestamp': nowIso,
        'status': 'pending',
        'pushSent': false,
        'pushDeliveryMode': 'notification_queue',
      });
      if (ref != null) {
        refs.add(ref);
      } else {
        alreadyQueued++;
      }
    }

    if (refs.isNotEmpty) {
      await _triggerNotificationRefs(refs);
      await _db.child('alerts/$alertId').update({
        'notificationSent': true,
        'push_sent': true,
        'push_sent_at': nowIso,
        'push_delivery_mode': 'notification_queue',
      });
    }
    // Rows created by a racing producer still count as queued so the caller
    // does not double-buzz through the legacy /alerts fallback.
    return refs.length + alreadyQueued;
  }

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

  Stream<List<AlertModel>> getAlertsWhereAssistant(
    String assistantId, {
    int? limit,
  }) {
    return _db
        .child('alerts')
        .orderByChild('assistantId')
        .equalTo(assistantId)
        .onValue
        .map((event) => _toAlertList(event.snapshot));
  }

  Stream<List<AlertModel>> getAlertsWhereSupervisor(
    String supervisorId, {
    int? limit,
  }) {
    return _db
        .child('alerts')
        .orderByChild('superviseurId')
        .equalTo(supervisorId)
        .onValue
        .map((event) => _toAlertList(event.snapshot));
  }

  Stream<List<AlertModel>> getAlertsForCollaborator(String supervisorId) {
    return _db.child('collaboration_alerts/$supervisorId').onValue.switchMap((
      event,
    ) {
      final raw = event.snapshot.value;
      if (raw == null) return Stream.value(<AlertModel>[]);
      final ids = <String>[];
      if (raw is Map) {
        for (final entry in raw.entries) {
          if (entry.value == true) ids.add(entry.key.toString());
        }
      }
      if (ids.isEmpty) return Stream.value(<AlertModel>[]);

      final streams = ids.map((id) {
        return _db.child('alerts/$id').onValue.map<AlertModel?>((event) {
          final value = event.snapshot.value;
          if (value is! Map) return null;
          return AlertModel.fromMap(id, Map<String, dynamic>.from(value));
        });
      }).toList();

      return Rx.combineLatestList<AlertModel?>(streams).map((items) {
        final alerts = items.whereType<AlertModel>().toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
        return alerts;
      });
    });
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
      final older = alerts.where((a) => a.timestamp.isBefore(before)).toList()
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
        .map(
          (e) => AlertModel.fromMap(e.key, Map<String, dynamic>.from(e.value)),
        )
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
    final isValid = await hierarchyService.validateLocation(
      usine,
      convoyeur,
      poste,
    );
    if (!isValid) {
      throw Exception(
        'Invalid location: Factory "$usine", Conveyor $convoyeur, Station $poste does not exist in hierarchy.',
      );
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
      // App/console-created alerts are stamped as manually raised; SCADA/ingest
      // alerts carry their connector's source instead.
      'source': 'Manual',
      'timestamp': now.toIso8601String(),
      'description': description.trim().isEmpty
          ? _defaultDescription(type)
          : description,
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
    if (alertId != null && alertId.isNotEmpty) {
      try {
        final queued = await _queueNewAlertPushNotifications(
          alertId: alertId,
          alertType: type,
          description: alertData['description'] as String,
          usine: usine,
          alertNumber: alertNumber,
        );
        if (queued == 0) {
          await WorkerTriggerQueue.instance.enqueueAlertTrigger(alertId);
        }
      } catch (e, stackTrace) {
        _logger.warning(
          'Queued new-alert notification fan-out failed; using alert fallback',
          e,
          stackTrace,
        );
        await WorkerTriggerQueue.instance.enqueueAlertTrigger(alertId);
      }
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
    String alertId,
    String superviseurId,
    String superviseurName,
  ) async {
    // Auto-clean stale supervisor_active_alerts entries. This happens when an
    // alert was resolved/returned without properly clearing the node (crash,
    // network failure, or a worker-assigned alert that bypassed this path).
    await _cleanupStaleActiveClaim(superviseurId);

    // Block assistants: if this user is currently the assistantId on any
    // active (en_cours) alert they cannot claim a new one. assistantId is
    // indexed in database.rules.json so this query is efficient.
    final assistingSnap = await _db
        .child('alerts')
        .orderByChild('assistantId')
        .equalTo(superviseurId)
        .get();
    if (assistingSnap.exists && assistingSnap.value != null) {
      final raw = assistingSnap.value;
      if (raw is Map) {
        final isActiveAssistant = raw.values.any((v) {
          if (v is! Map) return false;
          return v['status']?.toString() == 'en_cours';
        });
        if (isActiveAssistant) {
          throw Exception(
            'You are currently assisting an active alert. '
            'Please complete or leave that assignment before claiming a new one.',
          );
        }
      }
    }

    final nowIso = DateTime.now().toIso8601String();
    final activeClaimRef = _db.child('supervisor_active_alerts/$superviseurId');
    final activeClaimResult = await activeClaimRef.runTransaction((current) {
      if (current == null) {
        return Transaction.success({'alertId': alertId, 'claimedAt': nowIso});
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

    final alertResult = await _db.child('alerts/$alertId').runTransaction((
      current,
    ) {
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

    // Stop any active buzz notification on this device so the supervisor's
    // phone stops vibrating the moment they claim the alert through the app.
    unawaited(FcmService.cancelAlertBuzz(alertId).catchError((_) {}));
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
    String alertId,
    String supervisorName,
    String? reason,
  ) async {
    final users = await getAllUsers();
    final refs = <WorkerNotificationRef>[];
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
        final ref = await _writeNotification(entry.key, notification);
        if (ref != null) refs.add(ref);
      }
    }
    await _triggerNotificationRefs(refs);
  }

  Future<void> resolveAlert(
    String alertId,
    String reason,
    int elapsedMinutes, {
    String? assistingSupervisorId,
    String? assistingSupervisorName,
  }) async {
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
    await _db.child('supervisor_active_alerts/$supervisorId').runTransaction((
      current,
    ) {
      if (current == null) return Transaction.abort();
      final currentMap = current is Map
          ? Map<String, dynamic>.from(current)
          : <String, dynamic>{};
      if (currentMap['alertId']?.toString() != alertId) {
        return Transaction.abort();
      }
      return Transaction.success(null);
    });
  }

  // Removes a stale supervisor_active_alerts entry before a new claim attempt.
  // Stale entries occur when an alert was resolved/returned by the worker or when
  // the app crashed before the cleanup write completed.
  Future<void> _cleanupStaleActiveClaim(String supervisorId) async {
    if (supervisorId.isEmpty) return;
    final snap = await _db
        .child('supervisor_active_alerts/$supervisorId')
        .get();
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
    String targetUserId,
    Map<String, dynamic> request,
  ) async {
    final notification = Map<String, dynamic>.from(request)
      ..putIfAbsent('pushSent', () => false);
    await _triggerNotificationRefs([
      await _writeNotification(targetUserId, notification),
    ]);
  }

  Future<void> createHelpRequest(
    String alertId,
    String requesterId,
    String requesterName,
    String targetSupervisorId,
  ) async {
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
    await _triggerNotificationRefs([
      await _writeNotification(targetSupervisorId, notification),
    ]);
  }

  Future<void> acceptHelpRequest(
    String alertId,
    String requestId,
    String assistantId,
    String assistantName,
  ) async {
    _logger.debug(
      'acceptHelpRequest: alertId=$alertId, requestId=$requestId, '
      'assistantId=$assistantId, assistantName=$assistantName',
    );
    await _db.child('alerts/$alertId').update({
      'assistantId': assistantId,
      'assistantName': assistantName,
      'helpRequestId': null,
    });
    if (requestId.isNotEmpty) {
      await _db.child('help_requests/$requestId').update({
        'status': 'accepted',
      });
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
      await _triggerNotificationRefs([
        await _writeNotification(requesterId, notification),
      ]);
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
    await _triggerNotificationRefs([
      await _writeNotification(requesterId, notification),
    ]);
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
  /// Push delivery is handled by the Cloudflare notify worker via FCM.
  Future<void> sendNewAlertNotification(
    String alertId,
    String alertType,
    String description,
  ) async {
    final alertSnap = await _db.child('alerts/$alertId').get();
    if (alertSnap.exists && alertSnap.child('notificationSent').value == true) {
      return;
    }

    final usine = alertSnap.child('usine').value?.toString() ?? 'Unknown plant';
    final factoryId = alertSnap.child('factoryId').value?.toString();
    final rawAlertNumber = alertSnap.child('alertNumber').value;
    final alertNumber = rawAlertNumber is num
        ? rawAlertNumber.toInt()
        : int.tryParse(rawAlertNumber?.toString() ?? '');
    try {
      final queued = await _queueNewAlertPushNotifications(
        alertId: alertId,
        alertType: alertType,
        description: description,
        usine: usine,
        alertNumber: alertNumber,
        factoryId: factoryId,
      );
      if (queued == 0) {
        await WorkerTriggerQueue.instance.enqueueAlertTrigger(alertId);
      }
    } catch (e, stackTrace) {
      _logger.warning(
        'Stream new-alert notification fan-out failed; using alert fallback',
        e,
        stackTrace,
      );
      await WorkerTriggerQueue.instance.enqueueAlertTrigger(alertId);
    }
  }
}
