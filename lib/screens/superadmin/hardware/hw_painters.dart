import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'hw_models.dart';
import 'hw_runtime.dart';

/// Renders every component, the breadboard grid and the wiring. Bodies are
/// drawn with real silicon colours (a dark ESP32 PCB, a teal UNO, beige
/// resistors) so the canvas reads like a Proteus/Wokwi bench regardless of the
/// app theme. The simulator state lights LEDs, shows LCD text, swings servos.

const double kHwPinHit = 9.0;

/// Draw a single component in absolute canvas coordinates, honouring rotation.
void drawHwComponent(
  Canvas canvas,
  HwComponent c, {
  HwSimulator? sim,
  bool selected = false,
  bool hovered = false,
}) {
  final def = c.def;
  final w = def.width;
  final h = def.height;
  canvas.save();
  switch (c.rot % 4) {
    case 1:
      canvas.translate(c.x + h, c.y);
      canvas.rotate(math.pi / 2);
    case 2:
      canvas.translate(c.x + w, c.y + h);
      canvas.rotate(math.pi);
    case 3:
      canvas.translate(c.x, c.y + w);
      canvas.rotate(3 * math.pi / 2);
    default:
      canvas.translate(c.x, c.y);
  }

  // Selection / hover halo behind the body.
  if (selected || hovered) {
    final r = RRect.fromRectAndRadius(
      Rect.fromLTWH(-6, -6, w + 12, h + 12),
      const Radius.circular(12),
    );
    canvas.drawRRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 2 : 1.2
        ..color = (selected ? def.accent : Colors.white)
            .withValues(alpha: selected ? 0.9 : 0.4),
    );
    if (selected) {
      canvas.drawRRect(
        r,
        Paint()
          ..color = def.accent.withValues(alpha: 0.06)
          ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 8),
      );
    }
  }

  switch (c.type) {
    case 'esp32':
      _drawEsp32(canvas, c, sim);
    case 'arduino-uno':
      _drawUno(canvas, c, sim);
    case 'arduino-nano':
    case 'arduino-mega':
    case 'esp8266':
    case 'esp32c3':
    case 'pico':
      _drawBoard(canvas, c, sim);
    case 'gnd':
      _drawGnd(canvas, c);
    case 'vcc':
      _drawVcc(canvas, c);
    case 'led':
      _drawLed(canvas, c, sim);
    case 'rgb-led':
      _drawRgbLed(canvas, c, sim);
    case 'button':
      _drawButton(canvas, c);
    case 'potentiometer':
      _drawPot(canvas, c);
    case 'lcd1602':
      _drawLcd(canvas, c, sim);
    case 'buzzer':
      _drawBuzzer(canvas, c, sim);
    case 'servo':
      _drawServo(canvas, c, sim);
    case 'temp-sensor':
      _drawTempSensor(canvas, c);
    case 'vibration-sensor':
      _drawVibration(canvas, c);
    case 'pir-sensor':
      _drawPir(canvas, c);
    case 'resistor':
      _drawResistor(canvas, c);
    case 'power-5v':
      _drawPower(canvas, c);
    default:
      _drawGeneric(canvas, c);
  }

  // Pin pads (drawn in local frame so they rotate with the body).
  for (final p in def.pins) {
    final hot = sim?.pinIsHot(c.id, p.name) ?? false;
    _drawPinPad(canvas, Offset(p.dx, p.dy), p.kind, hot: hot);
  }

  canvas.restore();
}

// ── shared helpers ──

void _text(
  Canvas canvas,
  String s,
  Offset at, {
  double size = 9,
  Color color = Colors.white,
  FontWeight weight = FontWeight.w600,
  TextAlign align = TextAlign.left,
  double? maxWidth,
  bool mono = false,
}) {
  final tp = TextPainter(
    text: TextSpan(
      text: s,
      style: TextStyle(
        color: color,
        fontSize: size,
        fontWeight: weight,
        fontFamily: mono ? 'monospace' : null,
        letterSpacing: 0.2,
      ),
    ),
    textDirection: TextDirection.ltr,
    textAlign: align,
  )..layout(maxWidth: maxWidth ?? double.infinity);
  var dx = at.dx;
  if (align == TextAlign.center) dx -= tp.width / 2;
  if (align == TextAlign.right) dx -= tp.width;
  tp.paint(canvas, Offset(dx, at.dy));
}

