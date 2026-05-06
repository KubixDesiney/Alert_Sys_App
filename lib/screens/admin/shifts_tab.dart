import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../models/shift_model.dart';
import '../../services/service_locator.dart';
import '../../services/shift_service.dart';
import '../../theme.dart';
import '../../widgets/shifts/shift_card.dart';
import 'shift_creation_dialog.dart';

/// Top-level container for the Shifts module. Renders sub-tabs:
///   • Schedule  — manage all shifts (animated cards)
///   • Live      — currently running shifts with countdown + readiness
///   • Timeline  — 24h horizontal strip with the now-marker drifting across
class AdminShiftsTab extends StatefulWidget {
  const AdminShiftsTab({super.key});

  @override
  State<AdminShiftsTab> createState() => _AdminShiftsTabState();
}

class _AdminShiftsTabState extends State<AdminShiftsTab>
    with SingleTickerProviderStateMixin {
  late TabController _sub;
  StreamSubscription<List<ShiftModel>>? _sub2;
  Timer? _ticker;

  List<ShiftModel> _shifts = [];
  bool _loading = true;

  final ShiftService _service = ServiceLocator.instance.shiftService;

  @override
  void initState() {
    super.initState();
    _sub = TabController(length: 3, vsync: this);
    _sub2 = _service.streamShifts().listen((data) {
      if (!mounted) return;
      setState(() {
        _shifts = data;
        _loading = false;
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
    _sub.dispose();
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

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Stack(
      children: [
        Column(
          children: [
            _SubTabBar(controller: _sub),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      controller: _sub,
                      children: [
                        _ScheduleView(
                          shifts: _shifts,
                          onTap: (s) => _openCreate(existing: s),
                          onDelete: (s) => _confirmDelete(s),
                        ),
                        _LiveView(shifts: _shifts),
                        _TimelineView(shifts: _shifts),
                      ],
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
      ],
    );
  }

  Future<void> _confirmDelete(ShiftModel s) async {
    final t = context.appTheme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete shift?'),
        content: Text(
            'This will permanently remove "${s.name}". Active assignments will not be affected.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(_, false),
              child: const Text('Cancel')),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: t.red),
            onPressed: () => Navigator.pop(_, true),
            icon: const Icon(Icons.delete, size: 16, color: Colors.white),
            label: const Text('Delete',
                style: TextStyle(color: Colors.white)),
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

// ────────────────────────── SUB-TAB BAR ──────────────────────────────────────
class _SubTabBar extends StatelessWidget {
  final TabController controller;
  const _SubTabBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Container(
      color: t.card,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Container(
        decoration: BoxDecoration(
          color: t.scaffold,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: t.border),
        ),
        child: TabBar(
          controller: controller,
          indicatorSize: TabBarIndicatorSize.tab,
          indicatorPadding: const EdgeInsets.all(4),
          labelColor: Colors.white,
          unselectedLabelColor: t.muted,
          labelStyle: const TextStyle(
              fontWeight: FontWeight.w800, fontSize: 13),
          dividerColor: Colors.transparent,
          indicator: BoxDecoration(
            color: t.navy,
            borderRadius: BorderRadius.circular(10),
          ),
          tabs: const [
            Tab(
                height: 38,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.calendar_view_week, size: 14),
                    SizedBox(width: 6),
                    Text('Schedule'),
                  ],
                )),
            Tab(
                height: 38,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.podcasts, size: 14),
                    SizedBox(width: 6),
                    Text('Live'),
                  ],
                )),
            Tab(
                height: 38,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.timeline, size: 14),
                    SizedBox(width: 6),
                    Text('Timeline'),
                  ],
                )),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────── SCHEDULE VIEW ────────────────────────────────────
class _ScheduleView extends StatelessWidget {
  final List<ShiftModel> shifts;
  final void Function(ShiftModel) onTap;
  final void Function(ShiftModel) onDelete;
  const _ScheduleView(
      {required this.shifts, required this.onTap, required this.onDelete});

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
    final now = DateTime.now();
    return LayoutBuilder(builder: (ctx, constraints) {
      final cross = constraints.maxWidth >= 1100
          ? 3
          : constraints.maxWidth >= 720
              ? 2
              : 1;
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 96),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cross,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 1.65,
        ),
        itemCount: shifts.length,
        itemBuilder: (ctx, i) {
          final s = shifts[i];
          return Stack(
            children: [
              ShiftCard(
                shift: s,
                isActiveNow: s.containsTime(now),
                onTap: () => onTap(s),
              ),
              Positioned(
                top: 6,
                right: 6,
                child: Material(
                  color: Colors.black26,
                  shape: const CircleBorder(),
                  child: IconButton(
                    icon: const Icon(Icons.delete_outline,
                        color: Colors.white, size: 18),
                    tooltip: 'Delete',
                    onPressed: () => onDelete(s),
                  ),
                ),
              ),
            ],
          );
        },
      );
    });
  }
}

