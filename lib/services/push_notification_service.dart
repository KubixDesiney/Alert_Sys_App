import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

class PushNotificationService {
  static final FirebaseMessaging _fcm = FirebaseMessaging.instance;

  static Future<void> initialize() async {
    // Request permission
    NotificationSettings settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus != AuthorizationStatus.authorized) {
      debugPrint('Push notifications not authorized');
      return;
    }

    debugPrint('Push notifications authorized');

    // Get FCM token (requires VAPID key)
    final vapidKey = 'YOUR_VAPID_PUBLIC_KEY'; // Replace with your key
    final token = await _fcm.getToken(vapidKey: vapidKey);
    debugPrint('FCM Token: $token');

    // Save token to Firebase (optional – store in user document)
    // await _saveToken(token);

    // Listen for messages while app is in foreground
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('Foreground message: ${message.data}');
      // Add to your in-app notification list
      _showInAppNotification(message);
    });

    // Listen when user taps notification
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('Notification opened');
      _handleNotificationTap(message);
    });
  }

  static void _showInAppNotification(RemoteMessage message) {
    // Integrate with your existing notification system (AlertProvider)
    final notification = {
      'alertId': message.data['alertId'],
      'alertType': message.data['alertType'],
      'alertDescription': message.data['alertDescription'],
      'message': message.notification?.title ?? 'New Alert',
      'timestamp': DateTime.now().toIso8601String(),
      'status': 'pending',
    };
    // You'll need to add this to your AlertProvider's notification list
    // For now, print to console
    debugPrint('In-app notification: $notification');
  }

  static void _handleNotificationTap(RemoteMessage message) {
    final alertId = message.data['alertId'];
    if (alertId != null) {
      // Navigate to AlertDetailScreen
      // You'll need a navigation key or use a global navigator
      debugPrint('Navigate to alert: $alertId');
    }
  }
}