import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'superadmin_theme.dart';

/// SuperAdmin tab 4: hardware fleet management.
///
/// Reserved surface — the IoT gateway, PLC bridge and edge-device telemetry
/// integrations will land here. Intentionally empty for now.
class HardwareTab extends StatelessWidget {
  const HardwareTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: GlassPanel(
          padding: const EdgeInsets.all(40),
          accent: Sa.violet,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _RadarSweep(),
              const SizedBox(height: 24),
              Text('HARDWARE FLEET', style: Sa.display(size: 18)),
              const SizedBox(height: 10),
              Text(
                'This module is reserved for the upcoming hardware integration: '
                'edge gateways, PLC bridges, sensor health and firmware '
                'rollouts will be commanded from here.',
                textAlign: TextAlign.center,
                style: Sa.body(size: 13, color: Sa.textDim),
              ),
              const SizedBox(height: 18),
              const GlowChip(
                label: 'AWAITING FIRST DEVICE',
                color: Sa.violet,
                pulse: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Decorative radar sweep animation.
class _RadarSweep extends StatefulWidget {
  const _RadarSweep();

  @override
  State<_RadarSweep> createState() => _RadarSweepState();
}

class _RadarSweepState extends State<_RadarSweep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 4))
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
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => CustomPaint(
          size: const Size(140, 140),
          painter: _RadarPainter(_c.value),
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  final double t;
  _RadarPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    for (var i = 1; i <= 3; i++) {
      canvas.drawCircle(
        center,
        radius * i / 3,
        Paint()
          ..color = Sa.violet.withValues(alpha: 0.18)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
    canvas.drawLine(
      Offset(center.dx - radius, center.dy),
      Offset(center.dx + radius, center.dy),
      Paint()..color = Sa.violet.withValues(alpha: 0.12),
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - radius),
      Offset(center.dx, center.dy + radius),
      Paint()..color = Sa.violet.withValues(alpha: 0.12),
    );

    final sweepAngle = t * math.pi * 2;
    final sweep = Paint()
      ..shader = SweepGradient(
        startAngle: sweepAngle - 1.1,
        endAngle: sweepAngle,
        colors: [
          Sa.violet.withValues(alpha: 0),
          Sa.violet.withValues(alpha: 0.45),
        ],
        transform: GradientRotation(0),
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawPath(
      Path()
        ..moveTo(center.dx, center.dy)
        ..arcTo(
          Rect.fromCircle(center: center, radius: radius),
          sweepAngle - 1.1,
          1.1,
          false,
        )
        ..close(),
      sweep,
    );

    canvas.drawCircle(center, 3, Paint()..color = Sa.violet);
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) => oldDelegate.t != t;
}
