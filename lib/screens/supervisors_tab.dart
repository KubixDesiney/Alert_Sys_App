// ignore_for_file: deprecated_member_use, prefer_const_constructors, prefer_const_declarations, unused_element, unused_element_parameter, use_build_context_synchronously, use_key_in_widget_constructors

import 'dart:async';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shimmer/shimmer.dart';

import '../../models/alert_model.dart';
import '../../models/hierarchy_model.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/service_locator.dart';
import '../../theme.dart';
import '../../utils/alert_meta.dart';
import '../../utils/user_friendly_error.dart';
import '../../widgets/common/app_loading_indicator.dart';
import 'admin/admin_dashboard_shared.dart';
import 'admin_escalation_screen.dart' show CollaborationsTab;

part 'supervisors_tab_charts.dart';
part 'supervisors_tab_charts2.dart';
part 'supervisors_tab_performance.dart';
part 'supervisors_tab_assignments.dart';

Color get _navy => adminNavy;
Color get _navyLt => adminNavyLt;
const _red = adminRed;
const _white = adminWhite;
const _border = adminBorder;
const _muted = adminMuted;
const _text = adminText;
const _green = adminGreen;
const _orange = adminOrange;
const _blue = adminBlue;

Color _typeColor(String type) =>
    typeMeta(type, const AppTheme(isDark: false)).color;
String _typeLabel(String type) =>
    typeMeta(type, const AppTheme(isDark: false)).label;
String _fmtMin(int min) => formatAdminMinutes(min);
String _fmtDate(DateTime d) => formatAdminDate(d);
String _initials(UserModel sup) {
  final first = sup.firstName.trim();
  final last = sup.lastName.trim();
  final letters = [
    if (first.isNotEmpty) first[0],
    if (last.isNotEmpty) last[0],
  ].join();
  if (letters.isNotEmpty) return letters.toUpperCase();
  return sup.fullName.trim().isEmpty
      ? 'S'
      : sup.fullName.trim()[0].toUpperCase();
}

// SUPERVISORS TAB (unchanged from original – keep as is)
// ═══════════════════════════════════════════════════════════════════════════
class AdminSupervisorsTab extends StatefulWidget {
  final List<UserModel> supervisors;
  final List<AlertModel> alerts;
  final VoidCallback onAdd;
  final void Function(UserModel) onDelete;
  final Future<void> Function() onRefresh;
  const AdminSupervisorsTab({
    required this.supervisors,
    required this.alerts,
    required this.onAdd,
    required this.onDelete,
    required this.onRefresh,
  });
  @override
  State<AdminSupervisorsTab> createState() => _SupervisorsTabState();
}

class _SupervisorsTabState extends State<AdminSupervisorsTab>
    with SingleTickerProviderStateMixin {
  late TabController _sub;
  final TextEditingController _searchCtrl = TextEditingController();
  final _hierarchyService = ServiceLocator.instance.hierarchyService;
  StreamSubscription<List<Factory>>? _factoriesSubscription;
  List<Factory> _factories = [];
  String _searchQuery = '';
  int _tabIndex = 0;
  int _previousTabIndex = 0;
  late final Stream _pendingCollaborationRequestsStream;

  @override
  void initState() {
    super.initState();
    _sub = TabController(length: 2, vsync: this);
    _sub.addListener(_handleSubTabChanged);
    _pendingCollaborationRequestsStream = ServiceLocator
        .instance
        .collaborationService
        .getPendingCollaborationRequests();
    _loadFactories();
  }

  void _handleSubTabChanged() {
    if (_tabIndex == _sub.index) return;
    setState(() {
      _previousTabIndex = _tabIndex;
      _tabIndex = _sub.index;
    });
  }

  void _loadFactories() {
    _factoriesSubscription?.cancel();
    _factoriesSubscription = _hierarchyService.getFactories().listen((
      factories,
    ) {
      if (!mounted) return;
      setState(() {
        _factories = factories;
      });
    });
  }

  @override
  void dispose() {
    _factoriesSubscription?.cancel();
    _searchCtrl.dispose();
    _sub.removeListener(_handleSubTabChanged);
    _sub.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _searchQuery.trim().toLowerCase();
    final filteredSupervisors = q.isEmpty
        ? widget.supervisors
        : widget.supervisors
              .where((s) => s.fullName.toLowerCase().contains(q))
              .toList();

    return Column(
      children: [
        Container(
          color: context.appTheme.card,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Container(
            decoration: BoxDecoration(
              color: context.appTheme.scaffold,
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.all(3),
            child: Row(
              children: [
                _SubPill(
                  label: 'Management',
                  icon: Icons.people,
                  index: 0,
                  ctrl: _sub,
                ),
                StreamBuilder(
                  stream: _pendingCollaborationRequestsStream,
                  builder: (context, snapshot) {
                    final requests = snapshot.data as List?;
                    return _SubPill(
                      label: 'Collaborations',
                      icon: Icons.shield,
                      index: 1,
                      ctrl: _sub,
                      badgeCount: requests?.length ?? 0,
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        Expanded(child: _buildAnimatedSubTab(filteredSupervisors)),
      ],
    );
  }

  Widget _buildAnimatedSubTab(List<UserModel> filteredSupervisors) {
    final forward = _tabIndex >= _previousTabIndex;
    final children = [
      _ManagementSubTab(
        key: const ValueKey('management'),
        supervisors: filteredSupervisors,
        allSupervisors: widget.supervisors,
        totalSupervisors: widget.supervisors.length,
        alerts: widget.alerts,
        factories: _factories,
        onAdd: widget.onAdd,
        onDelete: widget.onDelete,
        onRefresh: widget.onRefresh,
        searchCtrl: _searchCtrl,
        searchQuery: _searchQuery,
        onSearchChanged: (v) => setState(() => _searchQuery = v),
      ),
      const KeyedSubtree(
        key: ValueKey('collaborations'),
        child: CollaborationsTab(),
      ),
    ];

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 330),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final offset = Tween<Offset>(
          begin: Offset(forward ? 0.035 : -0.035, 0),
          end: Offset.zero,
        ).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: offset, child: child),
        );
      },
      child: children[_tabIndex],
    );
  }
}

class _SubPill extends StatefulWidget {
  final String label;
  final IconData icon;
  final int index;
  final TabController ctrl;
  final int badgeCount;
  const _SubPill({
    required this.label,
    required this.icon,
    required this.index,
    required this.ctrl,
    this.badgeCount = 0,
  });
  @override
  State<_SubPill> createState() => _SubPillState();
}

class _SubPillState extends State<_SubPill> {
  @override
  void initState() {
    super.initState();
    widget.ctrl.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final sel = widget.ctrl.index == widget.index;
    return Expanded(
      child: GestureDetector(
        onTap: () => widget.ctrl.animateTo(widget.index),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                color: sel ? context.appTheme.card : Colors.transparent,
                borderRadius: BorderRadius.circular(17),
                boxShadow: sel
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: .10),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ]
                    : [],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(widget.icon, size: 14, color: sel ? _navy : _muted),
                  const SizedBox(width: 5),
                  Text(
                    widget.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: sel ? _navy : _muted,
                    ),
                  ),
                ],
              ),
            ),
            if (widget.badgeCount > 0)
              Positioned(
                top: -8,
                right: 14,
                child: _SubPillBadge(count: widget.badgeCount),
              ),
          ],
        ),
      ),
    );
  }
}

