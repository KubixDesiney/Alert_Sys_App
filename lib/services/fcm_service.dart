import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../firebase_options.dart';
import '../providers/alert_provider.dart';
import '../screens/alert_detail_screen.dart';
import '../screens/voice_claim_screen.dart';
import 'voice_auth_service.dart';
import 'voice_command_dispatcher.dart';
import 'voice_command_parser.dart';
import 'voice_lock_service.dart';
import 'sherpa_stt_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  DartPluginRegistrant.ensureInitialized();

  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } catch (_) {}

  await FcmService.showVoiceActionNotificationForMessage(message);
}

class FcmService {
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();
  static String? pendingAlertId;
  static bool _hasPendingVoiceClaim = false;
  static Timer? _pendingVoiceClaimTimer;
  static String? _pendingAlertNavId;
  static Timer? _pendingAlertNavTimer;

  // Action ID for the "Speak command" notification action. When the user
  // taps it (works on the lock screen), Android brings the app forward and
  // we navigate straight into VoiceClaimScreen.
  static const String voiceClaimActionId = 'voice_claim';

  // Provider injected once at app startup; the FCM callback runs in a
  // detached context so we can't go through `Provider.of(context)`.
  static AlertProvider? alertProvider;

  static const AndroidNotificationChannel _androidChannel =
      AndroidNotificationChannel(
    'alerts_voice_critical',
    'Critical voice alerts',
    description: 'Urgent alerts with lock-screen voice actions',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
    audioAttributesUsage: AudioAttributesUsage.alarm,
  );

  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  static bool _localNotificationsInitialized = false;
  static bool _androidLockScreenAccessPrepared = false;

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final DatabaseReference _db = FirebaseDatabase.instance.ref();

