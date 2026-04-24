import 'package:firebase_database/firebase_database.dart';
import '../models/collaboration_model.dart';


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

  // Fetch each target supervisor's usine
  for (int i = 0; i < targetSupervisorIds.length; i++) {
    final supId = targetSupervisorIds[i];
    final supName = targetSupervisorNames[i];
    final supSnapshot = await _db.child('users/$supId').get();
    if (!supSnapshot.exists) {
      throw Exception('Supervisor $supName not found');
    }
    final supUsine = supSnapshot.child('usine').value as String?;
    if (supUsine != alertUsine) {
      throw Exception('Supervisor $supName is from factory "$supUsine", but alert is from "$alertUsine". Collaboration only allowed within same factory.');
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

  await _db.child('collaboration_requests/$requestId').set(request.toMap());

  // Update alert with collaboration request ID
  await _db.child('alerts/$alertId').update({
    'collaborationRequestId': requestId,
  });

  // Notify target supervisors
  for (final targetId in targetSupervisorIds) {
    final notification = {
      'type': 'collaboration_request',
      'collabRequestId': requestId,
      'alertId': alertId,
      'requesterName': requesterName,
      'message': '$requesterName is requesting collaboration on alert: $alertType',
      'timestamp': DateTime.now().toIso8601String(),
      'status': 'pending',
    };
    await _db.child('notifications/$targetId').push().set(notification);
  }

  return requestId;
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

  // Get pending collaboration requests (for admin)
  Stream<List<CollaborationRequest>> getPendingCollaborationRequests() {
    // Pending for PM/admin review means assistant accepted but PM not yet approved.
    return getAllCollaborationRequests().map((requests) => requests
        .where((r) =>
            r.pmApproved == false &&
            r.status != 'rejected' &&
            r.assistantDecision == 'accepted')
        .toList());
  }

  Future<void> respondToCollaborationRequest({
    required String requestId,
    required String responderId,
    required String responderName,
    required bool accepted,
  }) async {
    final snapshot = await _db.child('collaboration_requests/$requestId').get();
    if (!snapshot.exists) {
      throw Exception('Collaboration request not found');
    }

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
    if (request.assistantDecision != 'pending') {
      throw Exception('This request has already been responded to');
    }

    final nowIso = DateTime.now().toIso8601String();

    if (!accepted) {
      await _db.child('collaboration_requests/$requestId').update({
        'assistantDecision': 'refused',
        'assistantId': responderId,
        'assistantName': responderName,
        'assistantRespondedAt': nowIso,
        'status': 'rejected',
        'rejectedBy': responderId,
        'rejectedAt': nowIso,
      });

      await _db.child('alerts/${request.alertId}').update({
        'collaborationRequestId': null,
      });

      await _db.child('notifications/${request.requesterId}').push().set({
        'type': 'collaboration_refused',
        'collabRequestId': requestId,
        'alertId': request.alertId,
        'message': '$responderName refused your collaboration request.',
        'timestamp': nowIso,
        'status': 'pending',
      });
      return;
    }

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
      'message':
          '$responderName accepted your collaboration request. Waiting for PM approval.',
      'timestamp': nowIso,
      'status': 'pending',
    });

    // Now notify admin/PM for final review.
    final escalated = CollaborationRequest(
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
      approvedBy: request.approvedBy,
      approvedAt: request.approvedAt,
      rejectedBy: request.rejectedBy,
      rejectedAt: request.rejectedAt,
      requiresPMApproval: request.requiresPMApproval,
      pmApproved: request.pmApproved,
      cancelsOriginalAlert: request.cancelsOriginalAlert,
      usine: request.usine,
      convoyeur: request.convoyeur,
      poste: request.poste,
      alertType: request.alertType,
      alertDescription: request.alertDescription,
    );
    await _notifyAdminsAboutCollabRequest(escalated);
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
        'message': 'Your collaboration request has been approved by Production Manager',
        'timestamp': DateTime.now().toIso8601String(),
        'status': 'pending',
      };
      await _db.child('notifications/${request.requesterId}').push().set(notification);

      // Notify target supervisors
      for (final targetId in request.targetSupervisorIds) {
        final notif = {
          'type': 'collaboration_approved',
          'collabRequestId': requestId,
          'alertId': request.alertId,
          'message': 'Collaboration request approved. You can now work on this alert.',
          'timestamp': DateTime.now().toIso8601String(),
          'status': 'pending',
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
    // 1. Assign assistant to the collaboration alert
    final assistantId = request.assistantId ??
        (request.targetSupervisorIds.isNotEmpty
            ? request.targetSupervisorIds.first
            : null);
    final assistantName = request.assistantName ??
        (request.targetSupervisorNames.isNotEmpty
            ? request.targetSupervisorNames.first
            : null);

    if (assistantId != null && assistantName != null) {
      await _db.child('alerts/${request.alertId}').update({
        'assistantId': assistantId,
        'assistantName': assistantName,
      });
      print('Assigned assistant $assistantName to alert ${request.alertId}');
    }

    // 2. Return assistant's existing alerts to unclaimed (do NOT cancel them)
    if (confirmCancelOriginal && cancelExistingAlertIds != null && cancelExistingAlertIds.isNotEmpty) {
      for (final alertId in cancelExistingAlertIds) {
        await _db.child('alerts/$alertId').update({
          'status': 'disponible',
          'superviseurId': null,
          'superviseurName': null,
          'assistantId': null,
          'assistantName': null,
          'takenAtTimestamp': null,
        });
        print('Returned assistant\'s alert $alertId to unclaimed queue');
      }
    }

    // 3. Mark collaboration request as approved
    await _db.child('collaboration_requests/$requestId').update({
      'pmApproved': true,
      'status': 'approved',
      'approvedBy': approverId,
      'approvedAt': DateTime.now().toIso8601String(),
    });

    // 4. Send notifications
    final notification = {
      'type': 'collaboration_approved',
      'collabRequestId': requestId,
      'alertId': request.alertId,
      'message': 'Your collaboration request has been approved by Production Manager',
      'timestamp': DateTime.now().toIso8601String(),
      'status': 'pending',
    };
    await _db.child('notifications/${request.requesterId}').push().set(notification);

    for (final targetId in request.targetSupervisorIds) {
      final notif = {
        'type': 'collaboration_approved',
        'collabRequestId': requestId,
        'alertId': request.alertId,
        'message': 'Collaboration request approved. You are now assisting on this alert.',
        'timestamp': DateTime.now().toIso8601String(),
        'status': 'pending',
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
      'message': 'Your collaboration request has been rejected. ${reason.isNotEmpty ? "Reason: $reason" : ""}',
      'timestamp': DateTime.now().toIso8601String(),
      'status': 'pending',
    };
    await _db.child('notifications/${request.requesterId}').push().set(notification);

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
  Future<CollaborationRequest?> getCollaborationRequest(String requestId) async {
    final snapshot = await _db.child('collaboration_requests/$requestId').get();
    if (!snapshot.exists) return null;
    return CollaborationRequest.fromMap(
      requestId,
      Map<String, dynamic>.from(snapshot.value as Map),
    );
  }
}
