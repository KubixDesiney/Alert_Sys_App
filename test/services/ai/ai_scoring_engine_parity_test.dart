/// Scoring parity tests: every case is ported 1-to-1 from
/// worker_test/scoring.test.js with the exact same inputs and pinned expected
/// scores.  Any drift between the Dart engine and the Cloudflare Worker will
/// cause a failure here.
///
/// All tests call [AIScoringEngine.scoreWithStats] — the static JS-compatible
/// interface that accepts pre-computed stats (typeCounts, typeAvgRes,
/// stationCounts, conveyorCounts) and mirrors the Worker's scoreSupervisor
/// function signature exactly.
library;

import 'package:alertsysapp/services/ai/ai_scoring_engine.dart';
import 'package:flutter_test/flutter_test.dart';

// ─── helpers ────────────────────────────────────────────────────────────────

/// Convenience wrapper that mirrors the JS `score()` helper in scoring.test.js.
/// Default values replicate: sup.usine='Usine A', alert = baseAlert, no stats,
/// no feedback, 0 recent load, isCommander=false.
ScoringResult _score({
  String supUsine = 'Usine A',
  String alertUsine = 'Usine A',
  String alertType = 'qualite',
  int alertConvoyeur = 1,
  int alertPoste = 1,
  bool alertIsCritical = false,
  Map<String, int> typeCounts = const {},
  Map<String, double> typeAvgRes = const {},
  Map<String, int> stationCounts = const {},
  Map<String, int> conveyorCounts = const {},
  int recentAssignments = 0,
  int acceptedAssignments = 0,
  int resolvedOutcomes = 0,
  int rejectedAssignments = 0,
  double abortedAssignments = 0.0,
  bool isCommander = false,
}) =>
    AIScoringEngine.scoreWithStats(
      supUsine: supUsine,
      alertUsine: alertUsine,
      alertType: alertType,
      alertConvoyeur: alertConvoyeur,
      alertPoste: alertPoste,
      alertIsCritical: alertIsCritical,
      typeCounts: typeCounts,
      typeAvgRes: typeAvgRes,
      stationCounts: stationCounts,
      conveyorCounts: conveyorCounts,
      recentAssignments: recentAssignments,
      acceptedAssignments: acceptedAssignments,
      resolvedOutcomes: resolvedOutcomes,
      rejectedAssignments: rejectedAssignments,
      abortedAssignments: abortedAssignments,
      isCommander: isCommander,
    );

