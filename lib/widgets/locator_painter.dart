// lib/widgets/locator_painter.dart
//
// Renders the FactoryMap (entrance, conveyor edges, station nodes) on the
// supervisor's locator screen. When `claimedNodeKey` is set, draws an animated
// blue arrow from the entrance to that node along a grid route that avoids
// conveyor lines and station nodes, then pulses the target station.

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

const _routeDirections = <_RouteDelta>[
  _RouteDelta(-1, 0),
  _RouteDelta(0, 1),
  _RouteDelta(1, 0),
  _RouteDelta(0, -1),
];

class _RouteDelta {
  final int row;
  final int col;

  const _RouteDelta(this.row, this.col);

  @override
  bool operator ==(Object other) =>
      other is _RouteDelta && other.row == row && other.col == col;

  @override
  int get hashCode => Object.hash(row, col);
}

class _RouteState {
  final MapCell cell;
  final int direction;
  final double cost;
  final double priority;

  const _RouteState(this.cell, this.direction, this.cost, this.priority);
}

class FactoryMapLocatorPainter extends CustomPainter {
  final FactoryMap map;
  final AppTheme theme;
  final bool isDark;
  final Map<String, LocatorNodeBadge> badges;
  final String? claimedNodeKey;
  final MapCell? routeStart;
  final double pulse;

