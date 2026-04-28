import 'package:firebase_database/firebase_database.dart';
import 'package:http/http.dart' as http;
import '../models/collaboration_model.dart';

const String _workerNotifyUrl =
    'https://alert-notifier.aziz-nagati01.workers.dev/notify';

class CollaborationService {
  final DatabaseReference _db = FirebaseDatabase.instance.ref();

  // In collaboration_service.dart

  Future<String> createCollaborationRequest({
    required String alertId,
    required String requesterId,
    required String requesterName,
    required List<String> targetSupervisorIds,
    required List<String> targetSupervisorNames,
    required String message,
    required String usine,
    required int convoyeur,
    required int poste,
    required String alertType,
    required String alertDescription,
  }) async {
    // 1. Verify that all target supervisors belong to the same factory as the alert
    final alertSnapshot = await _db.child('alerts/$alertId').get();
    if (!alertSnapshot.exists) {
      throw Exception('Alert not found');
    }
    final alertUsine = alertSnapshot.child('usine').value as String?;
    if (alertUsine == null) {
      throw Exception('Alert has no factory assigned');
    }

    // Verify all target supervisors exist (cross-factory allowed — PM confirms at approval)
    for (int i = 0; i < targetSupervisorIds.length; i++) {
      final supId = targetSupervisorIds[i];
      final supName = targetSupervisorNames[i];
      final supSnapshot = await _db.child('users/$supId').get();
      if (!supSnapshot.exists) {
        throw Exception('Supervisor $supName not found');
      }
    }

    // 2. Original request creation (unchanged)
    final requestId = _db.child('collaboration_requests').push().key!;
    final request = CollaborationRequest(
      id: requestId,
      alertId: alertId,
      requesterId: requesterId,
      requesterName: requesterName,
      targetSupervisorIds: targetSupervisorIds,
      targetSupervisorNames: targetSupervisorNames,
      message: message,
      status: 'pending',
      assistantDecision: 'pending',
      timestamp: DateTime.now(),
      requiresPMApproval: true,
      pmApproved: false,
      usine: usine,
      convoyeur: convoyeur,
      poste: poste,
      alertType: alertType,
      alertDescription: alertDescription,
    );

    final updates = <String, dynamic>{
      'collaboration_requests/$requestId': request.toMap(),
      'alerts/$alertId/collaborationRequestId': requestId,
    };

    for (final targetId in targetSupervisorIds) {
      final notifId = _db.child('notifications/$targetId').push().key!;
      final notification = {
        'type': 'collaboration_request',
        'collabRequestId': requestId,
        'alertId': alertId,
        'requesterName': requesterName,
        'message':
            '$requesterName is requesting collaboration on alert: $alertType',
        'timestamp': DateTime.now().toIso8601String(),
        'status': 'pending',
        'pushSent': false,
      };
      updates['notifications/$targetId/$notifId'] = notification;
    }

    await _db.update(updates);

    // Trigger FCM fan-out so target supervisors receive a push immediately.
    http.post(Uri.parse(_workerNotifyUrl)).ignore();

    return requestId;
  }

  Future<void> cancelCollaborationRequest(
      String requestId, String alertId) async {
    await _db.child('collaboration_requests/$requestId').remove();
    await _db.child('alerts/$alertId').update({'collaborationRequestId': null});
  }

  // Get all collaboration requests (for admin)
  Stream<List<CollaborationRequest>> getAllCollaborationRequests() {
    return _db.child('collaboration_requests').onValue.map((event) {
      final data = event.snapshot.value;
      if (data == null) return <CollaborationRequest>[];
      final map = Map<String, dynamic>.from(data as Map);
      return map.entries
          .map((e) => CollaborationRequest.fromMap(
              e.key, Map<String, dynamic>.from(e.value)))
          .toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    });
  }

  bool _allAssistantsAccepted(CollaborationRequest r) {
    if (r.targetSupervisorIds.isEmpty) return false;
    return r.targetSupervisorIds.every(
      (id) => (r.assistantDecisions[id] ?? 'pending') == 'accepted',
    );
  }

  // Get pending collaboration requests (for admin)
  Stream<List<CollaborationRequest>> getPendingCollaborationRequests() {
    return getAllCollaborationRequests().map((requests) => requests.where((r) {
          return r.pmApproved == false &&
              r.status != 'rejected' &&
              _allAssistantsAccepted(r);
        }).toList());
  }

