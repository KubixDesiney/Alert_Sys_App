import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/shift_model.dart';
import '../../services/service_locator.dart';
import '../../services/shift_pdf_service.dart';
import '../../services/shift_service.dart';
import '../../theme.dart';
import '../../utils/user_friendly_error.dart';
import '../../widgets/common/app_loading_indicator.dart';
import '../../widgets/shifts/presence_grid.dart';
import '../../widgets/shifts/shift_card.dart';
import '../../widgets/shifts/shift_logs_panel.dart';
import 'shift_creation_dialog.dart';

/// Top-level container for the Shifts module. The screen is intentionally a
/// single command board: live timeline, compact shift roster, then selected
/// shift details.
class AdminShiftsTab extends StatefulWidget {
  const AdminShiftsTab({super.key});

  @override
  State<AdminShiftsTab> createState() => _AdminShiftsTabState();
}

class _AdminShiftsTabState extends State<AdminShiftsTab> {
  StreamSubscription<List<ShiftModel>>? _sub2;
  Timer? _ticker;

  List<ShiftModel> _shifts = [];
  bool _loading = true;
  ShiftModel? _logsShift;
  String? _selectedShiftId;
  final GlobalKey _detailsKey = GlobalKey();
  final Map<String, bool> _confettiShown = {};

  // Shift roster filters — mirrors the alert-history filter pattern.
  _ShiftFilters _filters = const _ShiftFilters();

  final ShiftService _service = ServiceLocator.instance.shiftService;

  @override
  void initState() {
    super.initState();
    _sub2 = _service.streamShifts().listen(
      (data) {
        if (!mounted) return;
        setState(() {
          _shifts = data;
          _loading = false;
          _selectedShiftId = _resolveSelectedId(data);
        });
      },
      onError: (_) {
        if (!mounted) return;
        setState(() => _loading = false);
      },
    );
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub2?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _openCreate({ShiftModel? existing}) async {
    final created = await ShiftCreationDialog.show(context, existing: existing);
    if (created == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Shift saved'),
          backgroundColor: Color(0xFF16A34A),
        ),
      );
    }
  }

  void _openLogs(ShiftModel s) => setState(() => _logsShift = s);
  void _closeLogs() => setState(() => _logsShift = null);

  String? _resolveSelectedId(List<ShiftModel> shifts) {
    if (shifts.isEmpty) return null;
    if (_selectedShiftId != null &&
        shifts.any((s) => s.id == _selectedShiftId)) {
      return _selectedShiftId;
    }
    final now = DateTime.now();
    for (final shift in shifts) {
      if (shift.containsTime(now)) return shift.id;
    }
    return shifts.first.id;
  }

  ShiftModel? _selectedShift() {
    final id = _selectedShiftId;
    if (id == null) return null;
    for (final shift in _shifts) {
      if (shift.id == id) return shift;
    }
    return null;
  }

  void _selectShift(ShiftModel s) {
    setState(() => _selectedShiftId = s.id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _detailsKey.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic,
        alignment: 0.08,
      );
    });
  }

  void _showConfettiFor(ShiftModel s) {
    if (_confettiShown[s.id] == true) return;
    _confettiShown[s.id] = true;
    final overlay = Overlay.of(context);
    final entry = OverlayEntry(builder: (_) => const _ConfettiOverlay());
    overlay.insert(entry);
    Future.delayed(const Duration(seconds: 4), entry.remove);
  }

  List<ShiftModel> _filteredShifts() {
    final now = DateTime.now();
    return _shifts.where((s) {
      if (_filters.kind != 'all') {
        final k = s.kind == ShiftKind.morning
            ? 'morning'
            : s.kind == ShiftKind.afternoon
            ? 'afternoon'
            : 'night';
        if (k != _filters.kind) return false;
      }
      if (_filters.commander == 'on' && !s.aiCommander) return false;
      if (_filters.commander == 'off' && s.aiCommander) return false;
      if (_filters.factory != 'all') {
        final hit = s.supervisors.any((sup) => sup.factory == _filters.factory);
        if (!hit) return false;
      }
      if (_filters.window == 'live' && !s.containsTime(now)) return false;
      if (_filters.window == 'today') {
        // Today: starts within the current calendar day.
        final start = DateTime(
          now.year,
          now.month,
          now.day,
        ).add(Duration(minutes: s.startMinutes));
        if (start.isBefore(DateTime(now.year, now.month, now.day))) {
          return false;
        }
      }
      if (_filters.window == 'week') {
        // Always true today since shifts repeat — kept for parity with the
        // alert-history filter shape.
      }
      return true;
    }).toList();
  }

  Future<void> _openFilters() async {
    final factoryOptions = <String>{};
    for (final s in _shifts) {
      for (final sup in s.supervisors) {
        if (sup.factory.isNotEmpty) factoryOptions.add(sup.factory);
      }
    }
    final result = await showDialog<_ShiftFilters>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _ShiftFilterSheet(
        current: _filters,
        factories: factoryOptions.toList()..sort(),
      ),
    );
    if (result != null && mounted) {
      setState(() => _filters = result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final hostSize = Size(constraints.maxWidth, constraints.maxHeight);
        final shifts = _filteredShifts();
        final selected = _selectedShift();
        // If the current selection was filtered out, fall back to first match.
        final resolvedSelected =
            selected != null && shifts.any((s) => s.id == selected.id)
            ? selected
            : (shifts.isNotEmpty ? shifts.first : selected);
        return Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: _loading
                      ? const AppLoadingIndicator()
                      : _UnifiedShiftsView(
                          shifts: shifts,
                          selectedShift: resolvedSelected,
                          detailsKey: _detailsKey,
                          onSelect: _selectShift,
                          onEdit: (s) => _openCreate(existing: s),
                          onDelete: _confirmDelete,
                          onViewLogs: _openLogs,
                          onConfettiNeeded: _showConfettiFor,
                          activeFilterCount: _filters.activeCount,
                          onOpenFilters: _openFilters,
                          onClearFilters: () =>
                              setState(() => _filters = const _ShiftFilters()),
                          totalShiftCount: _shifts.length,
                        ),
                ),
              ],
            ),
            Positioned(
              right: 22,
              bottom: 22,
              child: _PulsingFab(onTap: _openCreate, color: t.navy),
            ),
            if (_logsShift != null)
              ShiftLogsPanel(
                shift: _logsShift!,
                onClose: _closeLogs,
                hostSize: hostSize,
              ),
          ],
        );
      },
    );
  }

  Future<void> _confirmDelete(ShiftModel s) async {
    final t = context.appTheme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete shift?'),
        content: Text(
          'This will permanently remove "${s.name}". Active assignments will not be affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: t.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.delete, size: 16, color: Colors.white),
            label: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _service.deleteShift(s.id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Shift deleted')));
    }
  }
}

