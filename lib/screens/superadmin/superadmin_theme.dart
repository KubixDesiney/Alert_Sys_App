import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../providers/motion_provider.dart';

/// One full color set for the command center. Two instances exist — deep-space
/// dark and arctic light — and [Sa] points at whichever the operator picked.
class SaPalette {
  final bool isDark;
  final Color bg;
  final Color bgRaised;
  final Color panel;
  final Color panelSolid;
  final Color border;
  final Color borderBright;
  final Color cyan;
  final Color blue;
  final Color violet;
  final Color green;
  final Color amber;
  final Color red;
  final Color pink;
  final Color text;
  final Color textDim;
  final Color muted;

  /// Foreground used on accent-filled surfaces (gradient buttons, logo tile).
  final Color onAccent;

  /// Drop shadow under panels.
  final Color shadow;

  const SaPalette({
    required this.isDark,
    required this.bg,
    required this.bgRaised,
    required this.panel,
    required this.panelSolid,
    required this.border,
    required this.borderBright,
    required this.cyan,
    required this.blue,
    required this.violet,
    required this.green,
    required this.amber,
    required this.red,
    required this.pink,
    required this.text,
    required this.textDim,
    required this.muted,
    required this.onAccent,
    required this.shadow,
  });
}

/// Design tokens for the SuperAdmin command center.
///
/// The console follows the app-wide theme: a deep-space navy command-center
/// look in dark mode and an arctic glass variant in light mode, built on the
/// same brand blues as the rest of SIAS with cyan/violet
/// accents for AI surfaces. Call [Sa.setDark] before building the console
/// subtree; every token below resolves against the active palette.
class Sa {
  Sa._();

  static const SaPalette darkPalette = SaPalette(
    isDark: true,
    bg: Color(0xFF040A18),
    bgRaised: Color(0xFF081127),
    panel: Color(0xC00B1530),
    panelSolid: Color(0xFF0B1530),
    border: Color(0xFF1B2A4A),
    borderBright: Color(0xFF2C4370),
    cyan: Color(0xFF22D3EE),
    blue: Color(0xFF3B82F6),
    violet: Color(0xFFA78BFA),
    green: Color(0xFF34D399),
    amber: Color(0xFFFBBF24),
    red: Color(0xFFF87171),
    pink: Color(0xFFF472B6),
    text: Color(0xFFE2E8F0),
    textDim: Color(0xFF94A3B8),
    muted: Color(0xFF64748B),
    onAccent: Color(0xFF03101F),
    shadow: Color(0x66000000),
  );

  static const SaPalette lightPalette = SaPalette(
    isDark: false,
    bg: Color(0xFFEDF2FA),
    bgRaised: Color(0xFFF7FAFF),
    panel: Color(0xE6FFFFFF),
    panelSolid: Color(0xFFFFFFFF),
    border: Color(0xFFD4DEF0),
    borderBright: Color(0xFFB4C5E4),
    cyan: Color(0xFF0E7490),
    blue: Color(0xFF2563EB),
    violet: Color(0xFF7C3AED),
    green: Color(0xFF047857),
    amber: Color(0xFFB45309),
    red: Color(0xFFDC2626),
    pink: Color(0xFFDB2777),
    text: Color(0xFF14233E),
    textDim: Color(0xFF4A5C7A),
    muted: Color(0xFF7787A3),
    onAccent: Color(0xFFFFFFFF),
    shadow: Color(0x1F35538A),
  );

  static SaPalette _p = darkPalette;

  static SaPalette get palette => _p;
  static bool get isDark => _p.isDark;

  /// Points the console tokens at the dark or light palette. Idempotent and
  /// cheap — called from the dashboard build whenever the app theme changes.
  static void setDark(bool dark) {
    _p = dark ? darkPalette : lightPalette;
  }

  static Color get bg => _p.bg;
  static Color get bgRaised => _p.bgRaised;
  static Color get panel => _p.panel;
  static Color get panelSolid => _p.panelSolid;
  static Color get border => _p.border;
  static Color get borderBright => _p.borderBright;
  static Color get cyan => _p.cyan;
  static Color get blue => _p.blue;
  static Color get violet => _p.violet;
  static Color get green => _p.green;
  static Color get amber => _p.amber;
  static Color get red => _p.red;
  static Color get pink => _p.pink;
  static Color get text => _p.text;
  static Color get textDim => _p.textDim;
  static Color get muted => _p.muted;
  static Color get onAccent => _p.onAccent;
  static Color get shadow => _p.shadow;

