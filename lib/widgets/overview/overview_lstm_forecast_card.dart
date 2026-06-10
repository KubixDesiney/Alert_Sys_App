import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../../models/alert_model.dart';
import '../../services/lstm/lstm_forecast_engine.dart';
import '../../services/lstm/lstm_model_store.dart';
import '../../services/lstm/lstm_types.dart';
import '../../theme.dart';

/// Live LSTM forecast card on the Production Manager overview.
///
/// Loads the SuperAdmin-trained network from `ai_lstm/model` and runs real
/// on-device inference over the alert stream this dashboard already holds.
/// Every new alert (and every model redeploy) recomputes the next-24h risk
/// per machine — no external inference service in the path.
class LstmForecastCard extends StatefulWidget {
  final List<AlertModel> alerts;
  final String selectedUsine; // 'all' or a factory name

  const LstmForecastCard({
    super.key,
    required this.alerts,
    required this.selectedUsine,
  });

  @override
  State<LstmForecastCard> createState() => _LstmForecastCardState();
}

class _LstmForecastCardState extends State<LstmForecastCard> {
  final _store = LstmModelStore();
  StreamSubscription<TrainedLstmModel?>? _modelSub;
  TrainedLstmModel? _model;
  List<MachineForecast> _forecasts = const [];
  DateTime? _computedAt;
  int _lastAlertCount = -1;
  bool _publishedRecently = false;

  @override
  void initState() {
    super.initState();
    _modelSub = _store.modelStream().listen((m) {
      _model = m;
      _recompute(force: true);
    }, onError: (_) {});
  }

  @override
  void didUpdateWidget(covariant LstmForecastCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.alerts.length != _lastAlertCount) {
      _recompute();
    }
  }

  @override
  void dispose() {
    _modelSub?.cancel();
    super.dispose();
  }

  void _recompute({bool force = false}) {
    final model = _model;
    if (!mounted) return;
    if (model == null) {
      setState(() => _forecasts = const []);
      return;
    }
    // Throttle: new alerts arrive in bursts; one inference pass per 15s is
    // plenty while staying visibly real-time.
    if (!force &&
        _computedAt != null &&
        DateTime.now().difference(_computedAt!) <
            const Duration(seconds: 15) &&
        widget.alerts.length == _lastAlertCount) {
      return;
    }
    _lastAlertCount = widget.alerts.length;
    final records = widget.alerts
        .map((a) => AlertRecord(
              timestamp: a.timestamp,
              type: a.type,
              usine: a.usine,
              convoyeur: a.convoyeur,
              poste: a.poste,
              isCritical: a.isCritical,
            ))
        .toList();
    final forecasts = LstmForecastEngine.computeForecasts(model, records);
    setState(() {
      _forecasts = forecasts;
      _computedAt = DateTime.now();
    });
    _maybePublish(forecasts);
  }

  /// Keeps `ai_predictions/lstm` fresh for the rest of the platform without
  /// letting every open dashboard spam writes.
  Future<void> _maybePublish(List<MachineForecast> forecasts) async {
    if (_publishedRecently || forecasts.isEmpty) return;
    _publishedRecently = true;
    Timer(const Duration(minutes: 10), () => _publishedRecently = false);
    try {
      final snap = await FirebaseDatabase.instance
          .ref('ai_predictions/lstm/generatedAt')
          .get();
      final last = DateTime.tryParse((snap.value ?? '').toString());
      if (last != null &&
          DateTime.now().toUtc().difference(last.toUtc()) <
              const Duration(minutes: 10)) {
        return;
      }
      await LstmForecastEngine.publishSnapshot(forecasts);
    } catch (_) {
      // Display stays local-only when the write is not permitted.
    }
  }

  List<MachineForecast> get _scoped => widget.selectedUsine == 'all'
      ? _forecasts
      : _forecasts.where((f) => f.usine == widget.selectedUsine).toList();

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final model = _model;
    final scoped = _scoped.take(6).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    t.purple.withValues(alpha: 0.25),
                    t.blue.withValues(alpha: 0.12),
                  ]),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.psychology_outlined, size: 18, color: t.purple),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'LSTM Live Forecast',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: t.textDark,
                      ),
                    ),
                    Text(
                      'Next 24h machine risk · on-device neural inference',
                      style: TextStyle(fontSize: 10.5, color: t.muted),
                    ),
                  ],
                ),
              ),
              if (model != null) _LiveBadge(color: t.green),
            ],
          ),
          const SizedBox(height: 14),
          if (model == null)
            _emptyState(t)
          else if (scoped.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: Text(
                  'Not enough recent history for this scope — forecasts appear '
                  'as alert history accumulates.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: t.muted),
                ),
              ),
            )
          else ...[
            for (final f in scoped) _MachineRiskRow(forecast: f),
            const SizedBox(height: 10),
            _modelFooter(t, model),
          ],
        ],
      ),
    );
  }

  Widget _emptyState(AppTheme t) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
      decoration: BoxDecoration(
        color: t.scaffold,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.border),
      ),
      child: Column(
        children: [
          Icon(Icons.hub_outlined, size: 28, color: t.muted),
          const SizedBox(height: 10),
          Text(
            'No LSTM model deployed yet',
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: t.textDark),
          ),
          const SizedBox(height: 4),
          Text(
            'The SuperAdmin trains and deploys the forecaster from the AI '
            'Training console. Forecasts go live here instantly after deploy.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: t.muted),
          ),
        ],
      ),
    );
  }

  Widget _modelFooter(AppTheme t, TrainedLstmModel model) {
    final trained = model.trainedAt == null
        ? '—'
        : _agoLabel(DateTime.now().toUtc().difference(model.trainedAt!.toUtc()));
    return Row(
      children: [
        Icon(
          model.learning ? Icons.verified : Icons.info_outline,
          size: 13,
          color: model.learning ? t.green : t.orange,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '${model.learning ? 'Learning verified' : 'Baseline model'} · '
            'val loss ${model.valLoss.toStringAsFixed(3)} · '
            'acc ${(model.valAccuracy * 100).toStringAsFixed(0)}% · '
            'trained $trained'
            '${_computedAt != null ? ' · refreshed ${_agoLabel(DateTime.now().difference(_computedAt!))}' : ''}',
            style: TextStyle(fontSize: 10, color: t.muted),
          ),
        ),
      ],
    );
  }

  static String _agoLabel(Duration d) {
    if (d.inSeconds < 90) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 48) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }
}

