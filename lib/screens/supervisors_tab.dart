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

const _navy = adminNavy;
const _navyLt = adminNavyLt;
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

  @override
  void initState() {
    super.initState();
    _sub = TabController(length: 3, vsync: this);
    _sub.addListener(_handleSubTabChanged);
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
    _factoriesSubscription =
        _hierarchyService.getFactories().listen((factories) {
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

    return Column(children: [
      Container(
        color: context.appTheme.card,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Container(
          decoration: BoxDecoration(
              color: context.appTheme.scaffold,
              borderRadius: BorderRadius.circular(20)),
          padding: const EdgeInsets.all(3),
          child: Row(
            children: [
              _SubPill(
                  label: 'Management',
                  icon: Icons.people,
                  index: 0,
                  ctrl: _sub),
              _SubPill(
                  label: 'Collaborations',
                  icon: Icons.shield,
                  index: 1,
                  ctrl: _sub),
              _SubPill(
                  label: 'Assignments',
                  icon: Icons.bar_chart,
                  index: 2,
                  ctrl: _sub),
            ],
          ),
        ),
      ),
      Expanded(child: _buildAnimatedSubTab(filteredSupervisors)),
    ]);
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
      _AssignmentsSubTab(
        key: const ValueKey('assignments'),
        supervisors: widget.supervisors,
        onRefresh: widget.onRefresh,
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
  const _SubPill(
      {required this.label,
      required this.icon,
      required this.index,
      required this.ctrl});
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
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
              color: sel ? _white : Colors.transparent,
              borderRadius: BorderRadius.circular(17),
              boxShadow: sel
                  ? [
                      const BoxShadow(
                          color: Color(0x18000000),
                          blurRadius: 4,
                          offset: Offset(0, 1))
                    ]
                  : []),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(widget.icon, size: 14, color: sel ? _navy : _muted),
            const SizedBox(width: 5),
            Text(widget.label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: sel ? _navy : _muted)),
          ]),
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
  const _ManagementSubTab(
      {super.key,
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
      required this.onSearchChanged});

  @override
  State<_ManagementSubTab> createState() => _ManagementSubTabState();
}

class _ManagementSubTabState extends State<_ManagementSubTab>
    with TickerProviderStateMixin {
  String? _selectedId;
  String _chartRange = '7days';
  late final AnimationController _liveActivityController;

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
    _liveActivityController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _ManagementSubTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncSelection();
  }

  void _syncSelection() {
    if (widget.allSupervisors.isEmpty) {
      _selectedId = null;
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

  List<AlertModel> _alertsFor(UserModel sup) => widget.alerts
      .where((a) =>
          a.superviseurId == sup.id ||
          a.assistantId == sup.id ||
          a.assistedBySupervisorId == sup.id)
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
    final ranked = [...widget.allSupervisors]..sort((a, b) {
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
      final day = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: days - 1 - i));
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
      final day = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: days - 1 - i));
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
      final day = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: 6 - i));
      final next = day.add(const Duration(days: 1));
      return solved
          .where((a) => a.timestamp.isAfter(day) && a.timestamp.isBefore(next))
          .length;
    });
  }

  Map<String, int> _teamTypeDistribution() {
    final map = <String, int>{};
    for (final alert in widget.alerts) {
      final involved = alert.superviseurId != null ||
          alert.assistantId != null ||
          alert.assistedBySupervisorId != null;
      if (!involved) continue;
      map[alert.type] = (map[alert.type] ?? 0) + 1;
    }
    return map;
  }

  List<_LeaderboardEntry> _leaderboard() {
    final entries = widget.allSupervisors
        .map((sup) => _LeaderboardEntry(
              supervisor: sup,
              score: _impactScore(sup),
            ))
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
            .where((a) =>
                a.usine == factory &&
                (a.superviseurId == sup.id || a.assistantId == sup.id))
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
        )
    };
  }

  Map<String, List<UserModel>> _groupByFactory() {
    final map = <String, List<UserModel>>{};
    for (final factory in widget.factories) {
      map[factory.name] = widget.allSupervisors
          .where((s) => s.usine == factory.name)
          .toList()
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(newFactory.isEmpty
            ? '${sup.fullName} unassigned'
            : '${sup.fullName} moved to $newFactory'),
        backgroundColor: context.appTheme.green,
      ));
      await widget.onRefresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Update failed: ${UserFriendlyError.message(e)}'),
      ));
    }
  }

  Future<void> _showDeleteConfirmDialog(UserModel sup) async {
    return showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: context.appTheme.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
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
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Delete Supervisor',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: context.appTheme.text)),
              const SizedBox(height: 2),
              Text(sup.fullName,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700, color: _red)),
            ]),
          ),
        ]),
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
                  borderRadius: BorderRadius.circular(8)),
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
    }.toList()
      ..sort();
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
                            .map((u) =>
                                DropdownMenuItem(value: u, child: Text(u)))
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
                                      'First name, last name, and email are required')),
                            );
                            return;
                          }
                          if (!email.contains('@')) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Please enter a valid email')),
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
                                content:
                                    Text('Supervisor updated successfully'),
                                backgroundColor: _green,
                              ),
                            );
                          } catch (e) {
                            if (!mounted) return;
                            setDialogState(() => saving = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text(
                                      'Update failed: ${UserFriendlyError.message(e)}')),
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
    return Column(children: [
      _buildCommandHeader(t),
      Expanded(
        child: RefreshIndicator(
          color: t.navy,
          backgroundColor: t.card,
          notificationPredicate: (_) => true,
          onRefresh: _refreshManagement,
          child: widget.totalSupervisors == 0
              ? _emptySups()
              : LayoutBuilder(builder: (context, constraints) {
                  final compact = constraints.maxWidth < 920;
                  if (compact) {
                    return _buildCompact(t, selected);
                  }
                  return _buildWide(t, selected);
                }),
        ),
      ),
    ]);
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
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            t.isDark ? const Color(0xFF0B1220) : const Color(0xFF0D4A75),
            t.isDark ? const Color(0xFF123A55) : const Color(0xFF0F766E),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: t.navy.withValues(alpha: 0.18),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: CustomPaint(
        painter:
            _CommandGridPainter(color: Colors.white.withValues(alpha: 0.08)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Row(children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
              ),
              child:
                  const Icon(Icons.auto_graph, color: Colors.white, size: 25),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Supervisor Command Center',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            height: 1.05)),
                    const SizedBox(height: 7),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      _GlassChip(Icons.bolt, '$active active', _green),
                      _GlassChip(Icons.nights_stay_outlined, '$absent absent',
                          _orange),
                      _GlassChip(Icons.factory_outlined,
                          '$assignedPlants plants', _blue),
                    ]),
                  ]),
            ),
            ElevatedButton.icon(
              onPressed: widget.onAdd,
              icon: const Icon(Icons.person_add, size: 17),
              label: const Text('Add Supervisor',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF0D4A75),
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ]),
        ),
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

    return LayoutBuilder(builder: (context, constraints) {
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
    });
  }

  Widget _buildWide(AppTheme t, UserModel? selected) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(width: 342, child: _buildRail(t)),
        const SizedBox(width: 14),
        Expanded(child: _buildDetailScroller(t, selected)),
      ]),
    );
  }

  Widget _buildCompact(AppTheme t, UserModel? selected) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
      child: Column(children: [
        _buildRail(t, compact: true),
        const SizedBox(height: 14),
        _buildDetailContent(t, selected),
      ]),
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
              color: Color(0x08000000), blurRadius: 12, offset: Offset(0, 6))
        ],
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
          child: Row(children: [
            Icon(Icons.manage_accounts_outlined, size: 18, color: t.navy),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Roster',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: t.text)),
            ),
            _Chip('${widget.allSupervisors.length}', t.navy),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          child: _buildSearchField(t),
        ),
        if (compact)
          SizedBox(height: 154, child: _buildRosterList(t, compact: true))
        else
          Expanded(child: _buildRosterList(t)),
      ]),
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
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
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
          child: Text('No supervisors match "${widget.searchQuery}"',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: t.muted)),
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
                score: _impactScore(sup),
                spark: _resolvedSpark(sup),
                onTap: () => setState(() => _selectedId = sup.id),
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
            score: _impactScore(sup),
            spark: _resolvedSpark(sup),
            onTap: () => setState(() => _selectedId = sup.id),
            onEdit: () => _showModifyDialog(sup),
            onDelete: () => _showDeleteConfirmDialog(sup),
          ),
        );
      },
    );
  }

  Widget _buildDetailScroller(AppTheme t, UserModel? selected) {
    return SingleChildScrollView(
      child: _buildDetailContent(t, selected),
    );
  }

  Widget _buildDetailContent(AppTheme t, UserModel? selected) {
    if (selected == null) {
      return Container(
        height: 420,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: t.border),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.person_search, size: 42, color: t.muted),
          const SizedBox(height: 12),
          Text('Select a supervisor',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w800, color: t.muted)),
        ]),
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: Column(
        key: ValueKey(selected.id),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSupervisorHero(t, selected),
          const SizedBox(height: 14),
          _buildMetricGrid(t, selected),
          const SizedBox(height: 14),
          _buildPerformanceCard(t, selected),
          const SizedBox(height: 14),
          _buildTypeBreakdown(t, selected),
          const SizedBox(height: 14),
          _buildValidatedList(t, selected),
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
      child: Stack(children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _CommandGridPainter(color: t.navy.withValues(alpha: 0.06)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(18),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 66,
                height: 66,
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
                  child: Text(_initials(sup),
                      style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                          color: Colors.white)),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(sup.fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              color: t.text,
                              height: 1.05)),
                      const SizedBox(height: 7),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        _StatusPill(
                            color: statusColor,
                            label: sup.isActive ? 'Active' : 'Absent',
                            icon: Icons.circle,
                            pulse: sup.isActive),
                        _StatusPill(
                            color: t.blue,
                            label: sup.usine.isEmpty ? 'Unassigned' : sup.usine,
                            icon: Icons.factory_outlined),
                        _AnimatedRankPill(rank: rank, color: t.purple),
                      ]),
                    ]),
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
            ]),
            const SizedBox(height: 16),
            Wrap(spacing: 10, runSpacing: 10, children: [
              _FloatingHeroSignal(
                delay: const Duration(milliseconds: 0),
                child: _HeroSignal(
                    label: 'Resolved',
                    value: '${solved.length}',
                    color: t.green,
                    icon: Icons.check_circle_outline),
              ),
              _FloatingHeroSignal(
                delay: const Duration(milliseconds: 90),
                child: _HeroSignal(
                    label: 'Avg Time',
                    value: avg == null ? '-' : _fmtMin(avg),
                    color: t.orange,
                    icon: Icons.timer_outlined),
              ),
              _FloatingHeroSignal(
                delay: const Duration(milliseconds: 180),
                child: _HeroSignal(
                    label: 'Impact',
                    value: '${_impactScore(sup)}',
                    color: t.blue,
                    icon: Icons.bolt_outlined),
              ),
              if (dist.isNotEmpty)
                _FloatingHeroSignal(
                  delay: const Duration(milliseconds: 270),
                  child: _HeroSignal(
                      label: 'Top Plant',
                      value: dist.entries
                          .reduce((a, b) => a.value >= b.value ? a : b)
                          .key,
                      color: t.purple,
                      icon: Icons.hub_outlined),
                ),
            ]),
          ]),
        ),
      ]),
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
          tone: t.green),
      _CommandMetric(
          icon: Icons.speed,
          label: 'Average Resolution',
          value: avg == null ? '-' : _fmtMin(avg),
          tone: t.orange),
      _CommandMetric(
          icon: Icons.verified_outlined,
          label: 'Validation Rate',
          value: '$rate%',
          tone: t.blue),
      _CommandMetric(
          icon: Icons.psychology_alt_outlined,
          label: 'AI Assigned',
          value: '$ai',
          tone: t.purple),
      _CommandMetric(
          icon: Icons.warning_amber_rounded,
          label: 'Critical Load',
          value: '$critical',
          tone: t.red),
    ];

    return LayoutBuilder(builder: (context, constraints) {
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
        children:
            tiles.map((tile) => SizedBox(width: width, child: tile)).toList(),
      );
    });
  }

  Widget _buildPerformanceCard(AppTheme t, UserModel sup) {
    final points = _buildChartPoints(sup);
    final chartTotal = points.fold<double>(0, (sum, p) => sum + p.value);
    final key = ValueKey('${sup.id}-$_chartRange-$chartTotal');

    return _SectionShell(
      icon: Icons.show_chart,
      title: 'Performance Graph',
      subtitle: 'Resolved alerts over time',
      trailing: _RangeToggle(
        value: _chartRange,
        onChanged: (v) => setState(() => _chartRange = v),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          height: 230,
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
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(width: 30, height: 3, color: t.navy),
          const SizedBox(width: 7),
          Icon(Icons.circle, size: 8, color: t.green),
          const SizedBox(width: 7),
          Text('Validations', style: TextStyle(fontSize: 11, color: t.muted)),
        ]),
      ]),
    );
  }

  Widget _buildTypeBreakdown(AppTheme t, UserModel sup) {
    final stats = _typeStats(sup);
    return _SectionShell(
      icon: Icons.analytics_outlined,
      title: 'Alert Type Breakdown',
      subtitle: 'Validation quality by alert class',
      child: LayoutBuilder(builder: (context, constraints) {
        final columns = constraints.maxWidth > 900
            ? 4
            : constraints.maxWidth > 620
                ? 2
                : 1;
        final gap = 10.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: stats.entries.map((entry) {
            final type = entry.key;
            final data = entry.value;
            final total = data.validated + data.notValidated;
            final pct = total == 0 ? 0 : (data.validated / total * 100).round();
            final color = _typeColor(type);
            return SizedBox(
              width: width,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withValues(alpha: 0.24)),
                ),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                          child: Text(_typeLabel(type),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: color)),
                        ),
                        Text('$pct%',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: color)),
                      ]),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          minHeight: 7,
                          value: pct / 100,
                          backgroundColor: color.withValues(alpha: 0.12),
                          valueColor: AlwaysStoppedAnimation<Color>(color),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _PerfStatRow(
                          label: 'Validated',
                          value: data.validated,
                          color: _green),
                      const SizedBox(height: 3),
                      _PerfStatRow(
                          label: 'Open / returned',
                          value: data.notValidated,
                          color: _orange),
                    ]),
              ),
            );
          }).toList(),
        );
      }),
    );
  }

  Widget _buildAssignmentMatrix(AppTheme t) {
    final grouped = _groupByFactory();
    final unassigned = _unassigned();
    final cards = <Widget>[
      ...grouped.entries.map((entry) => _buildFactoryDropCard(
            t,
            factoryName: entry.key,
            location: _locationFor(entry.key),
            supervisors: entry.value,
            accent: t.navy,
            emptyLabel: 'Open slot',
            onAccept: (sup) => _reassign(sup, entry.key),
          )),
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
      title: 'Plant Assignment Matrix',
      subtitle: 'Drag a supervisor chip into a plant lane',
      child: LayoutBuilder(builder: (context, constraints) {
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
          children:
              cards.map((card) => SizedBox(width: width, child: card)).toList(),
        );
      }),
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
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.factory_outlined, color: accent, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(factoryName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              color: t.text)),
                      if (location != null && location.isNotEmpty)
                        Text(location,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: t.muted)),
                    ]),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text('${supervisors.length}',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: accent)),
              ),
            ]),
            const SizedBox(height: 12),
            if (supervisors.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color:
                          hovering ? accent.withValues(alpha: 0.45) : t.border),
                ),
                child: Text(hovering ? 'Release to assign' : emptyLabel,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            hovering ? FontWeight.w800 : FontWeight.w500,
                        color: hovering ? accent : t.muted)),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: supervisors
                    .map((sup) => _SupChip(
                          sup: sup,
                          selected: sup.id == _selectedId,
                          onTap: () => setState(() => _selectedId = sup.id),
                          onRemove: removable ? () => _reassign(sup, '') : null,
                        ))
                    .toList(),
              ),
          ]),
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
              child: Text('No validated alerts yet',
                  style: TextStyle(fontSize: 13, color: t.muted)),
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