  // Terminal surfaces (console viewer, raw JSON, schema map) intentionally
  // stay dark in both themes — light-on-dark monospace is the readable
  // convention for logs.
  static const Color termBg = Color(0xFF030911);
  static const Color termBorder = Color(0xFF1B2A4A);
  static const Color termText = Color(0xFFE2E8F0);
  static const Color termDim = Color(0xFF94A3B8);
  static const Color termMuted = Color(0xFF64748B);

  /// Accessibility floor for on-screen console text. The command center is a
  /// dense desktop surface, so metadata labels may run small — but never below
  /// this. Enforced in [body]/[mono] so a stray `size: 7.5` can't ship an
  /// illegible label; call sites keep their intent, the token guarantees the
  /// minimum. (The miniature dashboard previews in the Theme studio use raw
  /// `TextStyle`, not these helpers, so their deliberate scale is unaffected.)
  static const double minLabelPx = 11;

  static TextStyle display({double size = 22, Color? color}) =>
      GoogleFonts.orbitron(
        fontSize: size,
        fontWeight: FontWeight.w700,
        color: color ?? _p.text,
        letterSpacing: 1.2,
      );

  static TextStyle heading({double size = 15, Color? color}) =>
      GoogleFonts.rajdhani(
        fontSize: size,
        fontWeight: FontWeight.w700,
        color: color ?? _p.text,
        letterSpacing: 0.8,
      );

  static TextStyle body(
          {double size = 13,
          Color? color,
          FontWeight weight = FontWeight.w400}) =>
      TextStyle(
          fontSize: math.max(size, minLabelPx),
          color: color ?? _p.text,
          fontWeight: weight,
          height: 1.4);

  static TextStyle mono(
          {double size = 12,
          Color? color,
          FontWeight weight = FontWeight.w500}) =>
      GoogleFonts.jetBrainsMono(
          fontSize: math.max(size, minLabelPx),
          color: color ?? _p.text,
          fontWeight: weight);
}

/// Animated neural-mesh background: drifting nodes joined by proximity links
/// with pulses travelling along them. Pure vector motion graphics, painted at
/// a capped ~30fps behind a RepaintBoundary so it never invalidates the
/// content above it and never causes layout work.
class NeuralBackground extends StatefulWidget {
  final Widget child;
  const NeuralBackground({super.key, required this.child});

  @override
  State<NeuralBackground> createState() => _NeuralBackgroundState();
}

