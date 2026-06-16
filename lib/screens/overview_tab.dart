import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/alert_model.dart';
import '../../models/hierarchy_model.dart';
import '../../services/alert_pdf_service.dart';
import '../../services/forecast/forecast_overview_engine.dart';
import '../../services/predictive_intel_service.dart';
import '../../services/service_locator.dart';
import '../../theme.dart';
import '../../widgets/overview/ai_morning_briefing_hero.dart';
import '../../widgets/overview/overview_critical_alerts_card.dart';
import '../../widgets/overview/overview_predictive_failure_card.dart';
import '../../widgets/overview/overview_predictive_heatmap.dart';
import '../../widgets/overview/overview_stat_card.dart';
import 'admin/admin_dashboard_shared.dart';
import '../utils/user_friendly_error.dart';

part 'overview_tab_dialogs.dart';
part 'overview_tab_history.dart';
part 'overview_tab_export.dart';

String _fmtTs(DateTime d) => formatAdminTimestamp(d);

// ═══════════════════════════════════════════════════════════════════════════
// HEALTH SCORE CARD — semi-circular gauge
// ═══════════════════════════════════════════════════════════════════════════

class _HealthScoreCard extends StatelessWidget {
  final double value;
  final double resolutionRate;
  final int criticalCount;
  final String avgResponseLabel;
  final int totalAlerts;
  const _HealthScoreCard({
    required this.value,
    required this.resolutionRate,
    required this.criticalCount,
    required this.avgResponseLabel,
    required this.totalAlerts,
  });

  Color _scoreColor(BuildContext ctx) {
    final t = ctx.appTheme;
    if (value >= 75) return t.green;
    if (value >= 50) return t.yellow;
    return t.red;
  }

  String _verdict() {
    if (value >= 90) return 'Outstanding';
    if (value >= 75) return 'Healthy';
    if (value >= 50) return 'Watchful';
    if (value >= 25) return 'At risk';
    return 'Critical';
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final color = _scoreColor(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: context.isDark
              ? [theme.card, theme.card.withValues(alpha: 0.85)]
              : [Colors.white, color.withValues(alpha: 0.04)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.border),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: context.isDark ? 0.14 : 0.08),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (ctx, c) {
          final narrow = c.maxWidth < 520;
          final gauge = SizedBox(
            width: narrow ? 150 : 180,
            height: narrow ? 96 : 112,
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: value),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeOutCubic,
                  builder: (_, v, __) => CustomPaint(
                    painter: _HealthGaugePainter(
                      value: v,
                      color: color,
                      track: theme.border,
                    ),
                    size: Size.infinite,
                  ),
                ),
                Positioned(
                  bottom: 0,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: value),
                        duration: const Duration(milliseconds: 900),
                        curve: Curves.easeOutCubic,
                        builder: (_, v, __) => Text(
                          v.toStringAsFixed(0),
                          style: TextStyle(
                            fontSize: narrow ? 28 : 34,
                            fontWeight: FontWeight.w800,
                            color: color,
                            height: 1,
                          ),
                        ),
                      ),
                      Text(
                        '/ 100',
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );

          final stats = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      _verdict().toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: color,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Production Health',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: theme.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Composite of resolution rate and critical backlog.',
                style: TextStyle(fontSize: 12, color: theme.muted),
              ),
              const SizedBox(height: 14),
              _HealthMetric(
                icon: Icons.trending_up_rounded,
                color: theme.green,
                label: 'Resolution',
                value: '${resolutionRate.toStringAsFixed(0)}%',
              ),
              const SizedBox(height: 8),
              _HealthMetric(
                icon: Icons.warning_amber_rounded,
                color: criticalCount > 0 ? theme.red : theme.muted,
                label: 'Critical pending',
                value: '$criticalCount',
              ),
              const SizedBox(height: 8),
              _HealthMetric(
                icon: Icons.timer_outlined,
                color: theme.blue,
                label: 'Avg response',
                value: avgResponseLabel,
              ),
              const SizedBox(height: 8),
              _HealthMetric(
                icon: Icons.layers_rounded,
                color: theme.navy,
                label: 'Total this period',
                value: '$totalAlerts',
              ),
            ],
          );

          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [gauge, const SizedBox(height: 14), stats],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              gauge,
              const SizedBox(width: 22),
              Expanded(child: stats),
            ],
          );
        },
      ),
    );
  }
}

