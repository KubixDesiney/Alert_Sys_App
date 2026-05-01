import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

enum LocatorStationStatus {
  idle,
  available,
  inProgress,
  resolved,
  critical,
}

class LocatorStationPin {
  final String id;
  final String label;
  final String assetLabel;
  final int conveyorNumber;
  final int stationNumber;
  final double x;
  final double y;
  final LocatorStationStatus status;
  final bool isTarget;
  final int? alertNumber;

  const LocatorStationPin({
    required this.id,
    required this.label,
    required this.assetLabel,
    required this.conveyorNumber,
    required this.stationNumber,
    required this.x,
    required this.y,
    required this.status,
    this.isTarget = false,
    this.alertNumber,
  });

  Offset get point => Offset(x, y);
}

class LocatorMapPainter extends CustomPainter {
  final AppTheme theme;
  final bool isDark;
  final List<LocatorStationPin> stations;
  final Offset entrance;
  final Offset? currentPosition;
  final LocatorStationPin? targetStation;
  final double pulse;

  const LocatorMapPainter({
    required this.theme,
    required this.isDark,
    required this.stations,
    required this.entrance,
    required this.currentPosition,
    required this.targetStation,
    required this.pulse,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = _worldBounds();
    final transform = _MapTransform(size, bounds);

    _drawSurface(canvas, size, transform);
    _drawGrid(canvas, transform);
    _drawConveyors(canvas, transform);
    _drawGuide(canvas, transform);
    _drawEntrance(canvas, transform);
    if (currentPosition != null) {
      _drawCurrentPosition(canvas, transform, currentPosition!);
    }
    _drawStations(canvas, transform);
  }

  Rect _worldBounds() {
    final points = <Offset>[
      entrance,
      if (currentPosition != null) currentPosition!,
      ...stations.map((station) => station.point),
    ];
    if (points.isEmpty) return const Rect.fromLTRB(-4, -2, 6, 6);

    var minX = points.first.dx;
    var maxX = points.first.dx;
    var minY = points.first.dy;
    var maxY = points.first.dy;
    for (final point in points.skip(1)) {
      minX = math.min(minX, point.dx);
      maxX = math.max(maxX, point.dx);
      minY = math.min(minY, point.dy);
      maxY = math.max(maxY, point.dy);
    }

    if ((maxX - minX).abs() < 4) {
      minX -= 2;
      maxX += 2;
    }
    if ((maxY - minY).abs() < 4) {
      minY -= 2;
      maxY += 2;
    }
    return Rect.fromLTRB(minX - 1.2, minY - 1.2, maxX + 1.2, maxY + 1.2);
  }

  void _drawSurface(Canvas canvas, Size size, _MapTransform transform) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..color = isDark
            ? theme.scaffold.withValues(alpha: 0.72)
            : const Color(0xFFF8FAFC),
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(transform.floorRect, const Radius.circular(8)),
      Paint()..color = theme.card,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(transform.floorRect, const Radius.circular(8)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = theme.border,
    );
  }

  void _drawGrid(Canvas canvas, _MapTransform transform) {
    final gridPaint = Paint()
      ..color = theme.border.withValues(alpha: isDark ? 0.36 : 0.72)
      ..strokeWidth = 1;
    final axisPaint = Paint()
      ..color = theme.navy.withValues(alpha: isDark ? 0.32 : 0.22)
      ..strokeWidth = 1.6;

    for (var x = transform.bounds.left.floor();
        x <= transform.bounds.right.ceil();
        x++) {
      final start =
          transform.toScreen(Offset(x.toDouble(), transform.bounds.top));
      final end =
          transform.toScreen(Offset(x.toDouble(), transform.bounds.bottom));
      canvas.drawLine(start, end, x == 0 ? axisPaint : gridPaint);
    }
    for (var y = transform.bounds.top.floor();
        y <= transform.bounds.bottom.ceil();
        y++) {
      final start =
          transform.toScreen(Offset(transform.bounds.left, y.toDouble()));
      final end =
          transform.toScreen(Offset(transform.bounds.right, y.toDouble()));
      canvas.drawLine(start, end, y == 0 ? axisPaint : gridPaint);
    }
  }

