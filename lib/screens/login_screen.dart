import 'package:flutter/material.dart';
import '../services/auth_service.dart';
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

  // Colors
  static const _white = AppColors.white;
  static const _red = AppColors.red;
  static const _redLight = Color(0xFFFEF2F2);
  static const _border = AppColors.borderSoft;
  static const _textDark = AppColors.textDark;
  static const _textMuted = AppColors.textMuted;
  static const _navy = AppColors.navy;

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
        'https://github.com/KubixDesiney/Alert_Sys_App/releases/download/1.0.0B/Alertysysapp.apk';
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
    return Scaffold(
      backgroundColor: _white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
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
                            backgroundColor: _navy,
                            foregroundColor: _white,
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
                  const Icon(Icons.factory_outlined, size: 56, color: _red),
                  const SizedBox(height: 16),
                  Text(
                    _t('title'),
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: _textDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _t('subtitle'),
                    style: TextStyle(
                      fontSize: 14,
                      color: _textMuted,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),

                  // Card
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: _white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _border),
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
                            color: _textDark,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          style: const TextStyle(fontSize: 15),
                          decoration: InputDecoration(
                            hintText: _t('email_hint'),
                            hintStyle: TextStyle(color: _textMuted),
                            filled: true,
                            fillColor: _white,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 14),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: _border),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: _border),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide:
                                  const BorderSide(color: _red, width: 1.5),
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
                            color: _textDark,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          style: const TextStyle(fontSize: 15),
                          decoration: InputDecoration(
                            hintText: '********',
                            hintStyle: TextStyle(color: _textMuted),
                            filled: true,
                            fillColor: _white,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 14),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                color: _textMuted,
                              ),
                              onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword),
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: _border),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: _border),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide:
                                  const BorderSide(color: _red, width: 1.5),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Error message
                        if (_error != null)
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: _redLight,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: _red),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline,
                                    color: _red, size: 16),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _error!,
                                    style: const TextStyle(
                                        color: _red, fontSize: 13),
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
                              backgroundColor: _red,
                              foregroundColor: _white,
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
                                      color: _white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(
                                    _t('login'),
                                    style: TextStyle(
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

                  // Test accounts info (as in the picture)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _border),
                    ),
                    child: Column(
                      children: [
                        Text(
                          _t('test_accounts'),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _textDark,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _testAccountRow('superadmin@test.com', 'Super Admin'),
                        _testAccountRow(
                            'admin@test.com', _t('production_manager')),
                        _testAccountRow(
                            'superviseur@test.com', _t('supervisor')),
                        _testAccountRow('tech@test.com', _t('technician')),
                        const SizedBox(height: 8),
                        Text(
                          _t('accounts_note'),
                          style: TextStyle(fontSize: 11, color: _textMuted),
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

  Widget _testAccountRow(String email, String role) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.person_outline, size: 14, color: _textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              email,
              style: const TextStyle(fontSize: 12, color: _textDark),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: _red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              role,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: _red,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
