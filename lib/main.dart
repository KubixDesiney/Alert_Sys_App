import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'config/company_config.dart';
import 'providers/alert_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/locale_provider.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/mfa_enrollment_screen.dart';
import 'services/enterprise_auth_service.dart';
import 'package:firebase_database/firebase_database.dart';
import 'screens/admin_dashboard_screen.dart';
import 'screens/superadmin/superadmin_dashboard_screen.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';
import 'services/fcm_service.dart';
import 'services/location_tracking_service.dart';
import 'services/offline_account_cache.dart';
import 'services/offline_database_service.dart';
import 'services/service_locator.dart';
import 'services/voice_service.dart';
import 'services/worker_trigger_queue.dart';
import 'services/background_sync_service.dart';
import 'services/app_lifecycle_observer.dart';
import 'services/bug_report_service.dart';
import 'services/telemetry_service.dart';
import 'services/alert_type_registry.dart';
import 'theme.dart';
import 'l10n/generated/app_localizations.dart';
import 'l10n/app_strings.dart';
import 'services/connectivity_service.dart';
import 'widgets/common/app_loading_indicator.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

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
  // Route every ERROR-level log and uncaught async error into the bugs
  // pipeline surfaced on the SuperAdmin Logs tab.
  BugReportService.instance.init();
  // Crash-free / error-rate telemetry (chains the hooks above, never replaces).
  TelemetryService.instance.init();
  // Stream the deployment's configurable alert-type registry (defaults serve
  // synchronously until it resolves).
  AlertTypeRegistry.instance.start();
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

  runApp(const SmartIndustrialAlertApp());
}

Future<void> _safeInitFirebase() async {
  try {
    if (Firebase.apps.isNotEmpty) return;
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    // Isolation safety (dedicated-instance model — see PROVISIONING.md): confirm
    // this build is wired to the company's own Firebase project, so Company A's
    // app can never come up pointed at Company B's data.
    final companyMismatch = CompanyConfig.verifyFirebaseProject(
      DefaultFirebaseOptions.currentPlatform.projectId,
    );
    if (companyMismatch != null) {
      ServiceLocator.instance.logger.error(companyMismatch);
    }
  } catch (e) {
    // Duplicate app can happen on hot restart/background isolate startup.
    ServiceLocator.instance.logger.info('Firebase init skipped', e);
  }
}

