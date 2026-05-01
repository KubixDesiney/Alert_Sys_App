// lib/widgets/locator_painter.dart
//
// Renders the FactoryMap (entrance, conveyor edges, station nodes) on the
// supervisor's locator screen. When `claimedNodeKey` is set, draws an animated
// blue arrow from the entrance to that node along the saved edge graph (BFS
// fallback to straight line) and pulses the target station.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/factory_map_model.dart';
import '../screens/factory_mapping_tab.dart' show factoryMapConveyorColor;
import '../theme.dart';

enum LocatorNodeStatus { idle, available, inProgress, resolved, critical }

class LocatorNodeBadge {
  final String key;
  final LocatorNodeStatus status;
  final int? alertNumber;
  final String? assetLabel;
  const LocatorNodeBadge({
    required this.key,
    required this.status,
    this.alertNumber,
    this.assetLabel,
  });
}

class FactoryMapLocatorPainter extends CustomPainter {
  final FactoryMap map;
  final AppTheme theme;
  final bool isDark;
  final Map<String, LocatorNodeBadge> badges;
  final String? claimedNodeKey;
  final double pulse;

  FactoryMapLocatorPainter({
    required this.map,
    required this.theme,
    required this.isDark,
    required this.badges,
    required this.claimedNodeKey,
    required this.pulse,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cellSize = math.min(size.width / map.cols, size.height / map.rows);
    final ox = (size.width - cellSize * map.cols) / 2;
    final oy = (size.height - cellSize * map.rows) / 2;

    _drawSurface(canvas, size, ox, oy, cellSize);
    _drawGrid(canvas, ox, oy, cellSize);
    _drawEdges(canvas, ox, oy, cellSize);
    _drawRoute(canvas, ox, oy, cellSize);
    _drawEntrance(canvas, ox, oy, cellSize);
    _drawNodes(canvas, ox, oy, cellSize);
  }

  Offset _center(MapCell cell, double ox, double oy, double s) =>
      Offset(ox + cell.col * s + s / 2, oy + cell.row * s + s / 2);

  void _drawSurface(
      Canvas canvas, Size size, double ox, double oy, double s) {
    final paint = Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        Offset(size.width, size.height),
        [
          isDark ? const Color(0xFF111C32) : const Color(0xFFF4F7FB),
          isDark ? const Color(0xFF0B1322) : const Color(0xFFE8EEF7),
        ],
      );
    canvas.drawRect(Offset.zero & size, paint);
    final floor = Rect.fromLTWH(ox, oy, s * map.cols, s * map.rows);
    canvas.drawRRect(
      RRect.fromRectAndRadius(floor, const Radius.circular(12)),
      Paint()..color = theme.card.withValues(alpha: 0.62),
    );
  }

  void _drawGrid(Canvas canvas, double ox, double oy, double s) {
    final paint = Paint()
      ..color = theme.border.withValues(alpha: isDark ? 0.22 : 0.40)
      ..strokeWidth = 0.5;
    for (var c = 0; c <= map.cols; c++) {
      canvas.drawLine(
          Offset(ox + c * s, oy), Offset(ox + c * s, oy + map.rows * s), paint);
    }
    for (var r = 0; r <= map.rows; r++) {
      canvas.drawLine(
          Offset(ox, oy + r * s), Offset(ox + map.cols * s, oy + r * s), paint);
    }
  }

  void _drawEdges(Canvas canvas, double ox, double oy, double s) {
    for (final edge in map.edges) {
      final from = map.nodeByKey(edge.fromKey);
      final to = map.nodeByKey(edge.toKey);
      if (from == null || to == null) continue;
      final color = factoryMapConveyorColor(edge.conveyorNumber, theme);
      final p1 = _center(from.cell, ox, oy, s);
      final p2 = _center(to.cell, ox, oy, s);
      canvas.drawLine(
        p1,
        p2,
        Paint()
          ..color = color.withValues(alpha: isDark ? 0.20 : 0.18)
          ..strokeWidth = 14
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke,
      );
      canvas.drawLine(
        p1,
        p2,
        Paint()
          ..color = color
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke,
      );
    }
  }

