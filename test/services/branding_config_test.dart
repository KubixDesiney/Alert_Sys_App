import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alertsysapp/services/branding_config_service.dart';

void main() {
  group('BrandingConfig.parseColor', () {
    test('parses # hex (6 digits, FF alpha added)', () {
      expect(BrandingConfig.parseColor('#1565C0'), const Color(0xFF1565C0));
    });
    test('parses 0x ARGB literal', () {
      expect(BrandingConfig.parseColor('0xFF1565C0'), const Color(0xFF1565C0));
    });
    test('parses bare 6-digit hex', () {
      expect(BrandingConfig.parseColor('1565C0'), const Color(0xFF1565C0));
    });
    test('parses 8-digit # (explicit alpha)', () {
      expect(BrandingConfig.parseColor('#8012AB34'), const Color(0x8012AB34));
    });
    test('is case-insensitive', () {
      expect(BrandingConfig.parseColor('#ec4899'), const Color(0xFFEC4899));
    });
    test('returns null for empty/null/garbage', () {
      expect(BrandingConfig.parseColor(null), isNull);
      expect(BrandingConfig.parseColor(''), isNull);
      expect(BrandingConfig.parseColor('   '), isNull);
      expect(BrandingConfig.parseColor('not-a-color'), isNull);
    });
  });

  group('BrandingConfig.colorToHex', () {
    test('formats as 0xAARRGGBB upper-case', () {
      expect(BrandingConfig.colorToHex(const Color(0xFF1565C0)), '0xFF1565C0');
      expect(BrandingConfig.colorToHex(const Color(0xFFEC4899)), '0xFFEC4899');
    });
    test('round-trips with parseColor', () {
      for (final c in const [
        Color(0xFF0D4A75),
        Color(0xFFEC4899),
        Color(0x8012AB34),
      ]) {
        expect(BrandingConfig.parseColor(BrandingConfig.colorToHex(c)), c);
      }
    });
  });

  group('BrandingConfig.fromMap', () {
    test('null map yields empty config', () {
      final c = BrandingConfig.fromMap(null);
      expect(c.primaryColor, isNull);
      expect(c.accentColor, isNull);
      expect(c.logoUrl, '');
      expect(c.logoBackgroundless, isFalse);
      expect(c.defaultDark, isNull);
    });
    test('deserializes all fields', () {
      final c = BrandingConfig.fromMap({
        'primaryColor': '0xFFEC4899',
        'accentColor': '#10B981',
        'logoUrl': 'https://acme.com/logo.png',
        'logoBackgroundless': true,
        'defaultDark': true,
      });
      expect(c.primaryColor, const Color(0xFFEC4899));
      expect(c.accentColor, const Color(0xFF10B981));
      expect(c.logoUrl, 'https://acme.com/logo.png');
      expect(c.logoBackgroundless, isTrue);
      expect(c.defaultDark, isTrue);
    });
    test('logoBackgroundless only true for boolean true', () {
      expect(BrandingConfig.fromMap({'logoBackgroundless': 'true'}).logoBackgroundless, isFalse);
      expect(BrandingConfig.fromMap({'logoBackgroundless': 1}).logoBackgroundless, isFalse);
    });
  });

  group('BrandingConfig.toMap', () {
    test('omits null colors and includes set fields', () {
      final m = const BrandingConfig(
        primaryColor: Color(0xFFEC4899),
        logoUrl: 'https://x',
        logoBackgroundless: true,
      ).toMap();
      expect(m['primaryColor'], '0xFFEC4899');
      expect(m.containsKey('accentColor'), isFalse);
      expect(m['logoUrl'], 'https://x');
      expect(m['logoBackgroundless'], isTrue);
      expect(m.containsKey('updatedAt'), isTrue);
    });
    test('trims the logo url', () {
      final m = const BrandingConfig(logoUrl: '  https://x  ').toMap();
      expect(m['logoUrl'], 'https://x');
    });
  });

  group('BrandingConfig.copyWith / hasLogo', () {
    test('copyWith overrides only the given field', () {
      final c = BrandingConfig.empty.copyWith(primaryColor: const Color(0xFF112233));
      expect(c.primaryColor, const Color(0xFF112233));
      expect(c.logoUrl, '');
      expect(c.logoBackgroundless, isFalse);
    });
    test('hasLogo ignores whitespace', () {
      expect(const BrandingConfig(logoUrl: '   ').hasLogo, isFalse);
      expect(const BrandingConfig(logoUrl: 'x').hasLogo, isTrue);
    });
  });
}