class _NeuralBackgroundState extends State<NeuralBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final ValueNotifier<double> _tick = ValueNotifier<double>(0);
  int _lastFrameMs = 0;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: const Duration(seconds: 90))
          ..addListener(_onFrame)
          ..repeat();
  }

  void _onFrame() {
    // Cap the mesh at ~30fps — indistinguishable for slow drift, halves the
    // raster cost so foreground charts and transitions stay fluid.
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastFrameMs < 33) return;
    _lastFrameMs = now;
    _tick.value = _controller.value;
  }

  @override
  void dispose() {
    _controller.dispose();
    _tick.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Sa.isDark;
    // Respect the reduce-motion preference / OS accessibility flag: freeze the
    // mesh at a single calm frame instead of drifting it forever.
    final reduce = reduceMotionOf(context);
    if (reduce) {
      if (_controller.isAnimating) _controller.stop();
      _tick.value = 0.12;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-0.6, -0.9),
              radius: 1.6,
              colors: isDark
                  ? const [Color(0xFF0A1A38), Color(0xFF040A18)]
                  : const [Color(0xFFFDFEFF), Color(0xFFE7EEF9)],
            ),
          ),
        ),
        RepaintBoundary(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _NeuralPainter(tick: _tick, isDark: isDark),
              size: Size.infinite,
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

class _NeuralPainter extends CustomPainter {
  final ValueNotifier<double> tick;
  final bool isDark;

  _NeuralPainter({required this.tick, required this.isDark})
      : super(repaint: tick);

  static const int _nodeCount = 38;
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
    final t = tick.value;
    final angle = t * math.pi * 2;
    // Light mode keeps the mesh whisper-quiet so content contrast stays high.
    final dim = isDark ? 1.0 : 0.45;
    final nodeColor = isDark ? const Color(0xFF22D3EE) : const Color(0xFF2563EB);
    final linkColor = isDark ? const Color(0xFF22D3EE) : const Color(0xFF2563EB);
    final pulseA = isDark ? const Color(0xFF22D3EE) : const Color(0xFF0E7490);
    final pulseB = isDark ? const Color(0xFFA78BFA) : const Color(0xFF7C3AED);

    // Faint perspective grid.
    final gridPaint = Paint()
      ..color = (isDark ? const Color(0xFF3B82F6) : const Color(0xFF6E8BC7))
          .withValues(alpha: isDark ? 0.055 : 0.05)
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
            linkColor.withValues(alpha: 0.20 * strength * dim);
        canvas.drawLine(positions[i], positions[j], linkPaint);

        // A pulse travelling along some links.
        if ((i + j) % 7 == 0) {
          final p = (t * 3 + i * 0.13 + j * 0.07) % 1.0;
          final pos = Offset.lerp(positions[i], positions[j], p)!;
          canvas.drawCircle(
            pos,
            1.6,
            Paint()
              ..color = Color.lerp(pulseA, pulseB, p)!
                  .withValues(alpha: 0.5 * strength * dim),
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
        Paint()..color = nodeColor.withValues(alpha: 0.08 * glow * dim),
      );
      canvas.drawCircle(
        positions[i],
        s.radius,
        Paint()..color = nodeColor.withValues(alpha: (0.5 * glow + 0.2) * dim),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _NeuralPainter oldDelegate) =>
      oldDelegate.isDark != isDark;
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

/// Frosted glass panel with a gradient hairline border — the standard surface
/// of the console. The 1px gradient frame catches the accent at the top-left
/// corner and fades through the regular border color, which reads as premium
/// glass in both themes.
class GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? accent;
  final bool glow;

  const GlassPanel({
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
        borderRadius: BorderRadius.circular(17),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            a.withValues(alpha: glow ? 0.60 : 0.30),
            Sa.border,
            a.withValues(alpha: glow ? 0.28 : 0.08),
          ],
        ),
        boxShadow: [
          if (glow)
            BoxShadow(
              color: a.withValues(alpha: Sa.isDark ? 0.13 : 0.16),
              blurRadius: 26,
              spreadRadius: 1,
            ),
          BoxShadow(
            color: Sa.shadow,
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(1),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: Sa.panel,
          borderRadius: BorderRadius.circular(16),
        ),
        child: child,
      ),
    );
  }
}

