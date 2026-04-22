import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'firebase_options.dart';
import 'providers/alert_provider.dart';
import 'services/auth_service.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'package:firebase_database/firebase_database.dart';
import 'screens/admin_dashboard_screen.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';
import 'package:flutter/foundation.dart' show kIsWeb;



void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Safe Firebase initialization
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      print('Firebase initialized successfully');
    } else {
      print('Firebase already initialized');
    }
  } catch (e) {
    print('Firebase init error (ignored): $e');
  }

if (!kIsWeb) {
    OneSignal.initialize("322abcb7-c4e5-4630-811f-ccea86a6f481");
    OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
    OneSignal.Notifications.requestPermission(true);
  }

  // Only update OneSignal ID on mobile
  final user = FirebaseAuth.instance.currentUser;
  if (user != null && !kIsWeb) {
    final playerId = await OneSignal.User.getOnesignalId();
    if (playerId != null && playerId.isNotEmpty) {
      await FirebaseDatabase.instance.ref('users/${user.uid}').update({
        'onesignalId': playerId,
        'lastSeen': DateTime.now().toIso8601String(),
      });
    }
  }

  final shorebirdCodePush = ShorebirdCodePush();

  runApp(const AlertSysApp());
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
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
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

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  Future<void> _loadRole() async {
    try {
      final role = await AuthService().getUserRole(widget.uid);
      setState(() {
        _role = role;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _role = 'supervisor';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_role == 'admin') {
      return const AdminDashboardScreen();
    }
    return const DashboardScreen();
  }
}