void _drawPinPad(Canvas canvas, Offset at, HwPinKind kind, {bool hot = false}) {
  final base = switch (kind) {
    HwPinKind.power => const Color(0xFFEF4444),
    HwPinKind.ground => const Color(0xFF334155),
    HwPinKind.anode => const Color(0xFFEF4444),
    HwPinKind.cathode => const Color(0xFF334155),
    HwPinKind.i2cSda => const Color(0xFF8B5CF6),
    HwPinKind.i2cScl => const Color(0xFF8B5CF6),
    _ => const Color(0xFFB8923A),
  };
  if (hot) {
    canvas.drawCircle(
        at, 6, Paint()..color = const Color(0xFF34D399).withValues(alpha: 0.5));
  }
  canvas.drawCircle(at, 3.4, Paint()..color = const Color(0xFF0B1220));
  canvas.drawCircle(at, 2.6, Paint()..color = hot ? const Color(0xFF6EE7B7) : base);
  canvas.drawCircle(at, 1.0, Paint()..color = Colors.black.withValues(alpha: 0.5));
}

void _roundRect(Canvas canvas, Rect r, Color color, {double radius = 6, Color? border, double bw = 1}) {
  final rr = RRect.fromRectAndRadius(r, Radius.circular(radius));
  canvas.drawRRect(rr, Paint()..color = color);
  if (border != null) {
    canvas.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = bw
          ..color = border);
  }
}

// ── boards ──

void _drawEsp32(Canvas canvas, HwComponent c, HwSimulator? sim) {
  final w = c.def.width, h = c.def.height;
  _roundRect(canvas, Rect.fromLTWH(0, 0, w, h), const Color(0xFF111C33),
      radius: 10, border: const Color(0xFF22D3EE), bw: 1.2);
  // Pin rails (silk).
  _roundRect(canvas, Rect.fromLTWH(2, 8, 16, h - 16), const Color(0xFF0A1426),
      radius: 4);
  _roundRect(canvas, Rect.fromLTWH(w - 18, 8, 16, h - 16),
      const Color(0xFF0A1426),
      radius: 4);
  // WiFi/BLE metal shield.
  _roundRect(canvas, Rect.fromLTWH(w / 2 - 34, 30, 68, 78),
      const Color(0xFFC9D2DE),
      radius: 4, border: const Color(0xFF8A95A5), bw: 1);
  _text(canvas, 'ESP32-WROOM', Offset(w / 2, 60),
      size: 7.5, color: const Color(0xFF3A4658), align: TextAlign.center);
  // USB.
  _roundRect(canvas, Rect.fromLTWH(w / 2 - 13, h - 18, 26, 16),
      const Color(0xFF8A95A5),
      radius: 3);
  // Silk label + power LED.
  _text(canvas, 'ESP32', Offset(w / 2, 116),
      size: 11, color: const Color(0xFF22D3EE), align: TextAlign.center);
  final on = sim?.isRunning ?? false;
  canvas.drawCircle(Offset(w / 2 + 30, 130),
      3, Paint()..color = on ? const Color(0xFFEF4444) : const Color(0xFF5B1A1A));
  if (on) {
    canvas.drawCircle(Offset(w / 2 + 30, 130), 6,
        Paint()..color = const Color(0xFFEF4444).withValues(alpha: 0.4));
  }
  // Pin name silk.
  for (final p in c.def.pins) {
    final left = p.dx < w / 2;
    _text(canvas, p.name.replaceFirst('GPIO', ''),
        Offset(left ? p.dx + 8 : p.dx - 8, p.dy - 4),
        size: 6, color: const Color(0xFF7C8AA0),
        align: left ? TextAlign.left : TextAlign.right);
  }
}

