import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../theme.dart';

/// Horizontal pill-shaped tab bar used at the top of the admin dashboard.
///
/// When [showDeveloperTab] is true (i.e. the admin has enabled Developer
/// Mode from the settings popup), an extra "Developer" tab is appended.
/// The Developer tab's index is `6`; the surrounding screen relies on that
/// being the last index when selecting which body to render.
class PillTabBar extends StatelessWidget {
  final int tab;
  final void Function(int) onSelect;
  final bool showDeveloperTab;
  final Map<int, int> badgeCounts;

  const PillTabBar({
    super.key,
    required this.tab,
    required this.onSelect,
    this.showDeveloperTab = false,
    this.badgeCounts = const {},
  });

  @override
  Widget build(BuildContext context) {
    final l10n = Localizations.of<AppLocalizations>(context, AppLocalizations);
    final tabs = <Map<String, Object>>[
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
      if (showDeveloperTab)
        {'icon': Icons.build_circle_outlined, 'label': 'Developer'},
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
                // The Developer tab is purple-accented so it visually
                // signals "elevated mode" — the surrounding row stays
                // navy-blue, but Developer reads as a distinct tool.
                final isDev = showDeveloperTab && i == tabs.length - 1;
                final activeColor = isDev ? t.purple : t.navy;
                final inactiveBorder = isDev
                    ? t.purple.withValues(alpha: 0.35)
                    : t.border;
                final inactiveText = isDev ? t.purple : t.muted;
                final badgeCount = badgeCounts[i] ?? 0;
                return Padding(
                  padding: const EdgeInsets.only(right: 10, top: 4),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      GestureDetector(
                        onTap: () => onSelect(i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: sel ? activeColor : t.scaffold,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: sel ? activeColor : inactiveBorder,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                item['icon'] as IconData,
                                size: 15,
                                color: sel ? Colors.white : inactiveText,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                item['label'] as String,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: sel ? Colors.white : inactiveText,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (badgeCount > 0)
                        Positioned(
                          top: -8,
                          right: -7,
                          child: _TabCountBadge(count: badgeCount),
                        ),
                    ],
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

class _TabCountBadge extends StatelessWidget {
  final int count;

  const _TabCountBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final label = count > 99 ? '99+' : '$count';
    return Container(
      constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: t.red,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: t.card, width: 2),
        boxShadow: [
          BoxShadow(
            color: t.red.withValues(alpha: 0.26),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Center(
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w900,
            height: 1,
          ),
        ),
      ),
    );
  }
}
