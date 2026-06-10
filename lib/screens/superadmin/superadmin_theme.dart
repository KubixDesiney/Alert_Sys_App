import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens for the SuperAdmin command console.
///
/// The console is intentionally always-dark: a deep-space navy command-center
/// look built on the same brand blues as the rest of Smart Industrial Alert,
/// with cyan/violet accents for AI surfaces.
class Sa {
  Sa._();

  static const Color bg = Color(0xFF040A18);
  static const Color bgRaised = Color(0xFF081127);
  static const Color panel = Color(0xC00B1530);
  static const Color panelSolid = Color(0xFF0B1530);
  static const Color border = Color(0xFF1B2A4A);
  static const Color borderBright = Color(0xFF2C4370);

  static const Color cyan = Color(0xFF22D3EE);
  static const Color blue = Color(0xFF3B82F6);
  static const Color violet = Color(0xFFA78BFA);
  static const Color green = Color(0xFF34D399);
  static const Color amber = Color(0xFFFBBF24);
  static const Color red = Color(0xFFF87171);
  static const Color pink = Color(0xFFF472B6);

  static const Color text = Color(0xFFE2E8F0);
  static const Color textDim = Color(0xFF94A3B8);
  static const Color muted = Color(0xFF64748B);

  static TextStyle display({double size = 22, Color color = text}) =>
      GoogleFonts.orbitron(
        fontSize: size,
        fontWeight: FontWeight.w700,
        color: color,
        letterSpacing: 1.2,
      );

  static TextStyle heading({double size = 15, Color color = text}) =>
      GoogleFonts.rajdhani(
        fontSize: size,
        fontWeight: FontWeight.w700,
        color: color,
        letterSpacing: 0.8,
      );

  static TextStyle body({double size = 13, Color color = text, FontWeight weight = FontWeight.w400}) =>
      TextStyle(fontSize: size, color: color, fontWeight: weight, height: 1.4);

  static TextStyle mono({double size = 12, Color color = text, FontWeight weight = FontWeight.w500}) =>
      GoogleFonts.jetBrainsMono(fontSize: size, color: color, fontWeight: weight);
}

/// Animated neural-mesh background: drifting nodes joined by proximity links
/// with pulses travelling along them. Pure vector motion graphics, wrapped in
/// a RepaintBoundary so it never invalidates the content above it.
class NeuralBackground extends StatefulWidget {
  final Widget child;
  const NeuralBackground({super.key, required this.child});

  @override
  State<NeuralBackground> createState() => _NeuralBackgroundState();
}

class _NeuralBackgroundState extends State<NeuralBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: const Duration(seconds: 60))
          ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(-0.6, -0.9),
              radius: 1.6,
              colors: [Color(0xFF0A1A38), Sa.bg],
            ),
          ),
        ),
        RepaintBoundary(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (_, __) => CustomPaint(
                painter: _NeuralPainter(_controller.value),
                size: Size.infinite,
              ),
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

class _NeuralPainter extends CustomPainter {
  final double t;
  _NeuralPainter(this.t);

  static const int _nodeCount = 42;
  static final List<_NodeSeed> _seeds = List.generate(
    _nodeCount,
    (i) {
      final rng = math.Random(i * 7919);
      return _NodeSeed(
        baseX: rng.nextDouble(),
        baseY: rng.nextDouble(),
        ampX: 0.015 + rng.nextDouble() * 0.04,
        ampY: 0.015 + rng.nextDouble() * 0.04,
        speed: 0.5 + rng.nextDouble() * 1.5,
        phase: rng.nextDouble() * math.pi * 2,
        radius: 1.2 + rng.nextDouble() * 1.8,
      );
    },
  );

  @override
  void paint(Canvas canvas, Size size) {
    final angle = t * math.pi * 2;

    // Faint perspective grid.
    final gridPaint = Paint()
      ..color = const Color(0x0E3B82F6)
      ..strokeWidth = 1;
    const gridStep = 64.0;
    for (var x = 0.0; x < size.width; x += gridStep) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (var y = 0.0; y < size.height; y += gridStep) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final positions = <Offset>[];
    for (final s in _seeds) {
      positions.add(Offset(
        (s.baseX + s.ampX * math.sin(angle * s.speed + s.phase)) * size.width,
        (s.baseY + s.ampY * math.cos(angle * s.speed + s.phase)) * size.height,
      ));
    }

    final linkPaint = Paint()..strokeWidth = 1;
    final maxDist = math.min(size.width, size.height) * 0.22;
    for (var i = 0; i < positions.length; i++) {
      for (var j = i + 1; j < positions.length; j++) {
        final d = (positions[i] - positions[j]).distance;
        if (d > maxDist) continue;
        final strength = 1 - d / maxDist;
        linkPaint.color =
            Color.lerp(const Color(0x0022D3EE), const Color(0x3322D3EE), strength)!;
        canvas.drawLine(positions[i], positions[j], linkPaint);

        // A pulse travelling along some links.
        if ((i + j) % 7 == 0) {
          final p = (t * 3 + i * 0.13 + j * 0.07) % 1.0;
          final pos = Offset.lerp(positions[i], positions[j], p)!;
          canvas.drawCircle(
            pos,
            1.6,
            Paint()..color = Color.lerp(Sa.cyan, Sa.violet, p)!.withValues(alpha: 0.5 * strength),
          );
        }
      }
    }

    for (var i = 0; i < positions.length; i++) {
      final s = _seeds[i];
      final glow = 0.35 + 0.25 * math.sin(angle * 2 + s.phase);
      canvas.drawCircle(
        positions[i],
        s.radius + 2.5,
        Paint()..color = Sa.cyan.withValues(alpha: 0.08 * glow),
      );
      canvas.drawCircle(
        positions[i],
        s.radius,
        Paint()..color = Sa.cyan.withValues(alpha: 0.5 * glow + 0.2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _NeuralPainter oldDelegate) => oldDelegate.t != t;
}

class _NodeSeed {
  final double baseX, baseY, ampX, ampY, speed, phase, radius;
  const _NodeSeed({
    required this.baseX,
    required this.baseY,
    required this.ampX,
    required this.ampY,
    required this.speed,
    required this.phase,
    required this.radius,
  });
}

/// Frosted glass panel with a soft glow border — the standard surface of the
/// console.
class GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color accent;
  final bool glow;

  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.accent = Sa.cyan,
    this.glow = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Sa.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: glow ? accent.withValues(alpha: 0.45) : Sa.border),
        boxShadow: [
          if (glow)
            BoxShadow(
              color: accent.withValues(alpha: 0.12),
              blurRadius: 24,
              spreadRadius: 1,
            ),
          const BoxShadow(
            color: Color(0x66000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Section header used at the top of every console panel.
class SaSectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color accent;
  final Widget? trailing;

  const SaSectionHeader({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.accent = Sa.cyan,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [accent.withValues(alpha: 0.25), accent.withValues(alpha: 0.06)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: accent.withValues(alpha: 0.5)),
          ),
          child: Icon(icon, color: accent, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Sa.heading(size: 16)),
              if (subtitle != null)
                Text(subtitle!, style: Sa.body(size: 11.5, color: Sa.textDim)),
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// Pill chip with optional pulsing dot.
class GlowChip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  final bool pulse;

  const GlowChip({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.pulse = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (pulse) ...[
            PulseDot(color: color),
            const SizedBox(width: 6),
          ] else if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 5),
          ],
          Text(label,
              style: Sa.mono(size: 10.5, color: color, weight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Animated pulsing dot used in LIVE badges.
class PulseDot extends StatefulWidget {
  final Color color;
  final double size;
  const PulseDot({super.key, required this.color, this.size = 7});

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final v = _c.value;
        return Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: widget.size + widget.size * 1.6 * v,
              height: widget.size + widget.size * 1.6 * v,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color.withValues(alpha: (1 - v) * 0.35),
              ),
            ),
            Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color),
            ),
          ],
        );
      },
    );
  }
}

