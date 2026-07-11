import 'package:alertsysapp/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// WCAG 2.1 relative-contrast ratio between two opaque colours.
/// ratio = (Llighter + 0.05) / (Ldarker + 0.05), range 1..21.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  // The surfaces the brand/muted text actually sits on.
  const lightCard = Colors.white;
  const darkCard = Color(0xFF1E293B); // AppTheme.card (dark)

  group('brand primary contrast', () {
    test('light-mode navy on white card meets WCAG AA (>= 4.5:1)', () {
      expect(_contrast(brandPrimary(false), lightCard),
          greaterThanOrEqualTo(4.5));
    });

    test('dark-mode navy on dark card meets WCAG AA (>= 4.5:1)', () {
      // This is the exact regression the reviewer flagged: the old code used
      // brandPrimary(false) (=#0D4A75) on the dark card, which is only ~1.57:1.
      final fixed = _contrast(brandPrimary(true), darkCard);
      final oldBug = _contrast(brandPrimary(false), darkCard);
      expect(oldBug, lessThan(2.0)); // documents the regression
      expect(fixed, greaterThanOrEqualTo(4.5));
    });
  });

  group('theme-aware global getters follow the active brightness', () {
    test('themeBrandPrimary tracks setThemeBrightness', () {
      setThemeBrightness(false);
      expect(themeBrandPrimary, brandPrimary(false));
      expect(appIsDark, isFalse);

      setThemeBrightness(true);
      expect(themeBrandPrimary, brandPrimary(true));
      expect(appIsDark, isTrue);

      // …and the dark value is the readable one on a dark card.
      expect(_contrast(themeBrandPrimary, darkCard),
          greaterThanOrEqualTo(4.5));

      setThemeBrightness(false); // restore default for other tests
    });

    test('themeMuted meets AA on its surface in both themes', () {
      setThemeBrightness(false);
      expect(_contrast(themeMuted, lightCard), greaterThanOrEqualTo(4.5));
      setThemeBrightness(true);
      expect(_contrast(themeMuted, darkCard), greaterThanOrEqualTo(4.5));
      setThemeBrightness(false);
    });
  });
}
