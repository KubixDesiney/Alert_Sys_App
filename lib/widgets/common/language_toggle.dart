import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_strings.dart';
import '../../providers/locale_provider.dart';

/// A compact EN/FR language switcher: a translate icon plus the active language
/// code. Tapping flips the app between English and French instantly via
/// [LocaleProvider]. Drop it into any header/app bar.
class LanguageToggle extends StatelessWidget {
  /// Foreground color. Defaults to the ambient [IconTheme] color.
  final Color? color;
  final double iconSize;

  /// When true, renders a bordered "chip" look (for light surfaces/app bars);
  /// otherwise a plain icon+label button.
  final bool chip;

  const LanguageToggle({
    super.key,
    this.color,
    this.iconSize = 20,
    this.chip = false,
  });

  @override
  Widget build(BuildContext context) {
    // Tolerate a missing provider (e.g. isolated widget tests/previews): the
    // real app always supplies one, but we never want the chrome to crash.
    final lp = context.watch<LocaleProvider?>();
    final c = color ?? IconTheme.of(context).color ?? const Color(0xFF64748B);
    final code = (lp?.isFrench ?? context.isFrench) ? 'FR' : 'EN';

    final inner = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.translate, size: iconSize, color: c),
        const SizedBox(width: 5),
        Text(
          code,
          style: TextStyle(
            color: c,
            fontWeight: FontWeight.w700,
            fontSize: 12,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );

    return Tooltip(
      message: context.tr('Switch language'),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: lp?.toggle,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: chip ? 10 : 8,
              vertical: chip ? 6 : 6,
            ),
            decoration: chip
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: c.withValues(alpha: 0.35)),
                  )
                : null,
            child: inner,
          ),
        ),
      ),
    );
  }
}

/// An explicit two-segment EN/FR selector for settings panels and the login
/// screen, wired to the global [LocaleProvider].
class LanguageSegmented extends StatelessWidget {
  const LanguageSegmented({super.key});

  @override
  Widget build(BuildContext context) {
    final lp = context.watch<LocaleProvider?>();
    final code =
        lp?.languageCode ?? (context.isFrench ? 'fr' : 'en');
    return SegmentedButton<String>(
      segments: const [
        ButtonSegment(value: 'en', label: Text('EN')),
        ButtonSegment(value: 'fr', label: Text('FR')),
      ],
      selected: {code},
      showSelectedIcon: false,
      onSelectionChanged: lp == null
          ? null
          : (selection) => lp.setFrench(selection.first == 'fr'),
    );
  }
}
