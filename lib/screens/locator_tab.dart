// ignore_for_file: deprecated_member_use

// lib/screens/locator_tab.dart
//
// Supervisor-facing locator. Renders the FactoryMap built by the production
// manager (live, via streamFactoryMap). When the supervisor has claimed an
// alert, an animated blue arrow runs from the factory entrance to that
// station's circle, which pulses blue.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/alert_model.dart';
import '../models/factory_map_model.dart';
import '../models/hierarchy_model.dart';
import '../providers/alert_provider.dart';
import '../services/hierarchy_service.dart';
import '../theme.dart';
import '../widgets/locator_painter.dart';
import 'alert_detail_screen.dart';

class LocatorScreen extends StatefulWidget {
  final String supervisorId;
  final String factoryName;

  const LocatorScreen({
    super.key,
    required this.supervisorId,
    required this.factoryName,
  });

  @override
  State<LocatorScreen> createState() => _LocatorScreenState();
}

class _LocatorScreenState extends State<LocatorScreen>
    with SingleTickerProviderStateMixin {
  final HierarchyService _service = HierarchyService();
  late final AnimationController _pulse;
  StreamSubscription<List<Factory>>? _factoriesSub;
  StreamSubscription<FactoryMap>? _mapSub;
  List<Factory> _factories = const [];
  FactoryMap? _map;
  String? _trackedFactoryId;
  MapCell? _supervisorPosition;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    _factoriesSub = _service.getFactories().listen((list) {
      if (!mounted) return;
      setState(() => _factories = list);
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    _factoriesSub?.cancel();
    _mapSub?.cancel();
    super.dispose();
  }

  Factory? _resolveFactory(AlertModel? claim) {
    final factories = _factories;
    if (claim != null) {
      for (final f in factories) {
        if (_matches(f, claim.usine)) return f;
      }
    }
    for (final f in factories) {
      if (_matches(f, widget.factoryName)) return f;
    }
    return factories.isEmpty ? null : factories.first;
  }

  bool _matches(Factory f, String value) {
    final n = _normalize(value);
    return n == _normalize(f.id) || n == _normalize(f.name);
  }

  String _normalize(String v) =>
      v.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');

  void _ensureMapStream(String factoryId) {
    if (_trackedFactoryId == factoryId) return;
    _trackedFactoryId = factoryId;
    _mapSub?.cancel();
    _map = null;
    _supervisorPosition = null;
    _mapSub = _service.streamFactoryMap(factoryId).listen((m) {
      if (!mounted) return;
      setState(() => _map = m);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final alerts = context.watch<AlertProvider>().allAlerts;
    final claim = _activeClaim(alerts, widget.supervisorId);
    final factory = _resolveFactory(claim);

    if (_factories.isEmpty) {
      return Center(child: CircularProgressIndicator(color: t.navy));
    }
    if (factory == null) {
      return _Empty(
        icon: Icons.factory_outlined,
        title: 'No factory',
        message: 'No matching factory for ${widget.factoryName}.',
      );
    }
    _ensureMapStream(factory.id);

    final map = _map;
    if (map == null) {
      return Center(child: CircularProgressIndicator(color: t.navy));
    }

    final factoryAlerts =
        alerts.where((a) => _matches(factory, a.usine)).toList();
    final badges = <String, LocatorNodeBadge>{};
    for (final node in map.nodes) {
      final stationAlerts = factoryAlerts
          .where((a) =>
              a.convoyeur == node.conveyorNumber &&
              a.poste == node.stationNumber)
          .toList()
        ..sort((a, b) => _alertPriority(b).compareTo(_alertPriority(a)));
      if (stationAlerts.isEmpty) continue;
      final top = stationAlerts.first;
      badges[node.key] = LocatorNodeBadge(
        key: node.key,
        status: _statusFor(top),
        alertNumber: top.alertNumber == 0 ? null : top.alertNumber,
      );
    }

    final claimedNode =
        claim == null ? null : map.nodeForStation(claim.convoyeur, claim.poste);
    final claimedKey = claimedNode?.key;

    return Container(
      color: t.scaffold,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _LocatorHeader(
              factory: factory,
              mapped: map.nodes.length,
              hasMap: !map.isEmpty,
              hasClaim: claim != null,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                child: LayoutBuilder(builder: (context, c) {
                  final wide = c.maxWidth >= 880;
                  final compact = c.maxWidth < 640;
                  final canvas = _MapCard(
                    map: map,
                    pulse: _pulse,
                    claimedKey: claimedKey,
                    badges: badges,
                    compact: compact,
                    supervisorPosition: _supervisorPosition,
                    onSupervisorPositionChanged: (cell) {
                      setState(() => _supervisorPosition = cell);
                      HapticFeedback.mediumImpact();
                    },
                    onSupervisorPositionCleared: () {
                      setState(() => _supervisorPosition = null);
                    },
                  );
                  final side = _SidePanel(
                    factory: factory,
                    claim: claim,
                    claimedNode: claimedNode,
                    badges: badges,
                    map: map,
                  );
                  return wide
                      ? Row(children: [
                          Expanded(child: canvas),
                          const SizedBox(width: 12),
                          SizedBox(width: 320, child: side),
                        ])
                      : Column(children: [
                          Expanded(flex: compact ? 7 : 5, child: canvas),
                          SizedBox(height: compact ? 8 : 10),
                          SizedBox(
                            height: compact ? 138 : 200,
                            child: compact
                                ? _MobileRoutePanel(
                                    claim: claim,
                                    claimedNode: claimedNode,
                                    badges: badges,
                                    map: map,
                                    supervisorPosition: _supervisorPosition,
                                  )
                                : side,
                          ),
                        ]);
                }),
              ),
            ),
            if (claim == null && MediaQuery.sizeOf(context).width >= 640)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                decoration: BoxDecoration(
                  color: t.orangeLt,
                  border: Border(top: BorderSide(color: t.orange)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded, color: t.orange, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'No claimed alert. Claim one to see its route on the map.',
                        style: TextStyle(
                          color: t.text,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LocatorHeader extends StatelessWidget {
  final Factory factory;
  final int mapped;
  final bool hasMap;
  final bool hasClaim;

  const _LocatorHeader({
    required this.factory,
    required this.mapped,
    required this.hasMap,
    required this.hasClaim,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final compact = MediaQuery.sizeOf(context).width < 640;
    final pills = [
      _Pill(
          icon: Icons.pin_drop_outlined,
          label: '$mapped mapped',
          color: mapped > 0 ? t.green : t.muted),
      _Pill(
          icon: hasMap
              ? Icons.check_circle_outline_rounded
              : Icons.dashboard_outlined,
          label: hasMap ? 'Map ready' : 'No map',
          color: hasMap ? t.green : t.orange),
      _Pill(
          icon: hasClaim ? Icons.navigation_rounded : Icons.navigation_outlined,
          label: hasClaim ? 'Route on' : 'No route',
          color: hasClaim ? t.blue : t.muted),
    ];

    if (compact) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [t.green, t.blue],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(Icons.map_rounded,
                      color: Colors.white, size: 21),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Locator',
                          style: TextStyle(
                            color: t.text,
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                          )),
                      Text(factory.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: t.muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          )),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < pills.length; i++) ...[
                    if (i > 0) const SizedBox(width: 6),
                    pills[i],
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [t.green, t.blue],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.map_rounded, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Locator',
                    style: TextStyle(
                      color: t.text,
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                    )),
                Text(factory.name,
                    style: TextStyle(
                      color: t.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    )),
              ],
            ),
          ),
          Wrap(spacing: 8, children: pills),
        ],
      ),
    );
  }
}

