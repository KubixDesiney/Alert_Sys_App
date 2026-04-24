import 'dart:async';
import '../services/ai_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:vibration/vibration.dart';
import '../providers/alert_provider.dart';
import '../models/alert_model.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import 'login_screen.dart';
import 'alert_detail_screen.dart';
import 'supervisor_collaboration_screen.dart'; // new
import 'supervisor_collaboration_screen.dart' as collab;

const _navy = AppColors.navy;
const _red = AppColors.redAlt;
const _bgPage = AppColors.bg;
const _white = AppColors.white;
const _muted = AppColors.textMuted;

Color _typeColor(String type) => switch (type) {
      'qualite' => const Color(0xFFEF4444),
      'maintenance' => const Color(0xFF3B82F6),
      'defaut_produit' => const Color(0xFF22C55E),
      'manque_ressource' => const Color(0xFFF59E0B),
      _ => const Color(0xFF6B7280),
    };

String _typeLabel(String type) => switch (type) {
      'qualite' => 'Quality',
      'maintenance' => 'Maintenance',
      'defaut_produit' => 'Damaged Product',
      'manque_ressource' => 'Resources Deficiency',
      _ => type,
    };

String _formatTimestamp(DateTime dt) {
  final h12 = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
  final minute = dt.minute.toString().padLeft(2, '0');
  final ampm = dt.hour >= 12 ? 'PM' : 'AM';
  return '$h12:$minute $ampm';
}

// ============================================================================
// MAIN SCREEN – SWIPEABLE PAGES (Dashboard & Collaboration Progress)
// ============================================================================
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  String _usine = 'Usine A';

  String get _superviseurId =>
      FirebaseAuth.instance.currentUser?.uid ?? 'user1';
  String get _superviseurName =>
      FirebaseAuth.instance.currentUser?.email?.split('@').first ??
      'Supervisor';

  @override
  void initState() {
    super.initState();
    _fetchSupervisorUsine().then((usine) {
      if (mounted) {
        setState(() => _usine = usine);
        context.read<AlertProvider>().init(usine);
      }
    });
  }

  Future<String> _fetchSupervisorUsine() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 'Usine A';
    final snapshot =
        await FirebaseDatabase.instance.ref('users/${user.uid}/usine').once();
    final value = snapshot.snapshot.value;
    return (value as String?) ?? 'Usine A';
  }

  Future<void> _logout() async {
    await AuthService().logout();
    if (!mounted) return;
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgPage,
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) => setState(() => _currentPage = index),
        children: [
          // Page 0 – Original Dashboard (all functionality)
          _OriginalDashboardContent(
            superviseurId: _superviseurId,
            superviseurName: _superviseurName,
            usine: _usine,
            onLogout: _logout,
            currentPage: _currentPage,
          ),
          // Page 1 – Collaboration Progress
          const CollaborationProgressScreen(),
        ],
      ),
    );
  }
}

// ============================================================================
// ORIGINAL DASHBOARD CONTENT (everything from your old dashboard_screen.dart)
// ============================================================================
class _OriginalDashboardContent extends StatefulWidget {
  final String superviseurId;
  final String superviseurName;
  final String usine;
  final VoidCallback onLogout;
  final int currentPage;

  const _OriginalDashboardContent({
    required this.superviseurId,
    required this.superviseurName,
    required this.usine,
    required this.onLogout,
    required this.currentPage,
  });

  @override
  State<_OriginalDashboardContent> createState() =>
      _OriginalDashboardContentState();
}

class _OriginalDashboardContentState extends State<_OriginalDashboardContent> {
  String _activeView = 'received';
  bool _showPanel = false;

