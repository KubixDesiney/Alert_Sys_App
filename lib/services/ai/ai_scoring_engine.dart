import '../../models/alert_model.dart';
import '../../models/user_model.dart';
import '../ai_assignment_service.dart' show AICandidate;
import 'score_adjuster.dart';

/// Inputs that come from outside the pure scoring math — supervisor
/// availability flags, cooldown state and feedback adjustments.
///
/// Decoupling these from [AIAssignmentService]'s internal Maps makes the
/// engine fully testable: callers feed the snapshot in, the engine returns a
/// score with no Firebase or singleton dependency.
class AIScoringInputs {
  final UserModel supervisor;
  final bool aiOptOut;

  /// Wall-clock instant the supervisor entered the post-rejection cooldown,
  /// or null if not currently in cooldown.
  final DateTime? cooldownStart;

  /// Score adjustment from past feedback (clamped ±20 by the caller).
  final double feedbackRankAdjustment;

  const AIScoringInputs({
    required this.supervisor,
    required this.aiOptOut,
    this.cooldownStart,
    this.feedbackRankAdjustment = 0,
  });
}

/// Return type of [AIScoringEngine.scoreWithStats] — mirrors the JS
/// `scoreSupervisor` return value exactly so parity tests can pin values.
class ScoringResult {
  /// Rounded integer score matching JS `Math.round()`, clamped 0–1000.
  final int score;
  final List<String> reasons;

  const ScoringResult({required this.score, required this.reasons});
}

/// Pure scoring engine: given an alert, the candidate supervisor's
/// availability snapshot, and the full alerts history, returns the
/// [AICandidate] (either eligible with a numeric score and reason
/// breakdown, or skipped with a human-readable reason).
///
/// Has no Firebase, no singletons, no time mutation — pass [now] explicitly
/// so tests can pin a deterministic clock.
///
/// An optional [ScoreAdjuster] applies a reinforcement-learning bias after the
/// raw score is computed. The bias is clamped to ±15% of the raw score so it
/// can never override the core ranking logic.
class AIScoringEngine {
  const AIScoringEngine({
    this.cooldownDuration = const Duration(minutes: 5),
    this.adjuster,
  });

  final Duration cooldownDuration;

  /// Optional RL-based bias layer. If null the engine behaves exactly as
  /// before — existing tests remain unaffected.
  final ScoreAdjuster? adjuster;

