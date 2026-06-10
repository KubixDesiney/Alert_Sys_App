import 'dart:typed_data';

import 'lstm_types.dart';

/// One machine-day of engineered features.
class DailyRow {
  final String usine;
  final int convoyeur;
  final int poste;
  final DateTime day; // UTC midnight
  final Float64List features; // aligned with kLstmFeatureCols

  DailyRow({
    required this.usine,
    required this.convoyeur,
    required this.poste,
    required this.day,
    required this.features,
  });

  String get machineKey => '$usine|$convoyeur|$poste';

  /// 1.0 when this day had at least one alert of the given canonical type.
  double typeOccurred(int typeIndex) => features[typeIndex] > 0 ? 1.0 : 0.0;
}

/// Min/max scaler persisted next to the model so training-time and
/// inference-time inputs share the exact same normalization.
class FeatureScaler {
  final List<double> mins;
  final List<double> maxs;

  const FeatureScaler({required this.mins, required this.maxs});

  factory FeatureScaler.fit(List<DailyRow> rows) {
    final n = kLstmFeatureCols.length;
    final mins = List<double>.filled(n, double.infinity);
    final maxs = List<double>.filled(n, double.negativeInfinity);
    for (final row in rows) {
      for (var i = 0; i < n; i++) {
        final v = row.features[i];
        if (v < mins[i]) mins[i] = v;
        if (v > maxs[i]) maxs[i] = v;
      }
    }
    for (var i = 0; i < n; i++) {
      if (!mins[i].isFinite) mins[i] = 0;
      if (!maxs[i].isFinite) maxs[i] = 1;
    }
    return FeatureScaler(mins: mins, maxs: maxs);
  }

  Float64List transform(Float64List raw) {
    final out = Float64List(raw.length);
    for (var i = 0; i < raw.length; i++) {
      final range = maxs[i] - mins[i];
      out[i] = range == 0 ? 0 : (raw[i] - mins[i]) / range;
    }
    return out;
  }

  Map<String, dynamic> toJson() => {'mins': mins, 'maxs': maxs};

  factory FeatureScaler.fromJson(Map<String, dynamic> json) => FeatureScaler(
        mins: (json['mins'] as List).map((e) => (e as num).toDouble()).toList(),
        maxs: (json['maxs'] as List).map((e) => (e as num).toDouble()).toList(),
      );
}

/// Turns raw [AlertRecord]s into the per-machine daily feature matrix the
/// LSTM consumes. The schema mirrors the Cloudflare worker's
/// `_buildDailyFeatures` so app-trained models stay compatible with edge data.
class LstmFeatureEngineer {
  /// Builds gap-free daily rows for every machine between its first and last
  /// observed alert day.
  static List<DailyRow> buildDailyRows(List<AlertRecord> records) {
    if (records.isEmpty) return const [];

    final machines = <String, _MachineAcc>{};
    for (final r in records) {
      final acc = machines.putIfAbsent(
        r.machineKey,
        () => _MachineAcc(r.usine, r.convoyeur, r.poste),
      );
      acc.add(r);
    }

    final rows = <DailyRow>[];
    for (final acc in machines.values) {
      rows.addAll(acc.toRows());
    }
    return rows;
  }

  /// Builds supervised windows: [seqLen] consecutive scaled days as input,
  /// the following day's per-type occurrence flags as target.
  static List<TrainingSample> buildWindows(
    List<DailyRow> rows,
    FeatureScaler scaler,
    int seqLen,
  ) {
    final byMachine = <String, List<DailyRow>>{};
    for (final row in rows) {
      byMachine.putIfAbsent(row.machineKey, () => []).add(row);
    }

    final samples = <TrainingSample>[];
    for (final entry in byMachine.entries) {
      final machineRows = entry.value
        ..sort((a, b) => a.day.compareTo(b.day));
      if (machineRows.length <= seqLen) continue;
      for (var start = 0; start + seqLen < machineRows.length; start++) {
        final window = <Float64List>[];
        for (var t = 0; t < seqLen; t++) {
          window.add(scaler.transform(machineRows[start + t].features));
        }
        final next = machineRows[start + seqLen];
        final target = Float64List(kLstmAlertTypes.length);
        for (var k = 0; k < kLstmAlertTypes.length; k++) {
          target[k] = next.typeOccurred(k);
        }
        samples.add(TrainingSample(
          window: window,
          target: target,
          machineKey: entry.key,
        ));
      }
    }
    return samples;
  }