  void _handleCardClick(String view) {
    setState(() {
      if (_activeView == view && _showPanel) {
        _showPanel = false;
      } else {
        _activeView = view;
        _showPanel = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AlertProvider>();
    final available = provider.availableAlerts;
    final allInProgress = provider.allInProgressAlerts;
    final myInProgress = provider.inProgressAlerts(widget.superviseurId);
    final validated = provider.validatedAlerts(widget.superviseurId);
    final badge = available.length + myInProgress.length;

    return SafeArea(
      child: Column(
        children: [
          // Use the existing _Header (with notifications, buzzing, etc.)
          _Header(
            userName: widget.superviseurName,
            clientName: 'SAGEM',
            activeBadge: badge,
            onLogout: widget.onLogout,
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Dashboard Title & Pagination Dots
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.info_outline,
                              color: _navy, size: 20),
                          const SizedBox(width: 8),
                          const Text(
                            'Dashboard',
                            style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: _navy),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Icon(Icons.chevron_left, color: Colors.grey.shade400),
                          Icon(Icons.chevron_right, color: _navy),
                        ],
                      )
                    ],
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Column(
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                                width: 20,
                                height: 6,
                                decoration: BoxDecoration(
                                    color: widget.currentPage == 0
                                        ? _navy
                                        : const Color(0xFFCBD5E1),
                                    borderRadius: BorderRadius.circular(4))),
                            const SizedBox(width: 4),
                            Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                    color: widget.currentPage == 1
                                        ? _navy
                                        : const Color(0xFFCBD5E1),
                                    shape: BoxShape.circle)),
                            const SizedBox(width: 4),
                            Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                    color: Color(0xFFCBD5E1),
                                    shape: BoxShape.circle)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text('← Swipe to navigate →',
                            style: TextStyle(
                                fontSize: 10, color: Color(0xFF94A3B8))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Summary Cards (as in original)
                  _SummaryCard(
                    label: 'Fixed Alerts',
                    count: validated.length,
                    color: const Color(0xFF22C55E),
                    bgColor: const Color(0xFFDCFCE7),
                    icon: Icons.check_circle_outline,
                    active: _activeView == 'fixed' && _showPanel,
                    onTap: () => _handleCardClick('fixed'),
                  ),
                  const SizedBox(height: 12),
                  _SummaryCard(
                    label: 'Claimed Alerts',
                    count: myInProgress.length,
                    color: const Color(0xFF3B82F6),
                    bgColor: const Color(0xFFDBEAFE),
                    icon: Icons.timer_outlined,
                    active: _activeView == 'claimed' && _showPanel,
                    onTap: () => _handleCardClick('claimed'),
                  ),
                  const SizedBox(height: 12),
                  _SummaryCard(
                    label: 'Manage Alerts Received',
                    count: available.length,
                    color: const Color(0xFFF97316),
                    bgColor: const Color(0xFFFFEDD5),
                    icon: Icons.notifications_outlined,
                    active: _activeView == 'received' && _showPanel,
                    onTap: () => _handleCardClick('received'),
                  ),

                  if (_showPanel) ...[
                    const SizedBox(height: 20),
                    _DetailPanel(
                      activeView: _activeView,
                      available: available,
                      allInProgress: allInProgress,
                      validated: validated,
                      provider: provider,
                      superviseurId: widget.superviseurId,
                      superviseurName: widget.superviseurName,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// REMAINING ORIGINAL WIDGETS (copied verbatim from your old dashboard_screen.dart)
// ============================================================================

// ---------- HEADER (with notifications, PM actions, vibration, stop buzzing) ----------
class _Header extends StatefulWidget {
  final String userName, clientName;
  final int activeBadge;
  final VoidCallback onLogout;
  const _Header({
    required this.userName,
    required this.clientName,
    required this.activeBadge,
    required this.onLogout,
  });

  @override
  State<_Header> createState() => _HeaderState();
}

class _HeaderState extends State<_Header> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _notificationCount = 0;
  List<Map<String, dynamic>> _notifications = [];
  List<Map<String, dynamic>> _pmActions = [];
  final DatabaseReference _db = FirebaseDatabase.instance.ref();
  late StreamSubscription<DatabaseEvent> _notifSubscription;
  late StreamSubscription<DatabaseEvent> _pmSubscription;

  bool _isBuzzing = false;
  String? _buzzingNotificationId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      _db.child('notifications/$uid').remove();
      _db.child('pm_actions/$uid').remove();

      _notifSubscription =
          _db.child('notifications/$uid').onValue.listen((event) async {
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

        if (pending.isNotEmpty) {
          Map<String, dynamic>? newUnread;
          for (var n in pending) {
            if (_notifications.every((old) => old['id'] != n['id'])) {
              newUnread = n;
              break;
            }
          }
          if (newUnread != null) {
            final alertId = newUnread['alertId'];
            if (alertId != null) {
              final alertSnap = await _db.child('alerts/$alertId').get();
              if (alertSnap.exists) {
                final alertData = alertSnap.value as Map;
                final alertUsine = alertData['usine']?.toString() ?? '';
                final userInfo = await _getUserInfo();
                final userRole = userInfo['role'];
                final userUsine = userInfo['usine'];
                bool shouldBuzz = false;
                if (userRole == 'admin') {
                  shouldBuzz = true;
                } else if (userRole == 'supervisor' &&
                    alertUsine == userUsine) {
                  shouldBuzz = true;
                }
                if (shouldBuzz) {
                  _startBuzzing(newUnread['id']);
                }
              }
            }
          }
        }
        setState(() {
          _notifications = list;
          _notificationCount = pending.length;
        });
      });

      _pmSubscription = _db.child('pm_actions/$uid').onValue.listen((event) {
        final data = event.snapshot.value;
        if (data == null) {
          setState(() => _pmActions = []);
          return;
        }
        final map = Map<String, dynamic>.from(data as Map);
        final list = map.entries.map((e) {
          final m = Map<String, dynamic>.from(e.value as Map);
          m['id'] = e.key;
          return m;
        }).toList();
        setState(() => _pmActions = list);
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _notifSubscription.cancel();
    _pmSubscription.cancel();
    _stopBuzzing();
    super.dispose();
  }

  Future<Map<String, String>> _getUserInfo() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return {'role': 'supervisor', 'usine': 'Usine A'};
    final snapshot = await _db.child('users/$uid').get();
    if (!snapshot.exists) return {'role': 'supervisor', 'usine': 'Usine A'};
    final data = snapshot.value as Map;
    return {
      'role': data['role']?.toString() ?? 'supervisor',
      'usine': data['usine']?.toString() ?? 'Usine A',
    };
  }

  Future<void> _startBuzzing(String notificationId) async {
    if (_isBuzzing) return;
    final hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator == true) {
      Vibration.vibrate(pattern: [1000, 1000], repeat: 0);
      setState(() {
        _isBuzzing = true;
        _buzzingNotificationId = notificationId;
      });
    }
  }

  Future<void> _stopBuzzing() async {
    if (_isBuzzing) {
      await Vibration.cancel();
      setState(() {
        _isBuzzing = false;
        _buzzingNotificationId = null;
      });
    }
  }

  void _showNotifications() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.9,
              decoration: const BoxDecoration(
                color: _white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text('All Notifications',
                                  style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87)),
                              SizedBox(height: 4),
                              Text('View and manage your alerts and PM actions',
                                  style: TextStyle(
                                      fontSize: 14, color: Colors.grey)),
                            ],
                          ),
                        ),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                  color: _red,
                                  borderRadius: BorderRadius.circular(12)),
                              child: Text('$_notificationCount unread',
                                  style: const TextStyle(
                                      color: _white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12)),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () => Navigator.pop(context),
                              child: const Icon(Icons.close,
                                  color: Colors.black54),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(30)),
                    child: TabBar(
                      controller: _tabController,
                      indicator: BoxDecoration(
                          color: _white,
                          borderRadius: BorderRadius.circular(30),
                          boxShadow: const [
                            BoxShadow(
                                color: Color(0x0A000000),
                                blurRadius: 4,
                                offset: Offset(0, 2))
                          ]),
                      labelColor: _navy,
                      unselectedLabelColor: Colors.black54,
                      labelStyle: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13),
                      unselectedLabelStyle: const TextStyle(
                          fontWeight: FontWeight.w500, fontSize: 13),
                      tabs: [
                        Tab(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text('Alerts'),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                    color: _red, shape: BoxShape.circle),
                                child: Text('${_notifications.length}',
                                    style: const TextStyle(
                                        color: _white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        ),
                        Tab(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text('PM Actions'),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                    color: _red, shape: BoxShape.circle),
                                child: Text('${_pmActions.length}',
                                    style: const TextStyle(
                                        color: _white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        // Alerts tab
                        _notifications.isEmpty
                            ? const Center(child: Text('No alerts'))
                            : ListView.builder(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 20),
                                itemCount: _notifications.length,
                                itemBuilder: (context, index) {
                                  final n = _notifications[index];
                                  final isHelp = n['type'] == 'help_request';
                                  final isAssistance =
                                      n['type'] == 'assistance_request';
                                  final isUnread = n['status'] != 'read';
                                  if (isHelp) {
                                    return _buildHelpRequestItem(
                                        n, isUnread, setModalState, context);
                                  } else if (isAssistance) {
                                    return _buildAssistanceRequestItem(
                                        n, isUnread, setModalState, context);
                                  } else {
                                    return _buildDefaultNotificationItem(
                                        n, isUnread, setModalState, context);
                                  }
                                },
                              ),
                        // PM Actions tab
                        _pmActions.isEmpty
                            ? const Center(child: Text('No PM actions'))
                            : ListView.builder(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 20),
                                itemCount: _pmActions.length,
                                itemBuilder: (context, index) {
                                  final action = _pmActions[index];
                                  final isUnread = action['status'] != 'read';
                                  return _buildPmActionItem(
                                      action, isUnread, setModalState, context);
                                },
                              ),
                      ],
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

  Widget _buildHelpRequestItem(Map<String, dynamic> n, bool isUnread,
      StateSetter setModalState, BuildContext context) {
    final isBuzzingForThis = _isBuzzing && _buzzingNotificationId == n['id'];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: const Color(0xFFF0F9FF),
          border: Border.all(color: const Color(0xFFBAE6FD)),
          borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.help_outline, color: Colors.blue, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(n['message'] ?? 'Help request',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 4),
                    Text(n['alertDescription'] ?? 'Action required',
                        style: TextStyle(
                            color: Colors.grey.shade600, fontSize: 13)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.access_time,
                            size: 14, color: Colors.grey.shade500),
                        const SizedBox(width: 4),
                        Text(
                            _formatTimestamp(DateTime.parse(n['timestamp'] ??
                                DateTime.now().toIso8601String())),
                            style: TextStyle(
                                color: Colors.grey.shade500, fontSize: 12)),
                        if (isBuzzingForThis) ...[
                          const SizedBox(width: 12),
                          const Icon(Icons.vibration,
                              size: 14, color: Colors.red),
                          const SizedBox(width: 4),
                          const Text('Phone is buzzing',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.red,
                                  fontWeight: FontWeight.w500)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (isUnread)
                Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                        color: _red, shape: BoxShape.circle)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () async {
                  await Provider.of<AlertProvider>(context, listen: false)
                      .acceptHelp(n['alertId'], n['helpRequestId']);
                  final alertSnapshot = await FirebaseDatabase.instance
                      .ref('alerts/${n['alertId']}')
                      .once();
                  final alertData = alertSnapshot.snapshot.value as Map?;
                  final originalSupervisorId = alertData?['superviseurId'];
                  if (originalSupervisorId != null &&
                      originalSupervisorId !=
                          FirebaseAuth.instance.currentUser!.uid) {
                    final pmRef = FirebaseDatabase.instance
                        .ref('pm_actions/$originalSupervisorId')
                        .push();
                    await pmRef.set({
                      'title': 'Assistant Assigned',
                      'description':
                          '${FirebaseAuth.instance.currentUser?.displayName ?? 'A supervisor'} accepted your assistance request',
                      'timestamp': DateTime.now().toIso8601String(),
                      'status': 'unread',
                      'alertId': n['alertId'],
                      'type': 'assistant_assigned',
                    });
                  }
                  await _db
                      .child(
                          'notifications/${FirebaseAuth.instance.currentUser!.uid}/${n['id']}')
                      .remove();
                  if (context.mounted) {
                    setModalState(() {
                      _notifications
                          .removeWhere((item) => item['id'] == n['id']);
                      _notificationCount = _notifications
                          .where((x) => x['status'] != 'read')
                          .length;
                    });
                    if (_buzzingNotificationId == n['id']) _stopBuzzing();
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Help request accepted'),
                        backgroundColor: Colors.green));
                  }
                },
                icon: const Icon(Icons.check, size: 16, color: Colors.green),
                label:
                    const Text('Accept', style: TextStyle(color: Colors.green)),
                style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.green),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8))),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  await Provider.of<AlertProvider>(context, listen: false)
                      .refuseHelp(n['alertId'], n['helpRequestId']);
                  await _db
                      .child(
                          'notifications/${FirebaseAuth.instance.currentUser!.uid}/${n['id']}')
                      .remove();
                  if (context.mounted) {
                    setModalState(() {
                      _notifications
                          .removeWhere((item) => item['id'] == n['id']);
                      _notificationCount = _notifications
                          .where((x) => x['status'] != 'read')
                          .length;
                    });
                    if (_buzzingNotificationId == n['id']) _stopBuzzing();
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Help request refused'),
                        backgroundColor: Colors.orange));
                  }
                },
                icon: const Icon(Icons.close, size: 16, color: Colors.red),
                label:
                    const Text('Decline', style: TextStyle(color: Colors.red)),
                style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8))),
              ),
              if (isUnread) ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    await _stopBuzzing();
                    setModalState(() {});
                  },
                  icon:
                      const Icon(Icons.vibration, size: 16, color: Colors.red),
                  label: const Text('Stop Buzzing',
                      style: TextStyle(color: Colors.red)),
                  style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.red),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8))),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAssistanceRequestItem(Map<String, dynamic> n, bool isUnread,
      StateSetter setModalState, BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: const Color(0xFFFFF7ED),
          border: Border.all(color: const Color(0xFFFED7AA)),
          borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.group_add, color: Colors.orange, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(n['message'] ?? 'Assistance request',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 4),
                    Text(n['alertDescription'] ?? '',
                        style: TextStyle(
                            color: Colors.grey.shade600, fontSize: 13)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.access_time,
                            size: 14, color: Colors.grey.shade500),
                        const SizedBox(width: 4),
                        Text(
                            _formatTimestamp(DateTime.parse(n['timestamp'] ??
                                DateTime.now().toIso8601String())),
                            style: TextStyle(
                                color: Colors.grey.shade500, fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              ),
              if (isUnread)
                Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                        color: _red, shape: BoxShape.circle)),
            ],
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () async {
              final supervisors = await AuthService().getActiveSupervisors();
              if (supervisors.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('No active supervisors available')));
                return;
              }
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Assign Assistant'),
                  content: SizedBox(
                    width: 300,
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: supervisors.length,
                      itemBuilder: (_, i) => ListTile(
                        leading: const Icon(Icons.person, color: _navy),
                        title: Text(supervisors[i].fullName),
                        subtitle: Text(supervisors[i].email),
                        onTap: () async {
                          Navigator.pop(_);
                          await AuthService().assignAssistantToAlert(
                              n['alertId'],
                              supervisors[i].id,
                              supervisors[i].fullName);
                          await _db
                              .child(
                                  'notifications/${FirebaseAuth.instance.currentUser!.uid}/${n['id']}')
                              .remove();
                          if (context.mounted) {
                            setModalState(() {
                              _notifications
                                  .removeWhere((item) => item['id'] == n['id']);
                              _notificationCount = _notifications
                                  .where((x) => x['status'] != 'read')
                                  .length;
                            });
                          }
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(
                                  '✅ Assigned ${supervisors[i].fullName} as assistant'),
                              backgroundColor: Colors.green));
                        },
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(_),
                        child: const Text('Cancel'))
                  ],
                ),
              );
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8))),
            child:
                const Text('Assign Assistant', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildDefaultNotificationItem(Map<String, dynamic> n, bool isUnread,
      StateSetter setModalState, BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: _white,
          border: Border.all(color: const Color(0xFFE5E7EB)),
          borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(n['message'] ?? 'Notification',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(n['alertDescription'] ?? ''),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isUnread && _buzzingNotificationId == n['id'])
              IconButton(
                icon: const Icon(Icons.vibration, size: 18, color: Colors.red),
                onPressed: () async {
                  await _stopBuzzing();
                  setModalState(() {});
                },
              ),
            if (isUnread)
              IconButton(
                icon:
                    const Icon(Icons.visibility, size: 18, color: Colors.blue),
                onPressed: () async {
                  await _db
                      .child(
                          'notifications/${FirebaseAuth.instance.currentUser!.uid}/${n['id']}')
                      .remove();
                  if (context.mounted) {
                    setModalState(() {
                      _notifications
                          .removeWhere((item) => item['id'] == n['id']);
                      _notificationCount = _notifications
                          .where((x) => x['status'] != 'read')
                          .length;
                    });
                  }
                },
              ),
            IconButton(
              icon: const Icon(Icons.open_in_new, size: 18, color: _navy),
              onPressed: () async {
                if (isUnread)
                  await _db
                      .child(
                          'notifications/${FirebaseAuth.instance.currentUser!.uid}/${n['id']}')
                      .remove();
                if (context.mounted) {
                  Navigator.pop(context);
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              AlertDetailScreen(alertId: n['alertId'])));
                }
              },
            ),
          ],
        ),
        onTap: () async {
          if (isUnread)
            await _db
                .child(
                    'notifications/${FirebaseAuth.instance.currentUser!.uid}/${n['id']}')
                .remove();
          if (context.mounted) {
            Navigator.pop(context);
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => AlertDetailScreen(alertId: n['alertId'])));
          }
        },
      ),
    );
  }

  Widget _buildPmActionItem(Map<String, dynamic> action, bool isUnread,
      StateSetter setModalState, BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: const Color(0xFFF0FDF4),
          border: Border.all(color: const Color(0xFFBBF7D0)),
          borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.assignment_turned_in,
                  color: Colors.green, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(action['title'] ?? 'PM Action',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 4),
                    Text(action['description'] ?? '',
                        style: TextStyle(
                            color: Colors.grey.shade600, fontSize: 13)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.access_time,
                            size: 14, color: Colors.grey.shade500),
                        const SizedBox(width: 4),
                        Text(
                            _formatTimestamp(DateTime.parse(
                                action['timestamp'] ??
                                    DateTime.now().toIso8601String())),
                            style: TextStyle(
                                color: Colors.grey.shade500, fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              ),
              if (isUnread)
                Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                        color: _red, shape: BoxShape.circle)),
            ],
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () async {
              await _db
                  .child(
                      'pm_actions/${FirebaseAuth.instance.currentUser!.uid}/${action['id']}')
                  .remove();
              if (context.mounted) {
                setModalState(() {
                  _pmActions.removeWhere((item) => item['id'] == action['id']);
                });
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('PM action marked as read'),
                    backgroundColor: Colors.green));
              }
            },
            icon: const Icon(Icons.check_circle_outline,
                size: 16, color: Colors.black87),
            label: const Text('Mark as read',
                style: TextStyle(color: Colors.black87)),
            style: OutlinedButton.styleFrom(
                backgroundColor: _white,
                side: BorderSide(color: Colors.grey.shade300),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8))),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
          color: _white,
          border:
              Border(bottom: BorderSide(color: Color(0xFFE5E7EB), width: 1))),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: [
        Row(
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                Icon(Icons.factory, size: 28, color: _navy.withOpacity(0.8)),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    decoration: const BoxDecoration(
                        color: _white, shape: BoxShape.circle),
                    child: const Icon(Icons.warning, color: _red, size: 14),
                  ),
                )
              ],
            ),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Supervisor',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700, color: _navy)),
              Text(widget.userName,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ]),
          ],
        ),
        const Spacer(),
        Stack(clipBehavior: Clip.none, children: [
          IconButton(
              icon:
                  const Icon(Icons.notifications_none, color: _navy, size: 28),
              onPressed: _showNotifications),
          if (_notificationCount > 0)
            Positioned(
              top: 6,
              right: 6,
              child: Container(
                width: 18,
                height: 18,
                decoration:
                    const BoxDecoration(color: _red, shape: BoxShape.circle),
                child: Center(
                    child: Text('$_notificationCount',
                        style: const TextStyle(
                            color: _white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700))),
              ),
            ),
        ]),
        const SizedBox(width: 4),
        InkWell(
          onTap: widget.onLogout,
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
                border: Border.all(color: _red),
                borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.logout, size: 20, color: _red),
          ),
        ),
      ]),
    );
  }
}

