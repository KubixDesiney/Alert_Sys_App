import 'package:flutter/material.dart';

import '../../models/alert_model.dart';
import '../../services/predictive_intel_service.dart';
import '../../services/predictive_models.dart';
import '../../services/service_locator.dart';
import '../../theme.dart';
import '../../utils/alert_meta.dart';

class CriticalAlertsCard extends StatelessWidget {
  final List<AlertModel> alerts;
  final void Function(AlertModel) onAlertTap;
  final String Function(AlertModel) describe;
  const CriticalAlertsCard({
    required this.alerts,
    required this.onAlertTap,
    required this.describe,
  });

  Widget _alertTile(BuildContext context, AlertModel alert) {
    return _CriticalAlertRowAI(
      alert: alert,
      describe: describe,
      onAlertTap: () => onAlertTap(alert),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: theme.redLt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.red.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            color: theme.red.withValues(alpha: 0.15),
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
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: theme.red.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.warning_amber_rounded,
                    size: 17, color: theme.red),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Critical · ${alerts.length} pending',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: theme.red,
                      ),
                    ),
                    Text(
                      'Awaiting assignment for over 10 minutes',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.red.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...alerts.map((a) => _alertTile(context, a)),
        ],
      ),
    );
  }
}

class _CriticalAlertRowAI extends StatefulWidget {
  final AlertModel alert;
  final String Function(AlertModel) describe;
  final VoidCallback onAlertTap;
  const _CriticalAlertRowAI({
    required this.alert,
    required this.describe,
    required this.onAlertTap,
  });

  @override
  State<_CriticalAlertRowAI> createState() => _CriticalAlertRowAIState();
}

class _CriticalAlertRowAIState extends State<_CriticalAlertRowAI>
    with SingleTickerProviderStateMixin {
  AssigneeSuggestion? _suggestion;
  bool _loading = false;
  bool _assigning = false;
  String? _assignError;
  bool _assignedDone = false;
  late final AnimationController _glowCtrl;

  @override
  void initState() {
    super.initState();
    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _loadSuggestion();
  }

  @override
  void dispose() {
    _glowCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSuggestion() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final s =
        await PredictiveIntelService.instance.suggestAssignee(widget.alert.id);
    if (!mounted) return;
    setState(() {
      _suggestion = s;
      _loading = false;
    });
  }

  Future<void> _assign() async {
    final s = _suggestion;
    if (s == null || s.bestUid == null || _assigning || _assignedDone) return;
    setState(() {
      _assigning = true;
      _assignError = null;
    });
    try {
      await ServiceLocator.instance.alertService.takeAlert(
        widget.alert.id,
        s.bestUid!,
        s.bestName ?? 'AI assignment',
      );
      if (!mounted) return;
      setState(() {
        _assigning = false;
        _assignedDone = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _assigning = false;
        _assignError = 'Failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final alert = widget.alert;
    final elapsedMin = DateTime.now().difference(alert.timestamp).inMinutes;
    final elapsedText = elapsedMin < 60
        ? '${elapsedMin}m'
        : '${elapsedMin ~/ 60}h ${elapsedMin % 60}m';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: theme.card,
        border: Border.all(color: theme.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: widget.onAlertTap,
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 36,
                  decoration: BoxDecoration(
                    color: typeMeta(alert.type, context.appTheme).color,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${typeMeta(alert.type, context.appTheme).label} — ${widget.describe(alert)}',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: theme.text,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${alert.usine} · Line ${alert.convoyeur} · WS ${alert.poste}',
                        style: TextStyle(fontSize: 11, color: theme.muted),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.red.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(99),
                    border:
                        Border.all(color: theme.red.withValues(alpha: 0.35)),
                  ),
                  child: Text(
                    elapsedText,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: theme.red,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 9),
          _buildSuggestionStrip(theme),
        ],
      ),
    );
  }

  Widget _buildSuggestionStrip(AppTheme theme) {
    if (_loading) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: theme.purple.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: theme.purple.withValues(alpha: 0.18)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.6,
                valueColor: AlwaysStoppedAnimation(theme.purple),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'AI is matching the best supervisor…',
              style: TextStyle(
                fontSize: 11.5,
                color: theme.purple,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    if (_assignedDone) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: theme.green.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: theme.green.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle_rounded, size: 14, color: theme.green),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Assigned to ${_suggestion?.bestName ?? 'supervisor'} — supervisor notified.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: theme.green,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final s = _suggestion;
    if (s == null || s.bestUid == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: theme.scaffold.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: theme.border),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 13, color: theme.muted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'No eligible supervisor right now.',
                style: TextStyle(fontSize: 11, color: theme.muted),
              ),
            ),
            TextButton(
              onPressed: _loadSuggestion,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                minimumSize: const Size(0, 28),
              ),
              child: Text(
                'Retry',
                style: TextStyle(
                  fontSize: 11,
                  color: theme.navy,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return AnimatedBuilder(
      animation: _glowCtrl,
      builder: (_, __) {
        final glow = 0.18 + 0.12 * _glowCtrl.value;
        return Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                theme.purple.withValues(alpha: 0.15),
                theme.blue.withValues(alpha: 0.10),
              ],
            ),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: theme.purple.withValues(alpha: 0.30)),
            boxShadow: [
              BoxShadow(
                color: theme.purple.withValues(alpha: glow),
                blurRadius: 12,
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(Icons.auto_awesome_rounded, size: 14, color: theme.purple),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(
                          text: 'AI suggests: ',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: theme.muted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        TextSpan(
                          text: s.bestName ?? 'supervisor',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: theme.text,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        TextSpan(
                          text: '  ·  ${s.confidencePct}% match',
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.purple,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ]),
                    ),
                    if (s.reasons.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Text(
                          s.reasons.take(2).join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: theme.muted,
                          ),
                        ),
                      ),
                    if (_assignError != null)
                      Text(
                        _assignError!,
                        style: TextStyle(fontSize: 10.5, color: theme.red),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              ElevatedButton(
                onPressed: _assigning ? null : _assign,
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.purple,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                child: _assigning
                    ? const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.6,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      )
                    : const Text('Assign'),
              ),
            ],
          ),
        );
      },
    );
  }
}
