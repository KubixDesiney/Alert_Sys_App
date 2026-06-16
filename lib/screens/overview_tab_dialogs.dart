part of 'overview_tab.dart';

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