// ---------- SUMMARY CARD ----------
class _SummaryCard extends StatelessWidget {
  final String label;
  final int count;
  final Color color, bgColor;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  const _SummaryCard(
      {required this.label,
      required this.count,
      required this.color,
      required this.bgColor,
      required this.icon,
      required this.active,
      required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: active ? color : const Color(0xFFE5E7EB),
                width: active ? 2 : 1),
            boxShadow: active
                ? [
                    BoxShadow(
                        color: color.withOpacity(0.15),
                        blurRadius: 8,
                        offset: const Offset(0, 2))
                  ]
                : [],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                Text('$count',
                    style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: color)),
                const SizedBox(height: 8),
                const Text('Click to see details',
                    style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
              ]),
              Container(
                  width: 48,
                  height: 48,
                  decoration:
                      BoxDecoration(color: bgColor, shape: BoxShape.circle),
                  child: Icon(icon, color: color, size: 24)),
            ],
          ),
        ),
      );
}

// ---------- DETAIL PANEL ----------
class _DetailPanel extends StatelessWidget {
  final String activeView;
  final List<AlertModel> available, allInProgress, validated;
  final AlertProvider provider;
  final String superviseurId, superviseurName;
  const _DetailPanel(
      {required this.activeView,
      required this.available,
      required this.allInProgress,
      required this.validated,
      required this.provider,
      required this.superviseurId,
      required this.superviseurName});