/// Compact stat tile.
class SaStatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const SaStatTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Sa.bgRaised.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Sa.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(value, style: Sa.mono(size: 15, color: Sa.text, weight: FontWeight.w700)),
              Text(label.toUpperCase(),
                  style: Sa.mono(size: 8.5, color: Sa.muted, weight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Primary console button with gradient fill.
class SaButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color color;
  final bool busy;
  final bool outlined;

  const SaButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.color = Sa.cyan,
    this.busy = false,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null || busy;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: disabled ? 0.55 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: disabled ? null : onPressed,
          borderRadius: BorderRadius.circular(10),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
            decoration: BoxDecoration(
              gradient: outlined
                  ? null
                  : LinearGradient(
                      colors: [color.withValues(alpha: 0.85), color.withValues(alpha: 0.55)],
                    ),
              color: outlined ? Colors.transparent : null,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: outlined ? color.withValues(alpha: 0.6) : Colors.transparent),
              boxShadow: outlined || disabled
                  ? null
                  : [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 14)],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (busy)
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: outlined ? color : Sa.bg,
                    ),
                  )
                else
                  Icon(icon, size: 15, color: outlined ? color : const Color(0xFF03101F)),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: Sa.heading(
                    size: 13,
                    color: outlined ? color : const Color(0xFF03101F),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Console text field.
class SaTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool obscure;
  final TextInputType keyboard;
  final IconData? icon;

  const SaTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.obscure = false,
    this.keyboard = TextInputType.text,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboard,
      style: Sa.body(size: 13.5),
      cursorColor: Sa.cyan,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: Sa.body(size: 12.5, color: Sa.textDim),
        hintStyle: Sa.body(size: 12.5, color: Sa.muted),
        prefixIcon: icon != null ? Icon(icon, size: 17, color: Sa.muted) : null,
        filled: true,
        fillColor: Sa.bgRaised.withValues(alpha: 0.7),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Sa.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Sa.cyan),
        ),
      ),
    );
  }
}

/// Empty-state placeholder used across console tabs.
class SaEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Color accent;

  const SaEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.accent = Sa.cyan,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                accent.withValues(alpha: 0.18),
                accent.withValues(alpha: 0.02),
              ]),
              border: Border.all(color: accent.withValues(alpha: 0.35)),
            ),
            child: Icon(icon, color: accent, size: 30),
          ),
          const SizedBox(height: 16),
          Text(title, style: Sa.heading(size: 16)),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: Sa.body(size: 12.5, color: Sa.textDim),
            ),
          ),
        ],
      ),
    );
  }
}