class SmartIndustrialAlertApp extends StatelessWidget {
  const SmartIndustrialAlertApp({super.key});

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
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
        ChangeNotifierProvider(create: (_) {
          final c = ConnectivityService();
          // Fire-and-forget; the service swallows its own errors.
          c.init();
          return c;
        }),
      ],
      child: Consumer2<ThemeProvider, LocaleProvider>(
        builder: (context, themeProvider, localeProvider, _) => MaterialApp(
          title: 'SIAS - Smart Industrial Alert System',
          debugShowCheckedModeBanner: false,
          themeMode: themeProvider.mode,
          theme: buildLightTheme(),
          darkTheme: buildDarkTheme(),
          locale: localeProvider.locale,
          navigatorKey: FcmService.navigatorKey,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
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
          return const Scaffold(body: AppLoadingIndicator.fullscreen());
        }
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Text(
                  '${context.tr('Authentication error')}\n${snapshot.error}',
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
  bool _needsMfa = false;
  static const _accountLoadTimeout = Duration(seconds: 8);

  @override
  void initState() {
    super.initState();
    unawaited(OfflineDatabaseService.syncUserScopedPaths(widget.uid));
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
          unawaited(LocationTrackingService.instance.updateForRole(
            uid: widget.uid,
            role: cachedRole,
          ));
          setState(() {
            _role = cachedRole;
            _loading = false;
            _offlineAccountUnavailable = false;
          });
          return;
        }

        ServiceLocator.instance.logger
            .warning('Account record missing. Signing out.');
        await LocationTrackingService.instance.stop();
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
      var role = data['role']?.toString();
      var usine = data['usine']?.toString();

      // SCIM provisioning overlay: the customer's IdP writes provisioning/{email}.
      // Offboarding (active:false) revokes access here; a provisioned role is
      // granted to a user who has none yet (e.g. their first SSO login).
      final prov = await _provisioningFor();
      if (prov != null) {
        if (!prov.active) {
          ServiceLocator.instance.logger
              .warning('Account deprovisioned via SCIM. Signing out.');
          await LocationTrackingService.instance.stop();
          await FirebaseAuth.instance.signOut();
          if (!mounted) return;
          setState(() {
            _loading = false;
            _role = null;
            _offlineAccountUnavailable = false;
          });
          return;
        }
        if (!OfflineAccountCache.isValidRole(role) &&
            OfflineAccountCache.isValidRole(prov.role)) {
          role = prov.role;
          if (prov.factory != null && prov.factory!.isNotEmpty) {
            usine = prov.factory;
          }
          try {
            await FirebaseDatabase.instance.ref('users/${widget.uid}').update({
              'role': role,
              if (usine != null) 'usine': usine,
              'provisionedBy': 'scim',
            });
          } catch (_) {/* best-effort; role still applies this session */}
        }
      }

      if (!OfflineAccountCache.isValidRole(role)) {
        ServiceLocator.instance.logger
            .warning('Invalid role value for account. Signing out.');
        await LocationTrackingService.instance.stop();
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
        usine: usine,
      );
      unawaited(LocationTrackingService.instance.updateForRole(
        uid: widget.uid,
        role: role,
      ));
      final needsMfa = await _checkMfaRequired();
      if (!mounted) return;
      setState(() {
        _role = role;
        _needsMfa = needsMfa;
        _loading = false;
        _offlineAccountUnavailable = false;
      });
    } catch (e) {
      if (!mounted) return;
      final connected = await _isDatabaseConnected();
      if (cachedRole != null && (e is TimeoutException || !connected)) {
        ServiceLocator.instance.logger
            .warning('Account load failed; using cached role: $e');
        unawaited(LocationTrackingService.instance.updateForRole(
          uid: widget.uid,
          role: cachedRole,
        ));
        setState(() {
          _role = cachedRole;
          _loading = false;
          _offlineAccountUnavailable = false;
        });
        return;
      }

      if (connected) {
        await LocationTrackingService.instance.stop();
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

  /// Hard MFA gate: returns true when this company requires a second factor
  /// (build-time [CompanyConfig.mfaRequired] or the IT-set
  /// `auth_config/mfaRequired`) AND the signed-in user has none enrolled.
  Future<bool> _checkMfaRequired() async {
    var required = CompanyConfig.mfaRequired;
    if (!required) {
      try {
        final snap = await FirebaseDatabase.instance
            .ref('auth_config/mfaRequired')
            .get()
            .timeout(const Duration(seconds: 3));
        required = snap.value == true;
      } catch (_) {
        required = false; // runtime flag is best-effort; build flag is absolute
      }
    }
    if (!required) return false;
    final enrolled = await EnterpriseAuthService().hasEnrolledMfa();
    return !enrolled;
  }

  /// Reads this user's SCIM provisioning record (provisioning/{emailKey}). Used
  /// to grant a provisioned role on first login and to revoke deprovisioned
  /// accounts. Fail-safe: returns null on any error so a provisioning read can
  /// never block a legitimate login.
  Future<({bool active, String? role, String? factory})?> _provisioningFor() async {
    try {
      final email = FirebaseAuth.instance.currentUser?.email;
      if (email == null || email.trim().isEmpty) return null;
      final key =
          email.trim().toLowerCase().replaceAll(RegExp(r'[.#$\[\]/]'), '_');
      final snap = await FirebaseDatabase.instance
          .ref('provisioning/$key')
          .get()
          .timeout(const Duration(seconds: 3));
      if (!snap.exists || snap.value == null) return null;
      final m = Map<String, dynamic>.from(snap.value as Map);
      return (
        active: m['active'] != false,
        role: m['role']?.toString(),
        factory: m['factory']?.toString(),
      );
    } catch (_) {
      return null;
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
  void dispose() {
    unawaited(LocationTrackingService.instance.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: AppLoadingIndicator.fullscreen());
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
                  Text(
                    context.tr('Offline account data is not cached yet.'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.tr(
                        'Connect once so SIAS can save this account for offline startup.'),
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
                    child: Text(context.tr('Retry')),
                  ),
                ],
              ),
            ),
          ),
        );
      }
      return const LoginScreen();
    }
    final normalizedRole = _role?.trim().toLowerCase();
    if (_needsMfa) {
      return MfaEnrollmentScreen(
        mandatory: true,
        onCompleted: () => setState(() => _needsMfa = false),
      );
    }
    if (normalizedRole == 'superadmin') {
      return const SuperAdminDashboardScreen();
    }
    if (normalizedRole == 'admin') {
      return const AdminDashboardScreen();
    }
    return const DashboardScreen();
  }
}