  String get _title => switch (activeView) {
        'received' => 'Manage Alerts Received',
        'claimed' => 'Claimed Alerts',
        _ => 'Fixed Alerts'
      };

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        decoration: BoxDecoration(
            color: _white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE5E7EB))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Row(children: [
              const Icon(Icons.info_outline, color: _navy, size: 20),
              const SizedBox(width: 8),
              Text(_title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold, color: _navy))
            ]),
          ),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),
          const SizedBox(height: 16),
          if (activeView == 'received')
            _ReceivedView(
                alerts: available,
                provider: provider,
                superviseurId: superviseurId,
                superviseurName: superviseurName),
          if (activeView == 'claimed')
            _ClaimedView(alerts: allInProgress, provider: provider),
          if (activeView == 'fixed')
            _FixedView(alerts: validated, provider: provider),
          const SizedBox(height: 8),
        ]),
      );
}

// ---------- RECEIVED VIEW ----------
class _ReceivedView extends StatelessWidget {
  final List<AlertModel> alerts;
  final AlertProvider provider;
  final String superviseurId, superviseurName;
  const _ReceivedView(
      {required this.alerts,
      required this.provider,
      required this.superviseurId,
      required this.superviseurName});

  @override
  Widget build(BuildContext context) {
    if (alerts.isEmpty)
      return _empty(Icons.notifications_off_outlined, Colors.orange,
          'No alerts available', 'All alerts are being handled');
    return Column(
        children: alerts
            .map((a) => _AlertRow(
                  alert: a,
                  rowColor: const Color(0xFFFFF7ED),
                  statusLabel: 'Available',
                  statusColor: Colors.orange,
                  trailing: ElevatedButton.icon(
                    onPressed: () async {
                      try {
                        await provider.takeAlert(
                            a.id, superviseurId, superviseurName);
                        final pmRef = FirebaseDatabase.instance
                            .ref('pm_actions/$superviseurId')
                            .push();
                        await pmRef.set({
                          'title': 'Alert Assigned',
                          'description': 'You claimed alert: ${a.description}',
                          'timestamp': DateTime.now().toIso8601String(),
                          'status': 'unread',
                          'alertId': a.id,
                          'type': 'alert_assigned',
                        });
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(e.toString()),
                            backgroundColor: Colors.red));
                      }
                    },
                    icon: const Icon(Icons.play_circle_outline, size: 16),
                    label: const Text('Claim'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: _navy,
                        foregroundColor: _white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        textStyle: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8))),
                  ),
                ))
            .toList());
  }
}

