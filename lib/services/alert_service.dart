import 'package:firebase_database/firebase_database.dart';
import '../models/alert_model.dart';

class AlertService {
  final DatabaseReference _db = FirebaseDatabase.instance.ref();

  Stream<List<AlertModel>> getAlertsForUsine(String usine) {
    return _db
        .child('alerts')
        .orderByChild('usine')
        .equalTo(usine)
        .onValue
        .map((event) => _toAlertList(event.snapshot));
  }

  Stream<List<AlertModel>> getAllAlerts() {
    return _db.child('alerts').onValue.map((event) => _toAlertList(event.snapshot));
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
        .map((e) => AlertModel.fromMap(e.key, Map<String, dynamic>.from(e.value)))
        .toList();
  }

  Future<void> takeAlert(String alertId, String superviseurId, String superviseurName) async {
    await _db.child('alerts/$alertId').update({
      'status': 'en_cours',
      'superviseurId': superviseurId,
      'superviseurName': superviseurName,
      'takenAtTimestamp': DateTime.now().toIso8601String(),
    });
  }

  Future<void> returnToQueue(String alertId) async {
    await _db.child('alerts/$alertId').update({
      'status': 'disponible',
      'superviseurId': null,
      'superviseurName': null,
      'takenAtTimestamp': null,
    });
  }

  Future<void> resolveAlert(String alertId, String reason, int elapsedMinutes) async {
    await _db.child('alerts/$alertId').update({
      'status': 'validee',
      'elapsedTime': elapsedMinutes,
      'resolutionReason': reason,
      'resolvedAt': DateTime.now().toIso8601String(),
    });
  }

  Future<void> addComment(String alertId, String comment) async {
    final commentsRef = _db.child('alerts/$alertId/comments');
    final newCommentRef = commentsRef.push();
    await newCommentRef.set(comment);
  }

  Future<void> toggleCritical(String alertId, bool isCritical) async {
    await _db.child('alerts/$alertId').update({'isCritical': isCritical});
  }

  // Simple notification method (used for critical alerts, etc.)
  Future<void> sendHelpRequest(String targetUserId, Map<String, dynamic> request) async {
    await _db.child('notifications/$targetUserId').push().set(request);
  }

  // Collaboration method for assistance
  Future<void> createHelpRequest(String alertId, String requesterId, String requesterName, String targetSupervisorId) async {
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
    await _db.child('notifications/$targetSupervisorId').push().set(notification);
  }

Future<void> acceptHelpRequest(String alertId, String requestId, String assistantId, String assistantName) async {
  print('acceptHelpRequest: alertId=$alertId, requestId=$requestId, assistantId=$assistantId, assistantName=$assistantName');
  await _db.child('alerts/$alertId').update({
    'assistantId': assistantId,
    'assistantName': assistantName,
    'helpRequestId': null,
  });
  if (requestId.isNotEmpty) {
    await _db.child('help_requests/$requestId').update({'status': 'accepted'});
    final helpRequestSnap = await _db.child('help_requests/$requestId').get();
    final requesterId = helpRequestSnap.child('requesterId').value as String;
    final notification = {
      'type': 'help_accepted',
      'alertId': alertId,
      'message': '$assistantName accepted your assistance request',
      'timestamp': DateTime.now().toIso8601String(),
      'status': 'pending',
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
    };
    await _db.child('notifications/$requesterId').push().set(notification);
  }

  Future<Map<String, dynamic>> getAllUsers() async {
    final snapshot = await _db.child('users').get();
    if (!snapshot.exists) return {};
    return Map<String, dynamic>.from(snapshot.value as Map);
  }

Future<void> sendNewAlertNotification(String alertId, String alertType, String description) async {
  // Check if notification already sent for this alert
  final alertSnap = await _db.child('alerts/$alertId').get();
  if (alertSnap.exists && alertSnap.child('notificationSent').value == true) {
    return;
  }
  // Mark as sent
  await _db.child('alerts/$alertId').update({'notificationSent': true});
  
  final users = await getAllUsers();
  final Set<String> notifiedUsers = {};
  for (var entry in users.entries) {
    final userId = entry.key;
    if (notifiedUsers.contains(userId)) continue;
    notifiedUsers.add(userId);
    final role = entry.value['role'] ?? 'supervisor';
    if (role == 'supervisor' || role == 'admin') {
      final notification = {
        'alertId': alertId,
        'alertType': alertType,
        'alertDescription': description,
        'message': '🔔 New alert: $alertType',
        'timestamp': DateTime.now().toIso8601String(),
        'status': 'pending',
      };
      await _db.child('notifications/$userId').push().set(notification);
    }
  }
}
}