class _LeaderboardEntry {
  final UserModel supervisor;
  final int score;
  const _LeaderboardEntry({required this.supervisor, required this.score});
}

class _FactoryWorkloadSegment {
  final UserModel supervisor;
  final int count;
  const _FactoryWorkloadSegment({
    required this.supervisor,
    required this.count,
  });
}

class _DashboardShimmerSkeleton extends StatelessWidget {
  const _DashboardShimmerSkeleton();

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Shimmer.fromColors(
      baseColor: t.border.withValues(alpha: 0.38),
      highlightColor: t.card.withValues(alpha: 0.92),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: List.generate(
          5,
          (index) => Container(
            width: 320,
            height: 210,
            decoration: BoxDecoration(
              color: t.border,
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ),
    );
  }
}

class _StaggeredEntrance extends StatefulWidget {
  final Widget child;
  final Duration delay;
  const _StaggeredEntrance({required this.child, required this.delay});

  @override
  State<_StaggeredEntrance> createState() => _StaggeredEntranceState();
}

class _StaggeredEntranceState extends State<_StaggeredEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _offset;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 460),
    );
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _offset = Tween(begin: const Offset(0, 0.035), end: Offset.zero).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _timer = Timer(widget.delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _offset, child: widget.child),
    );
  }
}

class _WeeklyResolutionHeatmap extends StatelessWidget {
  final List<int> values;
  const _WeeklyResolutionHeatmap({required this.values});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final maxY = math.max(1, values.fold<int>(0, math.max)).toDouble();
    final now = DateTime.now();
    final days = List.generate(
      values.length,
      (i) => now.subtract(Duration(days: values.length - 1 - i)),
    );

    return SizedBox(
      height: 198,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxY + 1,
          minY: 0,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(
              color: t.border.withValues(alpha: 0.52),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: math.max(1, maxY / 3),
                getTitlesWidget: (value, _) => Text(
                  value.toInt().toString(),
                  style: TextStyle(fontSize: 9, color: t.muted),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, _) {
                  final index = value.toInt();
                  if (index < 0 || index >= days.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      _weekdayShort(days[index].weekday),
                      style: TextStyle(
                          fontSize: 10,
                          color: t.muted,
                          fontWeight: FontWeight.w700),
                    ),
                  );
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => t.text,
              getTooltipItem: (group, _, rod, __) => BarTooltipItem(
                '${rod.toY.toInt()} resolved',
                TextStyle(
                  color: t.card,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          barGroups: List.generate(values.length, (i) {
            return BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: values[i].toDouble(),
                  width: 18,
                  borderRadius: BorderRadius.circular(7),
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      t.green.withValues(alpha: 0.55),
                      t.green,
                    ],
                  ),
                ),
              ],
            );
          }),
        ),
        duration: const Duration(milliseconds: 850),
        curve: Curves.easeOutCubic,
      ),
    );
  }
}

