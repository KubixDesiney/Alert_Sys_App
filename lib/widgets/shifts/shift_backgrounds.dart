import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../models/shift_model.dart';

/// Live, animated background for a [ShiftCard]. The painter is selected based
/// on [kind]; in dark mode all painters reduce saturation and dim the sky so
/// the card still reads against the dark scaffold.
class ShiftAnimatedBackground extends StatefulWidget {
  final ShiftKind kind;
  final bool isDark;
  final BorderRadius borderRadius;

  const ShiftAnimatedBackground({
    super.key,
    required this.kind,
    required this.isDark,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
  });

  @override
  State<ShiftAnimatedBackground> createState() =>
      _ShiftAnimatedBackgroundState();
}

class _ShiftAnimatedBackgroundState extends State<ShiftAnimatedBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: widget.borderRadius,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (ctx, _) {
          final t = _ctrl.value;
          switch (widget.kind) {
            case ShiftKind.morning:
              return CustomPaint(
                painter: _MorningPainter(t: t, isDark: widget.isDark),
                size: Size.infinite,
              );
            case ShiftKind.afternoon:
              return CustomPaint(
                painter: _AfternoonPainter(t: t, isDark: widget.isDark),
                size: Size.infinite,
              );
            case ShiftKind.night:
              return CustomPaint(
                painter: _NightPainter(t: t, isDark: widget.isDark),
                size: Size.infinite,
              );
          }
        },
      ),
    );
  }
}

double _lerp(double a, double b, double t) => a + (b - a) * t;

// ─────────────────────────── MORNING ─────────────────────────────────────────
class _MorningPainter extends CustomPainter {
  _MorningPainter({required this.t, required this.isDark});
  final double t;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Sky gradient — golden to soft peach.
    final skyTop = isDark
        ? const Color(0xFF1F2A44)
        : const Color(0xFFFFD27A);
    final skyMid = isDark
        ? const Color(0xFF3B2E4B)
        : const Color(0xFFFFB199);
    final skyBot = isDark
        ? const Color(0xFF512A3A)
        : const Color(0xFFFFE3C8);
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [skyTop, skyMid, skyBot],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), paint);

    // Sun moving slowly along an arc.
    final sunCx = _lerp(w * 0.18, w * 0.82, t);
    final sunCy = h * 0.55 - math.sin(t * math.pi) * h * 0.30;
    final sunR = h * 0.18;

    // Rays — pulse subtly.
    final rayPaint = Paint()
      ..color = (isDark ? Colors.amber : const Color(0xFFFFE9A8))
          .withOpacity(isDark ? 0.18 : 0.55);
    final rayCount = 14;
    final rayLen = sunR * (2.4 + math.sin(t * 2 * math.pi) * 0.25);
    for (int i = 0; i < rayCount; i++) {
      final a = (i / rayCount) * 2 * math.pi + t * 0.6;
      final x1 = sunCx + math.cos(a) * sunR * 0.95;
      final y1 = sunCy + math.sin(a) * sunR * 0.95;
      final x2 = sunCx + math.cos(a) * rayLen;
      final y2 = sunCy + math.sin(a) * rayLen;
      rayPaint.strokeWidth = 2.4;
      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), rayPaint);
    }

    // Sun glow.
    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          (isDark ? Colors.amber : const Color(0xFFFFF1B5))
              .withOpacity(isDark ? 0.45 : 0.85),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: Offset(sunCx, sunCy), radius: sunR * 2.2));
    canvas.drawCircle(Offset(sunCx, sunCy), sunR * 2.2, glow);
    final sunPaint = Paint()
      ..color = isDark ? const Color(0xFFFFC36A) : const Color(0xFFFFD370);
    canvas.drawCircle(Offset(sunCx, sunCy), sunR, sunPaint);

    // Birds — three V-shapes drifting.
    final birdPaint = Paint()
      ..color = (isDark ? Colors.white : Colors.black)
          .withOpacity(isDark ? 0.45 : 0.55)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < 3; i++) {
      final progress = ((t + i * 0.33) % 1.0);
      final bx = -20 + progress * (w + 60);
      final by = h * (0.30 + 0.05 * i) + math.sin(t * 2 * math.pi + i) * 4;
      final bw = 14.0;
      final bh = 5.0 + math.sin(t * 4 * math.pi + i) * 2;
      final path = Path()
        ..moveTo(bx, by)
        ..quadraticBezierTo(bx + bw / 2, by - bh, bx + bw, by)
        ..moveTo(bx + bw, by)
        ..quadraticBezierTo(bx + bw * 1.5, by - bh, bx + bw * 2, by);
      canvas.drawPath(path, birdPaint);
    }

    // Soft cloud puff drifting bottom-left → right.
    _drawCloud(
      canvas,
      Offset(_lerp(-w * 0.2, w * 1.1, (t * 0.4) % 1.0), h * 0.22),
      h * 0.06,
      (isDark ? Colors.white : Colors.white).withOpacity(isDark ? 0.18 : 0.65),
    );
    _drawCloud(
      canvas,
      Offset(_lerp(w * 1.1, -w * 0.2, (t * 0.55) % 1.0), h * 0.42),
      h * 0.05,
      (isDark ? Colors.white : Colors.white).withOpacity(isDark ? 0.12 : 0.45),
    );

    // Ground silhouette to anchor the card.
    _drawGround(canvas, w, h, isDark);
  }

  @override
  bool shouldRepaint(covariant _MorningPainter old) => old.t != t;
}