  void _drawEntrance(Canvas canvas, double ox, double oy, double s) {
    final cell = map.entrance;
    if (cell == null) return;
    final c = _center(cell, ox, oy, s);
    final size = s * 0.72;
    final rect = Rect.fromCenter(center: c, width: size, height: size);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(10)),
      Paint()..color = theme.green,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.inflate(3), const Radius.circular(12)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = theme.green.withValues(alpha: 0.5),
    );
    final tp = TextPainter(
      text: const TextSpan(text: '🏭', style: TextStyle(fontSize: 16)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  void _drawNodes(Canvas canvas, double ox, double oy, double s) {
    for (final node in map.nodes) {
      final c = _center(node.cell, ox, oy, s);
      final color = factoryMapConveyorColor(node.conveyorNumber, theme);
      final radius = s * 0.32;
      final isTarget = claimedNodeKey == node.key;
      final badge = badges[node.key];
      final statusColor = badge == null
          ? color
          : _statusColor(badge.status, theme, fallback: color);

      if (isTarget) {
        final ring = radius + 10 + math.sin(pulse * math.pi * 2) * 6;
        canvas.drawCircle(
          c,
          ring,
          Paint()..color = theme.blue.withValues(alpha: 0.18),
        );
        canvas.drawCircle(
          c,
          radius + 6,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5
            ..color = theme.blue,
        );
      } else if (badge != null && badge.status != LocatorNodeStatus.idle) {
        canvas.drawCircle(
          c,
          radius + 5,
          Paint()..color = statusColor.withValues(alpha: 0.14),
        );
      }

      canvas.drawCircle(c, radius, Paint()..color = isTarget ? theme.blue : statusColor);
      canvas.drawCircle(
        c,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = theme.card,
      );
      final tp = TextPainter(
        text: TextSpan(
          text: node.label,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 9.5,
              fontWeight: FontWeight.w900),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    }
  }

  void _drawRoute(Canvas canvas, double ox, double oy, double s) {
    final entrance = map.entrance;
    final target = claimedNodeKey;
    if (entrance == null || target == null) return;
    final targetNode = map.nodeByKey(target);
    if (targetNode == null) return;

    final pathCells = _findRoute(entrance, targetNode);
    final points = <Offset>[
      _center(entrance, ox, oy, s),
      ...pathCells.map((cell) => _center(cell, ox, oy, s)),
    ];
    if (points.length < 2) {
      points
        ..clear()
        ..add(_center(entrance, ox, oy, s))
        ..add(_center(targetNode.cell, ox, oy, s));
    }

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = theme.blue.withValues(alpha: 0.25)
        ..strokeWidth = 16
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );
    _drawDashed(
      canvas,
      path,
      Paint()
        ..color = theme.blue
        ..strokeWidth = 4.5
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
      dash: 16,
      gap: 9,
      phase: pulse * 30,
    );

    // Arrow head
    final tail = points[points.length - 2];
    final head = points.last;
    final angle = math.atan2(head.dy - tail.dy, head.dx - tail.dx);
    _drawArrowHead(canvas, head, angle, theme.blue);

    // Travelling pip
    final metrics = path.computeMetrics().toList();
    if (metrics.isNotEmpty) {
      final m = metrics.first;
      final t = m.getTangentForOffset(m.length * pulse);
      if (t != null) {
        canvas.drawCircle(
            t.position, 12, Paint()..color = theme.blue.withValues(alpha: 0.25));
        canvas.drawCircle(t.position, 6, Paint()..color = theme.blue);
      }
    }
  }

  /// BFS over the saved edge graph from the cell containing the entrance to
  /// the target node. Returns the cells of intermediate nodes (target last).
  /// Falls back to an empty list (caller draws straight line) if disconnected.
  List<MapCell> _findRoute(MapCell entrance, MapNode target) {
    // The entrance is a free-floating cell, not a node, so we connect it to
    // its nearest node and BFS from there.
    if (map.nodes.isEmpty) return [];
    MapNode nearestToEntrance = map.nodes.first;
    double best = double.infinity;
    for (final n in map.nodes) {
      final dx = (n.cell.col - entrance.col).toDouble();
      final dy = (n.cell.row - entrance.row).toDouble();
      final d = dx * dx + dy * dy;
      if (d < best) {
        best = d;
        nearestToEntrance = n;
      }
    }
    if (nearestToEntrance.key == target.key) {
      return [target.cell];
    }
    final adjacency = <String, List<String>>{};
    for (final e in map.edges) {
      adjacency.putIfAbsent(e.fromKey, () => []).add(e.toKey);
      adjacency.putIfAbsent(e.toKey, () => []).add(e.fromKey);
    }
    final prev = <String, String?>{nearestToEntrance.key: null};
    final queue = <String>[nearestToEntrance.key];
    while (queue.isNotEmpty) {
      final cur = queue.removeAt(0);
      if (cur == target.key) break;
      for (final next in adjacency[cur] ?? const <String>[]) {
        if (prev.containsKey(next)) continue;
        prev[next] = cur;
        queue.add(next);
      }
    }
    if (!prev.containsKey(target.key)) {
      // Disconnected: at least connect entrance → nearest → target.
      return [nearestToEntrance.cell, target.cell];
    }
    final stack = <MapCell>[];
    String? cursor = target.key;
    while (cursor != null) {
      final n = map.nodeByKey(cursor);
      if (n != null) stack.insert(0, n.cell);
      cursor = prev[cursor];
    }
    return stack;
  }

  void _drawArrowHead(Canvas canvas, Offset tip, double angle, Color color) {
    const size = 16.0;
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(
        tip.dx - math.cos(angle - math.pi / 6) * size,
        tip.dy - math.sin(angle - math.pi / 6) * size,
      )
      ..lineTo(
        tip.dx - math.cos(angle + math.pi / 6) * size,
        tip.dy - math.sin(angle + math.pi / 6) * size,
      )
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  void _drawDashed(Canvas canvas, Path path, Paint paint,
      {required double dash, required double gap, required double phase}) {
    for (final m in path.computeMetrics()) {
      var d = -phase % (dash + gap);
      while (d < m.length) {
        final start = d.clamp(0.0, m.length).toDouble();
        final end = (d + dash).clamp(0.0, m.length).toDouble();
        if (end > start) canvas.drawPath(m.extractPath(start, end), paint);
        d += dash + gap;
      }
    }
  }

  Color _statusColor(LocatorNodeStatus s, AppTheme t, {required Color fallback}) {
    return switch (s) {
      LocatorNodeStatus.critical => t.red,
      LocatorNodeStatus.available => t.orange,
      LocatorNodeStatus.inProgress => t.blue,
      LocatorNodeStatus.resolved => t.green,
      LocatorNodeStatus.idle => fallback,
    };
  }

  @override
  bool shouldRepaint(covariant FactoryMapLocatorPainter old) =>
      old.map != map ||
      old.pulse != pulse ||
      old.claimedNodeKey != claimedNodeKey ||
      old.isDark != isDark ||
      old.badges.length != badges.length;
}
