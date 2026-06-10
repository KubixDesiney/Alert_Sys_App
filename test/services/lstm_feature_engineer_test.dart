import 'package:flutter_test/flutter_test.dart';
import 'package:alertsysapp/services/lstm/lstm_feature_engineer.dart';
import 'package:alertsysapp/services/lstm/lstm_types.dart';

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
  group('LstmFeatureEngineer.buildDailyRows', () {
    test('fills gap days and tracks days_since_failure', () {
      final rows = LstmFeatureEngineer.buildDailyRows([
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
      final rows = LstmFeatureEngineer.buildDailyRows([
        _alert('2026-01-01T08:00:00Z', 'qualite', conv: 1),
        _alert('2026-01-01T09:00:00Z', 'qualite', conv: 2),
      ]);
      expect(rows.map((r) => r.machineKey).toSet().length, 2);
    });

    test('dayofweek uses Monday=0 convention', () {
      // 2026-01-05 is a Monday.
      final rows = LstmFeatureEngineer.buildDailyRows([
        _alert('2026-01-05T08:00:00Z', 'qualite'),
      ]);
      expect(rows.single.features[7], 0);
    });
  });

  group('FeatureScaler', () {
    test('scales to 0..1 and survives constant columns', () {
      final rows = LstmFeatureEngineer.buildDailyRows([
        _alert('2026-01-01T06:00:00Z', 'qualite'),
        _alert('2026-01-03T18:00:00Z', 'qualite'),
      ]);
      final scaler = FeatureScaler.fit(rows);
      for (final row in rows) {
        final scaled = scaler.transform(row.features);
        for (final v in scaled) {
          expect(v, inInclusiveRange(0, 1));
        }
      }
    });
  });

  group('buildWindows', () {
    test('creates next-day multi-label targets', () {
      final records = <AlertRecord>[];
      // 10 consecutive days of qualite alerts on one machine.
      for (var d = 1; d <= 10; d++) {
        records.add(_alert('2026-01-${d.toString().padLeft(2, '0')}T08:00:00Z', 'qualite'));
      }
      final rows = LstmFeatureEngineer.buildDailyRows(records);
      final scaler = FeatureScaler.fit(rows);
      final samples = LstmFeatureEngineer.buildWindows(rows, scaler, 4);
      // 10 days → windows starting at day 1..6 (window of 4 + 1 target day).
      expect(samples.length, 6);
      for (final s in samples) {
        expect(s.window.length, 4);
        expect(s.target[0], 1); // qualite occurred next day
        expect(s.target[1], 0);
      }
    });

    test('skips machines with insufficient history', () {
      final rows = LstmFeatureEngineer.buildDailyRows([
        _alert('2026-01-01T08:00:00Z', 'qualite'),
        _alert('2026-01-02T08:00:00Z', 'qualite'),
      ]);
      final scaler = FeatureScaler.fit(rows);
      expect(LstmFeatureEngineer.buildWindows(rows, scaler, 14), isEmpty);
    });
  });

  group('buildInferenceWindows', () {
    test('pads quiet machines up to today with correct window length', () {
      final rows = LstmFeatureEngineer.buildDailyRows([
        _alert('2026-01-01T08:00:00Z', 'qualite'),
        _alert('2026-01-02T08:00:00Z', 'maintenance'),
      ]);
      final scaler = FeatureScaler.fit(rows);
      final windows = LstmFeatureEngineer.buildInferenceWindows(
        rows,
        scaler,
        14,
        today: DateTime.utc(2026, 1, 20),
      );
      expect(windows.length, 1);
      expect(windows.values.single.length, 14);
    });
  });
}
