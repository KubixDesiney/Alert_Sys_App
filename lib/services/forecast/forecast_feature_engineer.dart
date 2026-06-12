import 'dart:math' as math;
import 'dart:typed_data';

import 'forecast_types.dart';

/// One machine-day of base features.
class DailyRow {
  final String usine;
  final int convoyeur;
  final int poste;
  final DateTime day; // UTC midnight
  final Float64List features; // aligned with kDailyFeatureCols

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

  double get totalCount =>
      features[0] + features[1] + features[2] + features[3];
}

/// Turns raw [AlertRecord]s into the engineered tabular matrix the
/// gradient-boosted trees consume. Daily rows mirror the Cloudflare worker's
/// `_buildDailyFeatures` schema; the tabular layer adds lags, rolling counts
/// and recency features on top. Trees are scale-invariant, so no scaler is
/// fitted or persisted.
class ForecastFeatureEngineer {
  /// Days of prior history a machine-day needs before it can become a sample
  /// (keeps 7-day rollups fully formed).
  static const int kMinHistoryDays = 7;

  /// Cap for "days since last occurrence" recency features.
  static const double kRecencyCap = 30;

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

  /// Builds supervised samples: the engineered feature row of machine-day t,
  /// labelled with day t+1's per-type occurrence flags.
  static List<FeatureSample> buildSamples(List<DailyRow> rows) {
    final byMachine = _groupSorted(rows);

    final samples = <FeatureSample>[];
    for (final entry in byMachine.entries) {
      final machineRows = entry.value;
      for (var i = kMinHistoryDays;
          i + 1 < machineRows.length;
          i++) {
        final next = machineRows[i + 1];
        final target = Float64List(kForecastAlertTypes.length);
        for (var k = 0; k < kForecastAlertTypes.length; k++) {
          target[k] = next.typeOccurred(k);
        }
        samples.add(FeatureSample(
          features: featuresFor(machineRows, i),
          target: target,
          machineKey: entry.key,
        ));
      }
    }
    return samples;
  }

  /// Builds the most recent feature row per machine for live inference. Rows
  /// are extended with quiet days up to [today] so machines without recent
  /// alerts still forecast (predicting tomorrow from today's state).
  static Map<String, Float64List> buildInferenceFeatures(
    List<DailyRow> rows, {
    DateTime? today,
  }) {
    final now = today ?? DateTime.now().toUtc();
    final endDay = DateTime.utc(now.year, now.month, now.day);
    final byMachine = _groupSorted(rows);

    final out = <String, Float64List>{};
    for (final entry in byMachine.entries) {
      final machineRows = List<DailyRow>.of(entry.value);
      final last = machineRows.last;

      // Track days_since_failure continuity across padded quiet days.
      var lastFailureDay = last.day;
      for (var i = machineRows.length - 1; i >= 0; i--) {
        if (machineRows[i].totalCount > 0) {
          lastFailureDay = machineRows[i].day;
          break;
        }
      }

      var day = last.day.add(const Duration(days: 1));
      while (!day.isAfter(endDay)) {
        final f = Float64List(kDailyFeatureCols.length);
        f[5] = day.difference(lastFailureDay).inDays.toDouble();
        f[7] = ((day.weekday + 6) % 7).toDouble(); // Monday=0
        machineRows.add(DailyRow(
          usine: last.usine,
          convoyeur: last.convoyeur,
          poste: last.poste,
          day: day,
          features: f,
        ));
        day = day.add(const Duration(days: 1));
      }

      out[entry.key] = featuresFor(machineRows, machineRows.length - 1);
    }
    return out;
  }

  /// Engineered feature vector for [rows]`[i]` (rows must be one machine's
  /// gap-free, day-sorted history). Layout follows [kForecastFeatureCols].
  static Float64List featuresFor(List<DailyRow> rows, int i) {
    final today = rows[i];
    final tomorrow = today.day.add(const Duration(days: 1));
    final f = Float64List(kForecastFeatureCols.length);

    // 0..7: today's base machine-day snapshot.
    for (var c = 0; c < 8; c++) {
      f[c] = today.features[c];
    }

    // 8..9: tomorrow's calendar context (the day being predicted).
    final targetDow = ((tomorrow.weekday + 6) % 7).toDouble();
    f[8] = targetDow;
    f[9] = targetDow >= 5 ? 1 : 0;

    // 10..12: any-type total lags.
    f[10] = today.totalCount;
    f[11] = i >= 1 ? rows[i - 1].totalCount : 0;
    f[12] = i >= 2 ? rows[i - 2].totalCount : 0;

    // 13..16 per-type 7d, 17 total 7d, 18 total 14d, 24 critical 7d.
    var total7 = 0.0;
    var total14 = 0.0;
    var prev7 = 0.0;
    var critical7 = 0.0;
    for (var back = 0; back < 14; back++) {
      final j = i - back;
      if (j < 0) break;
      final r = rows[j];
      final t = r.totalCount;
      total14 += t;
      if (back < 7) {
        total7 += t;
        critical7 += r.features[4];
        for (var k = 0; k < 4; k++) {
          f[13 + k] += r.features[k];
        }
      } else {
        prev7 += t;
      }
    }
    f[17] = total7;
    f[18] = total14;
    f[19] = total7 - prev7;
    f[24] = critical7;

    // 20..23: per-type recency (days since last occurrence, capped).
    for (var k = 0; k < 4; k++) {
      var since = kRecencyCap;
      for (var back = 0; back <= math.min(i, kRecencyCap.toInt()); back++) {
        if (rows[i - back].features[k] > 0) {
          since = back.toDouble();
          break;
        }
      }
      f[20 + k] = since;
    }

    return f;
  }

  static Map<String, List<DailyRow>> _groupSorted(List<DailyRow> rows) {
    final byMachine = <String, List<DailyRow>>{};
    for (final row in rows) {
      byMachine.putIfAbsent(row.machineKey, () => []).add(row);
    }
    for (final list in byMachine.values) {
      list.sort((a, b) => a.day.compareTo(b.day));
    }
    return byMachine;
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
    final typeIndex = kForecastAlertTypes.indexOf(r.type);
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

      final f = Float64List(kDailyFeatureCols.length);
      for (var k = 0; k < kForecastAlertTypes.length; k++) {
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
  final List<int> typeCounts = List<int>.filled(kForecastAlertTypes.length, 0);
  int total = 0;
  int criticalCount = 0;
  int hourSum = 0;
  int hourSamples = 0;
}
