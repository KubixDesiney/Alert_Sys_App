import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../models/shift_model.dart';
import '../../services/service_locator.dart';
import '../../services/shift_pdf_service.dart';
import '../../services/shift_service.dart';
import '../../theme.dart';
import '../../utils/user_friendly_error.dart';
import '../../widgets/common/app_loading_indicator.dart';
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

  final ShiftService _service = ServiceLocator.instance.shiftService;

  @override
  void initState() {
    super.initState();
    _sub2 = _service.streamShifts().listen((data) {
      if (!mounted) return;
      setState(() {
        _shifts = data;
        _loading = false;
        _selectedShiftId = _resolveSelectedId(data);
      });
    }, onError: (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    });
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

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final hostSize = Size(constraints.maxWidth, constraints.maxHeight);
        return Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: _loading
                      ? const AppLoadingIndicator()
                      : _UnifiedShiftsView(
                          shifts: _shifts,
                          selectedShift: _selectedShift(),
                          detailsKey: _detailsKey,
                          onSelect: _selectShift,
                          onEdit: (s) => _openCreate(existing: s),
                          onDelete: _confirmDelete,
                          onViewLogs: _openLogs,
                          onConfettiNeeded: _showConfettiFor,
                        ),
                ),
              ],
            ),
            Positioned(
              right: 22,
              bottom: 22,
              child: _PulsingFab(
                onTap: _openCreate,
                color: t.navy,
              ),
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
            'This will permanently remove "${s.name}". Active assignments will not be affected.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Shift deleted')),
      );
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

  const _UnifiedShiftsView({
    required this.shifts,
    required this.selectedShift,
    required this.detailsKey,
    required this.onSelect,
    required this.onEdit,
    required this.onDelete,
    required this.onViewLogs,
    required this.onConfettiNeeded,
  });

  @override
  Widget build(BuildContext context) {
    if (shifts.isEmpty) {
      return const _EmptyState(
        icon: Icons.schedule,
        title: 'No shifts yet',
        message:
            'Tap the glowing + button to define your first shift. Pick a name, time range, supervisors, and AI behavior.',
      );
    }
    final selected = selectedShift ?? shifts.first;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: [
        _TimelineView(shifts: shifts),
        const SizedBox(height: 16),
        _SectionHeader(
          icon: Icons.calendar_view_week,
          title: 'Shift roster',
          subtitle: 'Tap a card to bring its live controls into focus.',
          trailing: _LiveCountBadge(
            liveCount:
                shifts.where((s) => s.containsTime(DateTime.now())).length,
            totalCount: shifts.length,
          ),
        ),
        const SizedBox(height: 10),
        _CompactShiftGrid(
          shifts: shifts,
          selectedShiftId: selected.id,
          onSelect: onSelect,
          onEdit: onEdit,
          onDelete: onDelete,
        ),
        const SizedBox(height: 18),
        KeyedSubtree(
          key: detailsKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionHeader(
                icon: Icons.podcasts,
                title: 'Live shift detail',
                subtitle:
                    'Readiness, AI logs, handover, and exports in one place.',
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
    return LayoutBuilder(builder: (ctx, constraints) {
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
              final cardWidth = (box.maxHeight * 1.65).clamp(0.0, box.maxWidth);
              final settingsLeft = cardWidth - edgeInset - buttonSize * 2 - gap;
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
                                  color: context.appTheme.navy, width: 2)
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
    });
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
  String? _exportingFormat;
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
      WidgetsBinding.instance
          .addPostFrameCallback((_) => widget.onConfettiNeeded());
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
                    color: t.muted, fontSize: 11, fontWeight: FontWeight.w700),
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
                progress > 0.85 ? t.orange : t.navy),
          ),
        ),
        const SizedBox(height: 12),
        _ReadinessGrid(shift: widget.shift),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _ViewLogsButton(onTap: widget.onViewLogs)),
            const SizedBox(width: 8),
            Expanded(
              child: _ShiftExportMenuButton(
                exportingFormat: _exportingFormat,
                onExcel: () => _generateReport('excel'),
                onPdf: () => _generateReport('pdf'),
                onCsv: () => _generateReport('csv'),
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
                children: [
                  card,
                  const SizedBox(height: 14),
                  details,
                ],
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
      _handoverSummary = result ??
          'Could not reach the AI handover service. Please try again later.';
    });
  }

  int _minutesUntilStart(DateTime now) {
    final current = now.hour * 60 + now.minute;
    var delta = widget.shift.startMinutes - current;
    if (delta < 0) delta += 1440;
    return delta;
  }

  Future<void> _generateReport(String format) async {
    setState(() => _exportingFormat = format);
    try {
      switch (format) {
        case 'excel':
          await ShiftPdfService.exportExcelAndShare(
            shift: widget.shift,
            day: DateTime.now(),
          );
          break;
        case 'csv':
          await ShiftPdfService.exportCsvAndShare(
            shift: widget.shift,
            day: DateTime.now(),
          );
          break;
        case 'pdf':
        default:
          await ShiftPdfService.exportAndShare(
            shift: widget.shift,
            day: DateTime.now(),
          );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Failed to generate report: ${UserFriendlyError.message(e)}'),
          backgroundColor: context.appTheme.red,
        ),
      );
    }
    if (!mounted) return;
    setState(() => _exportingFormat = null);
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
    return Text('${h}h ${m}m',
        style:
            TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w900));
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
                      color: t.text, fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
              ElevatedButton.icon(
                onPressed: requesting ? null : onGenerate,
                icon: requesting
                    ? const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.auto_awesome,
                        size: 14, color: Colors.white),
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
            Text(summary!,
                style: TextStyle(color: t.text, fontSize: 12, height: 1.45)),
          ],
        ],
      ),
    );
  }
}

