import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../theme.dart';

/// Horizontal pill-shaped tab bar used at the top of the admin dashboard.
///
class PillTabBar extends StatelessWidget {
  final int tab;
  final void Function(int) onSelect;
  final Map<int, int> badgeCounts;

  const PillTabBar({
    super.key,
    required this.tab,
    required this.onSelect,
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
                final activeColor = t.navy;
                final inactiveBorder = t.border;
                final inactiveText = t.muted;
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
