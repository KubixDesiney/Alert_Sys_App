import 'dart:math' as math;
import 'dart:typed_data';

import 'forecast_types.dart';

/// One machine-day of base features. [typeCount] records how many alert types
/// the daily vector encodes, so downstream code stays type-dynamic: the daily
/// vector is `[is_type0..is_type(N-1), critical, days_since, hour, dow]` with
/// width `N + 4`.
class DailyRow {
  final String usine;
  final int convoyeur;
  final int poste;
  final DateTime day; // UTC midnight
  final Float64List features; // aligned with dailyFeatureColsFor(types)
  final int typeCount;

  DailyRow({
    required this.usine,
    required this.convoyeur,
    required this.poste,
    required this.day,
    required this.features,
    this.typeCount = 4,
  });

  String get machineKey => '$usine|$convoyeur|$poste';

  /// 1.0 when this day had at least one alert of the given type index.
  double typeOccurred(int typeIndex) => features[typeIndex] > 0 ? 1.0 : 0.0;

  double get totalCount {
    var sum = 0.0;
    for (var k = 0; k < typeCount; k++) {
      sum += features[k];
    }
    return sum;
  }
}

/// Turns raw [AlertRecord]s into the engineered tabular matrix the
/// gradient-boosted trees consume, for an arbitrary ordered set of alert types
/// (defaulting to [kForecastAlertTypes]). Daily rows mirror the Cloudflare
/// worker's `_buildDailyFeatures` schema; the tabular layer adds lags, rolling
/// counts and recency features on top. Trees are scale-invariant, so no scaler
/// is fitted or persisted.
class ForecastFeatureEngineer {
  /// Days of prior history a machine-day needs before it can become a sample
  /// (keeps 7-day rollups fully formed).
  static const int kMinHistoryDays = 7;

  /// Cap for "days since last occurrence" recency features.
  static const double kRecencyCap = 30;

