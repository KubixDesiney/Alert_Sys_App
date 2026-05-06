import 'package:flutter/material.dart';

import '../../theme.dart';

/// Bottom navigation bar for the supervisor dashboard. Routes between the
/// Dashboard, Locator, Station Scan, and Collaboration tabs.
class DashboardBottomNav extends StatelessWidget {
  final int currentIndex;
  final void Function(int) onTap;

  const DashboardBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Container(
      decoration: BoxDecoration(
        color: t.navBar,
        border: Border(top: BorderSide(color: t.border, width: 1)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              _NavBtn(
                icon: Icons.dashboard,
                label: 'Dashboard',
                selected: currentIndex == 0,
                onTap: () => onTap(0),
              ),
              _NavBtn(
                icon: Icons.map,
                label: 'Locator',
                selected: currentIndex == 1,
                onTap: () => onTap(1),
              ),
              _NavBtn(
                icon: Icons.qr_code_scanner,
                label: 'Station Scan',
                selected: currentIndex == 2,
                onTap: () => onTap(2),
              ),
              _NavBtn(
                icon: Icons.handshake,
                label: 'Collab Progress',
                selected: currentIndex == 3,
                onTap: () => onTap(3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavBtn({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: selected
              ? BoxDecoration(
                  color: t.navy,
                  borderRadius: BorderRadius.circular(12),
                )
              : const BoxDecoration(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: selected ? Colors.white : t.muted),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  color: selected ? Colors.white : t.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
