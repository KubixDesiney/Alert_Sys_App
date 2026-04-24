import 'dart:convert';
import 'package:firebase_database/firebase_database.dart';
import 'package:http/http.dart' as http;
import '../models/alert_model.dart';
import '../services/hierarchy_service.dart';

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
  /// Creates an alert only if the location exists in the hierarchy.
Future<String?> createAlertWithHierarchy({
  required String type,
  required String usine,
  required int convoyeur,
  required int poste,
  required String description,
  bool isCritical = false,
}) async {
  // Validate against the hierarchy
  final hierarchyService = HierarchyService();
  final isValid = await hierarchyService.validateLocation(usine, convoyeur, poste);
  if (!isValid) {
    throw Exception('Invalid location: Factory "$usine", Conveyor $convoyeur, Station $poste does not exist in hierarchy.');
  }

  // Create the alert (same as before)
  final ref = _db.child('alerts').push();
  final now = DateTime.now().toUtc();
  final alertId = ref.key;
  final alertData = {
    'type': type,
    'usine': usine,
    'convoyeur': convoyeur,
    'poste': poste,
    'adresse': '${usine.replaceAll(' ', '_')}_C${convoyeur}_P$poste',
    'timestamp': now.toIso8601String(),
    'description': description,
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
  return alertId;
}


  Future<void> takeAlert(String alertId, String superviseurId, String superviseurName) async {
    await _db.child('alerts/$alertId').update({
      'status': 'en_cours',
      'superviseurId': superviseurId,
      'superviseurName': superviseurName,
      'takenAtTimestamp': DateTime.now().toIso8601String(),
    });
  }
  Stream<List<AlertModel>> getAlertsWhereAssistant(String assistantId) {
  return _db
      .child('alerts')
      .orderByChild('assistantId')
      .equalTo(assistantId)
      .onValue
      .map((event) => _toAlertList(event.snapshot));
}

// Modify existing returnToQueue
Future<void> returnToQueue(String alertId, {String? reason}) async {
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
}

// Add this new method
Future<void> notifyAdminsAboutSuspend(String alertId, String supervisorName, String? reason) async {
  final users = await getAllUsers();
  for (var entry in users.entries) {
    final role = entry.value['role'] ?? 'supervisor';
    if (role == 'admin') {
      final notification = {
        'type': 'alert_suspended',
        'alertId': alertId,
        'supervisorName': supervisorName,
        'reason': reason ?? 'No reason provided',
        'message': '⚠️ Supervisor $supervisorName suspended an alert. ${reason != null ? "Reason: $reason" : ""}',
        'timestamp': DateTime.now().toIso8601String(),
        'status': 'pending',
      };
      await _db.child('notifications/${entry.key}').push().set(notification);
    }
  }
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

  Future<void> sendHelpRequest(String targetUserId, Map<String, dynamic> request) async {
    await _db.child('notifications/$targetUserId').push().set(request);
  }

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
  Future<void> setCriticalNote(String alertId, String note) async {
  await _db.child('alerts/$alertId').update({'criticalNote': note});
}

  // ✅ Fixed sendNewAlertNotification method
Future<void> sendNewAlertNotification(String alertId, String alertType, String description) async {
  const String onesignalAppId = "322abcb7-c4e5-4630-811f-ccea86a6f481";
  const String onesignalRestKey = "os_v2_app_givlzn6e4vddbai7ztvinjxuqewhaxkphaneo54dcramof6j6nf4ywcgn43htd5le6m6bthdk3abggndvxh225xfkpegcd5vmzduejq";

  final alertSnap = await _db.child('alerts/$alertId').get();
  if (alertSnap.exists && alertSnap.child('notificationSent').value == true) return;

  final usine = alertSnap.child('usine').value?.toString() ?? 'Unknown plant';
  await _db.child('alerts/$alertId').update({'notificationSent': true});

  final users = await getAllUsers();
  final List<String> playerIds = [];

  for (var entry in users.entries) {
    final role = entry.value['role'] ?? 'supervisor';
    if (role == 'supervisor' || role == 'admin') {
      // In‑app notification
      final notification = {
        'alertId': alertId,
        'alertType': alertType,
        'alertDescription': description,
        'usine': usine,
        'message': '🔔 New alert from $usine: $alertType',
        'timestamp': DateTime.now().toIso8601String(),
        'status': 'pending',
      };
      await _db.child('notifications/${entry.key}').push().set(notification);

      final onesignalId = entry.value['onesignalId'] as String?;
      if (onesignalId != null && onesignalId.isNotEmpty) {
        playerIds.add(onesignalId);
      }
    }
  }

  if (playerIds.isNotEmpty) {
    final payload = {
      'app_id': onesignalAppId,
      'include_player_ids': playerIds,
      'headings': {'en': '🚨 New Alert: $alertType'},
      'contents': {'en': '$usine - $description'},
      'data': {'alertId': alertId, 'type': alertType, 'usine': usine},
      'android_channel_id': 'alerts',
    };
    try {
      final response = await http.post(
        Uri.parse('https://onesignal.com/api/v1/notifications'),
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Authorization': 'Basic $onesignalRestKey',
        },
        body: jsonEncode(payload),
      );
      print('OneSignal push status: ${response.statusCode}');
    } catch (e) {
      print('Push error: $e');
    }
  }
}
}
