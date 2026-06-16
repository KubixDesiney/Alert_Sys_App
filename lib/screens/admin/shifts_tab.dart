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

part 'shifts_tab_live.dart';
part 'shifts_tab_timeline.dart';

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