class _AlertTypeDonut extends StatelessWidget {
  final Map<String, int> distribution;
  const _AlertTypeDonut({required this.distribution});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final entries = distribution.entries.where((e) => e.value > 0).toList();
    if (entries.isEmpty) {
      return _EmptyChartState(label: 'No alert type activity');
    }
    final total = entries.fold<int>(0, (sum, e) => sum + e.value);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, progress, _) {
        return Row(children: [
          SizedBox(
            width: 150,
            height: 150,
            child: PieChart(
              PieChartData(
                centerSpaceRadius: 42,
                sectionsSpace: 2,
                startDegreeOffset: -90,
                sections: List.generate(entries.length, (i) {
                  final visible =
                      ((progress * entries.length) - i).clamp(0.0, 1.0);
                  final entry = entries[i];
                  final color = typeMeta(entry.key, t).color;
                  return PieChartSectionData(
                    value: entry.value * visible,
                    title: visible > 0.85
                        ? '${(entry.value / total * 100).round()}%'
                        : '',
                    color: color,
                    radius: 34 + visible * 12,
                    titleStyle: TextStyle(
                      color: t.card,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  );
                }),
              ),
              duration: const Duration(milliseconds: 250),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: entries.map((entry) {
                final color = typeMeta(entry.key, t).color;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(alpha: 0.28),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        typeMeta(entry.key, t).label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: t.text,
                            fontSize: 11,
                            fontWeight: FontWeight.w800),
                      ),
                    ),
                    Text(
                      entry.value.toString(),
                      style: TextStyle(
                          color: t.muted,
                          fontSize: 11,
                          fontWeight: FontWeight.w800),
                    ),
                  ]),
                );
              }).toList(),
            ),
          ),
        ]);
      },
    );
  }
}

class _SupervisorLeaderboardChart extends StatelessWidget {
  final List<_LeaderboardEntry> entries;
  const _SupervisorLeaderboardChart({required this.entries});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    if (entries.isEmpty) {
      return _EmptyChartState(label: 'No supervisor scores yet');
    }
    final maxScore = math.max(1, entries.map((e) => e.score).reduce(math.max));
    return Column(
      children: List.generate(entries.length, (index) {
        final entry = entries[index];
        final color = _rankTone(t, index);
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: Duration(milliseconds: 520 + index * 90),
          curve: Curves.easeOutCubic,
          builder: (context, progress, _) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(children: [
                SizedBox(
                  width: 92,
                  child: Text(
                    entry.supervisor.fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: t.text,
                        fontSize: 11,
                        fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: Stack(children: [
                      Container(height: 12, color: t.scaffold),
                      FractionallySizedBox(
                        widthFactor: (entry.score / maxScore) * progress,
                        child: Container(
                          height: 12,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                color.withValues(alpha: 0.55),
                                color,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 34,
                  child: Text(
                    '${(entry.score * progress).round()}',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.w900),
                  ),
                ),
              ]),
            );
          },
        );
      }),
    );
  }
}

class _LiveActivityPulseChart extends StatelessWidget {
  final List<double> samples;
  final double progress;
  const _LiveActivityPulseChart({
    required this.samples,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return SizedBox(
      height: 156,
      child: CustomPaint(
        painter: _HeartbeatPainter(
          samples: samples,
          progress: progress,
          color: t.green,
          gridColor: t.border,
          labelColor: t.muted,
          backgroundColor: t.scaffold,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _FactoryWorkloadChart extends StatelessWidget {
  final Map<String, List<_FactoryWorkloadSegment>> workload;
  const _FactoryWorkloadChart({required this.workload});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final entries = workload.entries
        .where((entry) => entry.value.isNotEmpty)
        .take(5)
        .toList();
    if (entries.isEmpty) {
      return _EmptyChartState(label: 'No factory workload yet');
    }
    final maxTotal = entries
        .map((e) => e.value.fold<int>(0, (sum, segment) => sum + segment.count))
        .fold<int>(1, math.max);
    final palette = [t.green, t.blue, t.orange, t.purple, t.yellow];

    return Column(
      children: List.generate(entries.length, (index) {
        final entry = entries[index];
        final total =
            entry.value.fold<int>(0, (sum, segment) => sum + segment.count);
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: Duration(milliseconds: 620 + index * 80),
          curve: Curves.easeOutCubic,
          builder: (context, progress, _) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(children: [
                SizedBox(
                  width: 86,
                  child: Text(
                    entry.key,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11,
                        color: t.text,
                        fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: SizedBox(
                      height: 16,
                      child: Row(children: [
                        for (var i = 0; i < entry.value.length; i++)
                          Flexible(
                            flex: math.max(
                                1, (entry.value[i].count * progress).round()),
                            child: Container(
                              color: palette[i % palette.length],
                            ),
                          ),
                        if (total < maxTotal)
                          Flexible(
                            flex: math.max(1, maxTotal - total),
                            child: Container(color: t.scaffold),
                          ),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  total.toString(),
                  style: TextStyle(
                      color: t.muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w800),
                ),
              ]),
            );
          },
        );
      }),
    );
  }
}

class _EmptyChartState extends StatelessWidget {
  final String label;
  const _EmptyChartState({required this.label});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Container(
      height: 136,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: t.scaffold,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.border),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, color: t.muted),
      ),
    );
  }
}

Color _rankTone(AppTheme t, int index) {
  if (index == 0) return t.yellow;
  if (index == 1) return t.blue;
  if (index == 2) return t.orange;
  return t.green;
}

String _weekdayShort(int weekday) {
  const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return labels[(weekday - 1).clamp(0, 6)];
}

class _HeartbeatPainter extends CustomPainter {
  final List<double> samples;
  final double progress;
  final Color color;
  final Color gridColor;
  final Color labelColor;
  final Color backgroundColor;

  const _HeartbeatPainter({
    required this.samples,
    required this.progress,
    required this.color,
    required this.gridColor,
    required this.labelColor,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) return;
    final rect = Offset.zero & size;
    final bg = Paint()..color = backgroundColor.withValues(alpha: 0.42);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(12)),
      bg,
    );

    final gridPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.55)
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final maxVal = math.max(1.0, samples.reduce(math.max));
    final step = size.width / math.max(1, samples.length - 1);
    final shift = progress * step;
    Offset point(int i) {
      final x = i * step - shift;
      final y = size.height -
          14 -
          (samples[i] / maxVal) * math.max(1, size.height - 28);
      return Offset(x, y);
    }

