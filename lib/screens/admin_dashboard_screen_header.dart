part of 'admin_dashboard_screen.dart';

class _Header extends StatelessWidget {
  final int activeSups;
  final VoidCallback onLogout;
  final VoidCallback onSimulateAlert;
  final bool enableNotifications;

  const _Header({
    required this.activeSups,
    required this.onLogout,
    required this.onSimulateAlert,
    this.enableNotifications = true,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final isDark = context.isDark;
    return Container(
      color: t.card,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: t.navyLt,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: t.border),
            ),
            child: Center(child: Icon(Icons.factory, size: 22, color: t.navy)),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('Production Manager'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: t.navy,
                    letterSpacing: .2,
                  ),
                ),
                Text(
                  context.tr('Production Manager - Dashboard'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: t.muted),
                ),
              ],
            ),
          ),
          const Spacer(),
          // ── Simulate Alert ──
          IconButton(
            onPressed: onSimulateAlert,
            icon: Icon(Icons.add_alert, size: 20, color: t.navy),
            tooltip: context.tr('Simulate Alert'),
            style: IconButton.styleFrom(
              side: BorderSide(color: t.border),
              padding: const EdgeInsets.all(10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // ── Language toggle ──
          LanguageToggle(color: t.muted),
          const SizedBox(width: 4),
          // ── Theme toggle ──
          IconButton(
            icon: Icon(
              isDark ? Icons.light_mode : Icons.dark_mode,
              color: t.muted,
              size: 22,
            ),
            tooltip: isDark ? context.tr('Light mode') : context.tr('Dark mode'),
            onPressed: () => context.read<ThemeProvider>().toggle(),
          ),
          // ── Notifications ──
          AdminNotificationBell(enabled: enableNotifications),
          const SizedBox(width: 4),
          OutlinedButton.icon(
            onPressed: onLogout,
            icon: Icon(Icons.logout, size: 15, color: t.red),
            label: Text(
              context.tr('Sign Out'),
              style: TextStyle(
                color: t.red,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: t.red),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