class _ReadinessGrid extends StatelessWidget {
  final ShiftModel shift;
  const _ReadinessGrid({required this.shift});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    if (shift.supervisors.isEmpty) {
      return Text('No supervisors assigned to this shift',
          style: TextStyle(color: t.muted, fontSize: 12));
    }
    final readyCount = shift.supervisors.where((s) => s.ready).length;
    final me = FirebaseAuth.instance.currentUser?.uid;
    final iAmIn = me != null && shift.supervisors.any((s) => s.id == me);
    final iAmReady =
        iAmIn && shift.supervisors.firstWhere((s) => s.id == me).ready;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.check_circle, color: t.green, size: 18),
            const SizedBox(width: 6),
            Text('Readiness',
                style: TextStyle(
                    color: t.muted, fontSize: 12, fontWeight: FontWeight.w700)),
            const Spacer(),
            Text('$readyCount / ${shift.supervisors.length} ready',
                style: TextStyle(
                    color: t.navy, fontSize: 13, fontWeight: FontWeight.w800)),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in shift.supervisors)
              _ReadyChip(sup: s, shiftId: shift.id),
          ],
        ),
        if (iAmIn) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              await ServiceLocator.instance.shiftService.setReadyState(
                shiftId: shift.id,
                supervisorId: me,
                ready: !iAmReady,
              );
            },
            icon: Icon(
              iAmReady ? Icons.cancel : Icons.handshake,
              size: 16,
              color: iAmReady ? t.red : t.green,
            ),
            label: Text(
              iAmReady ? 'Mark me not ready' : 'I\'m ready for shift',
              style: TextStyle(
                color: iAmReady ? t.red : t.green,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ReadyChip extends StatelessWidget {
  final AssignedSupervisor sup;
  final String shiftId;
  const _ReadyChip({required this.sup, required this.shiftId});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return InkWell(
      onTap: () async {
        await ServiceLocator.instance.shiftService.setReadyState(
          shiftId: shiftId,
          supervisorId: sup.id,
          ready: !sup.ready,
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: sup.ready ? t.greenLt : t.scaffold,
          border: Border.all(
              color: sup.ready ? t.green : t.border,
              width: sup.ready ? 1.5 : 1),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: sup.ready ? t.green : t.muted,
                shape: BoxShape.circle,
                boxShadow: [
                  if (sup.ready)
                    BoxShadow(
                      color: t.green.withValues(alpha: 0.7),
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              sup.name,
              style: TextStyle(
                color: sup.ready ? t.green : t.text,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
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
              Text('24-hour timeline',
                  style: TextStyle(
                      color: t.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w800)),
              const Spacer(),
              Text(
                _formatNow(now),
                style: TextStyle(
                    color: t.muted, fontSize: 12, fontWeight: FontWeight.w700),
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
            decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
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
      child: LayoutBuilder(builder: (ctx, c) {
        final w = c.maxWidth;
        return CustomPaint(
          size: Size(w, 96),
          painter: _TimelinePainter(
            shifts: shifts,
            nowMinutes: nowMinutes,
            isDark: isDark,
          ),
        );
      }),
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
          Rect.fromLTWH(0, trackY, w, trackH), const Radius.circular(8)),
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
        RRect.fromRectAndRadius(Rect.fromLTWH(x1, trackY, x2 - x1, trackH),
            const Radius.circular(6)),
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
          Offset(x, trackY - 6), Offset(x, trackY + trackH + 4), tickPaint);
      final tp = TextPainter(
        text: TextSpan(
            text: '${hr.toString().padLeft(2, '0')}h', style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset((x - tp.width / 2).clamp(0.0, w - tp.width), 6));
    }

    // Now marker.
    final nowX = (nowMinutes / 1440.0) * w;
    final nowGlow = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF22C55E).withValues(alpha: 0.6),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(
          center: Offset(nowX, trackY + trackH / 2), radius: 24));
    canvas.drawCircle(Offset(nowX, trackY + trackH / 2), 24, nowGlow);
    final nowLine = Paint()
      ..color = const Color(0xFF22C55E)
      ..strokeWidth = 2.4;
    canvas.drawLine(
      Offset(nowX, trackY - 10),
      Offset(nowX, trackY + trackH + 8),
      nowLine,
    );
    canvas.drawCircle(Offset(nowX, trackY + trackH / 2), 5,
        Paint()..color = const Color(0xFF22C55E));
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
  const _EmptyState(
      {required this.icon, required this.title, required this.message});

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
            Text(title,
                style: TextStyle(
                    color: t.text, fontSize: 18, fontWeight: FontWeight.w800)),
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
              center: Offset.zero, width: p.size, height: p.size * 0.5),
          paint);
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

// ────────────────────────── REPORT BUTTON ───────────────────────────────────
class _ShiftExportMenuButton extends StatelessWidget {
  final String? exportingFormat;
  final VoidCallback onExcel;
  final VoidCallback onPdf;
  final VoidCallback onCsv;

  const _ShiftExportMenuButton({
    required this.exportingFormat,
    required this.onExcel,
    required this.onPdf,
    required this.onCsv,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final isDark = context.isDark;
    final baseText = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final baseBg = isDark ? const Color(0xFF1E1E2E) : Colors.white;
    final borderColor =
        isDark ? const Color(0xFF3A3A5C) : const Color(0xFFDDE1EC);
    final busy = exportingFormat != null;

    return MenuAnchor(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(baseBg),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: borderColor),
          ),
        ),
        elevation: const WidgetStatePropertyAll(4),
        padding:
            const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 4)),
      ),
      menuChildren: [
        _ShiftExportMenuItem(
          icon: _excelIcon(),
          label: 'Excel',
          hoverColor: const Color(0xFF1D6F42),
          onTap: busy ? null : onExcel,
          baseBg: baseBg,
          baseText: baseText,
        ),
        _ShiftExportMenuItem(
          icon: _pdfIcon(),
          label: 'PDF',
          hoverColor: const Color(0xFFEC1C24),
          onTap: busy ? null : onPdf,
          baseBg: baseBg,
          baseText: baseText,
        ),
        _ShiftExportMenuItem(
          icon: Icon(Icons.table_chart_outlined, size: 16, color: baseText),
          label: 'CSV',
          hoverColor: const Color(0xFF0072C6),
          onTap: busy ? null : onCsv,
          baseBg: baseBg,
          baseText: baseText,
        ),
      ],
      builder: (context, controller, _) => OutlinedButton.icon(
        onPressed: busy
            ? null
            : () => controller.isOpen ? controller.close() : controller.open(),
        icon: busy
            ? SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(strokeWidth: 2, color: t.navy),
              )
            : Icon(Icons.download_outlined, size: 15, color: t.navy),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              busy ? 'Exporting ${exportingFormat!.toUpperCase()}' : 'Export',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: t.navy,
              ),
            ),
            if (!busy) ...[
              const SizedBox(width: 4),
              Icon(Icons.arrow_drop_down, size: 16, color: t.navy),
            ],
          ],
        ),
        style: OutlinedButton.styleFrom(
          backgroundColor: baseBg,
          side: BorderSide(color: borderColor),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
          minimumSize: const Size(0, 32),
        ),
      ),
    );
  }

  Widget _pdfIcon() => Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 18,
            height: 20,
            decoration: const BoxDecoration(
              color: Color(0xFFEC1C24),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(3),
                bottomLeft: Radius.circular(3),
                bottomRight: Radius.circular(3),
                topRight: Radius.circular(7),
              ),
            ),
          ),
          const Positioned(
            top: 0,
            right: 0,
            child: SizedBox(
              width: 7,
              height: 7,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Color(0xFFB71C1C),
                  borderRadius: BorderRadius.only(
                    topRight: Radius.circular(3),
                    bottomLeft: Radius.circular(3),
                  ),
                ),
              ),
            ),
          ),
          const Text(
            'PDF',
            style: TextStyle(
              fontSize: 5,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 0.2,
            ),
          ),
        ],
      );

  Widget _excelIcon() => Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 18,
            height: 20,
            decoration: BoxDecoration(
              color: const Color(0xFF1D6F42),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const Text(
            'X',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
        ],
      );
}

class _ShiftExportMenuItem extends StatefulWidget {
  final Widget icon;
  final String label;
  final Color hoverColor;
  final VoidCallback? onTap;
  final Color baseBg;
  final Color baseText;

  const _ShiftExportMenuItem({
    required this.icon,
    required this.label,
    required this.hoverColor,
    required this.onTap,
    required this.baseBg,
    required this.baseText,
  });

  @override
  State<_ShiftExportMenuItem> createState() => _ShiftExportMenuItemState();
}

class _ShiftExportMenuItemState extends State<_ShiftExportMenuItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) {
        if (enabled) setState(() => _hover = true);
      },
      onExit: (_) {
        if (enabled) setState(() => _hover = false);
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _hover
                ? widget.hoverColor.withValues(alpha: 0.12)
                : widget.baseBg,
            border: Border(
              left: BorderSide(
                color: _hover ? widget.hoverColor : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Row(
            children: [
              widget.icon,
              const SizedBox(width: 10),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _hover ? widget.hoverColor : widget.baseText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