void _drawUno(Canvas canvas, HwComponent c, HwSimulator? sim) {
  final w = c.def.width, h = c.def.height;
  _roundRect(canvas, Rect.fromLTWH(0, 0, w, h), const Color(0xFF0E7C7B),
      radius: 9, border: const Color(0xFF2DD4BF), bw: 1.2);
  // Headers.
  _roundRect(canvas, Rect.fromLTWH(14, 2, w - 40, 14), const Color(0xFF0B1118),
      radius: 3);
  _roundRect(canvas, Rect.fromLTWH(14, h - 16, w - 40, 14),
      const Color(0xFF0B1118),
      radius: 3);
  // USB-B + barrel jack.
  _roundRect(canvas, const Rect.fromLTWH(-6, 22, 34, 30),
      const Color(0xFFB9C2CC),
      radius: 3);
  _roundRect(canvas, Rect.fromLTWH(-4, h - 56, 26, 22), const Color(0xFF1A1A1A),
      radius: 4);
  // ATmega chip.
  _roundRect(canvas, Rect.fromLTWH(w / 2 - 20, h / 2 - 16, 84, 30),
      const Color(0xFF15202B),
      radius: 3, border: const Color(0xFF2B3A47), bw: 1);
  canvas.drawCircle(Offset(w / 2 - 14, h / 2 - 9), 2,
      Paint()..color = const Color(0xFF40505E));
  _text(canvas, 'ARDUINO  UNO', Offset(w / 2 + 6, 24),
      size: 11, color: Colors.white, align: TextAlign.center);
  // ON led.
  final on = sim?.isRunning ?? false;
  canvas.drawCircle(Offset(40, h / 2 + 4), 3,
      Paint()..color = on ? const Color(0xFF34D399) : const Color(0xFF1F4A3A));
  _text(canvas, 'ON', Offset(40, h / 2 + 8),
      size: 5, color: Colors.white70, align: TextAlign.center);
  // Pin silk.
  for (final p in c.def.pins) {
    final top = p.dy < h / 2;
    _text(canvas, p.name, Offset(p.dx, top ? p.dy + 6 : p.dy - 12),
        size: 5.5, color: Colors.white70, align: TextAlign.center);
  }
}

/// Generic dev-board body used by Nano / Mega / NodeMCU / ESP32-C3 / Pico.
/// Draws a tinted PCB with pin rails, an SoC/regulator, the board name and a
/// power LED that lights while the simulation runs — silicon-realistic without a
/// bespoke painter per board.
void _drawBoard(Canvas canvas, HwComponent c, HwSimulator? sim) {
  final def = c.def;
  final w = def.width, h = def.height;
  final accent = def.accent;
  // PCB.
  _roundRect(canvas, Rect.fromLTWH(0, 0, w, h), const Color(0xFF0E1A2E),
      radius: 10, border: accent.withValues(alpha: 0.8), bw: 1.2);
  // Pin rails (silk).
  _roundRect(canvas, Rect.fromLTWH(2, 10, 15, h - 20), const Color(0xFF0A1426),
      radius: 4);
  _roundRect(canvas, Rect.fromLTWH(w - 17, 10, 15, h - 20),
      const Color(0xFF0A1426),
      radius: 4);
  // USB connector at the top edge.
  _roundRect(canvas, Rect.fromLTWH(w / 2 - 12, -4, 24, 14),
      const Color(0xFF9AA6B5),
      radius: 3);
  // SoC / metal can.
  final chip = Rect.fromLTWH(w / 2 - 26, h * 0.30, 52, h * 0.22);
  _roundRect(canvas, chip, const Color(0xFF16223A),
      radius: 5, border: accent.withValues(alpha: 0.5), bw: 1);
  _text(canvas, def.shortName, chip.center.translate(0, -6),
      size: 9, color: accent, align: TextAlign.center, weight: FontWeight.w800);
  // Name silk down the middle.
  _text(canvas, def.name.toUpperCase(), Offset(w / 2, h * 0.58),
      size: 6.5, color: const Color(0xFF7C8AA0), align: TextAlign.center,
      maxWidth: w - 26);
  // Power LED.
  final on = sim?.isRunning ?? false;
  final ledAt = Offset(w / 2 + 18, h * 0.66);
  canvas.drawCircle(ledAt, 3,
      Paint()..color = on ? const Color(0xFFEF4444) : const Color(0xFF5B1A1A));
  if (on) {
    canvas.drawCircle(ledAt, 6,
        Paint()..color = const Color(0xFFEF4444).withValues(alpha: 0.4));
  }
  // Pin name silk.
  for (final p in def.pins) {
    final left = p.dx < w / 2;
    final label = p.name.replaceFirst('GPIO', '');
    _text(canvas, label, Offset(left ? p.dx + 8 : p.dx - 8, p.dy - 4),
        size: 5.5, color: const Color(0xFF7C8AA0),
        align: left ? TextAlign.left : TextAlign.right);
  }
}