  Future<void> respondToCollaborationRequest({
    required String requestId,
    required String responderId,
    required String responderName,
    required bool accepted,
  }) async {
    final snapshot = await _db.child('collaboration_requests/$requestId').get();
    if (!snapshot.exists) throw Exception('Collaboration request not found');

    final request = CollaborationRequest.fromMap(
      requestId,
      Map<String, dynamic>.from(snapshot.value as Map),
    );

    if (!request.targetSupervisorIds.contains(responderId)) {
      throw Exception('You are not allowed to respond to this request');
    }
    if (request.pmApproved) {
      throw Exception('This request has already been approved by PM');
    }
    // Allow each individual supervisor to respond exactly once.
    final existingDecision = request.assistantDecisions[responderId];
    if (existingDecision != null && existingDecision != 'pending') {
      throw Exception('You have already responded to this request');
    }

    final nowIso = DateTime.now().toIso8601String();

    // Record this supervisor's individual decision.
    await _db
        .child(
            'collaboration_requests/$requestId/assistantDecisions/$responderId')
        .set(accepted ? 'accepted' : 'refused');

    if (accepted) {
      // First acceptance → update top-level fields and notify.
      if (request.assistantDecision != 'accepted') {
        await _db.child('collaboration_requests/$requestId').update({
          'assistantDecision': 'accepted',
          'assistantId': responderId,
          'assistantName': responderName,
          'assistantRespondedAt': nowIso,
        });

        await _db.child('notifications/${request.requesterId}').push().set({
          'type': 'collaboration_assistant_accepted',
          'collabRequestId': requestId,
          'alertId': request.alertId,
          'responderName': responderName,
          'message':
              '$responderName accepted your collaboration request. Waiting for PM approval.',
          'timestamp': nowIso,
          'status': 'pending',
          'pushSent': false,
        });

        await _notifyAdminsAboutCollabRequest(CollaborationRequest(
          id: request.id,
          alertId: request.alertId,
          requesterId: request.requesterId,
          requesterName: request.requesterName,
          targetSupervisorIds: request.targetSupervisorIds,
          targetSupervisorNames: request.targetSupervisorNames,
          message: request.message,
          status: request.status,
          assistantDecision: 'accepted',
          assistantId: responderId,
          assistantName: responderName,
          assistantRespondedAt: DateTime.parse(nowIso),
          timestamp: request.timestamp,
          requiresPMApproval: request.requiresPMApproval,
          pmApproved: request.pmApproved,
          usine: request.usine,
          convoyeur: request.convoyeur,
          poste: request.poste,
          alertType: request.alertType,
          alertDescription: request.alertDescription,
        ));
      }
    } else {
      // Declined — notify the requester.
      await _db.child('notifications/${request.requesterId}').push().set({
        'type': 'collaboration_refused',
        'collabRequestId': requestId,
        'alertId': request.alertId,
        'responderName': responderName,
        'message': '$responderName declined your collaboration request.',
        'timestamp': nowIso,
        'status': 'pending',
        'pushSent': false,
      });

      // If every targeted supervisor has now refused, mark request as rejected.
      final updatedDecisions =
          Map<String, String>.from(request.assistantDecisions)
            ..[responderId] = 'refused';
      final allRefused = request.targetSupervisorIds
          .every((id) => updatedDecisions[id] == 'refused');
      if (allRefused) {
        await _db.child('collaboration_requests/$requestId').update({
          'assistantDecision': 'refused',
          'status': 'rejected',
          'rejectedBy': responderId,
          'rejectedAt': nowIso,
        });
        await _db.child('alerts/${request.alertId}').update({
          'collaborationRequestId': null,
        });
      }
    }
    // Trigger FCM fan-out so the requester / admins get a push.
    http.post(Uri.parse(_workerNotifyUrl)).ignore();
  }

