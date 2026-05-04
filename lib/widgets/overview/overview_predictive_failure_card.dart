import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/predictive_models.dart';
import '../../theme.dart';
import '../../utils/alert_meta.dart';

class PredictiveFailureCard extends StatefulWidget {
  final PredictiveModel? model;
  final String Function(String) describeType;
  const PredictiveFailureCard({
    required this.model,
    required this.describeType,
  });

  @override
  State<PredictiveFailureCard> createState() => _PredictiveFailureCardState();
}

class _PredictiveFailureCardState extends State<PredictiveFailureCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer;

  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final isDark = context.isDark;
    final preds = widget.model?.predictions ?? const <PredictedFailure>[];
    final top = preds.take(5).toList();

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  const Color(0xFF1B1230),
                  const Color(0xFF0F1B30),
                ]
              : [
                  const Color(0xFFF5F0FF),
                  const Color(0xFFEFF6FF),
                ],
        ),
        border: Border.all(color: theme.purple.withValues(alpha: 0.32)),
        boxShadow: [
          BoxShadow(
            color: theme.purple.withValues(alpha: isDark ? 0.18 : 0.10),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AnimatedBuilder(
                  animation: _shimmer,
                  builder: (_, __) {
                    final t = _shimmer.value;
                    return Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        gradient: SweepGradient(
                          startAngle: 0,
                          endAngle: math.pi * 2,
                          transform: GradientRotation(t * math.pi * 2),
                          colors: [
                            theme.purple,
                            theme.blue,
                            theme.purple,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(11),
                        boxShadow: [
                          BoxShadow(
                            color: theme.purple.withValues(alpha: 0.35),
                            blurRadius: 14,
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(Icons.psychology_alt_rounded,
                            size: 19, color: Colors.white),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Predictive Failure Alerts',
                            style: TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w800,
                              color: theme.text,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: theme.purple.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              'BETA',
                              style: TextStyle(
                                fontSize: 8.5,
                                fontWeight: FontWeight.w900,
                                color: theme.purple,
                                letterSpacing: 1.1,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        widget.model == null
                            ? 'Edge model warming up — first inference within 60s.'
                            : 'Top probable next failures · trained on last ${widget.model!.predictions.isEmpty ? 30 : 30}d',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: theme.muted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.model != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.card,
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: theme.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: theme.green,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: theme.green.withValues(alpha: 0.6),
                                blurRadius: 5,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'LIVE',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: theme.text,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            if (top.isEmpty)
              Container(
                padding: const EdgeInsets.all(18),
                alignment: Alignment.center,
                child: Column(
                  children: [
                    Icon(Icons.science_outlined, size: 32, color: theme.purple),
                    const SizedBox(height: 8),
                    Text(
                      'Not enough history yet',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: theme.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'The model needs a few days of alerts to learn patterns.',
                      style: TextStyle(fontSize: 11, color: theme.muted),
                    ),
                  ],
                ),
              )
            else
              ...top.asMap().entries.map((e) => _PredictedFailureRow(
                    rank: e.key + 1,
                    failure: e.value,
                    describeType: widget.describeType,
                  )),
          ],
        ),
      ),
    );
  }
}

class _PredictedFailureRow extends StatelessWidget {
  final int rank;
  final PredictedFailure failure;
  final String Function(String) describeType;
  const _PredictedFailureRow({
    required this.rank,
    required this.failure,
    required this.describeType,
  });

  String _eta() {
    final h = failure.etaHours;
    if (h == null) return 'No ETA yet';
    if (h <= 0) return 'Overdue · expected';
    if (h < 1) return 'Within ${(h * 60).round()} min';
    if (h < 24) return 'In ~${h.toStringAsFixed(1)}h';
    final d = (h / 24).round();
    return 'In ~${d}d';
  }

  String _lastSeen() {
    final t = failure.lastTs;
    if (t == null) return 'never';
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final meta = typeMeta(failure.type, context.appTheme);
    final tColor = meta.color;
    final conf = failure.confidence.clamp(0, 100).toDouble();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: theme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [theme.purple, theme.blue],
                  ),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Center(
                  child: Text(
                    '$rank',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: tColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(meta.icon, size: 11, color: tColor),
                    const SizedBox(width: 4),
                    Text(
                      describeType(failure.type),
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: tColor,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                '${conf.toInt()}%',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: theme.purple,
                ),
              ),
              const SizedBox(width: 2),
              Text(
                'conf.',
                style: TextStyle(
                  fontSize: 9,
                  color: theme.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${failure.usine.isNotEmpty ? failure.usine : failure.factoryId} · Line ${failure.convoyeur} · WS ${failure.poste}',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: theme.text,
            ),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: SizedBox(
              height: 6,
              child: Stack(
                children: [
                  Container(color: theme.border),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: conf / 100),
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.easeOutCubic,
                    builder: (_, w, __) => FractionallySizedBox(
                      widthFactor: w.clamp(0.0, 1.0),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [theme.purple, theme.blue],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.history_toggle_off_rounded,
                  size: 11, color: theme.muted),
              const SizedBox(width: 3),
              Text(
                'Last ${_lastSeen()}',
                style: TextStyle(fontSize: 10.5, color: theme.muted),
              ),
              const SizedBox(width: 10),
              Icon(Icons.timer_outlined, size: 11, color: theme.orange),
              const SizedBox(width: 3),
              Text(
                _eta(),
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: theme.orange,
                ),
              ),
              const Spacer(),
              if (failure.criticalCount > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.red.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    '${failure.criticalCount} critical',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: theme.red,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
