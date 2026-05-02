// lib/screens/alert_tree_visualization.dart
//
// Modern, fluid alert tree:
//   • InteractiveViewer (pinch-zoom + pan) replacing manual Transform.scale.
//   • Curved Bezier connectors between layers (BezierConnectorPainter).
//   • Card-style nodes with status badges and selection ring (TreeNodeCard).
//   • Modal DraggableScrollableSheet for alert detail (showTreeAlertSheet).
//   • Search + filter + density + tree/heatmap toggle (TreeFilterBar).
//   • Live status header with active counts and pulsing "Live" dot.
//   • Real-time ripple animation on stations that just received a new alert.
//   • AI assignment ON/OFF/Logs surfaced as a collapsible bottom pill.
//
// Data flow unchanged from the legacy implementation:
//   HierarchyService.getFactories() → factories list
//   widget.alerts (passed from AdminDashboardScreen) → alert counts per location
//   AIAssignmentService.instance → AI auto-assignment + logs

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/alert_model.dart';
import '../models/hierarchy_model.dart';
import '../services/ai_assignment_service.dart';
import '../services/hierarchy_service.dart';
import '../services/work_instruction_service.dart';
import '../theme.dart';
import '../utils/alert_meta.dart';
import '../widgets/ai_logs_panel.dart';
import 'widgets/tree_alert_sheet.dart';
import 'widgets/tree_connector_painter.dart';
import 'widgets/tree_filter_bar.dart';
import 'widgets/tree_heatmap_view.dart';
import 'widgets/tree_node_card.dart';

// Accent palette retained for the AI ON segment.
const _green = Color(0xFF16A34A);

// =============================================================================
// AlertNode — public model kept for backward compat with anything else that
// might import it from this file. The new tree uses local layout records but
// the shape is the same.
// =============================================================================
class AlertNode {
  final String id;
  final String label;
  final int errorCount;
  final List<AlertNode> children;
  final Map<String, dynamic>? alertData;
  final String type; // 'usine', 'conveyor', 'workstation'

  const AlertNode({
    required this.id,
    required this.label,
    this.errorCount = 0,
    this.children = const [],
    this.alertData,
    required this.type,
  });

  bool get hasError => errorCount > 0;
}

// =============================================================================
// Public widget
// =============================================================================
class AlertTreeVisualization extends StatefulWidget {
  final List<AlertModel> alerts;
  final Future<void> Function(AlertModel alert)? onAssignAssistant;

  const AlertTreeVisualization({
    super.key,
    required this.alerts,
    this.onAssignAssistant,
  });

  @override
  State<AlertTreeVisualization> createState() => _AlertTreeVisualizationState();
}