  void _drawConveyors(Canvas canvas, _MapTransform transform) {
    final grouped = <int, List<LocatorStationPin>>{};
    for (final station in stations) {
      grouped.putIfAbsent(station.conveyorNumber, () => []).add(station);
    }

    for (final entry in grouped.entries) {
      final pins = entry.value
        ..sort((a, b) => a.stationNumber.compareTo(b.stationNumber));
      if (pins.length < 2) continue;

      final path = Path();
      for (var i = 0; i < pins.length; i++) {
        final point = transform.toScreen(pins[i].point);
        if (i == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }

      canvas.drawPath(
        path,
        Paint()
          ..color = theme.borderSoft.withValues(alpha: isDark ? 0.40 : 0.84)
          ..strokeWidth = 20
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = theme.navy.withValues(alpha: isDark ? 0.30 : 0.16)
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke,
      );
    }
  }

  void _drawGuide(Canvas canvas, _MapTransform transform) {
    final target = targetStation;
    if (target == null) return;

    final startWorld = currentPosition ?? entrance;
    final start = transform.toScreen(startWorld);
    final end = transform.toScreen(target.point);
    final mid = Offset(
      start.dx + (end.dx - start.dx) * 0.52,
      start.dy + (end.dy - start.dy) * 0.18,
    );
    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..quadraticBezierTo(mid.dx, mid.dy, end.dx, end.dy);

    canvas.drawPath(
      path,
      Paint()
        ..color = theme.green.withValues(alpha: isDark ? 0.22 : 0.18)
        ..strokeWidth = 14
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
    _drawDashedPath(
      canvas,
      path,
      Paint()
        ..color = theme.green
        ..strokeWidth = 4.2
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
      dash: 18,
      gap: 10,
      phase: pulse * 32,
    );

    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;
    final metric = metrics.last;
    final tangent = metric.getTangentForOffset(metric.length);
    if (tangent == null) return;
    _drawArrowHead(canvas, tangent.position, tangent.angle, theme.green);

    final moving = metric.getTangentForOffset(metric.length * pulse);
    if (moving != null) {
      canvas.drawCircle(
        moving.position,
        5,
        Paint()..color = theme.green,
      );
      canvas.drawCircle(
        moving.position,
        10,
        Paint()..color = theme.green.withValues(alpha: 0.16),
      );
    }
  }

  void _drawEntrance(Canvas canvas, _MapTransform transform) {
    final point = transform.toScreen(entrance);
    final rect = Rect.fromCenter(center: point, width: 28, height: 28);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(8)),
      Paint()..color = theme.greenLt,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(8)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = theme.green.withValues(alpha: 0.58),
    );

    final door = Path()
      ..moveTo(point.dx - 5, point.dy + 7)
      ..lineTo(point.dx - 5, point.dy - 8)
      ..lineTo(point.dx + 6, point.dy - 5)
      ..lineTo(point.dx + 6, point.dy + 8)
      ..close();
    canvas.drawPath(door, Paint()..color = theme.green);

    _paintLabel(
      canvas,
      'Factory Entrance',
      point + const Offset(18, -30),
      fill: theme.card,
      border: theme.green.withValues(alpha: 0.30),
      textColor: theme.text,
    );
  }

  void _drawCurrentPosition(
    Canvas canvas,
    _MapTransform transform,
    Offset current,
  ) {
    final point = transform.toScreen(current);
    final ring = 18 + 6 * math.sin(pulse * math.pi);
    canvas.drawCircle(
      point,
      ring,
      Paint()..color = theme.blue.withValues(alpha: 0.13),
    );
    canvas.drawCircle(point, 8.5, Paint()..color = theme.blue);
    canvas.drawCircle(
      point,
      8.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = theme.card,
    );
    _paintLabel(
      canvas,
      'Current Position',
      point + const Offset(14, 12),
      fill: theme.card,
      border: theme.blue.withValues(alpha: 0.30),
      textColor: theme.text,
    );
  }

  void _drawStations(Canvas canvas, _MapTransform transform) {
    final ordered = [...stations]..sort((a, b) {
        if (a.isTarget != b.isTarget) return a.isTarget ? 1 : -1;
        return _statusPriority(a.status).compareTo(_statusPriority(b.status));
      });

    for (final station in ordered) {
      final point = transform.toScreen(station.point);
      final color = _statusColor(station.status);
      final targetPulse = station.isTarget ? math.sin(pulse * math.pi) : 0.0;
      final radius = station.isTarget ? 18.0 + targetPulse * 3.5 : 11.5;

      if (station.isTarget) {
        canvas.drawCircle(
          point,
          radius + 17 + targetPulse * 8,
          Paint()..color = theme.blue.withValues(alpha: 0.13),
        );
        canvas.drawCircle(
          point,
          radius + 7,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.4
            ..color = const Color(0xFF22D3EE).withValues(alpha: 0.70),
        );
      } else if (station.status != LocatorStationStatus.idle) {
        canvas.drawCircle(
          point,
          radius + 8,
          Paint()..color = color.withValues(alpha: 0.11),
        );
      }

      canvas.drawCircle(point, radius, Paint()..color = color);
      canvas.drawCircle(
        point,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..color = theme.card,
      );
      _paintCenteredText(
        canvas,
        'S${station.stationNumber}',
        point,
        TextStyle(
          color: Colors.white,
          fontSize: station.isTarget ? 10.5 : 9,
          fontWeight: FontWeight.w900,
        ),
      );

      _paintLabel(
        canvas,
        station.alertNumber == null
            ? '${station.label}\n${station.assetLabel}'
            : '${station.label} #${station.alertNumber}\n${station.assetLabel}',
        point + Offset(station.conveyorNumber.isEven ? 18 : -96, -34),
        fill: theme.card.withValues(alpha: isDark ? 0.90 : 0.94),
        border: color.withValues(alpha: station.isTarget ? 0.55 : 0.22),
        textColor: theme.text,
        accentColor: color,
      );
    }
  }