    final path = Path();
    for (var i = 0; i < samples.length; i++) {
      final p = point(i);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        final prev = point(i - 1);
        final cx = (prev.dx + p.dx) / 2;
        path.cubicTo(cx, prev.dy, cx, p.dy, p.dx, p.dy);
      }
    }

    final glow = Paint()
      ..color = color.withValues(alpha: 0.42)
      ..strokeWidth = 7
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawPath(path, glow);

    final line = Paint()
      ..color = color
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, line);

    final current = point(samples.length - 1);
    final dotGlow = Paint()
      ..color = color.withValues(alpha: 0.45)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9);
    canvas.drawCircle(current, 9, dotGlow);
    canvas.drawCircle(current, 3.5, Paint()..color = color);

    final label = TextPainter(
      text: TextSpan(
        text: 'LIVE',
        style: TextStyle(
          color: labelColor,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(canvas, const Offset(10, 10));
  }

  @override
  bool shouldRepaint(covariant _HeartbeatPainter oldDelegate) =>
      oldDelegate.samples != samples ||
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.gridColor != gridColor ||
      oldDelegate.labelColor != labelColor ||
      oldDelegate.backgroundColor != backgroundColor;
}

class _SupervisorRailTile extends StatefulWidget {
  final UserModel supervisor;
  final bool selected;
  final int solved;
  final int claimed;
  final int score;
  final List<int> spark;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _SupervisorRailTile({
    required this.supervisor,
    required this.selected,
    required this.solved,
    required this.claimed,
    required this.score,
    required this.spark,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_SupervisorRailTile> createState() => _SupervisorRailTileState();
}

class _SupervisorRailTileState extends State<_SupervisorRailTile> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final status = widget.supervisor.isActive ? t.green : t.red;
    final borderColor = widget.selected ? t.navy : t.border;
    final tile = AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      transform: Matrix4.translationValues(0, _hovering ? -3 : 0, 0),
      padding: const EdgeInsets.all(1.3),
      decoration: BoxDecoration(
        gradient: widget.selected
            ? LinearGradient(
                colors: [
                  t.navy.withValues(alpha: 0.72),
                  t.green.withValues(alpha: 0.48),
                  t.blue.withValues(alpha: 0.42),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: borderColor, width: widget.selected ? 1.4 : 1),
        boxShadow: widget.selected || _hovering
            ? [
                BoxShadow(
                  color: t.navy.withValues(alpha: 0.14),
                  blurRadius: _hovering ? 18 : 14,
                  offset: Offset(0, _hovering ? 10 : 7),
                ),
              ]
            : null,
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: widget.selected
              ? t.navyLt.withValues(alpha: t.isDark ? 0.82 : 0.96)
              : t.card,
          borderRadius: BorderRadius.circular(13),
        ),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: widget.selected ? t.navy : t.scaffold,
                  borderRadius: BorderRadius.circular(13),
                  border:
                      Border.all(color: widget.selected ? t.navy : t.border),
                ),
                child: Center(
                  child: Text(_initials(widget.supervisor),
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: widget.selected ? Colors.white : t.navy)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.supervisor.fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              color: t.text)),
                      const SizedBox(height: 3),
                      Row(children: [
                        _LivePulseDot(
                          color: status,
                          pulse: widget.supervisor.isActive,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            widget.supervisor.usine.isEmpty
                                ? 'Unassigned'
                                : widget.supervisor.usine,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: t.muted),
                          ),
                        ),
                      ]),
                    ]),
              ),
              Icon(Icons.drag_indicator, size: 18, color: t.muted),
            ]),
            const SizedBox(height: 11),
            Wrap(spacing: 6, runSpacing: 6, children: [
              _AnimatedMiniChip(
                  icon: Icons.check_circle_outline,
                  value: widget.solved,
                  suffix: ' fixed',
                  color: t.green),
              _AnimatedMiniChip(
                  icon: Icons.timer_outlined,
                  value: widget.claimed,
                  suffix: ' live',
                  color: t.blue),
              _AnimatedMiniChip(
                  icon: Icons.bolt_outlined,
                  value: widget.score,
                  suffix: ' pts',
                  color: t.orange),
            ]),
            const SizedBox(height: 10),
            SizedBox(
              height: 30,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 760),
                curve: Curves.easeOutCubic,
                builder: (context, progress, _) => CustomPaint(
                  painter: _MiniSparklinePainter(
                    data: widget.spark,
                    color: widget.selected ? t.navy : t.green,
                    gridColor: t.border,
                    progress: progress,
                  ),
                  size: Size.infinite,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: Text(widget.supervisor.email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, color: t.muted)),
              ),
              Tooltip(
                message: 'Modify Supervisor',
                child: InkWell(
                  onTap: widget.onEdit,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(5),
                    child: Icon(Icons.edit, size: 16, color: t.navy),
                  ),
                ),
              ),
              Tooltip(
                message: 'Delete Supervisor',
                child: InkWell(
                  onTap: widget.onDelete,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(5),
                    child: Icon(Icons.delete_outline, size: 16, color: t.red),
                  ),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: LongPressDraggable<UserModel>(
        data: widget.supervisor,
        feedback: Material(
          color: Colors.transparent,
          child: Container(
            width: 240,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: t.navy,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: t.navy.withValues(alpha: 0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(children: [
              const Icon(Icons.person_outline, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(widget.supervisor.fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w800)),
              ),
            ]),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.35, child: tile),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(14),
          child: tile,
        ),
      ),
    );
  }
}

class _AnimatedMiniChip extends StatelessWidget {
  final IconData icon;
  final int value;
  final String suffix;
  final Color color;
  const _AnimatedMiniChip({
    required this.icon,
    required this.value,
    required this.suffix,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<int>(
      tween: IntTween(begin: 0, end: value),
      duration: const Duration(milliseconds: 720),
      curve: Curves.easeOutCubic,
      builder: (context, animated, _) {
        return _MiniChip(icon, '$animated$suffix', color);
      },
    );
  }
}

class _LivePulseDot extends StatefulWidget {
  final Color color;
  final bool pulse;
  const _LivePulseDot({required this.color, this.pulse = true});

  @override
  State<_LivePulseDot> createState() => _LivePulseDotState();
}

class _LivePulseDotState extends State<_LivePulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void initState() {
    super.initState();
    if (widget.pulse) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _LivePulseDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulse && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.pulse && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final v = widget.pulse ? _controller.value : 0.0;
        return SizedBox(
          width: 14,
          height: 14,
          child: Stack(alignment: Alignment.center, children: [
            Container(
              width: 12 + v * 3,
              height: 12 + v * 3,
              decoration: BoxDecoration(
                color:
                    widget.color.withValues(alpha: widget.pulse ? 0.18 : 0.10),
                shape: BoxShape.circle,
              ),
            ),
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: widget.color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: widget.color
                        .withValues(alpha: widget.pulse ? 0.48 : 0.22),
                    blurRadius: widget.pulse ? 5 + v * 5 : 3,
                  ),
                ],
              ),
            ),
          ]),
        );
      },
    );
  }
}

class _MiniSparklinePainter extends CustomPainter {
  final List<int> data;
  final Color color;
  final Color gridColor;
  final double progress;

  const _MiniSparklinePainter({
    required this.data,
    required this.color,
    required this.gridColor,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty || size.isEmpty) return;
    final maxVal = math.max(1, data.reduce(math.max)).toDouble();
    final visibleCount =
        (data.length * progress).clamp(1.0, data.length.toDouble());
    final n = visibleCount.ceil();
    final stepX = data.length > 1 ? size.width / (data.length - 1) : size.width;

    final grid = Paint()
      ..color = gridColor.withValues(alpha: 0.34)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height - 2),
      Offset(size.width, size.height - 2),
      grid,
    );

    double yFor(int i) {
      final pad = size.height * 0.18;
      final usable = size.height - pad * 2;
      return pad + usable - (data[i] / maxVal) * usable;
    }

    final path = Path();
    final fill = Path();
    for (var i = 0; i < n; i++) {
      final x = i * stepX;
      final y = yFor(i);
      if (i == 0) {
        path.moveTo(x, y);
        fill.moveTo(x, size.height);
        fill.lineTo(x, y);
      } else {
        final prevX = (i - 1) * stepX;
        final prevY = yFor(i - 1);
        final cp1 = Offset(prevX + stepX / 2, prevY);
        final cp2 = Offset(x - stepX / 2, y);
        path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, x, y);
        fill.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, x, y);
      }
    }
    final lastX = (n - 1) * stepX;
    fill.lineTo(lastX, size.height);
    fill.close();

    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.24),
            color.withValues(alpha: 0.0),
          ],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _MiniSparklinePainter oldDelegate) =>
      oldDelegate.data != data ||
      oldDelegate.color != color ||
      oldDelegate.gridColor != gridColor ||
      oldDelegate.progress != progress;
}

class _GlassChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _GlassChip(this.icon, this.label, this.color);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Colors.white)),
        ]),
      );
}

class _StatusPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool pulse;
  const _StatusPill({
    required this.icon,
    required this.label,
    required this.color,
    this.pulse = false,
  });

  @override
  Widget build(BuildContext context) {
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.34)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: icon == Icons.circle ? 8 : 14, color: color),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w800, color: color)),
      ]),
    );
    if (!pulse) return pill;
    return _PulsingRing(color: color, child: pill);
  }
}

class _AnimatedRankPill extends StatelessWidget {
  final int rank;
  final Color color;
  const _AnimatedRankPill({required this.rank, required this.color});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOutBack,
      builder: (context, value, _) {
        return Transform.translate(
          offset: Offset((1 - value) * 14, 0),
          child: Transform.scale(
            scale: 0.92 + value * 0.08,
            child: Opacity(
              opacity: value.clamp(0.0, 1.0),
              child: _StatusPill(
                color: color,
                label: 'Rank #$rank',
                icon: Icons.leaderboard_outlined,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PulsingRing extends StatefulWidget {
  final Widget child;
  final Color color;
  const _PulsingRing({required this.child, required this.color});

  @override
  State<_PulsingRing> createState() => _PulsingRingState();
}

class _PulsingRingState extends State<_PulsingRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1700),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final v = _controller.value;
        return Container(
          padding: EdgeInsets.all(2 + v * 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: widget.color.withValues(alpha: 0.12 + v * 0.22),
            ),
          ),
          child: widget.child,
        );
      },
    );
  }
}

class _FloatingHeroSignal extends StatefulWidget {
  final Widget child;
  final Duration delay;
  const _FloatingHeroSignal({required this.child, required this.delay});

  @override
  State<_FloatingHeroSignal> createState() => _FloatingHeroSignalState();
}

class _FloatingHeroSignalState extends State<_FloatingHeroSignal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.delay, () {
      if (mounted) _controller.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final wave = math.sin(_controller.value * math.pi);
        return Opacity(
          opacity: (0.88 + wave * 0.12).clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, -wave * 3.5),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

class _HeroSignal extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _HeroSignal({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Container(
      width: 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.card.withValues(alpha: t.isDark ? 0.62 : 0.86),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 9),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: t.text,
                    height: 1)),
            const SizedBox(height: 4),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10, color: t.muted)),
          ]),
        ),
      ]),
    );
  }
}

class _CommandMetric extends StatefulWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color tone;
  const _CommandMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.tone,
  });

  @override
  State<_CommandMetric> createState() => _CommandMetricState();
}

