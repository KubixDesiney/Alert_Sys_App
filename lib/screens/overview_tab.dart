import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:csv/csv.dart';
import 'package:excel/excel.dart' as excel;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:universal_html/html.dart' as html;

import '../../models/alert_model.dart';
import '../../models/hierarchy_model.dart';
import '../../services/predictive_intel_service.dart';
import '../../services/predictive_models.dart';
import '../../services/service_locator.dart';
import '../../theme.dart';
import '../../widgets/overview/ai_morning_briefing_hero.dart';
import '../../widgets/overview/overview_critical_alerts_card.dart';
import '../../widgets/overview/overview_insights_strip.dart';
import '../../widgets/overview/overview_predictive_failure_card.dart';
import '../../widgets/overview/overview_predictive_heatmap.dart';
import '../../widgets/overview/overview_stat_card.dart';
import 'admin/admin_dashboard_shared.dart';

String _fmtTs(DateTime d) => formatAdminTimestamp(d);

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
        color: theme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.border),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: context.isDark ? 0.10 : 0.06),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: LayoutBuilder(builder: (ctx, c) {
        final narrow = c.maxWidth < 520;
        final gauge = SizedBox(
          width: narrow ? 160 : 190,
          height: narrow ? 100 : 118,
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
                          fontSize: narrow ? 30 : 36,
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
            children: [
              gauge,
              const SizedBox(height: 14),
              stats,
            ],
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
      }),
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
    final stroke = 14.0;
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
// Premium presentation layer over the existing alert/filter/export logic.
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

  MorningBriefing? _briefing;
  PredictiveModel? _predictions;
  StreamSubscription<MorningBriefing?>? _briefSub;
  StreamSubscription<PredictiveModel?>? _predSub;
  bool _briefingWarmed = false;
  bool _predictionsWarmed = false;

  @override
  void initState() {
    super.initState();
    _loadFactories();
    _bindPredictiveStreams();
    _warmPredictiveCaches();
  }

  @override
  void dispose() {
    _briefSub?.cancel();
    _predSub?.cancel();
    super.dispose();
  }

  void _loadFactories() {
    ServiceLocator.instance.hierarchyService.getFactories().listen((factories) {
      if (mounted) setState(() => _factories = factories);
    });
  }

  void _bindPredictiveStreams() {
    _briefSub = PredictiveIntelService.instance.briefingStream().listen((b) {
      if (mounted) setState(() => _briefing = b);
    });
    _predSub = PredictiveIntelService.instance.predictionsStream().listen((p) {
      if (mounted) setState(() => _predictions = p);
    });
  }

  Future<void> _warmPredictiveCaches() async {
    if (!_briefingWarmed) {
      _briefingWarmed = true;
      unawaited(PredictiveIntelService.instance.fetchBriefing());
    }
    if (!_predictionsWarmed) {
      _predictionsWarmed = true;
      unawaited(PredictiveIntelService.instance.fetchPredictions());
    }
  }

  Future<void> _refreshBriefing() async {
    final fresh =
        await PredictiveIntelService.instance.fetchBriefing(force: true);
    if (mounted && fresh != null) setState(() => _briefing = fresh);
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
      .where((a) => a.isCritical && a.status == 'disponible')
      .toList();

  int get _criticalUnclaimedCount => _criticalUnclaimedAlerts.length;

  List<AlertModel> get _displayedAlerts {
    if (_historyFilter == null) return widget.alerts;
    switch (_historyFilter) {
      case 'total':
        return widget.alerts;
      case 'validated':
        return widget.alerts.where((a) => a.status == 'validee').toList();
      case 'en_cours':
        return widget.alerts.where((a) => a.status == 'en_cours').toList();
      case 'pending':
        return widget.alerts.where((a) => a.status == 'disponible').toList();
      case 'qualite':
        return widget.alerts.where((a) => a.type == 'qualite').toList();
      case 'critical':
        return widget.alerts.where((a) => a.isCritical).toList();
      case 'maintenance':
        return widget.alerts.where((a) => a.type == 'maintenance').toList();
      case 'defaut_produit':
        return widget.alerts.where((a) => a.type == 'defaut_produit').toList();
      case 'manque_ressource':
        return widget.alerts
            .where((a) => a.type == 'manque_ressource')
            .toList();
      default:
        return widget.alerts;
    }
  }

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
        }
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
        .where((a) =>
            a.status == 'validee' &&
            a.elapsedTime != null &&
            a.elapsedTime! > 0)
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

  List<InsightItem> _smartInsights() {
    final insights = <InsightItem>[];
    final ts = _typeStats();
    String? biggest;
    var biggestVal = 0;
    ts.forEach((k, v) {
      if (v['total']! > biggestVal) {
        biggestVal = v['total']!;
        biggest = k;
      }
    });
    if (biggest != null && biggestVal > 0) {
      insights.add(InsightItem(
        icon: adminTypeIcon(context, biggest!),
        color: adminTypeColor(context, biggest!),
        text:
            '${adminTypeLabel(context, biggest!)} leads this period — $biggestVal alert${biggestVal > 1 ? 's' : ''}.',
      ));
    }

    if (widget.total > 0) {
      final rate = (widget.solved / widget.total * 100).round();
      if (rate >= 80) {
        insights.add(InsightItem(
          icon: Icons.trending_up_rounded,
          color: AppColors.green,
          text: 'Resolution rate at $rate% — operations running smoothly.',
        ));
      } else if (rate < 50) {
        insights.add(InsightItem(
          icon: Icons.priority_high_rounded,
          color: AppColors.orange,
          text: 'Resolution rate is $rate% — workload may need redistribution.',
        ));
      }
    }

    if (_criticalUnclaimedCount > 0) {
      insights.add(InsightItem(
        icon: Icons.warning_amber_rounded,
        color: AppColors.red,
        text:
            '$_criticalUnclaimedCount critical alert${_criticalUnclaimedCount > 1 ? 's' : ''} awaiting assignment.',
      ));
    }

    final avg = _avgResolutionTime();
    if (avg.inMinutes > 0) {
      insights.add(InsightItem(
        icon: Icons.timer_outlined,
        color: AppColors.blue,
        text: 'Average resolution time: ${_fmtDuration(avg)}.',
      ));
    }

    return insights;
  }

  void _exportFilteredAlerts(List<AlertModel> alertsToExport) async {
    if (alertsToExport.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No alerts to export'),
            backgroundColor: Colors.orange),
      );
      return;
    }
    final csvData = <List<dynamic>>[
      [
        'ID',
        'Type',
        'Usine',
        'Convoyeur',
        'Poste',
        'Adresse',
        'Timestamp',
        'Description',
        'Status',
        'Superviseur',
        'Assistant',
        'Resolution Reason',
        'Elapsed Time (min)',
        'Critical'
      ]
    ];
    for (final alert in alertsToExport) {
      csvData.add([
        alert.id,
        adminTypeLabel(context, alert.type),
        alert.usine,
        alert.convoyeur,
        alert.poste,
        alert.adresse,
        alert.timestamp.toIso8601String(),
        alert.description,
        alert.status,
        alert.superviseurName ?? '',
        alert.assistantName ?? '',
        alert.resolutionReason ?? '',
        alert.elapsedTime ?? '',
        alert.isCritical ? 'Yes' : 'No',
      ]);
    }
    final csv = const ListToCsvConverter().convert(csvData);
    final bytes = utf8.encode(csv);
    if (kIsWeb) {
      final blob = html.Blob([bytes], 'text/csv');
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..setAttribute('download', 'alerts.csv')
        ..click();
      html.Url.revokeObjectUrl(url);
      return;
    }
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/alerts.csv');
    await file.writeAsBytes(bytes);
    await Share.shareXFiles([XFile(file.path)], text: 'Exported alerts CSV');
  }

  void _exportFilteredAlertsExcel(List<AlertModel> alertsToExport) async {
    if (alertsToExport.isEmpty) return;
    final workbook = excel.Excel.createExcel();
    final sheet = workbook['Alerts'];
    sheet.appendRow([
      excel.TextCellValue('ID'),
      excel.TextCellValue('Type'),
      excel.TextCellValue('Usine'),
      excel.TextCellValue('Convoyeur'),
      excel.TextCellValue('Poste'),
      excel.TextCellValue('Adresse'),
      excel.TextCellValue('Timestamp'),
      excel.TextCellValue('Description'),
      excel.TextCellValue('Status'),
      excel.TextCellValue('Superviseur'),
      excel.TextCellValue('Assistant'),
      excel.TextCellValue('Resolution Reason'),
      excel.TextCellValue('Elapsed Time (min)'),
      excel.TextCellValue('Critical'),
    ]);
    for (final alert in alertsToExport) {
      sheet.appendRow([
        excel.TextCellValue(alert.id),
        excel.TextCellValue(adminTypeLabel(context, alert.type)),
        excel.TextCellValue(alert.usine),
        excel.TextCellValue(alert.convoyeur.toString()),
        excel.TextCellValue(alert.poste.toString()),
        excel.TextCellValue(alert.adresse),
        excel.TextCellValue(alert.timestamp.toIso8601String()),
        excel.TextCellValue(alert.description),
        excel.TextCellValue(alert.status),
        excel.TextCellValue(alert.superviseurName ?? ''),
        excel.TextCellValue(alert.assistantName ?? ''),
        excel.TextCellValue(alert.resolutionReason ?? ''),
        excel.TextCellValue((alert.elapsedTime ?? '').toString()),
        excel.TextCellValue(alert.isCritical ? 'Yes' : 'No'),
      ]);
    }
    final bytes = workbook.encode();
    if (bytes == null) return;
    if (kIsWeb) {
      final blob = html.Blob([bytes],
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..setAttribute('download', 'alerts.xlsx')
        ..click();
      html.Url.revokeObjectUrl(url);
      return;
    }
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/alerts.xlsx');
    await file.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles([XFile(file.path)], text: 'Exported alerts Excel');
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final ts = _typeStats();
    final insights = _smartInsights();
    final health = _healthScore();
    final receivedSpark = _last7DaysCounts((a) => a.status == 'disponible');
    final claimedSpark = _last7DaysCounts((a) => a.status == 'en_cours');
    final fixedSpark = _last7DaysCounts((a) => a.status == 'validee');
    final totalSpark = _last7DaysCounts((_) => true);
    final resolutionRate =
        widget.total == 0 ? 0.0 : (widget.solved / widget.total) * 100.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AIMorningBriefingHero(
            briefing: _briefing,
            timeRangeLabel: widget.timeRangeLabel,
            timeRangeSubtitle: widget.timeRangeSubtitle,
            onRefresh: _refreshBriefing,
          ),
          const SizedBox(height: 14),
          _ActiveFilterBanner(
            timeRange: widget.timeRange,
            timeRangeLabel: widget.timeRangeLabel,
            selectedUsine: widget.selectedUsine,
            filterConvoyeur: widget.filterConvoyeur,
            filterPoste: widget.filterPoste,
            filterType: widget.filterType,
            filterStatus: widget.filterStatus,
            onRemoveUsine: () => widget.onUsineChange('all'),
            onReset: widget.onReset,
          ),
          const SizedBox(height: 18),
          _HealthScoreCard(
            value: health,
            resolutionRate: resolutionRate,
            criticalCount: _criticalUnclaimedCount,
            avgResponseLabel: _fmtDuration(_avgResolutionTime()),
            totalAlerts: widget.total,
          ),
          const SizedBox(height: 14),
          LayoutBuilder(builder: (ctx, c) {
            final narrow = c.maxWidth < 720;
            if (narrow) {
              return Column(
                children: [
                  Row(children: [
                    Expanded(child: _statCardReceived(theme, receivedSpark)),
                    const SizedBox(width: 12),
                    Expanded(child: _statCardClaimed(theme, claimedSpark)),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: _statCardFixed(theme, fixedSpark)),
                    const SizedBox(width: 12),
                    Expanded(child: _statCardTotal(theme, totalSpark)),
                  ]),
                ],
              );
            }
            return Row(children: [
              Expanded(child: _statCardReceived(theme, receivedSpark)),
              const SizedBox(width: 12),
              Expanded(child: _statCardClaimed(theme, claimedSpark)),
              const SizedBox(width: 12),
              Expanded(child: _statCardFixed(theme, fixedSpark)),
              const SizedBox(width: 12),
              Expanded(child: _statCardTotal(theme, totalSpark)),
            ]);
          }),
          const SizedBox(height: 18),
          if (insights.isNotEmpty) ...[
            InsightsStrip(insights: insights),
            const SizedBox(height: 18),
          ],
          PredictiveFailureCard(
            model: _predictions,
            describeType: (type) => adminTypeLabel(context, type),
          ),
          const SizedBox(height: 18),
          PredictiveRiskHeatmap(
            stats: ts,
            model: _predictions,
            activeFilter: _historyFilter,
            onTap: _setHistoryFilter,
          ),
          const SizedBox(height: 18),
          if (_criticalUnclaimedCount > 0) ...[
            CriticalAlertsCard(
              alerts: _criticalUnclaimedAlerts,
              onAlertTap: (a) => _setHistoryFilter(a.type),
              describe: _getAlertDisplayDescription,
            ),
            const SizedBox(height: 18),
          ],
          _HistoryHeader(
            count: _displayedAlerts.length,
            onCsv: () => _exportFilteredAlerts(_displayedAlerts),
            onExcel: () => _exportFilteredAlertsExcel(_displayedAlerts),
          ),
          const SizedBox(height: 12),
          _FilterPanel(
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
              setState(() => _historyFilter = null);
            },
          ),
          const SizedBox(height: 14),
          if (_displayedAlerts.isEmpty)
            const _EmptyState()
          else
            ..._displayedAlerts.map((a) => _AlertHistoryRow(alert: a)),
        ],
      ),
    );
  }

  Widget _statCardReceived(AppTheme theme, List<int> spark) => EliteStatCard(
        label: 'Received',
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


// ═══════════════════════════════════════════════════════════════════════════
// CRITICAL ALERT ROW WITH AI ONE-TAP RESOLUTION SUGGESTION
// Lazily fetches the suggestion from the worker, lets PM assign with 1 tap.
// ═══════════════════════════════════════════════════════════════════════════
// HISTORY HEADER + EXPORT
// ═══════════════════════════════════════════════════════════════════════════

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 44),
      alignment: Alignment.center,
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: theme.green.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(16),
            ),
            child:
                Icon(Icons.check_circle_outline, size: 30, color: theme.green),
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
            style: TextStyle(fontSize: 13, color: theme.muted),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// FILTER PANEL
