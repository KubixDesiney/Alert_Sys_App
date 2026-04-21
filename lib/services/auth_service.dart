import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import '../models/user_model.dart';  // ✅ Add this import
import 'package:onesignal_flutter/onesignal_flutter.dart';


class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseReference _db = FirebaseDatabase.instance.ref();

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

Future<String?> login(String email, String password) async {
  try {
    await _auth.signInWithEmailAndPassword(email: email, password: password);
    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      // Get FCM token for push notifications (web requires VAPID key)
      String? fcmToken;
      final updates = {
        'status': 'active',
        'lastSeen': DateTime.now().toIso8601String(),
      };
      if (fcmToken != null) {
        updates['fcmToken'] = fcmToken;
      }
      String? playerId = await OneSignal.User.getOnesignalId();
if (playerId != null && playerId.isNotEmpty) {
  updates['onesignalId'] = playerId;
  print('Saved OneSignal player ID: $playerId');
}
      await _db.child('users/$uid').update(updates);
    }
    return null;
  } on FirebaseAuthException catch (e) {
    if (e.code == 'user-not-found') return 'User not found.';
    if (e.code == 'wrong-password') return 'Incorrect password.';
    return 'Login error: ${e.message}';
  }
}
  Future<List<UserModel>> getActiveSupervisors() async {
  final snapshot = await _db.child('users').orderByChild('role').equalTo('supervisor').get();
  if (!snapshot.exists) return [];
  final data = Map<String, dynamic>.from(snapshot.value as Map);
  final List<UserModel> list = [];
  data.forEach((key, value) {
    final user = Map<String, dynamic>.from(value as Map);
    if (user['status'] == 'active') {
      user['id'] = key;
      list.add(UserModel.fromMap(key, user));
    }
  });
  return list;
}
Future<void> updateSupervisorProfile({
  required String userId,
  required String firstName,
  required String lastName,
  required String phone,
  required String usine,
}) async {
  await _db.child('users/$userId').update({
    'firstName': firstName,
    'lastName': lastName,
    'fullName': '$firstName $lastName',
    'phone': phone,
    'usine': usine,
  });
}
Future<void> sendPasswordResetEmail(String email) async {
  await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
}
Future<void> assignAssistantToAlert(String alertId, String assistantId, String assistantName) async {
  await _db.child('alerts/$alertId').update({
    'assistantId': assistantId,
    'assistantName': assistantName,
  });
  
  // Get alert details for notification
  final alertSnap = await _db.child('alerts/$alertId').get();
  final alertType = alertSnap.child('type').value ?? 'alert';
  final alertDesc = alertSnap.child('description').value ?? '';
  final claimantName = alertSnap.child('superviseurName').value as String? ?? 'Supervisor';
  
  // Notify the assistant
  final assistantNotification = {
    'type': 'assistant_assigned',
    'alertId': alertId,
    'alertType': alertType,
    'alertDescription': alertDesc,
    'message': 'You have been assigned as assistant to $claimantName for alert: $alertType',
    'timestamp': DateTime.now().toIso8601String(),
    'status': 'pending',
  };
  await _db.child('notifications/$assistantId').push().set(assistantNotification);
  
  // Notify the claimant that an assistant was assigned (optional)
  final claimantId = alertSnap.child('superviseurId').value as String?;
  if (claimantId != null && claimantId != assistantId) {
    final claimantNotification = {
      'type': 'assistant_assigned',
      'alertId': alertId,
      'message': '$assistantName has been assigned as your assistant',
      'timestamp': DateTime.now().toIso8601String(),
      'status': 'pending',
    };
    await _db.child('notifications/$claimantId').push().set(assistantNotification);
  }
}

