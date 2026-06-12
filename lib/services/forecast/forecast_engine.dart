import 'package:firebase_database/firebase_database.dart';

import 'forecast_feature_engineer.dart';
import 'forecast_model_store.dart';
import 'forecast_types.dart';

/// Runs on-device gradient-boosting inference over recent alert history.
///
/// This is what makes the Production Manager forecasts genuinely live: every
/// dashboard rebuilds the latest engineered feature row per machine from the
/// alert stream it already has and pushes it through the deployed trees
/// locally — no external inference service involved.
class ForecastEngine {
  /// Computes next-24h forecasts for every machine present in [records].
  static List<MachineForecast> computeForecasts(
    TrainedForecastModel model,
    List<AlertRecord> records, {
    DateTime? now,
  }) {
    if (records.isEmpty) return const [];
    final rows = ForecastFeatureEngineer.buildDailyRows(records);
    final features = ForecastFeatureEngineer.buildInferenceFeatures(
      rows,
      today: now,
    );

    final forecasts = <MachineForecast>[];
    features.forEach((machineKey, x) {
      final parts = machineKey.split('|');
      final probs = model.model.predict(x);
      forecasts.add(MachineForecast(
        usine: parts.isNotEmpty ? parts[0] : '',
        convoyeur: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
        poste: parts.length > 2 ? int.tryParse(parts[2]) ?? 0 : 0,
        typeProbabilities: {
          for (var k = 0; k < kForecastAlertTypes.length; k++)
            kForecastAlertTypes[k]:
                double.parse(probs[k].clamp(0, 1).toStringAsFixed(4)),
        },
      ));
    });
    forecasts.sort((a, b) => b.anyProbability.compareTo(a.anyProbability));
    return forecasts;
  }

  /// Converts raw RTDB alert maps into [AlertRecord]s.
  static List<AlertRecord> recordsFromAlertMaps(Iterable<Map> alertMaps) {
    final records = <AlertRecord>[];
    for (final raw in alertMaps) {
      final ts = DateTime.tryParse((raw['timestamp'] ?? '').toString());
      if (ts == null) continue;
      records.add(AlertRecord(
        timestamp: ts,
        type: (raw['type'] ?? 'unknown').toString(),
        usine: (raw['usine'] ?? '').toString(),
        convoyeur: (raw['convoyeur'] as num?)?.toInt() ?? 0,
        poste: (raw['poste'] as num?)?.toInt() ?? 0,
        isCritical: raw['isCritical'] == true,
      ));
    }
    return records;
  }

  /// Publishes a forecast snapshot to `ai_predictions/forecast` so the rest
  /// of the platform (workers, briefings) can consume the on-device output.
  static Future<void> publishSnapshot(
    List<MachineForecast> forecasts, {
    FirebaseDatabase? database,
    String source = 'on_device_gbdt',
  }) async {
    final db = database ?? FirebaseDatabase.instance;
    await db.ref('ai_predictions/forecast').set({
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
      'source': source,
      'machineCount': forecasts.length,
      'predictions': forecasts.take(50).map((f) => f.toMap()).toList(),
    });
  }
}
