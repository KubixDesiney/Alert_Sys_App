import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'firebase_options.dart';
import 'services/config_service.dart';
import 'providers/alert_provider.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'package:firebase_database/firebase_database.dart';
import 'screens/admin_dashboard_screen.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';
import 'services/fcm_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await _safeInitFirebase();

  final fcm = FcmService();
  try {
    await fcm.init();
  } catch (e) {
    debugPrint('FCM init failed: $e');
  }

  // Keep startup path light; post-launch SDK setup runs in background.
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
        ChangeNotifierProvider(create: (_) => AlertProvider()),
      ],
      child: MaterialApp(
        title: 'AlertSys',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          scaffoldBackgroundColor: const Color(0xFFF3F4F6),
          colorScheme: const ColorScheme.light(
            primary: Color(0xFF0D4A75),
            error: Color(0xFFE31E24),
          ),
        ),
        navigatorKey: FcmService.navigatorKey,
        home: const AuthGate(),
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
