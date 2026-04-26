import 'package:flutter/material.dart';

// Static light-mode palette (kept for backward-compat const references)
class AppColors {
  static const Color navy = Color(0xFF0D4A75);
  static const Color navyLight = Color(0xFFE8F0F8);
  static const Color red = Color(0xFFDC2626);
  static const Color redAlt = Color(0xFFE31E24);
  static const Color white = Colors.white;
  static const Color bg = Color(0xFFF8FAFC);
  static const Color border = Color(0xFFE2E8F0);
  static const Color borderSoft = Color(0xFFE5E7EB);
  static const Color muted = Color(0xFF94A3B8);
  static const Color mutedDark = Color(0xFF64748B);
  static const Color text = Color(0xFF1E293B);
  static const Color textDark = Color(0xFF111827);
  static const Color textMuted = Color(0xFF6B7280);
  static const Color green = Color(0xFF16A34A);
  static const Color greenLight = Color(0xFFDCFCE7);
  static const Color orange = Color(0xFFEA580C);
  static const Color orangeLight = Color(0xFFFFF7ED);
  static const Color blue = Color(0xFF2563EB);
  static const Color blueLight = Color(0xFFEFF6FF);
  static const Color yellow = Color(0xFFFBBF24);
}

// Dynamic color tokens — picks correct value for light or dark brightness.
class AppTheme {
  final bool isDark;
  const AppTheme({required this.isDark});

  // ── Backgrounds ──────────────────────────────────────────────
  Color get scaffold => isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
  Color get card     => isDark ? const Color(0xFF1E293B) : Colors.white;
  Color get navBar   => isDark ? const Color(0xFF1E293B) : Colors.white;
  Color get bg       => scaffold;
  Color get white    => card; // alias used by screens

  // ── Brand ─────────────────────────────────────────────────────
  Color get navy     => isDark ? const Color(0xFF60A5FA) : const Color(0xFF0D4A75);
  Color get navyLt   => isDark ? const Color(0xFF1E3A5F) : const Color(0xFFE8F0F8);

  // ── Text ──────────────────────────────────────────────────────
  Color get text     => isDark ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B);
  Color get textDark => isDark ? const Color(0xFFF8FAFC) : const Color(0xFF111827);
  Color get muted    => isDark ? const Color(0xFF94A3B8) : const Color(0xFF6B7280);
  Color get mutedDk  => isDark ? const Color(0xFF64748B) : const Color(0xFF64748B);

  // ── Status ────────────────────────────────────────────────────
  Color get red      => isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626);
  Color get redAlt   => isDark ? const Color(0xFFF87171) : const Color(0xFFE31E24);
  Color get redLt    => isDark ? const Color(0xFF450A0A) : const Color(0xFFFEE2E2);
  Color get green    => isDark ? const Color(0xFF4ADE80) : const Color(0xFF16A34A);
  Color get greenLt  => isDark ? const Color(0xFF052E16) : const Color(0xFFDCFCE7);
  Color get orange   => isDark ? const Color(0xFFFB923C) : const Color(0xFFEA580C);
  Color get orangeLt => isDark ? const Color(0xFF431407) : const Color(0xFFFFF7ED);
  Color get blue     => isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB);
  Color get blueLt   => isDark ? const Color(0xFF0C1A3D) : const Color(0xFFEFF6FF);
  Color get yellow   => isDark ? const Color(0xFFFACC15) : const Color(0xFFD97706);
  Color get yellowLt => isDark ? const Color(0xFF422006) : const Color(0xFFFEF3C7);
  Color get purple   => isDark ? const Color(0xFFC084FC) : const Color(0xFF9333EA);

  // ── Surface / Border ─────────────────────────────────────────
  Color get border   => isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
  Color get borderSoft => isDark ? const Color(0xFF475569) : const Color(0xFFE5E7EB);
}

// One-liner access from any widget: context.appTheme.navy, context.isDark, etc.
extension AppThemeExtension on BuildContext {
  AppTheme get appTheme =>
      AppTheme(isDark: Theme.of(this).brightness == Brightness.dark);
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}

// ── Shared ThemeData definitions ─────────────────────────────────────────────

ThemeData buildLightTheme() => ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: const Color(0xFFF8FAFC),
      colorScheme: const ColorScheme.light(
        primary: Color(0xFF0D4A75),
        secondary: Color(0xFF0D4A75),
        surface: Colors.white,
        error: Color(0xFFE31E24),
        onPrimary: Colors.white,
        onSurface: Color(0xFF1E293B),
        onError: Colors.white,
      ),
      cardTheme: const CardThemeData(color: Colors.white, elevation: 0),
      dialogTheme: const DialogThemeData(backgroundColor: Colors.white),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: Color(0xFF1E293B),
        elevation: 0,
        iconTheme: IconThemeData(color: Color(0xFF0D4A75)),
      ),
      iconTheme: const IconThemeData(color: Color(0xFF0D4A75)),
      dividerColor: const Color(0xFFE2E8F0),
      snackBarTheme: const SnackBarThemeData(
        contentTextStyle: TextStyle(color: Colors.white),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        filled: true,
        fillColor: Colors.white,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: Color(0xFF0D4A75),
        unselectedItemColor: Color(0xFF6B7280),
        elevation: 0,
      ),
      dropdownMenuTheme: const DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(Colors.white),
        ),
      ),
    );

ThemeData buildDarkTheme() => ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF0F172A),
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF60A5FA),
        secondary: Color(0xFF60A5FA),
        surface: Color(0xFF1E293B),
        error: Color(0xFFF87171),
        onPrimary: Colors.white,
        onSurface: Color(0xFFF1F5F9),
        onError: Colors.white,
      ),
      cardTheme: const CardThemeData(color: Color(0xFF1E293B), elevation: 0),
      dialogTheme: const DialogThemeData(
        backgroundColor: Color(0xFF1E293B),
        titleTextStyle: TextStyle(
          color: Color(0xFFF1F5F9),
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        contentTextStyle: TextStyle(color: Color(0xFFCBD5E1), fontSize: 14),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF1E293B),
        foregroundColor: Color(0xFFF1F5F9),
        elevation: 0,
        iconTheme: IconThemeData(color: Color(0xFF60A5FA)),
      ),
      iconTheme: const IconThemeData(color: Color(0xFF94A3B8)),
      dividerColor: const Color(0xFF334155),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: Color(0xFF1E293B),
        contentTextStyle: TextStyle(color: Color(0xFFF1F5F9)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF334155)),
        ),
        filled: true,
        fillColor: const Color(0xFF1E293B),
        hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
        labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Color(0xFF1E293B),
        selectedItemColor: Color(0xFF60A5FA),
        unselectedItemColor: Color(0xFF94A3B8),
        elevation: 0,
      ),
      dropdownMenuTheme: const DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(Color(0xFF1E293B)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: const Color(0xFF60A5FA)),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF60A5FA),
          side: const BorderSide(color: Color(0xFF334155)),
        ),
      ),
      popupMenuTheme: const PopupMenuThemeData(
        color: Color(0xFF1E293B),
        textStyle: TextStyle(color: Color(0xFFF1F5F9)),
      ),
      listTileTheme: const ListTileThemeData(
        tileColor: Color(0xFF1E293B),
        textColor: Color(0xFFF1F5F9),
        iconColor: Color(0xFF94A3B8),
      ),
    );
