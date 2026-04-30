import 'package:flutter/material.dart';

/// Anchor pair for one parent → child branch. Coordinates are in the local
/// coordinate space of the connector layer (a SizedBox sandwiched between two
/// layers of the tree).
class TreeConnectorEdge {
  final Offset from;
  final Offset to;
  final bool active; // true if the branch contains active alerts
  const TreeConnectorEdge({
    required this.from,
    required this.to,
    this.active = false,
  });
}

/// Paints curved cubic Bezier connectors between a parent node and its
/// children. Uses [inactive] color for normal branches and [active] color for
/// branches containing live alerts. When [flowPhase] is non-zero, draws a
/// subtle flowing dashed overlay on active branches (driven by an external
/// AnimationController).
class BezierConnectorPainter extends CustomPainter {
  final List<TreeConnectorEdge> edges;
  final Color inactive;
  final Color active;
  final double flowPhase; // 0..1, animated externally
  final double strokeWidth;

  BezierConnectorPainter({
    required this.edges,
    required this.inactive,
    required this.active,
    this.flowPhase = 0,
    this.strokeWidth = 1.6,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final e in edges) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..color = e.active ? active : inactive
        ..strokeWidth = e.active ? strokeWidth + 0.4 : strokeWidth;

      final path = _bezier(e.from, e.to);
      canvas.drawPath(path, paint);

      if (e.active && flowPhase > 0) {
        _drawFlow(canvas, path, e);
      }
    }
  }

  Path _bezier(Offset from, Offset to) {
    final dy = (to.dy - from.dy);
    // Smooth S-shape: control points pulled vertically so curves are
    // pleasant even when from.x == to.x.
    final c1 = Offset(from.dx, from.dy + dy * 0.55);
    final c2 = Offset(to.dx, to.dy - dy * 0.55);
    return Path()
      ..moveTo(from.dx, from.dy)
      ..cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, to.dx, to.dy);
  }

  void _drawFlow(Canvas canvas, Path path, TreeConnectorEdge e) {
    // Walk the path and draw a few short dashes at progressing offsets to
    // create a subtle "data flowing" effect along active branches.
    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;
    final m = metrics.first;
    const dashLength = 6.0;
    const gapLength = 14.0;
    final period = dashLength + gapLength;
    final phaseOffset = (flowPhase * period) % period;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..color = active.withValues(alpha: 0.95)
      ..strokeWidth = strokeWidth + 0.6;

    double t = -phaseOffset;
    while (t < m.length) {
      final start = t.clamp(0, m.length).toDouble();
      final end = (t + dashLength).clamp(0, m.length).toDouble();
      if (end > start) {
        canvas.drawPath(m.extractPath(start, end), paint);
      }
      t += period;
    }
  }

  @override
  bool shouldRepaint(covariant BezierConnectorPainter old) =>
      old.edges != edges ||
      old.inactive != inactive ||
      old.active != active ||
      old.flowPhase != flowPhase ||
      old.strokeWidth != strokeWidth;
}
