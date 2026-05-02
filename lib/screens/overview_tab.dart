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

  // Predictive intelligence (worker-driven)
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
    HierarchyService().getFactories().listen((factories) {
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
    // Trigger a single fetch on first load so the worker primes the cache
    // even if the cron hasn't run yet.
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
          text: 'Resolution rate is $rate% — workload may need redistribution.',
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
          _AIMorningBriefingHero(
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

          // ── Predictive Failure Alerts (ML on historical patterns) ──
          _PredictiveFailureCard(
            model: _predictions,
            describeType: _typeLabel,
          ),
          const SizedBox(height: 18),

          // ── Predictive Risk Heatmap (replaces static type bars) ──
          _PredictiveRiskHeatmap(
            stats: ts,
            model: _predictions,
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
// AI MORNING BRIEFING HERO — replaces the static greeting with an LLM
// paragraph regenerated nightly by the Cloudflare Worker. Sparkling motion
// graphics, animated gradient mesh, dark/light aware.
// ═══════════════════════════════════════════════════════════════════════════

class _AIMorningBriefingHero extends StatefulWidget {
  final MorningBriefing? briefing;
  final String timeRangeLabel;
  final String timeRangeSubtitle;
  final Future<void> Function() onRefresh;
  const _AIMorningBriefingHero({
    required this.briefing,
    required this.timeRangeLabel,
    required this.timeRangeSubtitle,
    required this.onRefresh,
  });

  @override
  State<_AIMorningBriefingHero> createState() => _AIMorningBriefingHeroState();
}

class _AIMorningBriefingHeroState extends State<_AIMorningBriefingHero>
    with TickerProviderStateMixin {
  late final AnimationController _meshCtrl;
  late final AnimationController _sparkleCtrl;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _meshCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat();
    _sparkleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
  }

  @override
  void dispose() {
    _meshCtrl.dispose();
    _sparkleCtrl.dispose();
    super.dispose();
  }

  String _fallbackGreeting() {
    final h = DateTime.now().hour;
    if (h < 5) return 'Working late';
    if (h < 12) return 'Good morning';
    if (h < 18) return 'Good afternoon';
    return 'Good evening';
  }

  String _displaySummary() {
    final b = widget.briefing;
    if (b != null && b.summary.trim().isNotEmpty) return b.summary.trim();
    return '${_fallbackGreeting()}, supervisor. Your AI briefing is warming up — historical patterns are being analysed in the background. Hard data and a personalised summary will land here within the next minute.';
  }

  String _modelLabel() {
    final b = widget.briefing;
    if (b == null) return 'AI BRIEFING · WARMING UP';
    if (b.model == null || b.model == 'fallback')
      return 'AI BRIEFING · OFFLINE FALLBACK';
    return 'AI BRIEFING · LLAMA 3.2';
  }

  String _generatedLabel() {
    final ts = widget.briefing?.generatedAt;
    if (ts == null) return 'just now';
    final dt = DateTime.tryParse(ts);
    if (dt == null) return 'just now';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'moments ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Future<void> _doRefresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    await widget.onRefresh();
    if (mounted) setState(() => _refreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final isDark = context.isDark;
    final summary = _displaySummary();
    final b = widget.briefing;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Stack(
        children: [
          // Animated gradient mesh background
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _meshCtrl,
              builder: (_, __) => CustomPaint(
                painter: _AuroraMeshPainter(
                  t: _meshCtrl.value,
                  dark: isDark,
                ),
              ),
            ),
          ),
          // Sparkles layer
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _sparkleCtrl,
                builder: (_, __) => CustomPaint(
                  painter: _SparklePainter(t: _sparkleCtrl.value),
                ),
              ),
            ),
          ),
          // Glassy overlay for legibility
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.black.withValues(alpha: isDark ? 0.18 : 0.05),
                    Colors.black.withValues(alpha: isDark ? 0.42 : 0.20),
                  ],
                ),
              ),
            ),
          ),
          // Content
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 18, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const _LivePulseDot(),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.auto_awesome_rounded,
                              size: 11, color: Colors.white),
                          const SizedBox(width: 4),
                          Text(
                            _modelLabel(),
                            style: const TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.4,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.calendar_month_rounded,
                              size: 13, color: Colors.white),
                          const SizedBox(width: 6),
                          Text(
                            widget.timeRangeLabel,
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ShaderMask(
                  shaderCallback: (rect) => const LinearGradient(
                    colors: [Colors.white, Color(0xFFE0E7FF)],
                  ).createShader(rect),
                  child: const Text(
                    'Operations Briefing',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      height: 1.1,
                      letterSpacing: -0.4,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 480),
                  child: Text(
                    summary,
                    key: ValueKey(summary.hashCode),
                    style: TextStyle(
                      fontSize: 13.5,
                      color: Colors.white.withValues(alpha: 0.92),
                      height: 1.55,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (b?.topType != null)
                      _briefChip(
                        Icons.local_fire_department_rounded,
                        '${_typeLabel(b!.topType!)} leads · ${b.topTypeCount}',
                      ),
                    if (b?.topFactory != null)
                      _briefChip(
                        Icons.factory_rounded,
                        '${b!.topFactory} most active',
                      ),
                    if (b != null)
                      _briefChip(
                        Icons.trending_up_rounded,
                        '${b.resolutionRate}% resolved',
                      ),
                    _briefChip(
                      Icons.schedule_rounded,
                      'Updated ${_generatedLabel()}',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      widget.timeRangeSubtitle,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.white.withValues(alpha: 0.72),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(99),
                        onTap: _doRefresh,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.white.withValues(alpha: 0.22),
                                Colors.white.withValues(alpha: 0.10),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(99),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_refreshing)
                                const SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.6,
                                    valueColor:
                                        AlwaysStoppedAnimation(Colors.white),
                                  ),
                                )
                              else
                                const Icon(Icons.auto_awesome_rounded,
                                    size: 13, color: Colors.white),
                              const SizedBox(width: 6),
                              Text(
                                _refreshing ? 'Generating…' : 'Regenerate',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                  color: theme.text == Colors.white
                                      ? Colors.white
                                      : Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
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

  Widget _briefChip(IconData icon, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 11, color: Colors.white.withValues(alpha: 0.92)),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: Colors.white.withValues(alpha: 0.95),
              letterSpacing: 0.2,
            ),
          ),
        ]),
      );
}

