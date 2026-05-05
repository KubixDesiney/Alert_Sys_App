import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/predictive_intel_service.dart';
import '../../theme.dart';
import '../../utils/alert_meta.dart';

class AIMorningBriefingHero extends StatefulWidget {
  final MorningBriefing? briefing;
  final String timeRangeLabel;
  final String timeRangeSubtitle;
  final Future<void> Function() onRefresh;
  final bool compact;
  const AIMorningBriefingHero({
    required this.briefing,
    required this.timeRangeLabel,
    required this.timeRangeSubtitle,
    required this.onRefresh,
    this.compact = false,
  });

  @override
  State<AIMorningBriefingHero> createState() => _AIMorningBriefingHeroState();
}

class _AIMorningBriefingHeroState extends State<AIMorningBriefingHero>
    with TickerProviderStateMixin {
  late final AnimationController _meshCtrl;
  late final AnimationController _sparkleCtrl;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _meshCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat();
    _sparkleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
  }

  @override
  void dispose() {
    _meshCtrl.dispose();
    _sparkleCtrl.dispose();
    super.dispose();
  }

  String _fallbackGreeting() {
    final h = DateTime.now().hour;
    if (h < 5) return 'Working late';
    if (h < 12) return 'Good morning';
    if (h < 18) return 'Good afternoon';
    return 'Good evening';
  }

  String _displaySummary() {
    final b = widget.briefing;
    if (b != null && b.summary.trim().isNotEmpty) return b.summary.trim();
    return '${_fallbackGreeting()}, supervisor. Your AI briefing is warming up — historical patterns are being analysed in the background. Hard data and a personalised summary will land here within the next minute.';
  }

  String _modelLabel() {
    final b = widget.briefing;
    if (b == null) return 'AI BRIEFING · WARMING UP';
    if (b.model == null || b.model == 'fallback') {
      return 'AI BRIEFING · OFFLINE FALLBACK';
    }
    return 'AI BRIEFING · LLAMA 3.2';
  }

  String _generatedLabel() {
    final ts = widget.briefing?.generatedAt;
    if (ts == null) return 'just now';
    final dt = DateTime.tryParse(ts);
    if (dt == null) return 'just now';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'moments ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Future<void> _doRefresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    await widget.onRefresh();
    if (mounted) setState(() => _refreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final summary = _displaySummary();
    final b = widget.briefing;
    final compact = widget.compact;

    final pad = compact
        ? const EdgeInsets.fromLTRB(16, 12, 14, 12)
        : const EdgeInsets.fromLTRB(20, 18, 18, 20);
    final titleSize = compact ? 16.5 : 22.0;
    final summarySize = compact ? 12.0 : 13.5;
    final summaryMaxLines = compact ? 2 : 6;
    final spacingTitle = compact ? 6.0 : 14.0;
    final spacingAfterSummary = compact ? 8.0 : 14.0;
    final spacingAfterChips = compact ? 8.0 : 12.0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(compact ? 16 : 20),
      child: Stack(
        children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _meshCtrl,
              builder: (_, __) => CustomPaint(
                painter: _AuroraMeshPainter(
                  t: _meshCtrl.value,
                  dark: isDark,
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _sparkleCtrl,
                builder: (_, __) => CustomPaint(
                  painter: _SparklePainter(t: _sparkleCtrl.value),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.black.withValues(alpha: isDark ? 0.18 : 0.05),
                    Colors.black.withValues(alpha: isDark ? 0.42 : 0.20),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: pad,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const _LivePulseDot(),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.auto_awesome_rounded,
                                size: 11, color: Colors.white),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                _modelLabel(),
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.4,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: EdgeInsets.symmetric(
                          horizontal: compact ? 8 : 10,
                          vertical: compact ? 4 : 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.calendar_month_rounded,
                              size: 12, color: Colors.white),
                          const SizedBox(width: 5),
                          Text(
                            widget.timeRangeLabel,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: spacingTitle),
                ShaderMask(
                  shaderCallback: (rect) => const LinearGradient(
                    colors: [Colors.white, Color(0xFFE0E7FF)],
                  ).createShader(rect),
                  child: Text(
                    'Operations Briefing',
                    style: TextStyle(
                      fontSize: titleSize,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      height: 1.1,
                      letterSpacing: -0.4,
                    ),
                  ),
                ),
                SizedBox(height: compact ? 6 : 10),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 480),
                  child: Text(
                    summary,
                    key: ValueKey(summary.hashCode),
                    maxLines: summaryMaxLines,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: summarySize,
                      color: Colors.white.withValues(alpha: 0.92),
                      height: compact ? 1.35 : 1.55,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(height: spacingAfterSummary),
                Wrap(
                  spacing: 6,
                  runSpacing: 5,
                  children: [
                    if (b?.topType != null)
                      _briefChip(
                        Icons.local_fire_department_rounded,
                        '${typeMeta(b!.topType!, context.appTheme).label} · ${b.topTypeCount}',
                      ),
                    if (b?.topFactory != null && !compact)
                      _briefChip(
                        Icons.factory_rounded,
                        '${b!.topFactory} most active',
                      ),
                    if (b != null)
                      _briefChip(
                        Icons.trending_up_rounded,
                        '${b.resolutionRate}% resolved',
                      ),
                    _briefChip(
                      Icons.schedule_rounded,
                      'Updated ${_generatedLabel()}',
                    ),
                  ],
                ),
                SizedBox(height: spacingAfterChips),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.timeRangeSubtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.72),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(99),
                        onTap: _doRefresh,
                        child: Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: compact ? 10 : 12,
                              vertical: compact ? 5 : 7),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.white.withValues(alpha: 0.22),
                                Colors.white.withValues(alpha: 0.10),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(99),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_refreshing)
                                const SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.6,
                                    valueColor:
                                        AlwaysStoppedAnimation(Colors.white),
                                  ),
                                )
                              else
                                const Icon(Icons.auto_awesome_rounded,
                                    size: 13, color: Colors.white),
                              const SizedBox(width: 5),
                              Text(
                                _refreshing ? 'Generating…' : 'Regenerate',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _briefChip(IconData icon, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 11, color: Colors.white.withValues(alpha: 0.92)),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: Colors.white.withValues(alpha: 0.95),
              letterSpacing: 0.2,
            ),
          ),
        ]),
      );
}

