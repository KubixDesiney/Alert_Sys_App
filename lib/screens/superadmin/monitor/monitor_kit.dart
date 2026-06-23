import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../l10n/app_strings.dart';
import '../superadmin_theme.dart';
import 'monitor_data.dart';

/// Shared visual language for the Overview Monitor — a holographic command
/// deck. Everything here is theme-aware ([Sa] tokens) and motion is capped +
/// wrapped in [RepaintBoundary]s so the war-room scrolls glass-smooth.

Color liveColor(LiveState s) => switch (s) {
      LiveState.online => Sa.green,
      LiveState.idle => Sa.amber,
      LiveState.offline => Sa.red,
      LiveState.unknown => Sa.muted,
    };

String liveLabel(BuildContext context, LiveState s) => switch (s) {
      LiveState.online => context.tr('ONLINE'),
      LiveState.idle => context.tr('IDLE'),
      LiveState.offline => context.tr('OFFLINE'),
      LiveState.unknown => context.tr('NO DATA'),
    };

/// A premium HUD panel: gradient hairline frame, soft drop shadow and painted
/// corner brackets with a slow travelling scan-line — the surface every
/// war-room section sits on.
class HoloPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? accent;
  final bool glow;

  const HoloPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.accent,
    this.glow = false,
  });

  @override
  Widget build(BuildContext context) {
    final a = accent ?? Sa.cyan;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            a.withValues(alpha: glow ? 0.55 : 0.28),
            Sa.border,
            a.withValues(alpha: glow ? 0.24 : 0.06),
          ],
        ),
        boxShadow: [
          if (glow)
            BoxShadow(
              color: a.withValues(alpha: Sa.isDark ? 0.16 : 0.18),
              blurRadius: 30,
              spreadRadius: 1,
            ),
          BoxShadow(color: Sa.shadow, blurRadius: 20, offset: const Offset(0, 9)),
        ],
      ),
      padding: const EdgeInsets.all(1),
      child: CustomPaint(
        foregroundPainter: _HoloFramePainter(a),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Sa.panel,
            borderRadius: BorderRadius.circular(17),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _HoloFramePainter extends CustomPainter {
  final Color accent;
  _HoloFramePainter(this.accent);

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 9.0;
    const len = 18.0;
    final p = Paint()
      ..color = accent.withValues(alpha: 0.7)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    // Four corner brackets.
    void bracket(Offset o, int sx, int sy) {
      canvas.drawLine(o, o.translate(len * sx, 0), p);
      canvas.drawLine(o, o.translate(0, len * sy), p);
    }

    bracket(const Offset(inset, inset), 1, 1);
    bracket(Offset(size.width - inset, inset), -1, 1);
    bracket(Offset(inset, size.height - inset), 1, -1);
    bracket(Offset(size.width - inset, size.height - inset), -1, -1);
  }

  @override
  bool shouldRepaint(covariant _HoloFramePainter old) => old.accent != accent;
}

/// War-room section title — Orbitron heading with an accent tile, subtitle and
/// optional trailing controls.
class HoloHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color accent;
  final Widget? trailing;

  const HoloHeader({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.accent,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [accent.withValues(alpha: 0.3), accent.withValues(alpha: 0.05)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: accent.withValues(alpha: 0.5)),
            boxShadow: [
              BoxShadow(color: accent.withValues(alpha: 0.18), blurRadius: 14),
            ],
          ),
          child: Icon(icon, color: accent, size: 19),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Sa.display(size: 14)),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!, style: Sa.body(size: 11.5, color: Sa.textDim)),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// Big glowing numeric readout with an animated count-up — the headline KPIs of
/// the command strip.
class KpiReadout extends StatelessWidget {
  final IconData icon;
  final String label;
  final num value;
  final String? suffix;
  final String? sub;
  final Color accent;
  final bool pulse;

  const KpiReadout({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
    this.suffix,
    this.sub,
    this.pulse = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: Sa.isDark ? 0.12 : 0.10),
            Sa.bgRaised.withValues(alpha: Sa.isDark ? 0.65 : 0.92),
          ],
        ),
        border: Border.all(color: accent.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(color: accent.withValues(alpha: 0.12), blurRadius: 18),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: accent),
              const SizedBox(width: 7),
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Sa.mono(size: 9, color: Sa.muted, weight: FontWeight.w700)),
              ),
              if (pulse) PulseDot(color: accent, size: 6),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: value.toDouble()),
                duration: const Duration(milliseconds: 850),
                curve: Curves.easeOutCubic,
                builder: (_, v, __) => Text(
                  value is int || value == value.roundToDouble()
                      ? v.round().toString()
                      : v.toStringAsFixed(1),
                  style: Sa.display(size: 26, color: Sa.text),
                ),
              ),
              if (suffix != null) ...[
                const SizedBox(width: 3),
                Text(suffix!, style: Sa.heading(size: 13, color: accent)),
              ],
            ],
          ),
          if (sub != null) ...[
            const SizedBox(height: 3),
            Text(sub!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Sa.mono(size: 9.5, color: Sa.textDim)),
          ],
        ],
      ),
    );
  }
}