  int _statusPriority(LocatorStationStatus status) {
    return switch (status) {
      LocatorStationStatus.critical => 5,
      LocatorStationStatus.available => 4,
      LocatorStationStatus.inProgress => 3,
      LocatorStationStatus.resolved => 2,
      LocatorStationStatus.idle => 1,
    };
  }

  Color _statusColor(LocatorStationStatus status) {
    return switch (status) {
      LocatorStationStatus.critical => theme.red,
      LocatorStationStatus.available => theme.orange,
      LocatorStationStatus.inProgress => theme.blue,
      LocatorStationStatus.resolved => theme.green,
      LocatorStationStatus.idle => theme.mutedDk,
    };
  }

  void _drawDashedPath(
    Canvas canvas,
    Path path,
    Paint paint, {
    required double dash,
    required double gap,
    required double phase,
  }) {
    for (final metric in path.computeMetrics()) {
      var distance = -phase % (dash + gap);
      while (distance < metric.length) {
        final start = distance.clamp(0.0, metric.length).toDouble();
        final end = (distance + dash).clamp(0.0, metric.length).toDouble();
        if (end > start) {
          canvas.drawPath(metric.extractPath(start, end), paint);
        }
        distance += dash + gap;
      }
    }
  }

  void _drawArrowHead(Canvas canvas, Offset tip, double angle, Color color) {
    const size = 14.0;
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

  void _paintLabel(
    Canvas canvas,
    String text,
    Offset offset, {
    required Color fill,
    required Color border,
    required Color textColor,
    Color? accentColor,
  }) {
    final lines = text.split('\n');
    final painter = TextPainter(
      text: TextSpan(
        children: [
          TextSpan(
            text: lines.first,
            style: TextStyle(
              color: textColor,
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (lines.length > 1)
            TextSpan(
              text: '\n${lines.skip(1).join('\n')}',
              style: TextStyle(
                color: theme.muted,
                fontSize: 9.2,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
      textDirection: TextDirection.ltr,
      maxLines: 2,
    )..layout(maxWidth: 104);
    final rect = Rect.fromLTWH(
      offset.dx,
      offset.dy,
      painter.width + 15,
      painter.height + 10,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(8)),
      Paint()..color = fill,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(8)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = border,
    );
    if (accentColor != null) {
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(rect.left, rect.top, 4, rect.height),
          topLeft: const Radius.circular(8),
          bottomLeft: const Radius.circular(8),
        ),
        Paint()..color = accentColor,
      );
    }
    painter.paint(canvas, Offset(rect.left + 8, rect.top + 5));
  }

  void _paintCenteredText(
    Canvas canvas,
    String text,
    Offset center,
    TextStyle style,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant LocatorMapPainter oldDelegate) {
    return oldDelegate.theme.isDark != theme.isDark ||
        oldDelegate.stations != stations ||
        oldDelegate.currentPosition != currentPosition ||
        oldDelegate.targetStation != targetStation ||
        oldDelegate.pulse != pulse;
  }
}

class _MapTransform {
  final Size size;
  final Rect bounds;
  late final Rect floorRect;
  late final double scale;

  _MapTransform(this.size, this.bounds) {
    const padding = EdgeInsets.fromLTRB(56, 48, 56, 48);
    final available = Size(
      math.max(1.0, size.width - padding.horizontal),
      math.max(1.0, size.height - padding.vertical),
    );
    scale = math.min(
      available.width / bounds.width,
      available.height / bounds.height,
    );
    final width = bounds.width * scale;
    final height = bounds.height * scale;
    final left = padding.left + (available.width - width) / 2;
    final top = padding.top + (available.height - height) / 2;
    floorRect = Rect.fromLTWH(left, top, width, height);
  }

  Offset toScreen(Offset world) {
    return Offset(
      floorRect.left + (world.dx - bounds.left) * scale,
      floorRect.top + (bounds.bottom - world.dy) * scale,
    );
  }
}
