part of 'shifts_tab.dart';

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
        title: context.tr('No timeline yet'),
        message: context.tr(
            'Once you create shifts, they\'ll appear here as colored blocks across a 24-hour timeline. The pulsing line shows the current time.'),
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
                context.tr('24-hour timeline'),
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
              _legendDot(const Color(0xFFFCD34D), context.tr('Morning')),
              _legendDot(const Color(0xFFFB923C), context.tr('Evening')),
              _legendDot(const Color(0xFF6366F1), context.tr('Night')),
              _legendDot(t.green, context.tr('Now')),
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
      label: Text(context.tr('AI logs')),
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