  /// Builds gap-free daily rows for every machine between its first and last
  /// observed alert day, encoding one `is_<type>` column per entry of [types].
  static List<DailyRow> buildDailyRows(
    List<AlertRecord> records, {
    List<String> types = kForecastAlertTypes,
  }) {
    if (records.isEmpty) return const [];

    final typeIndex = <String, int>{
      for (var i = 0; i < types.length; i++) types[i]: i,
    };
    final machines = <String, _MachineAcc>{};
    for (final r in records) {
      final acc = machines.putIfAbsent(
        r.machineKey,
        () => _MachineAcc(r.usine, r.convoyeur, r.poste, typeIndex, types.length),
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
  /// labelled with day t+1's per-type occurrence flags. The label/feature
  /// widths follow the [DailyRow.typeCount] of the input rows.
  static List<FeatureSample> buildSamples(List<DailyRow> rows) {
    final byMachine = _groupSorted(rows);

    final samples = <FeatureSample>[];
    for (final entry in byMachine.entries) {
      final machineRows = entry.value;
      final typeCount = machineRows.isEmpty ? 4 : machineRows.first.typeCount;
      for (var i = kMinHistoryDays; i + 1 < machineRows.length; i++) {
        final next = machineRows[i + 1];
        final target = Float64List(typeCount);
        for (var k = 0; k < typeCount; k++) {
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
      final typeCount = last.typeCount;
      final dailyWidth = typeCount + 4;

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
        final f = Float64List(dailyWidth);
        f[typeCount + 1] = day.difference(lastFailureDay).inDays.toDouble();
        f[typeCount + 3] = ((day.weekday + 6) % 7).toDouble(); // Monday=0
        machineRows.add(DailyRow(
          usine: last.usine,
          convoyeur: last.convoyeur,
          poste: last.poste,
          day: day,
          features: f,
          typeCount: typeCount,
        ));
        day = day.add(const Duration(days: 1));
      }

      out[entry.key] = featuresFor(machineRows, machineRows.length - 1);
    }
    return out;
  }

  /// Engineered feature vector for [rows]`[i]` (rows must be one machine's
  /// gap-free, day-sorted history). Layout follows `forecastFeatureColsFor` for
  /// the row's [DailyRow.typeCount] — the N=4 case is exactly the historical
  /// 25-column layout.
  static Float64List featuresFor(List<DailyRow> rows, int i) {
    final today = rows[i];
    final n = today.typeCount;
    final tomorrow = today.day.add(const Duration(days: 1));
    final f = Float64List(forecastFeatureCountFor(n));

    // 0..(N+3): today's base machine-day snapshot (per-type counts + shared).
    for (var c = 0; c < n + 4; c++) {
      f[c] = today.features[c];
    }

    // Tomorrow's calendar context (the day being predicted).
    final targetDow = ((tomorrow.weekday + 6) % 7).toDouble();
    f[n + 4] = targetDow;
    f[n + 5] = targetDow >= 5 ? 1 : 0;

    // Any-type total lags.
    f[n + 6] = today.totalCount;
    f[n + 7] = i >= 1 ? rows[i - 1].totalCount : 0;
    f[n + 8] = i >= 2 ? rows[i - 2].totalCount : 0;

    // Per-type 7d counts (offset N+9), total 7d/14d/trend, critical 7d.
    final per7Base = n + 9;
    final total7Idx = 2 * n + 9;
    final total14Idx = 2 * n + 10;
    final trendIdx = 2 * n + 11;
    final criticalIdx = 3 * n + 12;
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
        critical7 += r.features[n]; // critical_count column
        for (var k = 0; k < n; k++) {
          f[per7Base + k] += r.features[k];
        }
      } else {
        prev7 += t;
      }
    }
    f[total7Idx] = total7;
    f[total14Idx] = total14;
    f[trendIdx] = total7 - prev7;
    f[criticalIdx] = critical7;

    // Per-type recency (days since last occurrence, capped), offset 2N+12.
    final recencyBase = 2 * n + 12;
    for (var k = 0; k < n; k++) {
      var since = kRecencyCap;
      for (var back = 0; back <= math.min(i, kRecencyCap.toInt()); back++) {
        if (rows[i - back].features[k] > 0) {
          since = back.toDouble();
          break;
        }
      }
      f[recencyBase + k] = since;
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
  final Map<String, int> typeIndex;
  final int typeCount;
  final Map<DateTime, _DayAcc> days = {};
  DateTime? minDay;
  DateTime? maxDay;

  _MachineAcc(this.usine, this.convoyeur, this.poste, this.typeIndex,
      this.typeCount);

  void add(AlertRecord r) {
    final ts = r.timestamp.toUtc();
    final day = DateTime.utc(ts.year, ts.month, ts.day);
    if (minDay == null || day.isBefore(minDay!)) minDay = day;
    if (maxDay == null || day.isAfter(maxDay!)) maxDay = day;
    final acc = days.putIfAbsent(day, () => _DayAcc(typeCount));
    final idx = typeIndex[r.type] ?? -1;
    if (idx >= 0) acc.typeCounts[idx]++;
    acc.total++;
    if (r.isCritical) acc.criticalCount++;
    acc.hourSum += ts.hour;
    acc.hourSamples++;
  }

  List<DailyRow> toRows() {
    final rows = <DailyRow>[];
    if (minDay == null || maxDay == null) return rows;
    final dailyWidth = typeCount + 4;
    DateTime? lastFailureDay;
    var day = minDay!;
    while (!day.isAfter(maxDay!)) {
      final acc = days[day];
      final hadFailure = (acc?.total ?? 0) > 0;
      if (hadFailure) lastFailureDay = day;

      final f = Float64List(dailyWidth);
      for (var k = 0; k < typeCount; k++) {
        f[k] = (acc?.typeCounts[k] ?? 0).toDouble();
      }
      f[typeCount] = (acc?.criticalCount ?? 0).toDouble();
      f[typeCount + 1] = hadFailure || lastFailureDay == null
          ? 0
          : day.difference(lastFailureDay).inDays.toDouble();
      f[typeCount + 2] = hadFailure && (acc?.hourSamples ?? 0) > 0
          ? acc!.hourSum / acc.hourSamples
          : 0;
      f[typeCount + 3] = ((day.weekday + 6) % 7).toDouble(); // Mon=0, Sun=6

      rows.add(DailyRow(
        usine: usine,
        convoyeur: convoyeur,
        poste: poste,
        day: day,
        features: f,
        typeCount: typeCount,
      ));
      day = day.add(const Duration(days: 1));
    }
    return rows;
  }
}

class _DayAcc {
  final List<int> typeCounts;
  int total = 0;
  int criticalCount = 0;
  int hourSum = 0;
  int hourSamples = 0;

  _DayAcc(int typeCount) : typeCounts = List<int>.filled(typeCount, 0);
}
