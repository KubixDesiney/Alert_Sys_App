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
import '../services/offline_account_cache.dart';
import '../theme.dart';
import '../utils/alert_meta.dart';
import '../utils/alert_claim_error.dart';
import '../widgets/dashboard_common.dart';
import 'login_screen.dart';
import 'alert_detail_screen.dart';
import 'alert_scan_screen.dart';
import 'locator_tab.dart';
import '../widgets/voice_command_button.dart';
import '../utils/user_friendly_error.dart';
import '../widgets/common/app_loading_indicator.dart';
import '../widgets/common/language_toggle.dart';
import '../l10n/app_strings.dart';
import '../widgets/dashboard/dashboard_badges.dart';
import '../widgets/dashboard/dashboard_bottom_nav.dart';
import '../widgets/dashboard/elapsed_timer.dart';
import '../l10n/generated/app_localizations.dart';
import 'supervisor_collaboration_screen.dart'; // new
import 'supervisor_collaboration_screen.dart' as collab;
import '../models/collaboration_model.dart';
import '../services/collaboration_service.dart';

part 'dashboard_screen_views.dart';

Color get _navy => brandPrimary(false);
const _white = AppColors.white;
const _muted = AppColors.textMuted;

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
    final cachedUsine = await OfflineAccountCache.usineFor(user.uid);
    try {
      final snapshot = await FirebaseDatabase.instance
          .ref('users/${user.uid}/usine')
          .once()
          .timeout(const Duration(seconds: 5));
      final value = snapshot.snapshot.value?.toString().trim();
      if (value != null && value.isNotEmpty) {
        await OfflineAccountCache.save(uid: user.uid, usine: value);
        return value;
      }
    } catch (e) {
      debugPrint('Supervisor factory load failed; using cached value: $e');
    }
    return cachedUsine ?? 'Usine A';
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

  void _goToPage(int index) {
    setState(() => _currentPage = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appTheme.scaffold,
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) => setState(() => _currentPage = index),
        children: [
          _OriginalDashboardContent(
            superviseurId: _superviseurId,
            superviseurName: _superviseurName,
            usine: _usine,
            onLogout: _logout,
          ),
          LocatorScreen(supervisorId: _superviseurId, factoryName: _usine),
          AlertScanScreen(isActive: _currentPage == 2),
          const CollaborationProgressScreen(),
        ],
      ),
      // Hands-free voice command launcher. Sits above the bottom nav so it's
      // reachable on both dashboard pages without obstructing alert cards.
      floatingActionButton: const VoiceCommandButton(),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: DashboardBottomNav(
        currentIndex: _currentPage,
        onTap: _goToPage,
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

  const _OriginalDashboardContent({
    required this.superviseurId,
    required this.superviseurName,
    required this.usine,
    required this.onLogout,
  });

  @override
  State<_OriginalDashboardContent> createState() =>
      _OriginalDashboardContentState();
}

class _OriginalDashboardContentState extends State<_OriginalDashboardContent> {
  String _activeView = 'received';
  bool _showPanel = false;
  final GlobalKey<_HeaderState> _headerKey = GlobalKey<_HeaderState>();

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
    final assisted = provider.assistedAlerts(widget.superviseurId);
    final badge = available.length + myInProgress.length;

