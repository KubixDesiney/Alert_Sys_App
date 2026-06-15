import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

/// Per-company branding, configured live by the IT team in the SuperAdmin
/// Branding & Theme studio and applied app-wide at runtime.
///
/// Stored at `branding_config` (public read so the login screen can brand
/// itself before sign-in; superadmin write). Overrides the build-time
/// [CompanyConfig] defaults when present.
class BrandingConfig {
  final Color? primaryColor;
  final Color? accentColor;
  final String logoUrl;
  final bool logoBackgroundless;
  final bool? defaultDark;
  final String updatedAt;

  const BrandingConfig({
    this.primaryColor,
    this.accentColor,
    this.logoUrl = '',
    this.logoBackgroundless = false,
    this.defaultDark,
    this.updatedAt = '',
  });

  static const empty = BrandingConfig();

  bool get hasLogo => logoUrl.trim().isNotEmpty;

  BrandingConfig copyWith({
    Color? primaryColor,
    Color? accentColor,
    String? logoUrl,
    bool? logoBackgroundless,
    bool? defaultDark,
  }) =>
      BrandingConfig(
        primaryColor: primaryColor ?? this.primaryColor,
        accentColor: accentColor ?? this.accentColor,
        logoUrl: logoUrl ?? this.logoUrl,
        logoBackgroundless: logoBackgroundless ?? this.logoBackgroundless,
        defaultDark: defaultDark ?? this.defaultDark,
        updatedAt: updatedAt,
      );

  factory BrandingConfig.fromMap(Map<dynamic, dynamic>? m) {
    if (m == null) return empty;
    return BrandingConfig(
      primaryColor: parseColor(m['primaryColor']?.toString()),
      accentColor: parseColor(m['accentColor']?.toString()),
      logoUrl: m['logoUrl']?.toString() ?? '',
      logoBackgroundless: m['logoBackgroundless'] == true,
      defaultDark: m['defaultDark'] is bool ? m['defaultDark'] as bool : null,
      updatedAt: m['updatedAt']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        if (primaryColor != null) 'primaryColor': colorToHex(primaryColor!),
        if (accentColor != null) 'accentColor': colorToHex(accentColor!),
        'logoUrl': logoUrl.trim(),
        'logoBackgroundless': logoBackgroundless,
        if (defaultDark != null) 'defaultDark': defaultDark,
        'updatedAt': DateTime.now().toIso8601String(),
      };

  /// Accepts `0xFFRRGGBB`, `#RRGGBB`, `#AARRGGBB`, or bare `RRGGBB`.
  static Color? parseColor(String? raw) {
    if (raw == null) return null;
    var s = raw.trim();
    if (s.isEmpty) return null;
    if (s.startsWith('#')) s = s.substring(1);
    if (s.startsWith('0x') || s.startsWith('0X')) s = s.substring(2);
    if (s.length == 6) s = 'FF$s';
    final v = int.tryParse(s, radix: 16);
    return v == null ? null : Color(v);
  }

  static String colorToHex(Color c) =>
      '0x${c.value.toRadixString(16).padLeft(8, '0').toUpperCase()}';
}

class BrandingConfigService {
  BrandingConfigService({FirebaseDatabase? db})
      : _ref = (db ?? FirebaseDatabase.instance).ref('branding_config');

  final DatabaseReference _ref;

  Stream<BrandingConfig> stream() => _ref.onValue.map(
      (e) => BrandingConfig.fromMap(e.snapshot.value as Map<dynamic, dynamic>?));

  Future<BrandingConfig> fetch() async {
    final snap = await _ref.get();
    return BrandingConfig.fromMap(snap.value as Map<dynamic, dynamic>?);
  }

  Future<void> save(BrandingConfig config) => _ref.update(config.toMap());
}
