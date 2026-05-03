part of '../../screens/admin_dashboard_screen.dart';

class _EliteStatCard extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  final Color color;
  final Color accentLt;
  final List<int> spark;
  final double trendPct;
  final int? criticalCount;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback? onCriticalTap;

  const _EliteStatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.accentLt,
    required this.spark,
    required this.trendPct,
    required this.isActive,
    required this.onTap,
    this.criticalCount,
    this.onCriticalTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final isDark = context.isDark;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        decoration: BoxDecoration(
          gradient: isActive
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    accentLt,
                    theme.card,
                  ],
                )
              : null,
          color: isActive ? null : theme.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isActive ? color : theme.border,
            width: isActive ? 1.6 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: (isActive ? color : Colors.black)
                  .withValues(alpha: isDark ? 0.18 : (isActive ? 0.10 : 0.04)),
              blurRadius: isActive ? 14 : 8,
              offset: const Offset(0, 4),
            ),
          ],
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
                    color: color.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 16, color: color),
                ),
                const Spacer(),
                _TrendBadge(pct: trendPct),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                color: theme.muted,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 4),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: value.toDouble()),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (_, v, __) => Text(
                v.toInt().toString(),
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: color,
                  height: 1,
                  letterSpacing: -0.5,
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 28,
              child: spark.fold<int>(0, (a, b) => a + b) == 0
                  ? Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'No 7-day activity',
                        style: TextStyle(
                          fontSize: 10,
                          color: theme.muted,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    )
                  : CustomPaint(
                      painter: _SparklinePainter(data: spark, color: color),
                      size: Size.infinite,
                    ),
            ),
            if (criticalCount != null && criticalCount! > 0) ...[
              const SizedBox(height: 6),
              GestureDetector(
                onTap: onCriticalTap,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: theme.red.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          size: 11, color: theme.red),
                      const SizedBox(width: 3),
                      Text(
                        '$criticalCount critical',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: theme.red,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TrendBadge extends StatelessWidget {
  final double pct;
  const _TrendBadge({required this.pct});

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final isUp = pct > 0;
    final isFlat = pct.abs() < 0.5;
    final color = isFlat ? theme.muted : (isUp ? theme.green : theme.red);
    final icon = isFlat
        ? Icons.remove_rounded
        : (isUp ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded);
    final txt = isFlat ? '0%' : '${pct.abs().toStringAsFixed(0)}%';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 2),
          Text(
            txt,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<int> data;
  final Color color;
  _SparklinePainter({required this.data, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    final maxVal = data.reduce((a, b) => a > b ? a : b).toDouble();
    if (maxVal == 0) return;

    final n = data.length;
    final stepX = n > 1 ? size.width / (n - 1) : size.width;
    double yFor(int i) {
      final pad = size.height * 0.12;
      final usable = size.height - pad * 2;
      return pad + usable - (data[i] / maxVal) * usable;
    }

    final path = Path();
    final fill = Path();
    final firstY = yFor(0);
    path.moveTo(0, firstY);
    fill.moveTo(0, size.height);
    fill.lineTo(0, firstY);

    for (var i = 1; i < n; i++) {
      final x = i * stepX;
      final y = yFor(i);
      final prevX = (i - 1) * stepX;
      final prevY = yFor(i - 1);
      final cp1 = Offset(prevX + stepX / 2, prevY);
      final cp2 = Offset(x - stepX / 2, y);
      path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, x, y);
      fill.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, x, y);
    }
    fill.lineTo(size.width, size.height);
    fill.close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: 0.32),
          color.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(fill, fillPaint);

    final strokePaint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, strokePaint);

    final lastX = (n - 1) * stepX;
    final lastY = yFor(n - 1);
    final dotGlow = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(Offset(lastX, lastY), 4, dotGlow);
    final dot = Paint()..color = color;
    canvas.drawCircle(Offset(lastX, lastY), 2.5, dot);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter old) =>
      old.data != data || old.color != color;
}
