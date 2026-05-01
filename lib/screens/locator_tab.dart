import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/alert_model.dart';
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
  final HierarchyService _hierarchyService = HierarchyService();
  late final AnimationController _pulseController;
  Offset? _manualPosition;
  bool _loadingManualPosition = true;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
    unawaited(_loadManualPosition());
  }

  @override
  void didUpdateWidget(covariant LocatorScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.factoryName != widget.factoryName) {
      unawaited(_loadManualPosition());
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _loadManualPosition() async {
    setState(() => _loadingManualPosition = true);
    final prefs = await SharedPreferences.getInstance();
    final x = prefs.getDouble(_manualXKey);
    final y = prefs.getDouble(_manualYKey);
    if (!mounted) return;
    setState(() {
      _manualPosition = x == null || y == null ? null : Offset(x, y);
      _loadingManualPosition = false;
    });
  }

  Future<void> _saveManualPosition(Offset? position) async {
    final prefs = await SharedPreferences.getInstance();
    if (position == null) {
      await prefs.remove(_manualXKey);
      await prefs.remove(_manualYKey);
    } else {
      await prefs.setDouble(_manualXKey, position.dx);
      await prefs.setDouble(_manualYKey, position.dy);
    }
    if (!mounted) return;
    setState(() => _manualPosition = position);
  }

  String get _manualKeyPrefix {
    return widget.factoryName.trim().toLowerCase().replaceAll(
          RegExp(r'[^a-z0-9]+'),
          '_',
        );
  }

  String get _manualXKey => 'locator_${_manualKeyPrefix}_manual_x';
  String get _manualYKey => 'locator_${_manualKeyPrefix}_manual_y';

  @override
  Widget build(BuildContext context) {
    final alerts = context.watch<AlertProvider>().allAlerts;
    final myClaim = _activeClaimForSupervisor(alerts, widget.supervisorId);

    return Container(
      color: context.appTheme.scaffold,
      child: SafeArea(
        bottom: false,
        child: StreamBuilder<List<Factory>>(
          stream: _hierarchyService.getFactories(),
          builder: (context, snapshot) {
            final factories = snapshot.data ?? const <Factory>[];
            final factory = _resolveFactory(factories, myClaim);

            if (snapshot.connectionState == ConnectionState.waiting &&
                factory == null) {
              return const Center(child: CircularProgressIndicator());
            }

            if (factory == null) {
              return _LocatorEmptyState(
                icon: Icons.factory_outlined,
                title: 'Factory map unavailable',
                message:
                    'No hierarchy entry matched ${widget.factoryName}. Check the supervisor factory assignment.',
              );
            }

            final factoryAlerts = alerts
                .where((alert) => _matchesFactory(factory, alert.usine))
                .toList();
            final pins = _buildPins(factory, factoryAlerts, myClaim);
            final targetPin = myClaim == null
                ? null
                : pins.cast<LocatorStationPin?>().firstWhere(
                      (pin) =>
                          pin?.conveyorNumber == myClaim.convoyeur &&
                          pin?.stationNumber == myClaim.poste,
                      orElse: () => null,
                    );
            final missingCount = _missingCoordinateCount(factory);

            return _LocatorContent(
              factory: factory,
              pins: pins,
              missingCoordinateCount: missingCount,
              claim: myClaim,
              targetPin: targetPin,
              manualPosition: _loadingManualPosition ? null : _manualPosition,
              loadingManualPosition: _loadingManualPosition,
              pulseController: _pulseController,
              onSetManualPosition: _showManualPositionDialog,
            );
          },
        ),
      ),
    );
  }

  Factory? _resolveFactory(List<Factory> factories, AlertModel? claim) {
    if (claim != null) {
      final claimFactory = factories.cast<Factory?>().firstWhere(
            (factory) =>
                factory != null && _matchesFactory(factory, claim.usine),
            orElse: () => null,
          );
      if (claimFactory != null) return claimFactory;
    }

    return factories.cast<Factory?>().firstWhere(
          (factory) =>
              factory != null && _matchesFactory(factory, widget.factoryName),
          orElse: () => null,
        );
  }

  Future<void> _showManualPositionDialog() async {
    final xController = TextEditingController(
      text: _manualPosition == null ? '' : _formatCoord(_manualPosition!.dx),
    );
    final yController = TextEditingController(
      text: _manualPosition == null ? '' : _formatCoord(_manualPosition!.dy),
    );
    String? error;

    final result = await showDialog<_ManualPositionResult>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) {
          final t = context.appTheme;
          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.my_location_rounded, color: t.blue),
                const SizedBox(width: 8),
                const Expanded(child: Text('Set Current Position')),
              ],
            ),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Enter your current factory coordinates in metres.',
                    style: TextStyle(color: t.muted, fontSize: 12),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _ManualCoordinateField(
                          controller: xController,
                          label: 'X',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _ManualCoordinateField(
                          controller: yController,
                          label: 'Y',
                        ),
                      ),
                    ],
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(error!, style: TextStyle(color: t.red, fontSize: 12)),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(
                  context,
                  const _ManualPositionResult.cancel(),
                ),
                child: const Text('Cancel'),
              ),
              TextButton.icon(
                onPressed: () => Navigator.pop(
                  context,
                  const _ManualPositionResult.useEntrance(),
                ),
                icon: const Icon(Icons.restart_alt_rounded, size: 16),
                label: const Text('Use Entrance'),
              ),
              FilledButton.icon(
                onPressed: () {
                  final x = _parseCoord(xController.text);
                  final y = _parseCoord(yController.text);
                  if (x == null || y == null) {
                    setDialogState(() {
                      error = 'Enter valid decimal values for X and Y.';
                    });
                    return;
                  }
                  Navigator.pop(
                    context,
                    _ManualPositionResult(position: Offset(x, y)),
                  );
                },
                icon: const Icon(Icons.check_rounded, size: 16),
                label: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );

    xController.dispose();
    yController.dispose();
    if (!mounted) return;
    if (result == null || result.cancelled) return;
    await _saveManualPosition(result.position);
  }
}