class _LiveBadge extends StatefulWidget {
  final Color color;
  const _LiveBadge({required this.color});

  @override
  State<_LiveBadge> createState() => _LiveBadgeState();
}

class _LiveBadgeState extends State<_LiveBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1300))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.55, end: 1.0).animate(_c),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: widget.color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: widget.color.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration:
                  BoxDecoration(color: widget.color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Text(
              'LIVE',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: widget.color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MachineRiskRow extends StatelessWidget {
  final MachineForecast forecast;
  const _MachineRiskRow({required this.forecast});

  static const _typeLabels = {
    'qualite': 'Quality',
    'maintenance': 'Maintenance',
    'defaut_produit': 'Defect',
    'manque_ressource': 'Resource',
  };

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final any = forecast.anyProbability;
    final riskColor = any >= 0.66
        ? t.red
        : any >= 0.33
            ? t.orange
            : t.green;
    final typeColors = {
      'qualite': t.blue,
      'maintenance': t.orange,
      'defaut_produit': t.red,
      'manque_ressource': t.purple,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: t.scaffold,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.border),
      ),
      child: Row(
        children: [
          TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            tween: Tween(begin: 0, end: any),
            builder: (_, v, __) => SizedBox(
              width: 40,
              height: 40,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: v,
                    strokeWidth: 3.4,
                    backgroundColor: t.border,
                    color: riskColor,
                  ),
                  Text(
                    '${(v * 100).round()}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: riskColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${forecast.usine} · C${forecast.convoyeur} · P${forecast.poste}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: t.textDark,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    for (final e in forecast.typeProbabilities.entries)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 5),
                          child: Tooltip(
                            message:
                                '${_typeLabels[e.key] ?? e.key}: ${(e.value * 100).toStringAsFixed(1)}%',
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(99),
                              child: TweenAnimationBuilder<double>(
                                duration: const Duration(milliseconds: 700),
                                curve: Curves.easeOutCubic,
                                tween: Tween(begin: 0, end: e.value),
                                builder: (_, v, __) => LinearProgressIndicator(
                                  value: v,
                                  minHeight: 5,
                                  backgroundColor: t.border,
                                  color: typeColors[e.key] ?? t.blue,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: (typeColors[forecast.topType] ?? t.blue)
                  .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              _typeLabels[forecast.topType] ?? forecast.topType,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: typeColors[forecast.topType] ?? t.blue,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