/// Classic ground symbol (descending bars under the pin).
void _drawGnd(Canvas canvas, HwComponent c) {
  final w = c.def.width;
  final cx = w / 2;
  final p = Paint()
    ..color = const Color(0xFF94A3B8)
    ..strokeWidth = 2.4
    ..strokeCap = StrokeCap.round;
  // Lead down from the pin.
  canvas.drawLine(Offset(cx, 6), Offset(cx, 22), p);
  // Three descending bars.
  canvas.drawLine(Offset(cx - 12, 24), Offset(cx + 12, 24), p);
  canvas.drawLine(Offset(cx - 8, 31), Offset(cx + 8, 31), p);
  canvas.drawLine(Offset(cx - 4, 38), Offset(cx + 4, 38), p);
  _text(canvas, 'GND', Offset(cx, 41),
      size: 7, color: const Color(0xFF94A3B8), align: TextAlign.center);
}

/// VCC supply symbol — an upward rail with the configured voltage.
void _drawVcc(Canvas canvas, HwComponent c) {
  final w = c.def.width;
  final cx = w / 2;
  final volts = (c.params['volts'] as num?)?.toDouble() ?? 5.0;
  const color = Color(0xFFEF4444);
  final p = Paint()
    ..color = color
    ..strokeWidth = 2.4
    ..strokeCap = StrokeCap.round;
  // Top rail bar.
  canvas.drawLine(Offset(cx - 13, 10), Offset(cx + 13, 10), p);
  // Arrow up.
  canvas.drawLine(Offset(cx, 22), Offset(cx, 12), p);
  canvas.drawLine(Offset(cx, 12), Offset(cx - 4, 17), p);
  canvas.drawLine(Offset(cx, 12), Offset(cx + 4, 17), p);
  // Lead down to the pin.
  canvas.drawLine(Offset(cx, 22), Offset(cx, 44), p);
  _text(canvas, volts >= 5 ? '5V' : '3V3', Offset(cx, 24),
      size: 8, color: color, align: TextAlign.center, weight: FontWeight.w800);
}

// ── outputs ──

void _drawLed(Canvas canvas, HwComponent c, HwSimulator? sim) {
  final w = c.def.width;
  final color = Color(kHwColorSwatches[c.params['color']] ?? 0xFFFF4D4D);
  final level = sim?.ledLevelOf(c.id) ?? 0;
  // Legs.
  final leg = Paint()
    ..color = const Color(0xFFB8923A)
    ..strokeWidth = 2.4;
  canvas.drawLine(const Offset(14, 40), const Offset(14, 60), leg);
  canvas.drawLine(const Offset(30, 40), const Offset(30, 60), leg);
  // Glow when lit.
  if (level > 0.02) {
    canvas.drawCircle(Offset(w / 2, 22), 16 + 10 * level,
        Paint()..color = color.withValues(alpha: 0.5 * level)
          ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 8));
  }
  // Dome.
  final domeColor = Color.lerp(color.withValues(alpha: 0.55), color, level)!;
  final dome = Path()
    ..addArc(Rect.fromLTWH(w / 2 - 12, 6, 24, 24), math.pi, math.pi)
    ..lineTo(w / 2 + 12, 30)
    ..lineTo(w / 2 - 12, 30)
    ..close();
  canvas.drawPath(dome, Paint()..color = domeColor);
  canvas.drawCircle(Offset(w / 2, 18), 11,
      Paint()..color = Color.lerp(color.withValues(alpha: 0.4), Colors.white, 0.2 + 0.6 * level)!);
  // Highlight.
  canvas.drawCircle(Offset(w / 2 - 3, 13), 3,
      Paint()..color = Colors.white.withValues(alpha: 0.5 + 0.4 * level));
  _text(canvas, '+', const Offset(8, 30), size: 8, color: Colors.white70);
}

void _drawRgbLed(Canvas canvas, HwComponent c, HwSimulator? sim) {
  final w = c.def.width;
  final level = sim?.ledLevelOf(c.id) ?? 0;
  if (level > 0.02) {
    canvas.drawCircle(Offset(w / 2, 26), 18 + 10 * level,
        Paint()..color = const Color(0xFFA78BFA).withValues(alpha: 0.4 * level)
          ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 9));
  }
  canvas.drawCircle(Offset(w / 2, 26), 16,
      Paint()..color = Color.lerp(const Color(0x33FFFFFF), Colors.white, level)!);
  canvas.drawCircle(Offset(w / 2, 26), 16,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = const Color(0xFF7C8AA0));
  final leg = Paint()
    ..color = const Color(0xFFB8923A)
    ..strokeWidth = 2.2;
  for (final p in c.def.pins) {
    canvas.drawLine(Offset(p.dx, 44), Offset(p.dx, p.dy), leg);
  }
}