class _CommandMetricState extends State<_CommandMetric> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0, _hovering ? -3 : 0, 0),
        height: 94,
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: widget.tone.withValues(alpha: 0.18)),
          boxShadow: [
            BoxShadow(
              color: widget.tone.withValues(alpha: _hovering ? 0.16 : 0.06),
              blurRadius: _hovering ? 18 : 10,
              offset: Offset(0, _hovering ? 9 : 5),
            )
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(widget.icon, size: 17, color: widget.tone),
            const Spacer(),
            Container(
              width: 22,
              height: 3,
              decoration: BoxDecoration(
                color: widget.tone.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ]),
          const Spacer(),
          Text(widget.value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: t.text,
                  height: 1)),
          const SizedBox(height: 5),
          Text(widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: t.muted)),
        ]),
      ),
    );
  }
}

class _SectionShell extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;
  const _SectionShell({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.border),
        boxShadow: const [
          BoxShadow(
              color: Color(0x06000000), blurRadius: 12, offset: Offset(0, 6))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: t.navyLt,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: t.navy),
          ),
          const SizedBox(width: 10),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: t.text)),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(fontSize: 11, color: t.muted)),
            ]),
          ),
          if (trailing != null) trailing!,
        ]),
        const SizedBox(height: 15),
        child,
      ]),
    );
  }
}

class _RangeToggle extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _RangeToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Container(
      width: 142,
      height: 34,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: t.scaffold,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.border),
      ),
      child: LayoutBuilder(builder: (context, constraints) {
        final itemW = constraints.maxWidth / 2;
        final selectedIndex = value == '30days' ? 1 : 0;
        Widget item(String id, String label) {
          final selected = value == id;
          return Expanded(
            child: InkWell(
              onTap: () => onChanged(id),
              borderRadius: BorderRadius.circular(9),
              child: Center(
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 180),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: selected ? Colors.white : t.muted,
                  ),
                  child: Text(label),
                ),
              ),
            ),
          );
        }

        return Stack(children: [
          AnimatedPositioned(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            left: itemW * selectedIndex,
            top: 0,
            bottom: 0,
            width: itemW,
            child: Container(
              decoration: BoxDecoration(
                color: t.navy,
                borderRadius: BorderRadius.circular(9),
                boxShadow: [
                  BoxShadow(
                    color: t.navy.withValues(alpha: 0.24),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
            ),
          ),
          Row(children: [item('7days', '7D'), item('30days', '30D')]),
        ]);
      }),
    );
  }
}

class _CommandGridPainter extends CustomPainter {
  final Color color;
  const _CommandGridPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const step = 28.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(
          Offset(x, 0), Offset(x + size.height * 0.35, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CommandGridPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _PerformanceSubTab extends StatefulWidget {
  final List<UserModel> supervisors;
  final List<AlertModel> alerts;
  const _PerformanceSubTab({required this.supervisors, required this.alerts});
  @override
  State<_PerformanceSubTab> createState() => _PerformanceSubTabState();
}

class _PerformanceSubTabState extends State<_PerformanceSubTab> {
  UserModel? _selected;
  String _chartRange = '7days';

  List<AlertModel> get _supAlerts => _selected == null
      ? []
      : widget.alerts
          .where((a) =>
              a.superviseurId == _selected!.id ||
              a.assistantId == _selected!.id)
          .toList();

  List<AlertModel> get _solved =>
      _supAlerts.where((a) => a.status == 'validee').toList();

  int? get _avgMin {
    final w = _solved.where((a) => a.elapsedTime != null).toList();
    if (w.isEmpty) return null;
    return w.fold(0, (s, a) => s + (a.elapsedTime ?? 0)) ~/ w.length;
  }

  List<_ChartPoint> _buildChartPoints() {
    final days = _chartRange == '7days' ? 7 : 30;
    final now = DateTime.now();
    return List.generate(days, (i) {
      final day = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: days - 1 - i));
      final next = day.add(const Duration(days: 1));
      final count = _solved
          .where((a) => a.timestamp.isAfter(day) && a.timestamp.isBefore(next))
          .length;
      return _ChartPoint(day: day, value: count.toDouble());
    });
  }

  Map<String, int> _factoryDist() {
    final m = <String, int>{};
    for (var a in _solved) {
      m[a.usine] = (m[a.usine] ?? 0) + 1;
    }
    return m;
  }

  Map<String, _TypeStats> _typeStats() {
    final types = [
      'qualite',
      'maintenance',
      'defaut_produit',
      'manque_ressource'
    ];
    return {
      for (var t in types)
        t: _TypeStats(
          validated: _supAlerts
              .where((a) => a.type == t && a.status == 'validee')
              .length,
          notValidated: _supAlerts
              .where((a) => a.type == t && a.status != 'validee')
              .length,
        )
    };
  }

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Supervisor Performance',
            style: TextStyle(
                fontSize: 19, fontWeight: FontWeight.w800, color: t.text)),
        const SizedBox(height: 2),
        Text('Analyse alert validations per supervisor',
            style: TextStyle(fontSize: 13, color: t.muted)),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: t.card,
              border: Border.all(color: t.border),
              borderRadius: BorderRadius.circular(12)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Select a supervisor',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: t.text)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                  color: t.scaffold,
                  border: Border.all(color: t.border),
                  borderRadius: BorderRadius.circular(9)),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<UserModel>(
                  isExpanded: true,
                  value: _selected,
                  hint: Text('Choose a supervisor…',
                      style: TextStyle(color: t.muted, fontSize: 14)),
                  dropdownColor: t.card,
                  items: widget.supervisors
                      .map((s) => DropdownMenuItem(
                            value: s,
                            child: Row(children: [
                              Icon(Icons.person_outline,
                                  size: 16, color: t.navy),
                              const SizedBox(width: 8),
                              Text(s.fullName,
                                  style:
                                      TextStyle(fontSize: 14, color: t.text)),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                    color: t.navyLt,
                                    borderRadius: BorderRadius.circular(99)),
                                child: Text(s.usine,
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: t.navy,
                                        fontWeight: FontWeight.w600)),
                              ),
                            ]),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _selected = v),
                ),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        if (_selected == null)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 60),
            alignment: Alignment.center,
            child: Column(children: [
              Container(
                width: 64,
                height: 64,
                decoration:
                    BoxDecoration(color: t.scaffold, shape: BoxShape.circle),
                child: Icon(Icons.person_search, size: 32, color: t.muted),
              ),
              const SizedBox(height: 14),
              Text('Choose a supervisor',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: t.muted)),
              const SizedBox(height: 4),
              Text('Select a supervisor above to see their statistics',
                  style: TextStyle(fontSize: 12, color: t.muted)),
            ]),
          ),
        if (_selected != null) ...[
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              flex: 2,
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                    color: t.card,
                    border: Border.all(color: t.border),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [
                      BoxShadow(
                          color: Color(0x06000000),
                          blurRadius: 4,
                          offset: Offset(0, 2))
                    ]),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Fixed Alerts',
                          style: TextStyle(fontSize: 12, color: t.muted)),
                      const SizedBox(height: 6),
                      Row(children: [
                        Text('${_solved.length}',
                            style: TextStyle(
                                fontSize: 40,
                                fontWeight: FontWeight.w800,
                                color: t.navy,
                                height: 1)),
                        const Spacer(),
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                              color: t.blueLt, shape: BoxShape.circle),
                          child: Icon(Icons.check_circle_outline,
                              color: t.blue, size: 24),
                        ),
                      ]),
                      Divider(height: 20, color: t.border),
                      Text('Distribution by Factory:',
                          style: TextStyle(fontSize: 11, color: t.muted)),
                      const SizedBox(height: 8),
                      Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _factoryDist()
                              .entries
                              .map((e) => Container(
                                    padding:
                                        const EdgeInsets.fromLTRB(10, 7, 14, 7),
                                    decoration: BoxDecoration(
                                        color: t.navyLt,
                                        border: Border.all(
                                            color: t.navy.withOpacity(0.3)),
                                        borderRadius: BorderRadius.circular(8)),
                                    child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.bar_chart,
                                              size: 14, color: t.navy),
                                          const SizedBox(width: 6),
                                          Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(e.key,
                                                    style: TextStyle(
                                                        fontSize: 11,
                                                        color: t.navy,
                                                        fontWeight:
                                                            FontWeight.w600)),
                                                Text('${e.value}',
                                                    style: TextStyle(
                                                        fontSize: 16,
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        color: t.navy)),
                                              ]),
                                        ]),
                                  ))
                              .toList()),
                    ]),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                    color: t.card,
                    border: Border.all(color: t.border),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [
                      BoxShadow(
                          color: Color(0x06000000),
                          blurRadius: 4,
                          offset: Offset(0, 2))
                    ]),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Average Time',
                          style: TextStyle(fontSize: 12, color: t.muted)),
                      const SizedBox(height: 6),
                      Row(children: [
                        Expanded(
                          child: Text(_avgMin == null ? '—' : _fmtMin(_avgMin!),
                              style: TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800,
                                  color: t.green,
                                  height: 1)),
                        ),
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                              color: t.greenLt, shape: BoxShape.circle),
                          child: Icon(Icons.timer, color: t.green, size: 24),
                        ),
                      ]),
                    ]),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          Row(
              children: [
            'qualite',
            'maintenance',
            'defaut_produit',
            'manque_ressource'
          ].map((tp) {
            final ts = _typeStats()[tp]!;
            final clr = _typeColor(tp);
            final tot = ts.validated + ts.notValidated;
            final pct = tot == 0 ? 0 : (ts.validated / tot * 100).round();
            return Expanded(
                child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: t.card,
                    border: Border.all(color: clr.withValues(alpha: .25)),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [
                      BoxShadow(
                          color: Color(0x06000000),
                          blurRadius: 3,
                          offset: Offset(0, 2))
                    ]),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                            child: Text(_typeLabel(tp),
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: clr))),
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                              color: clr.withOpacity(.1),
                              shape: BoxShape.circle),
                          child: Icon(Icons.check_circle_outline,
                              color: clr, size: 16),
                        ),
                      ]),
                      const SizedBox(height: 6),
                      Text('$tot',
                          style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              color: clr,
                              height: 1)),
                      const SizedBox(height: 10),
                      _PerfStatRow(
                          label: 'Validated',
                          value: ts.validated,
                          color: _green),
                      const SizedBox(height: 3),
                      _PerfStatRow(
                          label: 'Not validated',
                          value: ts.notValidated,
                          color: _orange),
                      const SizedBox(height: 6),
                      Text('$pct% validated',
                          style: TextStyle(fontSize: 10, color: t.muted)),
                    ]),
              ),
            ));
          }).toList()),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
                color: t.card,
                border: Border.all(color: t.border),
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(
                      color: Color(0x06000000),
                      blurRadius: 4,
                      offset: Offset(0, 2))
                ]),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.calendar_today, size: 15, color: t.navy),
                const SizedBox(width: 8),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('Evolution of Validations',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: t.text)),
                      Text('Number of alerts validated per day',
                          style: TextStyle(fontSize: 11, color: t.muted)),
                    ])),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                      color: t.scaffold,
                      border: Border.all(color: t.border),
                      borderRadius: BorderRadius.circular(8)),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _chartRange,
                      style: TextStyle(fontSize: 12, color: t.text),
                      dropdownColor: t.card,
                      items: [
                        DropdownMenuItem(
                            value: '7days',
                            child: Text('Last 7 days',
                                style: TextStyle(color: t.text))),
                        DropdownMenuItem(
                            value: '30days',
                            child: Text('Last 30 days',
                                style: TextStyle(color: t.text))),
                      ],
                      onChanged: (v) => setState(() => _chartRange = v!),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 20),
              SizedBox(
                height: 200,
                child: _LineChart(points: _buildChartPoints()),
              ),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(width: 28, height: 2, color: t.navy),
                const SizedBox(width: 6),
                Icon(Icons.circle, size: 7, color: t.navy),
                const SizedBox(width: 6),
                Text('Validations',
                    style: TextStyle(fontSize: 11, color: t.muted)),
              ]),
            ]),
          ),
          const SizedBox(height: 20),
          Row(children: [
            Icon(Icons.check_circle_outline, size: 16, color: t.green),
            const SizedBox(width: 6),
            Text('Validated Alerts (${_solved.length})',
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700, color: t.text)),
          ]),
          const SizedBox(height: 2),
          Text('Detailed list of alerts validated by ${_selected!.fullName}',
              style: TextStyle(fontSize: 12, color: t.muted)),
          const SizedBox(height: 12),
          if (_solved.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 30),
              alignment: Alignment.center,
              child: Text('No validated alerts yet',
                  style: TextStyle(fontSize: 14, color: t.muted)),
            )
          else
            ..._solved.map((a) => _ValidatedAlertRow(alert: a)),
        ],
      ]),
    );
  }
}

