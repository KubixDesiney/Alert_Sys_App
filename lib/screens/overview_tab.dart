import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/alert_model.dart';
import '../../models/hierarchy_model.dart';
import '../../services/alert_pdf_service.dart';
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


  @override
  void initState() {
    super.initState();
    _seedKnownCriticalAlerts();
    _loadFactories();
    _bindPredictiveStreams();
    _warmPredictiveCaches();
  }

  @override
  void dispose() {
    _briefSub?.cancel();
    _predSub?.cancel();
    _accSub?.cancel();
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

        final failureCard = PredictiveFailureCard(
          accuracy: _accuracy,
          model: scopedPreds,
          describeType: (type) => adminTypeLabel(context, type),
        );
        final riskCard = PredictiveRiskHeatmap(
          stats: ts,
          model: scopedPreds,
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

class _CriticalArrivalDialog extends StatefulWidget {
  final AlertModel alert;
  final String Function(AlertModel) describe;
  const _CriticalArrivalDialog({required this.alert, required this.describe});

  @override
  State<_CriticalArrivalDialog> createState() => _CriticalArrivalDialogState();
}

class _CriticalArrivalDialogState extends State<_CriticalArrivalDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  AssigneeSuggestion? _suggestion;
  bool _loadingSuggestion = false;
  bool _assigning = false;
  String? _assignError;
  bool _assignedDone = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1150),
    )..repeat(reverse: true);
    _loadSuggestion();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _loadSuggestion() async {
    setState(() {
      _loadingSuggestion = true;
    });
    final s = await PredictiveIntelService.instance.suggestAssignee(
      widget.alert.id,
    );
    if (!mounted) return;
    setState(() {
      _suggestion = s;
      _loadingSuggestion = false;
    });
  }

  Future<void> _assignSupervisor() async {
    if (_assigning || _assignedDone) return;
    final s = _suggestion;
    final uid = s?.bestUid;
    if (uid == null || uid.isEmpty) return;
    setState(() {
      _assigning = true;
      _assignError = null;
    });
    try {
      await ServiceLocator.instance.alertService.takeAlert(
        widget.alert.id,
        uid,
        s?.bestName ?? 'AI assignment',
      );
      if (!mounted) return;
      setState(() {
        _assigning = false;
        _assignedDone = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _assigning = false;
        _assignError = 'Assignment failed. Please retry.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final alert = widget.alert;
    final typeColor = adminTypeColor(context, alert.type);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 620),
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF2D0006),
                  Color(0xFF5A000D),
                  Color(0xFF7E0A16),
                ],
              ),
              border: Border.all(color: const Color(0xFFFF6B73), width: 1.2),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x99FF1D2E),
                  blurRadius: 30,
                  spreadRadius: 2,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AnimatedBuilder(
                      animation: _pulse,
                      builder: (_, __) {
                        final scale = 0.9 + (_pulse.value * 0.24);
                        return Transform.scale(
                          scale: scale,
                          child: Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0x33FF6B73),
                              border: Border.all(
                                color: const Color(0xFFFF8F96),
                                width: 1.1,
                              ),
                            ),
                            child: const Icon(
                              Icons.warning_amber_rounded,
                              color: Color(0xFFFFD8DB),
                              size: 24,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'CRITICAL ALERT ARRIVED',
                            style: TextStyle(
                              color: const Color(0xFFFFDDE0),
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            adminTypeLabel(context, alert.type),
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                      color: const Color(0xFFFFCAD0),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: const Color(0x55140004),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0x66FF8D95)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.describe(alert),
                        style: const TextStyle(
                          color: Color(0xFFFFECED),
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${alert.usine} · Line ${alert.convoyeur} · WS ${alert.poste}',
                        style: const TextStyle(
                          color: Color(0xFFFFCAD0),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (alert.description.trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          alert.description,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFFFE1E4),
                            fontSize: 12,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0x2A7B4BFF),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0x668E6BFF)),
                        ),
                        child: _loadingSuggestion
                            ? const Text(
                                'AI suggestion: analyzing best supervisor...',
                                style: TextStyle(
                                  color: Color(0xFFE7DDFF),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              )
                            : Text(
                                _suggestion?.bestUid != null
                                    ? 'AI suggestion: ${_suggestion?.bestName ?? 'Supervisor'} (${_suggestion?.confidencePct ?? 0}%)'
                                    : 'AI suggestion: no eligible supervisor right now.',
                                style: const TextStyle(
                                  color: Color(0xFFE7DDFF),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                      if (_assignError != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _assignError!,
                          style: const TextStyle(
                            color: Color(0xFFFFC5C9),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.emergency_rounded, color: typeColor, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'Immediate attention required',
                      style: TextStyle(
                        color: const Color(0xFFFFD6D9),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: _assigning ? null : _assignSupervisor,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF7B4BFF),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: const Color(0xFF6B3EE0),
                        disabledForegroundColor: const Color(0xFFE8DEFF),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                      ),
                      child: Text(
                        _assigning
                            ? 'Assigning...'
                            : (_assignedDone
                                  ? 'Assigned'
                                  : 'Assign Supervisor'),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFFF2E42),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                      ),
                      child: const Text(
                        'Acknowledge',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// FACTORY MASTER BAR — single big selector that scopes the whole tab.
// ═══════════════════════════════════════════════════════════════════════════

class _FactoryMasterBar extends StatelessWidget {
  final List<String> factories;
  final String selected;
  final int activeCount;
  final String timeRangeLabel;
  final void Function(String) onChanged;
  final VoidCallback onOpenFilters;
  final VoidCallback onReset;
  const _FactoryMasterBar({
    required this.factories,
    required this.selected,
    required this.activeCount,
    required this.timeRangeLabel,
    required this.onChanged,
    required this.onOpenFilters,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final isDark = context.isDark;
    final isAll = selected == 'all';

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  t.navy.withValues(alpha: 0.18),
                  t.purple.withValues(alpha: 0.10),
                ]
              : [t.navyLt, t.purple.withValues(alpha: 0.05)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.navy.withValues(alpha: 0.32)),
      ),
      child: LayoutBuilder(
        builder: (ctx, c) {
          final narrow = c.maxWidth < 620;
          final factoryPicker = Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: t.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: t.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [t.navy, t.purple]),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.factory_rounded,
                    size: 17,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'PLANT SCOPE',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.4,
                          color: t.muted,
                        ),
                      ),
                      DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: factories.contains(selected)
                              ? selected
                              : 'all',
                          isExpanded: true,
                          isDense: true,
                          style: TextStyle(
                            fontSize: 14,
                            color: t.text,
                            fontWeight: FontWeight.w700,
                          ),
                          dropdownColor: t.card,
                          icon: Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: t.navy,
                          ),
                          items: factories
                              .map(
                                (f) => DropdownMenuItem(
                                  value: f,
                                  child: Text(
                                    f == 'all' ? 'All Plants' : f,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: t.text,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v != null) onChanged(v);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );

          final scopeChip = Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isAll
                  ? t.muted.withValues(alpha: 0.14)
                  : t.green.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(
                color: (isAll ? t.muted : t.green).withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isAll ? Icons.public_rounded : Icons.location_on_rounded,
                  size: 13,
                  color: isAll ? t.muted : t.green,
                ),
                const SizedBox(width: 5),
                Text(
                  isAll ? 'Aggregate' : 'Scoped',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: isAll ? t.muted : t.green,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          );

          final timeChip = Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: t.orange.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: t.orange.withValues(alpha: 0.35)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.calendar_month_rounded, size: 13, color: t.orange),
                const SizedBox(width: 5),
                Text(
                  timeRangeLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: t.orange,
                  ),
                ),
              ],
            ),
          );

          final resetBtn = activeCount > 0
              ? IconButton(
                  onPressed: onReset,
                  icon: Icon(Icons.refresh_rounded, color: t.red),
                  tooltip: 'Reset filters',
                  style: IconButton.styleFrom(
                    backgroundColor: t.card,
                    side: BorderSide(color: t.border),
                    padding: const EdgeInsets.all(9),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                )
              : const SizedBox.shrink();

          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                factoryPicker,
                const SizedBox(height: 10),
                Row(
                  children: [
                    scopeChip,
                    const SizedBox(width: 6),
                    timeChip,
                    const Spacer(),
                    if (activeCount > 0) ...[resetBtn],
                  ],
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(flex: 5, child: factoryPicker),
              const SizedBox(width: 12),
              scopeChip,
              const SizedBox(width: 6),
              timeChip,
              const Spacer(),
              if (activeCount > 0) ...[resetBtn],
            ],
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// HISTORY FILTERS — data class holding local filter state for the history box
// ═══════════════════════════════════════════════════════════════════════════

class _HistoryFilters {
  final String factory, conveyeur, poste, type, status, critical, timeRange;
  const _HistoryFilters({
    required this.factory,
    required this.conveyeur,
    required this.poste,
    required this.type,
    required this.status,
    required this.critical,
    required this.timeRange,
  });

  bool get hasActive =>
      factory != 'all' ||
      conveyeur != 'all' ||
      poste != 'all' ||
      type != 'all' ||
      status != 'all' ||
      critical != 'all' ||
      timeRange != 'all';

  int get activeCount =>
      [factory, conveyeur, poste, type, status, critical, timeRange]
          .where((v) => v != 'all')
          .length;
}

// ═══════════════════════════════════════════════════════════════════════════
// HISTORY FILTER SHEET — self-contained StatefulWidget dialog
// ═══════════════════════════════════════════════════════════════════════════

class _HistoryFilterSheet extends StatefulWidget {
  final _HistoryFilters current;
  final List<String> factories;
  final List<Factory> rawFactories;
  final List<AlertModel> allAlerts;

  const _HistoryFilterSheet({
    required this.current,
    required this.factories,
    required this.rawFactories,
    required this.allAlerts,
  });

  @override
  State<_HistoryFilterSheet> createState() => _HistoryFilterSheetState();
}

class _HistoryFilterSheetState extends State<_HistoryFilterSheet> {
  late String _factory;
  late String _conveyeur;
  late String _poste;
  late String _type;
  late String _status;
  late String _critical;
  late String _timeRange;

  @override
  void initState() {
    super.initState();
    _factory = widget.current.factory;
    _conveyeur = widget.current.conveyeur;
    _poste = widget.current.poste;
    _type = widget.current.type;
    _status = widget.current.status;
    _critical = widget.current.critical;
    _timeRange = widget.current.timeRange;
  }

  List<String> _conveyeurOptions() {
    if (_factory == 'all') {
      final vals = <String>{};
      for (final a in widget.allAlerts) {
        final cv = a.convoyeur.toString();
        if (cv.isNotEmpty && cv != '0') vals.add(cv);
      }
      return ['all', ...vals.toList()..sort()];
    }
    Factory? fac;
    for (final f in widget.rawFactories) {
      if (f.name == _factory) {
        fac = f;
        break;
      }
    }
    if (fac == null) return ['all'];
    return ['all', ...fac.conveyors.values.map((c) => c.number.toString())];
  }

  List<String> _posteOptions() {
    if (_conveyeur == 'all') return ['all'];
    if (_factory != 'all') {
      Factory? fac;
      for (final f in widget.rawFactories) {
        if (f.name == _factory) {
          fac = f;
          break;
        }
      }
      if (fac != null) {
        Conveyor? conv;
        for (final c in fac.conveyors.values) {
          if (c.number.toString() == _conveyeur) {
            conv = c;
            break;
          }
        }
        if (conv != null) {
          return [
            'all',
            ...conv.stations.values.map((s) => s.id.replaceAll('station_', '')),
          ];
        }
      }
    }
    // Fallback: build from alerts for that conveyor
    final vals = <String>{};
    for (final a in widget.allAlerts) {
      if (a.convoyeur.toString() == _conveyeur) {
        final p = a.poste.toString();
        if (p.isNotEmpty && p != '0') vals.add(p);
      }
    }
    return ['all', ...vals.toList()..sort()];
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final conveyeurOpts = _conveyeurOptions();
    final posteOpts = _posteOptions();

    // Ensure current values are valid given the options
    final safeConveyeur = conveyeurOpts.contains(_conveyeur) ? _conveyeur : 'all';
    final safePoste = posteOpts.contains(_poste) ? _poste : 'all';

    return SafeArea(
      child: LayoutBuilder(
        builder: (ctx, c) {
          final maxHeight = c.maxHeight > 0 ? c.maxHeight * 0.92 : 780.0;
          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 820, maxHeight: maxHeight),
              child: Container(
                decoration: BoxDecoration(
                  color: theme.card,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: theme.border),
                ),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
                  shrinkWrap: true,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: theme.border,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: theme.navy.withValues(alpha: 0.13),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.tune_rounded,
                            size: 18,
                            color: theme.navy,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'History Filters',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  color: theme.text,
                                ),
                              ),
                              Text(
                                'Refine alert history only — dashboard stats are unaffected',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: theme.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            setState(() {
                              _factory = 'all';
                              _conveyeur = 'all';
                              _poste = 'all';
                              _type = 'all';
                              _status = 'all';
                              _critical = 'all';
                              _timeRange = 'all';
                            });
                          },
                          icon: const Icon(Icons.refresh_rounded, size: 14),
                          label: const Text(
                            'Reset',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: theme.red,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    // Plant
                    _FilterDropdown(
                      label: 'Plant',
                      value: _factory,
                      items: widget.factories
                          .map(
                            (v) => DropdownMenuItem(
                              value: v,
                              child: Text(
                                v == 'all' ? 'All Plants' : v,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        setState(() {
                          _factory = v;
                          _conveyeur = 'all';
                          _poste = 'all';
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    // Conveyor
                    _FilterDropdown(
                      label: 'Conveyor',
                      value: safeConveyeur,
                      items: conveyeurOpts
                          .map(
                            (v) => DropdownMenuItem(
                              value: v,
                              child: Text(
                                v == 'all' ? 'All Conveyors' : 'Conv. $v',
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        setState(() {
                          _conveyeur = v;
                          _poste = 'all';
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    // Workstation
                    _FilterDropdown(
                      label: 'Workstation',
                      value: safePoste,
                      items: posteOpts
                          .map(
                            (v) => DropdownMenuItem(
                              value: v,
                              child: Text(
                                v == 'all' ? 'All Workstations' : 'WS $v',
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => _poste = v),
                    ),
                    const SizedBox(height: 10),
                    // Alert Type
                    _FilterDropdown(
                      label: 'Alert Type',
                      value: _type,
                      items: [
                        const DropdownMenuItem(
                          value: 'all',
                          child: Text(
                            'All Types',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                        ...[
                          'qualite',
                          'maintenance',
                          'defaut_produit',
                          'manque_ressource',
                        ].map(
                          (t) => DropdownMenuItem(
                            value: t,
                            child: Text(
                              adminTypeLabel(context, t),
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ),
                      ],
                      onChanged: (v) => setState(() => _type = v),
                    ),
                    const SizedBox(height: 10),
                    // Status
                    _FilterDropdown(
                      label: 'Status',
                      value: _status,
                      items: const [
                        DropdownMenuItem(
                          value: 'all',
                          child: Text(
                            'All Statuses',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'disponible',
                          child: Text(
                            'Pending',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'en_cours',
                          child: Text(
                            'Claimed',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'validee',
                          child: Text(
                            'Fixed',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                      onChanged: (v) => setState(() => _status = v),
                    ),
                    const SizedBox(height: 10),
                    // Criticality — toggle chips
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'CRITICALITY',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: theme.muted,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            for (final opt in [
                              ('all', 'All'),
                              ('critical', 'Critical Only'),
                              ('normal', 'Normal Only'),
                            ]) ...[
                              ChoiceChip(
                                label: Text(
                                  opt.$2,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: _critical == opt.$1
                                        ? Colors.white
                                        : theme.text,
                                  ),
                                ),
                                selected: _critical == opt.$1,
                                selectedColor: theme.navy,
                                backgroundColor: theme.scaffold,
                                side: BorderSide(
                                  color: _critical == opt.$1
                                      ? theme.navy
                                      : theme.border,
                                ),
                                onSelected: (_) =>
                                    setState(() => _critical = opt.$1),
                              ),
                              const SizedBox(width: 8),
                            ],
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Time Range
                    _FilterDropdown(
                      label: 'Time Range',
                      value: _timeRange,
                      items: const [
                        DropdownMenuItem(
                          value: 'all',
                          child: Text(
                            'All Time',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'today',
                          child: Text('Today', style: TextStyle(fontSize: 13)),
                        ),
                        DropdownMenuItem(
                          value: 'week',
                          child: Text(
                            'Last 7 Days',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'month',
                          child: Text(
                            'This Month',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'year',
                          child: Text(
                            'This Year',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                      onChanged: (v) => setState(() => _timeRange = v),
                    ),
                    const SizedBox(height: 18),
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop(
                          _HistoryFilters(
                            factory: _factory,
                            conveyeur: safeConveyeur,
                            poste: safePoste,
                            type: _type,
                            status: _status,
                            critical: _critical,
                            timeRange: _timeRange,
                          ),
                        );
                      },
                      icon: const Icon(Icons.check_rounded, size: 16),
                      label: const Text(
                        'Apply',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.navy,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ALERT HISTORY BOX — self-contained StatefulWidget with own filter state
// ═══════════════════════════════════════════════════════════════════════════

class _AlertHistoryBox extends StatefulWidget {
  final List<AlertModel> allAlerts;
  final String? quickFilter;
  final VoidCallback onClearQuickFilter;
  final List<Factory> factories;
  final String scope;
  final Future<void> Function(List<AlertModel>, String reportName) onExportPdf;

  const _AlertHistoryBox({
    required this.allAlerts,
    required this.quickFilter,
    required this.onClearQuickFilter,
    required this.factories,
    required this.scope,
    required this.onExportPdf,
  });

  @override
  State<_AlertHistoryBox> createState() => _AlertHistoryBoxState();
}

class _AlertHistoryBoxState extends State<_AlertHistoryBox> {
  String _factory = 'all';
  String _conveyeur = 'all';
  String _poste = 'all';
  String _type = 'all';
  String _status = 'all';
  String _critical = 'all';
  String _timeRange = 'all';
  int _pageIndex = 0;
  int _pageSize = 10;
  static const _pageSizeOptions = [5, 10, 25, 50, 100];

  List<String> _factoryOptions() {
    final names = <String>{};
    for (final f in widget.factories) {
      if (f.name.isNotEmpty) names.add(f.name);
    }
    for (final a in widget.allAlerts) {
      if (a.usine.isNotEmpty && a.usine != 'all') names.add(a.usine);
    }
    return ['all', ...names.toList()..sort()];
  }

  List<AlertModel> get _filteredAlerts {
    final now = DateTime.now();
    return widget.allAlerts.where((a) {
      if (_factory != 'all' && a.usine != _factory) return false;
      if (_conveyeur != 'all' && a.convoyeur.toString() != _conveyeur) {
        return false;
      }
      if (_poste != 'all' && a.poste.toString() != _poste) return false;
      if (_type != 'all' && a.type != _type) return false;
      if (_status != 'all' && a.status != _status) return false;
      if (_critical == 'critical' && !a.isCritical) return false;
      if (_critical == 'normal' && a.isCritical) return false;
      switch (_timeRange) {
        case 'today':
          if (!(a.timestamp.year == now.year &&
              a.timestamp.month == now.month &&
              a.timestamp.day == now.day)) { return false; }
        case 'week':
          if (now.difference(a.timestamp).inDays > 7) { return false; }
        case 'month':
          if (!(a.timestamp.year == now.year &&
              a.timestamp.month == now.month)) { return false; }
        case 'year':
          if (a.timestamp.year != now.year) { return false; }
      }
      if (widget.quickFilter != null) {
        switch (widget.quickFilter) {
          case 'pending':
            if (a.status != 'disponible') return false;
          case 'en_cours':
            if (a.status != 'en_cours') return false;
          case 'validated':
            if (a.status != 'validee') return false;
          case 'critical':
            if (!a.isCritical) return false;
          case 'qualite':
            if (a.type != 'qualite') return false;
          case 'maintenance':
            if (a.type != 'maintenance') return false;
          case 'defaut_produit':
            if (a.type != 'defaut_produit') return false;
          case 'manque_ressource':
            if (a.type != 'manque_ressource') return false;
        }
      }
      return true;
    }).toList();
  }

  int get _activeAdvancedFilterCount =>
      [_factory, _conveyeur, _poste, _type, _status, _critical, _timeRange]
          .where((v) => v != 'all')
          .length;

  void _openFilterSheet() {
    showDialog<_HistoryFilters>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: _HistoryFilterSheet(
          current: _HistoryFilters(
            factory: _factory,
            conveyeur: _conveyeur,
            poste: _poste,
            type: _type,
            status: _status,
            critical: _critical,
            timeRange: _timeRange,
          ),
          factories: _factoryOptions(),
          rawFactories: widget.factories,
          allAlerts: widget.allAlerts,
        ),
      ),
    ).then((result) {
      if (result != null && mounted) {
        setState(() {
          _factory = result.factory;
          _conveyeur = result.conveyeur;
          _poste = result.poste;
          _type = result.type;
          _status = result.status;
          _critical = result.critical;
          _timeRange = result.timeRange;
          _pageIndex = 0;
        });
      }
    });
  }

  String _chipLabel(BuildContext ctx, String key) {
    switch (key) {
      case 'pending':
        return 'PENDING';
      case 'en_cours':
        return 'CLAIMED';
      case 'validated':
        return 'FIXED';
      case 'critical':
        return 'CRITICAL';
      case 'total':
        return 'TOTAL';
      default:
        return adminTypeLabel(ctx, key).toUpperCase();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final filtered = _filteredAlerts;
    final pageCount =
        filtered.isEmpty ? 1 : ((filtered.length + _pageSize - 1) ~/ _pageSize);
    final clampedPage = _pageIndex.clamp(0, pageCount - 1);
    final start = clampedPage * _pageSize;
    final end = math.min(start + _pageSize, filtered.length);
    final pageItems = filtered.sublist(start, end);
    final advCount = _activeAdvancedFilterCount;

    return Container(
      decoration: BoxDecoration(
        color: theme.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.border),
        boxShadow: [
          BoxShadow(
            color: theme.navy.withValues(alpha: context.isDark ? 0.12 : 0.05),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 8),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [theme.navy, theme.blue]),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.history_rounded,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Alert History',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: theme.text,
                        ),
                      ),
                      Text(
                        '${filtered.length} alert${filtered.length == 1 ? '' : 's'} · ${widget.scope}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.muted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                // Filter button with active count badge
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _openFilterSheet,
                      icon: const Icon(Icons.tune_rounded, size: 14),
                      label: const Text(
                        'Filters',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: advCount > 0 ? theme.navy : theme.navy,
                        side: BorderSide(
                          color: advCount > 0 ? theme.navy : theme.border,
                          width: advCount > 0 ? 1.5 : 1.0,
                        ),
                        backgroundColor: theme.scaffold,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(9),
                        ),
                      ),
                    ),
                    if (advCount > 0)
                      Positioned(
                        top: -4,
                        right: -4,
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: theme.navy,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '$advCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 8),
                // Quick filter chip from stat card click
                if (widget.quickFilter != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: theme.purple.withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(
                        color: theme.purple.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.filter_alt_rounded,
                          size: 11,
                          color: theme.purple,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _chipLabel(context, widget.quickFilter!),
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: theme.purple,
                          ),
                        ),
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: widget.onClearQuickFilter,
                          child: Icon(
                            Icons.close,
                            size: 12,
                            color: theme.purple,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          Divider(color: theme.border, height: 1),
          // Scrollable list
          Expanded(
            child: pageItems.isEmpty
                ? const _EmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                    itemCount: pageItems.length,
                    itemBuilder: (_, i) =>
                        _AlertHistoryRow(alert: pageItems[i]),
                  ),
          ),
          Divider(color: theme.border, height: 1),
          // Pagination controls
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Row(
              children: [
                Text(
                  'Show',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: theme.scaffold,
                    border: Border.all(color: theme.border),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: _pageSize,
                      isDense: true,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.text,
                        fontWeight: FontWeight.w700,
                      ),
                      dropdownColor: theme.card,
                      items: _pageSizeOptions
                          .map(
                            (s) => DropdownMenuItem(
                              value: s,
                              child: Text(
                                '$s',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.text,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) {
                          setState(() {
                            _pageSize = v;
                            _pageIndex = 0;
                          });
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  'per page',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: clampedPage > 0
                      ? () => setState(() => _pageIndex = clampedPage - 1)
                      : null,
                  icon: const Icon(Icons.chevron_left_rounded),
                  iconSize: 20,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 30,
                    minHeight: 30,
                  ),
                  color: theme.navy,
                  disabledColor: theme.muted.withValues(alpha: 0.4),
                  tooltip: 'Previous page',
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: theme.navy.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    '${clampedPage + 1} / $pageCount',
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.navy,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: clampedPage < pageCount - 1
                      ? () => setState(() => _pageIndex = clampedPage + 1)
                      : null,
                  icon: const Icon(Icons.chevron_right_rounded),
                  iconSize: 20,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 30,
                    minHeight: 30,
                  ),
                  color: theme.navy,
                  disabledColor: theme.muted.withValues(alpha: 0.4),
                  tooltip: 'Next page',
                ),
              ],
            ),
          ),
          Divider(color: theme.border, height: 1),
          // Export footer — opens the professional Export Report dialog.
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: _ExportReportButton(
              onTap: () => _openExportReportDialog(filtered),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openExportReportDialog(List<AlertModel> visibleAlerts) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: _ExportReportDialog(
          baseAlerts: widget.allAlerts,
          factories: widget.factories,
          scopeLabel: widget.scope,
          initialFactory: _factory,
          initialConveyeur: _conveyeur,
          initialPoste: _poste,
          initialType: _type,
          initialCritical: _critical,
          initialStatus: _status,
          initialTimeRange: _timeRange,
          labelType: (t) => adminTypeLabel(context, t),
          onExport: (alertsToExport, reportName) async {
            await widget.onExportPdf(alertsToExport, reportName);
          },
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// EMPTY STATE
// ═══════════════════════════════════════════════════════════════════════════

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 16),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: theme.green.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              Icons.check_circle_outline,
              size: 30,
              color: theme.green,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'All clear',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: theme.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'No alerts match your filters.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: theme.muted),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// FILTER SHEET — full filter panel surfaced from the icon button.
// ═══════════════════════════════════════════════════════════════════════════

class _FilterSheet extends StatelessWidget {
  final List<String> usines, convoyeurs, postes;
  final String selectedUsine,
      filterConvoyeur,
      filterPoste,
      filterType,
      filterStatus,
      timeRange;
  final void Function(String) onUsine,
      onConvoyeur,
      onPoste,
      onType,
      onStatus,
      onTime;
  final VoidCallback onReset;

  const _FilterSheet({
    required this.usines,
    required this.convoyeurs,
    required this.postes,
    required this.selectedUsine,
    required this.filterConvoyeur,
    required this.filterPoste,
    required this.filterType,
    required this.filterStatus,
    required this.timeRange,
    required this.onUsine,
    required this.onConvoyeur,
    required this.onPoste,
    required this.onType,
    required this.onStatus,
    required this.onTime,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return SafeArea(
      child: LayoutBuilder(
        builder: (ctx, c) {
          final maxHeight = c.maxHeight > 0 ? c.maxHeight * 0.86 : 720.0;
          return ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 820, maxHeight: maxHeight),
            child: Container(
              decoration: BoxDecoration(
                color: theme.card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: theme.border),
              ),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: theme.border,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: theme.navy.withValues(alpha: 0.13),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.tune_rounded,
                          size: 18,
                          color: theme.navy,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Filter alerts',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: theme.text,
                              ),
                            ),
                            Text(
                              'Refine the history list — every selection scopes the dashboard',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: theme.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          onReset();
                          Navigator.of(ctx).pop();
                        },
                        icon: const Icon(Icons.refresh_rounded, size: 14),
                        label: const Text(
                          'Reset',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        style: TextButton.styleFrom(foregroundColor: theme.red),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _FilterDropdown(
                    label: 'Plant',
                    value: selectedUsine,
                    items: usines
                        .map(
                          (v) => DropdownMenuItem(
                            value: v,
                            child: Text(
                              v == 'all' ? 'All Plants' : v,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: onUsine,
                  ),
                  const SizedBox(height: 10),
                  _FilterDropdown(
                    label: 'Conveyor',
                    value: filterConvoyeur,
                    items: convoyeurs
                        .map(
                          (v) => DropdownMenuItem(
                            value: v,
                            child: Text(
                              v == 'all' ? 'All Conveyors' : 'Conv. $v',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: onConvoyeur,
                  ),
                  const SizedBox(height: 10),
                  _FilterDropdown(
                    label: 'Post',
                    value: filterPoste,
                    items: postes
                        .map(
                          (v) => DropdownMenuItem(
                            value: v,
                            child: Text(
                              v == 'all' ? 'All Posts' : 'Post $v',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: onPoste,
                  ),
                  const SizedBox(height: 10),
                  _FilterDropdown(
                    label: 'Alert Type',
                    value: filterType,
                    items: [
                      const DropdownMenuItem(
                        value: 'all',
                        child: Text(
                          'All Types',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                      ...[
                        'qualite',
                        'maintenance',
                        'defaut_produit',
                        'manque_ressource',
                      ].map(
                        (t) => DropdownMenuItem(
                          value: t,
                          child: Text(
                            adminTypeLabel(context, t),
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ),
                    ],
                    onChanged: onType,
                  ),
                  const SizedBox(height: 10),
                  _FilterDropdown(
                    label: 'Status',
                    value: filterStatus,
                    items: const [
                      DropdownMenuItem(
                        value: 'all',
                        child: Text(
                          'All Statuses',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'disponible',
                        child: Text('Pending', style: TextStyle(fontSize: 13)),
                      ),
                      DropdownMenuItem(
                        value: 'en_cours',
                        child: Text('Claimed', style: TextStyle(fontSize: 13)),
                      ),
                      DropdownMenuItem(
                        value: 'validee',
                        child: Text('Fixed', style: TextStyle(fontSize: 13)),
                      ),
                    ],
                    onChanged: onStatus,
                  ),
                  const SizedBox(height: 10),
                  _FilterDropdown(
                    label: 'Time Range',
                    value: timeRange,
                    items: const [
                      DropdownMenuItem(
                        value: 'all',
                        child: Text('All Time', style: TextStyle(fontSize: 13)),
                      ),
                      DropdownMenuItem(
                        value: 'today',
                        child: Text('Today', style: TextStyle(fontSize: 13)),
                      ),
                      DropdownMenuItem(
                        value: 'week',
                        child: Text(
                          'Last 7 Days',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'month',
                        child: Text(
                          'This Month',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'year',
                        child: Text(
                          'This Year',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'custom',
                        child: Text('Custom', style: TextStyle(fontSize: 13)),
                      ),
                    ],
                    onChanged: onTime,
                  ),
                  const SizedBox(height: 18),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.of(ctx).pop(),
                    icon: const Icon(Icons.check_rounded, size: 16),
                    label: const Text(
                      'Apply',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.navy,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FilterDropdown extends StatelessWidget {
  final String label, value;
  final List<DropdownMenuItem<String>> items;
  final void Function(String) onChanged;
  const _FilterDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: theme.muted,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 5),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: theme.scaffold,
            border: Border.all(color: theme.border),
            borderRadius: BorderRadius.circular(10),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: items.any((i) => i.value == value) ? value : 'all',
              isExpanded: true,
              style: TextStyle(fontSize: 13, color: theme.text),
              dropdownColor: theme.card,
              items: items,
              onChanged: (v) => onChanged(v!),
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ALERT HISTORY ROW
// ═══════════════════════════════════════════════════════════════════════════

class _AlertHistoryRow extends StatelessWidget {
  final AlertModel alert;
  const _AlertHistoryRow({required this.alert});

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final sc = switch (alert.status) {
      'validee' => theme.green,
      'en_cours' => theme.blue,
      _ => theme.orange,
    };
    final sl = switch (alert.status) {
      'validee' => 'Fixed',
      'en_cours' => 'Claimed',
      _ => 'Pending',
    };
    final desc = alert.description.trim().isEmpty
        ? '(no description)'
        : alert.description;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      decoration: BoxDecoration(
        color: theme.scaffold,
        border: Border.all(color: theme.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 4,
                height: 36,
                margin: const EdgeInsets.only(top: 2),
                decoration: BoxDecoration(
                  color: adminTypeColor(context, alert.type),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: adminTypeColor(
                              context,
                              alert.type,
                            ).withValues(alpha: 0.13),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            adminTypeLabel(context, alert.type),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: adminTypeColor(context, alert.type),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (alert.isCritical)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: theme.red.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              'CRITICAL',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                color: theme.red,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: sc.withValues(alpha: 0.13),
                            border: Border.all(
                              color: sc.withValues(alpha: 0.4),
                            ),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            sl,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: sc,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Full description, no ellipsis — wraps so PM can read all of it.
                    Text(
                      desc,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: theme.text,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${alert.usine}  ·  Line ${alert.convoyeur}  ·  Post ${alert.poste}  ·  ${_fmtTs(alert.timestamp)}',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 10,
                        color: theme.muted,
                      ),
                    ),
                    if (alert.superviseurName != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Row(
                          children: [
                            Icon(
                              Icons.person_outline,
                              size: 11,
                              color: theme.blue,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                'Assigned: ${alert.superviseurName}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: theme.blue,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (alert.criticalNote != null &&
                        alert.criticalNote!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          'Critical note: ${alert.criticalNote}',
                          style: TextStyle(fontSize: 11, color: theme.red),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// EXPORT REPORT BUTTON — opens the professional Export Report dialog.
// ═══════════════════════════════════════════════════════════════════════════

class _ExportReportButton extends StatefulWidget {
  final VoidCallback onTap;
  const _ExportReportButton({required this.onTap});

  @override
  State<_ExportReportButton> createState() => _ExportReportButtonState();
}

class _ExportReportButtonState extends State<_ExportReportButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final isDark = context.isDark;
    final accent = theme.navy;
    final hoverBg = accent.withValues(alpha: isDark ? 0.18 : 0.08);
    final hoverBorder = accent.withValues(alpha: 0.55);
    final baseBg = isDark ? const Color(0xFF1E1E2E) : Colors.white;
    final baseBorder = isDark
        ? const Color(0xFF3A3A5C)
        : const Color(0xFFDDE1EC);

    return SizedBox(
      width: double.infinity,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            gradient: _hover
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      accent.withValues(alpha: isDark ? 0.22 : 0.10),
                      accent.withValues(alpha: isDark ? 0.12 : 0.04),
                    ],
                  )
                : null,
            color: _hover ? null : baseBg,
            border: Border.all(color: _hover ? hoverBorder : baseBorder),
            borderRadius: BorderRadius.circular(10),
            boxShadow: _hover
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.22),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(10),
              splashColor: accent.withValues(alpha: 0.10),
              highlightColor: accent.withValues(alpha: 0.05),
              hoverColor: hoverBg,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Icon(
                        Icons.picture_as_pdf_rounded,
                        size: 14,
                        color: accent,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Export Report',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: accent,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.tune_rounded,
                      size: 13,
                      color: accent.withValues(alpha: 0.75),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// EXPORT REPORT DIALOG — corporate-grade PDF report builder.
// Lets the user set the report name, date range (preset or custom),
// alert types, criticality, and status. The dialog returns the filtered
// alert list and the final report name to the caller.
// ═══════════════════════════════════════════════════════════════════════════

class _ExportReportDialog extends StatefulWidget {
  final List<AlertModel> baseAlerts;
  final List<Factory> factories;
  final String scopeLabel;
  final String initialFactory;
  final String initialConveyeur;
  final String initialPoste;
  final String initialType;
  final String initialCritical;
  final String initialStatus;
  final String initialTimeRange;
  final String Function(String type) labelType;
  final Future<void> Function(List<AlertModel> alerts, String reportName)
      onExport;

  const _ExportReportDialog({
    required this.baseAlerts,
    required this.factories,
    required this.scopeLabel,
    required this.initialFactory,
    required this.initialConveyeur,
    required this.initialPoste,
    required this.initialType,
    required this.initialCritical,
    required this.initialStatus,
    required this.initialTimeRange,
    required this.labelType,
    required this.onExport,
  });

  @override
  State<_ExportReportDialog> createState() => _ExportReportDialogState();
}

class _ExportReportDialogState extends State<_ExportReportDialog> {
  static const _allTypes = <String>{
    'qualite',
    'maintenance',
    'defaut_produit',
    'manque_ressource',
  };

  late final TextEditingController _nameController;
  bool _nameTouched = false;

  late String _factory;
  late String _conveyeur;
  late String _poste;
  late Set<String> _selectedTypes;
  late String _critical;
  late String _status;
  late String _datePreset;
  DateTime? _customFrom;
  DateTime? _customTo;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _factory = widget.initialFactory;
    _conveyeur = widget.initialConveyeur;
    _poste = widget.initialPoste;
    _selectedTypes = widget.initialType == 'all'
        ? Set<String>.from(_allTypes)
        : {widget.initialType};
    _critical = widget.initialCritical;
    _status = widget.initialStatus;
    _datePreset = widget.initialTimeRange == 'all'
        ? 'all'
        : widget.initialTimeRange;
    _nameController = TextEditingController(text: _autoName());
    _nameController.addListener(() {
      if (!_nameTouched && _nameController.text != _autoName()) {
        _nameTouched = true;
      }
    });
  }

  List<String> _factoryOptions() {
    final names = <String>{};
    for (final f in widget.factories) {
      if (f.name.isNotEmpty) names.add(f.name);
    }
    for (final a in widget.baseAlerts) {
      if (a.usine.isNotEmpty && a.usine != 'all') names.add(a.usine);
    }
    return ['all', ...names.toList()..sort()];
  }

  List<String> _conveyeurOptions() {
    if (_factory == 'all') {
      final vals = <String>{};
      for (final a in widget.baseAlerts) {
        final cv = a.convoyeur.toString();
        if (cv.isNotEmpty && cv != '0') vals.add(cv);
      }
      final list = vals.toList()
        ..sort((a, b) =>
            (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));
      return ['all', ...list];
    }
    Factory? fac;
    for (final f in widget.factories) {
      if (f.name == _factory) {
        fac = f;
        break;
      }
    }
    if (fac == null) {
      final vals = <String>{};
      for (final a in widget.baseAlerts) {
        if (a.usine == _factory) {
          final cv = a.convoyeur.toString();
          if (cv.isNotEmpty && cv != '0') vals.add(cv);
        }
      }
      final list = vals.toList()
        ..sort((a, b) =>
            (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));
      return ['all', ...list];
    }
    final list = fac.conveyors.values.map((c) => c.number.toString()).toList()
      ..sort((a, b) =>
          (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));
    return ['all', ...list];
  }

  List<String> _posteOptions() {
    if (_conveyeur == 'all') return const ['all'];
    if (_factory != 'all') {
      Factory? fac;
      for (final f in widget.factories) {
        if (f.name == _factory) {
          fac = f;
          break;
        }
      }
      if (fac != null) {
        Conveyor? conv;
        for (final c in fac.conveyors.values) {
          if (c.number.toString() == _conveyeur) {
            conv = c;
            break;
          }
        }
        if (conv != null) {
          final stations = conv.stations.values
              .map((s) => s.id.replaceAll('station_', ''))
              .toList()
            ..sort((a, b) =>
                (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));
          return ['all', ...stations];
        }
      }
    }
    final vals = <String>{};
    for (final a in widget.baseAlerts) {
      if (a.convoyeur.toString() == _conveyeur) {
        if (_factory != 'all' && a.usine != _factory) continue;
        final p = a.poste.toString();
        if (p.isNotEmpty && p != '0') vals.add(p);
      }
    }
    final list = vals.toList()
      ..sort(
          (a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));
    return ['all', ...list];
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _datePresetLabel() {
    switch (_datePreset) {
      case 'today':
        return 'Today';
      case 'week':
        return 'Last 7 Days';
      case 'month':
        return 'This Month';
      case 'year':
        return 'This Year';
      case 'custom':
        if (_customFrom != null && _customTo != null) {
          return '${_isoDate(_customFrom!)} - ${_isoDate(_customTo!)}';
        }
        return 'Custom Range';
      default:
        return 'All Time';
    }
  }

  String _criticalSuffix() {
    switch (_critical) {
      case 'critical':
        return ' - Critical Only';
      case 'normal':
        return ' - Normal Only';
      default:
        return '';
    }
  }

  String _autoName() {
    final today = _isoDate(DateTime.now());
    final scope = _factory != 'all'
        ? _factory
        : (widget.scopeLabel.isEmpty ? 'All Plants' : widget.scopeLabel);
    final locationSuffix = StringBuffer();
    if (_conveyeur != 'all') {
      locationSuffix.write(' - Conv. $_conveyeur');
    }
    if (_poste != 'all') {
      locationSuffix.write(' - WS $_poste');
    }
    return 'Smart Industrial Alert - SIA - Operations Report - $scope$locationSuffix - $today${_criticalSuffix()}';
  }

  void _refreshAutoNameIfNeeded() {
    if (!_nameTouched) {
      _nameController.text = _autoName();
      _nameController.selection = TextSelection.fromPosition(
        TextPosition(offset: _nameController.text.length),
      );
    }
  }

  ({DateTime? from, DateTime? to}) _resolvedRange() {
    final now = DateTime.now();
    switch (_datePreset) {
      case 'today':
        final start = DateTime(now.year, now.month, now.day);
        return (from: start, to: now);
      case 'week':
        return (from: now.subtract(const Duration(days: 7)), to: now);
      case 'month':
        return (from: DateTime(now.year, now.month, 1), to: now);
      case 'year':
        return (from: DateTime(now.year, 1, 1), to: now);
      case 'custom':
        if (_customFrom == null || _customTo == null) {
          return (from: null, to: null);
        }
        final start = DateTime(
          _customFrom!.year,
          _customFrom!.month,
          _customFrom!.day,
        );
        final end = DateTime(
          _customTo!.year,
          _customTo!.month,
          _customTo!.day,
          23,
          59,
          59,
        );
        return (from: start, to: end);
      default:
        return (from: null, to: null);
    }
  }

  List<AlertModel> _resolvedAlerts() {
    final range = _resolvedRange();
    return widget.baseAlerts.where((a) {
      if (_factory != 'all' && a.usine != _factory) return false;
      if (_conveyeur != 'all' && a.convoyeur.toString() != _conveyeur) {
        return false;
      }
      if (_poste != 'all' && a.poste.toString() != _poste) return false;
      if (!_selectedTypes.contains(a.type)) return false;
      if (_critical == 'critical' && !a.isCritical) return false;
      if (_critical == 'normal' && a.isCritical) return false;
      if (_status != 'all' && a.status != _status) return false;
      if (range.from != null && a.timestamp.isBefore(range.from!)) {
        return false;
      }
      if (range.to != null && a.timestamp.isAfter(range.to!)) {
        return false;
      }
      return true;
    }).toList();
  }

  Future<void> _pickDate(bool isFrom) async {
    final theme = context.appTheme;
    final now = DateTime.now();
    final initial = isFrom
        ? (_customFrom ?? now.subtract(const Duration(days: 7)))
        : (_customTo ?? now);
    final firstDate = DateTime(now.year - 5);
    final lastDate = DateTime(now.year + 1, 12, 31);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDate,
      lastDate: lastDate,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(ctx).colorScheme.copyWith(
                primary: theme.navy,
                onPrimary: Colors.white,
              ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        if (isFrom) {
          _customFrom = picked;
          if (_customTo != null && _customTo!.isBefore(picked)) {
            _customTo = picked;
          }
        } else {
          _customTo = picked;
          if (_customFrom != null && _customFrom!.isAfter(picked)) {
            _customFrom = picked;
          }
        }
        _refreshAutoNameIfNeeded();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final filtered = _resolvedAlerts();

    return SafeArea(
      child: LayoutBuilder(
        builder: (ctx, c) {
          final maxHeight = c.maxHeight > 0 ? c.maxHeight * 0.92 : 760.0;
          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 680, maxHeight: maxHeight),
              child: Container(
                decoration: BoxDecoration(
                  color: theme.card,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: theme.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 32,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildHeader(theme),
                    Flexible(
                      child: SingleChildScrollView(
                        padding:
                            const EdgeInsets.fromLTRB(22, 18, 22, 18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildReportNameField(theme),
                            const SizedBox(height: 18),
                            _buildLocationSection(theme),
                            const SizedBox(height: 18),
                            _buildDateRangeSection(theme),
                            const SizedBox(height: 18),
                            _buildAlertTypeSection(theme),
                            const SizedBox(height: 18),
                            _buildSegmentSection(
                              theme: theme,
                              label: 'Criticality',
                              icon: Icons.priority_high_rounded,
                              value: _critical,
                              options: const [
                                ('all', 'All'),
                                ('critical', 'Critical Only'),
                                ('normal', 'Normal Only'),
                              ],
                              onChanged: (v) => setState(() {
                                _critical = v;
                                _refreshAutoNameIfNeeded();
                              }),
                            ),
                            const SizedBox(height: 18),
                            _buildSegmentSection(
                              theme: theme,
                              label: 'Status',
                              icon: Icons.flag_rounded,
                              value: _status,
                              options: const [
                                ('all', 'All'),
                                ('disponible', 'Pending'),
                                ('en_cours', 'Claimed'),
                                ('validee', 'Resolved'),
                              ],
                              onChanged: (v) =>
                                  setState(() => _status = v),
                            ),
                          ],
                        ),
                      ),
                    ),
                    _buildFooter(theme, filtered),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(AppTheme theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 20, 16, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.navy,
            theme.navy.withValues(alpha: 0.78),
          ],
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
            ),
            child: const Icon(
              Icons.picture_as_pdf_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Export Report',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Generate a professional PDF tailored to your filters',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _exporting ? null : () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
            color: Colors.white,
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }

  Widget _buildReportNameField(AppTheme theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(theme, 'Report Name', Icons.edit_note_rounded),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: theme.scaffold,
            border: Border.all(color: theme.border),
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _nameController,
                  maxLines: 2,
                  minLines: 1,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: theme.text,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                    hintText: 'Report name',
                  ),
                ),
              ),
              if (_nameTouched)
                IconButton(
                  tooltip: 'Reset to auto-generated name',
                  onPressed: () {
                    setState(() {
                      _nameTouched = false;
                      _nameController.text = _autoName();
                    });
                  },
                  icon: Icon(
                    Icons.refresh_rounded,
                    size: 18,
                    color: theme.muted,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _nameTouched
              ? 'Custom report name'
              : 'Auto-generated from current filters',
          style: TextStyle(
            fontSize: 11,
            color: theme.muted,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildLocationSection(AppTheme theme) {
    final factoryOpts = _factoryOptions();
    final safeFactory =
        factoryOpts.contains(_factory) ? _factory : 'all';
    final conveyeurOpts = _conveyeurOptions();
    final safeConveyeur =
        conveyeurOpts.contains(_conveyeur) ? _conveyeur : 'all';
    final posteOpts = _posteOptions();
    final safePoste = posteOpts.contains(_poste) ? _poste : 'all';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(theme, 'Location Scope', Icons.factory_rounded),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (ctx, c) {
            final narrow = c.maxWidth < 520;
            final factoryField = _locationDropdown(
              theme: theme,
              icon: Icons.business_rounded,
              label: 'Plant',
              value: safeFactory,
              items: factoryOpts.map((v) {
                return DropdownMenuItem<String>(
                  value: v,
                  child: Text(
                    v == 'all' ? 'All Plants' : v,
                    style: TextStyle(fontSize: 13, color: theme.text),
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              onChanged: (v) => setState(() {
                _factory = v;
                _conveyeur = 'all';
                _poste = 'all';
                _refreshAutoNameIfNeeded();
              }),
            );
            final conveyorField = _locationDropdown(
              theme: theme,
              icon: Icons.linear_scale_rounded,
              label: 'Conveyor',
              value: safeConveyeur,
              enabled: conveyeurOpts.length > 1,
              items: conveyeurOpts.map((v) {
                return DropdownMenuItem<String>(
                  value: v,
                  child: Text(
                    v == 'all' ? 'All Conveyors' : 'Conv. $v',
                    style: TextStyle(fontSize: 13, color: theme.text),
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              onChanged: (v) => setState(() {
                _conveyeur = v;
                _poste = 'all';
                _refreshAutoNameIfNeeded();
              }),
            );
            final stationField = _locationDropdown(
              theme: theme,
              icon: Icons.location_on_rounded,
              label: 'Workstation',
              value: safePoste,
              enabled: posteOpts.length > 1,
              items: posteOpts.map((v) {
                return DropdownMenuItem<String>(
                  value: v,
                  child: Text(
                    v == 'all' ? 'All Workstations' : 'WS $v',
                    style: TextStyle(fontSize: 13, color: theme.text),
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              onChanged: (v) => setState(() {
                _poste = v;
                _refreshAutoNameIfNeeded();
              }),
            );

            if (narrow) {
              return Column(
                children: [
                  factoryField,
                  const SizedBox(height: 10),
                  conveyorField,
                  const SizedBox(height: 10),
                  stationField,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: factoryField),
                const SizedBox(width: 10),
                Expanded(child: conveyorField),
                const SizedBox(width: 10),
                Expanded(child: stationField),
              ],
            );
          },
        ),
        if (_factory != 'all' || _conveyeur != 'all' || _poste != 'all') ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() {
                _factory = 'all';
                _conveyeur = 'all';
                _poste = 'all';
                _refreshAutoNameIfNeeded();
              }),
              icon: const Icon(Icons.clear_rounded, size: 14),
              label: const Text(
                'Clear location filters',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
              ),
              style: TextButton.styleFrom(
                foregroundColor: theme.red,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _locationDropdown({
    required AppTheme theme,
    required IconData icon,
    required String label,
    required String value,
    required List<DropdownMenuItem<String>> items,
    required void Function(String) onChanged,
    bool enabled = true,
  }) {
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: theme.muted),
              const SizedBox(width: 5),
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontSize: 9.5,
                  color: theme.muted,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: theme.scaffold,
              border: Border.all(color: theme.border),
              borderRadius: BorderRadius.circular(10),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: value,
                isExpanded: true,
                style: TextStyle(fontSize: 13, color: theme.text),
                dropdownColor: theme.card,
                items: items,
                onChanged: enabled
                    ? (v) {
                        if (v != null) onChanged(v);
                      }
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateRangeSection(AppTheme theme) {
    const presets = <(String, String)>[
      ('all', 'All Time'),
      ('today', 'Today'),
      ('week', 'Last 7 Days'),
      ('month', 'This Month'),
      ('year', 'This Year'),
      ('custom', 'Custom'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(theme, 'Date Range', Icons.event_rounded),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: presets.map((p) {
            final selected = _datePreset == p.$1;
            return ChoiceChip(
              label: Text(
                p.$2,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : theme.text,
                ),
              ),
              selected: selected,
              selectedColor: theme.navy,
              backgroundColor: theme.scaffold,
              side: BorderSide(
                color: selected ? theme.navy : theme.border,
              ),
              onSelected: (_) => setState(() {
                _datePreset = p.$1;
                _refreshAutoNameIfNeeded();
              }),
            );
          }).toList(),
        ),
        if (_datePreset == 'custom') ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _datePickerField(
                  theme: theme,
                  label: 'From',
                  value: _customFrom,
                  onTap: () => _pickDate(true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _datePickerField(
                  theme: theme,
                  label: 'To',
                  value: _customTo,
                  onTap: () => _pickDate(false),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _datePickerField({
    required AppTheme theme,
    required String label,
    required DateTime? value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: theme.scaffold,
          border: Border.all(color: theme.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_rounded, size: 14, color: theme.muted),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label.toUpperCase(),
                    style: TextStyle(
                      fontSize: 9.5,
                      color: theme.muted,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value == null ? 'Select date' : _isoDate(value),
                    style: TextStyle(
                      fontSize: 13,
                      color: value == null ? theme.muted : theme.text,
                      fontWeight: FontWeight.w700,
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

  Widget _buildAlertTypeSection(AppTheme theme) {
    final allSelected = _selectedTypes.length == _allTypes.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _sectionLabel(theme, 'Alert Types', Icons.category_rounded),
            const Spacer(),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  if (allSelected) {
                    _selectedTypes = {};
                  } else {
                    _selectedTypes = Set<String>.from(_allTypes);
                  }
                });
              },
              icon: Icon(
                allSelected
                    ? Icons.indeterminate_check_box_outlined
                    : Icons.select_all_rounded,
                size: 14,
              ),
              label: Text(
                allSelected ? 'Clear all' : 'Select all',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: TextButton.styleFrom(
                foregroundColor: theme.navy,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _allTypes.map((t) {
            final selected = _selectedTypes.contains(t);
            final color = adminTypeColor(context, t);
            return FilterChip(
              label: Text(
                widget.labelType(t),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected ? color : theme.text,
                ),
              ),
              selected: selected,
              selectedColor: color.withValues(alpha: 0.15),
              checkmarkColor: color,
              backgroundColor: theme.scaffold,
              side: BorderSide(
                color: selected ? color : theme.border,
                width: selected ? 1.4 : 1,
              ),
              onSelected: (v) {
                setState(() {
                  if (v) {
                    _selectedTypes.add(t);
                  } else {
                    _selectedTypes.remove(t);
                  }
                });
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildSegmentSection({
    required AppTheme theme,
    required String label,
    required IconData icon,
    required String value,
    required List<(String, String)> options,
    required void Function(String) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(theme, label, icon),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((opt) {
            final selected = value == opt.$1;
            return ChoiceChip(
              label: Text(
                opt.$2,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : theme.text,
                ),
              ),
              selected: selected,
              selectedColor: theme.navy,
              backgroundColor: theme.scaffold,
              side: BorderSide(
                color: selected ? theme.navy : theme.border,
              ),
              onSelected: (_) => onChanged(opt.$1),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _sectionLabel(AppTheme theme, String text, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: theme.navy.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(icon, size: 13, color: theme.navy),
        ),
        const SizedBox(width: 8),
        Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            color: theme.text,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
          ),
        ),
      ],
    );
  }

  Widget _buildFooter(AppTheme theme, List<AlertModel> filtered) {
    final canExport = filtered.isNotEmpty &&
        _selectedTypes.isNotEmpty &&
        !_exporting &&
        (_datePreset != 'custom' ||
            (_customFrom != null && _customTo != null));

    return Container(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 16),
      decoration: BoxDecoration(
        color: theme.scaffold,
        border: Border(top: BorderSide(color: theme.border)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: filtered.isEmpty
                  ? theme.red.withValues(alpha: 0.10)
                  : theme.green.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: filtered.isEmpty
                    ? theme.red.withValues(alpha: 0.4)
                    : theme.green.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  filtered.isEmpty
                      ? Icons.warning_amber_rounded
                      : Icons.fact_check_rounded,
                  size: 14,
                  color: filtered.isEmpty ? theme.red : theme.green,
                ),
                const SizedBox(width: 6),
                Text(
                  filtered.isEmpty
                      ? 'No alerts match'
                      : '${filtered.length} ${filtered.length == 1 ? "alert" : "alerts"} included',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: filtered.isEmpty ? theme.red : theme.green,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _datePresetLabel(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: theme.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed:
                _exporting ? null : () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              foregroundColor: theme.muted,
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
            child: const Text(
              'Cancel',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: canExport ? _handleExport : null,
            icon: _exporting
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.download_rounded, size: 16),
            label: Text(
              _exporting ? 'Generating...' : 'Generate PDF',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.navy,
              foregroundColor: Colors.white,
              disabledBackgroundColor: theme.muted.withValues(alpha: 0.35),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleExport() async {
    final filtered = _resolvedAlerts();
    if (filtered.isEmpty) return;
    final name = _nameController.text.trim().isEmpty
        ? _autoName()
        : _nameController.text.trim();
    setState(() => _exporting = true);
    try {
      await widget.onExport(filtered, name);
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
        Navigator.of(context).pop();
      }
    }
  }
}