    return SafeArea(
      child: Column(
        children: [
          // Use the existing _Header (with notifications, buzzing, etc.)
          _Header(
            key: _headerKey,
            userName: widget.superviseurName,
            clientName: 'SAGEM',
            activeBadge: badge,
            usine: widget.usine,
            onLogout: widget.onLogout,
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Dashboard Title
                  Row(
                    children: [
                      Icon(Icons.dashboard, color: _navy, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        AppLocalizations.of(context).dashboardHeaderTitle,
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: _navy),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Summary Cards (as in original)
                  _SummaryCard(
                    label: context.tr('Fixed Alerts'),
                    count: validated.length + assisted.length,
                    color: const Color(0xFF22C55E),
                    bgColor: const Color(0xFFDCFCE7),
                    icon: Icons.check_circle_outline,
                    active: _activeView == 'fixed' && _showPanel,
                    onTap: () => _handleCardClick('fixed'),
                  ),
                  const SizedBox(height: 12),
                  _SummaryCard(
                    label: context.tr('Claimed Alerts'),
                    count: myInProgress.length,
                    color: const Color(0xFF3B82F6),
                    bgColor: const Color(0xFFDBEAFE),
                    icon: Icons.timer,
                    active: _activeView == 'claimed' && _showPanel,
                    onTap: () => _handleCardClick('claimed'),
                  ),
                  const SizedBox(height: 12),
                  _SummaryCard(
                    label: context.tr('Manage Pending Alerts'),
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
                      assisted: assisted,
                      provider: provider,
                      superviseurId: widget.superviseurId,
                      superviseurName: widget.superviseurName,
                      onAlertClaimed: () async {
                        await _headerKey.currentState?.stopBuzzingFromClaim();
                      },
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
  final String usine;
  final VoidCallback onLogout;
  const _Header({
    super.key,
    required this.userName,
    required this.clientName,
    required this.activeBadge,
    required this.usine,
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
  StreamSubscription<DatabaseEvent>? _notifSubscription;
  StreamSubscription<DatabaseEvent>? _pmSubscription;

  bool _isBuzzing = false;
  String? _buzzingNotificationId;
  static const Set<String> _forceBuzzNotificationTypes = {
    'cross_factory_transfer',
  };
  static const Set<String> _crossFactoryNotificationTypes = {
    'assistant_assigned',
    'collab_auto_approved',
    'collaboration_approved',
    'collaboration_assistant_accepted',
    'collaboration_assistant_removed',
    'collaboration_removed',
    'collaboration_rejected',
    'collaboration_request',
    'collaboration_request_admin',
  };

  Future<void> stopBuzzingFromClaim() => _stopBuzzing();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      _notifSubscription =
          _db.child('notifications/$uid').onValue.listen(_handleNotifications);
      /*
        final data = event.snapshot.value;
        if (!mounted) return; // ← add this
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
                final type = newUnread['type']?.toString() ?? '';
                final forceBuzz = newUnread['buzz'] == true ||
                    _forceBuzzNotificationTypes.contains(type);
                bool shouldBuzz = false;
                if (userRole == 'admin') {
                  shouldBuzz = true;
                } else if (userRole == 'supervisor' &&
                    (alertUsine == userUsine || forceBuzz)) {
                  if (mounted) {
                    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
                    final hasClaimed = context
                        .read<AlertProvider>()
                        .inProgressAlerts(uid)
                        .isNotEmpty;
                    shouldBuzz = forceBuzz || !hasClaimed;
                  }
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

      */
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
    _notifSubscription?.cancel();
    _pmSubscription?.cancel();
    Vibration.cancel();
    super.dispose();
  }

  Future<void> _handleNotifications(DatabaseEvent event) async {
    final data = event.snapshot.value;
    if (!mounted) return;
    if (data == null) {
      await _stopBuzzing();
      setState(() {
        _notificationCount = 0;
        _notifications = [];
      });
      return;
    }

    final map = Map<String, dynamic>.from(data as Map);
    final rawList = map.entries.map((e) {
      final m = Map<String, dynamic>.from(e.value as Map);
      m['id'] = e.key;
      return m;
    }).toList();
    final previousIds = _notifications
        .map((notification) => notification['id']?.toString())
        .whereType<String>()
        .toSet();
    final list = <Map<String, dynamic>>[];
    for (final notification in rawList) {
      if (await _shouldKeepNotification(notification)) {
        list.add(notification);
      }
    }
    final pending = list.where((n) => n['status'] != 'read').toList();

    if (pending.isNotEmpty) {
      Map<String, dynamic>? newUnread;
      for (final n in pending) {
        final id = n['id']?.toString();
        if (id != null && !previousIds.contains(id)) {
          newUnread = n;
          break;
        }
      }
      if (newUnread != null &&
          (_shouldForceBuzzNotification(newUnread) ||
              (_isAiAssignmentNotification(newUnread) &&
                  !_hasClaimedAlert()))) {
        await _startBuzzing(newUnread);
      }
    }

    if (_buzzingNotificationId != null &&
        list.every(
            (notification) => notification['id'] != _buzzingNotificationId)) {
      await _stopBuzzing();
    }

    if (!mounted) return;
    setState(() {
      _notifications = list;
      _notificationCount = pending.length;
    });
  }

  bool _sameFactory(String? a, String? b) {
    final left = (a ?? '').trim().toLowerCase();
    final right = (b ?? '').trim().toLowerCase();
    return left.isNotEmpty && left == right;
  }

  bool _isCollaborationNotification(Map<String, dynamic> notification) {
    final type = notification['type']?.toString() ?? '';
    return _crossFactoryNotificationTypes.contains(type);
  }

  bool _isCrossFactoryTransferNotification(Map<String, dynamic> notification) {
    return notification['type']?.toString() == 'cross_factory_transfer';
  }

  bool _isAiAssignmentNotification(Map<String, dynamic> notification) {
    return notification['type']?.toString() == 'ai_assigned';
  }

  bool _shouldForceBuzzNotification(Map<String, dynamic> notification) {
    final type = notification['type']?.toString() ?? '';
    return notification['buzz'] == true ||
        _forceBuzzNotificationTypes.contains(type);
  }

  bool _supportsBuzzingNotification(Map<String, dynamic> notification) {
    return _isAiAssignmentNotification(notification) ||
        _isCrossFactoryTransferNotification(notification);
  }

  bool _hasClaimedAlert() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || !mounted) return false;
    return context.read<AlertProvider>().inProgressAlerts(uid).isNotEmpty;
  }

  String? _notificationFactory(Map<String, dynamic> notification) {
    for (final key in const ['usine', 'alertUsine', 'factoryName']) {
      final value = notification[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  Future<String?> _fetchAlertFactory(String alertId) async {
    final alertSnap = await _db.child('alerts/$alertId/usine').get();
    final value = alertSnap.value?.toString().trim();
    return (value == null || value.isEmpty) ? null : value;
  }

  Future<bool> _shouldKeepNotification(
      Map<String, dynamic> notification) async {
    if (_isCollaborationNotification(notification) ||
        _isCrossFactoryTransferNotification(notification)) {
      return true;
    }

    final usine = _notificationFactory(notification);
    final alertId = notification['alertId']?.toString().trim();
    if ((usine == null || usine.isEmpty) &&
        (alertId == null || alertId.isEmpty)) {
      return true;
    }

    final resolvedFactory = (usine != null && usine.isNotEmpty)
        ? usine
        : await _fetchAlertFactory(alertId!);
    if (resolvedFactory == null || resolvedFactory.isEmpty) {
      return false;
    }
    return _sameFactory(resolvedFactory, widget.usine);
  }

  Widget _buildStopBuzzingButton(StateSetter setModalState) {
    final t = context.appTheme;
    return OutlinedButton.icon(
      onPressed: () async {
        await _stopBuzzing();
        if (mounted) {
          setModalState(() {});
        }
      },
      icon: Icon(Icons.vibration, size: 16, color: t.red),
      label: Text(context.tr('Stop Buzzing'), style: TextStyle(color: t.red)),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: t.red),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Future<void> _startBuzzing(Map<String, dynamic> notification) async {
    final notificationId = notification['id']?.toString();
    if (notificationId == null || !_supportsBuzzingNotification(notification)) {
      return;
    }
    await Vibration.cancel();
    final hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator == true) {
      Vibration.vibrate(pattern: [1000, 1000], repeat: 0);
      if (!mounted) return;
      setState(() {
        _isBuzzing = true;
        _buzzingNotificationId = notificationId;
      });
    }
  }

  Future<void> _stopBuzzing() async {
    await Vibration.cancel();
    if (!mounted) return;
    if (_isBuzzing || _buzzingNotificationId != null) {
      setState(() {
        _isBuzzing = false;
        _buzzingNotificationId = null;
      });
    }
  }

  // ────────────────────────────────────────────────────────────
  // Notifications Drawer (fully theme‑aware)
  // ────────────────────────────────────────────────────────────
  void _showNotifications() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final t = context.appTheme;
            return Container(
              height: MediaQuery.of(context).size.height * 0.9,
              decoration: BoxDecoration(
                color: t.card,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
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
                            children: [
                              Text(context.tr('All Notifications'),
                                  style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: t.text)),
                              const SizedBox(height: 4),
                              Text(
                                  context.tr(
                                      'View and manage your alerts and PM actions'),
                                  style:
                                      TextStyle(fontSize: 14, color: t.muted)),
                            ],
                          ),
                        ),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                  color: t.red,
                                  borderRadius: BorderRadius.circular(12)),
                              child: Text(
                                  context.tr('{n} unread',
                                      {'n': '$_notificationCount'}),
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12)),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () => Navigator.pop(context),
                              child: Icon(Icons.close, color: t.muted),
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
                        color: t.scaffold,
                        borderRadius: BorderRadius.circular(30)),
                    child: TabBar(
                      controller: _tabController,
                      indicator: BoxDecoration(
                          color: t.card,
                          borderRadius: BorderRadius.circular(30),
                          boxShadow: const [
                            BoxShadow(
                                color: Color(0x0A000000),
                                blurRadius: 4,
                                offset: Offset(0, 2))
                          ]),
                      labelColor: t.navy,
                      unselectedLabelColor: t.muted,
                      labelStyle: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13),
                      unselectedLabelStyle: const TextStyle(
                          fontWeight: FontWeight.w500, fontSize: 13),
                      tabs: [
                        Tab(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(context.tr('Alerts')),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                    color: t.red, shape: BoxShape.circle),
                                child: Text('${_notifications.length}',
                                    style: const TextStyle(
                                        color: Colors.white,
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
                              Text(context.tr('PM Actions')),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                    color: t.red, shape: BoxShape.circle),
                                child: Text('${_pmActions.length}',
                                    style: const TextStyle(
                                        color: Colors.white,
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
                            ? Center(
                                child: Text(context.tr('No alerts'),
                                    style: TextStyle(color: t.muted)))
                            : ListView.builder(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 20),
                                itemCount: _notifications.length,
                                itemBuilder: (context, index) {
                                  final n = _notifications[index];
                                  final isHelp = n['type'] == 'help_request';
                                  final isAssistance =
                                      n['type'] == 'assistance_request';
                                  final isCollab =
                                      n['type'] == 'collaboration_request';
                                  final isTransfer =
                                      n['type'] == 'cross_factory_transfer';
                                  final isUnread = n['status'] != 'read';
                                  if (isHelp) {
                                    return _buildHelpRequestItem(
                                        n, isUnread, setModalState, context);
                                  } else if (isAssistance) {
                                    return _buildAssistanceRequestItem(
                                        n, isUnread, setModalState, context);
                                  } else if (isCollab) {
                                    return _buildCollabRequestItem(
                                        n, isUnread, setModalState, context);
                                  } else if (isTransfer) {
                                    return _buildCrossFactoryTransferItem(
                                        n, isUnread, setModalState, context);
                                  } else {
                                    return _buildDefaultNotificationItem(
                                        n, isUnread, setModalState, context);
                                  }
                                },
                              ),
                        // PM Actions tab
                        _pmActions.isEmpty
                            ? Center(
                                child: Text(context.tr('No PM actions'),
                                    style: TextStyle(color: t.muted)))
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

  // Notification helpers
  Future<void> _markNotificationAsRead(
    Map<String, dynamic> notification,
    StateSetter setModalState,
    BuildContext modalContext,
  ) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final notificationId = notification['id']?.toString();
    if (uid == null || notificationId == null || notificationId.isEmpty) {
      return;
    }

    await _db.child('notifications/$uid/$notificationId').remove();

    if (_buzzingNotificationId == notificationId) {
      await _stopBuzzing();
    }

    if (!mounted || !modalContext.mounted) return;
    setModalState(() {
      _notifications.removeWhere((item) => item['id'] == notificationId);
      _notificationCount =
          _notifications.where((item) => item['status'] != 'read').length;
    });
    setState(() {});
  }

  double? _notificationDistanceKm(Map<String, dynamic> notification) {
    final value = notification['distanceKm'];
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim());
    return null;
  }

  String? _distanceLabel(double? distanceKm) {
    if (distanceKm == null || !distanceKm.isFinite) return null;
    return '${distanceKm.toStringAsFixed(1)} km away';
  }

  Future<void> _openNotificationAlert(
    Map<String, dynamic> notification,
    bool isUnread,
    StateSetter setModalState,
    BuildContext modalContext,
  ) async {
    final alertId = notification['alertId']?.toString();
    if (alertId == null || alertId.isEmpty) return;

    if (isUnread) {
      await _markNotificationAsRead(notification, setModalState, modalContext);
    } else if (_buzzingNotificationId == notification['id']) {
      await _stopBuzzing();
    }

    if (!mounted || !modalContext.mounted) return;
    Navigator.pop(modalContext);
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AlertDetailScreen(alertId: alertId)),
    );
  }

  // Help Request Item
  Widget _buildHelpRequestItem(Map<String, dynamic> n, bool isUnread,
      StateSetter setModalState, BuildContext context) {
    final t = context.appTheme;
    final isBuzzingForThis = _isBuzzing && _buzzingNotificationId == n['id'];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: t.blueLt,
          border: Border.all(color: t.blue.withOpacity(0.3)),
          borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.help_outline, color: t.blue, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(n['message'] ?? 'Help request',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: t.text)),
                    const SizedBox(height: 4),
                    Text(n['alertDescription'] ?? context.tr('Action required'),
                        style: TextStyle(color: t.muted, fontSize: 13)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.access_time, size: 14, color: t.muted),
                        const SizedBox(width: 4),
                        Text(
                            _formatTimestamp(DateTime.parse(n['timestamp'] ??
                                DateTime.now().toIso8601String())),
                            style: TextStyle(color: t.muted, fontSize: 12)),
                        if (isBuzzingForThis) ...[
                          const SizedBox(width: 12),
                          Icon(Icons.vibration, size: 14, color: t.red),
                          const SizedBox(width: 4),
                          Text(context.tr('Phone is buzzing'),
                              style: TextStyle(
                                  fontSize: 11,
                                  color: t.red,
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
                    decoration:
                        BoxDecoration(color: t.red, shape: BoxShape.circle)),
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
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(context.tr('Help request accepted')),
                        backgroundColor: Colors.green));
                  }
                },
                icon: Icon(Icons.check, size: 16, color: t.green),
                label: Text(context.tr('Accept'), style: TextStyle(color: t.green)),
                style: OutlinedButton.styleFrom(
                    side: BorderSide(color: t.green),
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
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(context.tr('Help request refused')),
                        backgroundColor: Colors.orange));
                  }
                },
                icon: Icon(Icons.close, size: 16, color: t.red),
                label: Text(context.tr('Decline'), style: TextStyle(color: t.red)),
                style: OutlinedButton.styleFrom(
                    side: BorderSide(color: t.red),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8))),
              ),
              if (isBuzzingForThis) ...[
                const SizedBox(width: 8),
                _buildStopBuzzingButton(setModalState),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ── Assistance Request Item ──
  Widget _buildAssistanceRequestItem(Map<String, dynamic> n, bool isUnread,
      StateSetter setModalState, BuildContext context) {
    final t = context.appTheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: t.orangeLt,
          border: Border.all(color: t.orange.withOpacity(0.3)),
          borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.group_add, color: t.orange, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(n['message'] ?? 'Assistance request',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: t.text)),
                    const SizedBox(height: 4),
                    Text(n['alertDescription'] ?? '',
                        style: TextStyle(color: t.muted, fontSize: 13)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.access_time, size: 14, color: t.muted),
                        const SizedBox(width: 4),
                        Text(
                            _formatTimestamp(DateTime.parse(n['timestamp'] ??
                                DateTime.now().toIso8601String())),
                            style: TextStyle(color: t.muted, fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              ),
              if (isUnread)
                Container(
                    width: 10,
                    height: 10,
                    decoration:
                        BoxDecoration(color: t.red, shape: BoxShape.circle)),
            ],
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () async {
              final supervisors = await AuthService().getActiveSupervisors();
              if (supervisors.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content:
                        Text(context.tr('No active supervisors available'))));
                return;
              }
              showDialog(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: Text(context.tr('Assign Assistant')),
                  content: SizedBox(
                    width: 300,
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: supervisors.length,
                      itemBuilder: (_, i) => ListTile(
                        leading: Icon(Icons.person, color: t.navy),
                        title: Text(supervisors[i].fullName),
                        subtitle: Text(supervisors[i].email),
                        onTap: () async {
                          Navigator.pop(dialogContext);
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
                              content: Text(context.tr(
                                  'Assigned {name} as assistant',
                                  {'name': supervisors[i].fullName})),
                              backgroundColor: t.green));
                        },
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: Text(context.tr('Cancel')))
                  ],
                ),
              );
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: t.orange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8))),
            child: Text(context.tr('Assign Assistant'),
                style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  // ── Collaboration Request Item (FULLY COMPLETE) ──
  Widget _buildCollabRequestItem(Map<String, dynamic> n, bool isUnread,
      StateSetter setModalState, BuildContext context) {
    final t = context.appTheme;
    final collabRequestId = n['collabRequestId'] as String?;
    final alertId = n['alertId'] as String?;
    final requesterName = n['requesterName'] as String? ?? 'A supervisor';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: t.card,
          border: Border.all(
              color: isUnread
                  ? const Color(0xFFE9D5FF) // subtle purple accent
                  : t.border),
          borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.people,
                color: isUnread ? const Color(0xFF9333EA) : t.muted, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(n['message'] ?? context.tr('Collaboration request'),
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: t.text)),
                  const SizedBox(height: 4),
                  Text(context.tr('From: {name}', {'name': requesterName}),
                      style: TextStyle(color: t.muted, fontSize: 13)),
                ],
              ),
            ),
            if (isUnread)
              Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                      color: isUnread ? const Color(0xFF9333EA) : t.muted,
                      shape: BoxShape.circle)),
          ]),
          const SizedBox(height: 14),
          // Inline Accept / Decline — keyed on collabRequestId
          if (collabRequestId != null)
            StreamBuilder<CollaborationRequest?>(
              stream: CollaborationService()
                  .getAllCollaborationRequests()
                  .map((list) {
                try {
                  return list.firstWhere((r) => r.id == collabRequestId);
                } catch (_) {
                  return null;
                }
              }),
              builder: (context, snap) {
                final req = snap.data;
                final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
                final myDecision = req?.assistantDecisions[uid];
                final decided =
                    myDecision == 'accepted' || myDecision == 'refused';

                if (req == null) {
                  return Text(context.tr('Loading…'),
                      style: TextStyle(color: t.muted, fontSize: 12));
                }
                if (decided) {
                  final accepted = myDecision == 'accepted';
                  return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: accepted
                          ? const Color(0xFF16A34A).withValues(alpha: 0.1)
                          : Colors.red.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(children: [
                      Icon(accepted ? Icons.check_circle : Icons.cancel,
                          size: 16,
                          color:
                              accepted ? const Color(0xFF16A34A) : Colors.red),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                            accepted
                                ? context.tr('You accepted — waiting for PM approval')
                                : context.tr('You declined this request'),
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: accepted
                                    ? const Color(0xFF16A34A)
                                    : Colors.red)),
                      ),
                    ]),
                  );
                }

                // Still pending — show accept/decline
                return Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final name = FirebaseAuth.instance.currentUser?.email
                                ?.split('@')
                                .first ??
                            'Supervisor';
                        try {
                          await CollaborationService()
                              .respondToCollaborationRequest(
                            requestId: collabRequestId,
                            responderId: uid,
                            responderName: name,
                            accepted: false,
                          );
                          if (alertId != null) {
                            await _db
                                .child(
                                    'notifications/${FirebaseAuth.instance.currentUser!.uid}/${n['id']}')
                                .remove();
                          }
                          if (context.mounted) {
                            setModalState(() {
                              _notifications
                                  .removeWhere((x) => x['id'] == n['id']);
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text(
                                        context.tr('Collaboration declined')),
                                    backgroundColor: Colors.red));
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text(UserFriendlyError.message(e))));
                          }
                        }
                      },
                      icon:
                          const Icon(Icons.close, size: 16, color: Colors.red),
                      label: Text(context.tr('Decline'),
                          style: const TextStyle(
                              color: Colors.red, fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8))),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final name = FirebaseAuth.instance.currentUser?.email
                                ?.split('@')
                                .first ??
                            'Supervisor';
                        try {
                          await CollaborationService()
                              .respondToCollaborationRequest(
                            requestId: collabRequestId,
                            responderId: uid,
                            responderName: name,
                            accepted: true,
                          );
                          if (alertId != null) {
                            await _db
                                .child(
                                    'notifications/${FirebaseAuth.instance.currentUser!.uid}/${n['id']}')
                                .remove();
                          }
                          if (context.mounted) {
                            setModalState(() {
                              _notifications
                                  .removeWhere((x) => x['id'] == n['id']);
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text(context.tr(
                                        'Collaboration accepted! Waiting for PM.')),
                                    backgroundColor: const Color(0xFF16A34A)));
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text(UserFriendlyError.message(e))));
                          }
                        }
                      },
                      icon: const Icon(Icons.check_circle,
                          size: 16, color: Colors.white),
                      label: Text(context.tr('Accept'),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF16A34A),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8))),
                    ),
                  ),
                ]);
              },
            ),
          if (isUnread) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  await _markNotificationAsRead(n, setModalState, context);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(context
                            .tr('Collaboration request marked as read')),
                        backgroundColor: t.green,
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.done_all_rounded, size: 16),
                label: const Text(
                  'Mark as read',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF9333EA),
                  backgroundColor:
                      const Color(0xFF9333EA).withValues(alpha: 0.06),
                  side: BorderSide(
                    color: const Color(0xFF9333EA).withValues(alpha: 0.35),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Default Notification Item ──
  Widget _buildCrossFactoryTransferItem(Map<String, dynamic> n, bool isUnread,
      StateSetter setModalState, BuildContext context) {
    final t = context.appTheme;
    final isBuzzingForThis = _isBuzzing && _buzzingNotificationId == n['id'];
    final distanceLabel = _distanceLabel(_notificationDistanceKm(n));
    final alertId = n['alertId']?.toString();
    final canOpenAlert = alertId != null && alertId.isNotEmpty;
    final accent = t.purple;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: t.orangeLt,
        border: Border.all(
          color: isUnread
              ? accent.withValues(alpha: 0.40)
              : accent.withValues(alpha: 0.20),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: canOpenAlert
              ? () =>
                  _openNotificationAlert(n, isUnread, setModalState, context)
              : null,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.swap_horiz, color: accent, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Cross-factory Transfer',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: t.text,
                                  ),
                                ),
                              ),
                              if (isUnread)
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: accent,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            n['message'] ??
                                'Transfer required for a critical alert',
                            style: TextStyle(
                              color: t.text,
                              fontSize: 13,
                              height: 1.35,
                            ),
                          ),
                          if (distanceLabel != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              distanceLabel,
                              style: TextStyle(color: t.muted, fontSize: 12),
                            ),
                          ],
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: accent.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: accent.withValues(alpha: 0.24),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.alt_route,
                                      size: 14,
                                      color: accent,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Urgent transfer',
                                      style: TextStyle(
                                        color: accent,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (distanceLabel != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: t.orange.withValues(alpha: 0.10),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: t.orange.withValues(alpha: 0.28),
                                    ),
                                  ),
                                  child: Text(
                                    distanceLabel,
                                    style: TextStyle(
                                      color: t.orange,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.access_time,
                                    size: 14,
                                    color: t.muted,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _formatTimestamp(
                                      DateTime.parse(
                                        n['timestamp'] ??
                                            DateTime.now().toIso8601String(),
                                      ),
                                    ),
                                    style: TextStyle(
                                      color: t.muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                              if (isBuzzingForThis)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.vibration,
                                      size: 14,
                                      color: t.red,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Phone is buzzing',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: t.red,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      onPressed: canOpenAlert
                          ? () => _openNotificationAlert(
                              n, isUnread, setModalState, context)
                          : null,
                      icon: const Icon(Icons.open_in_new, size: 16),
                      label: const Text(
                        'Open alert',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    if (isUnread)
                      OutlinedButton.icon(
                        onPressed: () async {
                          await _markNotificationAsRead(
                              n, setModalState, context);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text(
                                  'Cross-factory transfer marked as read',
                                ),
                                backgroundColor: t.green,
                              ),
                            );
                          }
                        },
                        icon: Icon(
                          Icons.done_all_rounded,
                          size: 16,
                          color: accent,
                        ),
                        label: Text(
                          'Mark as read',
                          style: TextStyle(
                            color: accent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: accent.withValues(alpha: 0.35),
                          ),
                          backgroundColor: accent.withValues(alpha: 0.06),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    if (isBuzzingForThis)
                      _buildStopBuzzingButton(setModalState),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDefaultNotificationItem(Map<String, dynamic> n, bool isUnread,
      StateSetter setModalState, BuildContext context) {
    final t = context.appTheme;
    final isBuzzingForThis = _isBuzzing && _buzzingNotificationId == n['id'];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: t.card,
          border: Border.all(color: t.border),
          borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(n['message'] ?? context.tr('Notification'),
                style: TextStyle(fontWeight: FontWeight.bold, color: t.text)),
            subtitle: Text(n['alertDescription'] ?? '',
                style: TextStyle(color: t.muted)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isUnread)
                  IconButton(
                    icon: Icon(Icons.visibility, size: 18, color: t.blue),
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
                  icon: Icon(Icons.open_in_new, size: 18, color: t.navy),
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
                        builder: (_) =>
                            AlertDetailScreen(alertId: n['alertId'])));
              }
            },
          ),
          if (isBuzzingForThis) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: _buildStopBuzzingButton(setModalState),
            ),
          ],
        ],
      ),
    );
  }

  // ── PM Action Item ──
  Widget _buildPmActionItem(Map<String, dynamic> action, bool isUnread,
      StateSetter setModalState, BuildContext context) {
    final t = context.appTheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: t.greenLt,
          border: Border.all(color: t.green.withOpacity(0.3)),
          borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.assignment_turned_in, color: t.green, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(action['title'] ?? context.tr('PM Action'),
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: t.text)),
                    const SizedBox(height: 4),
                    Text(action['description'] ?? '',
                        style: TextStyle(color: t.muted, fontSize: 13)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.access_time, size: 14, color: t.muted),
                        const SizedBox(width: 4),
                        Text(
                            _formatTimestamp(DateTime.parse(
                                action['timestamp'] ??
                                    DateTime.now().toIso8601String())),
                            style: TextStyle(color: t.muted, fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              ),
              if (isUnread)
                Container(
                    width: 10,
                    height: 10,
                    decoration:
                        BoxDecoration(color: t.red, shape: BoxShape.circle)),
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
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(context.tr('PM action marked as read')),
                    backgroundColor: Colors.green));
              }
            },
            icon: Icon(Icons.check_circle_outline, size: 16, color: t.text),
            label: Text(context.tr('Mark as read'), style: TextStyle(color: t.text)),
            style: OutlinedButton.styleFrom(
                backgroundColor: Colors.transparent,
                side: BorderSide(color: t.border),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8))),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Container(
      decoration: BoxDecoration(
          color: t.card,
          border: Border(bottom: BorderSide(color: t.border, width: 1))),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: [
        DashboardUserInfo(
          title: context.tr('Supervisor'),
          subtitle: widget.userName,
          trailingIcon: Icons.warning,
        ),
        const Spacer(),
        LanguageToggle(color: t.navy),
        DashboardThemeToggleButton(color: t.navy),
        DashboardNotificationBell(
          count: _notificationCount,
          onPressed: _showNotifications,
          color: t.navy,
          iconSize: 28,
        ),
        const SizedBox(width: 4),
        // Logout
        InkWell(
          onTap: widget.onLogout,
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
                border: Border.all(color: t.red),
                borderRadius: BorderRadius.circular(8)),
            child: Icon(Icons.logout, size: 20, color: t.red),
          ),
        ),
      ]),
    );
  }
}

// ---------- SUMMARY CARD ----------