class _PerfStatRow extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _PerfStatRow(
      {required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
            child: Text(label,
                style: const TextStyle(fontSize: 10, color: _muted))),
        Text('$value',
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: color)),
      ]);
}

class _TypeStats {
  final int validated, notValidated;
  const _TypeStats({required this.validated, required this.notValidated});
}

class _ValidatedAlertRow extends StatelessWidget {
  final AlertModel alert;
  const _ValidatedAlertRow({required this.alert});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final clr = _typeColor(alert.type);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
          color: t.card,
          border: Border.all(color: t.border),
          borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
              color: clr.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(6)),
          child: Text(_typeLabel(alert.type),
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, color: clr)),
        ),
        const SizedBox(width: 10),
        Expanded(
            child: Text(
                '${alert.usine} — C${alert.convoyeur} — P${alert.poste}',
                style: TextStyle(fontSize: 12, color: t.text))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
              color: t.greenLt, borderRadius: BorderRadius.circular(99)),
          child: Text('Validated',
              style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w700, color: t.green)),
        ),
      ]),
    );
  }
}

class _ChartPoint {
  final DateTime day;
  final double value;
  const _ChartPoint({required this.day, required this.value});
}

class _LineChart extends StatefulWidget {
  final List<_ChartPoint> points;
  final double progress;
  final Color? color;
  final Color? fillColor;
  final Color? gridColor;
  final Color? labelColor;
  const _LineChart({
    required this.points,
    this.progress = 1,
    this.color,
    this.fillColor,
    this.gridColor,
    this.labelColor,
  });

  @override
  State<_LineChart> createState() => _LineChartState();
}

class _LineChartState extends State<_LineChart> {
  int? _selectedIndex;

  int? _nearestPoint(Size size, Offset localPosition) {
    if (widget.points.isEmpty) return null;
    const leftPad = 36.0;
    const rightPad = 16.0;
    final chartW = size.width - leftPad - rightPad;
    final n = widget.points.length;
    if (chartW <= 0) return null;
    final ratio = ((localPosition.dx - leftPad) / chartW).clamp(0.0, 1.0);
    return (ratio * (n - 1)).round().clamp(0, n - 1);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (details) {
          setState(() {
            _selectedIndex = _nearestPoint(
              Size(width, constraints.maxHeight),
              details.localPosition,
            );
          });
        },
        child: Stack(children: [
          CustomPaint(
            painter: _LineChartPainter(
              points: widget.points,
              progress: widget.progress,
              color: widget.color ?? t.navy,
              fillColor: widget.fillColor ?? t.navy,
              gridColor: widget.gridColor ?? t.border,
              labelColor: widget.labelColor ?? t.muted,
              dotBorderColor: t.card,
              selectedIndex: _selectedIndex,
            ),
            size: const Size(double.infinity, 200),
          ),
          if (_selectedIndex != null && widget.points.isNotEmpty)
            _LineChartTooltip(
              point: widget.points[_selectedIndex!],
              left: _tooltipLeft(width, _selectedIndex!, widget.points.length),
            ),
        ]),
      );
    });
  }

  double _tooltipLeft(double width, int index, int count) {
    const leftPad = 36.0;
    const rightPad = 16.0;
    final chartW = width - leftPad - rightPad;
    final x =
        leftPad + (count == 1 ? chartW / 2 : index / (count - 1) * chartW);
    return (x - 58).clamp(6.0, math.max(6.0, width - 116));
  }
}