// ---------- CLAIMED VIEW (with collaboration dialog on "Request Assistance") ----------
class _ClaimedView extends StatelessWidget {
  final List<AlertModel> alerts;
  final AlertProvider provider;
  const _ClaimedView({required this.alerts, required this.provider});

  Future<void> _showHoldCollabPrompt(
      BuildContext context, AlertModel alert) async {
    final shouldOpen = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
        contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        title: Row(
          children: [
            const Icon(Icons.people_alt_outlined,
                color: Colors.deepPurple, size: 22),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Request Collaboration',
                style: TextStyle(
                    color: Colors.deepPurple, fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              onPressed: () => Navigator.pop(context, false),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Hold detected! Would you like to request collaboration for this alert?',
              style: TextStyle(fontSize: 13, color: _muted),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                border: Border.all(color: const Color(0xFFFED7AA)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _typeLabel(alert.type),
                    style: const TextStyle(
                      color: Color(0xFF9A3412),
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${alert.usine} - Line ${alert.convoyeur} - WS ${alert.poste}',
                    style:
                        const TextStyle(fontSize: 12, color: Color(0xFFEA580C)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    alert.description,
                    style:
                        const TextStyle(fontSize: 13, color: Color(0xFF7C2D12)),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          OutlinedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.people_outline),
            label: const Text('Collab'),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.deepPurple),
          ),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
          ),
        ],
      ),
    );