void _drawCloud(Canvas canvas, Offset c, double r, Color color) {
  final p = Paint()..color = color;
  canvas.drawCircle(c, r, p);
  canvas.drawCircle(c.translate(r * 0.9, 0), r * 0.85, p);
  canvas.drawCircle(c.translate(-r * 0.9, 0), r * 0.85, p);
  canvas.drawCircle(c.translate(0, -r * 0.55), r * 0.7, p);
}

void _drawGround(Canvas canvas, double w, double h, bool isDark) {
  final groundPaint = Paint()
    ..color = (isDark ? Colors.black : const Color(0xFF1F2937))
        .withOpacity(isDark ? 0.55 : 0.18);
  final path = Path()..moveTo(0, h);
  path.lineTo(0, h * 0.84);
  path.cubicTo(
      w * 0.18, h * 0.79, w * 0.30, h * 0.86, w * 0.42, h * 0.83);
  path.cubicTo(
      w * 0.55, h * 0.80, w * 0.70, h * 0.88, w * 0.84, h * 0.84);
  path.cubicTo(w * 0.92, h * 0.81, w * 0.97, h * 0.86, w, h * 0.85);
  path.lineTo(w, h);
  path.close();
  canvas.drawPath(path, groundPaint);
}

// ─────────────────────────── AFTERNOON / EVENING ─────────────────────────────
class _AfternoonPainter extends CustomPainter {
  _AfternoonPainter({required this.t, required this.isDark});
  final double t;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: isDark
            ? [
                const Color(0xFF2B1538),
                const Color(0xFF55204A),
                const Color(0xFF8A2547),
              ]
            : [
                const Color(0xFFFF8E5A),
                const Color(0xFFF06292),
                const Color(0xFFFFC093),
              ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), paint);

    // Big setting sun on the right.
    final sunCx = w * 0.75 - math.sin(t * math.pi) * w * 0.05;
    final sunCy = h * (0.62 + math.sin(t * 2 * math.pi) * 0.02);
    final sunR = h * 0.32;
    final sunGlow = Paint()
      ..shader = RadialGradient(
        colors: [
          (isDark ? const Color(0xFFFF6B85) : const Color(0xFFFFD27A))
              .withOpacity(isDark ? 0.6 : 0.95),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: Offset(sunCx, sunCy), radius: sunR * 1.6));
    canvas.drawCircle(Offset(sunCx, sunCy), sunR * 1.6, sunGlow);
    canvas.drawCircle(
      Offset(sunCx, sunCy),
      sunR,
      Paint()..color = isDark ? const Color(0xFFFFB570) : const Color(0xFFFFF1B5),
    );

    // Drifting bands of cloud.
    for (int i = 0; i < 4; i++) {
      final yy = h * (0.20 + i * 0.07);
      final shift = ((t * (0.30 + i * 0.05)) % 1.0);
      final xx = _lerp(-w * 0.3, w * 1.3, shift);
      final cloudColor = (isDark ? Colors.white : Colors.white)
          .withOpacity(isDark ? 0.10 - i * 0.015 : 0.35 - i * 0.05);
      _drawCloud(canvas, Offset(xx, yy), h * (0.045 + i * 0.005), cloudColor);
    }

    // Factory silhouette — smoke stacks with drifting smoke.
    _drawFactorySilhouette(canvas, w, h, isDark, t);
  }

  @override
  bool shouldRepaint(covariant _AfternoonPainter old) => old.t != t;
}