  AICandidate evaluate({
    required AlertModel alert,
    required AIScoringInputs candidate,
    required List<AlertModel> allAlerts,
    required DateTime now,
    bool isCommander = false,
  }) {
    final sup = candidate.supervisor;

    // ── Disqualifiers ───────────────────────────────────────────────────────
    if (candidate.aiOptOut) {
      return AICandidate(
        supervisor: sup,
        score: 0,
        reasons: const [],
        skipReason: 'Opted out of AI auto-assignment',
      );
    }
    if (sup.status != 'active') {
      return AICandidate(
        supervisor: sup,
        score: 0,
        reasons: const [],
        skipReason: 'Not currently active',
      );
    }
    final hasInProgress = allAlerts.any((a) =>
        a.status == 'en_cours' &&
        (a.superviseurId == sup.id || a.assistantId == sup.id));
    if (hasInProgress) {
      return AICandidate(
        supervisor: sup,
        score: 0,
        reasons: const [],
        skipReason: 'Already has an active alert',
      );
    }
    if (!alert.isCritical && candidate.cooldownStart != null) {
      final cd = candidate.cooldownStart!;
      if (now.difference(cd) < cooldownDuration) {
        final remaining = cooldownDuration - now.difference(cd);
        return AICandidate(
          supervisor: sup,
          score: 0,
          reasons: const [],
          skipReason:
              'In cooldown (${remaining.inMinutes}m ${remaining.inSeconds % 60}s remaining)',
        );
      }
    }

    // ── Scoring ─────────────────────────────────────────────────────────────
    double score = 0;
    final reasons = <String>[];

    if (sup.usine == alert.usine) {
      score += 30;
      reasons.add('Same factory (+30)');
    } else if (!isCommander) {
      // Under AI Shift Commander the cross-factory penalty is waived so that
      // experienced shift members from other factories can compete fairly.
      score -= 25;
      reasons.add('Different factory (−25)');
    }

    final typeResolved = allAlerts
        .where((a) =>
            a.type == alert.type &&
            a.status == 'validee' &&
            (a.superviseurId == sup.id || a.assistantId == sup.id))
        .length;
    if (typeResolved > 0) {
      final bonus = (typeResolved * 4).clamp(0, 40).toDouble();
      score += bonus;
      reasons.add(
          '$typeResolved past ${alert.type} alert${typeResolved > 1 ? 's' : ''} resolved (+${bonus.toStringAsFixed(0)})');
    } else {
      reasons.add('No prior ${alert.type} experience (0)');
    }

    final supTypeAlerts = allAlerts
        .where((a) =>
            a.type == alert.type &&
            a.status == 'validee' &&
            a.elapsedTime != null &&
            a.superviseurId == sup.id)
        .toList();
    if (supTypeAlerts.isNotEmpty) {
      final avg = supTypeAlerts.fold<int>(0, (s, a) => s + a.elapsedTime!) /
          supTypeAlerts.length;
      final speedBonus = (60 - avg).clamp(0, 25).toDouble();
      score += speedBonus;
      reasons.add(
          'Avg resolution ${avg.toStringAsFixed(0)}min for ${alert.type} (+${speedBonus.toStringAsFixed(0)})');
    }

    final stationResolved = allAlerts
        .where((a) =>
            a.usine == alert.usine &&
            a.convoyeur == alert.convoyeur &&
            a.poste == alert.poste &&
            a.status == 'validee' &&
            (a.superviseurId == sup.id || a.assistantId == sup.id))
        .length;
    if (stationResolved > 0) {
      final bonus = (stationResolved * 6).clamp(0, 30).toDouble();
      score += bonus;
      reasons.add(
          '$stationResolved fix${stationResolved > 1 ? 'es' : ''} at this workstation (+${bonus.toStringAsFixed(0)})');
    }

    final conveyorResolved = allAlerts
        .where((a) =>
            a.usine == alert.usine &&
            a.convoyeur == alert.convoyeur &&
            a.status == 'validee' &&
            (a.superviseurId == sup.id || a.assistantId == sup.id))
        .length;
    if (conveyorResolved > 0) {
      final bonus = (conveyorResolved * 1.5).clamp(0, 15).toDouble();
      score += bonus;
      reasons.add(
          '$conveyorResolved fix${conveyorResolved > 1 ? 'es' : ''} on Line ${alert.convoyeur} (+${bonus.toStringAsFixed(0)})');
    }

    final recentAssignments = allAlerts
        .where((a) =>
            a.superviseurId == sup.id &&
            a.takenAtTimestamp != null &&
            now.difference(a.takenAtTimestamp!) <
                const Duration(minutes: 10))
        .length;
    if (!alert.isCritical && recentAssignments > 0) {
      final penalty = (recentAssignments * 8).toDouble();
      score -= penalty;
      reasons.add(
          'Recent load: $recentAssignments assignment${recentAssignments > 1 ? 's' : ''} in 10min (−${penalty.toStringAsFixed(0)})');
    }

    if (alert.isCritical) {
      final criticalResolved = allAlerts
          .where((a) =>
              a.isCritical == true &&
              a.status == 'validee' &&
              a.superviseurId == sup.id)
          .length;
      if (criticalResolved > 0) {
        final bonus = (criticalResolved * 5).clamp(0, 20).toDouble();
        score += bonus;
        reasons.add(
            'Resolved $criticalResolved critical alert${criticalResolved > 1 ? 's' : ''} (+${bonus.toStringAsFixed(0)})');
      }
    }

    final fb = candidate.feedbackRankAdjustment;
    if (fb != 0) {
      score += fb;
      reasons.add(
          'Feedback adjustment (${fb >= 0 ? '+' : ''}${fb.toStringAsFixed(0)})');
    }

    // Apply RL-based adjuster: bias clamped to ±15% of the pre-adjustment
    // positive score. Neutral by default so all existing tests pass unchanged.
    if (adjuster != null) {
      final baseScore = score.clamp(0.0, 1000.0);
      final rawAdj = adjuster!.adjustmentFor(sup.id);
      final maxAdj = baseScore * 0.15;
      if (maxAdj > 0) {
        final clampedAdj = rawAdj.clamp(-maxAdj, maxAdj);
        if (clampedAdj.abs() >= 0.01) {
          score += clampedAdj;
          reasons.add(
              'AI learning bias (${clampedAdj >= 0 ? '+' : ''}${clampedAdj.toStringAsFixed(1)})');
        }
      }
    }

    // Round final score to match JS `Math.round()` semantics, then clamp.
    return AICandidate(
      supervisor: sup,
      score: score.round().clamp(0, 1000).toDouble(),
      reasons: reasons,
      skipReason: null,
    );
  }

