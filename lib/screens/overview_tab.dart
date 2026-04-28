part of 'admin_dashboard_screen.dart';

// OVERVIEW TAB (full implementation – already correct, keep as is)
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
    final hierarchyService = HierarchyService();
    hierarchyService.getFactories().listen((factories) {
      if (mounted) {
        setState(() {
          _factories = factories;
        });
      }
    });
  }

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

  List<AlertModel> get _criticalUnclaimedAlerts {
    return widget.allAlerts
        .where((a) => a.isCritical && a.status == 'disponible')
        .toList();
  }

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
      if (_historyFilter == filter) {
        _historyFilter = null;
      } else {
        _historyFilter = filter;
      }
    });
  }

  Map<String, Map<String, int>> _typeStats() {
    final keys = [
      'qualite',
      'maintenance',
      'defaut_produit',
      'manque_ressource'
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

  // Use hierarchy-based convoyeurs and postes
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
        return 'Resource shortage - missing raw materials';
      default:
        return 'Alert detected';
    }
  }

  int get _criticalInProgressCount {
    return widget.allAlerts
        .where((a) => a.status == 'en_cours' && a.isCritical)
        .length;
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

  @override
  Widget build(BuildContext context) {
    final ts = _typeStats();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Alert Dashboard',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: _text),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Overview and detailed analysis of alerts',
                      style: TextStyle(fontSize: 13, color: _muted),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: context.appTheme.card,
                  border: Border.all(color: context.appTheme.border),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.filter_alt_outlined,
                        size: 13, color: _navy),
                    const SizedBox(width: 4),
                    Text(
                      widget.timeRangeLabel,
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _navy),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Active filter banner
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
          const SizedBox(height: 20),

          // 4 stat cards
          Row(
            children: [
              Expanded(
                child: _UnclaimedStatCard(
                  unclaimedCount: widget.pending,
                  criticalCount: _criticalUnclaimedCount,
                  isActive: _historyFilter == 'pending',
                  onTap: () => _setHistoryFilter('pending'),
                  onCriticalTap: () => _setHistoryFilter('critical'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ProgressStatCard(
                  inProgressCount: widget.inProgress,
                  criticalCount: _criticalInProgressCount,
                  isActive: _historyFilter == 'en_cours',
                  onTap: () => _setHistoryFilter('en_cours'),
                  onCriticalTap: () => _setHistoryFilter('critical'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ClickableStatCard(
                  label: 'Fixed Alerts',
                  value: widget.solved,
                  color: _green,
                  icon: Icons.check_circle_outline,
                  iconBg: _greenLt,
                  isActive: _historyFilter == 'validated',
                  onTap: () => _setHistoryFilter('validated'),
                  showHistoryHint: true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ClickableStatCard(
                  label: 'Total Alerts',
                  value: widget.total,
                  color: _navy,
                  icon: Icons.notifications_outlined,
                  iconBg: _navyLt,
                  isActive: _historyFilter == 'total',
                  onTap: () => _setHistoryFilter('total'),
                  showHistoryHint: true,
                ),
              ),
            ],
          ),

          // Critical unclaimed alerts
          if (_criticalUnclaimedCount > 0) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                border: Border.all(color: Colors.red.shade300),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          color: Colors.red, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Critical Unclaimed Alerts ($_criticalUnclaimedCount)',
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.red),
                      ),
                      const Spacer(),
                      Text(
                        'These alerts have been waiting for more than 10 minutes',
                        style:
                            TextStyle(fontSize: 11, color: Colors.red.shade700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ..._criticalUnclaimedAlerts.map((alert) {
                    final elapsedMinutes =
                        DateTime.now().difference(alert.timestamp).inMinutes;
                    final elapsedText = elapsedMinutes < 60
                        ? '$elapsedMinutes min'
                        : '${elapsedMinutes ~/ 60}h ${elapsedMinutes % 60}m';
                    final displayDescription =
                        _getAlertDisplayDescription(alert);
                    return GestureDetector(
                      onTap: () => _setHistoryFilter(alert.type),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: context.appTheme.card,
                          border: Border.all(color: context.appTheme.border),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: _typeColor(alert.type),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${_typeLabel(alert.type)} — $displayDescription',
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: _text),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${alert.usine} - Line ${alert.convoyeur} - WS ${alert.poste}',
                                    style: const TextStyle(
                                        fontSize: 11, color: _muted),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.red.shade200),
                              ),
                              child: Text(
                                elapsedText,
                                style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.red),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.chevron_right,
                                color: _muted, size: 18),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // 4 type breakdown cards
          Row(
            children: [
              Expanded(
                child: _ClickableTypeCard(
                  type: 'qualite',
                  total: ts['qualite']!['total']!,
                  solved: ts['qualite']!['solved']!,
                  pending: ts['qualite']!['pending']!,
                  isActive: _historyFilter == 'qualite',
                  onTap: () => _setHistoryFilter('qualite'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ClickableTypeCard(
                  type: 'maintenance',
                  total: ts['maintenance']!['total']!,
                  solved: ts['maintenance']!['solved']!,
                  pending: ts['maintenance']!['pending']!,
                  isActive: _historyFilter == 'maintenance',
                  onTap: () => _setHistoryFilter('maintenance'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ClickableTypeCard(
                  type: 'defaut_produit',
                  total: ts['defaut_produit']!['total']!,
                  solved: ts['defaut_produit']!['solved']!,
                  pending: ts['defaut_produit']!['pending']!,
                  isActive: _historyFilter == 'defaut_produit',
                  onTap: () => _setHistoryFilter('defaut_produit'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ClickableTypeCard(
                  type: 'manque_ressource',
                  total: ts['manque_ressource']!['total']!,
                  solved: ts['manque_ressource']!['solved']!,
                  pending: ts['manque_ressource']!['pending']!,
                  isActive: _historyFilter == 'manque_ressource',
                  onTap: () => _setHistoryFilter('manque_ressource'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Alert history section
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Row(
                  children: [
                    const Icon(Icons.calendar_today,
                        size: 16, color: _navy),
                    const SizedBox(width: 8),
                    Text(
                      'Alert History (${_displayedAlerts.length})',
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: _text),
                    ),
                  ],
                ),
                const SizedBox(width: 16),
                _ExportBtn(
                  label: 'Export CSV',
                  icon: Icons.table_chart,
                  onTap: () {
                    _exportFilteredAlerts(_displayedAlerts);
                  },
                ),
                const SizedBox(width: 8),
                _ExportBtn(
                  label: 'Export Excel',
                  icon: Icons.grid_on,
                  onTap: () {
                    _exportFilteredAlertsExcel(_displayedAlerts);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Full alert list with filters',
            style: TextStyle(fontSize: 12, color: _muted),
          ),
          const SizedBox(height: 14),

          // Filter row
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.appTheme.card,
              border: Border.all(color: context.appTheme.border),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.filter_list, size: 16, color: _navy),
                    SizedBox(width: 6),
                    Text(
                      'Filter History',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _text),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _FilterDropdown(
                        label: 'Plant',
                        value: widget.selectedUsine,
                        items: _usines()
                            .map((v) => DropdownMenuItem(
                                  value: v,
                                  child: Text(
                                    v == 'all' ? 'All Plants' : v,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ))
                            .toList(),
                        onChanged: widget.onUsineChange,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _FilterDropdown(
                        label: 'Conveyor',
                        value: widget.filterConvoyeur,
                        items: _convoyeursForFilter()
                            .map((v) => DropdownMenuItem(
                                  value: v,
                                  child: Text(
                                    v == 'all' ? 'All Conveyors' : 'Conv. $v',
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ))
                            .toList(),
                        onChanged: widget.onConvoyeurChange,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _FilterDropdown(
                        label: 'Post',
                        value: widget.filterPoste,
                        items: _postesForFilter()
                            .map((v) => DropdownMenuItem(
                                  value: v,
                                  child: Text(
                                    v == 'all' ? 'All Posts' : 'Post $v',
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ))
                            .toList(),
                        onChanged: widget.onPosteChange,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _FilterDropdown(
                        label: 'Alert Type',
                        value: widget.filterType,
                        items: [
                          const DropdownMenuItem(
                            value: 'all',
                            child: Text('All Types',
                                style: TextStyle(fontSize: 13)),
                          ),
                          ...[
                            'qualite',
                            'maintenance',
                            'defaut_produit',
                            'manque_ressource'
                          ].map((t) => DropdownMenuItem(
                                value: t,
                                child: Text(
                                  _typeLabel(t),
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ))
                        ],
                        onChanged: widget.onTypeChange,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _FilterDropdown(
                        label: 'Status',
                        value: widget.filterStatus,
                        items: const [
                          DropdownMenuItem(
                            value: 'all',
                            child: Text('All Statuses',
                                style: TextStyle(fontSize: 13)),
                          ),
                          DropdownMenuItem(
                            value: 'disponible',
                            child: Text('Available',
                                style: TextStyle(fontSize: 13)),
                          ),
                          DropdownMenuItem(
                            value: 'en_cours',
                            child: Text('Claimed Alerts',
                                style: TextStyle(fontSize: 13)),
                          ),
                          DropdownMenuItem(
                            value: 'validee',
                            child: Text('Fixed Alerts',
                                style: TextStyle(fontSize: 13)),
                          ),
                        ],
                        onChanged: widget.onStatusChange,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _FilterDropdown(
                        label: 'Time Range',
                        value: widget.timeRange,
                        items: const [
                          DropdownMenuItem(
                              value: 'all',
                              child: Text('All Time',
                                  style: TextStyle(fontSize: 13))),
                          DropdownMenuItem(
                              value: 'today',
                              child: Text('Today',
                                  style: TextStyle(fontSize: 13))),
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
                              child: Text('This Year',
                                  style: TextStyle(fontSize: 13))),
                          DropdownMenuItem(
                              value: 'custom',
                              child: Text('Custom',
                                  style: TextStyle(fontSize: 13))),
                        ],
                        onChanged: widget.onTimeRangeChange,
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      onPressed: () {
                        widget.onReset();
                        setState(() => _historyFilter = null);
                      },
                      icon: const Icon(Icons.refresh, size: 15),
                      label: const Text('Reset',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _navy,
                        side: const BorderSide(color: _border),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Alert list
          if (_displayedAlerts.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 40),
              alignment: Alignment.center,
              child: Column(
                children: const [
                  Icon(Icons.check_circle_outline, size: 48, color: _green),
                  SizedBox(height: 12),
                  Text(
                    'No alerts match your filters',
                    style: TextStyle(fontSize: 15, color: _muted),
                  ),
                ],
              ),
            )
          else
            ..._displayedAlerts.map((a) => _AlertHistoryRow(alert: a)),
        ],
      ),
    );
  }
}

class _ProgressStatCard extends StatelessWidget {
  final int inProgressCount;
  final int criticalCount;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onCriticalTap;

  const _ProgressStatCard({
    required this.inProgressCount,
    required this.criticalCount,
    required this.isActive,
    required this.onTap,
    required this.onCriticalTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: isActive ? _blue.withValues(alpha: 0.1) : context.appTheme.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive ? _blue : _border,
            width: isActive ? 2 : 1,
          ),
          boxShadow: const [
            BoxShadow(
                color: Color(0x06000000), blurRadius: 4, offset: Offset(0, 2))
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Claimed Alerts',
                      style: TextStyle(
                          fontSize: 12,
                          color: _muted,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 6),
                  Text('$inProgressCount',
                      style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          color: _blue,
                          height: 1)),
                  const SizedBox(height: 4),
                  if (criticalCount > 0)
                    GestureDetector(
                      onTap: onCriticalTap,
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded,
                              size: 12, color: Colors.red),
                          const SizedBox(width: 4),
                          Text('$criticalCount Critical',
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.red,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  if (isActive)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text('Click to hide history',
                          style: TextStyle(
                              fontSize: 9,
                              color: _muted,
                              fontStyle: FontStyle.italic)),
                    ),
                ],
              ),
            ),
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: _blueLt, shape: BoxShape.circle),
              child: const Icon(Icons.timer, color: _blue, size: 22),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnclaimedStatCard extends StatelessWidget {
  final int unclaimedCount;
  final int criticalCount;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onCriticalTap;

  const _UnclaimedStatCard({
    required this.unclaimedCount,
    required this.criticalCount,
    required this.isActive,
    required this.onTap,
    required this.onCriticalTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: isActive ? _orange.withValues(alpha: 0.1) : context.appTheme.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive ? _orange : _border,
            width: isActive ? 2 : 1,
          ),
          boxShadow: const [
            BoxShadow(
                color: Color(0x06000000), blurRadius: 4, offset: Offset(0, 2))
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Received Alerts',
                      style: TextStyle(
                          fontSize: 12,
                          color: _muted,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 6),
                  Text('$unclaimedCount',
                      style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          color: _orange,
                          height: 1)),
                  const SizedBox(height: 4),
                  if (criticalCount > 0)
                    GestureDetector(
                      onTap: onCriticalTap,
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded,
                              size: 12, color: Colors.red),
                          const SizedBox(width: 4),
                          Text('$criticalCount Critical',
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.red,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  if (isActive)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text('Click to hide history',
                          style: TextStyle(
                              fontSize: 9,
                              color: _muted,
                              fontStyle: FontStyle.italic)),
                    ),
                ],
              ),
            ),
            Container(
              width: 46,
              height: 46,
              decoration:
                  BoxDecoration(color: _orangeLt, shape: BoxShape.circle),
              child: const Icon(Icons.notifications_outlined,
                  color: _orange, size: 22),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Helper widgets ──────────────────────────────────────────────────────────

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
    if (!_hasNonDefaultFilters) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFEFF6FF),
          border: Border.all(color: const Color(0xFFBFDBFE)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle_outline, size: 15, color: _blue),
            const SizedBox(width: 6),
            const Text(
              'Showing all alerts — no filters active',
              style: TextStyle(fontSize: 12, color: _blue, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      );
    }

    // Non-default filters active — show amber warning
    final chips = <Widget>[];
    if (timeRange != 'all') {
      chips.add(_ActiveChip(label: timeRangeLabel, color: _orange));
    }
    if (selectedUsine != 'all') {
      chips.add(_ActiveChip(label: selectedUsine, color: _orange, onRemove: onRemoveUsine));
    }
    if (filterConvoyeur != 'all') {
      chips.add(_ActiveChip(label: 'Line $filterConvoyeur', color: _orange));
    }
    if (filterPoste != 'all') {
      chips.add(_ActiveChip(label: 'Post $filterPoste', color: _orange));
    }
    if (filterType != 'all') {
      chips.add(_ActiveChip(label: filterType, color: _orange));
    }
    if (filterStatus != 'all') {
      chips.add(_ActiveChip(label: filterStatus, color: _orange));
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _orangeLt,
        border: Border.all(color: _orange.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, size: 15, color: _orange),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Filters active — some alerts may be hidden from this view',
                  style: TextStyle(fontSize: 12, color: _orange, fontWeight: FontWeight.w600),
                ),
              ),
              GestureDetector(
                onTap: onReset,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _orange,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Reset all',
                    style: TextStyle(fontSize: 11, color: _white, fontWeight: FontWeight.w700),
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
                  fontSize: 11, color: _white, fontWeight: FontWeight.w600)),
          if (onRemove != null) ...[
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onRemove,
              child: const Icon(Icons.close, size: 12, color: _white),
            ),
          ],
        ]),
      );
}

class _ExportBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _ExportBtn({required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
            foregroundColor: _text,
            side: const BorderSide(color: _border),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
        icon: Icon(icon, size: 14),
        label: Text(label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      );
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
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: _muted,
                  letterSpacing: 1)),
          const SizedBox(height: 5),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
                color: context.appTheme.scaffold,
                border: Border.all(color: context.appTheme.border),
                borderRadius: BorderRadius.circular(8)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: value,
                isExpanded: true,
                style: TextStyle(fontSize: 13, color: context.appTheme.text),
                dropdownColor: context.appTheme.card,
                items: items,
                onChanged: (v) => onChanged(v!),
              ),
            ),
          ),
        ],
      );
}

class _AlertHistoryRow extends StatelessWidget {
  final AlertModel alert;
  const _AlertHistoryRow({required this.alert});

  @override
  Widget build(BuildContext context) {
    final sc = switch (alert.status) {
      'validee' => _green,
      'en_cours' => _blue,
      _ => _orange,
    };
    final sl = switch (alert.status) {
      'validee' => 'Fixed Alerts',
      'en_cours' => 'Claimed Alerts',
      _ => 'Available',
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: context.appTheme.card,
          border: Border.all(color: context.appTheme.border),
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [
            BoxShadow(
                color: Color(0x05000000), blurRadius: 3, offset: Offset(0, 1))
          ]),
      child: Row(children: [
        Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
                color: _typeColor(alert.type), shape: BoxShape.circle)),
        const SizedBox(width: 10),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${_typeLabel(alert.type)} — ${alert.description}',
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: context.appTheme.text),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(
              '${alert.usine}  ·  Line ${alert.convoyeur}'
              '  ·  Post ${alert.poste}  ·  ${_fmtTs(alert.timestamp)}',
              style: const TextStyle(
                  fontFamily: 'monospace', fontSize: 10, color: _muted)),
          if (alert.superviseurName != null)
            Text('Assigned: ${alert.superviseurName}',
                style: const TextStyle(fontSize: 11, color: _blue)),
          if (alert.criticalNote != null && alert.criticalNote!.isNotEmpty)
            Text('Critical note: ${alert.criticalNote}',
                style: const TextStyle(fontSize: 11, color: Colors.red)),
        ])),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
              color: sc.withValues(alpha: .1),
              border: Border.all(color: sc),
              borderRadius: BorderRadius.circular(99)),
          child: Text(sl,
              style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w700, color: sc)),
        ),
      ]),
    );
  }
}

