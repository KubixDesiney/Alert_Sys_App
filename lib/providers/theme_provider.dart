import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/branding_config_service.dart';

class ThemeProvider extends ChangeNotifier {
  static const _key = 'isDarkMode';
  ThemeMode _mode = ThemeMode.light;

  // Live, IT-configured branding (SuperAdmin → Branding & Theme).
  Color? _brandColor;
  String _logoUrl = '';
  bool _logoBackgroundless = false;
  StreamSubscription? _brandingSub;

  ThemeMode get mode => _mode;
  bool get isDark => _mode == ThemeMode.dark;

  /// Runtime brand color from `branding_config`, or null to fall back to the
  /// build-time CompanyConfig default.
  Color? get brandColor => _brandColor;
  String get logoUrl => _logoUrl;
  bool get logoBackgroundless => _logoBackgroundless;

  ThemeProvider() {
    _load();
    _bindBranding();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _mode = (prefs.getBool(_key) ?? false) ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }

  /// Streams `branding_config` so a save in the studio re-skins every open
  /// dashboard live. Public read on the node lets even the login screen brand
  /// itself before sign-in.
  void _bindBranding() {
    try {
      _brandingSub = BrandingConfigService().stream().listen((c) {
        _brandColor = c.primaryColor;
        _logoUrl = c.logoUrl;
        _logoBackgroundless = c.logoBackgroundless;
        notifyListeners();
      }, onError: (_) {});
    } catch (_) {
      // Branding is best-effort; the app still runs on CompanyConfig defaults.
    }
  }

  /// Instant local apply on the device that just saved (the stream delivers the
  /// same values to every other device a moment later).
  void applyBranding({Color? primary, String? logoUrl, bool? logoBackgroundless}) {
    if (primary != null) _brandColor = primary;
    if (logoUrl != null) _logoUrl = logoUrl;
    if (logoBackgroundless != null) _logoBackgroundless = logoBackgroundless;
    notifyListeners();
  }

  Future<void> toggle() async {
    _mode = isDark ? ThemeMode.light : ThemeMode.dark;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, isDark);
    notifyListeners();
  }

  @override
  void dispose() {
    _brandingSub?.cancel();
    super.dispose();
  }
}
