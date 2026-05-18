// Elite live presence grid for a shift — replaces the old "ready / not ready"
// chip set with a three-state view (Active / Inactive / Absent) plus the
// "Awaiting confirmation" intermediate state. Subscribes to the per-shift
// presence stream from PresenceService.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/shift_model.dart';
import '../../models/supervisor_presence.dart';
import '../../services/presence_service.dart';
import '../../services/service_locator.dart';
import '../../theme.dart';

class ShiftPresenceGrid extends StatefulWidget {
  final ShiftModel shift;
  final bool isActiveNow;

  const ShiftPresenceGrid({
    super.key,
    required this.shift,
    required this.isActiveNow,
  });

  @override
  State<ShiftPresenceGrid> createState() => _ShiftPresenceGridState();
}

class _ShiftPresenceGridState extends State<ShiftPresenceGrid> {
  StreamSubscription<List<SupervisorPresence>>? _sub;
  List<SupervisorPresence> _rows = const [];
  Timer? _ticker;

  PresenceService get _service => ServiceLocator.instance.presenceService;

  @override
  void initState() {
    super.initState();
    _bind(widget.shift.id);
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant ShiftPresenceGrid old) {
    super.didUpdateWidget(old);
    if (old.shift.id != widget.shift.id) {
      _bind(widget.shift.id);
    }
  }

  void _bind(String shiftId) {
    _sub?.cancel();
    _sub = _service.streamPresence(shiftId).listen((rows) {
      if (!mounted) return;
      setState(() => _rows = rows);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    if (widget.shift.supervisors.isEmpty) {
      return Text('No supervisors assigned to this shift',
          style: TextStyle(color: t.muted, fontSize: 12));
    }

    // Merge roster + presence rows so people without a presence record yet
    // still render as "Awaiting check-in".
    final byId = {for (final r in _rows) r.supervisorId: r};
    final merged = <SupervisorPresence>[];
    for (final s in widget.shift.supervisors) {
      final existing = byId[s.id];
      if (existing != null) {
        merged.add(existing);
      } else {
        merged.add(SupervisorPresence(
          shiftId: widget.shift.id,
          supervisorId: s.id,
          name: s.name,
          factory: s.factory,
          status: widget.isActiveNow
              ? PresenceStatus.pendingConfirm
              : PresenceStatus.absent,
        ));
      }
    }
    merged.sort((a, b) => _statusOrder(a.status).compareTo(_statusOrder(b.status)));

    final activeCount =
        merged.where((m) => m.status == PresenceStatus.active).length;
    final inactiveCount =
        merged.where((m) => m.status == PresenceStatus.inactive).length;
    final absentCount =
        merged.where((m) => m.status == PresenceStatus.absent).length;
    final pendingCount =
        merged.where((m) => m.status == PresenceStatus.pendingConfirm).length;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.scaffold,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _HeaderPill(
                icon: Icons.radar,
                label: 'Shift Commander · Live Presence',
                color: t.navy,
              ),
              const Spacer(),
              if (pendingCount > 0)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _CountBadge(
                    label: 'Awaiting',
                    count: pendingCount,
                    color: t.orange,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                  child: _PresenceCountCard(
                label: 'Active',
                count: activeCount,
                icon: Icons.bolt,
                color: t.green,
              )),
              const SizedBox(width: 8),
              Expanded(
                  child: _PresenceCountCard(
                label: 'Inactive',
                count: inactiveCount,
                icon: Icons.do_not_disturb_on,
                color: t.orange,
              )),
              const SizedBox(width: 8),
              Expanded(
                  child: _PresenceCountCard(
                label: 'Absent',
                count: absentCount,
                icon: Icons.person_off,
                color: t.red,
              )),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final r in merged) _PresenceChip(row: r),
            ],
          ),
        ],
      ),
    );
  }

  static int _statusOrder(PresenceStatus s) {
    switch (s) {
      case PresenceStatus.active:
        return 0;
      case PresenceStatus.pendingConfirm:
        return 1;
      case PresenceStatus.inactive:
        return 2;
      case PresenceStatus.absent:
        return 3;
    }
  }
}

class _HeaderPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _HeaderPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3)),
        ],
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _CountBadge({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text('$label · $count',
          style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4)),
    );
  }
}

