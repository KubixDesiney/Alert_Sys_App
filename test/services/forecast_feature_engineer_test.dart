import 'package:flutter_test/flutter_test.dart';
import 'package:alertsysapp/services/forecast/forecast_feature_engineer.dart';
import 'package:alertsysapp/services/forecast/forecast_types.dart';

AlertRecord _alert(String iso, String type,
        {String usine = 'Plant A', int conv = 1, int poste = 2, bool crit = false}) =>
    AlertRecord(
      timestamp: DateTime.parse(iso),
      type: type,
      usine: usine,
      convoyeur: conv,
      poste: poste,
      isCritical: crit,
    );

void main() {
  group('ForecastFeatureEngineer.buildDailyRows', () {
    test('fills gap days and tracks days_since_failure', () {
      final rows = ForecastFeatureEngineer.buildDailyRows([
        _alert('2026-01-01T08:00:00Z', 'qualite'),
        _alert('2026-01-04T10:00:00Z', 'maintenance', crit: true),
      ]);
      expect(rows.length, 4); // Jan 1..4 continuous
      // Day 1: qualite occurred.
      expect(rows[0].features[0], 1);
      expect(rows[0].features[5], 0); // had failure that day
      // Day 2: no alert, 1 day since failure.
      expect(rows[1].features[0], 0);
      expect(rows[1].features[5], 1);
      // Day 3: 2 days since failure.
      expect(rows[2].features[5], 2);
      // Day 4: maintenance + critical.
      expect(rows[3].features[1], 1);
      expect(rows[3].features[4], 1);
      expect(rows[3].features[5], 0);
    });

    test('separates machines', () {
      final rows = ForecastFeatureEngineer.buildDailyRows([
        _alert('2026-01-01T08:00:00Z', 'qualite', conv: 1),
        _alert('2026-01-01T09:00:00Z', 'qualite', conv: 2),
      ]);
      expect(rows.map((r) => r.machineKey).toSet().length, 2);
    });

    test('dayofweek uses Monday=0 convention', () {
      // 2026-01-05 is a Monday.
      final rows = ForecastFeatureEngineer.buildDailyRows([
        _alert('2026-01-05T08:00:00Z', 'qualite'),
      ]);
      expect(rows.single.features[7], 0);
    });
  });

  group('buildSamples', () {
    test('creates next-day multi-label targets with rolling features', () {
      final records = <AlertRecord>[];
      // 12 consecutive days of qualite alerts on one machine.
      for (var d = 1; d <= 12; d++) {
        records.add(_alert(
            '2026-01-${d.toString().padLeft(2, '0')}T08:00:00Z', 'qualite'));
      }
      final rows = ForecastFeatureEngineer.buildDailyRows(records);
      final samples = ForecastFeatureEngineer.buildSamples(rows);
      // Days at index 7..10 can be sampled (index 11 has no next day).
      expect(samples.length, 4);
      for (final s in samples) {
        expect(s.features.length, kForecastFeatureCols.length);
        expect(s.target[0], 1); // qualite occurred next day
        expect(s.target[1], 0);
        // 7-day rolling qualite count is fully formed.
        expect(s.features[13], 7);
        // Recency: qualite occurred today.
        expect(s.features[20], 0);
        // Tomorrow's calendar context is populated.
        expect(s.features[8], inInclusiveRange(0, 6));
      }
    });

    test('skips machines with insufficient history', () {
      final rows = ForecastFeatureEngineer.buildDailyRows([
        _alert('2026-01-01T08:00:00Z', 'qualite'),
        _alert('2026-01-02T08:00:00Z', 'qualite'),
      ]);
      expect(ForecastFeatureEngineer.buildSamples(rows), isEmpty);
    });
  });

  group('featuresFor', () {
    test('computes lags, trend and per-type recency', () {
      final records = <AlertRecord>[
        // Burst week then quiet week.
        for (var d = 1; d <= 7; d++)
          _alert('2026-01-0${d}T08:00:00Z', 'qualite'),
        _alert('2026-01-14T08:00:00Z', 'maintenance'),
      ];
      final rows = ForecastFeatureEngineer.buildDailyRows(records)
        ..sort((a, b) => a.day.compareTo(b.day));
      final f = ForecastFeatureEngineer.featuresFor(rows, rows.length - 1);

      // Today (Jan 14): one maintenance alert.
      expect(f[10], 1); // total_today
      expect(f[11], 0); // total_yesterday
      // 7d window (Jan 8..14) holds only the maintenance alert.
      expect(f[17], 1);
      // 14d window holds the whole history.
      expect(f[18], 8);
      // Tempo collapsed: this week (1) minus last week (7).
      expect(f[19], -6);
      // Recency: maintenance today, qualite 7 days ago.
      expect(f[21], 0);
      expect(f[20], 7);
    });
  });

  group('buildInferenceFeatures', () {
    test('pads quiet machines up to today', () {
      final rows = ForecastFeatureEngineer.buildDailyRows([
        _alert('2026-01-01T08:00:00Z', 'qualite'),
        _alert('2026-01-02T08:00:00Z', 'maintenance'),
      ]);
      final features = ForecastFeatureEngineer.buildInferenceFeatures(
        rows,
        today: DateTime.utc(2026, 1, 20),
      );
      expect(features.length, 1);
      final f = features.values.single;
      expect(f.length, kForecastFeatureCols.length);
      // 18 quiet days since the last alert.
      expect(f[5], 18);
      // Nothing in the last 7/14 days.
      expect(f[17], 0);
      expect(f[18], 0);
      // Recency capped at 30 — both types beyond the 7/14d windows but seen.
      expect(f[20], 19);
      expect(f[21], 18);
    });

    test('uses today\'s row when the machine alerted today', () {
      final rows = ForecastFeatureEngineer.buildDailyRows([
        _alert('2026-01-19T08:00:00Z', 'qualite'),
        _alert('2026-01-20T09:00:00Z', 'qualite'),
      ]);
      final features = ForecastFeatureEngineer.buildInferenceFeatures(
        rows,
        today: DateTime.utc(2026, 1, 20),
      );
      final f = features.values.single;
      expect(f[0], 1); // qualite today
      expect(f[10], 1); // total today
      expect(f[11], 1); // total yesterday
      expect(f[20], 0); // qualite recency
    });
  });
}
