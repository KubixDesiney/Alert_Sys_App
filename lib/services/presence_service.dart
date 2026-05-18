import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

import '../models/supervisor_presence.dart';
import 'app_logger.dart';

/// Reads and writes supervisor presence state for shifts.
///
/// Path layout in RTDB:
///   shift_presence/{shiftId}/{supervisorId} : SupervisorPresence
///
/// The worker is the primary writer of `status`, `lastActiveAt`,
/// `inactiveSince`, `confirmRequestedAt`, and `confirmExpiresAt`. The
/// supervisor's mobile client only writes `confirmedAt` (in response to the
/// "Confirm Presence" notification action).
class PresenceService {
  PresenceService({AppLogger? logger}) : _logger = logger ?? const AppLogger();

  final AppLogger _logger;
  final FirebaseDatabase _db = FirebaseDatabase.instance;

  DatabaseReference _shiftRef(String shiftId) =>
      _db.ref('shift_presence/$shiftId');

  /// Live stream of presence rows for a single shift, ordered by name.
  Stream<List<SupervisorPresence>> streamPresence(String shiftId) {
    return _shiftRef(shiftId).onValue.map((event) {
      final raw = event.snapshot.value;
      if (raw is! Map) return <SupervisorPresence>[];
      final out = <SupervisorPresence>[];
      for (final entry in raw.entries) {
        final v = entry.value;
        if (v is Map) {
          out.add(SupervisorPresence.fromMap(
            shiftId,
            entry.key.toString(),
            Map<String, dynamic>.from(v),
          ));
        }
      }
      out.sort((a, b) =>
          a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return out;
    });
  }

  /// One-shot read for export / report use.
  Future<List<SupervisorPresence>> fetchPresenceOnce(String shiftId) async {
    final snap = await _shiftRef(shiftId).get();
    final raw = snap.value;
    if (raw is! Map) return <SupervisorPresence>[];
    final out = <SupervisorPresence>[];
    for (final entry in raw.entries) {
      final v = entry.value;
      if (v is Map) {
        out.add(SupervisorPresence.fromMap(
          shiftId,
          entry.key.toString(),
          Map<String, dynamic>.from(v),
        ));
      }
    }
    out.sort((a, b) =>
        a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  /// Called when the supervisor taps the "Confirm Presence" action on the
  /// FCM notification (or the matching in-app button). Writes `confirmedAt`
  /// and flips `status` to `active`. The worker's next cron tick will keep it
  /// active for the inactivity window.
  Future<void> confirmPresence(String shiftId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final now = DateTime.now();
      await _shiftRef(shiftId).child(uid).update({
        'status': SupervisorPresence.statusToString(PresenceStatus.active),
        'confirmedAt': now.toIso8601String(),
        'lastActiveAt': now.toIso8601String(),
        'confirmRequestedAt': null,
        'confirmExpiresAt': null,
        'inactiveSince': null,
      });
    } catch (e) {
      _logger.warning('presence confirm failed: $e');
    }
  }
}