// ────────────────────────── LIVE VIEW ────────────────────────────────────────
class _LiveView extends StatefulWidget {
  final List<ShiftModel> shifts;
  const _LiveView({required this.shifts});

  @override
  State<_LiveView> createState() => _LiveViewState();
}

class _LiveViewState extends State<_LiveView> {
  final Map<String, bool> _confettiShown = {};

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final now = DateTime.now();
    final live =
        widget.shifts.where((s) => s.containsTime(now)).toList(growable: false);
    final upcoming = widget.shifts
        .where((s) => !s.containsTime(now))
        .toList(growable: false)
      ..sort((a, b) {
        final m = now.hour * 60 + now.minute;
        int distance(int start) {
          final d = start - m;
          return d < 0 ? d + 1440 : d;
        }

        return distance(a.startMinutes).compareTo(distance(b.startMinutes));
      });

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: [
        if (live.isEmpty)
          _EmptyState(
            icon: Icons.podcasts,
            title: 'No active shifts right now',
            message:
                'When a shift window opens, you\'ll see live status, countdowns, and a confetti celebration when it ends.',
          ),
        for (final s in live)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _LiveShiftPanel(
              shift: s,
              onConfettiNeeded: () {
                if (_confettiShown[s.id] == true) return;
                _confettiShown[s.id] = true;
                _showConfetti(context);
              },
            ),
          ),
        if (upcoming.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
            child: Text(
              'Upcoming today',
              style: TextStyle(
                color: t.muted,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
              ),
            ),
          ),
          for (final s in upcoming.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _UpcomingRow(shift: s),
            ),
        ],
      ],
    );
  }

  void _showConfetti(BuildContext context) {
    final overlay = Overlay.of(context);
    final entry = OverlayEntry(builder: (_) => const _ConfettiOverlay());
    overlay.insert(entry);
    Future.delayed(const Duration(seconds: 4), entry.remove);
  }
}

class _LiveShiftPanel extends StatefulWidget {
  final ShiftModel shift;
  final VoidCallback onConfettiNeeded;
  const _LiveShiftPanel(
      {required this.shift, required this.onConfettiNeeded});

  @override
  State<_LiveShiftPanel> createState() => _LiveShiftPanelState();
}

class _LiveShiftPanelState extends State<_LiveShiftPanel> {
  bool _requestingHandover = false;
  String? _handoverSummary;

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final now = DateTime.now();
    final remaining = widget.shift.minutesRemaining(now) ?? 0;
    final progress = widget.shift.progress(now);

    if (remaining <= 0) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => widget.onConfettiNeeded());
    }

    return Container(
      decoration: BoxDecoration(
        color: t.card,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          ShiftCard(shift: widget.shift, isActiveNow: true),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.timer, color: t.navy, size: 18),
                    const SizedBox(width: 6),
                    Text('Time remaining',
                        style: TextStyle(
                            color: t.muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                    const Spacer(),
                    _CountdownText(minutes: remaining, color: t.navy),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    backgroundColor: t.scaffold,
                    valueColor: AlwaysStoppedAnimation<Color>(
                        progress > 0.85 ? t.orange : t.navy),
                  ),
                ),
                if (remaining <= 30 && remaining > 0) ...[
                  const SizedBox(height: 14),
                  _HandoverBanner(
                    minutes: remaining,
                    requesting: _requestingHandover,
                    summary: _handoverSummary,
                    onGenerate: _generateHandover,
                  ),
                ],
                const SizedBox(height: 14),
                _ReadinessGrid(shift: widget.shift),
              ],
            ),
          ),
        ],
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
        style: TextStyle(
            color: color, fontSize: 18, fontWeight: FontWeight.w900));
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
                      fontWeight: FontWeight.w700),
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
                style:
                    TextStyle(color: t.text, fontSize: 12, height: 1.45)),
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
                    color: t.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
            const Spacer(),
            Text('$readyCount / ${shift.supervisors.length} ready',
                style: TextStyle(
                    color: t.navy,
                    fontSize: 13,
                    fontWeight: FontWeight.w800)),
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
              color: sup.ready ? t.green : t.border, width: sup.ready ? 1.5 : 1),
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
                      color: t.green.withOpacity(0.7),
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