void _drawButton(Canvas canvas, HwComponent c) {
  final w = c.def.width, h = c.def.height;
  final pressed = c.params['pressed'] == true;
  final color = Color(kHwColorSwatches[c.params['color']] ?? 0xFFFF4D4D);
  // Base.
  _roundRect(canvas, Rect.fromLTWH(14, 14, w - 28, h - 28),
      const Color(0xFF1B2433),
      radius: 6, border: const Color(0xFF33405A), bw: 1);
  // Legs.
  final leg = Paint()
    ..color = const Color(0xFFB8923A)
    ..strokeWidth = 2.4;
  canvas.drawLine(const Offset(6, 36), const Offset(18, 36), leg);
  canvas.drawLine(Offset(w - 6, 36), Offset(w - 18, 36), leg);
  // Cap.
  final r = pressed ? 11.0 : 13.0;
  canvas.drawCircle(Offset(w / 2, h / 2), r + 1,
      Paint()..color = Colors.black.withValues(alpha: 0.4));
  canvas.drawCircle(Offset(w / 2, h / 2), r,
      Paint()..color = pressed ? color : color.withValues(alpha: 0.82));
  canvas.drawCircle(Offset(w / 2 - 3, h / 2 - 3), 3,
      Paint()..color = Colors.white.withValues(alpha: pressed ? 0.3 : 0.55));
}

void _drawPot(Canvas canvas, HwComponent c) {
  final w = c.def.width;
  final v = (c.params['value'] as num?)?.toDouble() ?? 0.5;
  _roundRect(canvas, Rect.fromLTWH(8, 6, w - 16, 48), const Color(0xFF1E3A5F),
      radius: 8, border: const Color(0xFF38BDF8), bw: 1);
  final cx = w / 2, cy = 30.0;
  canvas.drawCircle(Offset(cx, cy), 18, Paint()..color = const Color(0xFF0E2238));
  canvas.drawCircle(Offset(cx, cy), 18,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = const Color(0xFF38BDF8));
  // Indicator (135° → 405°).
  final ang = (-0.75 * math.pi) + v * (1.5 * math.pi);
  canvas.drawLine(
      Offset(cx, cy),
      Offset(cx + 14 * math.cos(ang), cy + 14 * math.sin(ang)),
      Paint()
        ..color = const Color(0xFF38BDF8)
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round);
  final leg = Paint()
    ..color = const Color(0xFFB8923A)
    ..strokeWidth = 2.2;
  for (final p in c.def.pins) {
    canvas.drawLine(Offset(p.dx, 54), Offset(p.dx, p.dy), leg);
  }
  _text(canvas, '${(v * 100).round()}%', Offset(cx, 56),
      size: 7, color: Colors.white70, align: TextAlign.center);
}

void _drawLcd(Canvas canvas, HwComponent c, HwSimulator? sim) {
  final w = c.def.width, h = c.def.height;
  _roundRect(canvas, Rect.fromLTWH(0, 0, w, h - 8), const Color(0xFF0E6E4E),
      radius: 6, border: const Color(0xFF34D399), bw: 1);
  // Screen.
  final screen = Rect.fromLTWH(12, 10, w - 24, h - 34);
  _roundRect(canvas, screen, const Color(0xFF1A6BE0), radius: 3);
  _roundRect(canvas, screen.deflate(3), const Color(0xFF2F86FF), radius: 2);
  // 16x2 chars.
  final lines = sim?.lcdLines ?? const ['', ''];
  final cellW = (screen.width - 8) / 16;
  for (var row = 0; row < 2; row++) {
    final text = (row < lines.length ? lines[row] : '').padRight(16);
    for (var col = 0; col < 16; col++) {
      final ch = col < text.length ? text[col] : ' ';
      if (ch.trim().isEmpty) continue;
      _text(canvas, ch,
          Offset(screen.left + 6 + col * cellW, screen.top + 4 + row * 16),
          size: 11, color: const Color(0xFFEAF6FF), weight: FontWeight.w700,
          mono: true);
    }
  }
  // Header pins silk.
  for (final p in c.def.pins) {
    _text(canvas, p.name, Offset(p.dx, p.dy - 12),
        size: 5.5, color: Colors.white70, align: TextAlign.center);
  }
}

