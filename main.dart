import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'providers/alert_provider.dart';
import 'services/auth_service.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Request notification permission
  final messaging = FirebaseMessaging.instance;
  await messaging.requestPermission();

  // Get the device token (save this to Firestore linked to the user)
  final token = await messaging.getToken();
  print('FCM Token: $token');

  // Listen for foreground messages
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
  print('Got a message: ${message.notification?.title}');
  // Show a local notification here
});
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
          scaffoldBackgroundColor: const Color(0xFF0D0F14),
          colorScheme: ColorScheme.dark(
            primary: const Color(0xFFE85D26),
            surface: const Color(0xFF161920),
          ),
          fontFamily: 'Inter',
        ),
        home: const AuthGate(),
      ),
    );
  }
}

// Decides whether to show Login or Dashboard
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = AuthService();
    return StreamBuilder(
      stream: auth.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasData) {
          return const DashboardScreen();
        }
        return const LoginScreen();
      },
    );
  }
}