class _SubPillBadge extends StatelessWidget {
  final int count;

  const _SubPillBadge({required this.count});

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
        border: Border.all(color: t.scaffold, width: 2),
        boxShadow: [
          BoxShadow(
            color: t.red.withValues(alpha: 0.24),
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

class _ManagementSubTab extends StatefulWidget {
  final List<UserModel> supervisors;
  final List<UserModel> allSupervisors;
  final int totalSupervisors;
  final List<AlertModel> alerts;
  final List<Factory> factories;
  final VoidCallback onAdd;
  final void Function(UserModel) onDelete;
  final Future<void> Function() onRefresh;
  final TextEditingController searchCtrl;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  const _ManagementSubTab({
    super.key,
    required this.supervisors,
    required this.allSupervisors,
    required this.alerts,
    required this.factories,
    required this.onAdd,
    required this.onDelete,
    required this.onRefresh,
    required this.totalSupervisors,
    required this.searchCtrl,
    required this.searchQuery,
    required this.onSearchChanged,
  });

  @override
  State<_ManagementSubTab> createState() => _ManagementSubTabState();
}

class _ManagementSubTabState extends State<_ManagementSubTab>
    with TickerProviderStateMixin {
  String? _selectedId;
  String _chartRange = '7days';
  bool _performancePanelOpen = false;
  OverlayEntry? _performanceOverlayEntry;
  Offset? _performancePanelOffset;
  double _performancePanelWidth = 460;
  double _performancePanelHeight = 620;
  late final AnimationController _liveActivityController;

  static const double _panelMinWidth = 340;
  static const double _panelMinHeight = 360;

  @override
  void initState() {
    super.initState();
    _liveActivityController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    _syncSelection();
  }

  @override
  void dispose() {
    _removePerformanceOverlay();
    _liveActivityController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _ManagementSubTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncSelection();
    _showOrRefreshPerformanceOverlay();
  }

  void _syncSelection() {
    if (widget.allSupervisors.isEmpty) {
      _selectedId = null;
      _performancePanelOpen = false;
      _removePerformanceOverlay();
      return;
    }
    final exists = widget.allSupervisors.any((s) => s.id == _selectedId);
    if (!exists) {
      _selectedId = widget.supervisors.isNotEmpty
          ? widget.supervisors.first.id
          : widget.allSupervisors.first.id;
    }
  }

  UserModel? get _selectedSupervisor {
    if (_selectedId == null) return null;
    for (final sup in widget.allSupervisors) {
      if (sup.id == _selectedId) return sup;
    }
    return null;
  }

  void _openPerformancePanel(UserModel sup) {
    HapticFeedback.selectionClick();
    setState(() {
      _selectedId = sup.id;
      _performancePanelOpen = true;
    });
    _showOrRefreshPerformanceOverlay();
  }

  void _closePerformancePanel() {
    setState(() {
      _performancePanelOpen = false;
    });
    _removePerformanceOverlay();
  }

  void _showOrRefreshPerformanceOverlay() {
    if (!_performancePanelOpen || _selectedSupervisor == null) {
      _removePerformanceOverlay();
      return;
    }
    if (_performanceOverlayEntry == null) {
      final overlay = Overlay.of(context, rootOverlay: true);
      _performanceOverlayEntry = OverlayEntry(
        builder: (overlayContext) =>
            _buildGlobalPerformancePanel(overlayContext, _selectedSupervisor!),
      );
      overlay.insert(_performanceOverlayEntry!);
      return;
    }
    _performanceOverlayEntry!.markNeedsBuild();
  }

  void _refreshPerformanceOverlay() {
    _performanceOverlayEntry?.markNeedsBuild();
  }

  void _setChartRange(String range) {
    if (_chartRange == range) return;
    setState(() => _chartRange = range);
    _refreshPerformanceOverlay();
  }

  void _removePerformanceOverlay() {
    _performanceOverlayEntry?.remove();
    _performanceOverlayEntry = null;
  }

  double _clampPanelValue(double value, double min, double max) {
    if (max < min) return min;
    return value.clamp(min, max).toDouble();
  }

  Offset _resolvedPanelOffset({
    required Size bounds,
    required Size panelSize,
    required Offset fallback,
  }) {
    final raw = _performancePanelOffset ?? fallback;
    return Offset(
      _clampPanelValue(raw.dx, 8, bounds.width - panelSize.width - 8),
      _clampPanelValue(raw.dy, 8, bounds.height - panelSize.height - 8),
    );
  }

  void _movePerformancePanel({
    required Offset delta,
    required Size bounds,
    required Size panelSize,
    required Offset fallback,
  }) {
    final current = _resolvedPanelOffset(
      bounds: bounds,
      panelSize: panelSize,
      fallback: fallback,
    );
    setState(() {
      _performancePanelOffset = Offset(
        _clampPanelValue(
          current.dx + delta.dx,
          8,
          bounds.width - panelSize.width - 8,
        ),
        _clampPanelValue(
          current.dy + delta.dy,
          8,
          bounds.height - panelSize.height - 8,
        ),
      );
    });
    _refreshPerformanceOverlay();
  }

  void _resizePerformancePanel({
    required Offset delta,
    required Size bounds,
    required Offset fallback,
  }) {
    setState(() {
      final availableWidth = math.max(280.0, bounds.width - 16);
      final availableHeight = math.max(320.0, bounds.height - 16);
      final minWidth = math.min(_panelMinWidth, availableWidth);
      final minHeight = math.min(_panelMinHeight, availableHeight);
      _performancePanelWidth = _clampPanelValue(
        _performancePanelWidth + delta.dx,
        minWidth,
        availableWidth,
      );
      _performancePanelHeight = _clampPanelValue(
        _performancePanelHeight + delta.dy,
        minHeight,
        availableHeight,
      );
      final panelSize = Size(_performancePanelWidth, _performancePanelHeight);
      _performancePanelOffset = _resolvedPanelOffset(
        bounds: bounds,
        panelSize: panelSize,
        fallback: fallback,
      );
    });
    _refreshPerformanceOverlay();
  }

  void _togglePerformancePanelSize(Size bounds, Offset fallback) {
    final expanded = _performancePanelWidth > 560;
    setState(() {
      final availableWidth = math.max(280.0, bounds.width - 16);
      final availableHeight = math.max(320.0, bounds.height - 16);
      final minWidth = math.min(_panelMinWidth, availableWidth);
      final minHeight = math.min(_panelMinHeight, availableHeight);
      _performancePanelWidth = expanded
          ? _clampPanelValue(460, minWidth, availableWidth)
          : _clampPanelValue(760, minWidth, availableWidth);
      _performancePanelHeight = expanded
          ? _clampPanelValue(620, minHeight, availableHeight)
          : _clampPanelValue(760, minHeight, availableHeight);
      final panelSize = Size(_performancePanelWidth, _performancePanelHeight);
      _performancePanelOffset = _resolvedPanelOffset(
        bounds: bounds,
        panelSize: panelSize,
        fallback: fallback,
      );
    });
    _refreshPerformanceOverlay();
  }

  List<AlertModel> _alertsFor(UserModel sup) => widget.alerts
      .where(
        (a) =>
            a.superviseurId == sup.id ||
            a.assistantId == sup.id ||
            a.assistedBySupervisorId == sup.id,
      )
      .toList();

  List<AlertModel> _solvedFor(UserModel sup) =>
      _alertsFor(sup).where((a) => a.status == 'validee').toList();

  int _claimedFor(UserModel sup) => widget.alerts
      .where((a) => a.status == 'en_cours' && a.superviseurId == sup.id)
      .length;

  int? _avgMinFor(List<AlertModel> solved) {
    final timed = solved.where((a) => a.elapsedTime != null).toList();
    if (timed.isEmpty) return null;
    return timed.fold(0, (sum, a) => sum + (a.elapsedTime ?? 0)) ~/
        timed.length;
  }

  int _impactScore(UserModel sup) {
    final solved = _solvedFor(sup);
    final avg = _avgMinFor(solved);
    final speedWindow = avg == null ? 0 : (120 - avg).clamp(0, 120).toInt();
    final aiWins = _alertsFor(sup).where((a) => a.aiAssigned).length;
    return solved.length * 8 +
        _claimedFor(sup) * 5 +
        aiWins * 3 +
        speedWindow ~/ 6;
  }

  int _rankFor(UserModel sup) {
    final ranked = [...widget.allSupervisors]
      ..sort((a, b) {
        final score = _impactScore(b).compareTo(_impactScore(a));
        if (score != 0) return score;
        return _solvedFor(b).length.compareTo(_solvedFor(a).length);
      });
    final index = ranked.indexWhere((s) => s.id == sup.id);
    return index < 0 ? ranked.length : index + 1;
  }

  double _validationRate(UserModel sup) {
    final all = _alertsFor(sup);
    if (all.isEmpty) return 0;
    return _solvedFor(sup).length / all.length;
  }

  List<_ChartPoint> _buildChartPoints(UserModel sup) {
    final days = _chartRange == '7days' ? 7 : 30;
    final solved = _solvedFor(sup);
    final now = DateTime.now();
    return List.generate(days, (i) {
      final day = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: days - 1 - i));
      final next = day.add(const Duration(days: 1));
      final count = solved
          .where((a) => a.timestamp.isAfter(day) && a.timestamp.isBefore(next))
          .length;
      return _ChartPoint(day: day, value: count.toDouble());
    });
  }

  List<int> _resolvedSpark(UserModel sup, {int days = 7}) {
    final solved = _solvedFor(sup);
    final now = DateTime.now();
    return List.generate(days, (i) {
      final day = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: days - 1 - i));
      final next = day.add(const Duration(days: 1));
      return solved
          .where((a) => a.timestamp.isAfter(day) && a.timestamp.isBefore(next))
          .length;
    });
  }

  List<int> _teamResolvedWeek() {
    final solved = widget.alerts.where((a) => a.status == 'validee').toList();
    final now = DateTime.now();
    return List.generate(7, (i) {
      final day = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: 6 - i));
      final next = day.add(const Duration(days: 1));
      return solved
          .where((a) => a.timestamp.isAfter(day) && a.timestamp.isBefore(next))
          .length;
    });
  }

  Map<String, int> _teamTypeDistribution() {
    final map = <String, int>{};
    for (final alert in widget.alerts) {
      final involved =
          alert.superviseurId != null ||
          alert.assistantId != null ||
          alert.assistedBySupervisorId != null;
      if (!involved) continue;
      map[alert.type] = (map[alert.type] ?? 0) + 1;
    }
    return map;
  }

  List<_LeaderboardEntry> _leaderboard() {
    final entries =
        widget.allSupervisors
            .map(
              (sup) =>
                  _LeaderboardEntry(supervisor: sup, score: _impactScore(sup)),
            )
            .toList()
          ..sort((a, b) => b.score.compareTo(a.score));
    return entries.take(5).toList();
  }

  Map<String, List<_FactoryWorkloadSegment>> _factoryWorkload() {
    final result = <String, List<_FactoryWorkloadSegment>>{};
    final factories = <String>{
      ...widget.factories.map((f) => f.name),
      ...widget.alerts.map((a) => a.usine),
    }..removeWhere((name) => name.trim().isEmpty);

    for (final factory in factories) {
      final segments = <_FactoryWorkloadSegment>[];
      for (final sup in widget.allSupervisors) {
        final count = widget.alerts
            .where(
              (a) =>
                  a.usine == factory &&
                  (a.superviseurId == sup.id || a.assistantId == sup.id),
            )
            .length;
        if (count == 0) continue;
        segments.add(_FactoryWorkloadSegment(supervisor: sup, count: count));
      }
      segments.sort((a, b) => b.count.compareTo(a.count));
      result[factory] = segments.take(5).toList();
    }
    return result;
  }

  List<double> _activityPulseSamples() {
    final now = DateTime.now();
    return List.generate(24, (i) {
      final end = now.subtract(Duration(seconds: (23 - i) * 3));
      final start = end.subtract(const Duration(seconds: 3));
      final count = widget.alerts
          .where((a) => a.timestamp.isAfter(start) && a.timestamp.isBefore(end))
          .length;
      final heartbeat = math.sin((i / 23) * math.pi * 4) * 0.35 + 0.45;
      return count + heartbeat;
    });
  }

  Future<void> _refreshManagement() async {
    HapticFeedback.selectionClick();
    await widget.onRefresh();
  }

  Map<String, int> _factoryDist(UserModel sup) {
    final map = <String, int>{};
    for (final alert in _solvedFor(sup)) {
      map[alert.usine] = (map[alert.usine] ?? 0) + 1;
    }
    return map;
  }

  Map<String, _TypeStats> _typeStats(UserModel sup) {
    final involved = _alertsFor(sup);
    final types = <String>{
      'qualite',
      'maintenance',
      'defaut_produit',
      'manque_ressource',
      ...involved.map((a) => a.type),
    }.toList();
    return {
      for (final type in types)
        type: _TypeStats(
          validated: involved
              .where((a) => a.type == type && a.status == 'validee')
              .length,
          notValidated: involved
              .where((a) => a.type == type && a.status != 'validee')
              .length,
        ),
    };
  }

  Map<String, List<UserModel>> _groupByFactory() {
    final map = <String, List<UserModel>>{};
    for (final factory in widget.factories) {
      map[factory.name] =
          widget.allSupervisors.where((s) => s.usine == factory.name).toList()
            ..sort((a, b) => a.fullName.compareTo(b.fullName));
    }
    return map;
  }

  List<UserModel> _unassigned() {
    final factoryNames = widget.factories.map((f) => f.name).toSet();
    return widget.allSupervisors
        .where((s) => s.usine.isEmpty || !factoryNames.contains(s.usine))
        .toList()
      ..sort((a, b) => a.fullName.compareTo(b.fullName));
  }

  String? _locationFor(String factoryName) {
    for (final factory in widget.factories) {
      if (factory.name == factoryName) return factory.location;
    }
    return null;
  }

  Future<void> _reassign(UserModel sup, String newFactory) async {
    if (sup.usine == newFactory) return;
    try {
      await AuthService().updateSupervisorProfile(
        userId: sup.id,
        firstName: sup.firstName,
        lastName: sup.lastName,
        email: sup.email,
        phone: sup.phone,
        usine: newFactory,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newFactory.isEmpty
                ? '${sup.fullName} unassigned'
                : '${sup.fullName} moved to $newFactory',
          ),
          backgroundColor: context.appTheme.green,
        ),
      );
      await widget.onRefresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Update failed: ${UserFriendlyError.message(e)}'),
        ),
      );
    }
  }

  Future<void> _showDeleteConfirmDialog(UserModel sup) async {
    return showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: context.appTheme.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: _red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.warning_outlined, color: _red, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Delete Supervisor',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: context.appTheme.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sup.fullName,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _red,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: Text(
          'This permanently removes ${sup.fullName} from ${sup.usine.isEmpty ? 'the roster' : sup.usine}.',
          style: TextStyle(fontSize: 13, color: context.appTheme.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(dialogCtx);
              widget.onDelete(sup);
            },
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Delete'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _red,
              foregroundColor: _white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showModifyDialog(UserModel sup) async {
    final firstCtrl = TextEditingController(text: sup.firstName);
    final lastCtrl = TextEditingController(text: sup.lastName);
    final emailCtrl = TextEditingController(text: sup.email);
    final phoneCtrl = TextEditingController(text: sup.phone);
    final usineChoices = <String>{
      if (sup.usine.isNotEmpty) sup.usine,
      ...widget.factories.map((f) => f.name),
    }.toList()..sort();
    var selectedUsine = sup.usine;
    var saving = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('Modify Supervisor'),
              content: SizedBox(
                width: 380,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SheetLabel('First Name'),
                      TextField(
                        controller: firstCtrl,
                        decoration: const InputDecoration(
                          hintText: 'First name',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SheetLabel('Last Name'),
                      TextField(
                        controller: lastCtrl,
                        decoration: const InputDecoration(
                          hintText: 'Last name',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SheetLabel('Email'),
                      TextField(
                        controller: emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          hintText: 'Email address',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SheetLabel('Phone'),
                      TextField(
                        controller: phoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          hintText: 'Phone number',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SheetLabel('Assigned Plant'),
                      DropdownButtonFormField<String>(
                        value: usineChoices.contains(selectedUsine)
                            ? selectedUsine
                            : null,
                        hint: const Text('Unassigned'),
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: usineChoices
                            .map(
                              (u) => DropdownMenuItem(value: u, child: Text(u)),
                            )
                            .toList(),
                        onChanged: saving
                            ? null
                            : (v) {
                                if (v == null) return;
                                setDialogState(() => selectedUsine = v);
                              },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(dialogCtx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: saving
                      ? null
                      : () async {
                          final first = firstCtrl.text.trim();
                          final last = lastCtrl.text.trim();
                          final email = emailCtrl.text.trim();
                          final phone = phoneCtrl.text.trim();
                          if (first.isEmpty || last.isEmpty || email.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'First name, last name, and email are required',
                                ),
                              ),
                            );
                            return;
                          }
                          if (!email.contains('@')) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Please enter a valid email'),
                              ),
                            );
                            return;
                          }
                          setDialogState(() => saving = true);
                          try {
                            await AuthService().updateSupervisorProfile(
                              userId: sup.id,
                              firstName: first,
                              lastName: last,
                              email: email,
                              phone: phone,
                              usine: selectedUsine,
                            );
                            await widget.onRefresh();
                            if (!mounted) return;
                            Navigator.pop(dialogCtx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Supervisor updated successfully',
                                ),
                                backgroundColor: _green,
                              ),
                            );
                          } catch (e) {
                            if (!mounted) return;
                            setDialogState(() => saving = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Update failed: ${UserFriendlyError.message(e)}',
                                ),
                              ),
                            );
                          }
                        },
                  child: saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save Changes'),
                ),
              ],
            );
          },
        );
      },
    );

    firstCtrl.dispose();
    lastCtrl.dispose();
    emailCtrl.dispose();
    phoneCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final selected = _selectedSupervisor;
    return Column(
      children: [
        _buildCommandHeader(t),
        Expanded(
          child: RefreshIndicator(
            color: t.navy,
            backgroundColor: t.card,
            notificationPredicate: (_) => true,
            onRefresh: _refreshManagement,
            child: widget.totalSupervisors == 0
                ? _emptySups()
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 920;
                      if (compact) {
                        return _buildCompact(t, selected);
                      }
                      return _buildWide(t, selected);
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildCommandHeader(AppTheme t) {
    final active = widget.allSupervisors.where((s) => s.isActive).length;
    final absent = widget.allSupervisors.length - active;
    final assignedPlants = widget.allSupervisors
        .map((s) => s.usine)
        .where((u) => u.isNotEmpty)
        .toSet()
        .length;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: t.isDark ? 0.18 : 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 720;
          final titleBlock = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Supervisors',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: t.text,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'Roster, plant assignments, and on-demand performance.',
                style: TextStyle(
                  fontSize: 12,
                  color: t.muted,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _Chip('$active active', t.green),
                  _Chip('$absent absent', t.orange),
                  _Chip('$assignedPlants plants', t.blue),
                ],
              ),
            ],
          );

          final action = ElevatedButton.icon(
            onPressed: widget.onAdd,
            icon: const Icon(Icons.person_add, size: 17),
            label: const Text(
              'Add Supervisor',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: t.navy,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [titleBlock, const SizedBox(height: 14), action],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: titleBlock),
              const SizedBox(width: 16),
              action,
            ],
          );
        },
      ),
    );
  }

  Widget _buildPerformanceDashboard(AppTheme t) {
    final weekly = _teamResolvedWeek();
    final types = _teamTypeDistribution();
    final leaderboard = _leaderboard();
    final factoryWorkload = _factoryWorkload();
    final hasAnyData =
        widget.allSupervisors.isNotEmpty || widget.alerts.isNotEmpty;

    if (!hasAnyData) {
      return const _DashboardShimmerSkeleton();
    }

    final cards = [
      _SectionShell(
        icon: Icons.stacked_bar_chart,
        title: 'Weekly Team Resolution Heatmap',
        subtitle: 'Total resolved alerts by day',
        child: _WeeklyResolutionHeatmap(values: weekly),
      ),
      _SectionShell(
        icon: Icons.donut_large,
        title: 'Alert Type Distribution',
        subtitle: 'Combined supervisor workload mix',
        child: _AlertTypeDonut(distribution: types),
      ),
      _SectionShell(
        icon: Icons.emoji_events_outlined,
        title: 'Supervisor Leaderboard',
        subtitle: 'Top 5 by impact score',
        child: _SupervisorLeaderboardChart(entries: leaderboard),
      ),
      _SectionShell(
        icon: Icons.monitor_heart_outlined,
        title: 'Live Activity Pulse',
        subtitle: 'Rolling alert activity window',
        child: AnimatedBuilder(
          animation: _liveActivityController,
          builder: (context, _) => _LiveActivityPulseChart(
            samples: _activityPulseSamples(),
            progress: _liveActivityController.value,
          ),
        ),
      ),
      _SectionShell(
        icon: Icons.factory_outlined,
        title: 'Factory Workload Map',
        subtitle: 'Supervisor load by factory',
        child: _FactoryWorkloadChart(workload: factoryWorkload),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 1180
            ? 3
            : constraints.maxWidth > 760
            ? 2
            : 1;
        final gap = 12.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: List.generate(cards.length, (index) {
            return SizedBox(
              width: width,
              child: _StaggeredEntrance(
                delay: Duration(milliseconds: 60 * index),
                child: cards[index],
              ),
            );
          }),
        );
      },
    );
  }

  Widget _buildWide(AppTheme t, UserModel? selected) {
    final railWidth = MediaQuery.sizeOf(context).width >= 1600 ? 310.0 : 326.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: railWidth, child: _buildRail(t)),
          const SizedBox(width: 12),
          Expanded(child: _buildDetailScroller(t, selected)),
        ],
      ),
    );
  }

  Widget _buildCompact(AppTheme t, UserModel? selected) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
      child: Column(
        children: [
          _buildRail(t, compact: true),
          const SizedBox(height: 14),
          _buildDetailContent(t, selected),
        ],
      ),
    );
  }

  Widget _buildGlobalPerformancePanel(
    BuildContext overlayContext,
    UserModel sup,
  ) {
    final t = overlayContext.appTheme;
    final bounds = MediaQuery.sizeOf(overlayContext);
    final availableWidth = math.max(280.0, bounds.width - 16);
    final availableHeight = math.max(320.0, bounds.height - 16);
    final minWidth = math.min(_panelMinWidth, availableWidth);
    final minHeight = math.min(_panelMinHeight, availableHeight);
    final width = _clampPanelValue(
      _performancePanelWidth,
      minWidth,
      availableWidth,
    );
    final height = _clampPanelValue(
      _performancePanelHeight,
      minHeight,
      availableHeight,
    );
    final panelSize = Size(width, height);
    final fallback = Offset(
      _clampPanelValue(bounds.width - width - 24, 8, bounds.width - width - 8),
      _clampPanelValue(92, 8, bounds.height - height - 8),
    );
    final offset = _resolvedPanelOffset(
      bounds: bounds,
      panelSize: panelSize,
      fallback: fallback,
    );
    final statusColor = sup.isActive ? t.green : t.red;

    return SizedBox.expand(
      child: Stack(
        children: [
          Positioned(
            left: offset.dx,
            top: offset.dy,
            width: width,
            height: height,
            child: Material(
              color: Colors.transparent,
              elevation: 18,
              borderRadius: BorderRadius.circular(18),
              child: Stack(
                children: [
                  Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: t.card.withValues(alpha: t.isDark ? 0.98 : 0.96),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: t.navy.withValues(alpha: 0.22)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: t.isDark ? 0.42 : 0.18,
                          ),
                          blurRadius: 34,
                          offset: const Offset(0, 18),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanUpdate: (details) => _movePerformancePanel(
                            delta: details.delta,
                            bounds: bounds,
                            panelSize: panelSize,
                            fallback: fallback,
                          ),
                          child: MouseRegion(
                            cursor: SystemMouseCursors.move,
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(
                                14,
                                12,
                                10,
                                12,
                              ),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    t.navy.withValues(
                                      alpha: t.isDark ? 0.32 : 0.10,
                                    ),
                                    t.green.withValues(
                                      alpha: t.isDark ? 0.18 : 0.07,
                                    ),
                                  ],
                                ),
                                border: Border(
                                  bottom: BorderSide(color: t.border),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [t.navy, t.green],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Center(
                                      child: Text(
                                        _initials(sup),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Performance',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 0.5,
                                            color: t.muted,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          sup.fullName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w900,
                                            color: t.text,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            _LivePulseDot(
                                              color: statusColor,
                                              pulse: sup.isActive,
                                            ),
                                            const SizedBox(width: 5),
                                            Expanded(
                                              child: Text(
                                                sup.usine.isEmpty
                                                    ? 'Unassigned'
                                                    : sup.usine,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: t.muted,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  Tooltip(
                                    message: 'Resize panel',
                                    child: Icon(
                                      Icons.drag_indicator,
                                      color: t.muted,
                                      size: 20,
                                    ),
                                  ),
                                  Tooltip(
                                    message: 'Toggle size',
                                    child: IconButton(
                                      onPressed: () =>
                                          _togglePerformancePanelSize(
                                            bounds,
                                            fallback,
                                          ),
                                      icon: Icon(
                                        Icons.open_in_full,
                                        color: t.navy,
                                        size: 18,
                                      ),
                                    ),
                                  ),
                                  Tooltip(
                                    message: 'Close',
                                    child: IconButton(
                                      onPressed: _closePerformancePanel,
                                      icon: Icon(
                                        Icons.close,
                                        color: t.red,
                                        size: 19,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildMetricGrid(t, sup),
                                const SizedBox(height: 12),
                                _buildPerformanceCard(t, sup),
                                const SizedBox(height: 12),
                                _buildTypeBreakdown(t, sup),
                                const SizedBox(height: 12),
                                _buildValidatedList(t, sup),
                                const SizedBox(height: 18),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    right: 2,
                    bottom: 2,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanUpdate: (details) => _resizePerformancePanel(
                        delta: details.delta,
                        bounds: bounds,
                        fallback: fallback,
                      ),
                      child: MouseRegion(
                        cursor: SystemMouseCursors.resizeUpLeftDownRight,
                        child: Container(
                          width: 34,
                          height: 34,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: t.navy.withValues(alpha: 0.10),
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(14),
                              bottomRight: Radius.circular(16),
                            ),
                            border: Border.all(
                              color: t.navy.withValues(alpha: 0.16),
                            ),
                          ),
                          child: Icon(
                            Icons.open_in_full,
                            size: 15,
                            color: t.navy,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRail(AppTheme t, {bool compact = false}) {
    return Container(
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              children: [
                Icon(Icons.manage_accounts_outlined, size: 18, color: t.navy),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Roster',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: t.text,
                    ),
                  ),
                ),
                _Chip('${widget.allSupervisors.length}', t.navy),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: _buildSearchField(t),
          ),
          if (compact)
            SizedBox(height: 154, child: _buildRosterList(t, compact: true))
          else
            Expanded(child: _buildRosterList(t)),
        ],
      ),
    );
  }

  Widget _buildSearchField(AppTheme t) {
    return TextField(
      controller: widget.searchCtrl,
      onChanged: widget.onSearchChanged,
      style: TextStyle(color: t.text, fontSize: 13),
      decoration: InputDecoration(
        hintText: 'Search supervisor',
        hintStyle: TextStyle(color: t.muted),
        prefixIcon: Icon(Icons.search, color: t.muted, size: 18),
        suffixIcon: widget.searchQuery.isEmpty
            ? null
            : IconButton(
                icon: Icon(Icons.close, size: 18, color: t.muted),
                onPressed: () {
                  widget.searchCtrl.clear();
                  widget.onSearchChanged('');
                },
              ),
        filled: true,
        fillColor: t.scaffold,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 11,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: t.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: t.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: t.navy, width: 1.4),
        ),
      ),
    );
  }

  Widget _buildRosterList(AppTheme t, {bool compact = false}) {
    if (widget.supervisors.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Text(
            'No supervisors match "${widget.searchQuery}"',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: t.muted),
          ),
        ),
      );
    }

    if (compact) {
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        scrollDirection: Axis.horizontal,
        itemCount: widget.supervisors.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final sup = widget.supervisors[i];
          return SizedBox(
            width: 260,
            child: _StaggeredEntrance(
              delay: Duration(milliseconds: 55 * i),
              child: _SupervisorRailTile(
                supervisor: sup,
                selected: sup.id == _selectedId,
                solved: _solvedFor(sup).length,
                claimed: _claimedFor(sup),
                spark: _resolvedSpark(sup),
                onTap: () => _openPerformancePanel(sup),
                onEdit: () => _showModifyDialog(sup),
                onDelete: () => _showDeleteConfirmDialog(sup),
              ),
            ),
          );
        },
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      itemCount: widget.supervisors.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final sup = widget.supervisors[i];
        return _StaggeredEntrance(
          delay: Duration(milliseconds: 55 * (i % 8)),
          child: _SupervisorRailTile(
            supervisor: sup,
            selected: sup.id == _selectedId,
            solved: _solvedFor(sup).length,
            claimed: _claimedFor(sup),
            spark: _resolvedSpark(sup),
            onTap: () => _openPerformancePanel(sup),
            onEdit: () => _showModifyDialog(sup),
            onDelete: () => _showDeleteConfirmDialog(sup),
          ),
        );
      },
    );
  }

  Widget _buildDetailScroller(AppTheme t, UserModel? selected) {
    return SingleChildScrollView(child: _buildDetailContent(t, selected));
  }

  Widget _buildDetailContent(AppTheme t, UserModel? selected) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildAssignmentCommandDeck(t, selected),
        const SizedBox(height: 12),
        _buildAssignmentMatrix(t),
      ],
    );
  }

  Widget _buildAssignmentCommandDeck(AppTheme t, UserModel? selected) {
    final grouped = _groupByFactory();
    final unassigned = _unassigned().length;
    final active = widget.allSupervisors.where((s) => s.isActive).length;
    final assigned = math.max(0, widget.allSupervisors.length - unassigned);
    final staffedFactories = grouped.values
        .where((sups) => sups.isNotEmpty)
        .length;

    Widget signal({
      required IconData icon,
      required String label,
      required String value,
      required Color color,
    }) {
      return Container(
        width: 146,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: t.card.withValues(alpha: t.isDark ? 0.54 : 0.82),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.20)),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 17),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: t.text,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, color: t.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.border),
        gradient: LinearGradient(
          colors: [
            t.card,
            t.isDark ? const Color(0xFF12263A) : const Color(0xFFEFF6FF),
            t.isDark ? const Color(0xFF10261B) : const Color(0xFFF0FDF4),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: t.isDark ? 0.20 : 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _CommandGridPainter(
                color: t.navy.withValues(alpha: 0.06),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: t.navy.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(
                          color: t.navy.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Icon(
                        Icons.account_tree_outlined,
                        color: t.navy,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Factory Assignments',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: t.text,
                              height: 1.05,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            'Live supervisor placement by plant.',
                            style: TextStyle(
                              fontSize: 12,
                              color: t.muted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (selected != null && _performancePanelOpen)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        constraints: const BoxConstraints(maxWidth: 230),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: t.navy.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(
                            color: t.navy.withValues(alpha: 0.18),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.analytics_outlined,
                              size: 14,
                              color: t.navy,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                selected.fullName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  color: t.navy,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    signal(
                      icon: Icons.factory_outlined,
                      label: 'plant lanes',
                      value: '${widget.factories.length}',
                      color: t.navy,
                    ),
                    signal(
                      icon: Icons.groups_2_outlined,
                      label: 'assigned',
                      value: '$assigned',
                      color: t.green,
                    ),
                    signal(
                      icon: Icons.pending_actions_outlined,
                      label: 'unassigned',
                      value: '$unassigned',
                      color: t.orange,
                    ),
                    signal(
                      icon: Icons.sensors_outlined,
                      label: 'active',
                      value: '$active',
                      color: t.blue,
                    ),
                    signal(
                      icon: Icons.domain_verification_outlined,
                      label: 'staffed plants',
                      value: '$staffedFactories',
                      color: t.purple,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSupervisorHero(AppTheme t, UserModel sup) {
    final solved = _solvedFor(sup);
    final avg = _avgMinFor(solved);
    final dist = _factoryDist(sup);
    final rank = _rankFor(sup);
    final statusColor = sup.isActive ? t.green : t.red;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: [
            t.card,
            t.isDark ? const Color(0xFF132238) : const Color(0xFFEFF6FF),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: t.border),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _CommandGridPainter(
                color: t.navy.withValues(alpha: 0.06),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [t.navy, t.green],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: t.navy.withValues(alpha: 0.25),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          _initials(sup),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            sup.fullName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: t.text,
                              height: 1.05,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _StatusPill(
                                color: statusColor,
                                label: sup.isActive ? 'Active' : 'Absent',
                                icon: Icons.circle,
                                pulse: sup.isActive,
                              ),
                              _StatusPill(
                                color: t.blue,
                                label: sup.usine.isEmpty
                                    ? 'Unassigned'
                                    : sup.usine,
                                icon: Icons.factory_outlined,
                              ),
                              _AnimatedRankPill(rank: rank, color: t.purple),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => _showModifyDialog(sup),
                      icon: Icon(Icons.edit, color: t.navy),
                      tooltip: 'Modify Supervisor',
                    ),
                    IconButton(
                      onPressed: () => _showDeleteConfirmDialog(sup),
                      icon: Icon(Icons.delete_outline, color: t.red),
                      tooltip: 'Delete Supervisor',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _FloatingHeroSignal(
                      delay: const Duration(milliseconds: 0),
                      child: _HeroSignal(
                        label: 'Resolved',
                        value: '${solved.length}',
                        color: t.green,
                        icon: Icons.check_circle_outline,
                      ),
                    ),
                    _FloatingHeroSignal(
                      delay: const Duration(milliseconds: 90),
                      child: _HeroSignal(
                        label: 'Avg Time',
                        value: avg == null ? '-' : _fmtMin(avg),
                        color: t.orange,
                        icon: Icons.timer_outlined,
                      ),
                    ),
                    if (dist.isNotEmpty)
                      _FloatingHeroSignal(
                        delay: const Duration(milliseconds: 180),
                        child: _HeroSignal(
                          label: 'Top Plant',
                          value: dist.entries
                              .reduce((a, b) => a.value >= b.value ? a : b)
                              .key,
                          color: t.purple,
                          icon: Icons.hub_outlined,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricGrid(AppTheme t, UserModel sup) {
    final solved = _solvedFor(sup);
    final involved = _alertsFor(sup);
    final avg = _avgMinFor(solved);
    final ai = involved.where((a) => a.aiAssigned).length;
    final critical = involved.where((a) => a.isCritical).length;
    final rate = (_validationRate(sup) * 100).round();
    final tiles = [
      _CommandMetric(
        icon: Icons.done_all,
        label: 'Resolved Alerts',
        value: '${solved.length}',
        tone: t.green,
      ),
      _CommandMetric(
        icon: Icons.speed,
        label: 'Average Resolution',
        value: avg == null ? '-' : _fmtMin(avg),
        tone: t.orange,
      ),
      _CommandMetric(
        icon: Icons.verified_outlined,
        label: 'Validation Rate',
        value: '$rate%',
        tone: t.blue,
      ),
      _CommandMetric(
        icon: Icons.psychology_alt_outlined,
        label: 'AI Assigned',
        value: '$ai',
        tone: t.purple,
      ),
      _CommandMetric(
        icon: Icons.warning_amber_rounded,
        label: 'Critical Load',
        value: '$critical',
        tone: t.red,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 980
            ? 5
            : constraints.maxWidth > 720
            ? 3
            : 2;
        final gap = 10.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: tiles
              .map((tile) => SizedBox(width: width, child: tile))
              .toList(),
        );
      },
    );
  }

  Widget _buildPerformanceCard(AppTheme t, UserModel sup) {
    final points = _buildChartPoints(sup);
    final chartTotal = points.fold<double>(0, (sum, p) => sum + p.value);
    final key = ValueKey('${sup.id}-$_chartRange-$chartTotal');

    return _SectionShell(
      icon: Icons.show_chart,
      title: 'Performance Graph',
      subtitle: 'Resolved alerts over time',
      trailing: _RangeToggle(value: _chartRange, onChanged: _setChartRange),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 190,
            child: TweenAnimationBuilder<double>(
              key: key,
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 850),
              curve: Curves.easeOutCubic,
              builder: (context, progress, _) => _LineChart(
                points: points,
                progress: progress,
                color: t.navy,
                fillColor: t.green,
                gridColor: t.border,
                labelColor: t.muted,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(width: 30, height: 3, color: t.navy),
              const SizedBox(width: 7),
              Icon(Icons.circle, size: 8, color: t.green),
              const SizedBox(width: 7),
              Text(
                'Validations',
                style: TextStyle(fontSize: 11, color: t.muted),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTypeBreakdown(AppTheme t, UserModel sup) {
    final stats = _typeStats(sup);
    return _SectionShell(
      icon: Icons.analytics_outlined,
      title: 'Alert Type Breakdown',
      subtitle: 'Validated alerts by class',
      child: _SupervisorTypeDonutChart(stats: stats),
    );
  }

  Widget _buildAssignmentMatrix(AppTheme t) {
    final grouped = _groupByFactory();
    final unassigned = _unassigned();
    final cards = <Widget>[
      ...grouped.entries.map(
        (entry) => _buildFactoryDropCard(
          t,
          factoryName: entry.key,
          location: _locationFor(entry.key),
          supervisors: entry.value,
          accent: t.navy,
          emptyLabel: 'Open slot',
          onAccept: (sup) => _reassign(sup, entry.key),
        ),
      ),
      if (unassigned.isNotEmpty || grouped.isEmpty)
        _buildFactoryDropCard(
          t,
          factoryName: 'Unassigned',
          location: 'Awaiting plant placement',
          supervisors: unassigned,
          accent: t.orange,
          emptyLabel: 'No unassigned supervisors',
          onAccept: (sup) => _reassign(sup, ''),
          accepts: (sup) => sup.usine.isNotEmpty,
          removable: false,
        ),
    ];

    return _SectionShell(
      icon: Icons.account_tree_outlined,
      title: 'Assignment Board',
      subtitle: 'Roster source, factory lanes, and unassigned pool',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth > 980
              ? 3
              : constraints.maxWidth > 640
              ? 2
              : 1;
          final gap = 12.0;
          final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: cards
                .map((card) => SizedBox(width: width, child: card))
                .toList(),
          );
        },
      ),
    );
  }

  Widget _buildFactoryDropCard(
    AppTheme t, {
    required String factoryName,
    required String? location,
    required List<UserModel> supervisors,
    required Color accent,
    required String emptyLabel,
    required ValueChanged<UserModel> onAccept,
    bool Function(UserModel sup)? accepts,
    bool removable = true,
  }) {
    return DragTarget<UserModel>(
      onWillAcceptWithDetails: (details) =>
          accepts?.call(details.data) ?? details.data.usine != factoryName,
      onAcceptWithDetails: (details) => onAccept(details.data),
      builder: (context, candidates, _) {
        final hovering = candidates.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: hovering
                ? accent.withValues(alpha: 0.10)
                : t.scaffold.withValues(alpha: t.isDark ? 0.7 : 1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: hovering ? accent : t.border,
              width: hovering ? 1.8 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.factory_outlined,
                      color: accent,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          factoryName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: t.text,
                          ),
                        ),
                        if (location != null && location.isNotEmpty)
                          Text(
                            location,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: t.muted),
                          ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      '${supervisors.length}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: accent,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (supervisors.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: hovering
                          ? accent.withValues(alpha: 0.45)
                          : t.border,
                    ),
                  ),
                  child: Text(
                    hovering ? 'Release to assign' : emptyLabel,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: hovering ? FontWeight.w800 : FontWeight.w500,
                      color: hovering ? accent : t.muted,
                    ),
                  ),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: supervisors
                      .map(
                        (sup) => _SupChip(
                          sup: sup,
                          selected: sup.id == _selectedId,
                          onTap: () => _openPerformancePanel(sup),
                          onRemove: removable ? () => _reassign(sup, '') : null,
                        ),
                      )
                      .toList(),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildValidatedList(AppTheme t, UserModel sup) {
    final solved = _solvedFor(sup)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return _SectionShell(
      icon: Icons.fact_check_outlined,
      title: 'Validated Alert Trail',
      subtitle: '${solved.length} resolved records',
      child: solved.isEmpty
          ? Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 28),
              alignment: Alignment.center,
              child: Text(
                'No validated alerts yet',
                style: TextStyle(fontSize: 13, color: t.muted),
              ),
            )
          : Column(
              children: solved
                  .take(12)
                  .map((alert) => _ValidatedAlertRow(alert: alert))
                  .toList(),
            ),
    );
  }
}