  /// Remove one assistant from an active collaboration request (PM action).
  Future<void> removeAssistantFromRequest({
    required String requestId,
    required String assistantId,
    required String assistantName,
    required String removedByName,
  }) async {
    final snapshot = await _db.child('collaboration_requests/$requestId').get();
    if (!snapshot.exists) return;
    final request = CollaborationRequest.fromMap(
      requestId,
      Map<String, dynamic>.from(snapshot.value as Map),
    );

    final newIds = List<String>.from(request.targetSupervisorIds)
      ..remove(assistantId);
    final newNames = List<String>.from(request.targetSupervisorNames)
      ..remove(assistantName);

    final updates = <String, dynamic>{
      'targetSupervisorIds': newIds,
      'targetSupervisorNames': newNames,
      'assistantDecisions/$assistantId': null,
    };

    // If this was the accepted assistant, clear top-level acceptance.
    if (request.assistantId == assistantId) {
      updates['assistantDecision'] = 'pending';
      updates['assistantId'] = null;
      updates['assistantName'] = null;
      updates['assistantRespondedAt'] = null;
    }

    await _db.child('collaboration_requests/$requestId').update(updates);

    final nowIso = DateTime.now().toIso8601String();
    // Notify requester.
    await _db.child('notifications/${request.requesterId}').push().set({
      'type': 'collaboration_assistant_removed',
      'collabRequestId': requestId,
      'alertId': request.alertId,
      'message':
          '$removedByName removed $assistantName from the collaboration.',
      'timestamp': nowIso,
      'status': 'pending',
      'pushSent': false,
    });
    // Notify removed assistant.
    await _db.child('notifications/$assistantId').push().set({
      'type': 'collaboration_removed',
      'collabRequestId': requestId,
      'alertId': request.alertId,
      'message': 'You were removed from the collaboration by $removedByName.',
      'timestamp': nowIso,
      'status': 'pending',
      'pushSent': false,
    });
  }

  /// Returns true if the given supervisor already has a pending/active outgoing request.
  Future<bool> hasActiveCollaborationRequest(String requesterId) async {
    final snapshot = await _db.child('collaboration_requests').get();
    if (!snapshot.exists || snapshot.value == null) return false;
    final map = Map<String, dynamic>.from(snapshot.value as Map);
    return map.values.any((raw) {
      final m = Map<String, dynamic>.from(raw as Map);
      return m['requesterId'] == requesterId &&
          m['status'] == 'pending' &&
          (m['pmApproved'] == false || m['pmApproved'] == null);
    });
  }

  // Get collaboration requests for a specific supervisor
  Stream<List<CollaborationRequest>> getCollaborationRequestsForSupervisor(
      String supervisorId) {
    return getAllCollaborationRequests().map((requests) => requests
        .where((r) =>
            r.targetSupervisorIds.contains(supervisorId) ||
            r.requesterId == supervisorId)
        .toList());
  }

  // Approve collaboration request (supervisor or admin)
  Future<void> approveCollaborationRequest(
    String requestId,
    String approverId,
    String approverName,
    bool isPMApproval,
  ) async {
    final snapshot = await _db.child('collaboration_requests/$requestId').get();
    if (!snapshot.exists) return;

    final request = CollaborationRequest.fromMap(
      requestId,
      Map<String, dynamic>.from(snapshot.value as Map),
    );

    if (isPMApproval) {
      if (request.assistantDecision != 'accepted') {
        throw Exception('Assistant must accept before PM approval');
      }
      // PM approval
      await _db.child('collaboration_requests/$requestId').update({
        'pmApproved': true,
        'status': 'approved',
        'approvedBy': approverId,
        'approvedAt': DateTime.now().toIso8601String(),
      });

      // Notify requester
      final notification = {
        'type': 'collaboration_approved',
        'collabRequestId': requestId,
        'alertId': request.alertId,
        'message':
            'Your collaboration request has been approved by Production Manager',
        'timestamp': DateTime.now().toIso8601String(),
        'status': 'pending',
        'pushSent': false,
      };
      await _db
          .child('notifications/${request.requesterId}')
          .push()
          .set(notification);

      // Notify target supervisors
      for (final targetId in request.targetSupervisorIds) {
        final notif = {
          'type': 'collaboration_approved',
          'collabRequestId': requestId,
          'alertId': request.alertId,
          'message':
              'Collaboration request approved. You can now work on this alert.',
          'timestamp': DateTime.now().toIso8601String(),
          'status': 'pending',
          'pushSent': false,
        };
        await _db.child('notifications/$targetId').push().set(notif);
      }

      // If cancels original alert, cancel it
      if (request.cancelsOriginalAlert) {
        await _db.child('alerts/${request.alertId}').update({
          'status': 'cancelled',
          'cancelledReason': 'Replaced by collaboration',
        });
      }
    }
  }

