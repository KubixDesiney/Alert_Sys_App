part of 'overview_tab.dart';

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
                      context.tr('Export Report'),
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

  String _datePresetLabel(BuildContext context) {
    switch (_datePreset) {
      case 'today':
        return context.tr('Today');
      case 'week':
        return context.tr('Last 7 Days');
      case 'month':
        return context.tr('This Month');
      case 'year':
        return context.tr('This Year');
      case 'custom':
        if (_customFrom != null && _customTo != null) {
          return '${_isoDate(_customFrom!)} - ${_isoDate(_customTo!)}';
        }
        return context.tr('Custom Range');
      default:
        return context.tr('All Time');
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
                              label: context.tr('Criticality'),
                              icon: Icons.priority_high_rounded,
                              value: _critical,
                              options: [
                                ('all', context.tr('All')),
                                ('critical', context.tr('Critical Only')),
                                ('normal', context.tr('Normal Only')),
                              ],
                              onChanged: (v) => setState(() {
                                _critical = v;
                                _refreshAutoNameIfNeeded();
                              }),
                            ),
                            const SizedBox(height: 18),
                            _buildSegmentSection(
                              theme: theme,
                              label: context.tr('Status'),
                              icon: Icons.flag_rounded,
                              value: _status,
                              options: [
                                ('all', context.tr('All')),
                                ('disponible', context.tr('Pending')),
                                ('en_cours', context.tr('Claimed')),
                                ('validee', context.tr('Resolved')),
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('Export Report'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  context.tr(
                      'Generate a professional PDF tailored to your filters'),
                  style: const TextStyle(
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
            tooltip: context.tr('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildReportNameField(AppTheme theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(theme, context.tr('Report Name'), Icons.edit_note_rounded),
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
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    hintText: context.tr('Report name'),
                  ),
                ),
              ),
              if (_nameTouched)
                IconButton(
                  tooltip: context.tr('Reset to auto-generated name'),
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
              ? context.tr('Custom report name')
              : context.tr('Auto-generated from current filters'),
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
        _sectionLabel(theme, context.tr('Location Scope'), Icons.factory_rounded),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (ctx, c) {
            final narrow = c.maxWidth < 520;
            final factoryField = _locationDropdown(
              theme: theme,
              icon: Icons.business_rounded,
              label: context.tr('Plant'),
              value: safeFactory,
              items: factoryOpts.map((v) {
                return DropdownMenuItem<String>(
                  value: v,
                  child: Text(
                    v == 'all' ? context.tr('All Plants') : v,
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
              label: context.tr('Conveyor'),
              value: safeConveyeur,
              enabled: conveyeurOpts.length > 1,
              items: conveyeurOpts.map((v) {
                return DropdownMenuItem<String>(
                  value: v,
                  child: Text(
                    v == 'all'
                        ? context.tr('All Conveyors')
                        : context.tr('Conv. {n}', {'n': v}),
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
              label: context.tr('Workstation'),
              value: safePoste,
              enabled: posteOpts.length > 1,
              items: posteOpts.map((v) {
                return DropdownMenuItem<String>(
                  value: v,
                  child: Text(
                    v == 'all'
                        ? context.tr('All Workstations')
                        : context.tr('WS {n}', {'n': v}),
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
              label: Text(
                context.tr('Clear location filters'),
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
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
    final presets = <(String, String)>[
      ('all', context.tr('All Time')),
      ('today', context.tr('Today')),
      ('week', context.tr('Last 7 Days')),
      ('month', context.tr('This Month')),
      ('year', context.tr('This Year')),
      ('custom', context.tr('Custom')),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(theme, context.tr('Date Range'), Icons.event_rounded),
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
                  label: context.tr('From'),
                  value: _customFrom,
                  onTap: () => _pickDate(true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _datePickerField(
                  theme: theme,
                  label: context.tr('To'),
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
                    value == null ? context.tr('Select date') : _isoDate(value),
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
            _sectionLabel(theme, context.tr('Alert Types'), Icons.category_rounded),
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
                allSelected ? context.tr('Clear all') : context.tr('Select all'),
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
                      ? context.tr('No alerts match')
                      : (filtered.length == 1
                          ? context.tr('{n} alert included',
                              {'n': '${filtered.length}'})
                          : context.tr('{n} alerts included',
                              {'n': '${filtered.length}'})),
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
              _datePresetLabel(context),
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
            child: Text(
              context.tr('Cancel'),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
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
              _exporting
                  ? context.tr('Generating...')
                  : context.tr('Generate PDF'),
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
