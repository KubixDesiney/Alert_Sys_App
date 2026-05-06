import '../../models/alert_model.dart';
import '../../models/user_model.dart';
import '../ai_assignment_service.dart' show AICandidate;

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

/// Pure scoring engine: given an alert, the candidate supervisor's
/// availability snapshot, and the full alerts history, returns the
/// [AICandidate] (either eligible with a numeric score and reason
/// breakdown, or skipped with a human-readable reason).
///
/// Has no Firebase, no singletons, no time mutation — pass [now] explicitly
/// so tests can pin a deterministic clock.
class AIScoringEngine {
  const AIScoringEngine({
    this.cooldownDuration = const Duration(minutes: 5),
  });

  final Duration cooldownDuration;

  AICandidate evaluate({
    required AlertModel alert,
    required AIScoringInputs candidate,
    required List<AlertModel> allAlerts,
    required DateTime now,
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
    } else {
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

    return AICandidate(
      supervisor: sup,
      score: score.clamp(0, 1000),
      reasons: reasons,
      skipReason: null,
    );
  }
}
