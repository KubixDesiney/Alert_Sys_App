import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:provider/provider.dart';

import '../providers/theme_provider.dart';
import '../theme.dart';

class DashboardUserInfo extends StatelessWidget {
  const DashboardUserInfo({
    super.key,
    required this.title,
    required this.subtitle,
    this.icon = Icons.factory,
    this.trailingIcon,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final IconData? trailingIcon;

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Row(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: t.navyLt,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: t.border),
              ),
              child: Icon(icon, size: 22, color: t.navy),
            ),
            if (trailingIcon != null)
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  decoration: BoxDecoration(
                    color: t.card,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(trailingIcon, color: t.red, size: 14),
                ),
              ),
          ],
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: t.navy,
                letterSpacing: .2,
              ),
            ),
            Text(
              subtitle,
              style: TextStyle(fontSize: 11, color: t.muted),
            ),
          ],
        ),
      ],
    );
  }
}

class DashboardThemeToggleButton extends StatelessWidget {
  const DashboardThemeToggleButton({super.key, this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final isDark = context.isDark;
    return IconButton(
      icon: Icon(
        isDark ? Icons.light_mode : Icons.dark_mode,
        color: color ?? t.muted,
        size: 22,
      ),
      tooltip: isDark ? 'Light mode' : 'Dark mode',
      onPressed: () => context.read<ThemeProvider>().toggle(),
    );
  }
}

class DashboardNotificationBell extends StatelessWidget {
  const DashboardNotificationBell({
    super.key,
    required this.count,
    required this.onPressed,
    this.color,
    this.iconSize = 24,
  });

  final int count;
  final VoidCallback onPressed;
  final Color? color;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          icon: Icon(
            Icons.notifications_none,
            color: color ?? t.muted,
            size: iconSize,
          ),
          onPressed: onPressed,
        ),
        if (count > 0)
          Positioned(
            top: 6,
            right: 6,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(color: t.red, shape: BoxShape.circle),
              child: Center(
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: t.card,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Widget that manages subscribing to Firebase notification stream for the
/// current user and exposes the count and notification list to a builder.
class NotificationCenter extends StatefulWidget {
  const NotificationCenter({super.key, required this.builder});

  final Widget Function(BuildContext context, int count,
      List<Map<String, dynamic>> notifications, VoidCallback show)
      builder;

  @override
  State<NotificationCenter> createState() => _NotificationCenterState();
}

class _NotificationCenterState extends State<NotificationCenter> {
  int _notificationCount = 0;
  List<Map<String, dynamic>> _notifications = [];
  StreamSubscription<DatabaseEvent>? _notifSub;

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      final db = FirebaseDatabase.instance.ref();
      _notifSub = db.child('notifications/$uid').onValue.listen((event) {
        final data = event.snapshot.value;
        if (!mounted) return;
        if (data == null) {
          setState(() {
            _notificationCount = 0;
            _notifications = [];
          });
          return;
        }
        final map = Map<String, dynamic>.from(data as Map);
        final list = map.entries.map((e) {
          final m = Map<String, dynamic>.from(e.value as Map);
          m['id'] = e.key;
          return m;
        }).toList();
        final pending = list.where((n) => n['status'] != 'read').toList();
        setState(() {
          _notifications = list;
          _notificationCount = pending.length;
        });
      }, onError: (err, st) {
        if (mounted) setState(() => _notifications = []);
      });
    }
  }

  @override
  void dispose() {
    _notifSub?.cancel();
    super.dispose();
  }

  void _showNotifications() {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        final textColor =
            theme.brightness == Brightness.dark ? Colors.white : Colors.black87;
        return Container(
          padding: const EdgeInsets.all(16),
          height: 400,
          color: theme.scaffoldBackgroundColor,
          child: Column(
            children: [
              Text(
                'Notifications',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
              Divider(color: theme.dividerColor),
              Expanded(
                child: _notifications.isEmpty
                    ? Center(
                        child: Text('No notifications',
                            style: TextStyle(color: textColor)),
                      )
                    : ListView.builder(
                        itemCount: _notifications.length,
                        itemBuilder: (context, index) {
                          final n = _notifications[index];
                          return ListTile(
                            title: Text(
                              n['message']?.toString() ?? 'Notification',
                              style: TextStyle(color: textColor),
                            ),
                            subtitle: Text(
                              n['timestamp']?.toString() ?? '',
                              style: TextStyle(
                                color: textColor.withValues(alpha: 0.7),
                              ),
                            ),
                            onTap: () async {
                              final uid =
                                  FirebaseAuth.instance.currentUser?.uid;
                              final id = n['id']?.toString();
                              if (uid != null && id != null) {
                                await FirebaseDatabase.instance
                                    .ref('notifications/$uid/$id')
                                    .update({'status': 'read'});
                              }
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _notificationCount, _notifications,
        () => _showNotifications());
  }
}
