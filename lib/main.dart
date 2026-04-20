import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'providers/alert_provider.dart';
import 'services/auth_service.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/admin_dashboard_screen.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Check if already initialized to avoid duplicate error on hot restart
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  }

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

// ── AuthGate — listens to Firebase auth state ──────────────────────────────
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Still connecting
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingScreen(message: 'Connecting…');
        }

        // Firebase error
        if (snapshot.hasError) {
          return Scaffold(
            backgroundColor: const Color(0xFFF3F4F6),
            body: Center(
              child: Text('Firebase error:\n${snapshot.error}',
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center),
            ),
          );
        }

        // Logged out → reset provider and show login
        if (!snapshot.hasData || snapshot.data == null) {
          // Reset provider on logout
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Provider.of<AlertProvider>(context, listen: false).reset();
          });
          return const LoginScreen();
        }

        // Logged in → read role and route
        return _RoleRouter(uid: snapshot.data!.uid);
      },
    );
  }
}

// ── _RoleRouter — reads role from RTDB and routes to correct screen ─────────
class _RoleRouter extends StatefulWidget {
  final String uid;
  const _RoleRouter({required this.uid});

  @override
  State<_RoleRouter> createState() => _RoleRouterState();
}

class _RoleRouterState extends State<_RoleRouter> {
  String? _role;
  bool    _loading = true;

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  Future<void> _loadRole() async {
    final role = await AuthService().getUserRole(widget.uid);
    if (!mounted) return;

    // Init provider based on role
    final provider = Provider.of<AlertProvider>(context, listen: false);
    if (role == 'admin') {
      provider.initForProductionManager();
    } else {
      provider.init('Usine A');
    }

    setState(() {
      _role    = role;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const _LoadingScreen(message: 'Loading profile…');

    debugPrint('Routing to role: $_role');

    if (_role == 'admin') return const AdminDashboardScreen();
    return const DashboardScreen();
  }
}

// ── Loading screen ─────────────────────────────────────────────────────────
class _LoadingScreen extends StatelessWidget {
  final String message;
  const _LoadingScreen({required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const CircularProgressIndicator(color: Color(0xFF0D4A75)),
          const SizedBox(height: 16),
          Text(message,
              style: const TextStyle(
                  color: Color(0xFF6B7280),
                  fontFamily: 'monospace',
                  fontSize: 12)),
        ]),
      ),
    );
  }
}