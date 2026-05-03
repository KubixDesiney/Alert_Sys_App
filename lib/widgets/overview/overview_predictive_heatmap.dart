part of '../../screens/admin_dashboard_screen.dart';

class _PredictiveRiskHeatmap extends StatelessWidget {
  final Map<String, Map<String, int>> stats;
  final PredictiveModel? model;
  final String? activeFilter;
  final void Function(String) onTap;
  const _PredictiveRiskHeatmap({
    required this.stats,
    required this.model,
    required this.activeFilter,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: theme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.border),
        boxShadow: [
          BoxShadow(
            color: theme.purple.withValues(alpha: context.isDark ? 0.06 : 0.03),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [theme.purple, theme.blue],
                  ),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(Icons.show_chart_rounded,
                    size: 14, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Predictive Risk · Next 24h',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: theme.text,
                      ),
                    ),
                    Text(
                      model == null
                          ? 'Awaiting first model from edge inference…'
                          : 'Probability per 2h window · tap row to filter history',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.muted,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: theme.purple.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bolt_rounded, size: 11, color: theme.purple),
                    const SizedBox(width: 3),
                    Text(
                      'ML',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: theme.purple,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...stats.entries.map((e) {
            final type = e.key;
            final past = e.value['total']!;
            final solved = e.value['solved']!;
            final curve = model?.curves[type];
            return _RiskCurveRow(
              type: type,
              past: past,
              solved: solved,
              curve: curve,
              isActive: activeFilter == type,
              onTap: () => onTap(type),
            );
          }),
        ],
      ),
    );
  }
}

class _RiskCurveRow extends StatefulWidget {
  final String type;
  final int past;
  final int solved;
  final RiskCurve? curve;
  final bool isActive;
  final VoidCallback onTap;
  const _RiskCurveRow({
    required this.type,
    required this.past,
    required this.solved,
    required this.curve,
    required this.isActive,
    required this.onTap,
  });

  @override
  State<_RiskCurveRow> createState() => _RiskCurveRowState();
}

class _RiskCurveRowState extends State<_RiskCurveRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _waveCtrl;

  @override
  void initState() {
    super.initState();
    _waveCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _waveCtrl.dispose();
    super.dispose();
  }

  String _riskLabel(double p) {
    if (p >= 0.7) return 'High';
    if (p >= 0.4) return 'Elevated';
    if (p >= 0.15) return 'Watch';
    return 'Low';
  }

  Color _riskColor(BuildContext ctx, double p) {
    final t = ctx.appTheme;
    if (p >= 0.7) return t.red;
    if (p >= 0.4) return t.orange;
    if (p >= 0.15) return t.yellow;
    return t.green;
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final color = _typeColor(widget.type);
    final curve = widget.curve;
    final p = curve?.total24h ?? 0;
    final riskColor = _riskColor(context, p);

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
        decoration: BoxDecoration(
          color: widget.isActive
              ? color.withValues(alpha: 0.08)
              : theme.scaffold.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color:
                widget.isActive ? color.withValues(alpha: 0.55) : theme.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        color.withValues(alpha: 0.85),
                        color.withValues(alpha: 0.55),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(_typeIcon(widget.type),
                      size: 15, color: Colors.white),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _typeLabel(widget.type),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: theme.text,
                        ),
                      ),
                      Text(
                        curve == null
                            ? '${widget.past} past · awaiting forecast'
                            : '${widget.past} past · ${widget.solved} resolved · peak @ ${curve.peakHour.toString().padLeft(2, '0')}:00',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: theme.muted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: riskColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(
                      color: riskColor.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    '${_riskLabel(p)} · ${(p * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: riskColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 38,
              child: AnimatedBuilder(
                animation: _waveCtrl,
                builder: (_, __) => CustomPaint(
                  painter: _WaveBarsPainter(
                    buckets: curve?.buckets ?? const [],
                    color: color,
                    waveT: _waveCtrl.value,
                    dark: context.isDark,
                  ),
                  size: Size.infinite,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  'now',
                  style: TextStyle(fontSize: 9.5, color: theme.muted),
                ),
                const Spacer(),
                Text(
                  '+12h',
                  style: TextStyle(fontSize: 9.5, color: theme.muted),
                ),
                const Spacer(),
                Text(
                  '+24h',
                  style: TextStyle(fontSize: 9.5, color: theme.muted),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WaveBarsPainter extends CustomPainter {
  final List<RiskBucket> buckets;
  final Color color;
  final double waveT;
  final bool dark;
  _WaveBarsPainter({
    required this.buckets,
    required this.color,
    required this.waveT,
    required this.dark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (buckets.isEmpty) {
      final p = Paint()
        ..color = color.withValues(alpha: 0.12)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(6)),
        p,
      );
      return;
    }

    final n = buckets.length;
    final gap = 3.0;
    final barW = (size.width - gap * (n - 1)) / n;
    final maxProb = buckets.map((b) => b.probability).fold<double>(0, math.max);
    final scale = maxProb <= 0 ? 0.0 : 1.0;

    for (var i = 0; i < n; i++) {
      final b = buckets[i];
      final x = i * (barW + gap);
      final mod = 0.85 + 0.15 * math.sin(waveT * math.pi * 2 + i * 0.45);
      final h = maxProb == 0
          ? 0.0
          : (b.probability / maxProb) * size.height * mod * scale;

      final rect = Rect.fromLTWH(x, size.height - h, barW, h);
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4));

      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            color.withValues(alpha: 0.95),
            color.withValues(alpha: 0.45),
          ],
        ).createShader(rect);
      canvas.drawRRect(rrect, paint);

      if (b.probability == maxProb && h > 4) {
        final glow = Paint()
          ..color = color.withValues(alpha: dark ? 0.45 : 0.30)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
        canvas.drawCircle(
          Offset(rect.center.dx, rect.top),
          barW * 0.55,
          glow,
        );
      }

      final base = Paint()
        ..color = color.withValues(alpha: 0.08)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, size.height - 2, barW, 2),
          const Radius.circular(2),
        ),
        base,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveBarsPainter old) =>
      old.buckets != buckets ||
      old.color != color ||
      old.waveT != waveT ||
      old.dark != dark;
}