class _AlertTreeVisualizationState extends State<AlertTreeVisualization>
    with TickerProviderStateMixin {
  // ---------------- Data ----------------
  final HierarchyService _hierarchyService = HierarchyService();
  final WorkInstructionService _workInstructionService =
      WorkInstructionService();
  StreamSubscription<List<Factory>>? _hierarchySub;
  List<Factory> _factories = [];

  // ---------------- Selection ----------------
  String? _selectedUsineId;
  String? _selectedConveyorId;

  // ---------------- Filter / view state ----------------
  TreeFilterState _filter = const TreeFilterState();

  // ---------------- AI panel ----------------
  bool _aiPanelExpanded = false;
  bool _showAILogsPanel = false;

  // ---------------- Pinch-zoom ----------------
  final TransformationController _transform = TransformationController();
  late final AnimationController _zoomBtnAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );
  Matrix4 _zoomBtnFrom = Matrix4.identity();
  Matrix4 _zoomBtnTo = Matrix4.identity();

  // ---------------- Connector flow animation ----------------
  late final AnimationController _flowAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat();

  // ---------------- Live ticker (for "Updated x ago") ----------------
  late final Timer _ticker;
  DateTime _lastUpdate = DateTime.now();

  // ---------------- Ripple tracking ----------------
  Set<String> _knownAlertIds = {};
  final Map<String, DateTime> _lastRippleAt = {};
  final Set<String> _rippleStations = {}; // location keys currently rippling

  AppTheme get _t => context.appTheme;

  // ---------------------------------------------------------------------------
  @override
  void initState() {
    super.initState();
    _knownAlertIds = widget.alerts.map((a) => a.id).toSet();

    _hierarchySub = _hierarchyService.getFactories().listen((factories) {
      if (!mounted) return;
      setState(() {
        _factories = factories;
        _lastUpdate = DateTime.now();
      });
    });

    AIAssignmentService.instance.init().then((_) {
      if (!mounted) return;
      setState(() {});
      AIAssignmentService.instance.processAlerts(widget.alerts);
    });
    AIAssignmentService.instance.addListener(_onAIChange);

    _zoomBtnAnim.addListener(_onZoomBtnTick);

    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant AlertTreeVisualization old) {
    super.didUpdateWidget(old);
    if (!identical(widget.alerts, old.alerts)) {
      _detectNewAlertsForRipple();
      AIAssignmentService.instance.processAlerts(widget.alerts);
      _lastUpdate = DateTime.now();
    }
  }

  @override
  void dispose() {
    _ticker.cancel();
    _hierarchySub?.cancel();
    AIAssignmentService.instance.removeListener(_onAIChange);
    _zoomBtnAnim.removeListener(_onZoomBtnTick);
    _zoomBtnAnim.dispose();
    _flowAnim.dispose();
    _transform.dispose();
    super.dispose();
  }

  void _onAIChange() {
    if (mounted) setState(() {});
  }

  // ---------------------------------------------------------------------------
  // Ripple handling: pulse a station node when a new alert lands there.
  // ---------------------------------------------------------------------------
  void _detectNewAlertsForRipple() {
    final newIds = widget.alerts.map((a) => a.id).toSet();
    final added = newIds.difference(_knownAlertIds);
    if (added.isEmpty) {
      _knownAlertIds = newIds;
      return;
    }
    final now = DateTime.now();
    for (final a in widget.alerts.where((a) => added.contains(a.id))) {
      final key = _locationKey(a.usine, a.convoyeur, a.poste);
      final last = _lastRippleAt[key];
      if (last != null && now.difference(last) < const Duration(seconds: 2)) {
        continue;
      }
      _lastRippleAt[key] = now;
      _rippleStations.add(key);
      Future.delayed(const Duration(milliseconds: 1600), () {
        if (!mounted) return;
        setState(() => _rippleStations.remove(key));
      });
    }
    _knownAlertIds = newIds;
  }

  String _locationKey(String usine, int conveyor, int station) =>
      '$usine|$conveyor|$station';

  Color _nodeAccent(
    AppTheme t, {
    required int activeCount,
    required int inProgressCount,
    required bool isCritical,
    required Color idle,
  }) {
    final unclaimedCount =
        (activeCount - inProgressCount).clamp(0, activeCount);
    if (isCritical || unclaimedCount > 0) return t.red;
    if (inProgressCount > 0) return t.yellow;
    return idle;
  }

  // ---------------------------------------------------------------------------
  // Zoom controls
  // ---------------------------------------------------------------------------
  void _onZoomBtnTick() {
    _transform.value = Matrix4Tween(begin: _zoomBtnFrom, end: _zoomBtnTo)
        .animate(
            CurvedAnimation(parent: _zoomBtnAnim, curve: Curves.easeOutCubic))
        .value;
  }

  void _animateZoom(double factor) {
    final current = _transform.value.clone();
    final scale = current.getMaxScaleOnAxis();
    final next = (scale * factor).clamp(0.5, 3.0);
    if ((next - scale).abs() < 0.01) return;
    _zoomBtnFrom = current;
    _zoomBtnTo = Matrix4.diagonal3Values(next, next, next);
    _zoomBtnAnim.forward(from: 0);
  }

  void _resetZoom() {
    _zoomBtnFrom = _transform.value.clone();
    _zoomBtnTo = Matrix4.identity();
    _zoomBtnAnim.forward(from: 0);
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final t = _t;
    final tree = _buildTreeData();

    return Stack(
      children: [
        Container(
          color: t.scaffold,
          child: Column(
            children: [
              _liveHeader(t, tree),
              TreeFilterBar(
                state: _filter,
                onChanged: (next) => setState(() => _filter = next),
              ),
              if (_filter.hasFilters) _filterSummaryBar(t, tree),
              Expanded(
                child: tree.factories.isEmpty
                    ? _emptyState(t)
                    : (_filter.heatmap
                        ? _buildHeatmap(tree)
                        : _buildTreeCanvas(tree)),
              ),
            ],
          ),
        ),
        if (!_filter.heatmap && tree.factories.isNotEmpty)
          Positioned(
            right: 16,
            bottom: 88,
            child: _zoomControls(t),
          ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: _aiBottomPill(t),
        ),
        if (_showAILogsPanel)
          AILogsPanel(
            onClose: () => setState(() => _showAILogsPanel = false),
            hostSize: MediaQuery.of(context).size,
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Live status header
  // ---------------------------------------------------------------------------
  Widget _liveHeader(AppTheme t, _TreeData tree) {
    final activeTotal = tree.totalActive;
    final stationsAffected = tree.stationsWithActive;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        color: t.card,
        border: Border(bottom: BorderSide(color: t.border)),
      ),
      child: Row(
        children: [
          _LivePulseDot(color: t.green),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.account_tree, size: 16, color: t.navy),
                    const SizedBox(width: 6),
                    Text(
                      _scopeTitle(),
                      style: TextStyle(
                        color: t.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '$activeTotal active across $stationsAffected '
                  'station${stationsAffected == 1 ? '' : 's'} '
                  '· Updated ${_relative(_lastUpdate)}',
                  style: TextStyle(color: t.muted, fontSize: 11),
                ),
              ],
            ),
          ),
          if (_selectedUsineId != null || _selectedConveyorId != null)
            IconButton(
              tooltip: 'Reset view',
              icon: Icon(Icons.close, size: 18, color: t.muted),
              onPressed: () => setState(() {
                _selectedUsineId = null;
                _selectedConveyorId = null;
                _resetZoom();
              }),
            ),
        ],
      ),
    );
  }

  String _scopeTitle() {
    if (_selectedUsineId == null) return 'All Plants';
    final f = _factoryById(_selectedUsineId!);
    if (f == null) return 'All Plants';
    if (_selectedConveyorId == null) return f.name;
    final c = f.conveyors.values.firstWhere(
      (c) => '${f.id}|${c.id}' == _selectedConveyorId,
      orElse: () => f.conveyors.values.first,
    );
    return '${f.name} · Conveyor ${c.number}';
  }

  Widget _filterSummaryBar(AppTheme t, _TreeData tree) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: t.navyLt.withValues(alpha: 0.5),
      child: Row(
        children: [
          Icon(Icons.filter_alt, size: 14, color: t.navy),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${tree.matchingNodeCount} of ${tree.totalNodeCount} nodes match filters',
              style: TextStyle(
                color: t.navy,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: () => setState(() => _filter = const TreeFilterState()),
            child: Text(
              'Clear',
              style: TextStyle(color: t.navy, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tree canvas (InteractiveViewer + Stack + connectors)
  // ---------------------------------------------------------------------------
  Widget _buildTreeCanvas(_TreeData tree) {
    final layout = _layoutTree(tree);
    return InteractiveViewer(
      transformationController: _transform,
      panEnabled: true,
      scaleEnabled: true,
      minScale: 0.5,
      maxScale: 3.0,
      boundaryMargin: const EdgeInsets.all(400),
      constrained: false,
      child: SizedBox(
        width: layout.size.width,
        height: layout.size.height,
        child: AnimatedBuilder(
          animation: _flowAnim,
          builder: (context, _) {
            return Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: BezierConnectorPainter(
                      edges: layout.edges,
                      inactive: _t.border,
                      active: _t.red.withValues(alpha: 0.7),
                      flowPhase: _flowAnim.value,
                    ),
                  ),
                ),
                ...layout.placements.map((p) => Positioned(
                      left: p.left,
                      top: p.top,
                      child: p.widget,
                    )),
              ],
            );
          },
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Heatmap
  // ---------------------------------------------------------------------------
  Widget _buildHeatmap(_TreeData tree) {
    final cells = <HeatmapCell>[];
    final scopeFactories = _selectedUsineId == null
        ? _factories
        : _factories.where((f) => f.id == _selectedUsineId).toList();

    for (final f in scopeFactories) {
      for (final c in f.conveyors.values) {
        for (final s in c.stations.values) {
          final stationNumber =
              int.tryParse(s.id.replaceAll('station_', '')) ?? 0;
          final stationAlerts = widget.alerts.where((a) =>
              a.usine == f.name &&
              a.convoyeur == c.number &&
              a.poste == stationNumber);
          final active =
              stationAlerts.where((a) => isActiveStatus(a.status)).toList();
          final critical = active.where((a) => a.isCritical).toList();
          if (active.isEmpty && critical.isEmpty) {
            cells.add(HeatmapCell(
              factoryName: f.name,
              conveyor: c.number,
              station: stationNumber,
              label: s.name,
              assetId: s.assetId,
              activeCount: 0,
              inProgressCount: 0,
              criticalCount: 0,
              topAlert: null,
            ));
          } else {
            active.sort((a, b) => b.timestamp.compareTo(a.timestamp));
            cells.add(HeatmapCell(
              factoryName: f.name,
              conveyor: c.number,
              station: stationNumber,
              label: s.name,
              assetId: s.assetId,
              activeCount: active.length,
              inProgressCount:
                  active.where((a) => a.status == 'en_cours').length,
              criticalCount: critical.length,
              topAlert: active.isNotEmpty ? active.first : null,
            ));
          }
        }
      }
    }

    return TreeHeatmapView(
      cells: cells,
      scopeLabel: _selectedUsineId == null ? null : _scopeTitle(),
      onStationTap: (cell) => _showStationActions(
        usine: cell.factoryName,
        convoyeur: cell.conveyor,
        poste: cell.station,
        stationLabel: cell.label,
        assetId: cell.assetId,
        activeAlert: cell.topAlert,
      ),
    );
  }

  void _showStationActions({
    required String usine,
    required int convoyeur,
    required int poste,
    required String stationLabel,
    String? assetId,
    AlertModel? activeAlert,
  }) {
    final t = _t;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: t.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.62,
          minChildSize: 0.34,
          maxChildSize: 0.9,
          builder: (_, controller) {
            return StreamBuilder<List<AlertModel>>(
              stream: _workInstructionService.historyAtLocation(
                usine: usine,
                convoyeur: convoyeur,
                poste: poste,
                assetId: assetId,
              ),
              builder: (context, snapshot) {
                final history = snapshot.data ?? const <AlertModel>[];
                final current = activeAlert ??
                    history.cast<AlertModel?>().firstWhere(
                          (a) => a != null && isActiveStatus(a.status),
                          orElse: () => null,
                        );
                return ListView(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: t.border,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: t.navyLt,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.settings, color: t.navy),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                stationLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: t.text,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                '$usine - Conveyor $convoyeur - Workstation $poste',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: t.muted, fontSize: 12),
                              ),
                              if (assetId != null && assetId.trim().isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: _AssetChip(t: t, assetId: assetId),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (current != null)
                          OutlinedButton.icon(
                            icon: const Icon(Icons.open_in_new, size: 16),
                            label: const Text('Open Alert'),
                            onPressed: () {
                              Navigator.pop(sheetContext);
                              showTreeAlertSheet(context, current);
                            },
                          ),
                        if (current != null && widget.onAssignAssistant != null)
                          FilledButton.icon(
                            icon: const Icon(Icons.group_add, size: 16),
                            label: const Text('Assign Assistant'),
                            onPressed: () async {
                              Navigator.pop(sheetContext);
                              await widget.onAssignAssistant!(current);
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Icon(Icons.history, size: 18, color: t.navy),
                        const SizedBox(width: 8),
                        Text(
                          assetId != null && assetId.trim().isNotEmpty
                              ? 'Asset History'
                              : 'Workstation History',
                          style: TextStyle(
                            color: t.text,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const Spacer(),
                        if (history.isNotEmpty)
                          Text(
                            '${history.length}',
                            style: TextStyle(
                              color: t.muted,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (snapshot.connectionState == ConnectionState.waiting)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (history.isEmpty)
                      _StationEmptyHistory(t: t)
                    else
                      ...history.map((a) => _StationHistoryTile(alert: a)),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Empty state
  // ---------------------------------------------------------------------------
  Widget _emptyState(AppTheme t) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: t.navyLt,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.factory, size: 32, color: t.navy),
            ),
            const SizedBox(height: 14),
            Text(
              'No factories configured',
              style: TextStyle(
                color: t.text,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Add a factory in the Hierarchy tab to start tracking alerts.',
              textAlign: TextAlign.center,
              style: TextStyle(color: t.muted, fontSize: 12.5, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Zoom controls
  // ---------------------------------------------------------------------------
  Widget _zoomControls(AppTheme t) {
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(14),
      color: t.card,
      child: Container(
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: t.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Zoom in',
              onPressed: () => _animateZoom(1.2),
              icon: Icon(Icons.add, color: t.navy),
            ),
            Container(width: 24, height: 1, color: t.border),
            IconButton(
              tooltip: 'Reset',
              onPressed: _resetZoom,
              icon: Icon(Icons.center_focus_strong, color: t.navy, size: 18),
            ),
            Container(width: 24, height: 1, color: t.border),
            IconButton(
              tooltip: 'Zoom out',
              onPressed: () => _animateZoom(0.8),
              icon: Icon(Icons.remove, color: t.navy),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // AI bottom pill
  // ---------------------------------------------------------------------------
  Widget _aiBottomPill(AppTheme t) {
    final isOn = AIAssignmentService.instance.enabled;
    final logCount = AIAssignmentService.instance.logs.length;
    final backendOk = AIAssignmentService.instance.isUsingBackendSettings;

    return Material(
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.2),
      borderRadius: BorderRadius.circular(16),
      color: t.card,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isOn ? t.green.withValues(alpha: 0.5) : t.border,
            width: 1,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: isOn ? t.green : t.navy,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.smart_toy_outlined,
                      size: 16, color: Colors.white),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'AI Assignment',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: t.text,
                            ),
                          ),
                          if (!backendOk) ...[
                            const SizedBox(width: 6),
                            _localFallbackBadge(t),
                          ],
                        ],
                      ),
                      Text(
                        isOn
                            ? 'Auto-assigning new alerts'
                            : 'Manual assignment only',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: isOn ? t.green : t.muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: _aiPanelExpanded ? 'Collapse' : 'Expand',
                  icon: Icon(
                    _aiPanelExpanded ? Icons.expand_more : Icons.expand_less,
                    color: t.navy,
                  ),
                  onPressed: () =>
                      setState(() => _aiPanelExpanded = !_aiPanelExpanded),
                ),
              ],
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: _aiPanelExpanded
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(2, 8, 2, 4),
                      child: Row(
                        children: [
                          _aiSegment(
                            icon: Icons.power_settings_new,
                            label: 'ON',
                            active: isOn,
                            activeColor: _green,
                            onTap: isOn ? null : () => _toggleAI(true),
                          ),
                          const SizedBox(width: 6),
                          _aiSegment(
                            icon: Icons.stop_circle_outlined,
                            label: 'OFF',
                            active: !isOn,
                            activeColor: t.muted,
                            onTap: !isOn ? null : () => _toggleAI(false),
                          ),
                          const SizedBox(width: 6),
                          _aiSegment(
                            icon: Icons.receipt_long,
                            label: 'AI-LOGS',
                            active: _showAILogsPanel,
                            activeColor: t.navy,
                            badge: logCount > 0 ? '$logCount' : null,
                            onTap: () => setState(
                                () => _showAILogsPanel = !_showAILogsPanel),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }

  Widget _localFallbackBadge(AppTheme t) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: t.orangeLt,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: t.orange.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.warning_amber_rounded, size: 9, color: t.orange),
          const SizedBox(width: 3),
          Text(
            'LOCAL FALLBACK',
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w800,
              color: t.orange,
              letterSpacing: 0.25,
            ),
          ),
        ],
      ),
    );
  }

  Widget _aiSegment({
    required IconData icon,
    required String label,
    required bool active,
    required Color activeColor,
    String? badge,
    VoidCallback? onTap,
  }) {
    final t = _t;
    final bg = active ? activeColor : t.scaffold;
    final fg = active ? Colors.white : t.muted;
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(8),
              border:
                  Border.all(color: active ? activeColor : t.border, width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 13, color: fg),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: fg,
                    letterSpacing: 0.3,
                  ),
                ),
                if (badge != null) ...[
                  const SizedBox(width: 5),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: active
                          ? Colors.white.withValues(alpha: 0.25)
                          : activeColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      badge,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: active ? Colors.white : activeColor,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _toggleAI(bool on) async {
    await AIAssignmentService.instance.setEnabled(on);
    if (on) AIAssignmentService.instance.processAlerts(widget.alerts);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(on
            ? 'Global AI ON — auto-assignment enabled'
            : 'Global AI OFF — manual assignment only'),
        backgroundColor: on ? _t.green : _t.muted,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tree data + layout
  // ---------------------------------------------------------------------------
  _TreeData _buildTreeData() {
    // alerts indexed by location
    final activeAtLocation = <String, List<AlertModel>>{};
    final inProgressAtLocation = <String, List<AlertModel>>{};
    final resolvedAtLocation = <String, List<AlertModel>>{};
    final criticalAtLocation = <String, List<AlertModel>>{};
    final topActiveAtLocation = <String, AlertModel>{};

    for (final a in widget.alerts) {
      final key = _locationKey(a.usine, a.convoyeur, a.poste);
      if (a.status == 'disponible' || a.status == 'en_cours') {
        activeAtLocation.putIfAbsent(key, () => []).add(a);
        if (a.status == 'en_cours') {
          inProgressAtLocation.putIfAbsent(key, () => []).add(a);
        }
        if (a.isCritical) {
          criticalAtLocation.putIfAbsent(key, () => []).add(a);
        }
        final cur = topActiveAtLocation[key];
        if (cur == null ||
            (a.status == 'en_cours' && cur.status != 'en_cours') ||
            (a.status == cur.status && a.timestamp.isAfter(cur.timestamp))) {
          topActiveAtLocation[key] = a;
        }
      } else if (a.status == 'validee') {
        resolvedAtLocation.putIfAbsent(key, () => []).add(a);
      }
    }

    int totalActive = 0;
    final affectedStations = <String>{};
    int totalNodes = 0;
    int matchingNodes = 0;
    final search = _filter.search.toLowerCase();

    bool nodeMatchesSearch(String label) =>
        search.isEmpty || label.toLowerCase().contains(search);

    bool alertsMatchFilters(List<AlertModel> alerts) {
      if (_filter.types.isEmpty &&
          _filter.statuses.isEmpty &&
          !_filter.criticalOnly) {
        return true;
      }
      return alerts.any((a) {
        if (_filter.types.isNotEmpty && !_filter.types.contains(a.type)) {
          return false;
        }
        if (_filter.statuses.isNotEmpty &&
            !_filter.statuses.contains(a.status)) {
          return false;
        }
        if (_filter.criticalOnly && !a.isCritical) return false;
        return true;
      });
    }

    for (final a in widget.alerts.where((a) => isActiveStatus(a.status))) {
      totalActive++;
      affectedStations.add(_locationKey(a.usine, a.convoyeur, a.poste));
    }

    final nodes = <_LayoutNode>[];
    for (final f in _factories) {
      totalNodes++;
      int factoryActive = 0;
      int factoryInProgress = 0;
      int factoryResolved = 0;
      int factoryCritical = 0;
      bool factoryMatches = nodeMatchesSearch(f.name);

      final conveyorNodes = <_LayoutNode>[];
      for (final c in f.conveyors.values) {
        totalNodes++;
        int conveyorActive = 0;
        int conveyorInProgress = 0;
        int conveyorResolved = 0;
        int conveyorCritical = 0;
        bool conveyorMatches =
            nodeMatchesSearch('Conveyor ${c.number}') || factoryMatches;

        final stationNodes = <_LayoutNode>[];
        for (final s in c.stations.values) {
          totalNodes++;
          final stationNumber =
              int.tryParse(s.id.replaceAll('station_', '')) ?? 0;
          final key = _locationKey(f.name, c.number, stationNumber);
          final activeList = activeAtLocation[key] ?? const [];
          final inProgressList = inProgressAtLocation[key] ?? const [];
          final resolvedList = resolvedAtLocation[key] ?? const [];
          final criticalList = criticalAtLocation[key] ?? const [];

          factoryActive += activeList.length;
          conveyorActive += activeList.length;
          factoryInProgress += inProgressList.length;
          conveyorInProgress += inProgressList.length;
          factoryResolved += resolvedList.length;
          conveyorResolved += resolvedList.length;
          factoryCritical += criticalList.length;
          conveyorCritical += criticalList.length;

          final matchesText = nodeMatchesSearch(s.name) ||
              nodeMatchesSearch(s.assetId) ||
              conveyorMatches;
          final allLocationAlerts = [
            ...activeList,
            ...resolvedList,
          ];
          final matches = matchesText && alertsMatchFilters(allLocationAlerts);
          if (matches) matchingNodes++;

          stationNodes.add(_LayoutNode(
            id: '${f.id}|${c.id}|${s.id}',
            label: s.name,
            type: 'workstation',
            activeCount: activeList.length,
            inProgressCount: inProgressList.length,
            resolvedCount: resolvedList.length,
            isCritical: criticalList.isNotEmpty,
            matches: matches,
            topActiveAlert: topActiveAtLocation[key],
            payload: {
              'usine': f.name,
              'convoyeur': c.number,
              'poste': stationNumber,
              'assetId': s.assetId,
            },
          ));
        }

        final conveyorAlerts = stationNodes
            .expand((s) =>
                activeAtLocation[_locationKey(
                  f.name,
                  c.number,
                  s.payload['poste'] as int,
                )] ??
                const <AlertModel>[])
            .toList();
        final conveyorMatchesFilters = alertsMatchFilters(conveyorAlerts);
        final conveyorVisible = conveyorMatches && conveyorMatchesFilters;
        if (conveyorVisible) matchingNodes++;
        conveyorNodes.add(_LayoutNode(
          id: '${f.id}|${c.id}',
          label: 'Conveyor ${c.number}',
          type: 'conveyor',
          activeCount: conveyorActive,
          inProgressCount: conveyorInProgress,
          resolvedCount: conveyorResolved,
          isCritical: conveyorCritical > 0,
          matches: conveyorVisible,
          children: stationNodes,
        ));
      }

      final factoryAlerts =
          widget.alerts.where((a) => a.usine == f.name).toList();
      final factoryMatchesFilters = alertsMatchFilters(factoryAlerts);
      final factoryVisible = factoryMatches && factoryMatchesFilters;
      if (factoryVisible) matchingNodes++;

      nodes.add(_LayoutNode(
        id: f.id,
        label: f.name,
        type: 'usine',
        activeCount: factoryActive,
        inProgressCount: factoryInProgress,
        resolvedCount: factoryResolved,
        isCritical: factoryCritical > 0,
        matches: factoryVisible,
        children: conveyorNodes,
      ));
    }

    return _TreeData(
      factories: _factories,
      rootNodes: nodes,
      totalActive: totalActive,
      stationsWithActive: affectedStations.length,
      totalNodeCount: totalNodes,
      matchingNodeCount: matchingNodes,
    );
  }

  Factory? _factoryById(String id) {
    for (final f in _factories) {
      if (f.id == id) return f;
    }
    return null;
  }

  // Layout: compute positions for visible nodes given the current selection.
  _Layout _layoutTree(_TreeData tree) {
    final cardW = _filter.density.cardWidth;
    final cardH = _filter.density.cardHeight;
    const spacingX = 32.0;
    const layerGap = 80.0;
    const padding = 28.0;

    final placements = <_Placement>[];
    final edges = <TreeConnectorEdge>[];

    final t = _t;

    // ---- Layer 1: factories (always shown) ----
    final factoryNodes = tree.rootNodes;
    double rowWidth(int count) =>
        count <= 0 ? 0 : count * cardW + (count - 1) * spacingX;
    final l1Width = rowWidth(factoryNodes.length);
    var cursorX = padding;
    final factoryCenters = <String, Offset>{};
    final factoryY = padding;

    for (final f in factoryNodes) {
      final left = cursorX;
      final selected = _selectedUsineId == f.id;
      final dimmed = !f.matches;
      final accent = _nodeAccent(
        t,
        activeCount: f.activeCount,
        inProgressCount: f.inProgressCount,
        isCritical: f.isCritical,
        idle: t.navy,
      );
      placements.add(_Placement(
        left: left,
        top: factoryY.toDouble(),
        widget: SizedBox(
          width: cardW,
          child: TreeNodeCard(
            icon: Icons.factory,
            title: f.label,
            subtitle:
                '${f.children.length} conveyor${f.children.length == 1 ? '' : 's'}',
            activeCount: f.activeCount,
            inProgressCount: f.inProgressCount,
            resolvedCount: f.resolvedCount,
            hasError: f.activeCount > 0,
            isCritical: f.isCritical,
            isSelected: selected,
            isDimmed: dimmed,
            accent: accent,
            density: _filter.density,
            onTap: () => setState(() {
              if (_selectedUsineId == f.id) {
                _selectedUsineId = null;
                _selectedConveyorId = null;
              } else {
                _selectedUsineId = f.id;
                _selectedConveyorId = null;
              }
            }),
          ),
        ),
      ));
      factoryCenters[f.id] = Offset(left + cardW / 2, factoryY + cardH);
      cursorX += cardW + spacingX;
    }

    var totalWidth = padding * 2 + l1Width;
    var totalHeight = padding + cardH;

    // ---- Layer 2: conveyors of selected factory ----
    if (_selectedUsineId != null) {
      final selectedF = factoryNodes.cast<_LayoutNode?>().firstWhere(
            (f) => f?.id == _selectedUsineId,
            orElse: () => null,
          );
      if (selectedF == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {
            _selectedUsineId = null;
            _selectedConveyorId = null;
          });
        });
        return _Layout(
          placements: placements,
          edges: edges,
          size: Size(totalWidth, totalHeight),
        );
      }
      final conveyors = selectedF.children;
      if (conveyors.isNotEmpty) {
        final l2Width = rowWidth(conveyors.length);
        final visibleContentWidth = l1Width > l2Width ? l1Width : l2Width;
        // Position centered under the parent factory.
        final parentCenter = factoryCenters[selectedF.id]!;
        final conveyorY = factoryY + cardH + layerGap;
        var cx = parentCenter.dx - l2Width / 2;
        // Clamp to keep within a reasonable canvas width.
        cx = cx
            .clamp(padding, padding + visibleContentWidth - l2Width)
            .toDouble();

        final conveyorCenters = <String, Offset>{};
        for (final c in conveyors) {
          final left = cx;
          final selected = _selectedConveyorId == c.id;
          final accent = _nodeAccent(
            t,
            activeCount: c.activeCount,
            inProgressCount: c.inProgressCount,
            isCritical: c.isCritical,
            idle: t.blue,
          );
          placements.add(_Placement(
            left: left,
            top: conveyorY.toDouble(),
            widget: SizedBox(
              width: cardW,
              child: TreeNodeCard(
                icon: Icons.linear_scale,
                title: c.label,
                subtitle:
                    '${c.children.length} station${c.children.length == 1 ? '' : 's'}',
                activeCount: c.activeCount,
                inProgressCount: c.inProgressCount,
                resolvedCount: c.resolvedCount,
                hasError: c.activeCount > 0,
                isCritical: c.isCritical,
                isSelected: selected,
                isDimmed: !c.matches,
                accent: accent,
                density: _filter.density,
                onTap: () => setState(() {
                  _selectedConveyorId =
                      _selectedConveyorId == c.id ? null : c.id;
                }),
              ),
            ),
          ));
          conveyorCenters[c.id] = Offset(left + cardW / 2, conveyorY + cardH);

          edges.add(TreeConnectorEdge(
            from: parentCenter,
            to: Offset(left + cardW / 2, conveyorY.toDouble()),
            active: c.activeCount > 0,
          ));

          cx += cardW + spacingX;
        }
        totalHeight = conveyorY + cardH + padding;
        totalWidth = totalWidth < (padding * 2 + visibleContentWidth)
            ? padding * 2 + visibleContentWidth
            : totalWidth;

        // ---- Layer 3: workstations of selected conveyor ----
        if (_selectedConveyorId != null) {
          final selectedC = conveyors.cast<_LayoutNode?>().firstWhere(
                (c) => c?.id == _selectedConveyorId,
                orElse: () => null,
              );
          if (selectedC == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              setState(() => _selectedConveyorId = null);
            });
            return _Layout(
              placements: placements,
              edges: edges,
              size: Size(totalWidth, totalHeight),
            );
          }
          final stations = selectedC.children;
          if (stations.isNotEmpty) {
            // Stations may be many — wrap into rows of up to 6.
            const perRow = 6;
            final rows = <List<_LayoutNode>>[];
            for (var i = 0; i < stations.length; i += perRow) {
              rows.add(stations.sublist(
                  i, (i + perRow).clamp(0, stations.length).toInt()));
            }

            final parentConveyorCenter = conveyorCenters[selectedC.id]!;
            final stationY = conveyorY + cardH + layerGap;
            var rowY = stationY;
            for (final row in rows) {
              final stationRowWidth = rowWidth(row.length);
              var sx = parentConveyorCenter.dx - stationRowWidth / 2;
              sx = sx.clamp(padding, double.infinity).toDouble();
              for (final s in row) {
                final left = sx;
                final activeAlert = s.topActiveAlert;
                final hasError = s.activeCount > 0;
                final accent = _nodeAccent(
                  t,
                  activeCount: s.activeCount,
                  inProgressCount: s.inProgressCount,
                  isCritical: s.isCritical,
                  idle: t.green,
                );
                final stationKey = _locationKey(
                  s.payload['usine'] as String,
                  s.payload['convoyeur'] as int,
                  s.payload['poste'] as int,
                );
                placements.add(_Placement(
                  left: left,
                  top: rowY.toDouble(),
                  widget: SizedBox(
                    width: cardW,
                    child: TreeNodeCard(
                      icon: Icons.settings,
                      title: s.label,
                      subtitle: hasError
                          ? '${s.activeCount} active alert${s.activeCount == 1 ? '' : 's'}'
                          : 'Healthy',
                      activeCount: s.activeCount,
                      inProgressCount: s.inProgressCount,
                      resolvedCount: s.resolvedCount,
                      hasError: hasError,
                      isCritical: s.isCritical,
                      isSelected: false,
                      isDimmed: !s.matches,
                      ripple: _rippleStations.contains(stationKey),
                      accent: accent,
                      density: _filter.density,
                      onTap: () => _showStationActions(
                        usine: s.payload['usine'] as String,
                        convoyeur: s.payload['convoyeur'] as int,
                        poste: s.payload['poste'] as int,
                        stationLabel: s.label,
                        assetId: s.payload['assetId'] as String?,
                        activeAlert: activeAlert,
                      ),
                    ),
                  ),
                ));

                edges.add(TreeConnectorEdge(
                  from: parentConveyorCenter,
                  to: Offset(left + cardW / 2, rowY.toDouble()),
                  active: hasError,
                ));

                sx += cardW + spacingX;
              }
              rowY += cardH + 24;
              final rowExtent = sx - spacingX + padding;
              totalWidth = totalWidth < rowExtent ? rowExtent : totalWidth;
            }
            totalHeight = rowY + padding;
          }
        }
      }
    }

    return _Layout(
      placements: placements,
      edges: edges,
      size: Size(totalWidth, totalHeight),
    );
  }

  String _relative(DateTime dt) {
    final d = DateTime.now().difference(dt);
    if (d.inSeconds < 60) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }
}

// =============================================================================
// Internal types
// =============================================================================
class _LayoutNode {
  final String id;
  final String label;
  final String type;
  final int activeCount;
  final int inProgressCount;
  final int resolvedCount;
  final bool isCritical;
  final bool matches;
  final List<_LayoutNode> children;
  final AlertModel? topActiveAlert;
  final Map<String, dynamic> payload;

  const _LayoutNode({
    required this.id,
    required this.label,
    required this.type,
    this.activeCount = 0,
    this.inProgressCount = 0,
    this.resolvedCount = 0,
    this.isCritical = false,
    this.matches = true,
    this.children = const [],
    this.topActiveAlert,
    this.payload = const {},
  });
}

class _TreeData {
  final List<Factory> factories;
  final List<_LayoutNode> rootNodes;
  final int totalActive;
  final int stationsWithActive;
  final int totalNodeCount;
  final int matchingNodeCount;

  const _TreeData({
    required this.factories,
    required this.rootNodes,
    required this.totalActive,
    required this.stationsWithActive,
    required this.totalNodeCount,
    required this.matchingNodeCount,
  });
}

class _Placement {
  final double left;
  final double top;
  final Widget widget;
  const _Placement({
    required this.left,
    required this.top,
    required this.widget,
  });
}

class _Layout {
  final List<_Placement> placements;
  final List<TreeConnectorEdge> edges;
  final Size size;
  const _Layout({
    required this.placements,
    required this.edges,
    required this.size,
  });
}

class _AssetChip extends StatelessWidget {
  final AppTheme t;
  final String assetId;

  const _AssetChip({required this.t, required this.assetId});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: t.navyLt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.navy.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.precision_manufacturing_outlined, size: 13, color: t.navy),
          const SizedBox(width: 5),
          SelectableText(
            assetId,
            style: TextStyle(
              color: t.navy,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _StationEmptyHistory extends StatelessWidget {
  final AppTheme t;
  const _StationEmptyHistory({required this.t});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: t.scaffold,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.border),
      ),
      child: Row(
        children: [
          Icon(Icons.inbox_outlined, color: t.muted, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'No alerts have been recorded at this workstation yet.',
              style: TextStyle(color: t.muted, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _StationHistoryTile extends StatelessWidget {
  final AlertModel alert;
  const _StationHistoryTile({required this.alert});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final type = typeMeta(alert.type, t);
    final status = statusMeta(alert.status, t);
    return Material(
      color: t.scaffold,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => showTreeAlertSheet(context, alert),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: t.border),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: type.bg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(type.icon, color: type.color, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      type.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: t.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      DateFormat('MMM d, h:mm a').format(alert.timestamp),
                      style: TextStyle(color: t.muted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: status.bg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  status.label,
                  style: TextStyle(
                    color: status.color,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Live "pulsing" green dot — used in the live status header.
// =============================================================================
class _LivePulseDot extends StatefulWidget {
  final Color color;
  const _LivePulseDot({required this.color});

  @override
  State<_LivePulseDot> createState() => _LivePulseDotState();
}

class _LivePulseDotState extends State<_LivePulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final v = _c.value;
        return SizedBox(
          width: 14,
          height: 14,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withValues(alpha: 0.15 + v * 0.1),
                ),
              ),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color,
                  boxShadow: [
                    BoxShadow(
                      color: widget.color.withValues(alpha: 0.5),
                      blurRadius: 6 + v * 4,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