// ═══════════════════════════════════════════════════════════════════════════

class _FilterPanel extends StatelessWidget {
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

  const _FilterPanel({
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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.card,
        border: Border.all(color: theme.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tune_rounded, size: 16, color: theme.navy),
              const SizedBox(width: 8),
              Text(
                'Filters',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: theme.text,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: onReset,
                icon: const Icon(Icons.refresh_rounded, size: 14),
                label: const Text('Reset',
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                style: TextButton.styleFrom(
                  foregroundColor: theme.navy,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(builder: (ctx, c) {
            final twoCol = c.maxWidth < 640;
            final children = [
              _FilterDropdown(
                label: 'Plant',
                value: selectedUsine,
                items: usines
                    .map((v) => DropdownMenuItem(
                          value: v,
                          child: Text(
                            v == 'all' ? 'All Plants' : v,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ))
                    .toList(),
                onChanged: onUsine,
              ),
              _FilterDropdown(
                label: 'Conveyor',
                value: filterConvoyeur,
                items: convoyeurs
                    .map((v) => DropdownMenuItem(
                          value: v,
                          child: Text(
                            v == 'all' ? 'All Conveyors' : 'Conv. $v',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ))
                    .toList(),
                onChanged: onConvoyeur,
              ),
              _FilterDropdown(
                label: 'Post',
                value: filterPoste,
                items: postes
                    .map((v) => DropdownMenuItem(
                          value: v,
                          child: Text(
                            v == 'all' ? 'All Posts' : 'Post $v',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ))
                    .toList(),
                onChanged: onPoste,
              ),
              _FilterDropdown(
                label: 'Alert Type',
                value: filterType,
                items: [
                  const DropdownMenuItem(
                      value: 'all',
                      child: Text('All Types', style: TextStyle(fontSize: 13))),
                  ...[
                    'qualite',
                    'maintenance',
                    'defaut_produit',
                    'manque_ressource'
                  ].map((t) => DropdownMenuItem(
                        value: t,
                        child: Text(adminTypeLabel(context, t),
                            style: const TextStyle(fontSize: 13)),
                      )),
                ],
                onChanged: onType,
              ),
              _FilterDropdown(
                label: 'Status',
                value: filterStatus,
                items: const [
                  DropdownMenuItem(
                      value: 'all',
                      child:
                          Text('All Statuses', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(
                      value: 'disponible',
                      child: Text('Available', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(
                      value: 'en_cours',
                      child: Text('Claimed', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(
                      value: 'validee',
                      child: Text('Fixed', style: TextStyle(fontSize: 13))),
                ],
                onChanged: onStatus,
              ),
              _FilterDropdown(
                label: 'Time Range',
                value: timeRange,
                items: const [
                  DropdownMenuItem(
                      value: 'all',
                      child: Text('All Time', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(
                      value: 'today',
                      child: Text('Today', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(
                      value: 'week',
                      child:
                          Text('Last 7 Days', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(
                      value: 'month',
                      child:
                          Text('This Month', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(
                      value: 'year',
                      child: Text('This Year', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(
                      value: 'custom',
                      child: Text('Custom', style: TextStyle(fontSize: 13))),
                ],
                onChanged: onTime,
              ),
            ];
            final colCount = twoCol ? 2 : 3;
            final rows = <Widget>[];
            for (var i = 0; i < children.length; i += colCount) {
              final rowChildren = <Widget>[];
              for (var j = 0; j < colCount; j++) {
                if (i + j < children.length) {
                  if (j > 0) rowChildren.add(const SizedBox(width: 10));
                  rowChildren.add(Expanded(child: children[i + j]));
                } else {
                  if (j > 0) rowChildren.add(const SizedBox(width: 10));
                  rowChildren.add(const Expanded(child: SizedBox()));
                }
              }
              rows.add(Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(children: rowChildren),
              ));
            }
            return Column(children: rows);
          }),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SHARED SUBCOMPONENTS (active filter banner, dropdown, history row, export)
// ═══════════════════════════════════════════════════════════════════════════

class _ActiveFilterBanner extends StatelessWidget {
  final String timeRange;
  final String timeRangeLabel;
  final String selectedUsine;
  final String filterConvoyeur;
  final String filterPoste;
  final String filterType;
  final String filterStatus;
  final VoidCallback onRemoveUsine;
  final VoidCallback onReset;

  const _ActiveFilterBanner({
    required this.timeRange,
    required this.timeRangeLabel,
    required this.selectedUsine,
    required this.filterConvoyeur,
    required this.filterPoste,
    required this.filterType,
    required this.filterStatus,
    required this.onRemoveUsine,
    required this.onReset,
  });

  bool get _hasNonDefaultFilters =>
      timeRange != 'all' ||
      selectedUsine != 'all' ||
      filterConvoyeur != 'all' ||
      filterPoste != 'all' ||
      filterType != 'all' ||
      filterStatus != 'all';

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    if (!_hasNonDefaultFilters) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: theme.blueLt,
          border: Border.all(color: theme.blue.withValues(alpha: 0.35)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle_outline, size: 15, color: theme.blue),
            const SizedBox(width: 6),
            Text(
              'Showing all alerts — no filters active',
              style: TextStyle(
                fontSize: 12,
                color: theme.blue,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    final chips = <Widget>[];
    if (timeRange != 'all') {
      chips.add(_ActiveChip(label: timeRangeLabel, color: theme.orange));
    }
    if (selectedUsine != 'all') {
      chips.add(_ActiveChip(
          label: selectedUsine, color: theme.orange, onRemove: onRemoveUsine));
    }
    if (filterConvoyeur != 'all') {
      chips.add(
          _ActiveChip(label: 'Line $filterConvoyeur', color: theme.orange));
    }
    if (filterPoste != 'all') {
      chips.add(_ActiveChip(label: 'Post $filterPoste', color: theme.orange));
    }
    if (filterType != 'all') {
      chips
          .add(_ActiveChip(
            label: adminTypeLabel(context, filterType),
            color: theme.orange,
          ));
    }
    if (filterStatus != 'all') {
      chips.add(_ActiveChip(label: filterStatus, color: theme.orange));
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.orangeLt,
        border: Border.all(color: theme.orange.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, size: 15, color: theme.orange),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Filters active — some alerts may be hidden',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.orange,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              GestureDetector(
                onTap: onReset,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: theme.orange,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Reset all',
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.white,
                        fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
          if (chips.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 4, children: chips),
          ],
        ],
      ),
    );
  }
}

class _ActiveChip extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback? onRemove;
  const _ActiveChip({required this.label, required this.color, this.onRemove});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
            color: color, borderRadius: BorderRadius.circular(99)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 11,
                  color: Colors.white,
                  fontWeight: FontWeight.w700)),
          if (onRemove != null) ...[
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onRemove,
              child: const Icon(Icons.close, size: 12, color: Colors.white),
            ),
          ],
        ]),
      );
}

class _ExportBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _ExportBtn(
      {required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: theme.text,
        side: BorderSide(color: theme.border),
        backgroundColor: theme.card,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      icon: Icon(icon, size: 14),
      label: Text(label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}

class _HistoryHeader extends StatelessWidget {
  final int count;
  final VoidCallback onCsv;
  final VoidCallback onExcel;
  const _HistoryHeader({
    required this.count,
    required this.onCsv,
    required this.onExcel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return Row(
      children: [
        Icon(Icons.history_rounded, size: 18, color: theme.navy),
        const SizedBox(width: 8),
        Text(
          'Alert History',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: theme.text,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: theme.navy.withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: theme.navy,
            ),
          ),
        ),
        const Spacer(),
        _ExportBtn(
            label: 'CSV', icon: Icons.table_chart_outlined, onTap: onCsv),
        const SizedBox(width: 8),
        _ExportBtn(
            label: 'Excel', icon: Icons.grid_on_outlined, onTap: onExcel),
      ],
    );
  }
}

class _FilterDropdown extends StatelessWidget {
  final String label, value;
  final List<DropdownMenuItem<String>> items;
  final void Function(String) onChanged;
  const _FilterDropdown(
      {required this.label,
      required this.value,
      required this.items,
      required this.onChanged});

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
          padding: const EdgeInsets.symmetric(horizontal: 10),
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
              onChanged: (v) => onChanged(v!),
            ),
          ),
        ),
      ],
    );
  }
}

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
      _ => 'Available',
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      decoration: BoxDecoration(
        color: theme.card,
        border: Border.all(color: theme.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 38,
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
                Text(
                  '${adminTypeLabel(context, alert.type)} — ${alert.description}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: theme.text,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${alert.usine}  ·  Line ${alert.convoyeur}  ·  Post ${alert.poste}  ·  ${_fmtTs(alert.timestamp)}',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    color: theme.muted,
                  ),
                ),
                if (alert.superviseurName != null)
                  Text('Assigned: ${alert.superviseurName}',
                      style: TextStyle(fontSize: 11, color: theme.blue)),
                if (alert.criticalNote != null &&
                    alert.criticalNote!.isNotEmpty)
                  Text('Critical note: ${alert.criticalNote}',
                      style: TextStyle(fontSize: 11, color: theme.red)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: sc.withValues(alpha: 0.13),
              border: Border.all(color: sc.withValues(alpha: 0.4)),
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
    );
  }
}
