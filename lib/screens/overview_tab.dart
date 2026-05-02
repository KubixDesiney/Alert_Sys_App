part of 'admin_dashboard_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
// ELITE OVERVIEW TAB — Production Manager Dashboard
// Premium presentation layer over the existing alert/filter/export logic.
// ═══════════════════════════════════════════════════════════════════════════

class _OverviewTab extends StatefulWidget {
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

  const _OverviewTab({
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
  State<_OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<_OverviewTab> {
  List<Factory> _factories = [];
  String? _historyFilter;

  @override
  void initState() {
    super.initState();
    _loadFactories();
  }

  void _loadFactories() {
    HierarchyService().getFactories().listen((factories) {
      if (mounted) setState(() => _factories = factories);
    });
  }

  // ───── Existing data helpers (preserved) ─────────────────────────────────

  List<String> _convoyeurs() {
    if (widget.selectedUsine == 'all') return ['all'];
    Factory? factory;
    for (var f in _factories) {
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
    for (var f in _factories) {
      if (f.name == widget.selectedUsine) {
        factory = f;
        break;
      }
    }
    if (factory == null) return ['all'];
    if (widget.filterConvoyeur == 'all') return ['all'];
    Conveyor? conveyor;
    for (var c in factory.conveyors.values) {
      if (c.number.toString() == widget.filterConvoyeur) {
        conveyor = c;
        break;
      }
    }
    if (conveyor == null) return ['all'];
    return [
      'all',
      ...conveyor.stations.values.map((s) => s.id.replaceAll('station_', ''))
    ];
  }

  List<AlertModel> get _criticalUnclaimedAlerts => widget.allAlerts
      .where((a) => a.isCritical && a.status == 'disponible')
      .toList();

  int get _criticalUnclaimedCount => _criticalUnclaimedAlerts.length;

  int get _criticalInProgressCount => widget.allAlerts
      .where((a) => a.status == 'en_cours' && a.isCritical)
      .length;

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
      for (var k in keys)
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
          ..sort()
      ];

  List<String> _convoyeursForFilter() => _convoyeurs();
  List<String> _postesForFilter() => _postes();

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

  // ───── New helpers for elite analytics ───────────────────────────────────

  /// 7-day sparkline series. Index 0 = 6 days ago, 6 = today.
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

  /// Percentage change between first and second halves of a series.
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

  List<_Insight> _smartInsights() {
    final insights = <_Insight>[];
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
      insights.add(_Insight(
        icon: _typeIcon(biggest!),
        color: _typeColor(biggest!),
        text:
            '${_typeLabel(biggest!)} leads this period — $biggestVal alert${biggestVal > 1 ? 's' : ''}.',
      ));
    }

    if (widget.total > 0) {
      final rate = (widget.solved / widget.total * 100).round();
      if (rate >= 80) {
        insights.add(_Insight(
          icon: Icons.trending_up_rounded,
          color: AppColors.green,
          text: 'Resolution rate at $rate% — operations running smoothly.',
        ));
      } else if (rate < 50) {
        insights.add(_Insight(
          icon: Icons.priority_high_rounded,
          color: AppColors.orange,
          text:
              'Resolution rate is $rate% — workload may need redistribution.',
        ));
      }
    }

    if (_criticalUnclaimedCount > 0) {
      insights.add(_Insight(
        icon: Icons.warning_amber_rounded,
        color: AppColors.red,
        text:
            '$_criticalUnclaimedCount critical alert${_criticalUnclaimedCount > 1 ? 's' : ''} awaiting assignment.',
      ));
    }

    final avg = _avgResolutionTime();
    if (avg.inMinutes > 0) {
      insights.add(_Insight(
        icon: Icons.timer_outlined,
        color: AppColors.blue,
        text: 'Average resolution time: ${_fmtDuration(avg)}.',
      ));
    }

    return insights;
  }

  // ───── Exports (preserved exactly) ────────────────────────────────────────

  void _exportFilteredAlerts(List<AlertModel> alertsToExport) async {
    if (alertsToExport.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No alerts to export'),
            backgroundColor: Colors.orange),
      );
      return;
    }
    List<List<dynamic>> csvData = [
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
    for (var alert in alertsToExport) {
      csvData.add([
        alert.id,
        _typeLabel(alert.type),
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
    String csv = const ListToCsvConverter().convert(csvData);
    final bytes = utf8.encode(csv);
    if (kIsWeb) {
      final blob = html.Blob([bytes], 'text/csv');
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..setAttribute('download',
            'alerts_export_${DateTime.now().millisecondsSinceEpoch}.csv')
        ..click();
      html.Url.revokeObjectUrl(url);
    } else {
      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/alerts_export_${DateTime.now().millisecondsSinceEpoch}.csv');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path)], text: 'Alert export');
    }
  }

  void _exportFilteredAlertsExcel(List<AlertModel> alertsToExport) async {
    if (alertsToExport.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No alerts to export'),
            backgroundColor: Colors.orange),
      );
      return;
    }
    var excelFile = excel.Excel.createExcel();
    var sheet = excelFile['Alerts'];
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
    for (var alert in alertsToExport) {
      sheet.appendRow([
        excel.TextCellValue(alert.id),
        excel.TextCellValue(_typeLabel(alert.type)),
        excel.TextCellValue(alert.usine),
        excel.IntCellValue(alert.convoyeur),
        excel.IntCellValue(alert.poste),
        excel.TextCellValue(alert.adresse),
        excel.TextCellValue(alert.timestamp.toIso8601String()),
        excel.TextCellValue(alert.description),
        excel.TextCellValue(alert.status),
        excel.TextCellValue(alert.superviseurName ?? ''),
        excel.TextCellValue(alert.assistantName ?? ''),
        excel.TextCellValue(alert.resolutionReason ?? ''),
        excel.IntCellValue(alert.elapsedTime ?? 0),
        excel.TextCellValue(alert.isCritical ? 'Yes' : 'No'),
      ]);
    }
    final fileBytes = excelFile.encode();
    if (fileBytes == null) return;
    if (kIsWeb) {
      final blob = html.Blob([fileBytes],
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..setAttribute('download',
            'alerts_export_${DateTime.now().millisecondsSinceEpoch}.xlsx')
        ..click();
      html.Url.revokeObjectUrl(url);
    } else {
      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/alerts_export_${DateTime.now().millisecondsSinceEpoch}.xlsx');
      await file.writeAsBytes(fileBytes);
      await Share.shareXFiles([XFile(file.path)], text: 'Alert export');
    }
  }

  // ───── Build ──────────────────────────────────────────────────────────────

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
          _HeroHeader(
            timeRangeLabel: widget.timeRangeLabel,
            timeRangeSubtitle: widget.timeRangeSubtitle,
            isLive: true,
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

          // Production Health — signature card
          _HealthScoreCard(
            value: health,
            resolutionRate: resolutionRate,
            criticalCount: _criticalUnclaimedCount,
            avgResponseLabel: _fmtDuration(_avgResolutionTime()),
            totalAlerts: widget.total,
          ),
          const SizedBox(height: 14),

          // Elite stat cards with sparklines
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
            _InsightsStrip(insights: insights),
            const SizedBox(height: 18),
          ],

          _TypeBreakdownPanel(
            stats: ts,
            activeFilter: _historyFilter,
            onTap: _setHistoryFilter,
          ),
          const SizedBox(height: 18),

          if (_criticalUnclaimedCount > 0) ...[
            _CriticalAlertsCard(
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
            convoyeurs: _convoyeursForFilter(),
            postes: _postesForFilter(),
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

  Widget _statCardReceived(AppTheme theme, List<int> spark) => _EliteStatCard(
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

  Widget _statCardClaimed(AppTheme theme, List<int> spark) => _EliteStatCard(
        label: 'Claimed',
        value: widget.inProgress,
        icon: Icons.timelapse_rounded,
        color: theme.blue,
        accentLt: theme.blueLt,
        spark: spark,
        trendPct: _trendPct(spark),
        criticalCount: _criticalInProgressCount,
        isActive: _historyFilter == 'en_cours',
        onTap: () => _setHistoryFilter('en_cours'),
        onCriticalTap: () => _setHistoryFilter('critical'),
      );

  Widget _statCardFixed(AppTheme theme, List<int> spark) => _EliteStatCard(
        label: 'Fixed',
        value: widget.solved,
        icon: Icons.check_circle_rounded,
        color: theme.green,
        accentLt: theme.greenLt,
        spark: spark,
        trendPct: _trendPct(spark),
        isActive: _historyFilter == 'validated',
        onTap: () => _setHistoryFilter('validated'),
      );

  Widget _statCardTotal(AppTheme theme, List<int> spark) => _EliteStatCard(
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
// HERO HEADER
// ═══════════════════════════════════════════════════════════════════════════

class _HeroHeader extends StatelessWidget {
  final String timeRangeLabel;
  final String timeRangeSubtitle;
  final bool isLive;
  const _HeroHeader({
    required this.timeRangeLabel,
    required this.timeRangeSubtitle,
    required this.isLive,
  });

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 5) return 'Working late';
    if (h < 12) return 'Good morning';
    if (h < 18) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: context.isDark
              ? [
                  const Color(0xFF1E3A5F),
                  const Color(0xFF1E293B),
                ]
              : [
                  const Color(0xFF0D4A75),
                  const Color(0xFF1E5C8C),
                ],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: theme.navy.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (isLive) const _LivePulseDot(),
                    if (isLive) const SizedBox(width: 8),
                    Text(
                      isLive ? 'LIVE  ·  REAL-TIME' : 'OVERVIEW',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.6,
                        color: Colors.white.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${_greeting()}, supervisor',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Operations Overview',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1.1,
                  ),
                ),
                if (timeRangeSubtitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    timeRangeSubtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.calendar_month_rounded,
                    size: 14, color: Colors.white),
                const SizedBox(width: 6),
                Text(
                  timeRangeLabel,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LivePulseDot extends StatefulWidget {
  const _LivePulseDot();

  @override
  State<_LivePulseDot> createState() => _LivePulseDotState();
}

class _LivePulseDotState extends State<_LivePulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 12,
      height: 12,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) {
          final t = _ctrl.value;
          final scale = 1.0 + t * 1.4;
          final opacity = (1.0 - t).clamp(0.0, 1.0);
          return Stack(
            alignment: Alignment.center,
            children: [
              Transform.scale(
                scale: scale,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: const Color(0xFF4ADE80).withValues(alpha: opacity * 0.6),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: Color(0xFF4ADE80),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x664ADE80),
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

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
              style: TextStyle(
                fontSize: 12,
                color: theme.muted,
              ),
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

      // Tip glow
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
// ELITE STAT CARD — sparkline + animated counter + trend badge
// ═══════════════════════════════════════════════════════════════════════════

class _EliteStatCard extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  final Color color;
  final Color accentLt;
  final List<int> spark;
  final double trendPct;
  final int? criticalCount;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback? onCriticalTap;

  const _EliteStatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.accentLt,
    required this.spark,
    required this.trendPct,
    required this.isActive,
    required this.onTap,
    this.criticalCount,
    this.onCriticalTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final isDark = context.isDark;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        decoration: BoxDecoration(
          gradient: isActive
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    accentLt,
                    theme.card,
                  ],
                )
              : null,
          color: isActive ? null : theme.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isActive ? color : theme.border,
            width: isActive ? 1.6 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: (isActive ? color : Colors.black)
                  .withValues(alpha: isDark ? 0.18 : (isActive ? 0.10 : 0.04)),
              blurRadius: isActive ? 14 : 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 16, color: color),
                ),
                const Spacer(),
                _TrendBadge(pct: trendPct),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                color: theme.muted,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 4),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: value.toDouble()),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (_, v, __) => Text(
                v.toInt().toString(),
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: color,
                  height: 1,
                  letterSpacing: -0.5,
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 28,
              child: spark.fold<int>(0, (a, b) => a + b) == 0
                  ? Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'No 7-day activity',
                        style: TextStyle(
                          fontSize: 10,
                          color: theme.muted,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    )
                  : CustomPaint(
                      painter: _SparklinePainter(data: spark, color: color),
                      size: Size.infinite,
                    ),
            ),
            if (criticalCount != null && criticalCount! > 0) ...[
              const SizedBox(height: 6),
              GestureDetector(
                onTap: onCriticalTap,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: theme.red.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          size: 11, color: theme.red),
                      const SizedBox(width: 3),
                      Text(
                        '$criticalCount critical',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: theme.red,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TrendBadge extends StatelessWidget {
  final double pct;
  const _TrendBadge({required this.pct});

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final isUp = pct > 0;
    final isFlat = pct.abs() < 0.5;
    final color =
        isFlat ? theme.muted : (isUp ? theme.green : theme.red);
    final icon = isFlat
        ? Icons.remove_rounded
        : (isUp ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded);
    final txt = isFlat ? '0%' : '${pct.abs().toStringAsFixed(0)}%';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 2),
          Text(
            txt,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<int> data;
  final Color color;
  _SparklinePainter({required this.data, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    final maxVal = data.reduce((a, b) => a > b ? a : b).toDouble();
    if (maxVal == 0) return;

    final n = data.length;
    final stepX = n > 1 ? size.width / (n - 1) : size.width;
    double yFor(int i) {
      final pad = size.height * 0.12;
      final usable = size.height - pad * 2;
      return pad + usable - (data[i] / maxVal) * usable;
    }

    final path = Path();
    final fill = Path();
    final firstY = yFor(0);
    path.moveTo(0, firstY);
    fill.moveTo(0, size.height);
    fill.lineTo(0, firstY);

    for (var i = 1; i < n; i++) {
      final x = i * stepX;
      final y = yFor(i);
      final prevX = (i - 1) * stepX;
      final prevY = yFor(i - 1);
      final cp1 = Offset(prevX + stepX / 2, prevY);
      final cp2 = Offset(x - stepX / 2, y);
      path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, x, y);
      fill.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, x, y);
    }
    fill.lineTo(size.width, size.height);
    fill.close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: 0.32),
          color.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(fill, fillPaint);

    final strokePaint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, strokePaint);

    // Last-point dot
    final lastX = (n - 1) * stepX;
    final lastY = yFor(n - 1);
    final dotGlow = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(Offset(lastX, lastY), 4, dotGlow);
    final dot = Paint()..color = color;
    canvas.drawCircle(Offset(lastX, lastY), 2.5, dot);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter old) =>
      old.data != data || old.color != color;
}

// ═══════════════════════════════════════════════════════════════════════════
// SMART INSIGHTS STRIP
// ═══════════════════════════════════════════════════════════════════════════

class _Insight {
  final IconData icon;
  final Color color;
  final String text;
  _Insight({required this.icon, required this.color, required this.text});
}

class _InsightsStrip extends StatelessWidget {
  final List<_Insight> insights;
  const _InsightsStrip({required this.insights});

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: theme.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: theme.purple.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome_rounded,
                        size: 11, color: theme.purple),
                    const SizedBox(width: 4),
                    Text(
                      'INSIGHTS',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.4,
                        color: theme.purple,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Auto-generated from current data',
                style: TextStyle(
                  fontSize: 11,
                  color: theme.muted,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...insights.map((i) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 2),
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: i.color.withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(i.icon, size: 12, color: i.color),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        i.text,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: theme.text,
                          fontWeight: FontWeight.w500,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TYPE BREAKDOWN PANEL — animated horizontal bars
// ═══════════════════════════════════════════════════════════════════════════

class _TypeBreakdownPanel extends StatelessWidget {
  final Map<String, Map<String, int>> stats;
  final String? activeFilter;
  final void Function(String) onTap;
  const _TypeBreakdownPanel({
    required this.stats,
    required this.activeFilter,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final maxTotal = stats.values
        .map((m) => m['total']!)
        .fold<int>(0, (a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: theme.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.donut_large_rounded, size: 18, color: theme.navy),
              const SizedBox(width: 8),
              Text(
                'Alert Type Distribution',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: theme.text,
                ),
              ),
              const Spacer(),
              Text(
                'Tap to filter',
                style: TextStyle(
                  fontSize: 11,
                  color: theme.muted,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...stats.entries.map((e) {
            final total = e.value['total']!;
            final solved = e.value['solved']!;
            final pending = e.value['pending']!;
            return _TypeBreakdownRow(
              type: e.key,
              total: total,
              solved: solved,
              pending: pending,
              maxTotal: maxTotal,
              isActive: activeFilter == e.key,
              onTap: () => onTap(e.key),
            );
          }),
        ],
      ),
    );
  }
}

class _TypeBreakdownRow extends StatelessWidget {
  final String type;
  final int total, solved, pending, maxTotal;
  final bool isActive;
  final VoidCallback onTap;
  const _TypeBreakdownRow({
    required this.type,
    required this.total,
    required this.solved,
    required this.pending,
    required this.maxTotal,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final color = _typeColor(type);
    final fraction = maxTotal == 0 ? 0.0 : total / maxTotal;
    final solvedFraction = total == 0 ? 0.0 : solved / total;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        decoration: BoxDecoration(
          color: isActive ? color.withValues(alpha: 0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isActive ? color.withValues(alpha: 0.5) : Colors.transparent,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Icon(_typeIcon(type), size: 15, color: color),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _typeLabel(type),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: theme.text,
                    ),
                  ),
                ),
                Text(
                  '$total',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: SizedBox(
                height: 8,
                child: Stack(
                  children: [
                    Container(color: theme.border),
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: fraction),
                      duration: const Duration(milliseconds: 700),
                      curve: Curves.easeOutCubic,
                      builder: (_, w, __) => FractionallySizedBox(
                        widthFactor: w.clamp(0.0, 1.0),
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                color.withValues(alpha: 0.7),
                                color,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.check_circle_outline,
                    size: 12, color: theme.green),
                const SizedBox(width: 4),
                Text(
                  '$solved fixed',
                  style: TextStyle(fontSize: 11, color: theme.muted),
                ),
                const SizedBox(width: 12),
                Icon(Icons.schedule_rounded, size: 12, color: theme.orange),
                const SizedBox(width: 4),
                Text(
                  '$pending pending',
                  style: TextStyle(fontSize: 11, color: theme.muted),
                ),
                const Spacer(),
                Text(
                  total == 0
                      ? '—'
                      : '${(solvedFraction * 100).toStringAsFixed(0)}% resolved',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: theme.text,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CRITICAL ALERTS CARD
// ═══════════════════════════════════════════════════════════════════════════

class _CriticalAlertsCard extends StatelessWidget {
  final List<AlertModel> alerts;
  final void Function(AlertModel) onAlertTap;
  final String Function(AlertModel) describe;
  const _CriticalAlertsCard({
    required this.alerts,
    required this.onAlertTap,
    required this.describe,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: theme.redLt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.red.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            color: theme.red.withValues(alpha: 0.15),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: theme.red.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.warning_amber_rounded,
                    size: 17, color: theme.red),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Critical · ${alerts.length} pending',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: theme.red,
                      ),
                    ),
                    Text(
                      'Awaiting assignment for over 10 minutes',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.red.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...alerts.map((alert) {
            final elapsedMin =
                DateTime.now().difference(alert.timestamp).inMinutes;
            final elapsedText = elapsedMin < 60
                ? '${elapsedMin}m'
                : '${elapsedMin ~/ 60}h ${elapsedMin % 60}m';
            return GestureDetector(
              onTap: () => onAlertTap(alert),
              child: Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: theme.card,
                  border: Border.all(color: theme.border),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 4,
                      height: 36,
                      decoration: BoxDecoration(
                        color: _typeColor(alert.type),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${_typeLabel(alert.type)} — ${describe(alert)}',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: theme.text,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${alert.usine} · Line ${alert.convoyeur} · WS ${alert.poste}',
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: theme.red.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(
                            color: theme.red.withValues(alpha: 0.35)),
                      ),
                      child: Text(
                        elapsedText,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: theme.red,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.chevron_right, size: 18, color: theme.muted),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// HISTORY HEADER + EXPORT
// ═══════════════════════════════════════════════════════════════════════════

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
        _ExportBtn(label: 'CSV', icon: Icons.table_chart_outlined, onTap: onCsv),
        const SizedBox(width: 8),
        _ExportBtn(label: 'Excel', icon: Icons.grid_on_outlined, onTap: onExcel),
      ],
    );
  }
}

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
            child: Icon(Icons.check_circle_outline,
                size: 30, color: theme.green),
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
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700)),
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
                      child: Text('All Types',
                          style: TextStyle(fontSize: 13))),
                  ...[
                    'qualite',
                    'maintenance',
                    'defaut_produit',
                    'manque_ressource'
                  ].map((t) => DropdownMenuItem(
                        value: t,
                        child:
                            Text(_typeLabel(t), style: const TextStyle(fontSize: 13)),
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
                      child:
                          Text('Fixed', style: TextStyle(fontSize: 13))),
                ],
                onChanged: onStatus,
              ),
              _FilterDropdown(
                label: 'Time Range',
                value: timeRange,
                items: const [
                  DropdownMenuItem(
                      value: 'all',
                      child:
                          Text('All Time', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(
                      value: 'today',
                      child: Text('Today', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(
                      value: 'week',
                      child: Text('Last 7 Days',
                          style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(
                      value: 'month',
                      child:
                          Text('This Month', style: TextStyle(fontSize: 13))),
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
      chips.add(_ActiveChip(
          label: 'Line $filterConvoyeur', color: theme.orange));
    }
    if (filterPoste != 'all') {
      chips.add(_ActiveChip(label: 'Post $filterPoste', color: theme.orange));
    }
    if (filterType != 'all') {
      chips.add(_ActiveChip(
          label: _typeLabel(filterType), color: theme.orange));
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
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      icon: Icon(icon, size: 14),
      label: Text(label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
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
              color: _typeColor(alert.type),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_typeLabel(alert.type)} — ${alert.description}',
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