class _MapCard extends StatefulWidget {
  final FactoryMap map;
  final AnimationController pulse;
  final String? claimedKey;
  final Map<String, LocatorNodeBadge> badges;
  final bool compact;
  final MapCell? supervisorPosition;
  final ValueChanged<MapCell> onSupervisorPositionChanged;
  final VoidCallback onSupervisorPositionCleared;

  const _MapCard({
    required this.map,
    required this.pulse,
    required this.claimedKey,
    required this.badges,
    required this.compact,
    required this.supervisorPosition,
    required this.onSupervisorPositionChanged,
    required this.onSupervisorPositionCleared,
  });

  @override
  State<_MapCard> createState() => _MapCardState();
}

class _MapCardState extends State<_MapCard> {
  late final TransformationController _controller = TransformationController();
  Size? _viewportSize;
  Size? _canvasSize;
  double? _cellSize;
  Object? _lastViewSignature;
  bool _needsInitialView = true;

  @override
  void didUpdateWidget(covariant _MapCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.map != widget.map ||
        oldWidget.claimedKey != widget.claimedKey ||
        oldWidget.supervisorPosition != widget.supervisorPosition ||
        oldWidget.compact != widget.compact) {
      _needsInitialView = true;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    if (widget.map.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: t.border),
        ),
        child: _Empty(
          icon: Icons.dashboard_customize_outlined,
          title: 'Map not configured',
          message:
              'Ask the production manager to build this factory in Hierarchy → Factory Mapping.',
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportSize = Size(
          constraints.maxWidth,
          constraints.maxHeight,
        );
        final cellSize = widget.compact ? 56.0 : 42.0;
        final canvasSize = Size(
          math.max(viewportSize.width, widget.map.cols * cellSize),
          math.max(viewportSize.height, widget.map.rows * cellSize),
        );
        _viewportSize = viewportSize;
        _canvasSize = canvasSize;
        _cellSize = cellSize;
        _scheduleInitialView(viewportSize, canvasSize, cellSize);

        return Container(
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: t.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black
                    .withValues(alpha: context.isDark ? 0.22 : 0.07),
                blurRadius: 22,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: InteractiveViewer(
                  transformationController: _controller,
                  constrained: false,
                  minScale: _minScale(viewportSize, canvasSize),
                  maxScale: widget.compact ? 5 : 4,
                  boundaryMargin: EdgeInsets.all(widget.compact ? 180 : 120),
                  child: SizedBox(
                    width: canvasSize.width,
                    height: canvasSize.height,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onLongPressStart: (details) => _setPositionFromScene(
                        details.localPosition,
                        canvasSize,
                        cellSize,
                      ),
                      child: AnimatedBuilder(
                        animation: widget.pulse,
                        builder: (context, _) {
                          return CustomPaint(
                            size: canvasSize,
                            painter: FactoryMapLocatorPainter(
                              map: widget.map,
                              theme: t,
                              isDark: context.isDark,
                              badges: widget.badges,
                              claimedNodeKey: widget.claimedKey,
                              routeStart: widget.supervisorPosition,
                              pulse: widget.pulse.value,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 10,
                right: 10,
                child: Column(
                  children: [
                    if (widget.claimedKey != null) ...[
                      _MapControlButton(
                        icon: Icons.my_location_rounded,
                        tooltip: 'Focus route',
                        onTap: _focusRouteFromLastLayout,
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (widget.supervisorPosition != null) ...[
                      _MapControlButton(
                        icon: Icons.home_work_outlined,
                        tooltip: 'Use entrance',
                        onTap: widget.onSupervisorPositionCleared,
                      ),
                      const SizedBox(height: 8),
                    ],
                    _MapControlButton(
                      icon: Icons.fit_screen_rounded,
                      tooltip: 'Show full map',
                      onTap: _showOverviewFromLastLayout,
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 10,
                bottom: 10,
                child: _RouteStartChip(
                  usingCustomPosition: widget.supervisorPosition != null,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _scheduleInitialView(Size viewport, Size canvas, double cellSize) {
    final signature = Object.hash(
      widget.map.factoryId,
      widget.map.updatedAt,
      widget.map.nodes.length,
      widget.map.edges.length,
      widget.claimedKey,
      widget.supervisorPosition,
      widget.compact,
      viewport.width.round(),
      viewport.height.round(),
    );
    if (!_needsInitialView && _lastViewSignature == signature) return;
    _lastViewSignature = signature;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _lastViewSignature != signature) return;
      _focusBest(viewport, canvas, cellSize);
      _needsInitialView = false;
    });
  }

  void _focusBest(Size viewport, Size canvas, double cellSize) {
    if (!_focusRoute(viewport, canvas, cellSize)) {
      _showOverview(viewport, canvas);
    }
  }

  bool _focusRoute(Size viewport, Size canvas, double cellSize) {
    final claimedKey = widget.claimedKey;
    if (claimedKey == null) return false;
    final target = widget.map.nodeByKey(claimedKey);
    if (target == null) return false;

    final points = <Offset>[_cellCenter(target.cell, canvas, cellSize)];
    final start = widget.supervisorPosition ?? widget.map.entrance;
    if (start != null) {
      points.add(_cellCenter(start, canvas, cellSize));
    }

    var bounds = Rect.fromCircle(center: points.first, radius: cellSize);
    for (final point in points.skip(1)) {
      bounds = bounds.expandToInclude(
        Rect.fromCircle(center: point, radius: cellSize),
      );
    }
    final padding = widget.compact ? cellSize * 2.0 : cellSize * 1.4;
    final padded = bounds.inflate(padding);
    final fitScale = math.min(
      viewport.width / math.max(padded.width, 1),
      viewport.height / math.max(padded.height, 1),
    );
    final scale = fitScale
        .clamp(
          _minScale(viewport, canvas),
          widget.compact ? 1.25 : 1.0,
        )
        .toDouble();
    _controller.value = _matrixFor(padded.center, viewport, canvas, scale);
    return true;
  }

  void _showOverview(Size viewport, Size canvas) {
    final fitScale = math.min(
      viewport.width / math.max(canvas.width, 1),
      viewport.height / math.max(canvas.height, 1),
    );
    final scale = fitScale.clamp(_minScale(viewport, canvas), 1.0).toDouble();
    _controller.value = _matrixFor(
      Offset(canvas.width / 2, canvas.height / 2),
      viewport,
      canvas,
      scale,
    );
  }

  void _focusRouteFromLastLayout() {
    final viewport = _viewportSize;
    final canvas = _canvasSize;
    final cellSize = _cellSize;
    if (viewport == null || canvas == null || cellSize == null) return;
    _focusBest(viewport, canvas, cellSize);
  }

  void _showOverviewFromLastLayout() {
    final viewport = _viewportSize;
    final canvas = _canvasSize;
    if (viewport == null || canvas == null) return;
    _showOverview(viewport, canvas);
  }

  void _setPositionFromScene(Offset sceneOffset, Size canvas, double cellSize) {
    final cell = _cellAtScene(sceneOffset, canvas, cellSize);
    if (cell == null) return;
    widget.onSupervisorPositionChanged(cell);
  }

  MapCell? _cellAtScene(Offset sceneOffset, Size canvas, double cellSize) {
    final ox = (canvas.width - widget.map.cols * cellSize) / 2;
    final oy = (canvas.height - widget.map.rows * cellSize) / 2;
    final local = sceneOffset - Offset(ox, oy);
    if (local.dx < 0 || local.dy < 0) return null;
    final col = (local.dx / cellSize).floor();
    final row = (local.dy / cellSize).floor();
    if (row < 0 || col < 0) return null;
    if (row >= widget.map.rows || col >= widget.map.cols) return null;
    return MapCell(row, col);
  }

  double _minScale(Size viewport, Size canvas) {
    final fitScale = math.min(
      viewport.width / math.max(canvas.width, 1),
      viewport.height / math.max(canvas.height, 1),
    );
    return math
        .min(fitScale, widget.compact ? 0.28 : 0.45)
        .clamp(0.16, 1.0)
        .toDouble();
  }

  Offset _cellCenter(MapCell cell, Size canvas, double cellSize) {
    final ox = (canvas.width - widget.map.cols * cellSize) / 2;
    final oy = (canvas.height - widget.map.rows * cellSize) / 2;
    return Offset(
      ox + cell.col * cellSize + cellSize / 2,
      oy + cell.row * cellSize + cellSize / 2,
    );
  }

  Matrix4 _matrixFor(
    Offset center,
    Size viewport,
    Size canvas,
    double scale,
  ) {
    final tx = _boundTranslation(
      viewport.width / 2 - center.dx * scale,
      viewport.width,
      canvas.width,
      scale,
    );
    final ty = _boundTranslation(
      viewport.height / 2 - center.dy * scale,
      viewport.height,
      canvas.height,
      scale,
    );
    return Matrix4.identity()
      ..translate(tx, ty)
      ..scale(scale);
  }

  double _boundTranslation(
    double value,
    double viewportExtent,
    double canvasExtent,
    double scale,
  ) {
    final contentExtent = canvasExtent * scale;
    if (contentExtent <= viewportExtent) {
      return (viewportExtent - contentExtent) / 2;
    }
    return value.clamp(viewportExtent - contentExtent, 0).toDouble();
  }
}

class _MapControlButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _MapControlButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: t.card.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(10),
        elevation: 3,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon, color: t.navy, size: 22),
          ),
        ),
      ),
    );
  }
}

class _RouteStartChip extends StatelessWidget {
  final bool usingCustomPosition;

  const _RouteStartChip({required this.usingCustomPosition});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final color = usingCustomPosition ? t.blue : t.green;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: t.card.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: context.isDark ? 0.24 : 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            usingCustomPosition
                ? Icons.person_pin_circle_outlined
                : Icons.door_front_door_outlined,
            size: 17,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(
            usingCustomPosition ? 'Start: You' : 'Start: Entrance',
            style: TextStyle(
              color: t.text,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _SidePanel extends StatelessWidget {
  final Factory factory;
  final AlertModel? claim;
  final MapNode? claimedNode;
  final Map<String, LocatorNodeBadge> badges;
  final FactoryMap map;

  const _SidePanel({
    required this.factory,
    required this.claim,
    required this.claimedNode,
    required this.badges,
    required this.map,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Container(
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.border),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (claim == null)
            _InfoBlock(
              icon: Icons.map_outlined,
              color: t.orange,
              title: 'No active claim',
              message: 'Claim an alert to view its blue route.',
            )
          else if (claimedNode == null)
            _InfoBlock(
              icon: Icons.report_gmailerrorred_outlined,
              color: t.red,
              title: 'Station not on map',
              message:
                  'C${claim!.convoyeur}S${claim!.poste} has not been placed yet.',
            )
          else
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => AlertDetailScreen(alertId: claim!.id)),
              ),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: t.blueLt,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: t.blue.withValues(alpha: 0.28)),
                ),
                child: Row(children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                        color: t.card, borderRadius: BorderRadius.circular(10)),
                    child:
                        Icon(Icons.navigation_rounded, color: t.blue, size: 26),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(claimedNode!.label,
                            style: TextStyle(
                              color: t.text,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            )),
                        Text(_typeLabel(claim!.type),
                            style: TextStyle(color: t.muted, fontSize: 11)),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: t.muted),
                ]),
              ),
            ),
          const SizedBox(height: 14),
          Text('Live station status',
              style: TextStyle(
                color: t.text,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              )),
          const SizedBox(height: 8),
          Expanded(
            child: badges.isEmpty
                ? Center(
                    child: Text('All mapped stations idle',
                        style: TextStyle(color: t.muted)))
                : ListView(
                    children: badges.entries.map((e) {
                      final node = map.nodeByKey(e.key);
                      if (node == null) return const SizedBox.shrink();
                      final color = _badgeColor(e.value.status, t);
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                                color: color, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              node.label,
                              style: TextStyle(
                                  color: t.text,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900),
                            ),
                          ),
                          if (e.value.alertNumber != null)
                            Text('#${e.value.alertNumber}',
                                style: TextStyle(color: t.muted, fontSize: 11)),
                        ]),
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }
}

