import 'package:flutter/widgets.dart';

import 'strings_fr.dart';

/// Runtime EN/FR translation dictionary.
///
/// Keys are the **English source text itself**, so any string that has not been
/// translated yet still renders correctly in English — French is layered on top
/// via [kStringsFr]. This keeps localizing the whole app low-friction: wrap a
/// literal with `context.tr('...')` and add one entry to the French map.
///
/// Usage:
/// ```dart
/// Text(context.tr('Resolve alert'))
/// Text(context.tr('Welcome back, {name}', {'name': user.firstName}))
/// ```
class AppStrings {
  const AppStrings._();

  /// Translate [source] for [languageCode], interpolating any `{placeholder}`
  /// tokens found in [params].
  static String translate(
    String source,
    String languageCode, [
    Map<String, String>? params,
  ]) {
    var out = source;
    if (languageCode == 'fr') {
      out = kStringsFr[source] ?? source;
    }
    if (params != null && params.isNotEmpty) {
      params.forEach((key, value) {
        out = out.replaceAll('{$key}', value);
      });
    }
    return out;
  }
}

extension AppLocalizationX on BuildContext {
  /// Localize [source] (English text) for the app's current language.
  ///
  /// Reads the active locale from the nearest [Localizations] ancestor, so when
  /// [LocaleProvider] flips `MaterialApp.locale` every visible `tr(...)` call
  /// re-renders in the new language. Optional [params] interpolate
  /// `{name}`-style placeholders.
  String tr(String source, [Map<String, String>? params]) {
    final lang = Localizations.maybeLocaleOf(this)?.languageCode ?? 'en';
    return AppStrings.translate(source, lang, params);
  }

  /// Whether the app is currently showing French.
  bool get isFrench =>
      (Localizations.maybeLocaleOf(this)?.languageCode ?? 'en') == 'fr';
}