// Aurora mesh — three soft radial gradient blobs slowly orbiting.
class _AuroraMeshPainter extends CustomPainter {
  final double t;
  final bool dark;
  _AuroraMeshPainter({required this.t, required this.dark});

  @override
  void paint(Canvas canvas, Size size) {
    final base = dark
        ? const [Color(0xFF0B1E3F), Color(0xFF1E2A4D)]
        : const [Color(0xFF0D4A75), Color(0xFF1E5C8C)];
    final bgPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: base,
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, bgPaint);

    final twoPi = math.pi * 2;
    final blobs = [
      _Blob(
        center: Offset(
          size.width * (0.20 + 0.18 * math.sin(twoPi * t)),
          size.height * (0.30 + 0.18 * math.cos(twoPi * t * 0.9)),
        ),
        radius: size.width * 0.55,
        color: dark
            ? const Color(0xFF6366F1).withValues(alpha: 0.35)
            : const Color(0xFF60A5FA).withValues(alpha: 0.55),
      ),
      _Blob(
        center: Offset(
          size.width * (0.78 + 0.10 * math.cos(twoPi * (t + 0.33))),
          size.height * (0.65 + 0.18 * math.sin(twoPi * (t + 0.33))),
        ),
        radius: size.width * 0.55,
        color: dark
            ? const Color(0xFF8B5CF6).withValues(alpha: 0.32)
            : const Color(0xFFC084FC).withValues(alpha: 0.45),
      ),
      _Blob(
        center: Offset(
          size.width * (0.52 + 0.20 * math.sin(twoPi * (t + 0.66))),
          size.height * (0.85 + 0.15 * math.cos(twoPi * (t + 0.66))),
        ),
        radius: size.width * 0.55,
        color: dark
            ? const Color(0xFF06B6D4).withValues(alpha: 0.28)
            : const Color(0xFF38BDF8).withValues(alpha: 0.40),
      ),
    ];