  FactoryMapLocatorPainter({
    required this.map,
    required this.theme,
    required this.isDark,
    required this.badges,
    required this.claimedNodeKey,
    required this.routeStart,
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
    _drawCurrentPosition(canvas, ox, oy, cellSize);
    _drawNodes(canvas, ox, oy, cellSize);
  }

  Offset _center(MapCell cell, double ox, double oy, double s) =>
      Offset(ox + cell.col * s + s / 2, oy + cell.row * s + s / 2);

  void _drawSurface(Canvas canvas, Size size, double ox, double oy, double s) {
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

  void _drawCurrentPosition(Canvas canvas, double ox, double oy, double s) {
    final cell = routeStart;
    if (cell == null) return;
    final c = _center(cell, ox, oy, s);
    final radius = math.max(14.0, s * 0.34);
    final wave = math.sin(pulse * math.pi * 2);

    canvas.drawCircle(
      c,
      radius + 10 + wave * 3,
      Paint()..color = theme.blue.withValues(alpha: 0.16),
    );
    canvas.drawCircle(
      c,
      radius,
      Paint()..color = theme.blue,
    );
    canvas.drawCircle(
      c,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white,
    );

    final tp = TextPainter(
      text: const TextSpan(
        text: 'YOU',
        style: TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  void _drawNodes(Canvas canvas, double ox, double oy, double s) {
    for (final node in map.nodes) {
      final c = _center(node.cell, ox, oy, s);
      final color = factoryMapConveyorColor(node.conveyorNumber, theme);
      final isTarget = claimedNodeKey == node.key;
      final badge = badges[node.key];
      final statusColor = badge == null
          ? color
          : _statusColor(badge.status, theme, fallback: color);
      final fontSize = node.label.length > 5 ? 10.0 : 11.0;
      final tp = TextPainter(
        text: TextSpan(
          text: node.label,
          style: TextStyle(
              color: Colors.white,
              fontSize: fontSize,
              fontWeight: FontWeight.w900),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final radius = math
          .min(
            s * 0.47,
            math.max(s * 0.38, tp.width / 2 + 8),
          )
          .toDouble();

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

      canvas.drawCircle(
          c, radius, Paint()..color = isTarget ? theme.blue : statusColor);
      canvas.drawCircle(
        c,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = theme.card,
      );
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    }
  }

  void _drawRoute(Canvas canvas, double ox, double oy, double s) {
    final start = routeStart ?? map.entrance;
    final target = claimedNodeKey;
    if (start == null || target == null) return;
    final targetNode = map.nodeByKey(target);
    if (targetNode == null) return;

    final pathCells = _findRoute(start, targetNode);
    final points = <Offset>[
      _center(start, ox, oy, s),
      ...pathCells.map((cell) => _center(cell, ox, oy, s)),
    ];
    if (points.length < 2) {
      points
        ..clear()
        ..add(_center(start, ox, oy, s))
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
        canvas.drawCircle(t.position, 12,
            Paint()..color = theme.blue.withValues(alpha: 0.25));
        canvas.drawCircle(t.position, 6, Paint()..color = theme.blue);
      }
    }
  }

  /// Prefer a walkable floor route over the saved conveyor graph. The returned
  /// cells exclude the start and include the target.
  List<MapCell> _findRoute(MapCell start, MapNode target) {
    final gridRoute = _findGridRoute(start, target.cell);
    if (gridRoute.length >= 2) {
      return _compressRoute(gridRoute).skip(1).toList();
    }

    if (start == target.cell) return [target.cell];
    return _orthogonalFallback(start, target.cell);
  }

  List<MapCell> _orthogonalFallback(MapCell start, MapCell goal) {
    final horizontalFirst = MapCell(start.row, goal.col);
    final verticalFirst = MapCell(goal.row, start.col);
    final blocked = _buildRouteObstacles(start, goal);
    final horizontalCost = _fallbackCost(start, horizontalFirst, goal, blocked);
    final verticalCost = _fallbackCost(start, verticalFirst, goal, blocked);

    if (horizontalCost <= verticalCost && horizontalCost < double.infinity) {
      return [horizontalFirst, goal];
    }
    if (verticalCost < double.infinity) {
      return [verticalFirst, goal];
    }
    return [goal];
  }

  double _fallbackCost(
    MapCell start,
    MapCell corner,
    MapCell goal,
    Set<MapCell> blocked,
  ) {
    if (!_insideGrid(corner)) return double.infinity;
    final cells = [
      ..._cellsOnAxis(start, corner),
      ..._cellsOnAxis(corner, goal),
    ];
    var cost = 0.0;
    for (final cell in cells) {
      if (cell != start && cell != goal && blocked.contains(cell)) {
        cost += 1000;
      }
      cost += _clearancePenalty(cell, blocked);
    }
    return cost + cells.length;
  }

  List<MapCell> _cellsOnAxis(MapCell from, MapCell to) {
    final cells = <MapCell>[];
    final rowStep = (to.row - from.row).sign;
    final colStep = (to.col - from.col).sign;
    var row = from.row;
    var col = from.col;
    while (row != to.row || col != to.col) {
      if (row != to.row) row += rowStep;
      if (col != to.col) col += colStep;
      cells.add(MapCell(row, col));
    }
    return cells;
  }

  List<MapCell> _findGridRoute(MapCell start, MapCell goal) {
    final blocked = _buildRouteObstacles(start, goal);
    final open = <_RouteState>[
      _RouteState(start, -1, 0, _heuristic(start, goal)),
    ];
    final startKey = _stateKey(start, -1);
    final bestCost = <String, double>{startKey: 0};
    final previous = <String, String?>{startKey: null};
    final cells = <String, MapCell>{startKey: start};
    String? goalKey;

    while (open.isNotEmpty) {
      var bestIndex = 0;
      for (var i = 1; i < open.length; i++) {
        if (open[i].priority < open[bestIndex].priority) {
          bestIndex = i;
        }
      }

      final current = open.removeAt(bestIndex);
      final currentKey = _stateKey(current.cell, current.direction);
      final knownCost = bestCost[currentKey];
      if (knownCost == null || current.cost > knownCost) continue;

      if (current.cell == goal) {
        goalKey = currentKey;
        break;
      }

      for (var direction = 0;
          direction < _routeDirections.length;
          direction++) {
        final delta = _routeDirections[direction];
        final next = MapCell(
          current.cell.row + delta.row,
          current.cell.col + delta.col,
        );
        if (!_insideGrid(next)) continue;
        if (blocked.contains(next) && next != goal) continue;

        final turnCost =
            current.direction == -1 || current.direction == direction ? 0 : 6;
        final nextCost =
            current.cost + 10 + turnCost + _clearancePenalty(next, blocked);
        final nextKey = _stateKey(next, direction);
        if (nextCost >= (bestCost[nextKey] ?? double.infinity)) continue;

        bestCost[nextKey] = nextCost.toDouble();
        previous[nextKey] = currentKey;
        cells[nextKey] = next;
        open.add(_RouteState(
          next,
          direction,
          nextCost.toDouble(),
          nextCost + _heuristic(next, goal),
        ));
      }
    }

    if (goalKey == null) return const [];
    final reversed = <MapCell>[];
    String? cursor = goalKey;
    while (cursor != null) {
      final cell = cells[cursor];
      if (cell != null) reversed.add(cell);
      cursor = previous[cursor];
    }
    return reversed.reversed.toList();
  }

  Set<MapCell> _buildRouteObstacles(MapCell start, MapCell goal) {
    final blocked = <MapCell>{};
    for (final node in map.nodes) {
      blocked.add(node.cell);
    }
    for (final edge in map.edges) {
      final from = map.nodeByKey(edge.fromKey);
      final to = map.nodeByKey(edge.toKey);
      if (from == null || to == null) continue;
      _addSegmentCells(blocked, from.cell, to.cell);
    }
    blocked
      ..remove(start)
      ..remove(goal);
    return blocked;
  }

  void _addSegmentCells(Set<MapCell> blocked, MapCell from, MapCell to) {
    final rowDelta = to.row - from.row;
    final colDelta = to.col - from.col;
    final steps = math.max(rowDelta.abs(), colDelta.abs()) * 6;
    if (steps == 0) {
      blocked.add(from);
      return;
    }
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final row = (from.row + rowDelta * t).round();
      final col = (from.col + colDelta * t).round();
      final cell = MapCell(row, col);
      if (_insideGrid(cell)) blocked.add(cell);
    }
  }

  List<MapCell> _compressRoute(List<MapCell> route) {
    if (route.length <= 2) return route;
    final compressed = <MapCell>[route.first];
    var previousDelta = _deltaBetween(route[0], route[1]);
    for (var i = 1; i < route.length - 1; i++) {
      final nextDelta = _deltaBetween(route[i], route[i + 1]);
      if (nextDelta != previousDelta) {
        compressed.add(route[i]);
      }
      previousDelta = nextDelta;
    }
    compressed.add(route.last);
    return compressed;
  }

  _RouteDelta _deltaBetween(MapCell a, MapCell b) =>
      _RouteDelta(b.row - a.row, b.col - a.col);

  bool _insideGrid(MapCell cell) =>
      cell.row >= 0 &&
      cell.col >= 0 &&
      cell.row < map.rows &&
      cell.col < map.cols;

  double _heuristic(MapCell a, MapCell b) =>
      ((a.row - b.row).abs() + (a.col - b.col).abs()) * 10.0;

  double _clearancePenalty(MapCell cell, Set<MapCell> blocked) {
    var penalty = 0.0;
    for (var dr = -1; dr <= 1; dr++) {
      for (var dc = -1; dc <= 1; dc++) {
        if (dr == 0 && dc == 0) continue;
        final nearby = MapCell(cell.row + dr, cell.col + dc);
        if (!blocked.contains(nearby)) continue;
        penalty += dr == 0 || dc == 0 ? 2.0 : 1.0;
      }
    }
    return penalty;
  }

  String _stateKey(MapCell cell, int direction) =>
      '${cell.row},${cell.col},$direction';

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

  Color _statusColor(LocatorNodeStatus s, AppTheme t,
      {required Color fallback}) {
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
      old.routeStart != routeStart ||
      old.isDark != isDark ||
      old.badges.length != badges.length;
}
