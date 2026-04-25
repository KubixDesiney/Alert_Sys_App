import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

class FcmService {
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final DatabaseReference _db = FirebaseDatabase.instance.ref();

  Future<void> init() async {
    // Get token and save
    await _updateToken();

    // Listen for token refresh
    _fcm.onTokenRefresh.listen((newToken) async {
      await _saveTokenToDatabase(newToken);
    });
  }

  Future<void> _updateToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final token = await _fcm.getToken();
    if (token != null) {
      await _saveTokenToDatabase(token);
    }
  }

  Future<void> _saveTokenToDatabase(String token) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await _db.child('users/${user.uid}').update({
      'fcmToken': token,
      'lastSeen': DateTime.now().toIso8601String(),
    });
    print('FCM token saved for user ${user.uid}');
  }
}