  Future<void> approveCollaborationRequestWithDetails({
    required String requestId,
    required String approverId,
    required String approverName,
    required bool isPMApproval,
    bool confirmTransfer = false,
    bool confirmCancelOriginal = false,
    List<String>? cancelExistingAlertIds,
  }) async {
    final snapshot = await _db.child('collaboration_requests/$requestId').get();
    if (!snapshot.exists) return;

    final request = CollaborationRequest.fromMap(
      requestId,
      Map<String, dynamic>.from(snapshot.value as Map),
    );

    if (isPMApproval) {
      if (request.assistantDecision != 'accepted') {
        throw Exception('Assistant must accept before PM approval');
      }
      // 1. Assign assistant to the collaboration alert (original behaviour)
      final assistantId = request.assistantId ??
          (request.targetSupervisorIds.isNotEmpty
              ? request.targetSupervisorIds.first
              : null);
      final assistantName = request.assistantName ??
          (request.targetSupervisorNames.isNotEmpty
              ? request.targetSupervisorNames.first
              : null);

      // Build list of all accepted collaborators
      final List<Map<String, String>> collaboratorsList = [];
      for (int i = 0; i < request.targetSupervisorIds.length; i++) {
        final id = request.targetSupervisorIds[i];
        final name = request.targetSupervisorNames[i];
        final decision = request.assistantDecisions[id] ?? 'pending';
        if (decision == 'accepted') {
          collaboratorsList.add({'id': id, 'name': name});
        }
      }

      final alertUpdates = <String, dynamic>{
        'collaborators': collaboratorsList,
      };
      if (assistantId != null && assistantName != null) {
        alertUpdates['assistantId'] = assistantId;
        alertUpdates['assistantName'] = assistantName;
      }

      await _db.child('alerts/${request.alertId}').update(alertUpdates);

      // 2. Return assistant's existing alerts to unclaimed
      if (confirmCancelOriginal &&
          cancelExistingAlertIds != null &&
          cancelExistingAlertIds.isNotEmpty) {
        for (final alertId in cancelExistingAlertIds) {
          await _db.child('alerts/$alertId').update({
            'status': 'disponible',
            'superviseurId': null,
            'superviseurName': null,
            'assistantId': null,
            'assistantName': null,
            'takenAtTimestamp': null,
          });
        }
      }

      // 3. Mark collaboration request as approved
      await _db.child('collaboration_requests/$requestId').update({
        'pmApproved': true,
        'status': 'approved',
        'approvedBy': approverId,
        'approvedAt': DateTime.now().toIso8601String(),
      });

      // 4. Send notifications (existing code unchanged) – abbreviated below
      final notification = {
        'type': 'collaboration_approved',
        'collabRequestId': requestId,
        'alertId': request.alertId,
        'message':
            'Your collaboration request has been approved by Production Manager',
        'timestamp': DateTime.now().toIso8601String(),
        'status': 'pending',
        'pushSent': false,
      };
      await _db
          .child('notifications/${request.requesterId}')
          .push()
          .set(notification);

      for (final targetId in request.targetSupervisorIds) {
        final notif = {
          'type': 'collaboration_approved',
          'collabRequestId': requestId,
          'alertId': request.alertId,
          'message':
              'Collaboration request approved. You are now assisting on this alert.',
          'timestamp': DateTime.now().toIso8601String(),
          'status': 'pending',
          'pushSent': false,
        };
        await _db.child('notifications/$targetId').push().set(notif);
      }
    } else {
      // Supervisor approval (not PM) – keep simple
      await _db.child('collaboration_requests/$requestId').update({
        'assistantDecision': 'accepted',
        'assistantId': approverId,
        'assistantName': approverName,
        'assistantRespondedAt': DateTime.now().toIso8601String(),
      });
    }
  }

