part of 'admin_dashboard_screen.dart';

class _Header extends StatefulWidget {
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
  State<_Header> createState() => _HeaderState();
}

class _HeaderState extends State<_Header> {
  int _notificationCount = 0;
  List<Map<String, dynamic>> _notifications = [];
  late final DatabaseReference _db;
  StreamSubscription<DatabaseEvent>? _notifSub;

  @override
  void initState() {
    super.initState();
    if (!widget.enableNotifications) {
      return;
    }
    _db = FirebaseDatabase.instance.ref();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      _notifSub = _db
          .child('notifications/$uid')
          .onValue
          .listen(
            (event) {
              final data = event.snapshot.value;
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
            },
            onError: (error) {
              debugPrint('Notification stream error: $error');
              // Don't crash; just treat as empty
              if (mounted) {
                setState(() {
                  _notifications = [];
                  _notificationCount = 0;
                });
              }
            },
          );
    }
  }

  @override
  void dispose() {
    _notifSub?.cancel();
    super.dispose();
  }

  void _showNotifications() {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final theme = Theme.of(context);
            final textColor = theme.brightness == Brightness.dark
                ? Colors.white
                : Colors.black87;
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
                            child: Text(
                              'No notifications',
                              style: TextStyle(color: textColor),
                            ),
                          )
                        : ListView.builder(
                            itemCount: _notifications.length,
                            itemBuilder: (context, index) {
                              final n = _notifications[index];
                              if (n['type'] ==
                                  'ai_cross_factory_recommendation') {
                                final alertId = (n['alertId'] ?? '').toString();
                                final recName =
                                    (n['recommendedSupervisorName'] ?? '')
                                        .toString();
                                final recReason = (n['reason'] ?? '')
                                    .toString();

                                Future<void> completeDecision({
                                  required bool approve,
                                }) async {
                                  if (alertId.isEmpty) return;
                                  final current =
                                      FirebaseAuth.instance.currentUser;
                                  final approverId = current?.uid;
                                  final approverName =
                                      current?.email?.split('@').first ??
                                      'Production Manager';

                                  final ok = approve
                                      ? await AIAssignmentService.instance
                                            .approveCrossFactoryRecommendation(
                                              alertId: alertId,
                                              approverId: approverId,
                                              approverName: approverName,
                                            )
                                      : await AIAssignmentService.instance
                                            .declineCrossFactoryRecommendation(
                                              alertId: alertId,
                                              approverId: approverId,
                                              approverName: approverName,
                                            );

                                  await _db
                                      .child(
                                        'notifications/${FirebaseAuth.instance.currentUser!.uid}/${n['id']}',
                                      )
                                      .remove();

                                  if (context.mounted) {
                                    setModalState(() {
                                      _notifications.removeWhere(
                                        (item) => item['id'] == n['id'],
                                      );
                                      _notificationCount = _notifications
                                          .where((x) => x['status'] != 'read')
                                          .length;
                                    });

                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          ok
                                              ? (approve
                                                    ? 'Recommendation approved'
                                                    : 'Recommendation declined')
                                              : 'Recommendation was already processed',
                                        ),
                                        backgroundColor: ok
                                            ? (approve
                                                  ? Colors.green
                                                  : Colors.orange)
                                            : Colors.blueGrey,
                                      ),
                                    );
                                  }
                                }

                                return ListTile(
                                  title: Text(
                                    n['message'] ??
                                        'AI cross-factory recommendation',
                                    style: TextStyle(
                                      color: theme.brightness == Brightness.dark
                                          ? Colors.white
                                          : Colors.black87,
                                    ),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (recName.isNotEmpty)
                                        Text(
                                          'Recommended: $recName',
                                          style: TextStyle(
                                            color:
                                                theme.brightness ==
                                                    Brightness.dark
                                                ? Colors.white70
                                                : Colors.black54,
                                          ),
                                        ),
                                      if (recReason.isNotEmpty)
                                        Text(
                                          recReason,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color:
                                                theme.brightness ==
                                                    Brightness.dark
                                                ? Colors.white70
                                                : Colors.black54,
                                          ),
                                        ),
                                    ],
                                  ),
                                  trailing: SizedBox(
                                    width: 188,
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: ElevatedButton.icon(
                                            onPressed: () => completeDecision(
                                              approve: false,
                                            ),
                                            icon: const Icon(
                                              Icons.close,
                                              size: 14,
                                              color: Colors.white,
                                            ),
                                            label: const Text(
                                              'Decline',
                                              style: TextStyle(fontSize: 11),
                                            ),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: const Color(
                                                0xFFFFB3BA,
                                              ),
                                              foregroundColor: Colors.white,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 8,
                                                  ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: ElevatedButton.icon(
                                            onPressed: () =>
                                                completeDecision(approve: true),
                                            icon: const Icon(
                                              Icons.check,
                                              size: 14,
                                              color: Colors.white,
                                            ),
                                            label: const Text(
                                              'Approve',
                                              style: TextStyle(fontSize: 11),
                                            ),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.green,
                                              foregroundColor: Colors.white,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 8,
                                                  ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  onTap: () async {
                                    await _db
                                        .child(
                                          'notifications/${FirebaseAuth.instance.currentUser!.uid}/${n['id']}',
                                        )
                                        .remove();
                                    if (context.mounted) {
                                      Navigator.pop(context);
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => AlertDetailScreen(
                                            alertId: alertId,
                                          ),
                                        ),
                                      );
                                    }
                                  },
                                );
                              } else if (n['type'] == 'help_request') {
                                return ListTile(
                                  title: Text(
                                    n['message'] ?? 'Help request',
                                    style: TextStyle(
                                      color: theme.brightness == Brightness.dark
                                          ? Colors.white
                                          : Colors.black87,
                                    ),
                                  ),
                                  subtitle: Text(
                                    'Tap to accept or refuse',
                                    style: TextStyle(
                                      color: theme.brightness == Brightness.dark
                                          ? Colors.white70
                                          : Colors.black54,
                                    ),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(
                                          Icons.check_circle,
                                          color: Colors.green,
                                        ),
                                        onPressed: () async {
                                          await Provider.of<AlertProvider>(
                                            context,
                                            listen: false,
                                          ).acceptHelp(
                                            n['alertId'],
                                            n['helpRequestId'],
                                          );
                                          await _db
                                              .child(
                                                'notifications/${FirebaseAuth.instance.currentUser!.uid}/${n['id']}',
                                              )
                                              .remove();
                                          if (context.mounted) {
                                            setModalState(() {
                                              _notifications.removeWhere(
                                                (item) => item['id'] == n['id'],
                                              );
                                              _notificationCount =
                                                  _notifications
                                                      .where(
                                                        (x) =>
                                                            x['status'] !=
                                                            'read',
                                                      )
                                                      .length;
                                            });
                                          }
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  'Help request accepted',
                                                ),
                                                backgroundColor: Colors.green,
                                              ),
                                            );
                                          }
                                        },
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.cancel,
                                          color: Colors.red,
                                        ),
                                        onPressed: () async {
                                          await Provider.of<AlertProvider>(
                                            context,
                                            listen: false,
                                          ).refuseHelp(
                                            n['alertId'],
                                            n['helpRequestId'],
                                          );
                                          await _db
                                              .child(
                                                'notifications/${FirebaseAuth.instance.currentUser!.uid}/${n['id']}',
                                              )
                                              .remove();
                                          if (context.mounted) {
                                            setModalState(() {
                                              _notifications.removeWhere(
                                                (item) => item['id'] == n['id'],
                                              );
                                              _notificationCount =
                                                  _notifications
                                                      .where(
                                                        (x) =>
                                                            x['status'] !=
                                                            'read',
                                                      )
                                                      .length;
                                            });
                                          }
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  'Help request refused',
                                                ),
                                                backgroundColor: Colors.orange,
                                              ),
                                            );
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                );
                              } else if (n['type'] == 'assistance_request') {
                                return ListTile(
                                  title: Text(
                                    n['message'] ?? 'Assistance request',
                                    style: TextStyle(
                                      color: theme.brightness == Brightness.dark
                                          ? Colors.white
                                          : Colors.black87,
                                    ),
                                  ),
                                  subtitle: Text(
                                    n['alertDescription'] ?? '',
                                    style: TextStyle(
                                      color: theme.brightness == Brightness.dark
                                          ? Colors.white70
                                          : Colors.black54,
                                    ),
                                  ),
                                  trailing: ElevatedButton(
                                    onPressed: () async {
                                      final supervisors = await AuthService()
                                          .getActiveSupervisors();
                                      if (supervisors.isEmpty) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'No active supervisors available',
                                            ),
                                          ),
                                        );
                                        return;
                                      }
                                      showDialog(
                                        context: context,
                                        builder: (dialogContext) => AlertDialog(
                                          title: const Text('Assign Assistant'),
                                          content: SizedBox(
                                            width: 300,
                                            child: ListView.builder(
                                              shrinkWrap: true,
                                              itemCount: supervisors.length,
                                              itemBuilder: (_, i) => ListTile(
                                                leading: Icon(
                                                  Icons.person,
                                                  color: _navy,
                                                ),
                                                title: Text(
                                                  supervisors[i].fullName,
                                                ),
                                                subtitle: Text(
                                                  supervisors[i].email,
                                                ),
                                                onTap: () async {
                                                  Navigator.pop(dialogContext);
                                                  await AuthService()
                                                      .assignAssistantToAlert(
                                                        n['alertId'],
                                                        supervisors[i].id,
                                                        supervisors[i].fullName,
                                                      );
                                                  await _db
                                                      .child(
                                                        'notifications/${FirebaseAuth.instance.currentUser!.uid}/${n['id']}',
                                                      )
                                                      .remove();
                                                  if (context.mounted) {
                                                    setModalState(() {
                                                      _notifications
                                                          .removeWhere(
                                                            (item) =>
                                                                item['id'] ==
                                                                n['id'],
                                                          );
                                                      _notificationCount =
                                                          _notifications
                                                              .where(
                                                                (x) =>
                                                                    x['status'] !=
                                                                    'read',
                                                              )
                                                              .length;
                                                    });
                                                  }
                                                  ScaffoldMessenger.of(
                                                    context,
                                                  ).showSnackBar(
                                                    SnackBar(
                                                      content: Text(
                                                        'Assigned ${supervisors[i].fullName} as assistant',
                                                      ),
                                                      backgroundColor:
                                                          Colors.green,
                                                    ),
                                                  );
                                                },
                                              ),
                                            ),
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(dialogContext),
                                              child: const Text('Cancel'),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                    child: const Text(
                                      'Assign Assistant',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ),
                                );
                              } else {
                                return ListTile(
                                  title: Text(n['message'] ?? 'Notification'),
                                  subtitle: Text(n['alertDescription'] ?? ''),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (n['status'] != 'read')
                                        IconButton(
                                          icon: const Icon(
                                            Icons.visibility,
                                            size: 18,
                                            color: Colors.blue,
                                          ),
                                          onPressed: () async {
                                            await _db
                                                .child(
                                                  'notifications/${FirebaseAuth.instance.currentUser!.uid}/${n['id']}',
                                                )
                                                .remove();
                                            if (context.mounted) {
                                              setModalState(() {
                                                _notifications.removeWhere(
                                                  (item) =>
                                                      item['id'] == n['id'],
                                                );
                                                _notificationCount =
                                                    _notifications
                                                        .where(
                                                          (x) =>
                                                              x['status'] !=
                                                              'read',
                                                        )
                                                        .length;
                                              });
                                            }
                                          },
                                        ),
                                      IconButton(
                                        icon: Icon(
                                          Icons.open_in_new,
                                          size: 18,
                                          color: _navy,
                                        ),
                                        onPressed: () async {
                                          if (n['status'] != 'read') {
                                            await _db
                                                .child(
                                                  'notifications/${FirebaseAuth.instance.currentUser!.uid}/${n['id']}',
                                                )
                                                .remove();
                                          }
                                          if (context.mounted) {
                                            Navigator.pop(context);
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    AlertDetailScreen(
                                                      alertId: n['alertId'],
                                                    ),
                                              ),
                                            );
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                  onTap: () async {
                                    if (n['status'] != 'read') {
                                      await _db
                                          .child(
                                            'notifications/${FirebaseAuth.instance.currentUser!.uid}/${n['id']}',
                                          )
                                          .remove();
                                    }
                                    if (context.mounted) {
                                      Navigator.pop(context);
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => AlertDetailScreen(
                                            alertId: n['alertId'],
                                          ),
                                        ),
                                      );
                                    }
                                  },
                                );
                              }
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

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
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Production Manager',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: t.navy,
                  letterSpacing: .2,
                ),
              ),
              Text(
                'Production Manager - Dashboard',
                style: TextStyle(fontSize: 11, color: t.muted),
              ),
            ],
          ),
          const Spacer(),
          // ── Simulate Alert ──
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
          // ── Theme toggle ──
          IconButton(
            icon: Icon(
              isDark ? Icons.light_mode : Icons.dark_mode,
              color: t.muted,
              size: 22,
            ),
            tooltip: isDark ? 'Light mode' : 'Dark mode',
            onPressed: () => context.read<ThemeProvider>().toggle(),
          ),
          // ── Notifications ──
          Stack(
            children: [
              IconButton(
                icon: Icon(Icons.notifications_none, color: t.muted, size: 24),
                onPressed: widget.enableNotifications
                    ? _showNotifications
                    : null,
              ),
              if (_notificationCount > 0)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: t.red,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '$_notificationCount',
                        style: TextStyle(
                          color: t.card,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
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