    for (final b in blobs) {
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [b.color, b.color.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: b.center, radius: b.radius))
        ..blendMode = BlendMode.plus;
      canvas.drawCircle(b.center, b.radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _AuroraMeshPainter old) =>
      old.t != t || old.dark != dark;
}

class _Blob {
  final Offset center;
  final double radius;
  final Color color;
  _Blob({required this.center, required this.radius, required this.color});
}

// Sparkle particles drifting upward, fading in/out.
class _SparklePainter extends CustomPainter {
  final double t;
  _SparklePainter({required this.t});

  static final List<_Sparkle> _seeds = List.generate(28, (i) {
    final r = math.Random(i * 7 + 11);
    return _Sparkle(
      x: r.nextDouble(),
      yOffset: r.nextDouble(),
      speed: 0.20 + r.nextDouble() * 0.55,
      size: 0.6 + r.nextDouble() * 1.8,
      phase: r.nextDouble(),
    );
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white;
    for (final s in _seeds) {
      final progress = ((t * s.speed) + s.phase) % 1.0;
      final y = (1 - progress) * size.height;
      final x =
          s.x * size.width + math.sin((progress + s.phase) * math.pi * 2) * 8;
      final twinkle = 0.5 + 0.5 * math.sin((t + s.phase) * math.pi * 4);
      final alpha = (twinkle * (1 - progress) * 0.7).clamp(0.0, 1.0);
      paint.color = Colors.white.withValues(alpha: alpha);
      canvas.drawCircle(Offset(x, y + s.yOffset * 6), s.size, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SparklePainter old) => old.t != t;
}

class _Sparkle {
  final double x, yOffset, speed, size, phase;
  _Sparkle({
    required this.x,
    required this.yOffset,
    required this.speed,
    required this.size,
    required this.phase,
  });
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
                    color: const Color(0xFF4ADE80)
                        .withValues(alpha: opacity * 0.6),
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
    final color = isFlat ? theme.muted : (isUp ? theme.green : theme.red);
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
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
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
// PREDICTIVE RISK HEATMAP — replaces static type bars with a 24h probability
// curve per alert type. Each row renders animated wave bars driven by the
// worker's Poisson model on the last 30 days of history.
// ═══════════════════════════════════════════════════════════════════════════

class _PredictiveRiskHeatmap extends StatelessWidget {
  final Map<String, Map<String, int>> stats;
  final PredictiveModel? model;
  final String? activeFilter;
  final void Function(String) onTap;
  const _PredictiveRiskHeatmap({
    required this.stats,
    required this.model,
    required this.activeFilter,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: theme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.border),
        boxShadow: [
          BoxShadow(
            color: theme.purple.withValues(alpha: context.isDark ? 0.06 : 0.03),
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
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [theme.purple, theme.blue],
                  ),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(Icons.show_chart_rounded,
                    size: 14, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Predictive Risk · Next 24h',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: theme.text,
                      ),
                    ),
                    Text(
                      model == null
                          ? 'Awaiting first model from edge inference…'
                          : 'Probability per 2h window · tap row to filter history',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.muted,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: theme.purple.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bolt_rounded, size: 11, color: theme.purple),
                    const SizedBox(width: 3),
                    Text(
                      'ML',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: theme.purple,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...stats.entries.map((e) {
            final type = e.key;
            final past = e.value['total']!;
            final solved = e.value['solved']!;
            final curve = model?.curves[type];
            return _RiskCurveRow(
              type: type,
              past: past,
              solved: solved,
              curve: curve,
              isActive: activeFilter == type,
              onTap: () => onTap(type),
            );
          }),
        ],
      ),
    );
  }
}

class _RiskCurveRow extends StatefulWidget {
  final String type;
  final int past;
  final int solved;
  final RiskCurve? curve;
  final bool isActive;
  final VoidCallback onTap;
  const _RiskCurveRow({
    required this.type,
    required this.past,
    required this.solved,
    required this.curve,
    required this.isActive,
    required this.onTap,
  });

  @override
  State<_RiskCurveRow> createState() => _RiskCurveRowState();
}

class _RiskCurveRowState extends State<_RiskCurveRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _waveCtrl;

  @override
  void initState() {
    super.initState();
    _waveCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _waveCtrl.dispose();
    super.dispose();
  }

  String _riskLabel(double p) {
    if (p >= 0.7) return 'High';
    if (p >= 0.4) return 'Elevated';
    if (p >= 0.15) return 'Watch';
    return 'Low';
  }

  Color _riskColor(BuildContext ctx, double p) {
    final t = ctx.appTheme;
    if (p >= 0.7) return t.red;
    if (p >= 0.4) return t.orange;
    if (p >= 0.15) return t.yellow;
    return t.green;
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final color = _typeColor(widget.type);
    final curve = widget.curve;
    final p = curve?.total24h ?? 0;
    final riskColor = _riskColor(context, p);

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
        decoration: BoxDecoration(
          color: widget.isActive
              ? color.withValues(alpha: 0.08)
              : theme.scaffold.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color:
                widget.isActive ? color.withValues(alpha: 0.55) : theme.border,
          ),
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
                    gradient: LinearGradient(
                      colors: [
                        color.withValues(alpha: 0.85),
                        color.withValues(alpha: 0.55),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(_typeIcon(widget.type),
                      size: 15, color: Colors.white),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _typeLabel(widget.type),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: theme.text,
                        ),
                      ),
                      Text(
                        curve == null
                            ? '${widget.past} past · awaiting forecast'
                            : '${widget.past} past · ${widget.solved} resolved · peak @ ${curve.peakHour.toString().padLeft(2, '0')}:00',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: theme.muted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: riskColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(
                      color: riskColor.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    '${_riskLabel(p)} · ${(p * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: riskColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 38,
              child: AnimatedBuilder(
                animation: _waveCtrl,
                builder: (_, __) => CustomPaint(
                  painter: _WaveBarsPainter(
                    buckets: curve?.buckets ?? const [],
                    color: color,
                    waveT: _waveCtrl.value,
                    dark: context.isDark,
                  ),
                  size: Size.infinite,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  'now',
                  style: TextStyle(fontSize: 9.5, color: theme.muted),
                ),
                const Spacer(),
                Text(
                  '+12h',
                  style: TextStyle(fontSize: 9.5, color: theme.muted),
                ),
                const Spacer(),
                Text(
                  '+24h',
                  style: TextStyle(fontSize: 9.5, color: theme.muted),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WaveBarsPainter extends CustomPainter {
  final List<RiskBucket> buckets;
  final Color color;
  final double waveT;
  final bool dark;
  _WaveBarsPainter({
    required this.buckets,
    required this.color,
    required this.waveT,
    required this.dark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (buckets.isEmpty) {
      // Placeholder shimmer
      final p = Paint()
        ..color = color.withValues(alpha: 0.12)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(6)),
        p,
      );
      return;
    }

    final n = buckets.length;
    final gap = 3.0;
    final barW = (size.width - gap * (n - 1)) / n;
    final maxProb = buckets.map((b) => b.probability).fold<double>(0, math.max);
    if (maxProb <= 0.01) {
      final p = Paint()
        ..color = color.withValues(alpha: 0.12)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(6)),
        p,
      );
      return;
    }
    final scale = maxProb <= 0 ? 0.0 : 1.0;

    for (var i = 0; i < n; i++) {
      final b = buckets[i];
      final x = i * (barW + gap);
      // Wave breathing modulation, normalized so the peak still reaches 1.
      final mod = 0.85 + 0.15 * math.sin(waveT * math.pi * 2 + i * 0.45);
      final h = maxProb == 0
          ? 0.0
          : (b.probability / maxProb) * size.height * mod * scale;

      final rect = Rect.fromLTWH(x, size.height - h, barW, h);
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4));

      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            color.withValues(alpha: 0.95),
            color.withValues(alpha: 0.45),
          ],
        ).createShader(rect);
      canvas.drawRRect(rrect, paint);

      // Soft top glow on the tallest bar
      if (b.probability == maxProb && h > 4) {
        final glow = Paint()
          ..color = color.withValues(alpha: dark ? 0.45 : 0.30)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
        canvas.drawCircle(
          Offset(rect.center.dx, rect.top),
          barW * 0.55,
          glow,
        );
      }

      // Faded baseline bar to anchor empty buckets
      final base = Paint()
        ..color = color.withValues(alpha: 0.08)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, size.height - 2, barW, 2),
          const Radius.circular(2),
        ),
        base,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveBarsPainter old) =>
      old.waveT != waveT ||
      old.buckets != buckets ||
      old.color != color ||
      old.dark != dark;
}