  // Reject collaboration request
  Future<void> rejectCollaborationRequest(
    String requestId,
    String rejecterId,
    String reason,
  ) async {
    final snapshot = await _db.child('collaboration_requests/$requestId').get();
    if (!snapshot.exists) return;

    final request = CollaborationRequest.fromMap(
      requestId,
      Map<String, dynamic>.from(snapshot.value as Map),
    );

    await _db.child('collaboration_requests/$requestId').update({
      'status': 'rejected',
      'rejectedBy': rejecterId,
      'rejectedAt': DateTime.now().toIso8601String(),
      'rejectionReason': reason,
    });

    // Notify requester
    final notification = {
      'type': 'collaboration_rejected',
      'collabRequestId': requestId,
      'alertId': request.alertId,
      'message':
          'Your collaboration request has been rejected. ${reason.isNotEmpty ? "Reason: $reason" : ""}',
      'timestamp': DateTime.now().toIso8601String(),
      'status': 'pending',
      'pushSent': false,
    };
    await _db
        .child('notifications/${request.requesterId}')
        .push()
        .set(notification);

    // Clear alert collaboration ID
    await _db.child('alerts/${request.alertId}').update({
      'collaborationRequestId': null,
    });
  }

  // Save escalation settings
  Future<void> saveEscalationSettings(EscalationSettings settings) async {
    await _db.child('escalation_settings').set(settings.toMap());
  }

  // Get escalation settings
  Future<EscalationSettings> getEscalationSettings() async {
    final snapshot = await _db.child('escalation_settings').get();
    if (!snapshot.exists) {
      return EscalationSettings.defaultSettings();
    }
    return EscalationSettings.fromMap(
        Map<String, dynamic>.from(snapshot.value as Map));
  }

  // Stream escalation settings
  Stream<EscalationSettings> escalationSettingsStream() {
    return _db.child('escalation_settings').onValue.map((event) {
      if (!event.snapshot.exists) {
        return EscalationSettings.defaultSettings();
      }
      return EscalationSettings.fromMap(
          Map<String, dynamic>.from(event.snapshot.value as Map));
    });
  }

  // Check if alert should be escalated
  Future<bool> shouldEscalateAlert(String alertId) async {
    final alertSnapshot = await _db.child('alerts/$alertId').get();
    if (!alertSnapshot.exists) return false;

    final alertData = Map<String, dynamic>.from(alertSnapshot.value as Map);
    final alertType = alertData['type'] as String;
    final status = alertData['status'] as String;
    final timestamp = DateTime.parse(alertData['timestamp'] as String);
    final takenAt = alertData['takenAtTimestamp'] != null
        ? DateTime.parse(alertData['takenAtTimestamp'] as String)
        : null;

    final settings = await getEscalationSettings();
    final threshold = settings.thresholds[alertType];
    if (threshold == null) return false;

    final now = DateTime.now();

    if (status == 'disponible') {
      final minutesSinceCreation = now.difference(timestamp).inMinutes;
      return minutesSinceCreation >= threshold.unclaimedMinutes;
    } else if (status == 'en_cours' && takenAt != null) {
      final minutesSinceClaimed = now.difference(takenAt).inMinutes;
      return minutesSinceClaimed >= threshold.claimedMinutes;
    }

    return false;
  }

  Future<void> _notifyAdminsAboutCollabRequest(
      CollaborationRequest request) async {
    final users = await _getAllUsers();
    for (var entry in users.entries) {
      final role = entry.value['role'] ?? 'supervisor';
      if (role == 'admin') {
        final notification = {
          'type': 'collaboration_request_admin',
          'collabRequestId': request.id,
          'alertId': request.alertId,
          'requesterName': request.requesterName,
          'message':
              '${request.requesterName} requested collaboration with ${request.targetSupervisorNames.join(", ")}',
          'timestamp': DateTime.now().toIso8601String(),
          'status': 'pending',
          'pushSent': false,
        };
        await _db.child('notifications/${entry.key}').push().set(notification);
      }
    }
  }

  Future<Map<String, dynamic>> _getAllUsers() async {
    final snapshot = await _db.child('users').get();
    if (!snapshot.exists) return {};
    return Map<String, dynamic>.from(snapshot.value as Map);
  }

  // Get collaboration request by ID
  Future<CollaborationRequest?> getCollaborationRequest(
      String requestId) async {
    final snapshot = await _db.child('collaboration_requests/$requestId').get();
    if (!snapshot.exists) return null;
    return CollaborationRequest.fromMap(
      requestId,
      Map<String, dynamic>.from(snapshot.value as Map),
    );
  }
}