class _ManualPositionResult {
  final Offset? position;
  final bool cancelled;

  const _ManualPositionResult({this.position}) : cancelled = false;
  const _ManualPositionResult.cancel()
      : position = null,
        cancelled = true;
  const _ManualPositionResult.useEntrance()
      : position = null,
        cancelled = false;
}

class _LocatorContent extends StatelessWidget {
  final Factory factory;
  final List<LocatorStationPin> pins;
  final int missingCoordinateCount;
  final AlertModel? claim;
  final LocatorStationPin? targetPin;
  final Offset? manualPosition;
  final bool loadingManualPosition;
  final AnimationController pulseController;
  final VoidCallback onSetManualPosition;

  const _LocatorContent({
    required this.factory,
    required this.pins,
    required this.missingCoordinateCount,
    required this.claim,
    required this.targetPin,
    required this.manualPosition,
    required this.loadingManualPosition,
    required this.pulseController,
    required this.onSetManualPosition,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final map = _LocatorMapCard(
          pins: pins,
          targetPin: targetPin,
          manualPosition: manualPosition,
          pulseController: pulseController,
        );
        final panel = _LocatorSidePanel(
          factory: factory,
          claim: claim,
          targetPin: targetPin,
          pins: pins,
          missingCoordinateCount: missingCoordinateCount,
          manualPosition: manualPosition,
          loadingManualPosition: loadingManualPosition,
          onSetManualPosition: onSetManualPosition,
        );

        return Column(
          children: [
            _LocatorHeader(
              factory: factory,
              pinCount: pins.length,
              missingCoordinateCount: missingCoordinateCount,
              hasClaim: claim != null,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                child: wide
                    ? Row(
                        children: [
                          Expanded(child: map),
                          const SizedBox(width: 14),
                          SizedBox(width: 350, child: panel),
                        ],
                      )
                    : Column(
                        children: [
                          Expanded(child: map),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: math.min(210, constraints.maxHeight * 0.34),
                            child: panel,
                          ),
                        ],
                      ),
              ),
            ),
            if (claim == null)
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
                        'No claimed alert. Claim an alert first to see its location.',
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
        );
      },
    );
  }
}

class _LocatorHeader extends StatelessWidget {
  final Factory factory;
  final int pinCount;
  final int missingCoordinateCount;
  final bool hasClaim;

