import 'package:alertsysapp/services/predictive_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MorningBriefing.fromMap', () {
    test('parses standard payload', () {
      final b = MorningBriefing.fromMap({
        'date': '2026-05-03',
        'summary': 'Steady night, 12 alerts resolved.',
        'generatedAt': DateTime.now().toIso8601String(),
        'model': 'claude-opus-4-7',
        'resolutionRate': 88,
        'stats': {'total': 12},
        'topType': {'type': 'qualite', 'count': 7},
        'topFactory': {'name': 'Usine A', 'count': 9},
      });
      expect(b.date, '2026-05-03');
      expect(b.resolutionRate, 88);
      expect(b.topType, 'qualite');
      expect(b.topTypeCount, 7);
      expect(b.topFactory, 'Usine A');
      expect(b.topFactoryCount, 9);
    });

    test('handles missing optional fields', () {
      final b = MorningBriefing.fromMap({});
      expect(b.date, '');
      expect(b.summary, '');
      expect(b.resolutionRate, 0);
      expect(b.stats, isEmpty);
      expect(b.topType, isNull);
    });

    test('isFresh true within 26 hours', () {
      final fresh = MorningBriefing.fromMap({
        'generatedAt':
            DateTime.now().subtract(const Duration(hours: 2)).toIso8601String(),
      });
      expect(fresh.isFresh, isTrue);
    });

    test('isFresh false beyond 26 hours', () {
      final stale = MorningBriefing.fromMap({
        'generatedAt': DateTime.now()
            .subtract(const Duration(hours: 48))
            .toIso8601String(),
      });
      expect(stale.isFresh, isFalse);
    });

    test('isFresh false when generatedAt missing or unparsable', () {
      expect(MorningBriefing.fromMap({}).isFresh, isFalse);
      expect(MorningBriefing.fromMap({'generatedAt': 'nope'}).isFresh, isFalse);
    });
  });

  group('PredictiveModel.fromMap', () {
    test('parses curves, predictions, and factory risk', () {
      final m = PredictiveModel.fromMap({
        'curves': {
          'qualite': {
            'buckets': [
              {
                'offsetHours': 0,
                'startHour': 6,
                'endHour': 7,
                'probability': 0.42,
                'expected': 0.5,
              }
            ],
            'total24h': 0.7,
            'hourlyRate': 0.05,
            'peakHour': 6,
            'peakProbability': 0.42,
            'avgProbability': 0.2,
            'sampleSize': 30,
          }
        },
        'predictions': [
          {
            'factoryId': 'usine_a',
            'usine': 'Usine A',
            'convoyeur': 1,
            'poste': 2,
            'type': 'qualite',
            'confidence': 87,
            'pastCount': 5,
            'criticalCount': 1,
            'lastTs': '2026-05-01T12:00:00.000Z',
            'etaHours': 6.0,
          }
        ],
        'factoryRisk': [
          {'id': 'usine_a', 'name': 'Usine A', 'score': 1.5, 'count': 7}
        ],
        'generatedAt': '2026-05-03T08:00:00.000Z',
      });

      expect(m.curves.containsKey('qualite'), isTrue);
      expect(m.curves['qualite']!.buckets.first.probability, 0.42);
      expect(m.predictions, hasLength(1));
      expect(m.predictions.first.confidence, 87);
      expect(m.factoryRisk, hasLength(1));
      expect(m.factoryRisk.first.id, 'usine_a');
      expect(m.generatedAt?.toUtc().year, 2026);
    });

    test('returns empty defaults for empty map', () {
      final m = PredictiveModel.fromMap({});
      expect(m.curves, isEmpty);
      expect(m.predictions, isEmpty);
      expect(m.factoryRisk, isEmpty);
      expect(m.generatedAt, isNull);
    });
  });

  group('AssigneeSuggestion.fromMap', () {
    test('parses best supervisor and runners', () {
      final s = AssigneeSuggestion.fromMap({
        'alertId': 'a1',
        'best': {
          'uid': 'u1',
          'name': 'Alice',
          'reasons': ['Same factory', '5 past resolutions'],
          'busy': false,
        },
        'confidencePct': 87,
        'candidateCount': 4,
        'runners': [
          {'uid': 'u2', 'name': 'Bob', 'score': 0.7, 'busy': true}
        ],
      });
      expect(s.alertId, 'a1');
      expect(s.bestUid, 'u1');
      expect(s.bestName, 'Alice');
      expect(s.reasons, hasLength(2));
      expect(s.confidencePct, 87);
      expect(s.candidateCount, 4);
      expect(s.busy, isFalse);
      expect(s.runners, hasLength(1));
      expect(s.runners.first.busy, isTrue);
    });

    test('handles missing best block', () {
      final s = AssigneeSuggestion.fromMap({'alertId': 'a1'});
      expect(s.bestUid, isNull);
      expect(s.bestName, isNull);
      expect(s.reasons, isEmpty);
    });
  });

  group('FactoryRisk and PredictedFailure', () {
    test('FactoryRisk.fromMap reads numeric fields', () {
      final f = FactoryRisk.fromMap({
        'id': 'a',
        'name': 'Usine A',
        'score': 1.25,
        'count': 4,
      });
      expect(f.score, closeTo(1.25, 0.001));
      expect(f.count, 4);
    });

    test('PredictedFailure.fromMap parses null lastTs as null', () {
      final p = PredictedFailure.fromMap({});
      expect(p.lastTs, isNull);
      expect(p.etaHours, isNull);
      expect(p.confidence, 0);
    });
  });
}
