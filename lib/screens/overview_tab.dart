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
      child: LayoutBuilder(builder: (ctx, c) {
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

  MorningBriefing? _briefing;
  PredictiveModel? _predictions;
  StreamSubscription<MorningBriefing?>? _briefSub;
  StreamSubscription<PredictiveModel?>? _predSub;
  bool _briefingWarmed = false;
  bool _predictionsWarmed = false;

  // Pagination state for the alert history list.
  int _pageSize = 10;
  int _pageIndex = 0;

  static const _pageSizeOptions = [5, 10, 25, 50, 100];

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
      .where((a) =>
          a.isCritical &&
          a.status == 'disponible' &&
          (widget.selectedUsine == 'all' || a.usine == widget.selectedUsine))
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
      _pageIndex = 0;
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
        .where((a) =>
            a.status == 'validee' &&
            a.elapsedTime != null &&
            a.elapsedTime! > 0 &&
            (widget.selectedUsine == 'all' ||
                a.usine == widget.selectedUsine))
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

  // Filter the predictive model client-side so cards reflect the master factory
  // selector even though the model is computed globally on the edge.
  PredictiveModel? _scopedPredictions() {
    final m = _predictions;
    if (m == null) return null;
    if (widget.selectedUsine == 'all') return m;
    return PredictiveModel(
      curves: m.curves,
      predictions:
          m.predictions.where((p) => p.usine == widget.selectedUsine).toList(),
      factoryRisk:
          m.factoryRisk.where((f) => f.name == widget.selectedUsine).toList(),
      generatedAt: m.generatedAt,
    );
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
              _pageIndex = 0;
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
    if (_historyFilter != null) n++;
    return n;
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
    final scopedPreds = _scopedPredictions();

    return LayoutBuilder(builder: (ctx, constraints) {
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
            _pageIndex = 0;
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

      final statGrid = LayoutBuilder(builder: (gctx, gc) {
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
          return Column(children: [
            Row(children: [
              Expanded(child: cards[0]),
              const SizedBox(width: 10),
              Expanded(child: cards[1]),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: cards[2]),
              const SizedBox(width: 10),
              Expanded(child: cards[3]),
            ]),
          ]);
        }
        return Row(children: [
          Expanded(child: cards[0]),
          const SizedBox(width: 10),
          Expanded(child: cards[1]),
          const SizedBox(width: 10),
          Expanded(child: cards[2]),
          const SizedBox(width: 10),
          Expanded(child: cards[3]),
        ]);
      });

      final leftColumn = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          healthCard,
          const SizedBox(height: 12),
          statGrid,
        ],
      );

      final pages = _displayedAlerts;
      final pageCount = pages.isEmpty
          ? 1
          : ((pages.length + _pageSize - 1) ~/ _pageSize);
      final clampedPage = _pageIndex.clamp(0, pageCount - 1);
      final start = clampedPage * _pageSize;
      final end = math.min(start + _pageSize, pages.length);
      final pageItems = pages.sublist(start, end);

      final historyBox = _AlertHistoryBox(
        alerts: pages,
        pageItems: pageItems,
        pageIndex: clampedPage,
        pageCount: pageCount,
        pageSize: _pageSize,
        pageSizeOptions: _pageSizeOptions,
        activeFilterChip: _historyFilter,
        onClearChip: () => setState(() => _historyFilter = null),
        onPageSizeChange: (s) => setState(() {
          _pageSize = s;
          _pageIndex = 0;
        }),
        onPrev: clampedPage > 0
            ? () => setState(() => _pageIndex = clampedPage - 1)
            : null,
        onNext: clampedPage < pageCount - 1
            ? () => setState(() => _pageIndex = clampedPage + 1)
            : null,
        onOpenFilters: _openFilterSheet,
        onCsv: () => _exportFilteredAlerts(pages),
        onExcel: () => _exportFilteredAlertsExcel(pages),
        scope: widget.selectedUsine == 'all'
            ? 'All Plants'
            : widget.selectedUsine,
      );

      final predictiveRow = LayoutBuilder(builder: (pctx, pc) {
        final stack = pc.maxWidth < 720;
        final failure = PredictiveFailureCard(
          model: scopedPreds,
          describeType: (type) => adminTypeLabel(context, type),
        );
        final risk = PredictiveRiskHeatmap(
          stats: ts,
          model: scopedPreds,
          activeFilter: _historyFilter,
          onTap: _setHistoryFilter,
        );
        if (stack) {
          return Column(children: [
            failure,
            const SizedBox(height: 12),
            risk,
          ]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: failure),
          const SizedBox(width: 12),
          Expanded(child: risk),
        ]);
      });

      final critical = _criticalUnclaimedCount > 0
          ? Padding(
              padding: const EdgeInsets.only(top: 14),
              child: CriticalAlertsCard(
                alerts: _criticalUnclaimedAlerts,
                onAlertTap: (a) => _setHistoryFilter(a.type),
                describe: _getAlertDisplayDescription,
              ),
            )
          : const SizedBox.shrink();

      final insightsBlock = insights.isNotEmpty
          ? Padding(
              padding: const EdgeInsets.only(top: 14),
              child: InsightsStrip(insights: insights),
            )
          : const SizedBox.shrink();

      // Wide layout: production health + history side by side; predictive
      // intelligence stacked underneath.
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
                  Expanded(flex: 5, child: historyBox),
                ],
              ),
            ),
            const SizedBox(height: 14),
            predictiveRow,
            critical,
            insightsBlock,
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
            SizedBox(height: 520, child: historyBox),
            const SizedBox(height: 14),
            predictiveRow,
            critical,
            insightsBlock,
          ],
        );
      }

      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 60),
        child: body,
      );
    });
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
              : [
                  t.navyLt,
                  t.purple.withValues(alpha: 0.05),
                ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.navy.withValues(alpha: 0.32)),
      ),
      child: LayoutBuilder(builder: (ctx, c) {
        final narrow = c.maxWidth < 620;
        final factoryPicker = Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: t.border),
          ),
          child: Row(children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [t.navy, t.purple],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child:
                  const Icon(Icons.factory_rounded, size: 17, color: Colors.white),
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
                      value: factories.contains(selected) ? selected : 'all',
                      isExpanded: true,
                      isDense: true,
                      style: TextStyle(
                        fontSize: 14,
                        color: t.text,
                        fontWeight: FontWeight.w700,
                      ),
                      dropdownColor: t.card,
                      icon: Icon(Icons.keyboard_arrow_down_rounded,
                          color: t.navy),
                      items: factories
                          .map((f) => DropdownMenuItem(
                                value: f,
                                child: Text(
                                  f == 'all' ? 'All Plants' : f,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: t.text,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) onChanged(v);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ]),
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
          child: Row(mainAxisSize: MainAxisSize.min, children: [
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
          ]),
        );

        final timeChip = Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: t.orange.withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: t.orange.withValues(alpha: 0.35)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
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
          ]),
        );

        final filterBtn = OutlinedButton.icon(
          onPressed: onOpenFilters,
          icon: const Icon(Icons.tune_rounded, size: 16),
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Filters',
                  style:
                      TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              if (activeCount > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: t.navy,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    '$activeCount',
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ]
            ],
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: t.navy,
            backgroundColor: t.card,
            side: BorderSide(color: t.border),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
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
              Row(children: [
                scopeChip,
                const SizedBox(width: 6),
                timeChip,
                const Spacer(),
                filterBtn,
                if (activeCount > 0) ...[
                  const SizedBox(width: 6),
                  resetBtn,
                ],
              ]),
            ],
          );
        }
        return Row(children: [
          Expanded(flex: 5, child: factoryPicker),
          const SizedBox(width: 12),
          scopeChip,
          const SizedBox(width: 6),
          timeChip,
          const SizedBox(width: 10),
          filterBtn,
          if (activeCount > 0) ...[
            const SizedBox(width: 6),
            resetBtn,
          ],
        ]);
      }),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ALERT HISTORY BOX — scrollable list with filter icon, paging, exports.
