import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/company_config.dart';
import '../services/branding_config_service.dart';
import '../theme.dart';

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

  /// Runtime brand color (null → product default navy). Read app-wide through
  /// [AppTheme.navy] and the [ColorScheme], so a change re-skins everything.
  Color? get brandColor => _brandColor;
  String get logoUrl => _logoUrl;
  bool get logoBackgroundless => _logoBackgroundless;

  ThemeProvider() {
    // Seed with the build-time brand (white-label) until branding_config loads.
    _brandColor = CompanyConfig.isConfigured ? CompanyConfig.brandColor : null;
    setRuntimeBrand(_brandColor);
    _load();
    _bindBranding();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _mode = (prefs.getBool(_key) ?? false) ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }

  /// Streams `branding_config` so a save in the studio re-skins every open
  /// dashboard live (public read lets the login screen brand itself too).
  void _bindBranding() {
    try {
      _brandingSub = BrandingConfigService().stream().listen((c) {
        _brandColor = c.primaryColor ??
            (CompanyConfig.isConfigured ? CompanyConfig.brandColor : null);
        _logoUrl = c.logoUrl;
        _logoBackgroundless = c.logoBackgroundless;
        setRuntimeBrand(_brandColor);
        notifyListeners();
      }, onError: (_) {});
    } catch (_) {
      // Branding is best-effort; the app still runs on the default theme.
    }
  }

  /// Instant local apply on the device that just saved (the stream delivers the
  /// same values to other devices a moment later).
  void applyBranding({Color? primary, String? logoUrl, bool? logoBackgroundless}) {
    if (primary != null) {
      _brandColor = primary;
      setRuntimeBrand(primary);
    }
    if (logoUrl != null) _logoUrl = logoUrl;
    if (logoBackgroundless != null) _logoBackgroundless = logoBackgroundless;
    notifyListeners();
  }

  /// Resets branding back to product defaults (the studio's "Reset to default").
  void resetBranding() {
    _brandColor = CompanyConfig.isConfigured ? CompanyConfig.brandColor : null;
    _logoUrl = '';
    _logoBackgroundless = false;
    setRuntimeBrand(_brandColor);
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
