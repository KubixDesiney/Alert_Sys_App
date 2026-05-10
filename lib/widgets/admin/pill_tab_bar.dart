import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../theme.dart';

/// Horizontal pill-shaped tab bar used at the top of the admin dashboard.
class PillTabBar extends StatelessWidget {
  final int tab;
  final void Function(int) onSelect;

  const PillTabBar({super.key, required this.tab, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final l10n = Localizations.of<AppLocalizations>(
      context,
      AppLocalizations,
    );
    final tabs = [
      {'icon': Icons.bar_chart, 'label': l10n?.adminTabOverview ?? 'Overview'},
      {
        'icon': Icons.people,
        'label': l10n?.adminTabSupervisors ?? 'Supervisors',
      },
      {'icon': Icons.schedule, 'label': l10n?.adminTabShifts ?? 'Shifts'},
      {
        'icon': Icons.notifications_outlined,
        'label': l10n?.adminTabAlerts ?? 'Alerts',
      },
      {
        'icon': Icons.warning_amber,
        'label': l10n?.adminTabEscalations ?? 'Escalations',
      },
      {
        'icon': Icons.account_tree,
        'label': l10n?.adminTabHierarchy ?? 'Hierarchy',
      },
    ];
    final t = context.appTheme;
    return Container(
      color: t.card,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: List.generate(tabs.length, (i) {
                final sel = tab == i;
                final item = tabs[i];
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => onSelect(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: sel ? t.navy : t.scaffold,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: sel ? t.navy : t.border),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(
                          item['icon'] as IconData,
                          size: 15,
                          color: sel ? Colors.white : t.muted,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          item['label'] as String,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: sel ? Colors.white : t.muted,
                          ),
                        ),
                      ]),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}