/// Section header used at the top of every console panel.
class SaSectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? accent;
  final Widget? trailing;

  /// Optional custom leading widget rendered inside the accent tile in place
  /// of [icon] — used to surface an agent's brand logo in its panel header.
  final Widget? leading;

  const SaSectionHeader({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.accent,
    this.trailing,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    final a = accent ?? Sa.cyan;
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [a.withValues(alpha: 0.25), a.withValues(alpha: 0.06)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: a.withValues(alpha: 0.5)),
          ),
          child: leading ?? Icon(icon, color: a, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Sa.heading(size: 16)),
              if (subtitle != null)
                Text(subtitle!, style: Sa.body(size: 12.5, color: Sa.textDim)),
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// Pill chip with optional pulsing dot. Layout is fully stable: the pulse is
/// painted, never laid out, so the chip never jitters.
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
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0.16),
            color.withValues(alpha: 0.07),
          ],
        ),
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
              style: Sa.mono(size: 11.5, color: color, weight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Animated pulsing dot used in LIVE badges.
///
/// Occupies a fixed [size]×[size] box; the expanding ripple is painted past
/// the bounds (CustomPaint does not clip) so the surrounding layout never
/// shifts — this is what keeps status chips perfectly steady.
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
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1600))
      ..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // A calm, static dot (core + soft halo) when reduce-motion is requested.
    if (reduceMotionOf(context)) {
      if (_c.isAnimating) _c.stop();
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: Center(
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color,
              boxShadow: [
                BoxShadow(
                  color: widget.color.withValues(alpha: 0.35),
                  blurRadius: 3,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (!_c.isAnimating) _c.repeat();
    return RepaintBoundary(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: CustomPaint(
          painter: _PulseDotPainter(color: widget.color, tick: _c),
        ),
      ),
    );
  }
}

class _PulseDotPainter extends CustomPainter {
  final Color color;
  final Animation<double> tick;

  _PulseDotPainter({required this.color, required this.tick})
      : super(repaint: tick);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final core = size.shortestSide / 2;
    final v = Curves.easeOut.transform(tick.value);

    // Expanding ripple, fading out (painted beyond bounds, no layout impact).
    canvas.drawCircle(
      center,
      core + core * 1.6 * v,
      Paint()..color = color.withValues(alpha: (1 - v) * 0.30),
    );
    // Soft halo.
    canvas.drawCircle(
      center,
      core * 1.45,
      Paint()..color = color.withValues(alpha: 0.22),
    );
    // Core.
    canvas.drawCircle(center, core, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _PulseDotPainter oldDelegate) =>
      oldDelegate.color != color;
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
        color: Sa.bgRaised.withValues(alpha: Sa.isDark ? 0.8 : 0.9),
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
              Text(value,
                  style:
                      Sa.mono(size: 15, color: Sa.text, weight: FontWeight.w700)),
              Text(label.toUpperCase(),
                  style:
                      Sa.mono(size: 11, color: Sa.muted, weight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Primary console button with gradient fill, hover lift and glow.
class SaButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? color;
  final bool busy;
  final bool outlined;

  const SaButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.color,
    this.busy = false,
    this.outlined = false,
  });

  @override
  State<SaButton> createState() => _SaButtonState();
}

class _SaButtonState extends State<SaButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Sa.cyan;
    final disabled = widget.onPressed == null || widget.busy;
    final reduce = reduceMotionOf(context);
    final lifted = _hover && !disabled && !reduce;
    return MouseRegion(
      cursor: disabled ? MouseCursor.defer : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedOpacity(
        duration: Duration(milliseconds: reduce ? 0 : 200),
        opacity: disabled ? 0.55 : 1,
        child: AnimatedScale(
          scale: lifted ? 1.03 : 1.0,
          duration: Duration(milliseconds: reduce ? 0 : 150),
          curve: Curves.easeOut,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: disabled ? null : widget.onPressed,
              borderRadius: BorderRadius.circular(10),
              child: Ink(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                decoration: BoxDecoration(
                  gradient: widget.outlined
                      ? null
                      : LinearGradient(
                          colors: [
                            color.withValues(alpha: lifted ? 1.0 : 0.85),
                            color.withValues(alpha: lifted ? 0.75 : 0.55),
                          ],
                        ),
                  color: widget.outlined ? Colors.transparent : null,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: widget.outlined
                          ? color.withValues(alpha: lifted ? 0.9 : 0.6)
                          : Colors.transparent),
                  boxShadow: widget.outlined || disabled
                      ? null
                      : [
                          BoxShadow(
                            color: color.withValues(alpha: lifted ? 0.45 : 0.3),
                            blurRadius: lifted ? 18 : 14,
                          ),
                        ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.busy)
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: widget.outlined ? color : Sa.onAccent,
                        ),
                      )
                    else
                      Icon(widget.icon,
                          size: 15,
                          color: widget.outlined ? color : Sa.onAccent),
                    const SizedBox(width: 8),
                    Text(
                      widget.label,
                      style: Sa.heading(
                        size: 13,
                        color: widget.outlined ? color : Sa.onAccent,
                      ),
                    ),
                  ],
                ),
              ),
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
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Sa.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Sa.cyan),
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
  final Color? accent;

  const SaEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final a = accent ?? Sa.cyan;
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
                a.withValues(alpha: 0.18),
                a.withValues(alpha: 0.02),
              ]),
              border: Border.all(color: a.withValues(alpha: 0.35)),
            ),
            child: Icon(icon, color: a, size: 30),
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
