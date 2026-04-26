import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../providers/theme_provider.dart';
import '../theme.dart';
import 'package:url_launcher/url_launcher.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _error;
  String _language = 'en';

  String _t(String key) {
    const copy = {
      'en': {
        'title': 'Sign In',
        'subtitle': 'Sign In (v2.0 - Patched!)',
        'email': 'Email',
        'email_hint': 'your@email.com',
        'password': 'Password',
        'login': 'Sign In',
        'test_accounts': 'Test Accounts:',
        'production_manager': 'Production Manager',
        'supervisor': 'Supervisor',
        'technician': 'Technician',
        'accounts_note': 'Accounts are created by administrators',
      },
      'fr': {
        'title': 'Connexion',
        'subtitle': 'Connexion (v2.0 - Patched!)',
        'email': 'Email',
        'email_hint': 'votre@email.com',
        'password': 'Mot de passe',
        'login': 'Se connecter',
        'test_accounts': 'Comptes de test :',
        'production_manager': 'Chef de Production',
        'supervisor': 'Superviseur',
        'technician': 'Technicien',
        'accounts_note': 'Les comptes sont crees par les administrateurs',
      },
    };

    return copy[_language]?[key] ?? copy['en']![key] ?? key;
  }

  Future<void> _login() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final error = await _authService.login(
      _emailController.text.trim(),
      _passwordController.text.trim(),
    );
    if (mounted) {
      setState(() {
        _isLoading = false;
        _error = error;
      });
    }
  }

  Future<void> _downloadApk() async {
    const url =
        'https://github.com/KubixDesiney/Alert_Sys_App/releases/download/1.0.0B/app-release.apk';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to open download link')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final isDark = context.isDark;

    return Scaffold(
      backgroundColor: t.scaffold,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Top row: APK download, Theme toggle, Language
                  Align(
                    alignment: Alignment.topRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _downloadApk,
                          icon: const Icon(Icons.download, size: 16),
                          label: const Text('Download APK'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: t.navy,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            textStyle: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // ── Theme toggle ──
                        IconButton(
                          icon: Icon(
                            isDark ? Icons.light_mode : Icons.dark_mode,
                            color: t.muted,
                            size: 22,
                          ),
                          tooltip: isDark ? 'Light mode' : 'Dark mode',
                          onPressed: () =>
                              context.read<ThemeProvider>().toggle(),
                        ),
                        const SizedBox(width: 8),
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(value: 'en', label: Text('EN')),
                            ButtonSegment(value: 'fr', label: Text('FR')),
                          ],
                          selected: {_language},
                          onSelectionChanged: (selection) {
                            setState(() {
                              _language = selection.first;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  // Logo / Title
                  Icon(Icons.factory, size: 56, color: t.red),
                  const SizedBox(height: 16),
                  Text(
                    _t('title'),
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: t.textDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _t('subtitle'),
                    style: TextStyle(
                      fontSize: 14,
                      color: t.muted,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),

                  // Card
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: t.card,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: t.border),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Email field
                        Text(
                          _t('email'),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: t.text,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          style: TextStyle(fontSize: 15, color: t.text),
                          decoration: InputDecoration(
                            hintText: _t('email_hint'),
                            hintStyle: TextStyle(color: t.muted),
                            filled: true,
                            fillColor: t.card,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 14),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: t.border),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: t.border),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: t.red, width: 1.5),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),

                        // Password field
                        Text(
                          _t('password'),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: t.text,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          style: TextStyle(fontSize: 15, color: t.text),
                          decoration: InputDecoration(
                            hintText: '********',
                            hintStyle: TextStyle(color: t.muted),
                            filled: true,
                            fillColor: t.card,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 14),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                color: t.muted,
                              ),
                              onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword),
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: t.border),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: t.border),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: t.red, width: 1.5),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Error message
                        if (_error != null)
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: t.redLt,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: t.red),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.error_outline,
                                    color: t.red, size: 16),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _error!,
                                    style:
                                        TextStyle(color: t.red, fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (_error != null) const SizedBox(height: 16),

                        // Login button
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _login,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: t.red,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(
                                    _t('login'),
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 28),

                  // Test accounts info
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: t.scaffold,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: t.border),
                    ),
                    child: Column(
                      children: [
                        Text(
                          _t('test_accounts'),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: t.text,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _testAccountRow(
                            t, 'superadmin@test.com', 'Super Admin'),
                        _testAccountRow(
                            t, 'admin@test.com', _t('production_manager')),
                        _testAccountRow(
                            t, 'superviseur@test.com', _t('supervisor')),
                        _testAccountRow(t, 'tech@test.com', _t('technician')),
                        const SizedBox(height: 8),
                        Text(
                          _t('accounts_note'),
                          style: TextStyle(fontSize: 11, color: t.muted),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _testAccountRow(AppTheme t, String email, String role) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(Icons.person_outline, size: 14, color: t.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              email,
              style: TextStyle(fontSize: 12, color: t.text),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: t.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              role,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: t.red,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
