import 'package:alertsysapp/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppTheme color tokens', () {
    test('light scaffold is the documented near-white token', () {
      const t = AppTheme(isDark: false);
      expect(t.scaffold, const Color(0xFFF8FAFC));
      expect(t.card, Colors.white);
    });

    test('dark scaffold is the documented near-black token', () {
      const t = AppTheme(isDark: true);
      expect(t.scaffold, const Color(0xFF0F172A));
      expect(t.card, const Color(0xFF1E293B));
    });

    test('navy brand differs between modes', () {
      const light = AppTheme(isDark: false);
      const dark = AppTheme(isDark: true);
      expect(light.navy, const Color(0xFF0D4A75));
      expect(dark.navy, const Color(0xFF60A5FA));
    });

    test('status colours are consistent across the value object', () {
      const t = AppTheme(isDark: false);
      // Sanity: status accent and its light pair are different shades.
      expect(t.red, isNot(t.redLt));
      expect(t.green, isNot(t.greenLt));
    });
  });

  group('AppTheme extension', () {
    testWidgets('reads brightness from MaterialApp', (tester) async {
      late AppTheme tCaptured;
      late bool isDarkCaptured;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(),
          darkTheme: ThemeData.dark(),
          themeMode: ThemeMode.dark,
          home: Builder(
            builder: (context) {
              tCaptured = context.appTheme;
              isDarkCaptured = context.isDark;
              return const SizedBox();
            },
          ),
        ),
      );

      expect(isDarkCaptured, isTrue);
      expect(tCaptured.isDark, isTrue);
    });
  });

  group('ThemeData factories', () {
    test('buildLightTheme produces a light theme', () {
      final theme = buildLightTheme();
      expect(theme.brightness, Brightness.light);
      expect(theme.scaffoldBackgroundColor, const Color(0xFFF8FAFC));
    });

    test('buildDarkTheme produces a dark theme', () {
      final theme = buildDarkTheme();
      expect(theme.brightness, Brightness.dark);
      expect(theme.scaffoldBackgroundColor, const Color(0xFF0F172A));
    });
  });

  group('AppColors', () {
    test('exposes brand-navy and brand-red constants', () {
      expect(AppColors.navy, const Color(0xFF0D4A75));
      expect(AppColors.red, const Color(0xFFDC2626));
    });
  });
}
