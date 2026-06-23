import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-wide language selection (English / French).
///
/// Mirrors [ThemeProvider]: persists the choice to [SharedPreferences] and
/// drives `MaterialApp.locale`, so flipping the language re-skins every open
/// screen instantly. The active language is read at render time via
/// `Localizations.localeOf(context)` by the `context.tr(...)` helper in
/// `lib/l10n/app_strings.dart`.
class LocaleProvider extends ChangeNotifier {
  static const _key = 'appLanguageCode';

  /// The two languages SIA ships. English is the source/default; French is the
  /// full translation.
  static const List<Locale> supported = [Locale('en'), Locale('fr')];

  Locale _locale = const Locale('en');

  LocaleProvider() {
    _load();
  }

  Locale get locale => _locale;
  String get languageCode => _locale.languageCode;
  bool get isFrench => _locale.languageCode == 'fr';

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final code = prefs.getString(_key);
      if (code == 'fr' || code == 'en') {
        _locale = Locale(code!);
        notifyListeners();
      }
    } catch (_) {
      // Best-effort; default English stands if prefs are unavailable.
    }
  }

  Future<void> setLocale(Locale locale) async {
    final code = locale.languageCode == 'fr' ? 'fr' : 'en';
    if (code == _locale.languageCode) return;
    _locale = Locale(code);
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, code);
    } catch (_) {
      // Non-fatal: the choice still applies for this session.
    }
  }

  /// Flip between the two supported languages.
  Future<void> toggle() =>
      setLocale(isFrench ? const Locale('en') : const Locale('fr'));

  Future<void> setFrench(bool french) =>
      setLocale(Locale(french ? 'fr' : 'en'));
}
