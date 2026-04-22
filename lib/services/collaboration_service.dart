import 'package:firebase_database/firebase_database.dart';
import '../models/collaboration_model.dart';


class CollaborationService {
  final DatabaseReference _db = FirebaseDatabase.instance.ref();

  // Create a new collaboration request
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

    // Notify admin/PM
    await _notifyAdminsAboutCollabRequest(request);

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
    return getAllCollaborationRequests().map((requests) =>
        requests.where((r) => r.status == 'pending').toList());
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