class _MobileRoutePanel extends StatelessWidget {
  final AlertModel? claim;
  final MapNode? claimedNode;
  final Map<String, LocatorNodeBadge> badges;
  final FactoryMap map;
  final MapCell? supervisorPosition;

  const _MobileRoutePanel({
    required this.claim,
    required this.claimedNode,
    required this.badges,
    required this.map,
    required this.supervisorPosition,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final activeBadges = badges.entries.where((entry) {
      return entry.value.status != LocatorNodeStatus.idle;
    }).toList();

    return Container(
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.border),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        children: [
          _mobileRouteCard(context),
          const SizedBox(height: 8),
          SizedBox(
            height: 34,
            child: activeBadges.isEmpty
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: _MobileStatusChip(
                      label: 'All idle',
                      color: t.green,
                      icon: Icons.check_circle_outline_rounded,
                    ),
                  )
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: activeBadges.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 7),
                    itemBuilder: (context, index) {
                      final entry = activeBadges[index];
                      final node = map.nodeByKey(entry.key);
                      if (node == null) return const SizedBox.shrink();
                      final badge = entry.value;
                      final color = _badgeColor(badge.status, t);
                      final number = badge.alertNumber;
                      return _MobileStatusChip(
                        label: number == null
                            ? node.label
                            : '${node.label} #$number',
                        color: color,
                        icon: _statusIcon(badge.status),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _mobileRouteCard(BuildContext context) {
    final t = context.appTheme;
    final claim = this.claim;
    final missingNode = claim != null && claimedNode == null;
    final color = claim == null
        ? t.orange
        : missingNode
            ? t.red
            : t.blue;
    final icon = claim == null
        ? Icons.map_outlined
        : missingNode
            ? Icons.report_gmailerrorred_outlined
            : Icons.navigation_rounded;
    final title = claim == null
        ? 'No active claim'
        : missingNode
            ? 'Station missing'
            : 'Route to ${claimedNode!.label}';
    final startLabel =
        supervisorPosition == null ? 'Entrance' : 'Your position';
    final subtitle = claim == null
        ? 'Claim an alert to unlock route focus.'
        : missingNode
            ? 'C${claim.convoyeur}S${claim.poste} is not on the map.'
            : '$startLabel -> ${_typeLabel(claim.type)}';

    final card = Container(
      height: 76,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: context.isDark ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: t.card,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: color, size: 27),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: t.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: t.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (claim != null && claim.alertNumber != 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: t.card,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: color.withValues(alpha: 0.25)),
              ),
              child: Text(
                '#${claim.alertNumber}',
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          if (claim != null) ...[
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, color: t.muted),
          ],
        ],
      ),
    );

    if (claim == null) return card;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => AlertDetailScreen(alertId: claim.id)),
      ),
      child: card,
    );
  }
}

