import 'package:flutter/material.dart';
import '../services/auth_service.dart';

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
  bool _showPassword = false;
  String? _error;

  // Color constants
  static const bg = Color(0xFF0D0F14);
  static const surface = Color(0xFF161920);
  static const border = Color(0xFF252D3D);
  static const accent = Color(0xFFE85D26);
  static const muted = Color(0xFF6B7A96);

  Future<void> _login() async {
    setState(() { _isLoading = true; _error = null; });
    final error = await _authService.login(
      _emailController.text.trim(),
      _passwordController.text.trim(),
    );
    if (mounted) {
      setState(() { _isLoading = false; _error = error; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.1),
                  border: Border.all(color: accent, width: 2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Center(child: Text('🏭', style: TextStyle(fontSize: 32))),
              ),
              const SizedBox(height: 20),
              const Text(
                'ALERTSYS',
                style: TextStyle(
                  fontFamily: 'Barlow Condensed',
                  fontSize: 32, fontWeight: FontWeight.w800,
                  color: Colors.white, letterSpacing: 2,
                ),
              ),
              const Text(
                'SUPERVISION INDUSTRIELLE',
                style: TextStyle(fontSize: 11, color: muted, letterSpacing: 4),
              ),
              const SizedBox(height: 40),

              // Form card
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: surface,
                  border: Border.all(color: border),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLabel('Identifiant (email)'),
                    const SizedBox(height: 8),
                    _buildTextField(
                      controller: _emailController,
                      hint: 'superviseur@sagem.com',
                      icon: Icons.person_outline,
                    ),
                    const SizedBox(height: 20),
                    _buildLabel('Mot de passe'),
                    const SizedBox(height: 8),
                    _buildTextField(
                      controller: _passwordController,
                      hint: '••••••••',
                      icon: Icons.lock_outline,
                      isPassword: true,
                      showPassword: _showPassword,
                      onTogglePassword: () => setState(() => _showPassword = !_showPassword),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.1),
                          border: Border.all(color: Colors.red.shade400),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(children: [
                          const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 16),
                          const SizedBox(width: 8),
                          Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                        ]),
                      ),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _login,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accent,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: _isLoading
                            ? const SizedBox(width: 20, height: 20,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Text(
                                '→ SE CONNECTER',
                                style: TextStyle(fontFamily: 'Barlow Condensed',
                                    fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 2),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(text.toUpperCase(),
      style: const TextStyle(fontSize: 10, color: muted, fontWeight: FontWeight.w600, letterSpacing: 2));
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool isPassword = false,
    bool showPassword = false,
    VoidCallback? onTogglePassword,
  }) {
    return TextField(
      controller: controller,
      obscureText: isPassword && !showPassword,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: muted),
        prefixIcon: Icon(icon, color: muted, size: 18),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(showPassword ? Icons.visibility_off : Icons.visibility, color: muted, size: 18),
                onPressed: onTogglePassword,
              )
            : null,
        filled: true,
        fillColor: const Color(0xFF0D0F14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: accent),
        ),
      ),
    );
  }
}