import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

/// Aggregated feedback metrics for one supervisor. Mirrors the schema written
/// by [AIDecisionRepository.recordFeedbackEvent] under
/// `ai_feedback/summary/{supervisorId}`.
class FeedbackSummary {
  final int acceptedAssignments;
  final int rejectedAssignments;
  final int abortedAssignments;
  final int resolvedOutcomes;

  const FeedbackSummary({
    required this.acceptedAssignments,
    required this.rejectedAssignments,
    required this.abortedAssignments,
    required this.resolvedOutcomes,
  });

  factory FeedbackSummary.fromMap(Map<String, dynamic> map) {
    return FeedbackSummary(
      acceptedAssignments: (map['acceptedAssignments'] as num?)?.toInt() ?? 0,
      rejectedAssignments: (map['rejectedAssignments'] as num?)?.toInt() ?? 0,
      abortedAssignments: (map['abortedAssignments'] as num?)?.toInt() ?? 0,
      resolvedOutcomes: (map['resolvedOutcomes'] as num?)?.toInt() ?? 0,
    );
  }

  /// Score adjustment fed into [AIScoringEngine]. Clamped ±20.
  double get rankAdjustment {
    final value = (acceptedAssignments * 2.0) +
        (resolvedOutcomes * 3.0) -
        (rejectedAssignments * 2.0) -
        (abortedAssignments * 1.5);
    return value.clamp(-20.0, 20.0);
  }
}

/// Owns the Firebase persistence for the AI assignment subsystem's feedback
/// loop. Carved out of [AIAssignmentService] so:
///
/// * The service no longer talks to Firebase directly for feedback events.
/// * Tests can substitute a fake repository (the constructor accepts the
///   [FirebaseDatabase] instance instead of reaching for the singleton).
/// * Permission-denied gating lives in one place — once the rules deny a
///   write the repository flips [isAvailable] to false and short-circuits
///   subsequent calls.
class AIDecisionRepository {
  AIDecisionRepository({FirebaseDatabase? database})
      : _db = (database ?? FirebaseDatabase.instance).ref();

  final DatabaseReference _db;

  bool _available = true;
  bool get isAvailable => _available;

  /// Marks the repository unavailable; called by the host service when any
  /// upstream check determined the feedback paths are not writable.
  void markUnavailable() => _available = false;

  /// Append one feedback event to `ai_feedback/events` and bump the
  /// per-supervisor summary counters at `ai_feedback/summary/{supervisorId}`.
  /// No-op when [isAvailable] is false.
  Future<void> recordFeedbackEvent({
    required String eventType,
    required String alertId,
    String? supervisorId,
    String? supervisorName,
    Map<String, dynamic>? details,
    DateTime? at,
  }) async {
    if (!_available) return;
    final now = at ?? DateTime.now();
    final event = <String, dynamic>{
      'eventType': eventType,
      'alertId': alertId,
      'supervisorId': supervisorId,
      'supervisorName': supervisorName,
      'timestamp': now.toIso8601String(),
      'details': details ?? <String, dynamic>{},
    };
    try {
      await _db.child('ai_feedback/events').push().set(event);

      if (supervisorId != null && supervisorId.isNotEmpty) {
        final summaryRef = _db.child('ai_feedback/summary/$supervisorId');
        final summarySnap = await summaryRef.get();
        final summary = summarySnap.exists
            ? Map<String, dynamic>.from(summarySnap.value as Map)
            : <String, dynamic>{};

        int current(String k) => (summary[k] as num?)?.toInt() ?? 0;
        final updates = <String, dynamic>{
          'supervisorId': supervisorId,
          'supervisorName': supervisorName,
          'updatedAt': now.toIso8601String(),
        };
        switch (eventType) {
          case 'accepted_assignment':
            updates['acceptedAssignments'] = current('acceptedAssignments') + 1;
            break;
          case 'rejected_assignment':
            updates['rejectedAssignments'] = current('rejectedAssignments') + 1;
            break;
          case 'aborted_assignment':
            updates['abortedAssignments'] = current('abortedAssignments') + 1;
            break;
          case 'resolved_outcome':
            updates['resolvedOutcomes'] = current('resolvedOutcomes') + 1;
            break;
        }
        await summaryRef.update(updates);
      }
    } catch (e) {
      if (_isPermissionDenied(e)) {
        debugPrint('AI feedback write permission denied at ai_feedback/events');
        _available = false;
      }
    }
  }

  /// Pull the latest per-supervisor summary table. Returns an empty map and
  /// flips [isAvailable] off if the rules deny the read.
  Future<Map<String, FeedbackSummary>> loadFeedbackSummary() async {
    if (!_available) return const <String, FeedbackSummary>{};
    try {
      final snap = await _db.child('ai_feedback/summary').get();
      if (!snap.exists) return const <String, FeedbackSummary>{};
      final map = Map<String, dynamic>.from(snap.value as Map);
      return {
        for (final entry in map.entries)
          entry.key: FeedbackSummary.fromMap(
              Map<String, dynamic>.from(entry.value as Map)),
      };
    } catch (e) {
      if (_isPermissionDenied(e)) {
        debugPrint('AI feedback read permission denied at ai_feedback/summary');
        _available = false;
      }
      return const <String, FeedbackSummary>{};
    }
  }

  static bool _isPermissionDenied(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('permission_denied') ||
        text.contains('permission-denied') ||
        text.contains('permission denied');
  }
}