class _LineChartPainter extends CustomPainter {
  final List<_ChartPoint> points;
  final double progress;
  final Color color;
  final Color fillColor;
  final Color gridColor;
  final Color labelColor;
  final Color dotBorderColor;
  final int? selectedIndex;
  _LineChartPainter({
    required this.points,
    required this.progress,
    required this.color,
    required this.fillColor,
    required this.gridColor,
    required this.labelColor,
    required this.dotBorderColor,
    this.selectedIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    const leftPad = 36.0;
    const rightPad = 16.0;
    const topPad = 10.0;
    const bottomPad = 28.0;

    final chartW = size.width - leftPad - rightPad;
    final chartH = size.height - topPad - bottomPad;

    final maxVal = points.map((p) => p.value).reduce((a, b) => a > b ? a : b);
    final yMax = maxVal < 1 ? 1.0 : maxVal;
    final n = points.length;

    final gridPaint = Paint()
      ..color = gridColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (int i = 0; i <= 4; i++) {
      final y = topPad + chartH * (1 - i / 4);
      canvas.drawLine(
          Offset(leftPad, y), Offset(leftPad + chartW, y), gridPaint);
      final textPainter = TextPainter(
        text: TextSpan(
            text: (yMax * i / 4).toStringAsFixed(0),
            style: TextStyle(fontSize: 9, color: labelColor)),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(canvas, Offset(0, y - textPainter.height / 2));
    }

    Offset pos(int i) {
      final x = leftPad + (n == 1 ? chartW / 2 : i / (n - 1) * chartW);
      final y = topPad + chartH * (1 - ((points[i].value * progress) / yMax));
      return Offset(x, y);
    }

    final fillPath = Path();
    fillPath.moveTo(leftPad, topPad + chartH);
    for (int i = 0; i < n; i++) {
      fillPath.lineTo(pos(i).dx, pos(i).dy);
    }
    fillPath.lineTo(pos(n - 1).dx, topPad + chartH);
    fillPath.close();

    canvas.drawPath(
        fillPath,
        Paint()
          ..shader = LinearGradient(
            colors: [
              fillColor.withValues(alpha: .18),
              color.withValues(alpha: .015)
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ).createShader(Rect.fromLTWH(0, topPad, size.width, chartH)));

    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final linePath = Path()..moveTo(pos(0).dx, pos(0).dy);
    for (int i = 1; i < n; i++) {
      final p0 = pos(i - 1);
      final p1 = pos(i);
      final cx = (p0.dx + p1.dx) / 2;
      linePath.cubicTo(cx, p0.dy, cx, p1.dy, p1.dx, p1.dy);
    }
    canvas.drawPath(linePath, linePaint);

    final dotPaint = Paint()..color = color;
    final dotBorder = Paint()
      ..color = dotBorderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final dateSteps = n <= 10 ? 1 : (n / 7).ceil();

    for (int i = 0; i < n; i++) {
      final p = pos(i);
      final isSelected = i == selectedIndex;
      final glowPaint = Paint()
        ..color = color.withValues(alpha: isSelected ? 0.42 : 0.20)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, isSelected ? 9 : 5);
      canvas.drawCircle(p, isSelected ? 9 : 6, glowPaint);
      canvas.drawCircle(p, isSelected ? 5 : 4, dotPaint);
      canvas.drawCircle(p, 4, dotBorder);

      if (i % dateSteps == 0 || i == n - 1) {
        final d = points[i].day;
        final label = '${d.day} ${_monthAbbr(d.month)}';
        final tp = TextPainter(
          text: TextSpan(
              text: label, style: TextStyle(fontSize: 9, color: labelColor)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(p.dx - tp.width / 2, topPad + chartH + 6));
      }
    }
  }

  String _monthAbbr(int m) {
    const abbr = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return abbr[m];
  }

  @override
  bool shouldRepaint(_LineChartPainter old) =>
      old.points != points ||
      old.progress != progress ||
      old.color != color ||
      old.fillColor != fillColor ||
      old.gridColor != gridColor ||
      old.labelColor != labelColor ||
      old.dotBorderColor != dotBorderColor ||
      old.selectedIndex != selectedIndex;
}

class _LineChartTooltip extends StatelessWidget {
  final _ChartPoint point;
  final double left;
  const _LineChartTooltip({required this.point, required this.left});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Positioned(
      top: 8,
      left: left,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutBack,
        builder: (context, value, child) {
          return Transform.scale(
            scale: 0.86 + value * 0.14,
            child: Opacity(opacity: value.clamp(0.0, 1.0), child: child),
          );
        },
        child: Container(
          width: 116,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: t.text,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: t.text.withValues(alpha: 0.18),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${point.value.toInt()} resolved',
                style: TextStyle(
                    color: t.card, fontSize: 12, fontWeight: FontWeight.w900)),
            const SizedBox(height: 2),
            Text('${point.day.day}/${point.day.month}/${point.day.year}',
                style: TextStyle(
                    color: t.card.withValues(alpha: 0.74),
                    fontSize: 10,
                    fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    );
  }
}

class _AssignmentsSubTab extends StatefulWidget {
  final List<UserModel> supervisors;
  final Future<void> Function()? onRefresh;
  const _AssignmentsSubTab(
      {super.key, required this.supervisors, this.onRefresh});

  @override
  State<_AssignmentsSubTab> createState() => _AssignmentsSubTabState();
}

class _AssignmentsSubTabState extends State<_AssignmentsSubTab> {
  List<Factory> _factories = [];
  bool _loading = true;
  StreamSubscription<List<Factory>>? _factoriesSub;

  @override
  void initState() {
    super.initState();
    _factoriesSub = ServiceLocator.instance.hierarchyService
        .getFactories()
        .listen((factories) {
      if (mounted) {
        setState(() {
          _factories = factories;
          _loading = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _factoriesSub?.cancel();
    super.dispose();
  }

  Map<String, List<UserModel>> _groupByFactory() {
    final map = <String, List<UserModel>>{};
    for (var factory in _factories) {
      map[factory.name] =
          widget.supervisors.where((s) => s.usine == factory.name).toList();
    }
    return map;
  }

  List<UserModel> _unassigned() {
    final names = _factories.map((f) => f.name).toSet();
    return widget.supervisors
        .where((s) => s.usine.isEmpty || !names.contains(s.usine))
        .toList();
  }

  String? _locationFor(String factoryName) {
    for (var f in _factories) {
      if (f.name == factoryName) return f.location;
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
      final t = context.appTheme;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(newFactory.isEmpty
            ? '${sup.fullName} unassigned'
            : '${sup.fullName} moved to $newFactory'),
        backgroundColor: t.green,
      ));
      widget.onRefresh?.call();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Failed: ${UserFriendlyError.message(e)}'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const AppLoadingIndicator();

    final t = context.appTheme;
    final grouped = _groupByFactory();
    final unassigned = _unassigned();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Supervisor Assignments',
            style: TextStyle(
                fontSize: 19, fontWeight: FontWeight.w800, color: t.text)),
        const SizedBox(height: 2),
        Text('Drag supervisors between plants · tap × to unassign',
            style: TextStyle(fontSize: 13, color: t.muted)),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
              color: t.card,
              border: Border.all(color: t.border),
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x06000000),
                    blurRadius: 4,
                    offset: Offset(0, 2))
              ]),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.bar_chart, size: 16, color: t.navy),
              const SizedBox(width: 8),
              Text('Assignments by Plant',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: t.text)),
            ]),
            const SizedBox(height: 4),
            Text('Drag a supervisor to a different plant to reassign',
                style: TextStyle(fontSize: 12, color: t.muted)),
            const SizedBox(height: 16),
            ...grouped.entries.map((e) => _buildFactoryCard(t, e.key, e.value)),
            if (unassigned.isNotEmpty) _buildUnassignedCard(t, unassigned),
          ]),
        ),
      ]),
    );
  }

  Widget _buildFactoryCard(
      AppTheme t, String factoryName, List<UserModel> sups) {
    final location = _locationFor(factoryName);
    return DragTarget<UserModel>(
      onWillAcceptWithDetails: (d) => d.data.usine != factoryName,
      onAcceptWithDetails: (d) => _reassign(d.data, factoryName),
      builder: (context, candidates, _) {
        final hovering = candidates.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: hovering ? t.navy.withValues(alpha: .08) : t.scaffold,
              border: Border.all(
                  color: hovering ? t.navy : t.border, width: hovering ? 2 : 1),
              borderRadius: BorderRadius.circular(10)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(factoryName,
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: t.text)),
                    if (location != null && location.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(location,
                          style: TextStyle(fontSize: 12, color: t.muted)),
                    ],
                  ])),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                    color: sups.isEmpty ? t.scaffold : t.navyLt,
                    borderRadius: BorderRadius.circular(99)),
                child: Text(
                    sups.isEmpty
                        ? '0 supervisors'
                        : '${sups.length} supervisor${sups.length > 1 ? 's' : ''}',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: sups.isEmpty ? t.muted : t.navy)),
              ),
            ]),
            const SizedBox(height: 10),
            if (sups.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                    border: Border.all(
                        color:
                            hovering ? t.navy.withValues(alpha: .4) : t.border),
                    borderRadius: BorderRadius.circular(8)),
                child: Center(
                  child: Text(
                      hovering
                          ? 'Drop here to assign'
                          : 'No supervisor assigned',
                      style: TextStyle(
                          fontSize: 12,
                          color: hovering ? t.navy : t.muted,
                          fontStyle:
                              hovering ? FontStyle.normal : FontStyle.italic)),
                ),
              )
            else
              Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: sups
                      .map((s) =>
                          _SupChip(sup: s, onRemove: () => _reassign(s, '')))
                      .toList()),
          ]),
        );
      },
    );
  }

  Widget _buildUnassignedCard(AppTheme t, List<UserModel> sups) {
    return DragTarget<UserModel>(
      onWillAcceptWithDetails: (d) => d.data.usine.isNotEmpty,
      onAcceptWithDetails: (d) => _reassign(d.data, ''),
      builder: (context, candidates, _) {
        final hovering = candidates.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: hovering
                  ? t.orange.withValues(alpha: .08)
                  : t.orangeLt.withValues(alpha: .5),
              border: Border.all(
                  color: hovering ? t.orange : t.orange.withValues(alpha: .35),
                  width: hovering ? 2 : 1),
              borderRadius: BorderRadius.circular(10)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text('Unassigned',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: t.orange)),
                    const SizedBox(height: 2),
                    Text('Not assigned to any plant',
                        style: TextStyle(fontSize: 12, color: t.muted)),
                  ])),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                    color: t.orangeLt, borderRadius: BorderRadius.circular(99)),
                child: Text(
                    '${sups.length} supervisor${sups.length > 1 ? 's' : ''}',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: t.orange)),
              ),
            ]),
            const SizedBox(height: 10),
            Wrap(
                spacing: 8,
                runSpacing: 8,
                children: sups.map((s) => _SupChip(sup: s)).toList()),
          ]),
        );
      },
    );
  }
}

class _SupChip extends StatelessWidget {
  final UserModel sup;
  final VoidCallback? onRemove;
  final VoidCallback? onTap;
  final bool selected;
  const _SupChip({
    required this.sup,
    this.onRemove,
    this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final chip = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: EdgeInsets.only(
              left: 10, right: onRemove != null ? 6 : 12, top: 6, bottom: 6),
          decoration: BoxDecoration(
            color: selected ? t.navy : t.navyLt,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? t.navy : t.navy.withValues(alpha: 0.12),
            ),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.person_outline,
                size: 13, color: selected ? Colors.white : t.navy),
            const SizedBox(width: 6),
            Text(sup.fullName,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : t.navy)),
            if (onRemove != null) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onRemove,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                      color: (selected ? Colors.white : t.navy)
                          .withValues(alpha: .15),
                      shape: BoxShape.circle),
                  child: Icon(Icons.close,
                      size: 11, color: selected ? Colors.white : t.navy),
                ),
              ),
            ],
          ]),
        ),
      ),
    );

    return Draggable<UserModel>(
      data: sup,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
              color: t.navy,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                    color: t.navy.withValues(alpha: .35),
                    blurRadius: 8,
                    offset: const Offset(0, 3))
              ]),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.person_outline, size: 13, color: Colors.white),
            const SizedBox(width: 6),
            Text(sup.fullName,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white)),
          ]),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: chip),
      child: chip,
    );
  }
}