  /// Builds the most recent window per machine for live inference. Rows are
  /// extended with empty days up to [today] so quiet machines still forecast.
  static Map<String, List<Float64List>> buildInferenceWindows(
    List<DailyRow> rows,
    FeatureScaler scaler,
    int seqLen, {
    DateTime? today,
  }) {
    final now = today ?? DateTime.now().toUtc();
    final endDay = DateTime.utc(now.year, now.month, now.day);

    final byMachine = <String, List<DailyRow>>{};
    for (final row in rows) {
      byMachine.putIfAbsent(row.machineKey, () => []).add(row);
    }

    final out = <String, List<Float64List>>{};
    for (final entry in byMachine.entries) {
      final machineRows = entry.value
        ..sort((a, b) => a.day.compareTo(b.day));
      final last = machineRows.last;
      final byDay = {for (final r in machineRows) r.day: r};

      // Track days_since_failure continuity across padded quiet days.
      var lastFailureDay = machineRows.lastWhere(
        (r) => r.features[0] + r.features[1] + r.features[2] + r.features[3] >
            0,
        orElse: () => machineRows.last,
      ).day;

      final window = <Float64List>[];
      for (var offset = seqLen - 1; offset >= 0; offset--) {
        final day = endDay.subtract(Duration(days: offset));
        final existing = byDay[day];
        if (existing != null) {
          window.add(scaler.transform(existing.features));
          final hadAlert = existing.features[0] +
                  existing.features[1] +
                  existing.features[2] +
                  existing.features[3] >
              0;
          if (hadAlert) lastFailureDay = day;
          continue;
        }
        final raw = Float64List(kLstmFeatureCols.length);
        raw[5] = day.isAfter(lastFailureDay)
            ? day.difference(lastFailureDay).inDays.toDouble()
            : 0;
        raw[7] = ((day.weekday + 6) % 7).toDouble(); // Monday=0
        window.add(scaler.transform(raw));
      }
      out['${last.usine}|${last.convoyeur}|${last.poste}'] = window;
    }
    return out;
  }
}

class _MachineAcc {
  final String usine;
  final int convoyeur;
  final int poste;
  final Map<DateTime, _DayAcc> days = {};
  DateTime? minDay;
  DateTime? maxDay;

  _MachineAcc(this.usine, this.convoyeur, this.poste);

  void add(AlertRecord r) {
    final ts = r.timestamp.toUtc();
    final day = DateTime.utc(ts.year, ts.month, ts.day);
    if (minDay == null || day.isBefore(minDay!)) minDay = day;
    if (maxDay == null || day.isAfter(maxDay!)) maxDay = day;
    final acc = days.putIfAbsent(day, () => _DayAcc());
    final typeIndex = kLstmAlertTypes.indexOf(r.type);
    if (typeIndex >= 0) acc.typeCounts[typeIndex]++;
    acc.total++;
    if (r.isCritical) acc.criticalCount++;
    acc.hourSum += ts.hour;
    acc.hourSamples++;
  }

  List<DailyRow> toRows() {
    final rows = <DailyRow>[];
    if (minDay == null || maxDay == null) return rows;
    DateTime? lastFailureDay;
    var day = minDay!;
    while (!day.isAfter(maxDay!)) {
      final acc = days[day];
      final hadFailure = (acc?.total ?? 0) > 0;
      if (hadFailure) lastFailureDay = day;

      final f = Float64List(kLstmFeatureCols.length);
      for (var k = 0; k < kLstmAlertTypes.length; k++) {
        f[k] = (acc?.typeCounts[k] ?? 0).toDouble();
      }
      f[4] = (acc?.criticalCount ?? 0).toDouble();
      f[5] = hadFailure || lastFailureDay == null
          ? 0
          : day.difference(lastFailureDay).inDays.toDouble();
      f[6] = hadFailure && (acc?.hourSamples ?? 0) > 0
          ? acc!.hourSum / acc.hourSamples
          : 0;
      f[7] = ((day.weekday + 6) % 7).toDouble(); // Monday=0, Sunday=6

      rows.add(DailyRow(
        usine: usine,
        convoyeur: convoyeur,
        poste: poste,
        day: day,
        features: f,
      ));
      day = day.add(const Duration(days: 1));
    }
    return rows;
  }
}

class _DayAcc {
  final List<int> typeCounts = List<int>.filled(kLstmAlertTypes.length, 0);
  int total = 0;
  int criticalCount = 0;
  int hourSum = 0;
  int hourSamples = 0;
}
