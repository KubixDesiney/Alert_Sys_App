import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../screens/alert_detail_screen.dart';
import '../providers/alert_provider.dart';
import 'voice_command_dispatcher.dart';
import 'voice_command_parser.dart';
import 'voice_service.dart';

class FcmService {
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();
  static String? pendingAlertId;

  // Action ID exposed to the OS for the inline-reply voice button. The
  // notification handler matches on this string to route input transcripts
  // through the voice command pipeline.
  static const String voiceReplyActionId = 'voice_reply';
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

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final DatabaseReference _db = FirebaseDatabase.instance.ref();

  Future<void> init() async {
    // Get token and save
    await _updateToken();

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    // Register an iOS notification category that exposes a text-input action.
    // We reference this category by id ('alerts_voice') on every alert
    // notification so the reply button appears when long-pressed.
    final iosVoiceCategory = DarwinNotificationCategory(
      'alerts_voice',
      actions: <DarwinNotificationAction>[
        DarwinNotificationAction.text(
          voiceReplyActionId,
          'Send',
          buttonTitle: 'Voice command',
          placeholder: 'Say a command',
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
        // Inline voice reply from the notification — fires on locked screen
        // without launching the app UI. Parse + dispatch the same way an
        // in-app mic press does, then speak the result back via TTS.
        if (response.actionId == voiceReplyActionId) {
          final spoken = response.input?.trim() ?? '';
          if (spoken.isEmpty) return;
          _handleVoiceReply(spoken);
          return;
        }
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
          // Inline voice-reply action — visible on the lock screen because
          // the channel is high importance. Speech-to-text is performed by
          // the OS; we receive the transcript in the response handler.
          actions: <AndroidNotificationAction>[
            AndroidNotificationAction(
              voiceReplyActionId,
              'Voice command',
              icon: const DrawableResourceAndroidBitmap('@android:drawable/ic_btn_speak_now'),
              inputs: <AndroidNotificationActionInput>[
                AndroidNotificationActionInput(
                  label: 'Say a command',
                  allowFreeFormInput: true,
                ),
              ],
              showsUserInterface: false,
              cancelNotification: false,
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

  // Run a transcribed voice reply from the lock-screen notification action.
  // Static so it can be invoked from the platform callback without a `this`.
  static Future<void> _handleVoiceReply(String spoken) async {
    final cmd = VoiceCommandParser.parse(spoken);
    final provider = alertProvider;
    if (provider == null) {
      await VoiceService.instance
          .speak('App is starting up. Please try again.');
      return;
    }
    final dispatcher = VoiceCommandDispatcher(provider);
    await dispatcher.execute(cmd);
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