Widget _emptySups() => Center(
        child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
          Icon(Icons.people_outline, size: 52, color: _muted),
          SizedBox(height: 12),
          Text('No supervisors yet',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600, color: _muted)),
          SizedBox(height: 6),
          Text('Tap "Add Supervisor" to create an account',
              style: TextStyle(fontSize: 12, color: _muted)),
        ]));

class _SupervisorCard extends StatefulWidget {
  final UserModel supervisor;
  final List<AlertModel> alerts;
  final List<Factory> factories;
  final Future<void> Function() onRefresh;
  final VoidCallback onDelete;
  const _SupervisorCard(
      {required this.supervisor,
      required this.alerts,
      required this.factories,
      required this.onDelete,
      required this.onRefresh});
  @override
  State<_SupervisorCard> createState() => _SupervisorCardState();
}

class _SupervisorCardState extends State<_SupervisorCard> {
  bool _expanded = false;

  Future<void> _showDeleteConfirmDialog(BuildContext context) async {
    final sup = widget.supervisor;
    return showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: context.appTheme.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child:
                    const Icon(Icons.warning_outlined, color: _red, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Delete Supervisor',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: _navy,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sup.fullName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _red,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                border: Border.all(color: _red.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: _red, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This action cannot be undone. All associated data will be permanently removed.',
                      style: TextStyle(
                        fontSize: 12,
                        color: _red.withValues(alpha: 0.8),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            RichText(
              text: TextSpan(
                style: const TextStyle(fontSize: 13, color: _text, height: 1.6),
                children: [
                  const TextSpan(
                    text: 'You are about to delete: ',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(
                    text: sup.fullName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: _navy,
                    ),
                  ),
                  const TextSpan(text: ' from '),
                  TextSpan(
                    text: sup.usine,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: _navy,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: _muted, fontWeight: FontWeight.w600),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(dialogCtx);
              widget.onDelete();
            },
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text(
              'Delete Permanently',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _red,
              foregroundColor: _white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showModifyDialog(BuildContext context) async {
    final sup = widget.supervisor;
    final firstCtrl = TextEditingController(text: sup.firstName);
    final lastCtrl = TextEditingController(text: sup.lastName);
    final emailCtrl = TextEditingController(text: sup.email);
    final phoneCtrl = TextEditingController(text: sup.phone);
    final usineChoices = <String>{
      sup.usine,
      ...widget.factories.map((f) => f.name),
    }.toList()
      ..sort();
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
                        value: selectedUsine,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: usineChoices
                            .map((u) =>
                                DropdownMenuItem(value: u, child: Text(u)))
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
                                      'First name, last name, and email are required')),
                            );
                            return;
                          }
                          if (!email.contains('@')) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Please enter a valid email')),
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
                                content:
                                    Text('Supervisor updated successfully'),
                                backgroundColor: _green,
                              ),
                            );
                          } catch (e) {
                            if (!mounted) return;
                            setDialogState(() => saving = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text(
                                      'Update failed: ${UserFriendlyError.message(e)}')),
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
    final sup = widget.supervisor;
    final solved = widget.alerts
        .where((a) =>
            a.status == 'validee' &&
            (a.superviseurId == sup.id || a.assistantId == sup.id))
        .toList();
    final inProg = widget.alerts
        .where((a) => a.status == 'en_cours' && a.superviseurId == sup.id)
        .length;
    final withTime = solved.where((a) => a.elapsedTime != null).toList();
    final avgMin = withTime.isEmpty
        ? null
        : withTime.fold(0, (s, a) => s + (a.elapsedTime ?? 0)) ~/
            withTime.length;
    final sc = sup.isActive ? _green : _red;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
          color: context.appTheme.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.appTheme.border),
          boxShadow: const [
            BoxShadow(
                color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 1))
          ]),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Stack(children: [
              Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                      color: _navyLt, borderRadius: BorderRadius.circular(12)),
                  child:
                      const Center(child: Icon(Icons.engineering, size: 24))),
              Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                          color: sc,
                          shape: BoxShape.circle,
                          border: Border.all(color: _white, width: 2)))),
            ]),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Row(children: [
                    Expanded(
                        child: Text(sup.fullName,
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: _navy))),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                          color: sc.withOpacity(.1),
                          border: Border.all(color: sc),
                          borderRadius: BorderRadius.circular(99)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                                color: sc, shape: BoxShape.circle)),
                        const SizedBox(width: 4),
                        Text(sup.isActive ? 'Active' : 'Absent',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: sc)),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 2),
                  Text(sup.email,
                      style: const TextStyle(fontSize: 11, color: _muted)),
                  Row(children: [
                    const Icon(Icons.phone, size: 12, color: _muted),
                    const SizedBox(width: 3),
                    Text(sup.phone.isEmpty ? 'No phone' : sup.phone,
                        style: const TextStyle(fontSize: 11, color: _muted)),
                    const SizedBox(width: 10),
                    const Icon(Icons.factory, size: 12, color: _muted),
                    const SizedBox(width: 3),
                    Text(sup.usine,
                        style: const TextStyle(fontSize: 11, color: _muted)),
                  ]),
                  if (sup.hiredDate != null)
                    Row(children: [
                      const Icon(Icons.calendar_today, size: 12, color: _muted),
                      const SizedBox(width: 3),
                      Text('Hired: ${_fmtDate(sup.hiredDate!)}',
                          style: const TextStyle(fontSize: 11, color: _muted)),
                    ]),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 6, children: [
                    _MiniChip(Icons.check_circle_outline,
                        '${solved.length} fixed', _green),
                    _MiniChip(Icons.timer, '$inProg claimed', _blue),
                    if (avgMin != null)
                      _MiniChip(
                          Icons.av_timer, 'Avg ${_fmtMin(avgMin)}', _orange),
                  ]),
                ])),
            Column(children: [
              if (solved.isNotEmpty)
                IconButton(
                  onPressed: () => setState(() => _expanded = !_expanded),
                  icon: Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: _navy),
                ),
              IconButton(
                onPressed: () => _showModifyDialog(context),
                icon: const Icon(Icons.edit, color: _navy, size: 20),
                tooltip: 'Modify Supervisor',
              ),
              IconButton(
                onPressed: () => _showDeleteConfirmDialog(context),
                icon: const Icon(Icons.delete_outline, color: _red, size: 20),
                tooltip: 'Delete Supervisor',
              ),
            ]),
          ]),
        ),
        if (_expanded && solved.isNotEmpty) ...[
          Divider(height: 1, color: _border),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('FIXED CASES HISTORY',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: _muted,
                        letterSpacing: 1.2)),
                const SizedBox(height: 10),
                ...solved.map((a) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: const Color(0xFFF0FDF4),
                          border: Border.all(color: const Color(0xFFBBF7D0)),
                          borderRadius: BorderRadius.circular(8)),
                      child: Row(children: [
                        Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                                color: _typeColor(a.type),
                                shape: BoxShape.circle)),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text('${_typeLabel(a.type)} — ${a.description}',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: _navy),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              Text(
                                  '${a.usine} · Line ${a.convoyeur} · Post ${a.poste}',
                                  style: const TextStyle(
                                      fontSize: 10, color: _muted)),
                            ])),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                              color: const Color(0xFFDCFCE7),
                              borderRadius: BorderRadius.circular(6)),
                          child: Text(
                              a.elapsedTime != null
                                  ? _fmtMin(a.elapsedTime!)
                                  : '-',
                              style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: _green)),
                        ),
                      ]),
                    )),
              ],
            ),
          ),
        ],
      ]),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip(this.label, this.color);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
            color: color.withOpacity(.1),
            border: Border.all(color: color),
            borderRadius: BorderRadius.circular(99)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, color: color)),
        ]),
      );
}

class _MiniChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _MiniChip(this.icon, this.label, this.color);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: color.withOpacity(.08),
            border: Border.all(color: color.withOpacity(.4)),
            borderRadius: BorderRadius.circular(6)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, color: color)),
        ]),
      );
}

class SheetField extends StatelessWidget {
  final String label, hint;
  final TextEditingController ctrl;
  final bool obscure;
  final TextInputType keyboard;
  const SheetField(this.label, this.ctrl, this.hint,
      {this.obscure = false, this.keyboard = TextInputType.text});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SheetLabel(label),
          TextField(
            controller: ctrl,
            obscureText: obscure,
            keyboardType: keyboard,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: _muted),
              filled: true,
              fillColor: context.appTheme.scaffold,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(9),
                  borderSide: const BorderSide(color: _border)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(9),
                  borderSide: const BorderSide(color: _border)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(9),
                  borderSide: const BorderSide(color: _navy, width: 1.5)),
            ),
          ),
          const SizedBox(height: 14),
        ],
      );
}

class SheetLabel extends StatelessWidget {
  final String text;
  const SheetLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: _muted,
                letterSpacing: 1.3)),
      );
}
