import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
import 'theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Global error handler
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('Flutter error caught: ${details.exception}');
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

  final fcm = FcmService();
  try {
    await fcm.init();
  } catch (e) {
    debugPrint('FCM init failed: $e');
  }

  // Keep startup path light; post-launch SDK setup runs in background.
  // The voice service initializes lazily when the user taps the mic
  // button or opens the voice claim screen, so no warm-up is needed.
  ShorebirdCodePush();

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
    debugPrint('Firebase init skipped: $e');
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
  static const _accountLoadTimeout = Duration(seconds: 8);

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  Future<void> _loadRole() async {
    try {
      final accountSnapshot = await FirebaseDatabase.instance
          .ref('users/${widget.uid}')
          .get()
          .timeout(_accountLoadTimeout, onTimeout: () {
        debugPrint('Account load timed out. Treating as invalid account.');
        throw TimeoutException('Account load timed out');
      });
      if (!mounted) return;
      if (!accountSnapshot.exists || accountSnapshot.value == null) {
        debugPrint('Account record missing. Signing out.');
        await FirebaseAuth.instance.signOut();
        if (!mounted) return;
        setState(() {
          _loading = false;
          _role = null;
        });
        return;
      }

      final data = Map<String, dynamic>.from(accountSnapshot.value as Map);
      final role = data['role']?.toString();
      if (role == null || (role != 'admin' && role != 'supervisor')) {
        debugPrint('Invalid role value for account. Signing out.');
        await FirebaseAuth.instance.signOut();
        if (!mounted) return;
        setState(() {
          _loading = false;
          _role = null;
        });
        return;
      }
      setState(() {
        _role = role;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _role = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_role == null) {
      return const LoginScreen();
    }
    if (_role == 'admin') {
      return const AdminDashboardScreen();
    }
    return const DashboardScreen();
  }
}