    if (shouldOpen == true && context.mounted) {
      showDialog(
        context: context,
        builder: (_) => collab.RequestCollaborationDialog(alert: alert),
      );
    }
  }

  void _resolveWithDialog(BuildContext context, AlertModel alert) {
    final reasonController = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Resolve Alert'),
        content: TextField(
            controller: reasonController,
            decoration: const InputDecoration(hintText: 'Resolution reason'),
            maxLines: 3),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (reasonController.text.trim().isEmpty) return;
              await provider.resolveAlert(
                  alert.id, reasonController.text.trim());
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Resolve'),
          ),
        ],
      ),
    );
  }

  Future<void> _getAiAssist(BuildContext context, AlertModel alert) async {
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()));
    final pastResolutions =
        await provider.getPastResolutionsForType(alert.type, 3);
    final aiService = AIService();
    final suggestion = await aiService.getResolutionSuggestion(
      alertType: alert.type,
      alertDescription: alert.description,
      pastResolutions: pastResolutions,
      convoyeur: alert.convoyeur,
      usine: alert.usine,
      poste: alert.poste,
    );
    if (context.mounted) {
      Navigator.pop(context);
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('🤖 AI Suggestion'),
          content: SingleChildScrollView(child: Text(suggestion)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'))
          ],
        ),
      );
    }
  }

  Future<void> _toggleCritical(AlertModel alert, BuildContext context) async {
    String? note;
    if (!alert.isCritical) {
      note = await showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Mark as Critical'),
          content: TextField(
            decoration: const InputDecoration(
                hintText: 'Optional note (reason, impact, etc.)'),
            maxLines: 3,
            onChanged: (value) => note = value,
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, null),
                child: const Text('Cancel')),
            ElevatedButton(
                onPressed: () => Navigator.pop(context, note ?? ''),
                child: const Text('Mark Critical')),
          ],
        ),
      );
      if (note == null) return;
    }
    await provider.toggleCritical(alert.id, !alert.isCritical,
        note: note?.isNotEmpty == true ? note : null);
  }

  // The old _requestAssistance method is removed – its action is now handled by the collaboration dialog.

  Future<void> _offerAssistance(BuildContext context, AlertModel alert) async {
    await provider.requestHelp(alert.id, FirebaseAuth.instance.currentUser!.uid,
        FirebaseAuth.instance.currentUser!.email!.split('@').first);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Assistance offered. The claimant will be notified.'),
        backgroundColor: Colors.purple));
  }

  String _getStatusLabel(AlertModel alert, bool isMine, String currentUserId) {
    final hasValidAssistant =
        alert.assistantId != null && alert.assistantId != alert.superviseurId;
    if (hasValidAssistant) {
      if (alert.assistantId == currentUserId)
        return 'Assisting ${alert.superviseurName}';
      else if (isMine)
        return 'My Claim (assisted by ${alert.assistantName ?? 'someone'})';
      else
        return 'Claimed by ${alert.superviseurName} (assisted by ${alert.assistantName ?? 'someone'})';
    }
    if (isMine) return 'My Claim';
    return 'Claimed by ${alert.superviseurName ?? 'other'}';
  }

  @override
  Widget build(BuildContext context) {
    if (alerts.isEmpty)
      return _empty(Icons.error_outline, const Color(0xFF94A3B8),
          'No alerts in progress', 'Claim an alert to start');
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
    return Column(
        children: alerts.map((a) {
      final isMine = a.superviseurId == currentUserId;
      final showRequestAssistance = isMine && a.assistantId == null;
      final showOfferAssistance = !isMine && a.assistantId == null;
      return _AlertRow(
        alert: a,
        rowColor: const Color(0xFFEFF6FF),
        borderColor: const Color(0xFF93C5FD),
        statusLabel: _getStatusLabel(a, isMine, currentUserId),
        statusColor: Colors.blue,
        pulseDot: !isMine,
        extraContent: _ElapsedTimer(alert: a, provider: provider),
        onCriticalToggle: isMine ? () => _toggleCritical(a, context) : null,
        // Hold gesture opens collaboration flow while preserving existing logic.
        onRequestAssistance: showRequestAssistance
            ? () => _showHoldCollabPrompt(context, a)
            : null,
        onOfferAssistance:
            showOfferAssistance ? () => _offerAssistance(context, a) : null,
        trailing: isMine
            ? Column(mainAxisSize: MainAxisSize.min, children: [
                ElevatedButton.icon(
                  onPressed: () => _resolveWithDialog(context, a),
                  icon: const Icon(Icons.check_circle_outline, size: 16),
                  label: const Text('Fixed'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    foregroundColor: _white,
                    minimumSize: const Size(110, 36),
                    textStyle: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  onPressed: () async {
                    String? reason;
                    await showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Suspend Alert'),
                        content: TextField(
                          decoration: const InputDecoration(
                              hintText: 'Optional reason for suspension'),
                          onChanged: (value) => reason = value,
                        ),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Cancel')),
                          ElevatedButton(
                            onPressed: () {
                              Navigator.pop(context);
                              provider.returnToQueue(a.id,
                                  reason: reason?.trim().isEmpty == true
                                      ? null
                                      : reason);
                            },
                            child: const Text('Suspend'),
                          ),
                        ],
                      ),
                    );
                  },
                  icon: const Icon(Icons.rotate_left, size: 16),
                  label: const Text('Suspend'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange,
                    side: const BorderSide(color: Colors.orange),
                    minimumSize: const Size(110, 36),
                    textStyle: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  onPressed: () => _getAiAssist(context, a),
                  icon: const Icon(Icons.auto_awesome, size: 16),
                  label:
                      const Text('AI Assist', style: TextStyle(fontSize: 11)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.purple,
                    side: const BorderSide(color: Colors.purple),
                    minimumSize: const Size(110, 36),
                    textStyle: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w600),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ])
            : null,
      );
    }).toList());
  }
}