Future<void> assignSupervisorToAlert(String alertId, String supervisorId, String supervisorName) async {
  await _db.child('alerts/$alertId').update({
    'status': 'en_cours',
    'superviseurId': supervisorId,
    'superviseurName': supervisorName,
    'takenAtTimestamp': DateTime.now().toIso8601String(),
  });
  final alertSnap = await _db.child('alerts/$alertId').get();
  final alertType = alertSnap.child('type').value ?? 'alert';
  final alertDesc = alertSnap.child('description').value ?? '';
  final notification = {
    'alertId': alertId,
    'alertType': alertType,
    'alertDescription': alertDesc,
    'message': '📋 You have been assigned to an alert: $alertType',
    'timestamp': DateTime.now().toIso8601String(),
    'status': 'pending',
  };
  await _db.child('notifications/$supervisorId').push().set(notification);
}
  Future<void> logout() async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid != null) {
        await _db.child('users/$uid').update({'status': 'absent'});
      }
    } catch (e) {
      debugPrint('Logout DB error: $e');
    }
    await _auth.signOut();
  }

  Future<String> getUserRole(String uid) async {
    debugPrint('getUserRole called for uid: $uid');
    try {
      final snapshot = await _db.child('users/$uid/role').get();
      if (snapshot.exists) {
        final role = snapshot.value.toString();
        debugPrint('Role found in DB: $role');
        return role;
      } else {
        debugPrint('No role node for $uid, defaulting to supervisor');
        return 'supervisor';
      }
    } catch (e) {
      debugPrint('Error reading role: $e');
      return 'supervisor';
    }
  }

  // ✅ Fixed fetchSupervisors method
Future<List<UserModel>> fetchSupervisors() async {
  try {
    final snapshot = await _db.child('users').orderByChild('role').equalTo('supervisor').get();
    if (!snapshot.exists) return [];

    final Map<dynamic, dynamic> data = snapshot.value as Map<dynamic, dynamic>;
    List<UserModel> supervisors = [];

    data.forEach((key, value) {
      final Map<String, dynamic> userMap = Map<String, dynamic>.from(value as Map);
      userMap['id'] = key.toString();
      supervisors.add(UserModel.fromMap(key.toString(), userMap));
    });

    return supervisors;
  } catch (e) {
    debugPrint('fetchSupervisors error: $e');
    return [];
  }
}

  Future<String?> createSupervisor({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
    required String phone,
    required String usine,
    required DateTime hiredDate,
  }) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
          email: email, password: password);
      final uid = cred.user!.uid;

      // Small delay to ensure auth token is ready
      await Future.delayed(const Duration(milliseconds: 500));

      final userData = {
        'firstName': firstName,
        'lastName': lastName,
        'email': email,
        'phone': phone,
        'role': 'supervisor',
        'usine': usine,
        'status': 'absent',
        'hiredDate': hiredDate.toIso8601String(),
        'lastSeen': DateTime.now().toIso8601String(),
      };
      await _db.child('users/$uid').set(userData);
      debugPrint('Supervisor $uid created in DB');
      return null;
    } on FirebaseAuthException catch (e) {
      return e.code == 'email-already-in-use'
          ? 'Email already in use.'
          : e.code == 'weak-password'
              ? 'Password too weak (min 6 chars).'
              : 'Error: ${e.message}';
    } catch (e) {
      debugPrint('Create supervisor DB error: $e');
      return 'Database error: ${e.toString()}';
    }
  }

  Future<void> deleteSupervisor(String uid) async {
    await _db.child('users/$uid').remove();
  }

  // Optional: keep the stream method if needed, but not used anymore
  Stream<List<Map<String, dynamic>>> getSupervisorsRaw() {
    return _db
        .child('users')
        .orderByChild('role')
        .equalTo('supervisor')
        .onValue
        .map((event) {
      final data = event.snapshot.value;
      if (data == null) return <Map<String, dynamic>>[];
      final map = Map<String, dynamic>.from(data as Map);
      return map.entries.map((e) {
        final m = Map<String, dynamic>.from(e.value as Map);
        m['id'] = e.key;
        return m;
      }).toList();
    });
  }
}