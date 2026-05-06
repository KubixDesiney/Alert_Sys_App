import 'package:flutter/material.dart';

import '../../models/shift_model.dart';
import '../../theme.dart';
import 'shift_backgrounds.dart';

/// A beautiful, animated card representing one shift on the Schedule tab.
class ShiftCard extends StatefulWidget {
  final ShiftModel shift;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onViewLogs;
  final bool isActiveNow;

  const ShiftCard({
    super.key,
    required this.shift,
    this.onTap,
    this.onLongPress,
    this.onViewLogs,
    this.isActiveNow = false,
  });

  @override
  State<ShiftCard> createState() => _ShiftCardState();
}

class _ShiftCardState extends State<ShiftCard> with SingleTickerProviderStateMixin {
  late AnimationController _hoverCtrl;
  bool _hovering = false;

  @override
  void initState() {
    super.initState();
    _hoverCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
  }

  @override
  void dispose() {
    _hoverCtrl.dispose();
    super.dispose();
  }

  void _setHover(bool v) {
    setState(() => _hovering = v);
    if (v) {
      _hoverCtrl.forward();
    } else {
      _hoverCtrl.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final isDark = context.isDark;
    final s = widget.shift;

    return MouseRegion(
      onEnter: (_) => _setHover(true),
      onExit: (_) => _setHover(false),
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: AnimatedScale(
          scale: _hovering ? 1.015 : 1.0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: (isDark ? Colors.black : Colors.black26)
                      .withValues(alpha: _hovering ? 0.32 : 0.18),
                  blurRadius: _hovering ? 22 : 14,
                  offset: const Offset(0, 6),
                ),
              ],
              border: Border.all(
                color: widget.isActiveNow
                    ? t.green.withValues(alpha: 0.85)
                    : t.border,
                width: widget.isActiveNow ? 2 : 1,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: AspectRatio(
                aspectRatio: 1.65,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ShiftAnimatedBackground(kind: s.kind, isDark: isDark),
                    // Foreground gradient veil for text contrast.
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.black.withValues(alpha: isDark ? 0.30 : 0.10),
                            Colors.black.withValues(alpha: isDark ? 0.55 : 0.30),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Badges row — FittedBox scales it down if needed, keeping single-row height.
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _ShiftKindChip(kind: s.kind),
                                if (widget.isActiveNow) ...[
                                  const SizedBox(width: 6),
                                  _LivePulseBadge(color: t.green),
                                ],
                                if (s.aiCommander) ...[
                                  const SizedBox(width: 6),
                                  _AiBadge(),
                                ],
                              ],
                            ),
                          ),
                          const Spacer(),
                          Text(
                            s.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.schedule,
                                  color: Colors.white70, size: 12),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  s.timeRangeLabel,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 11,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _SupervisorAvatars(
                            sups: s.supervisors,
                            max: 5,
                            extra: s.supervisors.length > 5
                                ? s.supervisors.length - 5
                                : 0,
                          ),
                        ],
                      ),
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

class _ShiftKindChip extends StatelessWidget {
  final ShiftKind kind;
  const _ShiftKindChip({required this.kind});

  @override
  Widget build(BuildContext context) {
    final label = switch (kind) {
      ShiftKind.morning => 'Morning',
      ShiftKind.afternoon => 'Evening',
      ShiftKind.night => 'Night',
    };
    final icon = switch (kind) {
      ShiftKind.morning => Icons.wb_sunny,
      ShiftKind.afternoon => Icons.wb_twilight,
      ShiftKind.night => Icons.nights_stay,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.white.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 13),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _AiBadge extends StatefulWidget {
  @override
  State<_AiBadge> createState() => _AiBadgeState();
}

class _AiBadgeState extends State<_AiBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
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
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color.lerp(const Color(0xFF60A5FA), const Color(0xFFC084FC), t)!,
                Color.lerp(const Color(0xFFC084FC), const Color(0xFF60A5FA), t)!,
              ],
            ),
            borderRadius: BorderRadius.circular(99),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF60A5FA).withValues(alpha: 0.55),
                blurRadius: 8 + 4 * t,
                spreadRadius: 0.5,
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome, color: Colors.white, size: 12),
              SizedBox(width: 4),
              Text(
                'AI Commander',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LivePulseBadge extends StatefulWidget {
  final Color color;
  const _LivePulseBadge({required this.color});

  @override
  State<_LivePulseBadge> createState() => _LivePulseBadgeState();
}

class _LivePulseBadgeState extends State<_LivePulseBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
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
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: widget.color,
            borderRadius: BorderRadius.circular(99),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.4 + 0.4 * _ctrl.value),
                blurRadius: 6 + 6 * _ctrl.value,
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.fiber_manual_record, color: Colors.white, size: 10),
              SizedBox(width: 4),
              Text(
                'LIVE',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SupervisorAvatars extends StatelessWidget {
  final List<AssignedSupervisor> sups;
  final int max;
  final int extra;
  const _SupervisorAvatars({
    required this.sups,
    required this.max,
    required this.extra,
  });

  @override
  Widget build(BuildContext context) {
    if (sups.isEmpty) {
      return Row(
        children: [
          Icon(Icons.person_off,
              color: Colors.white.withValues(alpha: 0.7), size: 14),
          const SizedBox(width: 6),
          const Text(
            'No supervisors yet',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }

    final visible = sups.take(max).toList();
    return SizedBox(
      height: 30,
      child: Stack(
        children: [
          for (int i = 0; i < visible.length; i++)
            Positioned(
              left: i * 22.0,
              child: _AvatarChip(s: visible[i]),
            ),
          if (extra > 0)
            Positioned(
              left: visible.length * 22.0,
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.20),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.55), width: 2),
                ),
                child: Center(
                  child: Text(
                    '+$extra',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AvatarChip extends StatelessWidget {
  final AssignedSupervisor s;
  const _AvatarChip({required this.s});

  @override
  Widget build(BuildContext context) {
    final colors = [
      const Color(0xFF60A5FA),
      const Color(0xFFC084FC),
      const Color(0xFF34D399),
      const Color(0xFFFBBF24),
      const Color(0xFFF87171),
    ];
    final color = colors[s.id.hashCode.abs() % colors.length];
    return Tooltip(
      message: '${s.name} • ${s.factory}',
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            if (s.ready)
              BoxShadow(
                color: const Color(0xFF22C55E).withValues(alpha: 0.7),
                blurRadius: 6,
                spreadRadius: 0.5,
              ),
          ],
        ),
        child: Center(
          child: Text(
            s.initials,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}