// ---------- FIXED VIEW ----------
class _FixedView extends StatelessWidget {
  final List<AlertModel> alerts;
  final AlertProvider provider;
  const _FixedView({required this.alerts, required this.provider});

  @override
  Widget build(BuildContext context) {
    if (alerts.isEmpty)
      return _empty(Icons.check_circle_outline, Colors.green, 'No fixed alerts',
          'Fixed alerts will appear here');
    return Column(
        children: alerts
            .map((a) => _AlertRow(
                  alert: a,
                  rowColor: const Color(0xFFF0FDF4),
                  statusLabel: 'Fixed',
                  statusColor: const Color(0xFF16A34A),
                  statusIcon: Icons.check_circle_outline,
                  extraContent: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                            color: const Color(0xFFDCFCE7),
                            border: Border.all(color: const Color(0xFF86EFAC)),
                            borderRadius: BorderRadius.circular(7)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.timer_outlined,
                              size: 15, color: Color(0xFF16A34A)),
                          const SizedBox(width: 6),
                          Text(
                              'Resolution time: ${provider.formatElapsedTime(a.elapsedTime)}',
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF16A34A)))
                        ]),
                      ),
                      if (a.superviseurName != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text.rich(TextSpan(children: [
                            const TextSpan(
                                text: 'Fixed by: ',
                                style: TextStyle(
                                    fontSize: 12, color: Color(0xFF6B7280))),
                            TextSpan(
                                text: a.superviseurName,
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: _navy)),
                            if (a.assistantName != null)
                              TextSpan(
                                  text: ' (assisted by ${a.assistantName})',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w400,
                                      color: _muted)),
                          ])),
                        ),
                    ],
                  ),
                ))
            .toList());
  }
}

// ---------- ALERT ROW ----------
class _AlertRow extends StatelessWidget {
  final AlertModel alert;
  final Color rowColor;
  final Color? borderColor;
  final String statusLabel;
  final Color statusColor;
  final IconData? statusIcon;
  final bool pulseDot;
  final Widget? trailing;
  final Widget? extraContent;
  final VoidCallback? onCriticalToggle;
  final VoidCallback? onRequestAssistance;
  final VoidCallback? onOfferAssistance;

  const _AlertRow(
      {required this.alert,
      required this.rowColor,
      required this.statusLabel,
      required this.statusColor,
      this.borderColor,
      this.statusIcon,
      this.pulseDot = false,
      this.trailing,
      this.extraContent,
      this.onCriticalToggle,
      this.onRequestAssistance,
      this.onOfferAssistance});

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final effectiveRowColor = alert.isCritical ? Colors.red.shade50 : rowColor;
    final effectiveBorderColor = alert.isCritical
        ? Colors.red.shade300
        : (borderColor ?? const Color(0xFFE5E7EB));

    final List<Widget> rightWidgets = [];
    if (trailing != null) rightWidgets.add(trailing!);
    if (onOfferAssistance != null)
      rightWidgets.add(ElevatedButton.icon(
          onPressed: onOfferAssistance,
          icon: const Icon(Icons.handshake, size: 16),
          label: const Text('Assist', style: TextStyle(fontSize: 12)),
          style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              textStyle: const TextStyle(fontWeight: FontWeight.w600),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)))));

    final card = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: effectiveRowColor,
          border: Border.all(
              color: effectiveBorderColor, width: borderColor != null ? 2 : 1),
          borderRadius: BorderRadius.circular(10)),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact =
              constraints.maxWidth < 520 && rightWidgets.isNotEmpty;

          final leftPanel = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                if (alert.isCritical)
                  const Icon(Icons.warning_amber_rounded,
                      color: Colors.red, size: 16),
                if (alert.isCritical) const SizedBox(width: 4),
                pulseDot
                    ? _PulseDot(color: _typeColor(alert.type))
                    : Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                            color: _typeColor(alert.type),
                            shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(_typeLabel(alert.type),
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: _navy))),
                if (alert.status == 'en_cours' &&
                    alert.superviseurId == currentUserId &&
                    onCriticalToggle != null)
                  IconButton(
                      onPressed: onCriticalToggle,
                      icon: Icon(
                          alert.isCritical
                              ? Icons.warning_rounded
                              : Icons.warning_amber_outlined,
                          color: alert.isCritical ? Colors.red : Colors.orange,
                          size: 20),
                      tooltip: alert.isCritical
                          ? 'Remove critical flag'
                          : 'Mark as critical',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints()),
              ]),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 4, children: [
                _OutlineBadge(
                    '${alert.usine} — Line ${alert.convoyeur} — Workstation ${alert.poste}'),
                _FilledBadge(
                    label: statusLabel, color: statusColor, icon: statusIcon),
              ]),
              const SizedBox(height: 6),
              Text(alert.description,
                  style:
                      const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
              const SizedBox(height: 4),
              Text(
                  'Address: ${alert.adresse}  ·  ${_formatTimestamp(alert.timestamp)}',
                  style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF9CA3AF),
                      fontFamily: 'monospace')),
              if (extraContent != null) extraContent!,
            ],
          );

          if (isCompact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                leftPanel,
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 110),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: rightWidgets,
                    ),
                  ),
                ),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: leftPanel),
              if (rightWidgets.isNotEmpty)
                Flexible(
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(minWidth: 100),
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: rightWidgets))),
            ],
          );
        },
      ),
    );

    if (onRequestAssistance == null) {
      return Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: card,
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: _HoldToCollabCard(
        onCompleted: onRequestAssistance!,
        child: card,
      ),
    );
  }
}