class _ClickableStatCard extends StatelessWidget {
  final String label;
  final int value;
  final Color color, iconBg;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;
  final bool showHistoryHint;

  const _ClickableStatCard({
    required this.label,
    required this.value,
    required this.color,
    required this.iconBg,
    required this.icon,
    required this.isActive,
    required this.onTap,
    this.showHistoryHint = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
            color: isActive ? color.withValues(alpha: 0.1) : context.appTheme.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: isActive ? color : _border, width: isActive ? 2 : 1),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x06000000), blurRadius: 4, offset: Offset(0, 2))
            ]),
        child: Row(children: [
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 12,
                        color: _muted,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 6),
                Text('$value',
                    style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        color: color,
                        height: 1)),
                if (showHistoryHint)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      isActive
                          ? 'Click to hide history'
                          : 'Click to show history',
                      style: const TextStyle(
                          fontSize: 9,
                          color: _muted,
                          fontStyle: FontStyle.italic),
                    ),
                  ),
              ])),
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 22),
          ),
        ]),
      ),
    );
  }
}

class _ClickableTypeCard extends StatelessWidget {
  final String type;
  final int total, solved, pending;
  final bool isActive;
  final VoidCallback onTap;

  const _ClickableTypeCard({
    required this.type,
    required this.total,
    required this.solved,
    required this.pending,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = _typeColor(type);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: isActive ? color.withValues(alpha: 0.1) : context.appTheme.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: isActive ? color : _border, width: isActive ? 2 : 1),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x06000000), blurRadius: 4, offset: Offset(0, 2))
            ]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(_typeLabel(type),
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isActive ? color : context.appTheme.text)),
            const Spacer(),
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                  color: color.withValues(alpha: .1), shape: BoxShape.circle),
              child: Icon(_typeIcon(type), color: color, size: 15),
            ),
          ]),
          const SizedBox(height: 8),
          Text('$total',
              style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: isActive ? color : context.appTheme.text,
                  height: 1)),
          const SizedBox(height: 10),
          Row(children: [
            Row(children: [
              const Icon(Icons.check_circle_outline, size: 13, color: _green),
              const SizedBox(width: 3),
              Text('Fixed Alerts',
                  style: const TextStyle(fontSize: 10, color: _muted)),
            ]),
            const Spacer(),
            Text('$solved',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700, color: _green)),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            Row(children: [
              const Icon(Icons.cancel, size: 13, color: _orange),
              const SizedBox(width: 3),
              Text('Pending',
                  style: const TextStyle(fontSize: 10, color: _muted)),
            ]),
            const Spacer(),
            Text('$pending',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700, color: _orange)),
          ]),
          const SizedBox(height: 6),
          Text(
            isActive ? 'Click to hide history' : 'Click to show history',
            style: const TextStyle(
                fontSize: 9, color: _muted, fontStyle: FontStyle.italic),
            textAlign: TextAlign.center,
          ),
        ]),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