/// Circular ring gauge with an animated sweep and a glowing leading tip.
class RingGauge extends StatelessWidget {
  final double value; // 0..1
  final Color accent;
  final double size;
  final String center;
  final String? caption;

  const RingGauge({
    super.key,
    required this.value,
    required this.accent,
    this.size = 96,
    required this.center,
    this.caption,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.clamp(0, 1)),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        builder: (_, v, __) => CustomPaint(
          painter: _RingPainter(v, accent),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(center, style: Sa.display(size: size * 0.20, color: Sa.text)),
                if (caption != null)
                  Text(caption!,
                      style: Sa.mono(size: size * 0.085, color: Sa.muted)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double v;
  final Color accent;
  _RingPainter(this.v, this.accent);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 7;
    const start = -math.pi / 2;
    final sweep = v * math.pi * 2;

    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = Sa.border
        ..strokeWidth = 6
        ..style = PaintingStyle.stroke,
    );
    final grad = SweepGradient(
      startAngle: start,
      endAngle: start + math.pi * 2,
      colors: [accent.withValues(alpha: 0.35), accent, accent],
      stops: const [0, 0.6, 1],
      transform: const GradientRotation(-math.pi / 2),
    );
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      start,
      sweep,
      false,
      Paint()
        ..shader = grad.createShader(Rect.fromCircle(center: c, radius: r))
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.6),
    );
    // Glowing leading tip.
    if (v > 0.001) {
      final tip = Offset(
        c.dx + r * math.cos(start + sweep),
        c.dy + r * math.sin(start + sweep),
      );
      canvas.drawCircle(tip, 4.5, Paint()..color = accent);
      canvas.drawCircle(
          tip, 9, Paint()..color = accent.withValues(alpha: 0.25));
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.v != v || old.accent != accent;
}

/// An ECG-style heartbeat strip — beats while a worker is live, flatlines when
/// it goes dark.
class Heartbeat extends StatefulWidget {
  final LiveState state;
  final double height;
  const Heartbeat({super.key, required this.state, this.height = 34});

  @override
  State<Heartbeat> createState() => _HeartbeatState();
}

class _HeartbeatState extends State<Heartbeat>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 3))
      ..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: CustomPaint(
          painter: _HeartbeatPainter(_c, liveColor(widget.state),
              alive: widget.state == LiveState.online ||
                  widget.state == LiveState.idle),
        ),
      ),
    );
  }
}

class _HeartbeatPainter extends CustomPainter {
  final Animation<double> t;
  final Color color;
  final bool alive;
  _HeartbeatPainter(this.t, this.color, {required this.alive})
      : super(repaint: t);

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height / 2;
    final path = Path()..moveTo(0, mid);
    const beats = 2;
    final span = size.width / beats;
    for (var b = 0; b < beats; b++) {
      final x0 = b * span;
      // Baseline then a sharp QRS spike.
      path.lineTo(x0 + span * 0.34, mid);
      if (alive) {
        path.lineTo(x0 + span * 0.40, mid - size.height * 0.10);
        path.lineTo(x0 + span * 0.46, mid + size.height * 0.42);
        path.lineTo(x0 + span * 0.52, mid - size.height * 0.46);
        path.lineTo(x0 + span * 0.58, mid + size.height * 0.12);
        path.lineTo(x0 + span * 0.64, mid);
      }
      path.lineTo(x0 + span, mid);
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: 0.85)
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 0.5),
    );

    if (!alive) return;
    // A sweeping scan glow that rides the trace.
    final sx = t.value * size.width;
    final glow = Rect.fromLTWH(sx - 26, 0, 52, size.height);
    canvas.drawRect(
      glow,
      Paint()
        ..shader = LinearGradient(
          colors: [
            color.withValues(alpha: 0),
            color.withValues(alpha: 0.28),
            color.withValues(alpha: 0),
          ],
        ).createShader(glow),
    );
  }

  @override
  bool shouldRepaint(covariant _HeartbeatPainter old) =>
      old.color != color || old.alive != alive;
}

/// Small status pip + label for a [LiveState].
class StatePip extends StatelessWidget {
  final LiveState state;
  final String? labelOverride;
  const StatePip({super.key, required this.state, this.labelOverride});

  @override
  Widget build(BuildContext context) {
    final c = liveColor(state);
    final live = state == LiveState.online;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (live)
          PulseDot(color: c, size: 7)
        else
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          ),
        const SizedBox(width: 6),
        Text(labelOverride ?? liveLabel(context, state),
            style: Sa.mono(size: 9.5, color: c, weight: FontWeight.w700)),
      ],
    );
  }
}