class _HoldToCollabCard extends StatefulWidget {
  final VoidCallback onCompleted;
  final Widget child;

  const _HoldToCollabCard({required this.onCompleted, required this.child});

  @override
  State<_HoldToCollabCard> createState() => _HoldToCollabCardState();
}

class _HoldToCollabCardState extends State<_HoldToCollabCard>
    with SingleTickerProviderStateMixin {
  Timer? _timer;
  double _progress = 0;
  bool _triggered = false;
  DateTime? _start;
  AnimationController? _pulseController;
  static const _holdDuration = Duration(seconds: 2);

  bool get _isHolding => _progress > 0;

  AnimationController _ensurePulseController() {
    return _pulseController ??= AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
  }

  void _startHold() {
    _timer?.cancel();
    _start = DateTime.now();
    _triggered = false;
    _ensurePulseController().repeat(reverse: true);
    _timer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (!mounted || _start == null) return;
      final elapsed = DateTime.now().difference(_start!);
      final next = (elapsed.inMilliseconds / _holdDuration.inMilliseconds)
          .clamp(0.0, 1.0);
      setState(() => _progress = next);
      if (next >= 1 && !_triggered) {
        _triggered = true;
        timer.cancel();
        widget.onCompleted();
        setState(() {
          _progress = 0;
          _start = null;
        });
      }
    });
  }

  void _cancelHold() {
    _timer?.cancel();
    _timer = null;
    _start = null;
    _pulseController?.stop();
    if (_progress != 0) {
      setState(() => _progress = 0);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pulse = _pulseController;

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _startHold(),
      onPointerUp: (_) => _cancelHold(),
      onPointerCancel: (_) => _cancelHold(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          children: [
            widget.child,
            if (_isHolding && pulse != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: Stack(
                    children: [
                      FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: _progress,
                        child: Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [
                                Color(0x33C084FC),
                                Color(0x55A855F7),
                                Color(0x447E22CE),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: Center(
                          child: ScaleTransition(
                            scale: Tween<double>(begin: 0.96, end: 1.04)
                                .animate(CurvedAnimation(
                              parent: pulse,
                              curve: Curves.easeInOut,
                            )),
                            child: FadeTransition(
                              opacity: Tween<double>(begin: 0.75, end: 1.0)
                                  .animate(CurvedAnimation(
                                parent: pulse,
                                curve: Curves.easeInOut,
                              )),
                              child: SizedBox(
                                width: 210,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF3E8FF)
                                        .withOpacity(0.96),
                                    borderRadius: BorderRadius.circular(99),
                                    border: Border.all(
                                      color: const Color(0xFFD8B4FE),
                                    ),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(99),
                                    child: Stack(
                                      children: [
                                        FractionallySizedBox(
                                          alignment: Alignment.centerLeft,
                                          widthFactor: _progress,
                                          child: Container(
                                            height: 24,
                                            decoration: const BoxDecoration(
                                              gradient: LinearGradient(
                                                begin: Alignment.centerLeft,
                                                end: Alignment.centerRight,
                                                colors: [
                                                  Color(0xFFC084FC),
                                                  Color(0xFFA855F7),
                                                  Color(0xFF7E22CE),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                        const Padding(
                                          padding: EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 5),
                                          child: Text(
                                            'Holding to collab...',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Color(0xFF7E22CE),
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 10,
              child: Text(
                '💡 Hold to collab this alert',
                style: TextStyle(
                  fontSize: 11,
                  color: _isHolding
                      ? const Color(0xFF7C3AED)
                      : const Color(0xFF8B5CF6),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ElapsedTimer extends StatelessWidget {
  final AlertModel alert;
  final AlertProvider provider;
  const _ElapsedTimer({required this.alert, required this.provider});

  @override
  Widget build(BuildContext context) {
    context.watch<AlertProvider>();
    final elapsed = provider.getElapsedTime(alert);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
          color: const Color(0xFFDBEAFE),
          border: Border.all(color: const Color(0xFF93C5FD)),
          borderRadius: BorderRadius.circular(7)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.timer_outlined, size: 15, color: Color(0xFF1D4ED8)),
        const SizedBox(width: 6),
        Flexible(
            child: Text('Elapsed time: $elapsed',
                style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1D4ED8)),
                overflow: TextOverflow.ellipsis)),
      ]),
    );
  }
}

class _PulseDot extends StatefulWidget {
  final Color color;
  const _PulseDot({required this.color});
  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _anim = Tween(begin: 0.3, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
      opacity: _anim,
      child: Container(
          width: 10,
          height: 10,
          decoration:
              BoxDecoration(color: widget.color, shape: BoxShape.circle)));
}

class _OutlineBadge extends StatelessWidget {
  final String text;
  const _OutlineBadge(this.text);
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFD1D5DB)),
          borderRadius: BorderRadius.circular(99)),
      child: Text(text,
          style: const TextStyle(fontSize: 10, color: Color(0xFF374151))));
}

class _FilledBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  const _FilledBadge({required this.label, required this.color, this.icon});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: color, borderRadius: BorderRadius.circular(99)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: _white),
            const SizedBox(width: 3)
          ],
          Flexible(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 10, color: _white, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1)),
        ]),
      );
}

Widget _empty(IconData icon, Color color, String title, String sub) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Center(
        child: Column(children: [
          Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: color.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(icon, size: 36, color: color)),
          const SizedBox(height: 12),
          Text(title,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87)),
          const SizedBox(height: 4),
          Text(sub,
              style: const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF))),
        ]),
      ),
    );