void _drawBuzzer(Canvas canvas, HwComponent c, HwSimulator? sim) {
  final w = c.def.width;
  final on = sim?.buzzerOn ?? false;
  canvas.drawCircle(Offset(w / 2, 26), 22,
      Paint()..color = const Color(0xFF141414));
  canvas.drawCircle(Offset(w / 2, 26), 22,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = const Color(0xFFF472B6));
  canvas.drawCircle(Offset(w / 2, 22), 3, Paint()..color = const Color(0xFF333333));
  _text(canvas, '+', Offset(w / 2 - 12, 14), size: 8, color: Colors.white70);
  if (on) {
    for (var i = 1; i <= 3; i++) {
      canvas.drawCircle(Offset(w / 2, 26), 22.0 + i * 5,
          Paint()
            ..style = PaintingStyle.stroke
            ..color = const Color(0xFFF472B6).withValues(alpha: 0.5 / i));
    }
  }
  final leg = Paint()
    ..color = const Color(0xFFB8923A)
    ..strokeWidth = 2.2;
  for (final p in c.def.pins) {
    canvas.drawLine(Offset(p.dx, 48), Offset(p.dx, p.dy), leg);
  }
}

void _drawServo(Canvas canvas, HwComponent c, HwSimulator? sim) {
  final w = c.def.width, h = c.def.height;
  _roundRect(canvas, Rect.fromLTWH(8, 16, w - 16, h - 30), const Color(0xFF1E64C8),
      radius: 4, border: const Color(0xFFFB923C), bw: 1);
  // Horn pivot.
  final pivot = Offset(w / 2, 16);
  canvas.drawCircle(pivot, 6, Paint()..color = const Color(0xFF0E2238));
  final angle = (sim?.servoAngles.values.isNotEmpty ?? false)
      ? sim!.servoAngles.values.first
      : ((c.params['angle'] as num?)?.toInt() ?? 0);
  final a = math.pi - (angle / 180.0) * math.pi; // 0°→right, 180°→left
  canvas.drawLine(
      pivot,
      Offset(pivot.dx + 22 * math.cos(a), pivot.dy - 22 * math.sin(a)),
      Paint()
        ..color = Colors.white
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round);
  _text(canvas, '$angle°', Offset(w / 2, h - 12),
      size: 8, color: Colors.white, align: TextAlign.center);
  final leg = Paint()
    ..color = const Color(0xFFB8923A)
    ..strokeWidth = 2.2;
  for (final p in c.def.pins) {
    canvas.drawLine(Offset(p.dx, h - 4), Offset(p.dx, p.dy), leg);
  }
}

void _drawTempSensor(Canvas canvas, HwComponent c) {
  final w = c.def.width;
  final t = (c.params['tempC'] as num?)?.toDouble() ?? 25.0;
  // TO-92 black half-dome.
  final body = Path()
    ..addArc(Rect.fromLTWH(w / 2 - 22, 8, 44, 44), math.pi, math.pi)
    ..lineTo(w / 2 + 22, 30)
    ..lineTo(w / 2 - 22, 30)
    ..close();
  canvas.drawPath(body, Paint()..color = const Color(0xFF14181C));
  canvas.drawPath(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = const Color(0xFFFB7185));
  _text(canvas, 'LM35', Offset(w / 2, 16), size: 7, color: Colors.white70, align: TextAlign.center);
  _text(canvas, '${t.toStringAsFixed(0)}°C', Offset(w / 2, 30),
      size: 9, color: const Color(0xFFFB7185), align: TextAlign.center, weight: FontWeight.w700);
  final leg = Paint()
    ..color = const Color(0xFFB8923A)
    ..strokeWidth = 2.2;
  for (final p in c.def.pins) {
    canvas.drawLine(Offset(p.dx, 46), Offset(p.dx, p.dy), leg);
  }
}