class _HealthMetric extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  const _HealthMetric({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return Row(
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(icon, size: 14, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: theme.muted,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            color: theme.text,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _HealthGaugePainter extends CustomPainter {
  final double value;
  final Color color;
  final Color track;
  _HealthGaugePainter({
    required this.value,
    required this.color,
    required this.track,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 14.0;
    final center = Offset(size.width / 2, size.height - 4);
    final radius = math.min(size.width / 2, size.height) - stroke / 2 - 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final trackPaint = Paint()
      ..color = track
      ..strokeWidth = stroke
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, math.pi, math.pi, false, trackPaint);

    final sweep = math.pi * (value / 100).clamp(0.0, 1.0);
    if (sweep > 0) {
      final progressPaint = Paint()
        ..shader = SweepGradient(
          startAngle: math.pi,
          endAngle: math.pi * 2,
          colors: [color.withValues(alpha: 0.55), color],
        ).createShader(rect)
        ..strokeWidth = stroke
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(rect, math.pi, sweep, false, progressPaint);

      final tipAngle = math.pi + sweep;
      final tip = Offset(
        center.dx + radius * math.cos(tipAngle),
        center.dy + radius * math.sin(tipAngle),
      );
      final glow = Paint()
        ..color = color.withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawCircle(tip, stroke / 2.2, glow);
      final tipDot = Paint()..color = color;
      canvas.drawCircle(tip, stroke / 3, tipDot);
    }
  }

  @override
  bool shouldRepaint(covariant _HealthGaugePainter old) =>
      old.value != value || old.color != color || old.track != track;
}

// ═══════════════════════════════════════════════════════════════════════════
// ELITE OVERVIEW TAB — Production Manager Dashboard
// Compact "single-eye" layout: factory selector commands all data; production
// health and alert history sit side-by-side; stat cards and predictive
// intelligence flow underneath.
// ═══════════════════════════════════════════════════════════════════════════

class AdminOverviewTab extends StatefulWidget {
  final int total, solved, inProgress, pending;
  final List<AlertModel> alerts;
  final List<AlertModel> allAlerts;
  final String timeRange, timeRangeLabel, timeRangeSubtitle;
  final String selectedUsine,
      filterConvoyeur,
      filterPoste,
      filterType,
      filterStatus;
  final void Function(String) onTimeRangeChange;
  final void Function(String) onUsineChange;
  final void Function(String) onConvoyeurChange;
  final void Function(String) onPosteChange;
  final void Function(String) onTypeChange;
  final void Function(String) onStatusChange;
  final VoidCallback onReset;
  final VoidCallback onExportCsv;
  final VoidCallback onExportExcel;

  const AdminOverviewTab({
    required this.onExportCsv,
    required this.onExportExcel,
    required this.total,
    required this.solved,
    required this.inProgress,
    required this.pending,
    required this.alerts,
    required this.allAlerts,
    required this.timeRange,
    required this.timeRangeLabel,
    required this.timeRangeSubtitle,
    required this.selectedUsine,
    required this.filterConvoyeur,
    required this.filterPoste,
    required this.filterType,
    required this.filterStatus,
    required this.onTimeRangeChange,
    required this.onUsineChange,
    required this.onConvoyeurChange,
    required this.onPosteChange,
    required this.onTypeChange,
    required this.onStatusChange,
    required this.onReset,
  });

  @override
  State<AdminOverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<AdminOverviewTab> {
  List<Factory> _factories = [];
  String? _historyFilter;
  final Set<String> _announcedCriticalIds = <String>{};
  final Set<String> _handledCriticalIds =
      <String>{}; // alerts user acknowledged/assigned
  final List<AlertModel> _criticalDialogQueue = <AlertModel>[];
  bool _criticalDialogOpen = false;

  MorningBriefing? _briefing;
  PredictiveModel? _predictions;
  PredictiveAccuracy? _accuracy;
  StreamSubscription<MorningBriefing?>? _briefSub;
  StreamSubscription<PredictiveModel?>? _predSub;
  StreamSubscription<PredictiveAccuracy?>? _accSub;
  bool _briefingWarmed = false;
  bool _predictionsWarmed = false;

  // On-device AI forecasts: once the SuperAdmin deploys a model, this
  // engine's overlay replaces the statistical model inside the Predictive
  // Failure Alerts and Predictive Risk cards.
  final ForecastOverviewEngine _forecastEngine = ForecastOverviewEngine();

  @override
  void initState() {
    super.initState();
    _seedKnownCriticalAlerts();
    _loadFactories();
    _bindPredictiveStreams();
    _warmPredictiveCaches();
    _forecastEngine.addListener(_onForecastEngineChanged);
    _forecastEngine.updateAlerts(widget.allAlerts);
  }

  void _onForecastEngineChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _briefSub?.cancel();
    _predSub?.cancel();
    _accSub?.cancel();
    _forecastEngine.removeListener(_onForecastEngineChanged);
    _forecastEngine.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AdminOverviewTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _detectIncomingCriticalAlerts(oldWidget.allAlerts);
    });
    if (oldWidget.selectedUsine != widget.selectedUsine) {
      _rebindFactoryScopedIntelStreams();
    }
    _forecastEngine.updateAlerts(widget.allAlerts);
  }

  void _rebindFactoryScopedIntelStreams() {
    _briefSub?.cancel();
    _predSub?.cancel();
    if (mounted) {
      setState(() {
        _briefSub = null;
        _predSub = null;
        _briefing = null;
        _predictions = null;
        _briefingWarmed = false;
        _predictionsWarmed = false;
      });
    } else {
      _briefSub = null;
      _predSub = null;
      _briefing = null;
      _predictions = null;
      _briefingWarmed = false;
      _predictionsWarmed = false;
    }
    _briefSub = PredictiveIntelService.instance
        .briefingStream(factory: _briefingFactory)
        .listen((b) {
          if (mounted) {
            setState(() => _briefing = b);
          }
        });
    _predSub = PredictiveIntelService.instance
        .predictionsStream(factory: _briefingFactory)
        .listen((p) {
          if (mounted) {
            setState(() => _predictions = p);
          }
        });
    _warmPredictiveCaches();
  }

  void _seedKnownCriticalAlerts() {
    for (final a in widget.allAlerts) {
      if (!a.isCritical) continue;
      _announcedCriticalIds.add(a.id);
    }
  }

  void _detectIncomingCriticalAlerts(List<AlertModel> previousAlerts) {
    final previousIds = previousAlerts
        .where((a) => a.isCritical)
        .map((a) => a.id)
        .toSet();
    final incoming = widget.allAlerts.where((a) {
      if (!a.isCritical) return false;
      if (a.status != 'disponible') return false;
      if (_announcedCriticalIds.contains(a.id)) return false;
      if (_handledCriticalIds.contains(a.id)) {
        return false; // never show again if handled
      }
      return !previousIds.contains(a.id);
    }).toList();
    if (incoming.isEmpty) return;
    for (final a in incoming) {
      _announcedCriticalIds.add(a.id);
      _criticalDialogQueue.add(a);
    }
    _requestShowNextCriticalDialog();
  }

  void _requestShowNextCriticalDialog() {
    if (!mounted || _criticalDialogOpen || _criticalDialogQueue.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _criticalDialogOpen || _criticalDialogQueue.isEmpty) {
        return;
      }
      _showNextCriticalDialog();
    });
  }

  Future<void> _showNextCriticalDialog() async {
    if (!mounted || _criticalDialogOpen || _criticalDialogQueue.isEmpty) return;
    _criticalDialogOpen = true;
    final alert = _criticalDialogQueue.removeAt(0);
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'critical-arrival',
      barrierColor: Colors.black.withValues(alpha: 0.68),
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (dialogContext, _, __) => _CriticalArrivalDialog(
        alert: alert,
        describe: _getAlertDisplayDescription,
      ),
      transitionBuilder: (_, anim, __, child) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.88, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
    // Mark as handled once dialog is dismissed (whether acknowledged or assigned)
    _handledCriticalIds.add(alert.id);
    _criticalDialogOpen = false;
    if (_criticalDialogQueue.isNotEmpty) {
      _requestShowNextCriticalDialog();
    }
  }

  void _loadFactories() {
    ServiceLocator.instance.hierarchyService.getFactories().listen((factories) {
      if (mounted) setState(() => _factories = factories);
    });
  }

  String? get _briefingFactory =>
      widget.selectedUsine == 'all' ? null : widget.selectedUsine;

  void _bindPredictiveStreams() {
    _briefSub = PredictiveIntelService.instance
        .briefingStream(factory: _briefingFactory)
        .listen((b) {
          if (mounted) setState(() => _briefing = b);
        });
    _predSub = PredictiveIntelService.instance
        .predictionsStream(factory: _briefingFactory)
        .listen((p) {
          if (mounted) setState(() => _predictions = p);
        });
    _accSub = PredictiveIntelService.instance.accuracyStream().listen((a) {
      if (mounted) setState(() => _accuracy = a);
    });
  }

  Future<void> _warmPredictiveCaches() async {
    final requestedFactory = _briefingFactory;
    if (!_briefingWarmed) {
      _briefingWarmed = true;
      unawaited(() async {
        final briefing = await PredictiveIntelService.instance.fetchBriefing(
          factory: requestedFactory,
        );
        if (mounted &&
            requestedFactory == _briefingFactory &&
            briefing != null) {
          setState(() => _briefing = briefing);
        }
      }());
    }
    if (!_predictionsWarmed) {
      _predictionsWarmed = true;
      unawaited(() async {
        final predictions = await PredictiveIntelService.instance
            .fetchPredictions(factory: requestedFactory);
        if (mounted &&
            requestedFactory == _briefingFactory &&
            predictions != null) {
          setState(() => _predictions = predictions);
        }
      }());
    }
  }

  Future<void> _refreshBriefing() async {
    final requestedFactory = _briefingFactory;
    final fresh = await PredictiveIntelService.instance.fetchBriefing(
      force: true,
      factory: requestedFactory,
    );
    if (mounted && requestedFactory == _briefingFactory && fresh != null) {
      setState(() => _briefing = fresh);
    }
  }

  List<String> _convoyeurs() {
    if (widget.selectedUsine == 'all') return ['all'];
    Factory? factory;
    for (final f in _factories) {
      if (f.name == widget.selectedUsine) {
        factory = f;
        break;
      }
    }
    if (factory == null) return ['all'];
    return ['all', ...factory.conveyors.values.map((c) => c.number.toString())];
  }

  List<String> _postes() {
    if (widget.selectedUsine == 'all') return ['all'];
    Factory? factory;
    for (final f in _factories) {
      if (f.name == widget.selectedUsine) {
        factory = f;
        break;
      }
    }
    if (factory == null) return ['all'];
    if (widget.filterConvoyeur == 'all') return ['all'];
    Conveyor? conveyor;
    for (final c in factory.conveyors.values) {
      if (c.number.toString() == widget.filterConvoyeur) {
        conveyor = c;
        break;
      }
    }
    if (conveyor == null) return ['all'];
    return [
      'all',
      ...conveyor.stations.values.map((s) => s.id.replaceAll('station_', '')),
    ];
  }

  List<AlertModel> get _criticalUnclaimedAlerts => widget.allAlerts
      .where(
        (a) =>
            a.isCritical &&
            a.status == 'disponible' &&
            (widget.selectedUsine == 'all' || a.usine == widget.selectedUsine),
      )
      .toList();

  int get _criticalUnclaimedCount => _criticalUnclaimedAlerts.length;

  void _setHistoryFilter(String? filter) {
    setState(() {
      _historyFilter = (_historyFilter == filter) ? null : filter;
    });
  }

  Map<String, Map<String, int>> _typeStats() {
    const keys = [
      'qualite',
      'maintenance',
      'defaut_produit',
      'manque_ressource',
    ];
    return {
      for (final k in keys)
        k: {
          'total': widget.alerts.where((a) => a.type == k).length,
          'solved': widget.alerts
              .where((a) => a.type == k && a.status == 'validee')
              .length,
          'pending': widget.alerts
              .where((a) => a.type == k && a.status != 'validee')
              .length,
        },
    };
  }

  List<String> _usines() => [
    'all',
    ...widget.allAlerts
        .map((a) => a.usine)
        .where((u) => u.isNotEmpty && u != 'all')
        .toSet()
        .toList()
      ..sort(),
  ];

  // Factory list combining hierarchy and observed alerts so the master selector
  // surfaces every factory the PM can act on.
  List<String> _factoryOptions() {
    final names = <String>{};
    for (final f in _factories) {
      if (f.name.isNotEmpty) names.add(f.name);
    }
    for (final a in widget.allAlerts) {
      if (a.usine.isNotEmpty && a.usine != 'all') names.add(a.usine);
    }
    final list = names.toList()..sort();
    return ['all', ...list];
  }

  String _getAlertDisplayDescription(AlertModel alert) {
    if (alert.description.trim().isNotEmpty) return alert.description;
    switch (alert.type) {
      case 'qualite':
        return 'Quality issue detected on production line';
      case 'maintenance':
        return 'Maintenance required on equipment';
      case 'defaut_produit':
        return 'Damaged product detected';
      case 'manque_ressource':
        return 'Resource deficiency - missing raw materials';
      default:
        return 'Alert detected';
    }
  }

  List<int> _last7DaysCounts(bool Function(AlertModel) test) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final out = List<int>.filled(7, 0);
    for (final a in widget.allAlerts) {
      if (widget.selectedUsine != 'all' && a.usine != widget.selectedUsine) {
        continue;
      }
      if (!test(a)) continue;
      final d = DateTime(a.timestamp.year, a.timestamp.month, a.timestamp.day);
      final daysAgo = today.difference(d).inDays;
      if (daysAgo >= 0 && daysAgo < 7) out[6 - daysAgo]++;
    }
    return out;
  }

  double _trendPct(List<int> data) {
    if (data.length < 2) return 0;
    final mid = data.length ~/ 2;
    final first = data.sublist(0, mid).fold<int>(0, (a, b) => a + b);
    final second = data.sublist(mid).fold<int>(0, (a, b) => a + b);
    if (first == 0) return second > 0 ? 100 : 0;
    return ((second - first) / first) * 100;
  }

  double _healthScore() {
    final total = widget.total;
    if (total == 0) return 100;
    final resolutionRate = (widget.solved / total) * 100;
    final critPenalty = (_criticalUnclaimedCount * 8.0).clamp(0, 40).toDouble();
    return (resolutionRate - critPenalty).clamp(0.0, 100.0);
  }

  Duration _avgResolutionTime() {
    final solved = widget.allAlerts
        .where(
          (a) =>
              a.status == 'validee' &&
              a.elapsedTime != null &&
              a.elapsedTime! > 0 &&
              (widget.selectedUsine == 'all' ||
                  a.usine == widget.selectedUsine),
        )
        .toList();
    if (solved.isEmpty) return Duration.zero;
    final totalMin = solved.fold<int>(0, (sum, a) => sum + a.elapsedTime!);
    return Duration(minutes: totalMin ~/ solved.length);
  }

  String _fmtDuration(Duration d) {
    if (d.inMinutes <= 0) return '—';
    if (d.inHours >= 1) return '${d.inHours}h ${d.inMinutes % 60}m';
    return '${d.inMinutes}m';
  }

  Future<void> _exportFilteredAlertsPdf(
    List<AlertModel> alertsToExport,
    String reportName,
  ) async {
    if (alertsToExport.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No alerts match the selected filters'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    try {
      await AlertPdfService.exportAndShare(
        alerts: alertsToExport,
        scopeLabel: widget.selectedUsine == 'all'
            ? 'All Plants'
            : widget.selectedUsine,
        timeRangeLabel: widget.timeRangeLabel,
        labelType: (t) => adminTypeLabel(context, t),
        reportName: reportName,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('PDF export failed: ${UserFriendlyError.message(e)}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _openFilterSheet() {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: _FilterSheet(
          usines: _usines(),
          convoyeurs: _convoyeurs(),
          postes: _postes(),
          selectedUsine: widget.selectedUsine,
          filterConvoyeur: widget.filterConvoyeur,
          filterPoste: widget.filterPoste,
          filterType: widget.filterType,
          filterStatus: widget.filterStatus,
          timeRange: widget.timeRange,
          onUsine: widget.onUsineChange,
          onConvoyeur: widget.onConvoyeurChange,
          onPoste: widget.onPosteChange,
          onType: widget.onTypeChange,
          onStatus: widget.onStatusChange,
          onTime: widget.onTimeRangeChange,
          onReset: () {
            widget.onReset();
            setState(() {
              _historyFilter = null;
            });
          },
        ),
      ),
    );
  }

  int _activeFilterCount() {
    var n = 0;
    if (widget.timeRange != 'all') n++;
    if (widget.selectedUsine != 'all') n++;
    if (widget.filterConvoyeur != 'all') n++;
    if (widget.filterPoste != 'all') n++;
    if (widget.filterType != 'all') n++;
    if (widget.filterStatus != 'all') n++;
    return n;
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final ts = _typeStats();
    final health = _healthScore();
    final receivedSpark = _last7DaysCounts((a) => a.status == 'disponible');
    final claimedSpark = _last7DaysCounts((a) => a.status == 'en_cours');
    final fixedSpark = _last7DaysCounts((a) => a.status == 'validee');
    final totalSpark = _last7DaysCounts((_) => true);
    final resolutionRate = widget.total == 0
        ? 0.0
        : (widget.solved / widget.total) * 100.0;
    final scopedPreds = _predictions;

    return LayoutBuilder(
      builder: (ctx, constraints) {
        final wide = constraints.maxWidth >= 980;

        final factoryRow = _FactoryMasterBar(
          factories: _factoryOptions(),
          selected: widget.selectedUsine,
          activeCount: _activeFilterCount(),
          timeRangeLabel: widget.timeRangeLabel,
          onChanged: widget.onUsineChange,
          onOpenFilters: _openFilterSheet,
          onReset: () {
            widget.onReset();
            setState(() {
              _historyFilter = null;
            });
          },
        );

        final briefing = AIMorningBriefingHero(
          briefing: _briefing,
          timeRangeLabel: widget.timeRangeLabel,
          timeRangeSubtitle: widget.timeRangeSubtitle,
          onRefresh: _refreshBriefing,
          compact: true,
        );

        final healthCard = _HealthScoreCard(
          value: health,
          resolutionRate: resolutionRate,
          criticalCount: _criticalUnclaimedCount,
          avgResponseLabel: _fmtDuration(_avgResolutionTime()),
          totalAlerts: widget.total,
        );

        final statGrid = LayoutBuilder(
          builder: (gctx, gc) {
            // The four stat cards stay in a snug 2x2 or 1x4 layout under the
            // health gauge, never stretching wider than the alert history.
            final twoCol = gc.maxWidth < 520;
            final cards = [
              _statCardReceived(theme, receivedSpark),
              _statCardClaimed(theme, claimedSpark),
              _statCardFixed(theme, fixedSpark),
              _statCardTotal(theme, totalSpark),
            ];
            if (twoCol) {
              return Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: cards[0]),
                      const SizedBox(width: 10),
                      Expanded(child: cards[1]),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: cards[2]),
                      const SizedBox(width: 10),
                      Expanded(child: cards[3]),
                    ],
                  ),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: cards[0]),
                const SizedBox(width: 10),
                Expanded(child: cards[1]),
                const SizedBox(width: 10),
                Expanded(child: cards[2]),
                const SizedBox(width: 10),
                Expanded(child: cards[3]),
              ],
            );
          },
        );

        final leftColumn = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            healthCard,
            const SizedBox(height: 12),
            Expanded(child: statGrid),
          ],
        );

        final historyBox = _AlertHistoryBox(
          allAlerts: widget.allAlerts,
          quickFilter: _historyFilter,
          onClearQuickFilter: () => setState(() => _historyFilter = null),
          factories: _factories,
          scope: widget.selectedUsine == 'all'
              ? 'All Plants'
              : widget.selectedUsine,
          onExportPdf: _exportFilteredAlertsPdf,
        );

        // The deployed AI forecaster takes over both predictive cards; the
        // statistical model remains the fallback until a model is deployed
        // (or when the current scope has no machine forecasts yet).
        final forecastOverlay =
            _forecastEngine.overlayFor(widget.selectedUsine, scopedPreds);
        final effectivePreds = forecastOverlay ?? scopedPreds;
        final forecastLive = forecastOverlay != null;

        final failureCard = PredictiveFailureCard(
          accuracy: _accuracy,
          model: effectivePreds,
          forecastLive: forecastLive,
          describeType: (type) => adminTypeLabel(context, type),
        );
        final riskCard = PredictiveRiskHeatmap(
          stats: ts,
          model: effectivePreds,
          forecastLive: forecastLive,
          activeFilter: _historyFilter,
          onTap: _setHistoryFilter,
        );

        final critical = _criticalUnclaimedCount > 0
            ? Padding(
                padding: const EdgeInsets.only(top: 14),
                child: CriticalAlertsCard(
                  alerts: _criticalUnclaimedAlerts,
                  onAlertTap: (a) => _setHistoryFilter(a.type),
                  describe: _getAlertDisplayDescription,
                  maxHeight: 300,
                ),
              )
            : const SizedBox.shrink();

        // Wide layout: 2x2 grid.
        //   Production health   |  Predictive failure alerts
        //   Alert history       |  Predictive risk · next 24h
        Widget body;
        if (wide) {
          body = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              briefing,
              const SizedBox(height: 12),
              factoryRow,
              const SizedBox(height: 14),
              SizedBox(
                height: 520,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 6, child: leftColumn),
                    const SizedBox(width: 14),
                    Expanded(
                      flex: 5,
                      child: SingleChildScrollView(child: failureCard),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 520,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 6, child: historyBox),
                    const SizedBox(width: 14),
                    Expanded(
                      flex: 5,
                      child: SingleChildScrollView(child: riskCard),
                    ),
                  ],
                ),
              ),
              critical,
            ],
          );
        } else {
          body = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              briefing,
              const SizedBox(height: 12),
              factoryRow,
              const SizedBox(height: 14),
              healthCard,
              const SizedBox(height: 12),
              statGrid,
              const SizedBox(height: 14),
              failureCard,
              const SizedBox(height: 12),
              SizedBox(height: 520, child: historyBox),
              const SizedBox(height: 14),
              riskCard,
              critical,
            ],
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 60),
          child: body,
        );
      },
    );
  }

  Widget _statCardReceived(AppTheme theme, List<int> spark) => EliteStatCard(
    label: 'Pending',
    value: widget.pending,
    icon: Icons.inbox_rounded,
    color: theme.orange,
    accentLt: theme.orangeLt,
    spark: spark,
    trendPct: _trendPct(spark),
    criticalCount: _criticalUnclaimedCount,
    isActive: _historyFilter == 'pending',
    onTap: () => _setHistoryFilter('pending'),
    onCriticalTap: () => _setHistoryFilter('critical'),
  );

  Widget _statCardClaimed(AppTheme theme, List<int> spark) => EliteStatCard(
    label: 'Claimed',
    value: widget.inProgress,
    icon: Icons.hourglass_bottom_rounded,
    color: theme.blue,
    accentLt: theme.blueLt,
    spark: spark,
    trendPct: _trendPct(spark),
    isActive: _historyFilter == 'en_cours',
    onTap: () => _setHistoryFilter('en_cours'),
  );

  Widget _statCardFixed(AppTheme theme, List<int> spark) => EliteStatCard(
    label: 'Fixed',
    value: widget.solved,
    icon: Icons.verified_rounded,
    color: theme.green,
    accentLt: theme.greenLt,
    spark: spark,
    trendPct: _trendPct(spark),
    isActive: _historyFilter == 'validated',
    onTap: () => _setHistoryFilter('validated'),
  );

  Widget _statCardTotal(AppTheme theme, List<int> spark) => EliteStatCard(
    label: 'Total',
    value: widget.total,
    icon: Icons.dashboard_rounded,
    color: theme.navy,
    accentLt: theme.navyLt,
    spark: spark,
    trendPct: _trendPct(spark),
    isActive: _historyFilter == 'total',
    onTap: () => _setHistoryFilter('total'),
  );
}