// ═══════════════════════════════════════════════════════════════════════════
// PREDICTIVE FAILURE CARD — top N machines/types most likely to alert next
// ═══════════════════════════════════════════════════════════════════════════

class _PredictiveFailureCard extends StatefulWidget {
  final PredictiveModel? model;
  final String Function(String) describeType;
  const _PredictiveFailureCard({
    required this.model,
    required this.describeType,
  });

  @override
  State<_PredictiveFailureCard> createState() => _PredictiveFailureCardState();
}

class _PredictiveFailureCardState extends State<_PredictiveFailureCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer;

  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final isDark = context.isDark;
    final preds = widget.model?.predictions ?? const <PredictedFailure>[];
    final top = preds.take(5).toList();

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  const Color(0xFF1B1230),
                  const Color(0xFF0F1B30),
                ]
              : [
                  const Color(0xFFF5F0FF),
                  const Color(0xFFEFF6FF),
                ],
        ),
        border: Border.all(color: theme.purple.withValues(alpha: 0.32)),
        boxShadow: [
          BoxShadow(
            color: theme.purple.withValues(alpha: isDark ? 0.18 : 0.10),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AnimatedBuilder(
                  animation: _shimmer,
                  builder: (_, __) {
                    final t = _shimmer.value;
                    return Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        gradient: SweepGradient(
                          startAngle: 0,
                          endAngle: math.pi * 2,
                          transform: GradientRotation(t * math.pi * 2),
                          colors: [
                            theme.purple,
                            theme.blue,
                            theme.purple,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(11),
                        boxShadow: [
                          BoxShadow(
                            color: theme.purple.withValues(alpha: 0.35),
                            blurRadius: 14,
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(Icons.psychology_alt_rounded,
                            size: 19, color: Colors.white),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Predictive Failure Alerts',
                            style: TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w800,
                              color: theme.text,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: theme.purple.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              'BETA',
                              style: TextStyle(
                                fontSize: 8.5,
                                fontWeight: FontWeight.w900,
                                color: theme.purple,
                                letterSpacing: 1.1,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        widget.model == null
                            ? 'Edge model warming up — first inference within 60s.'
                            : 'Top probable next failures · trained on last ${widget.model!.predictions.isEmpty ? 30 : 30}d',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: theme.muted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.model != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.card,
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: theme.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: theme.green,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: theme.green.withValues(alpha: 0.6),
                                blurRadius: 5,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'LIVE',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: theme.text,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            if (top.isEmpty)
              Container(
                padding: const EdgeInsets.all(18),
                alignment: Alignment.center,
                child: Column(
                  children: [
                    Icon(Icons.science_outlined, size: 32, color: theme.purple),
                    const SizedBox(height: 8),
                    Text(
                      'Not enough history yet',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: theme.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'The model needs a few days of alerts to learn patterns.',
                      style: TextStyle(fontSize: 11, color: theme.muted),
                    ),
                  ],
                ),
              )
            else
              ...top.asMap().entries.map((e) => _PredictedFailureRow(
                    rank: e.key + 1,
                    failure: e.value,
                    describeType: widget.describeType,
                  )),
          ],
        ),
      ),
    );
  }
}

class _PredictedFailureRow extends StatelessWidget {
  final int rank;
  final PredictedFailure failure;
  final String Function(String) describeType;
  const _PredictedFailureRow({
    required this.rank,
    required this.failure,
    required this.describeType,
  });

  String _eta() {
    final h = failure.etaHours;
    if (h == null) return 'No ETA yet';
    if (h <= 0) return 'Overdue · expected';
    if (h < 1) return 'Within ${(h * 60).round()} min';
    if (h < 24) return 'In ~${h.toStringAsFixed(1)}h';
    final d = (h / 24).round();
    return 'In ~${d}d';
  }

  String _lastSeen() {
    final t = failure.lastTs;
    if (t == null) return 'never';
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final tColor = _typeColor(failure.type);
    final conf = failure.confidence.clamp(0, 100).toDouble();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: theme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [theme.purple, theme.blue],
                  ),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Center(
                  child: Text(
                    '$rank',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: tColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_typeIcon(failure.type), size: 11, color: tColor),
                    const SizedBox(width: 4),
                    Text(
                      describeType(failure.type),
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: tColor,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                '${conf.toInt()}%',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: theme.purple,
                ),
              ),
              const SizedBox(width: 2),
              Text(
                'conf.',
                style: TextStyle(
                  fontSize: 9,
                  color: theme.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${failure.usine.isNotEmpty ? failure.usine : failure.factoryId} · Line ${failure.convoyeur} · WS ${failure.poste}',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: theme.text,
            ),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: SizedBox(
              height: 6,
              child: Stack(
                children: [
                  Container(color: theme.border),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: conf / 100),
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.easeOutCubic,
                    builder: (_, w, __) => FractionallySizedBox(
                      widthFactor: w.clamp(0.0, 1.0),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [theme.purple, theme.blue],
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
              Icon(Icons.history_toggle_off_rounded,
                  size: 11, color: theme.muted),
              const SizedBox(width: 3),
              Text(
                'Last ${_lastSeen()}',
                style: TextStyle(fontSize: 10.5, color: theme.muted),
              ),
              const SizedBox(width: 10),
              Icon(Icons.timer_outlined, size: 11, color: theme.orange),
              const SizedBox(width: 3),
              Text(
                _eta(),
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: theme.orange,
                ),
              ),
              const Spacer(),
              if (failure.criticalCount > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.red.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    '${failure.criticalCount} critical',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: theme.red,
                    ),
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
// CRITICAL ALERT ROW WITH AI ONE-TAP RESOLUTION SUGGESTION
// Lazily fetches the suggestion from the worker, lets PM assign with 1 tap.
// ═══════════════════════════════════════════════════════════════════════════

class _CriticalAlertRowAI extends StatefulWidget {
  final AlertModel alert;
  final String Function(AlertModel) describe;
  final VoidCallback onAlertTap;
  const _CriticalAlertRowAI({
    required this.alert,
    required this.describe,
    required this.onAlertTap,
  });

  @override
  State<_CriticalAlertRowAI> createState() => _CriticalAlertRowAIState();
}

class _CriticalAlertRowAIState extends State<_CriticalAlertRowAI>
    with SingleTickerProviderStateMixin {
  AssigneeSuggestion? _suggestion;
  bool _loading = false;
  bool _assigning = false;
  String? _assignError;
  bool _assignedDone = false;
  late final AnimationController _glowCtrl;

  @override
  void initState() {
    super.initState();
    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _loadSuggestion();
  }

  @override
  void dispose() {
    _glowCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSuggestion() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final s =
        await PredictiveIntelService.instance.suggestAssignee(widget.alert.id);
    if (!mounted) return;
    setState(() {
      _suggestion = s;
      _loading = false;
    });
  }

  Future<void> _assign() async {
    final s = _suggestion;
    if (s == null || s.bestUid == null || _assigning || _assignedDone) return;
    setState(() {
      _assigning = true;
      _assignError = null;
    });
    try {
      await AlertService().takeAlert(
        widget.alert.id,
        s.bestUid!,
        s.bestName ?? 'AI assignment',
      );
      if (!mounted) return;
      setState(() {
        _assigning = false;
        _assignedDone = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _assigning = false;
        _assignError = 'Failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final alert = widget.alert;
    final elapsedMin = DateTime.now().difference(alert.timestamp).inMinutes;
    final elapsedText = elapsedMin < 60
        ? '${elapsedMin}m'
        : '${elapsedMin ~/ 60}h ${elapsedMin % 60}m';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: theme.card,
        border: Border.all(color: theme.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: widget.onAlertTap,
            behavior: HitTestBehavior.opaque,
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
                        '${_typeLabel(alert.type)} — ${widget.describe(alert)}',
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
                        style: TextStyle(fontSize: 11, color: theme.muted),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.red.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(99),
                    border:
                        Border.all(color: theme.red.withValues(alpha: 0.35)),
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
              ],
            ),
          ),
          const SizedBox(height: 9),
          _buildSuggestionStrip(theme),
        ],
      ),
    );
  }

  Widget _buildSuggestionStrip(AppTheme theme) {
    if (_loading) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: theme.purple.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: theme.purple.withValues(alpha: 0.18)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.6,
                valueColor: AlwaysStoppedAnimation(theme.purple),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'AI is matching the best supervisor…',
              style: TextStyle(
                fontSize: 11.5,
                color: theme.purple,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    if (_assignedDone) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: theme.green.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: theme.green.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle_rounded, size: 14, color: theme.green),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Assigned to ${_suggestion?.bestName ?? 'supervisor'} — supervisor notified.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: theme.green,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final s = _suggestion;
    if (s == null || s.bestUid == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: theme.scaffold.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: theme.border),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 13, color: theme.muted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'No eligible supervisor right now.',
                style: TextStyle(fontSize: 11, color: theme.muted),
              ),
            ),
            TextButton(
              onPressed: _loadSuggestion,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                minimumSize: const Size(0, 28),
              ),
              child: Text(
                'Retry',
                style: TextStyle(
                  fontSize: 11,
                  color: theme.navy,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return AnimatedBuilder(
      animation: _glowCtrl,
      builder: (_, __) {
        final glow = 0.18 + 0.12 * _glowCtrl.value;
        return Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                theme.purple.withValues(alpha: 0.15),
                theme.blue.withValues(alpha: 0.10),
              ],
            ),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: theme.purple.withValues(alpha: 0.30)),
            boxShadow: [
              BoxShadow(
                color: theme.purple.withValues(alpha: glow),
                blurRadius: 12,
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(Icons.auto_awesome_rounded, size: 14, color: theme.purple),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(
                          text: 'AI suggests: ',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: theme.muted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        TextSpan(
                          text: s.bestName ?? 'supervisor',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: theme.text,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        TextSpan(
                          text: '  ·  ${s.confidencePct}% match',
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.purple,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ]),
                    ),
                    if (s.reasons.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Text(
                          s.reasons.take(2).join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: theme.muted,
                          ),
                        ),
                      ),
                    if (_assignError != null)
                      Text(
                        _assignError!,
                        style: TextStyle(fontSize: 10.5, color: theme.red),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              ElevatedButton(
                onPressed: _assigning ? null : _assign,
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.purple,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                child: _assigning
                    ? const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.6,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      )
                    : const Text('Assign'),
              ),
            ],
          ),
        );
      },
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

  Widget _alertTile(BuildContext context, AlertModel alert) {
    return _CriticalAlertRowAI(
      alert: alert,
      describe: describe,
      onAlertTap: () => onAlertTap(alert),
    );
  }

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
          ...alerts.map((a) => _alertTile(context, a)),
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
        _ExportBtn(
            label: 'CSV', icon: Icons.table_chart_outlined, onTap: onCsv),
        const SizedBox(width: 8),
        _ExportBtn(
            label: 'Excel', icon: Icons.grid_on_outlined, onTap: onExcel),
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
                        child: Text(_typeLabel(t),
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
          .add(_ActiveChip(label: _typeLabel(filterType), color: theme.orange));
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