class _UpcomingRow extends StatelessWidget {
  final ShiftModel shift;
  const _UpcomingRow({required this.shift});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final now = DateTime.now();
    final m = now.hour * 60 + now.minute;
    int delta = shift.startMinutes - m;
    if (delta < 0) delta += 1440;
    final hh = (delta ~/ 60);
    final mm = (delta % 60);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: t.card,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            switch (shift.kind) {
              ShiftKind.morning => Icons.wb_sunny,
              ShiftKind.afternoon => Icons.wb_twilight,
              ShiftKind.night => Icons.nights_stay,
            },
            color: switch (shift.kind) {
              ShiftKind.morning => t.yellow,
              ShiftKind.afternoon => t.orange,
              ShiftKind.night => t.navy,
            },
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(shift.name,
                    style: TextStyle(
                        color: t.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
                Text(shift.timeRangeLabel,
                    style: TextStyle(color: t.muted, fontSize: 11)),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: t.navyLt,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              hh > 0 ? 'in ${hh}h ${mm}m' : 'in $mm min',
              style: TextStyle(
                  color: t.navy,
                  fontSize: 11,
                  fontWeight: FontWeight.w800),
            ),
          ),
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
      return _EmptyState(
        icon: Icons.timeline,
        title: 'No timeline yet',
        message:
            'Once you create shifts, they\'ll appear here as colored blocks across a 24-hour timeline. The pulsing line shows the current time.',
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
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
                          color: t.muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w700),
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
                Row(
                  children: [
                    _legendDot(const Color(0xFFFCD34D), 'Morning'),
                    const SizedBox(width: 12),
                    _legendDot(const Color(0xFFFB923C), 'Evening'),
                    const SizedBox(width: 12),
                    _legendDot(const Color(0xFF6366F1), 'Night'),
                    const SizedBox(width: 12),
                    _legendDot(t.green, 'Now'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          ...shifts.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _UpcomingRow(shift: s),
              )),
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
            decoration:
                BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700)),
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
    final trackH = 22.0;

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
          colors: [c.withOpacity(0.85), c.withOpacity(1.0)],
        ).createShader(Rect.fromLTWH(x1, trackY, x2 - x1, trackH));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(x1, trackY, x2 - x1, trackH),
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
      ..color = (isDark ? Colors.white : Colors.black).withOpacity(0.18);
    final textStyle = TextStyle(
      color: (isDark ? Colors.white : Colors.black).withOpacity(0.55),
      fontSize: 10,
      fontWeight: FontWeight.w700,
    );
    for (int hr = 0; hr <= 24; hr += 3) {
      final x = (hr / 24.0) * w;
      canvas.drawLine(Offset(x, trackY - 6),
          Offset(x, trackY + trackH + 4), tickPaint);
      final tp = TextPainter(
        text: TextSpan(
            text: '${hr.toString().padLeft(2, '0')}h', style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
          canvas, Offset((x - tp.width / 2).clamp(0.0, w - tp.width), 6));
    }

    // Now marker.
    final nowX = (nowMinutes / 1440.0) * w;
    final nowGlow = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF22C55E).withOpacity(0.6),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(
          center: Offset(nowX, trackY + trackH / 2), radius: 24));
    canvas.drawCircle(
        Offset(nowX, trackY + trackH / 2), 24, nowGlow);
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
                    color: t.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: t.muted, fontSize: 13, height: 1.5),
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
                      color: widget.color.withOpacity(0.4),
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
                          color: widget.color.withOpacity(0.6),
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
      final paint = Paint()..color = p.color.withOpacity(1 - localT * 0.4);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(localT * p.spin * 6.28);
      canvas.drawRect(
          Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.5),
          paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) => old.t != t;
}
