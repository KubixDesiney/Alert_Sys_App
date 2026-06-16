import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alertsysapp/theme.dart';

void main() {
  // The runtime brand is a global; keep tests isolated.
  tearDown(() => setRuntimeBrand(null));

  group('brandPrimary', () {
    test('falls back to product navy when no brand is set', () {
      setRuntimeBrand(null);
      expect(brandPrimary(false), const Color(0xFF0D4A75));
      expect(brandPrimary(true), const Color(0xFF60A5FA));
    });

    test('uses the brand color verbatim in light mode', () {
      setRuntimeBrand(const Color(0xFFEC4899));
      expect(brandPrimary(false), const Color(0xFFEC4899));
    });

    test('lightens a dark brand for dark mode so it stays legible', () {
      const darkBrand = Color(0xFF3C3489); // deep purple
      setRuntimeBrand(darkBrand);
      final dark = brandPrimary(true);
      expect(dark, isNot(darkBrand));
      expect(
        HSLColor.fromColor(dark).lightness,
        greaterThan(HSLColor.fromColor(darkBrand).lightness),
      );
    });
  });

  group('brandPrimaryTint', () {
    test('falls back to the product tints when unset', () {
      setRuntimeBrand(null);
      expect(brandPrimaryTint(false), const Color(0xFFE8F0F8));
      expect(brandPrimaryTint(true), const Color(0xFF1E3A5F));
    });

    test('produces a soft (light) tint of the brand in light mode', () {
      setRuntimeBrand(const Color(0xFFEC4899));
      final tint = brandPrimaryTint(false);
      // A tint is much lighter than the brand itself.
      expect(
        HSLColor.fromColor(tint).lightness,
        greaterThan(HSLColor.fromColor(const Color(0xFFEC4899)).lightness),
      );
    });
  });

  group('theme builders consume the brand', () {
    test('light ColorScheme primary follows the runtime brand', () {
      setRuntimeBrand(const Color(0xFFEC4899));
      expect(buildLightTheme().colorScheme.primary, const Color(0xFFEC4899));
    });
    test('default light primary is product navy', () {
      setRuntimeBrand(null);
      expect(buildLightTheme().colorScheme.primary, const Color(0xFF0D4A75));
    });
  });
}