// ───────────────────────── UNIFIED BOARD ─────────────────────────────────────
class _UnifiedShiftsView extends StatelessWidget {
  final List<ShiftModel> shifts;
  final ShiftModel? selectedShift;
  final GlobalKey detailsKey;
  final void Function(ShiftModel) onSelect;
  final void Function(ShiftModel) onEdit;
  final void Function(ShiftModel) onDelete;
  final void Function(ShiftModel) onViewLogs;
  final void Function(ShiftModel) onConfettiNeeded;
  final int activeFilterCount;
  final VoidCallback onOpenFilters;
  final VoidCallback onClearFilters;
  final int totalShiftCount;

  const _UnifiedShiftsView({
    required this.shifts,
    required this.selectedShift,
    required this.detailsKey,
    required this.onSelect,
    required this.onEdit,
    required this.onDelete,
    required this.onViewLogs,
    required this.onConfettiNeeded,
    required this.activeFilterCount,
    required this.onOpenFilters,
    required this.onClearFilters,
    required this.totalShiftCount,
  });

  @override
  Widget build(BuildContext context) {
    if (totalShiftCount == 0) {
      return const _EmptyState(
        icon: Icons.schedule,
        title: 'No shifts yet',
        message:
            'Tap the glowing + button to define your first shift. Pick a name, time range, supervisors, and AI behavior.',
      );
    }
    final selected = selectedShift ?? (shifts.isNotEmpty ? shifts.first : null);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: [
        _TimelineView(shifts: shifts),
        const SizedBox(height: 16),
        _SectionHeader(
          icon: Icons.calendar_view_week,
          title: 'Shift roster',
          subtitle: 'Tap a card to bring its live controls into focus.',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _LiveCountBadge(
                liveCount: shifts
                    .where((s) => s.containsTime(DateTime.now()))
                    .length,
                totalCount: shifts.length,
              ),
              const SizedBox(width: 8),
              _ShiftFiltersButton(
                count: activeFilterCount,
                onPressed: onOpenFilters,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (shifts.isEmpty)
          _NoMatchingShifts(onClearFilters: onClearFilters)
        else
          _CompactShiftGrid(
            shifts: shifts,
            selectedShiftId: selected?.id ?? '',
            onSelect: onSelect,
            onEdit: onEdit,
            onDelete: onDelete,
          ),
        const SizedBox(height: 18),
        if (selected != null)
          KeyedSubtree(
            key: detailsKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionHeader(
                  icon: Icons.podcasts,
                  title: 'Live shift detail',
                  subtitle:
                      'Presence, AI logs, handover, and PDF export in one place.',
                ),
                const SizedBox(height: 10),
                _LiveShiftPanel(
                  shift: selected,
                  onConfettiNeeded: () => onConfettiNeeded(selected),
                  onViewLogs: () => onViewLogs(selected),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ───────────────────────── FILTERS ───────────────────────────────────────────
class _ShiftFilters {
  final String kind; // all | morning | afternoon | night
  final String commander; // all | on | off
  final String factory; // all | <factory name>
  final String window; // all | live | today | week

  const _ShiftFilters({
    this.kind = 'all',
    this.commander = 'all',
    this.factory = 'all',
    this.window = 'all',
  });

  int get activeCount =>
      [kind, commander, factory, window].where((v) => v != 'all').length;

  _ShiftFilters copyWith({
    String? kind,
    String? commander,
    String? factory,
    String? window,
  }) => _ShiftFilters(
    kind: kind ?? this.kind,
    commander: commander ?? this.commander,
    factory: factory ?? this.factory,
    window: window ?? this.window,
  );
}

class _ShiftExportSettings {
  final String reportName;
  final DateTime day;
  final String factory;
  final Set<String> actionKinds;

  const _ShiftExportSettings({
    required this.reportName,
    required this.day,
    required this.factory,
    required this.actionKinds,
  });
}

class _ShiftFiltersButton extends StatelessWidget {
  final int count;
  final VoidCallback onPressed;
  const _ShiftFiltersButton({required this.count, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        OutlinedButton.icon(
          onPressed: onPressed,
          icon: const Icon(Icons.tune_rounded, size: 14),
          label: const Text(
            'Filters',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: t.navy,
            side: BorderSide(
              color: count > 0 ? t.navy : t.border,
              width: count > 0 ? 1.5 : 1.0,
            ),
            backgroundColor: t.scaffold,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(9),
            ),
          ),
        ),
        if (count > 0)
          Positioned(
            top: -4,
            right: -4,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(color: t.navy, shape: BoxShape.circle),
              child: Center(
                child: Text(
                  '$count',
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
    );
  }
}

class _NoMatchingShifts extends StatelessWidget {
  final VoidCallback onClearFilters;
  const _NoMatchingShifts({required this.onClearFilters});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      decoration: BoxDecoration(
        color: t.card,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(Icons.filter_alt_off_rounded, size: 36, color: t.muted),
          const SizedBox(height: 8),
          Text(
            'No shifts match your filters',
            style: TextStyle(
              color: t.text,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onClearFilters,
            icon: const Icon(Icons.refresh, size: 14),
            label: const Text('Clear filters'),
          ),
        ],
      ),
    );
  }
}

class _ShiftFilterSheet extends StatefulWidget {
  final _ShiftFilters current;
  final List<String> factories;
  const _ShiftFilterSheet({required this.current, required this.factories});

  @override
  State<_ShiftFilterSheet> createState() => _ShiftFilterSheetState();
}

class _ShiftFilterSheetState extends State<_ShiftFilterSheet> {
  late _ShiftFilters _draft = widget.current;

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Dialog(
      backgroundColor: t.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 6),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [t.navy, t.navy.withValues(alpha: 0.8)],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.tune_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Shift Filters',
                          style: TextStyle(
                            color: t.text,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'Refine the shift roster the same way you filter alerts.',
                          style: TextStyle(color: t.muted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _FilterSegment(
                      label: 'Shift kind',
                      icon: Icons.brightness_5_outlined,
                      value: _draft.kind,
                      options: const [
                        ('all', 'All'),
                        ('morning', 'Morning'),
                        ('afternoon', 'Evening'),
                        ('night', 'Night'),
                      ],
                      onChanged: (v) =>
                          setState(() => _draft = _draft.copyWith(kind: v)),
                    ),
                    const SizedBox(height: 14),
                    _FilterSegment(
                      label: 'AI Commander',
                      icon: Icons.auto_awesome,
                      value: _draft.commander,
                      options: const [
                        ('all', 'All'),
                        ('on', 'Enabled'),
                        ('off', 'Disabled'),
                      ],
                      onChanged: (v) => setState(
                        () => _draft = _draft.copyWith(commander: v),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _FilterSegment(
                      label: 'Time window',
                      icon: Icons.schedule,
                      value: _draft.window,
                      options: const [
                        ('all', 'Anytime'),
                        ('live', 'Live now'),
                        ('today', 'Today'),
                        ('week', 'This week'),
                      ],
                      onChanged: (v) =>
                          setState(() => _draft = _draft.copyWith(window: v)),
                    ),
                    if (widget.factories.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Text(
                        'Factory',
                        style: TextStyle(
                          color: t.muted,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue: _draft.factory,
                        items: [
                          const DropdownMenuItem(
                            value: 'all',
                            child: Text('All factories'),
                          ),
                          for (final f in widget.factories)
                            DropdownMenuItem(value: f, child: Text(f)),
                        ],
                        onChanged: (v) => setState(
                          () => _draft = _draft.copyWith(factory: v ?? 'all'),
                        ),
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.factory_outlined),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: t.scaffold,
                border: Border(top: BorderSide(color: t.border)),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: () =>
                        setState(() => _draft = const _ShiftFilters()),
                    icon: const Icon(Icons.refresh, size: 14),
                    label: const Text('Reset'),
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context, _draft),
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Apply'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: t.navy,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 10,
                      ),
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
}

class _FilterSegment extends StatelessWidget {
  final String label;
  final IconData icon;
  final String value;
  final List<(String, String)> options;
  final ValueChanged<String> onChanged;
  const _FilterSegment({
    required this.label,
    required this.icon,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: t.muted),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: t.muted,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final opt in options)
              ChoiceChip(
                selected: value == opt.$1,
                onSelected: (_) => onChanged(opt.$1),
                label: Text(opt.$2),
                labelStyle: TextStyle(
                  color: value == opt.$1 ? Colors.white : t.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
                selectedColor: t.navy,
                backgroundColor: t.scaffold,
                side: BorderSide(color: value == opt.$1 ? t.navy : t.border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: t.navyLt,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: t.navy, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: t.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(color: t.muted, fontSize: 12)),
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _LiveCountBadge extends StatelessWidget {
  final int liveCount;
  final int totalCount;

  const _LiveCountBadge({required this.liveCount, required this.totalCount});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final active = liveCount > 0;
    final color = active ? t.green : t.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: active ? t.greenLt : t.scaffold,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: active ? t.green : t.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.fiber_manual_record, size: 10, color: color),
          const SizedBox(width: 6),
          Text(
            '$liveCount/$totalCount live',
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactShiftGrid extends StatelessWidget {
  final List<ShiftModel> shifts;
  final String selectedShiftId;
  final void Function(ShiftModel) onSelect;
  final void Function(ShiftModel) onEdit;
  final void Function(ShiftModel) onDelete;

  const _CompactShiftGrid({
    required this.shifts,
    required this.selectedShiftId,
    required this.onSelect,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final cross = constraints.maxWidth >= 1180
            ? 4
            : constraints.maxWidth >= 860
            ? 3
            : constraints.maxWidth >= 560
            ? 2
            : 1;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cross,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.95,
          ),
          itemCount: shifts.length,
          itemBuilder: (ctx, i) {
            final s = shifts[i];
            final selected = s.id == selectedShiftId;
            return LayoutBuilder(
              builder: (context, box) {
                const buttonSize = 34.0;
                const gap = 6.0;
                const edgeInset = 10.0;
                final cardWidth = (box.maxHeight * 1.65).clamp(
                  0.0,
                  box.maxWidth,
                );
                final settingsLeft =
                    cardWidth - edgeInset - buttonSize * 2 - gap;
                final deleteLeft = cardWidth - edgeInset - buttonSize;

                return ClipRRect(
                  borderRadius: BorderRadius.circular(23),
                  child: Stack(
                    clipBehavior: Clip.hardEdge,
                    children: [
                      SizedBox(
                        width: cardWidth,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: EdgeInsets.all(selected ? 3 : 0),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(23),
                            border: selected
                                ? Border.all(
                                    color: context.appTheme.navy,
                                    width: 2,
                                  )
                                : null,
                          ),
                          child: ShiftCard(
                            shift: s,
                            isActiveNow: s.containsTime(now),
                            onTap: () => onSelect(s),
                          ),
                        ),
                      ),
                      Positioned(
                        top: edgeInset,
                        left: settingsLeft,
                        child: _ShiftPictureIconButton(
                          icon: Icons.settings,
                          tooltip: 'Edit shift settings',
                          onPressed: () => onEdit(s),
                        ),
                      ),
                      Positioned(
                        top: edgeInset,
                        left: deleteLeft,
                        child: _ShiftPictureIconButton(
                          icon: Icons.delete_outline,
                          tooltip: 'Delete shift',
                          onPressed: () => onDelete(s),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _ShiftPictureIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _ShiftPictureIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.34),
      shape: const CircleBorder(),
      child: IconButton(
        icon: Icon(icon, color: Colors.white, size: 18),
        tooltip: tooltip,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
      ),
    );
  }
}

// ────────────────────────── SCHEDULE VIEW ────────────────────────────────────
// ────────────────────────── LIVE VIEW ────────────────────────────────────────
class _LiveShiftPanel extends StatefulWidget {
  final ShiftModel shift;
  final VoidCallback onConfettiNeeded;
  final VoidCallback onViewLogs;
  const _LiveShiftPanel({
    required this.shift,
    required this.onConfettiNeeded,
    required this.onViewLogs,
  });

  @override
  State<_LiveShiftPanel> createState() => _LiveShiftPanelState();
}

class _LiveShiftPanelState extends State<_LiveShiftPanel> {
  bool _requestingHandover = false;
  bool _exportingPdf = false;
  String? _handoverSummary;

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final now = DateTime.now();
    final activeNow = widget.shift.containsTime(now);
    final remaining = activeNow
        ? widget.shift.minutesRemaining(now) ?? 0
        : _minutesUntilStart(now);
    final progress = activeNow ? widget.shift.progress(now) : 0.0;
    final timeLabel = activeNow ? 'Time remaining' : 'Starts in';

    if (activeNow && remaining <= 0) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => widget.onConfettiNeeded(),
      );
    }

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.timer, color: t.navy, size: 16),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                timeLabel,
                style: TextStyle(
                  color: t.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            _CountdownText(minutes: remaining, color: t.navy),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: t.scaffold,
            valueColor: AlwaysStoppedAnimation<Color>(
              progress > 0.85 ? t.orange : t.navy,
            ),
          ),
        ),
        const SizedBox(height: 12),
        ShiftPresenceGrid(shift: widget.shift, isActiveNow: activeNow),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _ViewLogsButton(onTap: widget.onViewLogs)),
            const SizedBox(width: 8),
            Expanded(
              child: _ShiftPdfExportButton(
                busy: _exportingPdf,
                onTap: _generatePdfReport,
              ),
            ),
          ],
        ),
        if (activeNow && remaining <= 30 && remaining > 0) ...[
          const SizedBox(height: 10),
          _HandoverBanner(
            minutes: remaining,
            requesting: _requestingHandover,
            summary: _handoverSummary,
            onGenerate: _generateHandover,
          ),
        ],
      ],
    );

    return Container(
      decoration: BoxDecoration(
        color: t.card,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 680;
            final card = SizedBox(
              width: stacked ? double.infinity : 220,
              height: stacked ? 170 : 140,
              child: ShiftCard(shift: widget.shift, isActiveNow: activeNow),
            );
            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [card, const SizedBox(height: 14), details],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                card,
                const SizedBox(width: 16),
                Expanded(child: details),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _generateHandover() async {
    setState(() => _requestingHandover = true);
    final result = await ServiceLocator.instance.shiftService
        .requestHandoverSummary(widget.shift);
    if (!mounted) return;
    setState(() {
      _requestingHandover = false;
      _handoverSummary =
          result ??
          'Could not reach the AI handover service. Please try again later.';
    });
  }

  int _minutesUntilStart(DateTime now) {
    final current = now.hour * 60 + now.minute;
    var delta = widget.shift.startMinutes - current;
    if (delta < 0) delta += 1440;
    return delta;
  }

  Future<void> _generatePdfReport() async {
    final factories =
        widget.shift.supervisors
            .map((s) => s.factory.trim())
            .where((f) => f.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final settings = await showDialog<_ShiftExportSettings>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _ShiftExportDialog(shift: widget.shift, factories: factories),
    );
    if (settings == null) return;
    if (settings.actionKinds.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Select at least one action type'),
          backgroundColor: context.appTheme.orange,
        ),
      );
      return;
    }

    setState(() => _exportingPdf = true);
    try {
      const allKinds = _ShiftExportDialogState.actionKinds;
      await ShiftPdfService.exportAndShare(
        shift: widget.shift,
        day: settings.day,
        options: ShiftReportExportOptions(
          reportName: settings.reportName,
          factory: settings.factory,
          actionKinds: settings.actionKinds.length == allKinds.length
              ? const <String>{}
              : settings.actionKinds,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to generate report: ${UserFriendlyError.message(e)}',
          ),
          backgroundColor: context.appTheme.red,
        ),
      );
    }
    if (!mounted) return;
    setState(() => _exportingPdf = false);
  }
}

// ────────────────────────── PDF EXPORT BUTTON ───────────────────────────────
class _ShiftPdfExportButton extends StatelessWidget {
  final bool busy;
  final VoidCallback onTap;
  const _ShiftPdfExportButton({required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return OutlinedButton.icon(
      onPressed: busy ? null : onTap,
      icon: busy
          ? SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(strokeWidth: 2, color: t.navy),
            )
          : const _PdfIcon(),
      label: Text(
        busy ? 'Generating PDF…' : 'Export PDF report',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: t.navy,
        ),
      ),
      style: OutlinedButton.styleFrom(
        backgroundColor: t.scaffold,
        side: BorderSide(color: t.navy.withValues(alpha: 0.3)),
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        minimumSize: const Size(0, 32),
      ),
    );
  }
}

class _ShiftExportDialog extends StatefulWidget {
  final ShiftModel shift;
  final List<String> factories;

  const _ShiftExportDialog({required this.shift, required this.factories});

  @override
  State<_ShiftExportDialog> createState() => _ShiftExportDialogState();
}

class _ShiftExportDialogState extends State<_ShiftExportDialog> {
  static const actionKinds = <String>{
    'created',
    'claimed',
    'resolved',
    'ai_assigned',
    'escalated',
    'handover',
  };

  late final TextEditingController _nameController;
  late DateTime _day;
  late String _factory;
  late Set<String> _selectedKinds;
  bool _nameTouched = false;

  @override
  void initState() {
    super.initState();
    _day = DateTime.now();
    _factory = 'all';
    _selectedKinds = Set<String>.from(actionKinds);
    _nameController = TextEditingController(text: _autoName());
    _nameController.addListener(() {
      if (!_nameTouched && _nameController.text != _autoName()) {
        _nameTouched = true;
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _autoName() {
    final factory = _factory == 'all' ? 'All factories' : _factory;
    return 'SIA Shift Commander Report - ${widget.shift.name} - $factory - ${_date(_day)}';
  }

  void _refreshName() {
    if (_nameTouched) return;
    _nameController.text = _autoName();
    _nameController.selection = TextSelection.collapsed(
      offset: _nameController.text.length,
    );
  }

  String _label(String kind) {
    switch (kind) {
      case 'created':
        return 'Created';
      case 'claimed':
        return 'Claimed';
      case 'resolved':
        return 'Resolved';
      case 'ai_assigned':
        return 'AI Assignments';
      case 'escalated':
        return 'Escalations';
      case 'handover':
        return 'Handovers';
      default:
        return kind;
    }
  }

  IconData _icon(String kind) {
    switch (kind) {
      case 'ai_assigned':
        return Icons.auto_awesome_rounded;
      case 'handover':
        return Icons.swap_horiz_rounded;
      case 'resolved':
        return Icons.check_circle_outline_rounded;
      case 'escalated':
        return Icons.priority_high_rounded;
      case 'claimed':
        return Icons.person_search_rounded;
      default:
        return Icons.add_alert_outlined;
    }
  }

  Future<void> _pickDay() async {
    final t = context.appTheme;
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(DateTime.now().year - 5),
      lastDate: DateTime(DateTime.now().year + 1, 12, 31),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(
            ctx,
          ).colorScheme.copyWith(primary: t.navy, onPrimary: Colors.white),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      _day = picked;
      _refreshName();
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final canExport = _selectedKinds.isNotEmpty;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Container(
            decoration: BoxDecoration(
              color: t.card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: t.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 18, 12, 18),
                  color: t.navy,
                  child: Row(
                    children: [
                      const Icon(
                        Icons.picture_as_pdf_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Export Shift Report',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Choose date, factory, and action types',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                        color: Colors.white,
                        tooltip: 'Close',
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _dialogLabel(t, 'Report name', Icons.edit_note_rounded),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _nameController,
                          maxLines: 2,
                          minLines: 1,
                          style: TextStyle(
                            color: t.text,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Report name',
                            suffixIcon: _nameTouched
                                ? IconButton(
                                    tooltip: 'Reset name',
                                    icon: const Icon(
                                      Icons.refresh_rounded,
                                      size: 18,
                                    ),
                                    onPressed: () => setState(() {
                                      _nameTouched = false;
                                      _refreshName();
                                    }),
                                  )
                                : null,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _dialogLabel(t, 'Report date', Icons.event_rounded),
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: _pickDay,
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: t.scaffold,
                              border: Border.all(color: t.border),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.calendar_today_rounded,
                                  color: t.muted,
                                  size: 16,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  _date(_day),
                                  style: TextStyle(
                                    color: t.text,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _dialogLabel(t, 'Factory', Icons.factory_rounded),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          initialValue: _factory,
                          items: [
                            const DropdownMenuItem(
                              value: 'all',
                              child: Text('All factories'),
                            ),
                            for (final f in widget.factories)
                              DropdownMenuItem(value: f, child: Text(f)),
                          ],
                          onChanged: (v) => setState(() {
                            _factory = v ?? 'all';
                            _refreshName();
                          }),
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.business_rounded),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            _dialogLabel(
                              t,
                              'Action types',
                              Icons.checklist_rounded,
                            ),
                            const Spacer(),
                            TextButton(
                              onPressed: () => setState(() {
                                _selectedKinds =
                                    _selectedKinds.length == actionKinds.length
                                    ? <String>{}
                                    : Set<String>.from(actionKinds);
                              }),
                              child: Text(
                                _selectedKinds.length == actionKinds.length
                                    ? 'Clear all'
                                    : 'Select all',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () => setState(() {
                                _selectedKinds = {'ai_assigned', 'handover'};
                              }),
                              child: const Text(
                                'AI only',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final kind in actionKinds)
                              FilterChip(
                                avatar: Icon(_icon(kind), size: 15),
                                label: Text(_label(kind)),
                                selected: _selectedKinds.contains(kind),
                                selectedColor: t.navy.withValues(alpha: 0.14),
                                checkmarkColor: t.navy,
                                backgroundColor: t.scaffold,
                                side: BorderSide(
                                  color: _selectedKinds.contains(kind)
                                      ? t.navy
                                      : t.border,
                                ),
                                labelStyle: TextStyle(
                                  color: t.text,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                                onSelected: (selected) => setState(() {
                                  if (selected) {
                                    _selectedKinds.add(kind);
                                  } else {
                                    _selectedKinds.remove(kind);
                                  }
                                }),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                  decoration: BoxDecoration(
                    color: t.scaffold,
                    border: Border(top: BorderSide(color: t.border)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          canExport
                              ? '${_selectedKinds.length} action type${_selectedKinds.length == 1 ? '' : 's'} selected'
                              : 'No action types selected',
                          style: TextStyle(
                            color: canExport ? t.muted : t.red,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: canExport
                            ? () => Navigator.pop(
                                context,
                                _ShiftExportSettings(
                                  reportName: _nameController.text.trim(),
                                  day: _day,
                                  factory: _factory,
                                  actionKinds: Set<String>.from(_selectedKinds),
                                ),
                              )
                            : null,
                        icon: const Icon(Icons.download_rounded, size: 16),
                        label: const Text('Generate PDF'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: t.navy,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dialogLabel(AppTheme t, String label, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 14, color: t.navy),
        const SizedBox(width: 6),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: t.text,
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.7,
          ),
        ),
      ],
    );
  }
}

class _PdfIcon extends StatelessWidget {
  const _PdfIcon();

  @override
  Widget build(BuildContext context) {
    return const Icon(
      Icons.picture_as_pdf_rounded,
      color: Color(0xFFEC1C24),
      size: 18,
    );
  }
}

class _CountdownText extends StatelessWidget {
  final int minutes;
  final Color color;
  const _CountdownText({required this.minutes, required this.color});

  @override
  Widget build(BuildContext context) {
    final h = (minutes ~/ 60).toString().padLeft(2, '0');
    final m = (minutes % 60).toString().padLeft(2, '0');
    return Text(
      '${h}h ${m}m',
      style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w900),
    );
  }
}

class _HandoverBanner extends StatelessWidget {
  final int minutes;
  final bool requesting;
  final String? summary;
  final VoidCallback onGenerate;
  const _HandoverBanner({
    required this.minutes,
    required this.requesting,
    required this.summary,
    required this.onGenerate,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0x3360A5FA), Color(0x33C084FC)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF60A5FA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.swap_horiz, color: Color(0xFF60A5FA)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Shift ends in $minutes min — generate AI handover?',
                  style: TextStyle(
                    color: t.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ElevatedButton.icon(
                onPressed: requesting ? null : onGenerate,
                icon: requesting
                    ? const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(
                        Icons.auto_awesome,
                        size: 14,
                        color: Colors.white,
                      ),
                label: Text(requesting ? 'Generating…' : 'Generate'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF60A5FA),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
          if (summary != null) ...[
            const SizedBox(height: 10),
            Text(
              summary!,
              style: TextStyle(color: t.text, fontSize: 12, height: 1.45),
            ),
          ],
        ],
      ),
    );
  }
}

// ────────────────────────── TIMELINE VIEW ────────────────────────────────────
class _TimelineView extends StatelessWidget {
  final List<ShiftModel> shifts;
  const _TimelineView({required this.shifts});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final now = DateTime.now();
    final nowMinutes = now.hour * 60 + now.minute + now.second / 60;

    if (shifts.isEmpty) {
      return const _EmptyState(
        icon: Icons.timeline,
        title: 'No timeline yet',
        message:
            'Once you create shifts, they\'ll appear here as colored blocks across a 24-hour timeline. The pulsing line shows the current time.',
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.card,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.access_time, color: t.navy, size: 18),
              const SizedBox(width: 6),
              Text(
                '24-hour timeline',
                style: TextStyle(
                  color: t.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Text(
                _formatNow(now),
                style: TextStyle(
                  color: t.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _TimelineStrip(
            shifts: shifts,
            nowMinutes: nowMinutes,
            isDark: context.isDark,
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _legendDot(const Color(0xFFFCD34D), 'Morning'),
              _legendDot(const Color(0xFFFB923C), 'Evening'),
              _legendDot(const Color(0xFF6366F1), 'Night'),
              _legendDot(t.green, 'Now'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color c, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  String _formatNow(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:${d.second.toString().padLeft(2, '0')}';
}

class _TimelineStrip extends StatelessWidget {
  final List<ShiftModel> shifts;
  final double nowMinutes;
  final bool isDark;
  const _TimelineStrip({
    required this.shifts,
    required this.nowMinutes,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 96,
      child: LayoutBuilder(
        builder: (ctx, c) {
          final w = c.maxWidth;
          return CustomPaint(
            size: Size(w, 96),
            painter: _TimelinePainter(
              shifts: shifts,
              nowMinutes: nowMinutes,
              isDark: isDark,
            ),
          );
        },
      ),
    );
  }
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter({
    required this.shifts,
    required this.nowMinutes,
    required this.isDark,
  });

  final List<ShiftModel> shifts;
  final double nowMinutes;
  final bool isDark;

  Color _kindColor(ShiftKind k) {
    switch (k) {
      case ShiftKind.morning:
        return const Color(0xFFFCD34D);
      case ShiftKind.afternoon:
        return const Color(0xFFFB923C);
      case ShiftKind.night:
        return const Color(0xFF6366F1);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final trackY = h - 32;
    const trackH = 22.0;

    // Track background.
    final track = Paint()
      ..color = isDark ? const Color(0xFF1F2937) : const Color(0xFFE2E8F0);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, trackY, w, trackH),
        const Radius.circular(8),
      ),
      track,
    );

    void drawSegment(double startM, double endM, Color c) {
      final x1 = (startM / 1440.0) * w;
      final x2 = (endM / 1440.0) * w;
      final paint = Paint()
        ..shader = LinearGradient(
          colors: [c.withValues(alpha: 0.85), c.withValues(alpha: 1.0)],
        ).createShader(Rect.fromLTWH(x1, trackY, x2 - x1, trackH));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x1, trackY, x2 - x1, trackH),
          const Radius.circular(6),
        ),
        paint,
      );
    }

    for (final s in shifts) {
      final c = _kindColor(s.kind);
      if (s.endMinutes >= s.startMinutes) {
        drawSegment(s.startMinutes.toDouble(), s.endMinutes.toDouble(), c);
      } else {
        drawSegment(s.startMinutes.toDouble(), 1440, c);
        drawSegment(0, s.endMinutes.toDouble(), c);
      }
    }

    // Hour ticks every 3 hours.
    final tickPaint = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.18);
    final textStyle = TextStyle(
      color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.55),
      fontSize: 10,
      fontWeight: FontWeight.w700,
    );
    for (int hr = 0; hr <= 24; hr += 3) {
      final x = (hr / 24.0) * w;
      canvas.drawLine(
        Offset(x, trackY - 6),
        Offset(x, trackY + trackH + 4),
        tickPaint,
      );
      final tp = TextPainter(
        text: TextSpan(
          text: '${hr.toString().padLeft(2, '0')}h',
          style: textStyle,
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset((x - tp.width / 2).clamp(0.0, w - tp.width), 6));
    }

    // Now marker.
    final nowX = (nowMinutes / 1440.0) * w;
    final nowGlow = Paint()
      ..shader =
          RadialGradient(
            colors: [
              const Color(0xFF22C55E).withValues(alpha: 0.6),
              Colors.transparent,
            ],
          ).createShader(
            Rect.fromCircle(
              center: Offset(nowX, trackY + trackH / 2),
              radius: 24,
            ),
          );
    canvas.drawCircle(Offset(nowX, trackY + trackH / 2), 24, nowGlow);
    final nowLine = Paint()
      ..color = const Color(0xFF22C55E)
      ..strokeWidth = 2.4;
    canvas.drawLine(
      Offset(nowX, trackY - 10),
      Offset(nowX, trackY + trackH + 8),
      nowLine,
    );
    canvas.drawCircle(
      Offset(nowX, trackY + trackH / 2),
      5,
      Paint()..color = const Color(0xFF22C55E),
    );
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter old) {
    return old.nowMinutes != nowMinutes ||
        old.shifts != shifts ||
        old.isDark != isDark;
  }
}

// ────────────────────────── EMPTY STATE ──────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF60A5FA), Color(0xFFC084FC)],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(icon, color: Colors.white, size: 38),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                color: t.text,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(color: t.muted, fontSize: 13, height: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────── PULSING FAB ──────────────────────────────────────
class _PulsingFab extends StatefulWidget {
  final VoidCallback onTap;
  final Color color;
  const _PulsingFab({required this.onTap, required this.color});

  @override
  State<_PulsingFab> createState() => _PulsingFabState();
}

class _PulsingFabState extends State<_PulsingFab>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (ctx, _) {
        final t = _ctrl.value;
        return SizedBox(
          width: 80,
          height: 80,
          child: Stack(
            alignment: Alignment.center,
            children: [
              for (int i = 0; i < 2; i++)
                Opacity(
                  opacity: (1 - ((t + i * 0.5) % 1.0)) * 0.5,
                  child: Container(
                    width: 40 + ((t + i * 0.5) % 1.0) * 50,
                    height: 40 + ((t + i * 0.5) % 1.0) * 50,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.color.withValues(alpha: 0.4),
                    ),
                  ),
                ),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: widget.onTap,
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF60A5FA), Color(0xFFC084FC)],
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: widget.color.withValues(alpha: 0.6),
                          blurRadius: 18,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.add, color: Colors.white, size: 28),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ────────────────────────── CONFETTI ─────────────────────────────────────────
class _ConfettiOverlay extends StatefulWidget {
  const _ConfettiOverlay();

  @override
  State<_ConfettiOverlay> createState() => _ConfettiOverlayState();
}

class _ConfettiOverlayState extends State<_ConfettiOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late List<_ConfettiPiece> _pieces;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..forward();
    final rnd = math.Random();
    _pieces = List.generate(
      80,
      (_) => _ConfettiPiece(
        x: rnd.nextDouble(),
        delay: rnd.nextDouble() * 0.5,
        speed: 0.5 + rnd.nextDouble() * 0.7,
        spin: rnd.nextDouble() * 6 - 3,
        color: [
          const Color(0xFF60A5FA),
          const Color(0xFFFCD34D),
          const Color(0xFFC084FC),
          const Color(0xFF22C55E),
          const Color(0xFFF87171),
        ][rnd.nextInt(5)],
        size: 6 + rnd.nextDouble() * 6,
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (ctx, _) {
          return CustomPaint(
            painter: _ConfettiPainter(t: _ctrl.value, pieces: _pieces),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}

class _ConfettiPiece {
  final double x;
  final double delay;
  final double speed;
  final double spin;
  final Color color;
  final double size;
  _ConfettiPiece({
    required this.x,
    required this.delay,
    required this.speed,
    required this.spin,
    required this.color,
    required this.size,
  });
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({required this.t, required this.pieces});
  final double t;
  final List<_ConfettiPiece> pieces;

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in pieces) {
      final localT = ((t - p.delay) / p.speed).clamp(0.0, 1.0);
      if (localT <= 0) continue;
      final y = -20 + localT * (size.height + 40);
      final x = p.x * size.width + math.sin(localT * 6) * 30;
      final paint = Paint()
        ..color = p.color.withValues(alpha: 1 - localT * 0.4);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(localT * p.spin * 6.28);
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset.zero,
          width: p.size,
          height: p.size * 0.5,
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) => old.t != t;
}

// ────────────────────────── VIEW LOGS BUTTON ─────────────────────────────────
class _ViewLogsButton extends StatelessWidget {
  final VoidCallback onTap;
  const _ViewLogsButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.history, size: 14),
      label: const Text('AI logs'),
      style: OutlinedButton.styleFrom(
        foregroundColor: t.navy,
        side: BorderSide(color: t.navy.withValues(alpha: 0.3)),
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        minimumSize: const Size(0, 32),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}

// Old multi-format export menu replaced by `_ShiftPdfExportButton` above —
// PDF is now the only export format the PM can produce from this tab.