  Future<void> init() async {
    // Pre-warm the TFLite speaker model so the first voice verification is fast.
    unawaited(VoiceAuthService.instance.preload());

    // Get token and save
    await _updateToken();

    await _localNotifications.initialize(
      _initializationSettings(),
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
    _localNotificationsInitialized = true;
    await _ensureAndroidChannel();
    final launchedFromVoiceAction = await _handleInitialNotificationLaunch();
    if (!launchedFromVoiceAction) {
      await _prepareAndroidLockScreenNotifications();
    }

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
      _handleForegroundMessage(message);
    });
  }

  void _handleForegroundMessage(RemoteMessage message) {
    final alertId = message.data['alertId'];
    // FCM messages are now data-only; title/body live in message.data.
    final title = message.notification?.title ?? message.data['title'] ?? 'New Alert';
    final body = message.notification?.body ?? message.data['body'] ?? 'Tap to view details';

    if (alertId == null) return;

    HapticFeedback.mediumImpact();

    unawaited(showVoiceActionNotificationForMessage(message));

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
    if (defaultTargetPlatform == TargetPlatform.android) {
      unawaited(_startAndroidVoiceLockFlow(alertId));
      return;
    }
    _navigateToVoiceClaimScreen(alertId);
  }

  // iOS / fallback: push VoiceClaimScreen above the keyguard.
  void _navigateToVoiceClaimScreen(String? alertId) {
    final state = navigatorKey.currentState;
    if (state == null) {
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

  Future<void> _startAndroidVoiceLockFlow(String? alertId) async {
    final result = await VoiceLockService.startVoiceLockFlow();
    if (result == null) {
      _navigateToVoiceClaimScreen(alertId);
      return;
    }

    final provider = alertProvider;
    if (provider == null) return;

    Uint8List? audioBytes;
    if (result.audioPath.isNotEmpty) {
      try {
        audioBytes = await File(result.audioPath).readAsBytes();
      } catch (_) {}
    }

    final transcripts = result.transcripts.toList(growable: true);
    final transcript = await _transcribeVoiceLockAudio(audioBytes);
    if (transcript.isNotEmpty) transcripts.insert(0, transcript);
    final cmd = VoiceCommandParser.parseBest(transcripts);

    // VoiceCommandDispatcher handles voice auth internally.
    try {
      await VoiceCommandDispatcher(provider).execute(
        cmd,
        rawAudio: audioBytes,
        fallbackAlertId: alertId,
      );
    } catch (_) {}

    if (result.audioPath.isNotEmpty) {
      try {
        File(result.audioPath).deleteSync();
      } catch (_) {}
    }
  }

  static Future<String> _transcribeVoiceLockAudio(Uint8List? audioBytes) async {
    if (audioBytes == null || audioBytes.isEmpty) return '';

    try {
      var ready = SherpaSttService.instance.isReady;
      if (!ready) {
        ready = await SherpaSttService.instance.ensureReady();
      }
      if (!ready) {
        debugPrint('FcmService: voice STT model was not ready.');
        return '';
      }
      return SherpaSttService.instance
          .transcribe(audioBytes, sampleRate: 16000);
    } catch (e, st) {
      debugPrint('FcmService: voice transcription failed: $e\n$st');
      return '';
    }
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

  Future<bool> _handleInitialNotificationLaunch() async {
    final details = await _localNotifications.getNotificationAppLaunchDetails();
    final response = details?.notificationResponse;
    if (details?.didNotificationLaunchApp != true || response == null) {
      return false;
    }
    if (response.actionId == voiceClaimActionId) {
      _navigateToVoiceClaim(response.payload);
      return true;
    }
    // Plain notification tap (e.g. from a fullScreenIntent alert) — navigate
    // to the alert detail. The navigator may not be ready yet, so defer.
    final alertId = response.payload;
    if (alertId != null && alertId.isNotEmpty) {
      _deferNavigateToAlert(alertId);
      return true;
    }
    return false;
  }

  void _deferNavigateToAlert(String alertId) {
    _pendingAlertNavId = alertId;
    _pendingAlertNavTimer ??= Timer.periodic(
      const Duration(milliseconds: 150),
      (_) {
        if (_pendingAlertNavId == null) {
          _pendingAlertNavTimer?.cancel();
          _pendingAlertNavTimer = null;
          return;
        }
        if (navigatorKey.currentState != null) {
          final id = _pendingAlertNavId!;
          _pendingAlertNavId = null;
          _pendingAlertNavTimer?.cancel();
          _pendingAlertNavTimer = null;
          _navigateToAlertDetailById(id);
        }
      },
    );
  }

  static Future<void> showVoiceActionNotificationForMessage(
    RemoteMessage message,
  ) async {
    final alertId = message.data['alertId'];
    if (alertId == null || alertId.toString().isEmpty) return;

    final title =
        message.notification?.title ?? message.data['title'] ?? 'New Alert';
    final body = message.notification?.body ??
        message.data['body'] ??
        'Tap to view details';
    final id = int.tryParse(message.data['notificationId']?.toString() ?? '') ??
        message.messageId?.hashCode ??
        message.hashCode;

    await _showAlertNotification(
      id: id,
      title: title,
      body: body,
      alertId: alertId.toString(),
    );
  }

  static InitializationSettings _initializationSettings() {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
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
    return InitializationSettings(android: androidInit, iOS: iosInit);
  }

  static Future<void> _ensureAndroidChannel() async {
    final androidImpl =
        _localNotifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.createNotificationChannel(_androidChannel);
  }

  static Future<void> _prepareAndroidLockScreenNotifications() async {
    if (_androidLockScreenAccessPrepared ||
        defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    _androidLockScreenAccessPrepared = true;

    final androidImpl =
        _localNotifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl == null) return;

    try {
      final enabled = await androidImpl.areNotificationsEnabled();
      if (enabled == false) {
        await androidImpl.requestNotificationsPermission();
      }
    } catch (e) {
      debugPrint('Android notification permission setup failed: $e');
    }

    try {
      await androidImpl.requestFullScreenIntentPermission();
    } catch (e) {
      debugPrint('Android full-screen intent setup failed: $e');
    }
  }

  static Future<void> _showAlertNotification({
    required int id,
    required String title,
    required String body,
    required String alertId,
  }) async {
    if (!_localNotificationsInitialized) {
      await _localNotifications.initialize(_initializationSettings());
      _localNotificationsInitialized = true;
    }
    await _ensureAndroidChannel();

    await _localNotifications.show(
      id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannel.id,
          _androidChannel.name,
          channelDescription: _androidChannel.description,
          importance: Importance.max,
          priority: Priority.max,
          playSound: true,
          enableVibration: true,
          icon: '@mipmap/ic_launcher',
          ticker: title,
          visibility: NotificationVisibility.public,
          category: AndroidNotificationCategory.alarm,
          // fullScreenIntent lets the voice action launch above the keyguard
          // where Android permits it. Requires USE_FULL_SCREEN_INTENT plus
          // showWhenLocked/turnScreenOn on the activity.
          fullScreenIntent: true,
          audioAttributesUsage: AudioAttributesUsage.alarm,
          actions: <AndroidNotificationAction>[
            AndroidNotificationAction(
              voiceClaimActionId,
              'Voice command',
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
