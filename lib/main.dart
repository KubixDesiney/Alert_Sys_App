import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'providers/alert_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'package:firebase_database/firebase_database.dart';
import 'screens/admin_dashboard_screen.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';
import 'services/fcm_service.dart';
import 'services/offline_account_cache.dart';
import 'services/offline_database_service.dart';
import 'services/service_locator.dart';
import 'services/voice_service.dart';
import 'services/worker_trigger_queue.dart';
import 'services/background_sync_service.dart';
import 'services/app_lifecycle_observer.dart';
import 'theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
    // Add app lifecycle observer for handling foreground/background transitions
    final lifecycleObserver = AppLifecycleObserver();
    WidgetsBinding.instance.addObserver(lifecycleObserver);
  
  // Global error handler
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    ServiceLocator.instance.logger
        .error('Flutter error caught', details.exception, details.stack);
  };
  // Show a red error screen instead of a white blank when a widget build fails
  ErrorWidget.builder = (errorDetails) {
    return Material(
      child: Container(
        color: const Color(
            0xFF0F172A), // dark background (you can use a theme later)
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  color: Color(0xFFF87171), size: 48),
              const SizedBox(height: 12),
              const Text('Something went wrong',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFF1F5F9))),
              const SizedBox(height: 8),
              Text('${errorDetails.exception}',
                  style:
                      const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  };

  await _safeInitFirebase();
  ServiceLocator.instance.init();
  await OfflineDatabaseService.configure();
    // Initialize background sync service for offline support
    BackgroundSyncService.instance.initialize();
  
  WorkerTriggerQueue.instance.start();
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  final fcm = FcmService();
  unawaited(
    fcm.init().timeout(const Duration(seconds: 8)).catchError((Object e) {
      ServiceLocator.instance.logger.warning('FCM init failed', e);
    }),
  );

  // Keep startup path light; post-launch SDK setup runs in background.
  ShorebirdCodePush();

  // Pre-warm the speech recognizer after first frame so the first tap on
  // the mic button starts listening with no perceptible delay. init() is
  // idempotent and any failure is swallowed inside the service.
  unawaited(
    Future.delayed(const Duration(milliseconds: 800), () async {
      try {
        await VoiceService.instance.init();
      } catch (e) {
        ServiceLocator.instance.logger.warning('Voice warmup failed', e);
      }
    }),
  );

  runApp(const AlertSysApp());
}

Future<void> _safeInitFirebase() async {
  try {
    if (Firebase.apps.isNotEmpty) return;
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    // Duplicate app can happen on hot restart/background isolate startup.
    ServiceLocator.instance.logger.info('Firebase init skipped', e);
  }
}

class AlertSysApp extends StatelessWidget {
  const AlertSysApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Capture the AlertProvider into FcmService so the lock-screen voice
        // reply handler (which runs without a BuildContext) can dispatch
        // commands through the same code path the in-app mic uses.
        ChangeNotifierProvider(create: (_) {
          final p = AlertProvider();
          FcmService.alertProvider = p;
          return p;
        }),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) => MaterialApp(
          title: 'AlertSys',
          debugShowCheckedModeBanner: false,
          themeMode: themeProvider.mode,
          theme: buildLightTheme(),
          darkTheme: buildDarkTheme(),
          navigatorKey: FcmService.navigatorKey,
          home: const AuthGate(),
        ),
      ),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Text('Firebase auth error:\n${snapshot.error}',
                  textAlign: TextAlign.center),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const LoginScreen();
        }
        return RoleRouter(uid: snapshot.data!.uid);
      },
    );
  }
}

class RoleRouter extends StatefulWidget {
  final String uid;
  const RoleRouter({super.key, required this.uid});

  @override
  State<RoleRouter> createState() => _RoleRouterState();
}

class _RoleRouterState extends State<RoleRouter> {
  String? _role;
  bool _loading = true;
  bool _offlineAccountUnavailable = false;
  static const _accountLoadTimeout = Duration(seconds: 8);

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  Future<void> _loadRole() async {
    final cachedRole = await OfflineAccountCache.roleFor(widget.uid);

    try {
      final accountSnapshot = await FirebaseDatabase.instance
          .ref('users/${widget.uid}')
          .get()
          .timeout(_accountLoadTimeout, onTimeout: () {
        ServiceLocator.instance.logger
            .warning('Account load timed out. Treating as invalid account.');
        throw TimeoutException('Account load timed out');
      });
      if (!mounted) return;
      if (!accountSnapshot.exists || accountSnapshot.value == null) {
        if (cachedRole != null && !(await _isDatabaseConnected())) {
          ServiceLocator.instance.logger.warning(
            'Account record unavailable offline. Using cached role.',
          );
          setState(() {
            _role = cachedRole;
            _loading = false;
            _offlineAccountUnavailable = false;
          });
          return;
        }

        ServiceLocator.instance.logger
            .warning('Account record missing. Signing out.');
        await FirebaseAuth.instance.signOut();
        if (!mounted) return;
        setState(() {
          _loading = false;
          _role = null;
          _offlineAccountUnavailable = false;
        });
        return;
      }

      final data = Map<String, dynamic>.from(accountSnapshot.value as Map);
      final role = data['role']?.toString();
      if (!OfflineAccountCache.isValidRole(role)) {
        ServiceLocator.instance.logger
            .warning('Invalid role value for account. Signing out.');
        await FirebaseAuth.instance.signOut();
        if (!mounted) return;
        setState(() {
          _loading = false;
          _role = null;
          _offlineAccountUnavailable = false;
        });
        return;
      }
      await OfflineAccountCache.save(
        uid: widget.uid,
        role: role,
        usine: data['usine']?.toString(),
      );
      if (!mounted) return;
      setState(() {
        _role = role;
        _loading = false;
        _offlineAccountUnavailable = false;
      });
    } catch (e) {
      if (!mounted) return;
      final connected = await _isDatabaseConnected();
      if (cachedRole != null && (e is TimeoutException || !connected)) {
        ServiceLocator.instance.logger
            .warning('Account load failed; using cached role: $e');
        setState(() {
          _role = cachedRole;
          _loading = false;
          _offlineAccountUnavailable = false;
        });
        return;
      }

      if (connected) {
        await FirebaseAuth.instance.signOut();
        if (!mounted) return;
      }

      ServiceLocator.instance.logger.warning(
        'Account load failed without an offline fallback: $e',
      );
      setState(() {
        _loading = false;
        _role = null;
        _offlineAccountUnavailable = !connected;
      });
    }
  }

  Future<bool> _isDatabaseConnected() async {
    try {
      final event = await FirebaseDatabase.instance
          .ref('.info/connected')
          .onValue
          .first
          .timeout(const Duration(seconds: 2));
      return event.snapshot.value == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_role == null) {
      if (_offlineAccountUnavailable) {
        return Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.wifi_off, size: 44),
                  const SizedBox(height: 12),
                  const Text(
                    'Offline account data is not cached yet.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Connect once so AlertSys can save this account for offline startup.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () {
                      setState(() {
                        _loading = true;
                        _offlineAccountUnavailable = false;
                      });
                      _loadRole();
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        );
      }
      return const LoginScreen();
    }
    if (_role == 'admin') {
      return const AdminDashboardScreen();
    }
    return const DashboardScreen();
  }
}
