part of 'overview_tab.dart';

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
                                context.tr('History Filters'),
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  color: theme.text,
                                ),
                              ),
                              Text(
                                context.tr(
                                    'Refine alert history only — dashboard stats are unaffected'),
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
                          label: Text(
                            context.tr('Reset'),
                            style: const TextStyle(
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
                      label: context.tr('Plant'),
                      value: _factory,
                      items: widget.factories
                          .map(
                            (v) => DropdownMenuItem(
                              value: v,
                              child: Text(
                                v == 'all' ? context.tr('All Plants') : v,
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
                      label: context.tr('Conveyor'),
                      value: safeConveyeur,
                      items: conveyeurOpts
                          .map(
                            (v) => DropdownMenuItem(
                              value: v,
                              child: Text(
                                v == 'all'
                                    ? context.tr('All Conveyors')
                                    : context.tr('Conv. {n}', {'n': v}),
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
                      label: context.tr('Workstation'),
                      value: safePoste,
                      items: posteOpts
                          .map(
                            (v) => DropdownMenuItem(
                              value: v,
                              child: Text(
                                v == 'all'
                                    ? context.tr('All Workstations')
                                    : context.tr('WS {n}', {'n': v}),
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
                      label: context.tr('Alert Type'),
                      value: _type,
                      items: [
                        DropdownMenuItem(
                          value: 'all',
                          child: Text(
                            context.tr('All Types'),
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        ...allAlertTypeCodes().map(
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
                      label: context.tr('Status'),
                      value: _status,
                      items: [
                        DropdownMenuItem(
                          value: 'all',
                          child: Text(
                            context.tr('All Statuses'),
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'disponible',
                          child: Text(
                            context.tr('Pending'),
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'en_cours',
                          child: Text(
                            context.tr('Claimed'),
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'validee',
                          child: Text(
                            context.tr('Fixed'),
                            style: const TextStyle(fontSize: 13),
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
                          context.tr('CRITICALITY'),
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
                              ('all', context.tr('All')),
                              ('critical', context.tr('Critical Only')),
                              ('normal', context.tr('Normal Only')),
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
                      label: context.tr('Time Range'),
                      value: _timeRange,
                      items: [
                        DropdownMenuItem(
                          value: 'all',
                          child: Text(
                            context.tr('All Time'),
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'today',
                          child: Text(context.tr('Today'),
                              style: const TextStyle(fontSize: 13)),
                        ),
                        DropdownMenuItem(
                          value: 'week',
                          child: Text(
                            context.tr('Last 7 Days'),
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'month',
                          child: Text(
                            context.tr('This Month'),
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'year',
                          child: Text(
                            context.tr('This Year'),
                            style: const TextStyle(fontSize: 13),
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
                      label: Text(
                        context.tr('Apply'),
                        style: const TextStyle(
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
          default:
            // Any configured alert-type code can be used as a quick filter.
            if (allAlertTypeCodes().contains(widget.quickFilter) &&
                a.type != widget.quickFilter) {
              return false;
            }
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
        return ctx.tr('PENDING');
      case 'en_cours':
        return ctx.tr('CLAIMED');
      case 'validated':
        return ctx.tr('FIXED');
      case 'critical':
        return ctx.tr('CRITICAL');
      case 'total':
        return ctx.tr('TOTAL');
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
                        context.tr('Alert History'),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: theme.text,
                        ),
                      ),
                      Text(
                        filtered.length == 1
                            ? context.tr('{n} alert · {scope}',
                                {'n': '${filtered.length}', 'scope': widget.scope})
                            : context.tr('{n} alerts · {scope}',
                                {'n': '${filtered.length}', 'scope': widget.scope}),
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
                      label: Text(
                        context.tr('Filters'),
                        style: const TextStyle(
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
                  context.tr('Show'),
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
                  tooltip: context.tr('Previous page'),
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
                  tooltip: context.tr('Next page'),
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
            context.tr('All clear'),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: theme.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            context.tr('No alerts match your filters.'),
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
                              ctx.tr('Filter alerts'),
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: theme.text,
                              ),
                            ),
                            Text(
                              ctx.tr(
                                  'Refine the history list — every selection scopes the dashboard'),
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
                        label: Text(
                          ctx.tr('Reset'),
                          style: const TextStyle(
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
                    label: context.tr('Plant'),
                    value: selectedUsine,
                    items: usines
                        .map(
                          (v) => DropdownMenuItem(
                            value: v,
                            child: Text(
                              v == 'all' ? context.tr('All Plants') : v,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: onUsine,
                  ),
                  const SizedBox(height: 10),
                  _FilterDropdown(
                    label: context.tr('Conveyor'),
                    value: filterConvoyeur,
                    items: convoyeurs
                        .map(
                          (v) => DropdownMenuItem(
                            value: v,
                            child: Text(
                              v == 'all'
                                  ? context.tr('All Conveyors')
                                  : context.tr('Conv. {n}', {'n': v}),
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: onConvoyeur,
                  ),
                  const SizedBox(height: 10),
                  _FilterDropdown(
                    label: context.tr('Post'),
                    value: filterPoste,
                    items: postes
                        .map(
                          (v) => DropdownMenuItem(
                            value: v,
                            child: Text(
                              v == 'all'
                                  ? context.tr('All Posts')
                                  : context.tr('Post {n}', {'n': v}),
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: onPoste,
                  ),
                  const SizedBox(height: 10),
                  _FilterDropdown(
                    label: context.tr('Alert Type'),
                    value: filterType,
                    items: [
                      DropdownMenuItem(
                        value: 'all',
                        child: Text(
                          context.tr('All Types'),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      ...allAlertTypeCodes().map(
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
                    label: context.tr('Status'),
                    value: filterStatus,
                    items: [
                      DropdownMenuItem(
                        value: 'all',
                        child: Text(
                          context.tr('All Statuses'),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'disponible',
                        child: Text(context.tr('Pending'),
                            style: const TextStyle(fontSize: 13)),
                      ),
                      DropdownMenuItem(
                        value: 'en_cours',
                        child: Text(context.tr('Claimed'),
                            style: const TextStyle(fontSize: 13)),
                      ),
                      DropdownMenuItem(
                        value: 'validee',
                        child: Text(context.tr('Fixed'),
                            style: const TextStyle(fontSize: 13)),
                      ),
                    ],
                    onChanged: onStatus,
                  ),
                  const SizedBox(height: 10),
                  _FilterDropdown(
                    label: context.tr('Time Range'),
                    value: timeRange,
                    items: [
                      DropdownMenuItem(
                        value: 'all',
                        child: Text(context.tr('All Time'),
                            style: const TextStyle(fontSize: 13)),
                      ),
                      DropdownMenuItem(
                        value: 'today',
                        child: Text(context.tr('Today'),
                            style: const TextStyle(fontSize: 13)),
                      ),
                      DropdownMenuItem(
                        value: 'week',
                        child: Text(
                          context.tr('Last 7 Days'),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'month',
                        child: Text(
                          context.tr('This Month'),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'year',
                        child: Text(
                          context.tr('This Year'),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'custom',
                        child: Text(context.tr('Custom'),
                            style: const TextStyle(fontSize: 13)),
                      ),
                    ],
                    onChanged: onTime,
                  ),
                  const SizedBox(height: 18),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.of(ctx).pop(),
                    icon: const Icon(Icons.check_rounded, size: 16),
                    label: Text(
                      ctx.tr('Apply'),
                      style: const TextStyle(
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
      'validee' => context.tr('Fixed'),
      'en_cours' => context.tr('Claimed'),
      _ => context.tr('Pending'),
    };
    final desc = alert.description.trim().isEmpty
        ? context.tr('(no description)')
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
                              context.tr('CRITICAL'),
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                color: theme.red,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                        if ((alert.source ?? '').isNotEmpty) ...[
                          const SizedBox(width: 6),
                          AlertSourceBadge(source: alert.source, dense: true),
                        ],
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
                      context.tr(
                          '{factory}  ·  Line {line}  ·  Post {station}  ·  {time}',
                          {
                            'factory': alert.usine,
                            'line': '${alert.convoyeur}',
                            'station': '${alert.poste}',
                            'time': _fmtTs(alert.timestamp),
                          }),
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
                                context.tr('Assigned: {name}',
                                    {'name': '${alert.superviseurName}'}),
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
                          context.tr('Critical note: {note}',
                              {'note': '${alert.criticalNote}'}),
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