void _drawVibration(Canvas canvas, HwComponent c) {
  final w = c.def.width;
  final on = c.params['vibrating'] == true;
  _roundRect(canvas, Rect.fromLTWH(8, 8, w - 16, 50), const Color(0xFF2A2410),
      radius: 5, border: const Color(0xFFFACC15), bw: 1);
  // Spring coil.
  final coil = Paint()
    ..style = PaintingStyle.stroke
    ..color = const Color(0xFFC9A227)
    ..strokeWidth = 2;
  final p = Path();
  for (var i = 0; i <= 16; i++) {
    final x = 18.0 + i * ((w - 36) / 16);
    final y = 24.0 + (i.isEven ? -4 : 4) + (on ? (i.isEven ? -3 : 3) : 0);
    if (i == 0) {
      p.moveTo(x, y);
    } else {
      p.lineTo(x, y);
    }
  }
  canvas.drawPath(p, coil);
  canvas.drawCircle(Offset(w - 16, 46), 2.5,
      Paint()..color = on ? const Color(0xFFFACC15) : const Color(0xFF5C4D14));
  _text(canvas, 'SW-420', Offset(w / 2, 44), size: 6, color: Colors.white60, align: TextAlign.center);
  final leg = Paint()
    ..color = const Color(0xFFB8923A)
    ..strokeWidth = 2.2;
  for (final pin in c.def.pins) {
    canvas.drawLine(Offset(pin.dx, 58), Offset(pin.dx, pin.dy), leg);
  }
}

void _drawPir(Canvas canvas, HwComponent c) {
  final w = c.def.width;
  final on = c.params['motion'] == true;
  _roundRect(canvas, Rect.fromLTWH(8, 8, w - 16, 50), const Color(0xFF13182E),
      radius: 5, border: const Color(0xFF818CF8), bw: 1);
  // Fresnel dome.
  canvas.drawCircle(Offset(w / 2, 30), 16,
      Paint()..color = on ? const Color(0xFFB9C0FF) : const Color(0xFFE8EBFF));
  for (var i = 0; i < 4; i++) {
    canvas.drawCircle(Offset(w / 2, 30), 4.0 + i * 3,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = const Color(0xFF818CF8).withValues(alpha: 0.5));
  }
  if (on) {
    canvas.drawCircle(Offset(w / 2, 30), 22,
        Paint()..color = const Color(0xFF818CF8).withValues(alpha: 0.4)
          ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 6));
  }
  final leg = Paint()
    ..color = const Color(0xFFB8923A)
    ..strokeWidth = 2.2;
  for (final p in c.def.pins) {
    canvas.drawLine(Offset(p.dx, 58), Offset(p.dx, p.dy), leg);
  }
}

void _drawResistor(Canvas canvas, HwComponent c) {
  final w = c.def.width;
  final lead = Paint()
    ..color = const Color(0xFFB8923A)
    ..strokeWidth = 2.4;
  canvas.drawLine(const Offset(4, 14), const Offset(22, 14), lead);
  canvas.drawLine(Offset(w - 22, 14), Offset(w - 4, 14), lead);
  _roundRect(canvas, Rect.fromLTWH(20, 4, w - 40, 20), const Color(0xFFD9B98A),
      radius: 8, border: const Color(0xFFA07C46), bw: 1);
  // Colour bands for 220Ω (red-red-brown) by default; just decorative bands.
  const bandColors = [
    Color(0xFFD32F2F),
    Color(0xFFD32F2F),
    Color(0xFF6D4C41),
    Color(0xFFFFD700),
  ];
  for (var i = 0; i < bandColors.length; i++) {
    final x = 26.0 + i * 8;
    canvas.drawRect(Rect.fromLTWH(x, 4, 3, 20), Paint()..color = bandColors[i]);
  }
  final ohms = (c.params['ohms'] as num?)?.toInt() ?? 220;
  _text(canvas, '$ohms Ω', Offset(w / 2, 28),
      size: 7, color: Colors.white70, align: TextAlign.center);
}

void _drawPower(Canvas canvas, HwComponent c) {
  final w = c.def.width;
  _roundRect(canvas, Rect.fromLTWH(6, 6, w - 12, 50), const Color(0xFF0E2A1E),
      radius: 6, border: const Color(0xFF34D399), bw: 1.2);
  _text(canvas, 'PWR', Offset(w / 2, 14), size: 9, color: const Color(0xFF34D399), align: TextAlign.center);
  _text(canvas, '5V · 3V3', Offset(w / 2, 30), size: 8, color: Colors.white70, align: TextAlign.center);
  final leg = Paint()
    ..color = const Color(0xFFB8923A)
    ..strokeWidth = 2.2;
  for (final p in c.def.pins) {
    canvas.drawLine(Offset(p.dx, 56), Offset(p.dx, p.dy), leg);
    _text(canvas, p.name, Offset(p.dx, 44), size: 5, color: Colors.white60, align: TextAlign.center);
  }
}