void main() {
  // ── factory bonus / penalty ────────────────────────────────────────────────

  group('factory bonus / penalty (parity)', () {
    test('same factory gives +30 with no other factors', () {
      final r = _score(supUsine: 'Usine A');
      expect(r.score, 30);
      expect(r.reasons.any((x) => x.contains('Same factory (+30)')), isTrue);
    });

    test('different factory clamps to 0 (no commander)', () {
      final r = _score(supUsine: 'Usine B');
      expect(r.score, 0);
      expect(r.reasons.any((x) => x.contains('Different factory')), isTrue);
    });

    test('different factory has NO penalty under commander', () {
      final r = _score(supUsine: 'Usine B', isCommander: true);
      // No factory penalty: score = 0 (no other factors), clamped to 0
      expect(r.score, 0);
      expect(r.reasons.any((x) => x.contains('Different factory')), isFalse);
    });

    test('same factory still gets +30 under commander', () {
      final r = _score(supUsine: 'Usine A', isCommander: true);
      expect(r.score, 30);
      expect(r.reasons.any((x) => x.contains('Same factory (+30)')), isTrue);
    });

    // CRITICAL: under commander, an experienced cross-factory supervisor
    // outscores an inexperienced same-factory supervisor.
    test('cross-factory + commander: experienced beats inexperienced same-factory', () {
      // cross: 0 + min(10*4,40)=40 → 40
      final experiencedCross = _score(
        supUsine: 'Usine B',
        typeCounts: {'qualite': 10},
        isCommander: true,
      );
      // same: 30 + 0 → 30
      final inexperiencedSame = _score(
        supUsine: 'Usine A',
        isCommander: true,
      );
      expect(experiencedCross.score, 40);
      expect(inexperiencedSame.score, 30);
      expect(experiencedCross.score, greaterThan(inexperiencedSame.score));
    });

    // Same scenario WITHOUT commander: -25 penalty makes same-factory win.
    test('cross-factory WITHOUT commander: penalty makes same-factory win', () {
      // cross: -25 + 40 = 15 → clamped to 15
      final experiencedCross = _score(
        supUsine: 'Usine B',
        typeCounts: {'qualite': 10},
      );
      // same: 30 + 0 = 30
      final inexperiencedSame = _score(supUsine: 'Usine A');
      expect(experiencedCross.score, 15);
      expect(inexperiencedSame.score, 30);
      expect(inexperiencedSame.score, greaterThan(experiencedCross.score));
    });
  });

  // ── type-experience bonus ─────────────────────────────────────────────────

  group('type experience bonus (parity)', () {
    test('0 past resolutions → no type bonus', () {
      final r = _score();
      // Only same-factory +30
      expect(r.score, 30);
    });

    test('3 past resolutions → +12 type bonus (3×4)', () {
      // 30 + 12 = 42
      final r = _score(typeCounts: {'qualite': 3});
      expect(r.score, 42);
      expect(r.reasons.any((x) => x.contains('past qualite')), isTrue);
    });

    test('type bonus caps at 40 (100+ resolutions)', () {
      // 30 + 40 (capped) = 70
      final r = _score(typeCounts: {'qualite': 100});
      expect(r.score, 70);
    });

    test('type mismatch: maintenance experience does not affect qualite score', () {
      final r = _score(typeCounts: {'maintenance': 10});
      // alert type = 'qualite', no qualite experience → only same-factory +30
      expect(r.score, 30);
    });
  });

  // ── resolution speed bonus ────────────────────────────────────────────────

  group('resolution speed bonus (parity)', () {
    test('avgRes 10 min → speed bonus 25 (capped)', () {
      // 30 + 4 + 25 = 59
      final r = _score(
        typeCounts: {'qualite': 1},
        typeAvgRes: {'qualite': 10.0},
      );
      expect(r.score, 59);
    });

    test('avgRes 45 min → speed bonus max(0,60-45)=15', () {
      // 30 + 4 + 15 = 49
      final r = _score(
        typeCounts: {'qualite': 1},
        typeAvgRes: {'qualite': 45.0},
      );
      expect(r.score, 49);
    });

    test('avgRes 65 min → speed bonus 0 (clamped to 0)', () {
      // 30 + 4 + 0 = 34
      final r = _score(
        typeCounts: {'qualite': 1},
        typeAvgRes: {'qualite': 65.0},
      );
      expect(r.score, 34);
    });

    test('no avgRes recorded → no speed bonus', () {
      // 30 + 12 = 42  (only type bonus, no speed)
      final r = _score(typeCounts: {'qualite': 3});
      expect(r.score, 42);
    });
  });

  // ── workstation / conveyor familiarity ────────────────────────────────────

  group('workstation and conveyor familiarity (parity)', () {
    test('1 station fix → +6', () {
      // 30 + 6 = 36
      final r = _score(stationCounts: {'Usine A|1|1': 1});
      expect(r.score, 36);
    });

    test('station bonus caps at 30 (10+ fixes)', () {
      // 30 + 30 (cap) = 60
      final r = _score(stationCounts: {'Usine A|1|1': 10});
      expect(r.score, 60);
    });

    test('3 conveyor fixes → score rounds 34.5 → 35', () {
      // 30 + min(3×1.5,15)=4.5 = 34.5 → Math.round = 35
      final r = _score(conveyorCounts: {'Usine A|1': 3});
      expect(r.score, 35);
    });

    test('station at different location does not contribute', () {
      // wrong key 'Usine A|2|9' vs alert key 'Usine A|1|1' → 30 only
      final r = _score(stationCounts: {'Usine A|2|9': 5});
      expect(r.score, 30);
    });
  });

  // ── load-balancing penalty ────────────────────────────────────────────────

  group('load balancing penalty (parity)', () {
    test('0 recent assignments → no penalty', () {
      final r = _score(recentAssignments: 0);
      expect(r.score, 30);
    });

    test('2 recent assignments → −16 penalty on non-critical', () {
      // 30 - 16 = 14
      final r = _score(alertIsCritical: false, recentAssignments: 2);
      expect(r.score, 14);
    });

    test('load penalty is NOT applied on critical alerts', () {
      final noLoad = _score(alertIsCritical: true, recentAssignments: 0).score;
      final withLoad = _score(alertIsCritical: true, recentAssignments: 2).score;
      expect(withLoad, noLoad);
    });
  });

  // ── feedback adjustment ───────────────────────────────────────────────────

  group('feedback adjustment (parity)', () {
    test('positive feedback adds up to +20 cap', () {
      // accepted×2 + resolved×3 = 200+300 = 500, clamped to +20 → 30+20 = 50
      final r = AIScoringEngine.scoreWithStats(
        supUsine: 'Usine A',
        alertUsine: 'Usine A',
        alertType: 'qualite',
        alertConvoyeur: 1,
        alertPoste: 1,
        acceptedAssignments: 100,
        resolvedOutcomes: 100,
      );
      expect(r.score, 50);
      expect(r.reasons.any((x) => x.contains('+20')), isTrue);
    });

    test('negative feedback reduces up to −20 cap', () {
      // rejected×2 + aborted×1.5 = 200+150 = 350, clamped to −20 → 30-20 = 10
      final r = AIScoringEngine.scoreWithStats(
        supUsine: 'Usine A',
        alertUsine: 'Usine A',
        alertType: 'qualite',
        alertConvoyeur: 1,
        alertPoste: 1,
        rejectedAssignments: 100,
        abortedAssignments: 100.0,
      );
      expect(r.score, 10);
    });

    test('no feedback record → zero adjustment', () {
      final r = _score();
      expect(r.score, 30);
      expect(r.reasons.any((x) => x.contains('Feedback')), isFalse);
    });
  });

  // ── score floor ───────────────────────────────────────────────────────────

  group('score floor (parity)', () {
    test('score is never negative even with heavy penalties', () {
      final r = AIScoringEngine.scoreWithStats(
        supUsine: 'Usine X',
        alertUsine: 'Usine A',
        alertType: 'qualite',
        alertConvoyeur: 1,
        alertPoste: 1,
        recentAssignments: 99,
        rejectedAssignments: 999,
        abortedAssignments: 999.0,
      );
      expect(r.score, greaterThanOrEqualTo(0));
    });
  });

  // ── full known I/O fixtures ───────────────────────────────────────────────

  group('full fixture: known input → known output (parity)', () {
    // Inputs:
    //   same factory (+30)
    //   typeCount=3 (+12), typeAvgRes=10 (+25)
    //   stationCount=2 (+12), conveyorCount=3 (+4.5)
    //   recentLoad=2, isCritical=false (−16)
    //   feedback: accepted=5, resolved=5, rejected=0, aborted=0
    //     → raw=25, capped→+20
    // Total = 30+12+25+12+4.5-16+20 = 87.5 → round = 88
    test('complete input set produces score 88', () {
      final r = AIScoringEngine.scoreWithStats(
        supUsine: 'Usine A',
        alertUsine: 'Usine A',
        alertType: 'qualite',
        alertConvoyeur: 1,
        alertPoste: 1,
        typeCounts: {'qualite': 3},
        typeAvgRes: {'qualite': 10.0},
        stationCounts: {'Usine A|1|1': 2},
        conveyorCounts: {'Usine A|1': 3},
        recentAssignments: 2,
        acceptedAssignments: 5,
        resolvedOutcomes: 5,
      );
      expect(r.score, 88);
    });

    // Same as above but commander + cross-factory: no penalty.
    // Total = 0+12+25+12+4.5-16+20 = 57.5 → round = 58
    test('commander mode cross-factory fixture produces score 58', () {
      final r = AIScoringEngine.scoreWithStats(
        supUsine: 'Usine B', // cross-factory
        alertUsine: 'Usine A',
        alertType: 'qualite',
        alertConvoyeur: 1,
        alertPoste: 1,
        typeCounts: {'qualite': 3},
        typeAvgRes: {'qualite': 10.0},
        stationCounts: {'Usine A|1|1': 2},
        conveyorCounts: {'Usine A|1': 3},
        recentAssignments: 2,
        acceptedAssignments: 5,
        resolvedOutcomes: 5,
        isCommander: true,
      );
      expect(r.score, 58);
    });
  });

  // ── buildSupStats-equivalent pipeline ────────────────────────────────────

  group('pre-computed stats pipeline (parity)', () {
    // Mirrors the JS buildSupStats integration test:
    //   a1: elapsedTime=10, a2: elapsedTime=30 → typeCount=2, avgRes=20
    //   both at conv=1, poste=1 → stationCount=2, conveyorCount=2
    // Score: 30 + min(2*4,40) + min(max(0,60-20),25) + min(2*6,30) + min(2*1.5,15)
    //       = 30 + 8 + 25 + 12 + 3 = 78
    test('stats built from two resolved alerts produce score 78', () {
      final r = AIScoringEngine.scoreWithStats(
        supUsine: 'Usine A',
        alertUsine: 'Usine A',
        alertType: 'qualite',
        alertConvoyeur: 1,
        alertPoste: 1,
        typeCounts: {'qualite': 2},
        typeAvgRes: {'qualite': 20.0},
        stationCounts: {'Usine A|1|1': 2},
        conveyorCounts: {'Usine A|1': 2},
      );
      expect(r.score, 78);
    });
  });

  // ── regression checksum ───────────────────────────────────────────────────
  //
  // Runs a matrix of 20 inputs and asserts the sum of all scores. Any future
  // change to the scoring formula that shifts any output will break this test,
  // making scoring regressions impossible to miss.

  group('scoring regression checksum', () {
    test('matrix of 20 inputs produces stable checksum', () {
      final inputs = [
        // (supUsine, typeCount, typeAvgRes, stationCount, conveyorCount, recent, isCommander) → expected score
        ('Usine A', 0, null, 0, 0, 0, false),   // 30
        ('Usine B', 0, null, 0, 0, 0, false),   // 0
        ('Usine A', 1, 10.0, 0, 0, 0, false),   // 59
        ('Usine A', 3, null, 0, 0, 0, false),   // 42
        ('Usine A', 100, null, 0, 0, 0, false), // 70
        ('Usine B', 10, null, 0, 0, 0, false),  // 15
        ('Usine B', 10, null, 0, 0, 0, true),   // 40
        ('Usine A', 0, null, 1, 0, 0, false),   // 36
        ('Usine A', 0, null, 10, 0, 0, false),  // 60
        ('Usine A', 0, null, 0, 3, 0, false),   // 35
        ('Usine A', 0, null, 0, 0, 2, false),   // 14
        ('Usine A', 1, 45.0, 0, 0, 0, false),   // 49
        ('Usine A', 1, 65.0, 0, 0, 0, false),   // 34
        ('Usine A', 3, 10.0, 2, 3, 2, false),   // 88
        ('Usine B', 3, 10.0, 2, 3, 2, true),    // 58
        ('Usine A', 2, 20.0, 2, 2, 0, false),   // 78
        ('Usine A', 5, 30.0, 5, 5, 1, false),   // 30+20+25+30+7.5-8=104.5→105
        ('Usine A', 10, 5.0, 3, 10, 0, false),  // 30+40+25+18+15=128
        ('Usine B', 0, null, 0, 0, 0, true),    // 0
        ('Usine A', 0, null, 0, 10, 0, false),  // 30+15=45
      ];

      final scores = inputs.map((t) {
        final (su, tc, ta, sc, cc, ra, cmd) = t;
        return AIScoringEngine.scoreWithStats(
          supUsine: su,
          alertUsine: 'Usine A',
          alertType: 'qualite',
          alertConvoyeur: 1,
          alertPoste: 1,
          typeCounts: tc > 0 ? {'qualite': tc} : {},
          typeAvgRes: ta != null ? {'qualite': ta} : {},
          stationCounts: sc > 0 ? {'Usine A|1|1': sc} : {},
          conveyorCounts: cc > 0 ? {'Usine A|1': cc} : {},
          recentAssignments: ra,
          isCommander: cmd,
        ).score;
      }).toList();

      // Pin the individual scores first so regressions are traceable.
      expect(scores[0], 30,  reason: 'same factory, no extras');
      expect(scores[1], 0,   reason: 'different factory, no commander');
      expect(scores[2], 59,  reason: 'avgRes 10');
      expect(scores[3], 42,  reason: '3 type resolutions');
      expect(scores[4], 70,  reason: 'type cap at 40');
      expect(scores[5], 15,  reason: 'cross-factory with experience');
      expect(scores[6], 40,  reason: 'cross-factory + commander');
      expect(scores[7], 36,  reason: '1 station fix');
      expect(scores[8], 60,  reason: 'station cap at 30');
      expect(scores[9], 35,  reason: '3 conveyor (rounds 34.5)');
      expect(scores[10], 14, reason: '2 recent load');
      expect(scores[11], 49, reason: 'avgRes 45');
      expect(scores[12], 34, reason: 'avgRes 65');
      // Rows 13/14 are the full combo WITHOUT feedback → different from the
      // standalone "score 88/58" tests which include acceptedAssignments=5.
      expect(scores[13], 68, reason: 'full combo without feedback (30+12+25+12+4.5-16 = 67.5 → 68)');
      expect(scores[14], 38, reason: 'commander cross-factory without feedback (37.5 → 38)');
      expect(scores[15], 78, reason: 'buildSupStats pipeline');
      expect(scores[19], 45, reason: '10 conveyor fixes (cap at 15)');

      // Stable checksum: sum of all 20 scores must equal this value.
      // Recalculate: 30+0+59+42+70+15+40+36+60+35+14+49+34+68+38+78+105+128+0+45 = 946
      final checksum = scores.fold<int>(0, (a, b) => a + b);
      expect(checksum, 946,
          reason: 'Checksum changed — scoring formula may have drifted');
    });
  });
}