void _drawFactorySilhouette(Canvas canvas, double w, double h, bool isDark, double t) {
  final base = Paint()
    ..color = (isDark ? Colors.black : const Color(0xFF1A1A2E))
        .withOpacity(isDark ? 0.85 : 0.78);

  final path = Path()
    ..moveTo(0, h)
    ..lineTo(0, h * 0.74);
  // First building.
  path
    ..lineTo(w * 0.10, h * 0.74)
    ..lineTo(w * 0.10, h * 0.62)
    ..lineTo(w * 0.18, h * 0.62)
    ..lineTo(w * 0.18, h * 0.74);
  // Stack 1
  path
    ..lineTo(w * 0.22, h * 0.74)
    ..lineTo(w * 0.22, h * 0.40)
    ..lineTo(w * 0.27, h * 0.40)
    ..lineTo(w * 0.27, h * 0.74);
  // Stack 2 (taller)
  path
    ..lineTo(w * 0.32, h * 0.74)
    ..lineTo(w * 0.32, h * 0.34)
    ..lineTo(w * 0.36, h * 0.34)
    ..lineTo(w * 0.36, h * 0.74);
  // Building.
  path
    ..lineTo(w * 0.50, h * 0.74)
    ..lineTo(w * 0.50, h * 0.60)
    ..lineTo(w * 0.65, h * 0.60)
    ..lineTo(w * 0.65, h * 0.74);
  // Stack 3
  path
    ..lineTo(w * 0.70, h * 0.74)
    ..lineTo(w * 0.70, h * 0.46)
    ..lineTo(w * 0.74, h * 0.46)
    ..lineTo(w * 0.74, h * 0.74);
  path
    ..lineTo(w, h * 0.74)
    ..lineTo(w, h)
    ..close();
  canvas.drawPath(path, base);

  // Animated smoke puffs.
  final smokeColor =
      (isDark ? Colors.white : Colors.white).withOpacity(isDark ? 0.16 : 0.55);
  for (int i = 0; i < 3; i++) {
    final stackX = i == 0 ? w * 0.245 : (i == 1 ? w * 0.34 : w * 0.72);
    final stackY = i == 0 ? h * 0.40 : (i == 1 ? h * 0.34 : h * 0.46);
    for (int j = 0; j < 3; j++) {
      final p = ((t + j * 0.33 + i * 0.17) % 1.0);
      final dy = -p * h * 0.30;
      final dx = math.sin((t + i) * math.pi * 2 + j) * 6;
      final r = h * (0.025 + p * 0.04);
      canvas.drawCircle(
        Offset(stackX + dx, stackY + dy),
        r,
        Paint()..color = smokeColor.withOpacity(smokeColor.opacity * (1 - p)),
      );
    }
  }
}

// ─────────────────────────── NIGHT ───────────────────────────────────────────
class _NightPainter extends CustomPainter {
  _NightPainter({required this.t, required this.isDark});
  final double t;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Deep night sky.
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: isDark
            ? [
                const Color(0xFF050818),
                const Color(0xFF0A1136),
                const Color(0xFF14224C),
              ]
            : [
                const Color(0xFF13204C),
                const Color(0xFF1F2E66),
                const Color(0xFF2A3D7E),
              ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), paint);

    // Aurora ribbons — animated wave bands of color.
    _drawAurora(canvas, w, h, t, isDark);

    // Stars — twinkling.
    final starPaint = Paint()..color = Colors.white;
    final rnd = math.Random(7);
    for (int i = 0; i < 60; i++) {
      final sx = rnd.nextDouble() * w;
      final sy = rnd.nextDouble() * h * 0.65;
      final phase = rnd.nextDouble();
      final twinkle =
          0.3 + 0.7 * (0.5 + 0.5 * math.sin((t + phase) * 2 * math.pi));
      final r = 0.7 + rnd.nextDouble() * 1.6;
      starPaint.color = Colors.white.withOpacity(twinkle * 0.85);
      canvas.drawCircle(Offset(sx, sy), r, starPaint);
    }

    // Moon top-right.
    final moonCx = w * 0.78;
    final moonCy = h * 0.26 + math.sin(t * math.pi) * 4;
    final moonR = h * 0.13;
    final moonGlow = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withOpacity(0.55),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: Offset(moonCx, moonCy), radius: moonR * 2.4));
    canvas.drawCircle(Offset(moonCx, moonCy), moonR * 2.4, moonGlow);
    canvas.drawCircle(
      Offset(moonCx, moonCy),
      moonR,
      Paint()..color = const Color(0xFFF5F3E5),
    );
    // Moon crater detail.
    final crater = Paint()..color = const Color(0xFFE0DCC8).withOpacity(0.7);
    canvas.drawCircle(Offset(moonCx - moonR * 0.3, moonCy - moonR * 0.1),
        moonR * 0.15, crater);
    canvas.drawCircle(Offset(moonCx + moonR * 0.25, moonCy + moonR * 0.2),
        moonR * 0.10, crater);

    // Dark factory outline along bottom.
    _drawFactorySilhouette(canvas, w, h, true, t);
  }

  @override
  bool shouldRepaint(covariant _NightPainter old) => old.t != t;
}

void _drawAurora(Canvas canvas, double w, double h, double t, bool isDark) {
  final colors = [
    const Color(0xFF34D399), // teal-green
    const Color(0xFF60A5FA), // blue
    const Color(0xFFC084FC), // purple
  ];
  for (int band = 0; band < 3; band++) {
    final path = Path();
    final yBase = h * (0.20 + band * 0.06);
    path.moveTo(0, yBase);
    final amp = h * 0.04;
    for (double x = 0; x <= w; x += 6) {
      final y = yBase +
          math.sin((x / w) * 4 * math.pi + t * 2 * math.pi + band) * amp +
          math.cos((x / w) * 2 * math.pi - t * math.pi + band * 0.5) * amp * 0.4;
      path.lineTo(x, y);
    }
    path.lineTo(w, yBase + h * 0.08);
    path.lineTo(0, yBase + h * 0.08);
    path.close();
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          colors[band].withOpacity(isDark ? 0.30 : 0.20),
          colors[band].withOpacity(0.0),
        ],
      ).createShader(Rect.fromLTWH(0, yBase, w, h * 0.20));
    canvas.drawPath(path, paint);
  }
}
