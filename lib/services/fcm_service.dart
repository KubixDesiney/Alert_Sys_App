import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

class FcmService {
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final DatabaseReference _db = FirebaseDatabase.instance.ref();

  Future<void> init() async {
    // Get token and save
    await _updateToken();

    // Listen for token refresh
    _fcm.onTokenRefresh.listen((newToken) async {
      await _saveTokenToDatabase(newToken);
    });

    // Handle notification taps when app is in foreground
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('Foreground message received: ${message.data}');
      _handleNotificationTap(message);
    });

    // Handle notification taps when app is in background
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('Notification opened app: ${message.data}');
      _navigateToAlertDetail(message);
    });
  }

  void _handleNotificationTap(RemoteMessage message) {
    final alertId = message.data['alertId'];
    if (alertId != null) {
      _navigateToAlertDetail(message);
    }
  }

  void _navigateToAlertDetail(RemoteMessage message) {
    final alertId = message.data['alertId'];
    if (alertId != null && navigatorKey.currentContext != null) {
      // Import AlertDetailScreen at the top
      // navigatorKey.currentState?.pushNamed('/alert/$alertId');
      // For now, we'll use a simple approach - dispatch to main app
      print('Navigating to alert: $alertId');
    }
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