  const _LocatorHeader({
    required this.factory,
    required this.pinCount,
    required this.missingCoordinateCount,
    required this.hasClaim,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: t.greenLt,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: t.green.withValues(alpha: 0.22)),
            ),
            child: Icon(Icons.map_rounded, color: t.green),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Locator',
                  style: TextStyle(
                    color: t.text,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  factory.name,
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
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              _LocatorPill(
                icon: Icons.pin_drop_outlined,
                label: '$pinCount mapped',
                color: pinCount > 0 ? t.green : t.muted,
              ),
              if (missingCoordinateCount > 0)
                _LocatorPill(
                  icon: Icons.edit_location_alt_outlined,
                  label: '$missingCoordinateCount unset',
                  color: t.orange,
                ),
              _LocatorPill(
                icon: hasClaim
                    ? Icons.navigation_rounded
                    : Icons.navigation_outlined,
                label: hasClaim ? 'Route ready' : 'No route',
                color: hasClaim ? t.blue : t.muted,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LocatorMapCard extends StatelessWidget {
  final List<LocatorStationPin> pins;
  final LocatorStationPin? targetPin;
  final Offset? manualPosition;
  final AnimationController pulseController;

  const _LocatorMapCard({
    required this.pins,
    required this.targetPin,
    required this.manualPosition,
    required this.pulseController,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    if (pins.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: t.border),
        ),
        child: _LocatorEmptyState(
          icon: Icons.edit_location_alt_outlined,
          title: 'Coordinates not set',
          message:
              'Ask an admin to enter station X/Y coordinates in the Hierarchy screen.',
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: context.isDark ? 0.20 : 0.07),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = math.max(1000.0, constraints.maxWidth);
            final height = math.max(760.0, constraints.maxHeight);
            return Stack(
              children: [
                InteractiveViewer(
                  minScale: 0.55,
                  maxScale: 4.0,
                  boundaryMargin: const EdgeInsets.all(260),
                  constrained: false,
                  child: SizedBox(
                    width: width,
                    height: height,
                    child: AnimatedBuilder(
                      animation: pulseController,
                      builder: (context, _) {
                        return CustomPaint(
                          painter: LocatorMapPainter(
                            theme: t,
                            isDark: context.isDark,
                            stations: pins,
                            entrance: Offset.zero,
                            currentPosition: manualPosition,
                            targetStation: targetPin,
                            pulse: pulseController.value,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  child: _MapLegend(),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LocatorSidePanel extends StatelessWidget {
  final Factory factory;
  final AlertModel? claim;
  final LocatorStationPin? targetPin;
  final List<LocatorStationPin> pins;
  final int missingCoordinateCount;
  final Offset? manualPosition;
  final bool loadingManualPosition;
  final VoidCallback onSetManualPosition;

  const _LocatorSidePanel({
    required this.factory,
    required this.claim,
    required this.targetPin,
    required this.pins,
    required this.missingCoordinateCount,
    required this.manualPosition,
    required this.loadingManualPosition,
    required this.onSetManualPosition,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.border),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _RouteSummaryCard(claim: claim, targetPin: targetPin),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _MiniMetric(
                    icon: Icons.door_front_door_outlined,
                    label: manualPosition == null ? 'Entrance' : 'Manual',
                    value: manualPosition == null
                        ? '0.00, 0.00'
                        : '${_formatCoord(manualPosition!.dx)}, ${_formatCoord(manualPosition!.dy)}',
                    color: manualPosition == null ? t.green : t.blue,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MiniMetric(
                    icon: Icons.edit_location_alt_outlined,
                    label: 'Unset',
                    value: '$missingCoordinateCount',
                    color: missingCoordinateCount == 0 ? t.green : t.orange,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: loadingManualPosition ? null : onSetManualPosition,
                icon: const Icon(Icons.my_location_rounded, size: 16),
                label: const Text('Set Current Position'),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Live station status',
              style: TextStyle(
                color: t.text,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            ..._statusRows(context),
          ],
        ),
      ),
    );
  }

  List<Widget> _statusRows(BuildContext context) {
    final activePins = pins
        .where((pin) => pin.status != LocatorStationStatus.idle || pin.isTarget)
        .toList()
      ..sort((a, b) {
        if (a.isTarget != b.isTarget) return a.isTarget ? -1 : 1;
        return _statusPriority(b.status).compareTo(_statusPriority(a.status));
      });
    if (activePins.isEmpty) {
      return [
        _StationStatusRow(
          color: context.appTheme.muted,
          title: 'All mapped stations idle',
          subtitle: factory.name,
        ),
      ];
    }
    return activePins.take(8).map((pin) {
      return _StationStatusRow(
        color: _statusColor(context.appTheme, pin.status),
        title: pin.label,
        subtitle: pin.alertNumber == null
            ? _statusText(pin.status)
            : '${_statusText(pin.status)} #${pin.alertNumber}',
      );
    }).toList();
  }
}

class _RouteSummaryCard extends StatelessWidget {
  final AlertModel? claim;
  final LocatorStationPin? targetPin;

  const _RouteSummaryCard({
    required this.claim,
    required this.targetPin,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final claim = this.claim;
    if (claim == null) {
      return _InfoBlock(
        icon: Icons.map_outlined,
        color: t.orange,
        title: 'No claimed alert',
        message: 'Claim an alert first to see its route.',
      );
    }
    if (targetPin == null) {
      return _InfoBlock(
        icon: Icons.edit_location_alt_outlined,
        color: t.red,
        title: 'Station has no coordinates',
        message: 'C${claim.convoyeur}S${claim.poste} needs X/Y values.',
      );
    }

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => AlertDetailScreen(alertId: claim.id)),
      ),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: t.blueLt,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: t.blue.withValues(alpha: 0.28)),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: t.card,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.navigation_rounded, color: t.blue, size: 28),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    targetPin!.label,
                    style: TextStyle(
                      color: t.text,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${targetPin!.assetLabel} - ${_typeLabel(claim.type)}',
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
            Icon(Icons.chevron_right_rounded, color: t.muted),
          ],
        ),
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
        color: color.withValues(alpha: context.isDark ? 0.15 : 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.26)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: t.text,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(message, style: TextStyle(color: t.muted, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _MiniMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: t.scaffold,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(color: t.muted, fontSize: 11)),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: t.text,
              fontSize: 13,
              fontWeight: FontWeight.w900,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

class _StationStatusRow extends StatelessWidget {
  final Color color;
  final String title;
  final String subtitle;

  const _StationStatusRow({
    required this.color,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 11,
            height: 11,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: color.withValues(alpha: 0.24), blurRadius: 10),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: t.text,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: t.muted, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MapLegend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: t.card.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.border),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 6,
        children: [
          _LegendDot(color: t.mutedDk, label: 'Idle'),
          _LegendDot(color: t.orange, label: 'Open'),
          _LegendDot(color: t.blue, label: 'In progress'),
          _LegendDot(color: t.green, label: 'Resolved'),
          _LegendDot(color: t.red, label: 'Critical'),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            color: t.muted,
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _LocatorPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _LocatorPill({
    required this.icon,
    required this.label,
    required this.color,
  });

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
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: t.text,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _ManualCoordinateField extends StatelessWidget {
  final TextEditingController controller;
  final String label;

  const _ManualCoordinateField({
    required this.controller,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(
        signed: true,
        decimal: true,
      ),
      decoration: InputDecoration(
        labelText: label,
        suffixText: 'm',
        border: const OutlineInputBorder(),
      ),
    );
  }
}

class _LocatorEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _LocatorEmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: t.navyLt,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: t.navy, size: 28),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: t.text,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: t.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

List<LocatorStationPin> _buildPins(
  Factory factory,
  List<AlertModel> alerts,
  AlertModel? claim,
) {
  final conveyors = factory.conveyors.values.toList()
    ..sort((a, b) => a.number.compareTo(b.number));
  final pins = <LocatorStationPin>[];
  for (final conveyor in conveyors) {
    final stations = conveyor.stations.values.toList()
      ..sort((a, b) => _stationNumber(a).compareTo(_stationNumber(b)));
    for (final station in stations) {
      if (!station.hasCoordinates) continue;
      final stationNumber = _stationNumber(station);
      final stationAlerts = alerts
          .where(
            (alert) =>
                alert.convoyeur == conveyor.number &&
                alert.poste == stationNumber,
          )
          .toList()
        ..sort(_sortAlertsForStatus);
      final topAlert = stationAlerts.isEmpty ? null : stationAlerts.first;
      final isTarget = claim != null &&
          claim.convoyeur == conveyor.number &&
          claim.poste == stationNumber;
      pins.add(
        LocatorStationPin(
          id: '${conveyor.id}/${station.id}',
          label: 'C${conveyor.number}S$stationNumber',
          assetLabel: station.assetId.trim().isEmpty
              ? 'ID pending'
              : 'ID#${station.assetId.trim()}',
          conveyorNumber: conveyor.number,
          stationNumber: stationNumber,
          x: station.x!,
          y: station.y!,
          status: _statusForAlert(topAlert),
          isTarget: isTarget,
          alertNumber:
              topAlert?.alertNumber == 0 ? null : topAlert?.alertNumber,
        ),
      );
    }
  }
  return pins;
}

int _sortAlertsForStatus(AlertModel a, AlertModel b) {
  final byPriority = _alertPriority(b).compareTo(_alertPriority(a));
  if (byPriority != 0) return byPriority;
  return b.timestamp.compareTo(a.timestamp);
}

int _alertPriority(AlertModel alert) {
  if (alert.isCritical && alert.status != 'validee') return 50;
  return switch (alert.status) {
    'disponible' => 40,
    'en_cours' => 30,
    'validee' => 20,
    _ => 0,
  };
}

LocatorStationStatus _statusForAlert(AlertModel? alert) {
  if (alert == null) return LocatorStationStatus.idle;
  if (alert.isCritical && alert.status != 'validee') {
    return LocatorStationStatus.critical;
  }
  return switch (alert.status) {
    'disponible' => LocatorStationStatus.available,
    'en_cours' => LocatorStationStatus.inProgress,
    'validee' => LocatorStationStatus.resolved,
    _ => LocatorStationStatus.idle,
  };
}

AlertModel? _activeClaimForSupervisor(
  List<AlertModel> alerts,
  String supervisorId,
) {
  final claims = alerts
      .where((alert) =>
          alert.status == 'en_cours' && alert.superviseurId == supervisorId)
      .toList()
    ..sort((a, b) {
      final at = a.takenAtTimestamp ?? a.timestamp;
      final bt = b.takenAtTimestamp ?? b.timestamp;
      return bt.compareTo(at);
    });
  return claims.isEmpty ? null : claims.first;
}

int _missingCoordinateCount(Factory factory) {
  return factory.conveyors.values
      .expand((conveyor) => conveyor.stations.values)
      .where((station) => !station.hasCoordinates)
      .length;
}

bool _matchesFactory(Factory factory, String value) {
  final normalized = _normalize(value);
  return normalized == _normalize(factory.id) ||
      normalized == _normalize(factory.name);
}

String _normalize(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
}

int _stationNumber(Station station) {
  return int.tryParse(station.id.replaceFirst('station_', '')) ?? 0;
}

double? _parseCoord(String value) {
  return double.tryParse(value.trim().replaceAll(',', '.'));
}

String _formatCoord(double value) {
  return value.toStringAsFixed(2);
}

int _statusPriority(LocatorStationStatus status) {
  return switch (status) {
    LocatorStationStatus.critical => 5,
    LocatorStationStatus.available => 4,
    LocatorStationStatus.inProgress => 3,
    LocatorStationStatus.resolved => 2,
    LocatorStationStatus.idle => 1,
  };
}

Color _statusColor(AppTheme t, LocatorStationStatus status) {
  return switch (status) {
    LocatorStationStatus.critical => t.red,
    LocatorStationStatus.available => t.orange,
    LocatorStationStatus.inProgress => t.blue,
    LocatorStationStatus.resolved => t.green,
    LocatorStationStatus.idle => t.mutedDk,
  };
}

String _statusText(LocatorStationStatus status) {
  return switch (status) {
    LocatorStationStatus.critical => 'Critical',
    LocatorStationStatus.available => 'Open',
    LocatorStationStatus.inProgress => 'In progress',
    LocatorStationStatus.resolved => 'Resolved',
    LocatorStationStatus.idle => 'Idle',
  };
}

String _typeLabel(String type) {
  return switch (type) {
    'qualite' => 'Quality',
    'maintenance' => 'Maintenance',
    'defaut_produit' => 'Damaged product',
    'manque_ressource' => 'Resource shortage',
    _ => type,
  };
}
