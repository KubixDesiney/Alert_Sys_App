import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../screens/alert_detail_screen.dart';

class FcmService {
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();
  static String? pendingAlertId;

  static const AndroidNotificationChannel _androidChannel =
      AndroidNotificationChannel(
    'alerts_high',
    'Critical alerts',
    description: 'High priority alert notifications',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
  );

  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final DatabaseReference _db = FirebaseDatabase.instance.ref();

  Future<void> init() async {
    // Get token and save
    await _updateToken();

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _localNotifications.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (response) {
        final alertId = response.payload;
        if (alertId != null && alertId.isNotEmpty) {
          _navigateToAlertDetailById(alertId);
        }
      },
    );

    final androidImpl =
        _localNotifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.createNotificationChannel(_androidChannel);

    // Listen for token refresh
    _fcm.onTokenRefresh.listen((newToken) async {
      await _saveTokenToDatabase(newToken);
    });

    // Handle notification taps when app is in background/terminated
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('Notification opened app: ${message.data}');
      _navigateToAlertDetail(message);
    });

    // Handle notification taps when app is in foreground
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('Foreground message received: ${message.data}');
      // Show a dialog or snackbar and navigate when tapped
      _handleForegroundMessage(message);
    });
  }

  void _handleForegroundMessage(RemoteMessage message) {
    final alertId = message.data['alertId'];
    final title = message.notification?.title ?? 'New Alert';
    final body = message.notification?.body ?? 'Tap to view details';

    if (alertId == null) return;

    HapticFeedback.mediumImpact();

    _localNotifications.show(
      message.hashCode,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannel.id,
          _androidChannel.name,
          channelDescription: _androidChannel.description,
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: alertId.toString(),
    );

    // Keep a lightweight in-app affordance too.
    if (navigatorKey.currentContext != null) {
      ScaffoldMessenger.of(navigatorKey.currentContext!).showSnackBar(
        SnackBar(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(body, maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
          ),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'VIEW',
            onPressed: () => _navigateToAlertDetail(message),
          ),
        ),
      );
    }
  }

  void _navigateToAlertDetail(RemoteMessage message) {
    final alertId = message.data['alertId'];
    if (alertId != null && navigatorKey.currentState != null) {
      print('🔔 Navigating to alert: $alertId');
      navigatorKey.currentState!.push(
        MaterialPageRoute(
          builder: (context) => AlertDetailScreen(alertId: alertId),
        ),
      );
    }
  }

  void _navigateToAlertDetailById(String alertId) {
    if (navigatorKey.currentState == null) return;
    navigatorKey.currentState!.push(
      MaterialPageRoute(
        builder: (context) => AlertDetailScreen(alertId: alertId),
      ),
    );
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