class _MobileStatusChip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;

  const _MobileStatusChip({
    required this.label,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: context.isDark ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: t.text,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoBlock extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String message;

  const _InfoBlock({
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: context.isDark ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                      color: t.text,
                      fontWeight: FontWeight.w900,
                      fontSize: 13)),
              Text(message, style: TextStyle(color: t.muted, fontSize: 12)),
            ],
          ),
        ),
      ]),
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _Pill({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: context.isDark ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 5),
        Text(label,
            style: TextStyle(
                color: t.text, fontSize: 11, fontWeight: FontWeight.w900)),
      ]),
    );
  }
}

class _Empty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  const _Empty(
      {required this.icon, required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
                color: t.navyLt, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: t.navy, size: 28),
          ),
          const SizedBox(height: 12),
          Text(title,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: t.text, fontSize: 16, fontWeight: FontWeight.w900)),
          const SizedBox(height: 5),
          Text(message,
              textAlign: TextAlign.center,
              style: TextStyle(color: t.muted, fontSize: 12)),
        ]),
      ),
    );
  }
}

// ── Helpers ─────────────────────────────────────────────────────────────────

AlertModel? _activeClaim(List<AlertModel> alerts, String supervisorId) {
  final claims = alerts
      .where((a) => a.status == 'en_cours' && a.superviseurId == supervisorId)
      .toList()
    ..sort((a, b) {
      final at = a.takenAtTimestamp ?? a.timestamp;
      final bt = b.takenAtTimestamp ?? b.timestamp;
      return bt.compareTo(at);
    });
  return claims.isEmpty ? null : claims.first;
}

