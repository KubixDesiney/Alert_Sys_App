import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../providers/alert_provider.dart';
import '../screens/alert_detail_screen.dart';
import '../screens/voice_claim_screen.dart';

class FcmService {
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();
  static String? pendingAlertId;
  static bool _hasPendingVoiceClaim = false;
  static Timer? _pendingVoiceClaimTimer;

  // Action ID for the "Speak command" notification action. When the user
  // taps it (works on the lock screen), Android brings the app forward and
  // we navigate straight into VoiceClaimScreen.
  static const String voiceClaimActionId = 'voice_claim';

  // Provider injected once at app startup; the FCM callback runs in a
  // detached context so we can't go through `Provider.of(context)`.
  static AlertProvider? alertProvider;

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
  static const MethodChannel _androidNotifications = MethodChannel(
    'alertsys/notifications',
  );

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final DatabaseReference _db = FirebaseDatabase.instance.ref();

  Future<void> init() async {
    // Get token and save
    await _updateToken();

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    // iOS notification category exposing a "Speak command" foreground action.
    // On iOS, tapping the action launches the app and routes the user into
    // VoiceClaimScreen exactly the same way as on Android.
    final iosVoiceCategory = DarwinNotificationCategory(
      'alerts_voice',
      actions: <DarwinNotificationAction>[
        DarwinNotificationAction.plain(
          voiceClaimActionId,
          'Speak command',
          options: <DarwinNotificationActionOption>{
            DarwinNotificationActionOption.foreground,
          },
        ),
      ],
      options: <DarwinNotificationCategoryOption>{
        DarwinNotificationCategoryOption.hiddenPreviewShowTitle,
      },
    );
    final iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
      notificationCategories: <DarwinNotificationCategory>[iosVoiceCategory],
    );
    await _localNotifications.initialize(
      InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (response) {
        // Voice claim action opens the dedicated screen above the keyguard.
        if (response.actionId == voiceClaimActionId) {
          _navigateToVoiceClaim(response.payload);
          return;
        }
        // Plain notification tap opens alert detail.
        final alertId = response.payload;
        if (alertId != null && alertId.isNotEmpty) {
          _navigateToAlertDetailById(alertId);
        }
      },
    );
    await _handleInitialNotificationLaunch();

    final androidImpl = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
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
      if (defaultTargetPlatform == TargetPlatform.android &&
          message.data['nativeNotification'] == 'true') {
        return;
      }
      _handleForegroundMessage(message);
    });
  }

  void _handleForegroundMessage(RemoteMessage message) {
    final alertId = message.data['alertId'];
    final title = message.notification?.title ?? 'New Alert';
    final body = message.notification?.body ?? 'Tap to view details';

    if (alertId == null) return;

    HapticFeedback.mediumImpact();

    unawaited(
      _showAlertNotification(
        id: message.hashCode,
        title: title,
        body: body,
        alertId: alertId.toString(),
      ),
    );

    // Lightweight in-app affordance.
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
      print('Navigating to alert: $alertId');
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

  void _navigateToVoiceClaim(String? alertId) {
    final state = navigatorKey.currentState;
    if (state == null) {
      // App not yet initialized; store payload and route once ready.
      pendingAlertId = alertId;
      _hasPendingVoiceClaim = true;
      _schedulePendingVoiceClaim();
      return;
    }
    pendingAlertId = null;
    _hasPendingVoiceClaim = false;
    _pendingVoiceClaimTimer?.cancel();
    _pendingVoiceClaimTimer = null;
    state.push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => VoiceClaimScreen(alertId: alertId),
      ),
    );
  }

  void _schedulePendingVoiceClaim() {
    _pendingVoiceClaimTimer ??= Timer.periodic(
      const Duration(milliseconds: 150),
      (_) {
        if (!_hasPendingVoiceClaim) {
          _pendingVoiceClaimTimer?.cancel();
          _pendingVoiceClaimTimer = null;
          return;
        }
        if (navigatorKey.currentState != null) {
          final alertId = pendingAlertId;
          _navigateToVoiceClaim(alertId);
        }
      },
    );
  }

  Future<void> _handleInitialNotificationLaunch() async {
    final details = await _localNotifications.getNotificationAppLaunchDetails();
    final response = details?.notificationResponse;
    if (details?.didNotificationLaunchApp == true &&
        response?.actionId == voiceClaimActionId) {
      _navigateToVoiceClaim(response?.payload);
    }
  }

  Future<void> _showAlertNotification({
    required int id,
    required String title,
    required String body,
    required String alertId,
  }) async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _androidNotifications.invokeMethod('showAlertNotification', {
          'notificationId': id,
          'title': title,
          'body': body,
          'payload': alertId,
        });
        return;
      } catch (e) {
        debugPrint('Native Android notification failed: $e');
      }
    }

    await _localNotifications.show(
      id,
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
          actions: <AndroidNotificationAction>[
            AndroidNotificationAction(
              voiceClaimActionId,
              'Speak command',
              icon: const DrawableResourceAndroidBitmap(
                '@android:drawable/ic_btn_speak_now',
              ),
              showsUserInterface: true,
              cancelNotification: true,
            ),
          ],
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          categoryIdentifier: 'alerts_voice',
        ),
      ),
      payload: alertId,
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
