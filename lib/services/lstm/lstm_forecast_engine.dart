import 'package:firebase_database/firebase_database.dart';

import 'lstm_feature_engineer.dart';
import 'lstm_model_store.dart';
import 'lstm_types.dart';

/// Runs on-device LSTM inference over recent alert history.
///
/// This is what makes the Production Manager forecasts genuinely live: every
/// dashboard rebuilds the latest 14-day window per machine from the alert
/// stream it already has and pushes it through the trained network locally —
/// no external inference service involved.
class LstmForecastEngine {
  /// Computes next-24h forecasts for every machine present in [records].
  static List<MachineForecast> computeForecasts(
    TrainedLstmModel model,
    List<AlertRecord> records, {
    DateTime? now,
  }) {
    if (records.isEmpty) return const [];
    final rows = LstmFeatureEngineer.buildDailyRows(records);
    final windows = LstmFeatureEngineer.buildInferenceWindows(
      rows,
      model.scaler,
      model.seqLen,
      today: now,
    );

    final forecasts = <MachineForecast>[];
    windows.forEach((machineKey, window) {
      final parts = machineKey.split('|');
      final probs = model.network.predict(window);
      forecasts.add(MachineForecast(
        usine: parts.isNotEmpty ? parts[0] : '',
        convoyeur: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
        poste: parts.length > 2 ? int.tryParse(parts[2]) ?? 0 : 0,
        typeProbabilities: {
          for (var k = 0; k < kLstmAlertTypes.length; k++)
            kLstmAlertTypes[k]: double.parse(
                probs[k].clamp(0, 1).toStringAsFixed(4)),
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

  /// Publishes a forecast snapshot to `ai_predictions/lstm` so the rest of
  /// the platform (workers, briefings) can consume the on-device output.
  static Future<void> publishSnapshot(
    List<MachineForecast> forecasts, {
    FirebaseDatabase? database,
    String source = 'on_device_lstm',
  }) async {
    final db = database ?? FirebaseDatabase.instance;
    await db.ref('ai_predictions/lstm').set({
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
      'source': source,
      'machineCount': forecasts.length,
      'predictions': forecasts.take(50).map((f) => f.toMap()).toList(),
    });
  }
}