  // ── JS-compatible static interface (parity surface) ──────────────────────
  //
  // Accepts the same pre-computed stats as the Cloudflare Worker's
  // `scoreSupervisor` function. Use this in parity tests so both sides
  // can be driven with identical inputs and expected to produce the exact
  // same integer score.
  static ScoringResult scoreWithStats({
    required String supUsine,
    required String alertUsine,
    required String alertType,
    required int alertConvoyeur,
    required int alertPoste,
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
  }) {
    double score = 0;
    final reasons = <String>[];

    // Factory bonus / penalty
    if (alertUsine == supUsine) {
      score += 30;
      reasons.add('Same factory (+30)');
    } else if (!isCommander) {
      score -= 25;
      reasons.add('Different factory (−25)');
    }

    // Type experience
    final typeCount = typeCounts[alertType] ?? 0;
    if (typeCount > 0) {
      final bonus = (typeCount * 4).clamp(0, 40).toDouble();
      score += bonus;
      reasons.add('$typeCount past $alertType resolved (+${bonus.toStringAsFixed(0)})');
    } else {
      reasons.add('No prior $alertType experience');
    }

    // Resolution speed
    final avgTime = typeAvgRes[alertType];
    if (avgTime != null) {
      final speedBonus = (60.0 - avgTime).clamp(0.0, 25.0);
      score += speedBonus;
      reasons.add(
          'Avg resolution ${avgTime.toStringAsFixed(0)}min (+${speedBonus.toStringAsFixed(0)})');
    }

    // Workstation familiarity
    final stationKey = '$alertUsine|$alertConvoyeur|$alertPoste';
    final stationCount = stationCounts[stationKey] ?? 0;
    if (stationCount > 0) {
      final bonus = (stationCount * 6).clamp(0, 30).toDouble();
      score += bonus;
      reasons.add('$stationCount fixes at workstation (+${bonus.toStringAsFixed(0)})');
    }

    // Conveyor-line familiarity
    final convKey = '$alertUsine|$alertConvoyeur';
    final convCount = conveyorCounts[convKey] ?? 0;
    if (convCount > 0) {
      final bonus = (convCount * 1.5).clamp(0.0, 15.0);
      score += bonus;
      reasons.add('$convCount fixes on line (+$bonus)');
    }

    // Load-balancing penalty (non-critical only)
    if (!alertIsCritical && recentAssignments > 0) {
      final penalty = (recentAssignments * 8).toDouble();
      score -= penalty;
      reasons.add('Recent load (−${penalty.toStringAsFixed(0)})');
    }

    // Feedback adjustment — mirrors JS formula exactly:
    //   accepted×2 + resolved×3 − rejected×2 − aborted×1.5, clamped ±20
    final rawFeedback = acceptedAssignments * 2.0 +
        resolvedOutcomes * 3.0 -
        rejectedAssignments * 2.0 -
        abortedAssignments * 1.5;
    final adjustment = rawFeedback.clamp(-20.0, 20.0);
    if (adjustment != 0) {
      score += adjustment;
      reasons.add(
          'Feedback adjustment (${adjustment >= 0 ? '+' : ''}${adjustment.toStringAsFixed(0)})');
    }

    // Round and clamp — matches JS `Math.max(0, Math.round(score))`.
    return ScoringResult(
      score: score.round().clamp(0, 1000),
      reasons: reasons,
    );
  }
}