class _PresenceCountCard extends StatelessWidget {
  final String label;
  final int count;
  final IconData icon;
  final Color color;
  const _PresenceCountCard({
    required this.label,
    required this.count,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: t.card,
        border: Border.all(color: color.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label.toUpperCase(),
                    style: TextStyle(
                        color: t.muted,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6)),
                Text('$count',
                    style: TextStyle(
                        color: color,
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                        height: 1.0)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PresenceChip extends StatelessWidget {
  final SupervisorPresence row;
  const _PresenceChip({required this.row});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final color = _statusColor(row.status, t);
    final icon = _statusIcon(row.status);
    final duration = row.durationInStatus;
    final durationLabel = duration == null ? null : _humanDuration(duration);

    return Tooltip(
      message: _tooltipFor(row, durationLabel),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          border: Border.all(color: color, width: 1.2),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PulseDot(color: color, pulsing: row.status == PresenceStatus.active),
            const SizedBox(width: 8),
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 5),
            Text(
              row.name.isEmpty ? row.supervisorId : row.name,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 7),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                _shortLabel(row.status),
                style: TextStyle(
                  color: color,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            if (durationLabel != null) ...[
              const SizedBox(width: 6),
              Text('· $durationLabel',
                  style: TextStyle(
                      color: t.muted,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace')),
            ],
          ],
        ),
      ),
    );
  }

  static String _shortLabel(PresenceStatus s) {
    switch (s) {
      case PresenceStatus.active:
        return 'ACTIVE';
      case PresenceStatus.inactive:
        return 'INACTIVE';
      case PresenceStatus.absent:
        return 'ABSENT';
      case PresenceStatus.pendingConfirm:
        return 'AWAITING';
    }
  }

  static IconData _statusIcon(PresenceStatus s) {
    switch (s) {
      case PresenceStatus.active:
        return Icons.bolt;
      case PresenceStatus.inactive:
        return Icons.do_not_disturb_on;
      case PresenceStatus.absent:
        return Icons.person_off;
      case PresenceStatus.pendingConfirm:
        return Icons.hourglass_top;
    }
  }

  static Color _statusColor(PresenceStatus s, AppTheme t) {
    switch (s) {
      case PresenceStatus.active:
        return t.green;
      case PresenceStatus.inactive:
        return t.orange;
      case PresenceStatus.absent:
        return t.red;
      case PresenceStatus.pendingConfirm:
        return t.blue;
    }
  }

  static String _tooltipFor(SupervisorPresence row, String? duration) {
    final buf = StringBuffer('${row.name} · ${row.statusLabel}');
    if (duration != null) buf.write(' · for $duration');
    if (row.factory.isNotEmpty) buf.write('\nFactory: ${row.factory}');
    if (row.lastActiveAt != null) {
      buf.write('\nLast activity: ${_fmtTime(row.lastActiveAt!)}');
    }
    if (row.status == PresenceStatus.pendingConfirm &&
        row.confirmExpiresAt != null) {
      buf.write('\nConfirm window expires at ${_fmtTime(row.confirmExpiresAt!)}');
    }
    return buf.toString();
  }

  static String _fmtTime(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

String _humanDuration(Duration d) {
  if (d.inMinutes < 1) return '${d.inSeconds}s';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  final h = d.inHours;
  final m = d.inMinutes % 60;
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

class _PulseDot extends StatefulWidget {
  final Color color;
  final bool pulsing;
  const _PulseDot({required this.color, required this.pulsing});

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    if (widget.pulsing) _ctrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _PulseDot old) {
    super.didUpdateWidget(old);
    if (widget.pulsing && !_ctrl.isAnimating) {
      _ctrl.repeat(reverse: true);
    } else if (!widget.pulsing && _ctrl.isAnimating) {
      _ctrl.stop();
    }
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
        final glow = widget.pulsing ? 4 + 4 * _ctrl.value : 0.0;
        return Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
            boxShadow: [
              if (widget.pulsing)
                BoxShadow(
                  color: widget.color.withValues(alpha: 0.55),
                  blurRadius: glow,
                  spreadRadius: glow / 6,
                ),
            ],
          ),
        );
      },
    );
  }
}