void _drawGeneric(Canvas canvas, HwComponent c) {
  _roundRect(canvas, Rect.fromLTWH(0, 0, c.def.width, c.def.height),
      const Color(0xFF1B2433),
      radius: 6, border: c.def.accent, bw: 1);
  _text(canvas, c.def.shortName, Offset(c.def.width / 2, c.def.height / 2 - 6),
      size: 10, color: Colors.white, align: TextAlign.center);
}

// ── wires ──

/// Build a rounded-corner [Path] along an orthogonal polyline.
Path _wirePath(List<Offset> pts, {double radius = 7}) {
  final path = Path();
  if (pts.isEmpty) return path;
  if (pts.length == 1) {
    path.moveTo(pts.first.dx, pts.first.dy);
    return path;
  }
  path.moveTo(pts.first.dx, pts.first.dy);
  for (var i = 1; i < pts.length - 1; i++) {
    final prev = pts[i - 1], cur = pts[i], next = pts[i + 1];
    final v1 = cur - prev, v2 = next - cur;
    final l1 = v1.distance, l2 = v2.distance;
    final r = math.min(radius, math.min(l1, l2) / 2);
    if (r <= 0.5) {
      path.lineTo(cur.dx, cur.dy);
      continue;
    }
    final p1 = cur - v1 / l1 * r;
    final p2 = cur + v2 / l2 * r;
    path.lineTo(p1.dx, p1.dy);
    path.quadraticBezierTo(cur.dx, cur.dy, p2.dx, p2.dy);
  }
  path.lineTo(pts.last.dx, pts.last.dy);
  return path;
}

Offset _pointAlong(List<Offset> pts, double t) {
  if (pts.length < 2) return pts.isEmpty ? Offset.zero : pts.first;
  var total = 0.0;
  for (var i = 0; i < pts.length - 1; i++) {
    total += (pts[i + 1] - pts[i]).distance;
  }
  var target = total * t.clamp(0.0, 1.0);
  for (var i = 0; i < pts.length - 1; i++) {
    final seg = (pts[i + 1] - pts[i]).distance;
    if (target <= seg) {
      return Offset.lerp(pts[i], pts[i + 1], seg == 0 ? 0 : target / seg)!;
    }
    target -= seg;
  }
  return pts.last;
}

/// Draw a clean right-angle wire along [pts] with a hot glow when energised —
/// Proteus-style routing that never sinks under a component body.
void drawHwWire(Canvas canvas, List<Offset> pts, Color color,
    {bool hot = false, bool selected = false}) {
  if (pts.length < 2) return;
  final path = _wirePath(pts);
  if (selected) {
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..strokeJoin = StrokeJoin.round
          ..color = color.withValues(alpha: 0.3)
          ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 4));
  }
  if (hot) {
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7
          ..strokeJoin = StrokeJoin.round
          ..color = const Color(0xFF34D399).withValues(alpha: 0.35)
          ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 4));
  }
  // Shadow.
  canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.black.withValues(alpha: 0.35));
  canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 3.6 : 2.8
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color);
  // Endpoints.
  for (final p in [pts.first, pts.last]) {
    canvas.drawCircle(p, 3.2, Paint()..color = color);
    canvas.drawCircle(
        p, 1.4, Paint()..color = Colors.white.withValues(alpha: 0.8));
  }
}

/// Animated energy dot travelling along a hot wire (called with t in 0..1).
void drawHwWirePulse(Canvas canvas, List<Offset> pts, double t, Color color) {
  if (pts.length < 2) return;
  final at = _pointAlong(pts, t);
  canvas.drawCircle(
      at,
      3.5,
      Paint()
        ..color = color.withValues(alpha: 0.9)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 2));
}

/// The faint engineering grid behind the schematic.
void drawHwGrid(Canvas canvas, Rect visible, double scale) {
  final paint = Paint()
    ..color = const Color(0xFF22D3EE).withValues(alpha: 0.06)
    ..strokeWidth = 1 / scale;
  const step = kHwGrid;
  final startX = (visible.left / step).floor() * step;
  final startY = (visible.top / step).floor() * step;
  for (var x = startX; x < visible.right; x += step) {
    canvas.drawLine(Offset(x, visible.top), Offset(x, visible.bottom), paint);
  }
  for (var y = startY; y < visible.bottom; y += step) {
    canvas.drawLine(Offset(visible.left, y), Offset(visible.right, y), paint);
  }
}
