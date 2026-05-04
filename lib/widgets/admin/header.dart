import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../../services/app_logger.dart';
import '../../services/service_locator.dart';
import '../../theme.dart';
import '../dashboard_common.dart';

class AdminDashboardHeader extends StatefulWidget {
  const AdminDashboardHeader({
    super.key,
    required this.activeSups,
    required this.onLogout,
    required this.onSimulateAlert,
  });

  final int activeSups;
  final VoidCallback onLogout;
  final VoidCallback onSimulateAlert;

  @override
  State<AdminDashboardHeader> createState() => _AdminDashboardHeaderState();
}

class _AdminDashboardHeaderState extends State<AdminDashboardHeader> {
  final AppLogger _logger = ServiceLocator.instance.logger;

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Container(
      color: t.card,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          const DashboardUserInfo(
            title: 'Production Manager',
            subtitle: 'Production Manager - Dashboard',
          ),
          const Spacer(),
          IconButton(
            onPressed: widget.onSimulateAlert,
            icon: Icon(Icons.add_alert, size: 20, color: t.navy),
            tooltip: 'Simulate Alert',
            style: IconButton.styleFrom(
              side: BorderSide(color: t.border),
              padding: const EdgeInsets.all(10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(width: 8),
          const DashboardThemeToggleButton(),
          const SizedBox(width: 8),
          NotificationCenter(builder: (ctx, count, notifications, show) {
            return DashboardNotificationBell(
              count: count,
              onPressed: show,
            );
          }),
          const SizedBox(width: 4),
          OutlinedButton.icon(
            onPressed: widget.onLogout,
            icon: Icon(Icons.logout, size: 15, color: t.red),
            label: Text(
              'Sign Out',
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

class AdminPillTabBar extends StatelessWidget {
  const AdminPillTabBar({
    super.key,
    required this.tab,
    required this.onSelect,
  });

  final int tab;
  final void Function(int) onSelect;

  @override
  Widget build(BuildContext context) {
    const tabs = [
      {'icon': Icons.bar_chart, 'label': 'Overview'},
      {'icon': Icons.people, 'label': 'Supervisors'},
      {'icon': Icons.notifications_outlined, 'label': 'Alerts'},
      {'icon': Icons.warning_amber, 'label': 'Escalations'},
      {'icon': Icons.account_tree, 'label': 'Hierarchy'},
    ];
    final t = context.appTheme;
    return Container(
      color: t.card,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(tabs.length, (i) {
            final sel = tab == i;
            final item = tabs[i];
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => onSelect(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: sel ? t.navy : t.scaffold,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: sel ? t.navy : t.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
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
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