// ═══════════════════════════════════════════════════════════════════════════

class _AlertHistoryBox extends StatelessWidget {
  final List<AlertModel> alerts;
  final List<AlertModel> pageItems;
  final int pageIndex;
  final int pageCount;
  final int pageSize;
  final List<int> pageSizeOptions;
  final String? activeFilterChip;
  final VoidCallback onClearChip;
  final void Function(int) onPageSizeChange;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final VoidCallback onOpenFilters;
  final VoidCallback onCsv;
  final VoidCallback onExcel;
  final String scope;

  const _AlertHistoryBox({
    required this.alerts,
    required this.pageItems,
    required this.pageIndex,
    required this.pageCount,
    required this.pageSize,
    required this.pageSizeOptions,
    required this.activeFilterChip,
    required this.onClearChip,
    required this.onPageSizeChange,
    required this.onPrev,
    required this.onNext,
    required this.onOpenFilters,
    required this.onCsv,
    required this.onExcel,
    required this.scope,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
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
            child: Row(children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [theme.navy, theme.blue],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.history_rounded,
                    size: 16, color: Colors.white),
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
                      '${alerts.length} alert${alerts.length == 1 ? '' : 's'} · $scope',
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
              if (activeFilterChip != null) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.purple.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(
                      color: theme.purple.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.filter_alt_rounded,
                        size: 11, color: theme.purple),
                    const SizedBox(width: 4),
                    Text(
                      _chipLabel(context, activeFilterChip!),
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: theme.purple,
                      ),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: onClearChip,
                      child:
                          Icon(Icons.close, size: 12, color: theme.purple),
                    ),
                  ]),
                ),
                const SizedBox(width: 6),
              ],
              Tooltip(
                message: 'Filter & search',
                child: InkWell(
                  onTap: onOpenFilters,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.navy.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: theme.navy.withValues(alpha: 0.2),
                      ),
                    ),
                    child:
                        Icon(Icons.tune_rounded, size: 16, color: theme.navy),
                  ),
                ),
              ),
            ]),
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
            child: Row(children: [
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
                    value: pageSize,
                    isDense: true,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.text,
                      fontWeight: FontWeight.w700,
                    ),
                    dropdownColor: theme.card,
                    items: pageSizeOptions
                        .map((s) => DropdownMenuItem(
                              value: s,
                              child: Text(
                                '$s',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.text,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) onPageSizeChange(v);
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
                onPressed: onPrev,
                icon: const Icon(Icons.chevron_left_rounded),
                iconSize: 20,
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 30, minHeight: 30),
                color: theme.navy,
                disabledColor: theme.muted.withValues(alpha: 0.4),
                tooltip: 'Previous page',
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: theme.navy.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  '${pageIndex + 1} / $pageCount',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.navy,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                onPressed: onNext,
                icon: const Icon(Icons.chevron_right_rounded),
                iconSize: 20,
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 30, minHeight: 30),
                color: theme.navy,
                disabledColor: theme.muted.withValues(alpha: 0.4),
                tooltip: 'Next page',
              ),
            ]),
          ),
          Divider(color: theme.border, height: 1),
          // Export footer
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onCsv,
                  icon: const Icon(Icons.table_chart_outlined, size: 14),
                  label: const Text('CSV',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.text,
                    side: BorderSide(color: theme.border),
                    backgroundColor: theme.scaffold,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onExcel,
                  icon: const Icon(Icons.grid_on_outlined, size: 14),
                  label: const Text('Excel',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.green,
                    side: BorderSide(
                      color: theme.green.withValues(alpha: 0.45),
                    ),
                    backgroundColor: theme.greenLt,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  String _chipLabel(BuildContext ctx, String key) {
    switch (key) {
      case 'pending':
        return 'AVAILABLE';
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
      child: LayoutBuilder(builder: (ctx, c) {
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
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.navy.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child:
                      Icon(Icons.tune_rounded, size: 18, color: theme.navy),
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
                        style:
                            TextStyle(fontSize: 11.5, color: theme.muted),
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
                  label: const Text('Reset',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700)),
                  style: TextButton.styleFrom(foregroundColor: theme.red),
                ),
              ]),
              const SizedBox(height: 14),
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
              const SizedBox(height: 10),
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
              const SizedBox(height: 10),
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
              const SizedBox(height: 10),
              _FilterDropdown(
                label: 'Alert Type',
                value: filterType,
                items: [
                  const DropdownMenuItem(
                      value: 'all',
                      child: Text('All Types',
                          style: TextStyle(fontSize: 13))),
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
              const SizedBox(height: 10),
              _FilterDropdown(
                label: 'Status',
                value: filterStatus,
                items: const [
                  DropdownMenuItem(
                      value: 'all',
                      child: Text('All Statuses',
                          style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(
                      value: 'disponible',
                      child:
                          Text('Available', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(
                      value: 'en_cours',
                      child:
                          Text('Claimed', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(
                      value: 'validee',
                      child: Text('Fixed', style: TextStyle(fontSize: 13))),
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
                      child: Text('All Time', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(
                      value: 'today',
                      child: Text('Today', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(
                      value: 'week',
                      child: Text('Last 7 Days',
                          style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(
                      value: 'month',
                      child: Text('This Month',
                          style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(
                      value: 'year',
                      child:
                          Text('This Year', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(
                      value: 'custom',
                      child: Text('Custom', style: TextStyle(fontSize: 13))),
                ],
                onChanged: onTime,
              ),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: () => Navigator.of(ctx).pop(),
                icon: const Icon(Icons.check_rounded, size: 16),
                label: const Text('Apply',
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
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
      }),
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
      _ => 'Available',
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
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: adminTypeColor(context, alert.type)
                              .withValues(alpha: 0.13),
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
                              horizontal: 6, vertical: 2),
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
                            horizontal: 8, vertical: 3),
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
                    ]),
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
                        child: Row(children: [
                          Icon(Icons.person_outline,
                              size: 11, color: theme.blue),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'Assigned: ${alert.superviseurName}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 11, color: theme.blue),
                            ),
                          ),
                        ]),
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