int _alertPriority(AlertModel a) {
  if (a.isCritical && a.status != 'validee') return 50;
  return switch (a.status) {
    'disponible' => 40,
    'en_cours' => 30,
    'validee' => 20,
    _ => 0,
  };
}

LocatorNodeStatus _statusFor(AlertModel a) {
  if (a.isCritical && a.status != 'validee') return LocatorNodeStatus.critical;
  return switch (a.status) {
    'disponible' => LocatorNodeStatus.available,
    'en_cours' => LocatorNodeStatus.inProgress,
    'validee' => LocatorNodeStatus.resolved,
    _ => LocatorNodeStatus.idle,
  };
}

Color _badgeColor(LocatorNodeStatus s, AppTheme t) => switch (s) {
      LocatorNodeStatus.critical => t.red,
      LocatorNodeStatus.available => t.orange,
      LocatorNodeStatus.inProgress => t.blue,
      LocatorNodeStatus.resolved => t.green,
      LocatorNodeStatus.idle => t.mutedDk,
    };

IconData _statusIcon(LocatorNodeStatus s) => switch (s) {
      LocatorNodeStatus.critical => Icons.priority_high_rounded,
      LocatorNodeStatus.available => Icons.notifications_active_outlined,
      LocatorNodeStatus.inProgress => Icons.engineering_outlined,
      LocatorNodeStatus.resolved => Icons.check_circle_outline_rounded,
      LocatorNodeStatus.idle => Icons.radio_button_unchecked_rounded,
    };

String _typeLabel(String type) => switch (type) {
      'qualite' => 'Quality',
      'maintenance' => 'Maintenance',
      'defaut_produit' => 'Damaged product',
      'manque_ressource' => 'Resource shortage',
      _ => type,
    };