class _AuroraMeshPainter extends CustomPainter {
  final double t;
  final bool dark;
  _AuroraMeshPainter({required this.t, required this.dark});

  @override
  void paint(Canvas canvas, Size size) {
    final base = dark
        ? const [Color(0xFF0B1E3F), Color(0xFF1E2A4D)]
        : const [Color(0xFF0D4A75), Color(0xFF1E5C8C)];
    final bgPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: base,
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, bgPaint);

    final twoPi = math.pi * 2;
    final blobs = [
      _Blob(
        center: Offset(
          size.width * (0.20 + 0.18 * math.sin(twoPi * t)),
          size.height * (0.30 + 0.18 * math.cos(twoPi * t * 0.9)),
        ),
        radius: size.width * 0.55,
        color: dark
            ? const Color(0xFF6366F1).withValues(alpha: 0.35)
            : const Color(0xFF60A5FA).withValues(alpha: 0.55),
      ),
      _Blob(
        center: Offset(
          size.width * (0.78 + 0.10 * math.cos(twoPi * (t + 0.33))),
          size.height * (0.65 + 0.18 * math.sin(twoPi * (t + 0.33))),
        ),
        radius: size.width * 0.55,
        color: dark
            ? const Color(0xFF8B5CF6).withValues(alpha: 0.32)
            : const Color(0xFFC084FC).withValues(alpha: 0.45),
      ),
      _Blob(
        center: Offset(
          size.width * (0.52 + 0.20 * math.sin(twoPi * (t + 0.66))),
          size.height * (0.85 + 0.15 * math.cos(twoPi * (t + 0.66))),
        ),
        radius: size.width * 0.55,
        color: dark
            ? const Color(0xFF06B6D4).withValues(alpha: 0.28)
            : const Color(0xFF38BDF8).withValues(alpha: 0.40),
      ),
    ];

    for (final b in blobs) {
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [b.color, b.color.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: b.center, radius: b.radius))
        ..blendMode = BlendMode.plus;
      canvas.drawCircle(b.center, b.radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _AuroraMeshPainter old) =>
      old.t != t || old.dark != dark;
}

class _Blob {
  final Offset center;
  final double radius;
  final Color color;
  _Blob({required this.center, required this.radius, required this.color});
}

class _SparklePainter extends CustomPainter {
  final double t;
  _SparklePainter({required this.t});

  static final List<_Sparkle> _seeds = List.generate(28, (i) {
    final r = math.Random(i * 7 + 11);
    return _Sparkle(
      x: r.nextDouble(),
      yOffset: r.nextDouble(),
      speed: 0.20 + r.nextDouble() * 0.55,
      size: 0.6 + r.nextDouble() * 1.8,
      phase: r.nextDouble(),
    );
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white;
    for (final s in _seeds) {
      final progress = ((t * s.speed) + s.phase) % 1.0;
      final y = (1 - progress) * size.height;
      final x =
          s.x * size.width + math.sin((progress + s.phase) * math.pi * 2) * 8;
      final twinkle = 0.5 + 0.5 * math.sin((t + s.phase) * math.pi * 4);
      final alpha = (twinkle * (1 - progress) * 0.7).clamp(0.0, 1.0);
      paint.color = Colors.white.withValues(alpha: alpha);
      canvas.drawCircle(Offset(x, y + s.yOffset * 6), s.size, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SparklePainter old) => old.t != t;
}

class _Sparkle {
  final double x, yOffset, speed, size, phase;
  _Sparkle({
    required this.x,
    required this.yOffset,
    required this.speed,
    required this.size,
    required this.phase,
  });
}

class _LivePulseDot extends StatefulWidget {
  const _LivePulseDot();

  @override
  State<_LivePulseDot> createState() => _LivePulseDotState();
}

class _LivePulseDotState extends State<_LivePulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 12,
      height: 12,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) {
          final t = _ctrl.value;
          final scale = 1.0 + t * 1.4;
          final opacity = (1.0 - t).clamp(0.0, 1.0);
          return Stack(
            alignment: Alignment.center,
            children: [
              Transform.scale(
                scale: scale,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: const Color(0xFF4ADE80)
                        .withValues(alpha: opacity * 0.6),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: Color(0xFF4ADE80),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x664ADE80),
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
