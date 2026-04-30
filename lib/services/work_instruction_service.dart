import 'dart:async';

import 'package:firebase_database/firebase_database.dart';

import '../models/alert_model.dart';
import '../models/work_instruction.dart';

/// Loads work instructions and finds active alerts at a given factory location.
///
/// Realtime DB layout:
///   /work_instructions/{alertType}/steps/...
///   /alerts/{alertId} { type, usine, convoyeur, poste, status, ... }
///
/// RTDB note: only one `equalTo` filter per query is allowed. To match
/// (usine + convoyeur + poste) in a single indexed query you would normally
/// store a synthetic composite key, e.g. `locationKey = "Usine A|1|5"`, and
/// `orderByChild('locationKey').equalTo('Usine A|1|5')`. Until that key is
/// backfilled this service queries by `usine` (the most selective field
/// available without schema changes) and filters the rest in-memory. For a
/// production deployment, add `locationKey` on alert creation and switch the
/// query to it — see [activeAlertsByLocationKey] below as a drop-in upgrade.
class WorkInstructionService {
  WorkInstructionService({FirebaseDatabase? database})
      : _db = database ?? FirebaseDatabase.instance;

  final FirebaseDatabase _db;

  // ---------------------------------------------------------------------------
  // Instructions
  // ---------------------------------------------------------------------------

  /// Loads `/work_instructions/{alertType}` once.
  /// Returns `null` if no node exists for that type.
  Future<WorkInstructions?> fetchInstructions(String alertType) async {
    final snap = await _db.ref('work_instructions/$alertType').get();
    if (!snap.exists || snap.value == null) return null;
    final raw = snap.value;
    if (raw is! Map) return null;
    return WorkInstructions.fromMap(
      alertType,
      Map<String, dynamic>.from(raw),
    );
  }

  // ---------------------------------------------------------------------------
  // Active-alert lookup at a location
  // ---------------------------------------------------------------------------

  /// One-shot lookup. Returns the first non-validated alert at the location,
  /// or `null` if none exists.
  Future<AlertModel?> findActiveAlertAtLocation({
    required String usine,
    required int convoyeur,
    required int poste,
  }) async {
    final query = _db
        .ref('alerts')
        .orderByChild('usine')
        .equalTo(usine);
    final snap = await query.get();
    if (!snap.exists || snap.value == null) return null;
    return _firstActiveMatch(snap, convoyeur: convoyeur, poste: poste);
  }

  /// Live stream of the **complete** alert history (every status) at the
  /// given location, sorted most-recent first.
  Stream<List<AlertModel>> historyAtLocation({
    required String usine,
    required int convoyeur,
    required int poste,
  }) {
    final query = _db
        .ref('alerts')
        .orderByChild('usine')
        .equalTo(usine);
    return query.onValue.map((event) {
      final raw = event.snapshot.value;
      if (raw is! Map) return <AlertModel>[];
      final out = <AlertModel>[];
      raw.forEach((key, value) {
        if (value is! Map) return;
        final data = Map<String, dynamic>.from(value);
        final c = (data['convoyeur'] as num?)?.toInt();
        final p = (data['poste'] as num?)?.toInt();
        if (c != convoyeur || p != poste) return;
        out.add(AlertModel.fromMap(key.toString(), data));
      });
      out.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return out;
    });
  }

  /// Live stream of the active alert at the given location.
  /// Emits `null` when no active alert is present.
  Stream<AlertModel?> listenToActiveAlertAtLocation({
    required String usine,
    required int convoyeur,
    required int poste,
  }) {
    final query = _db
        .ref('alerts')
        .orderByChild('usine')
        .equalTo(usine);
    return query.onValue.map(
      (event) => _firstActiveMatch(
        event.snapshot,
        convoyeur: convoyeur,
        poste: poste,
      ),
    );
  }

  AlertModel? _firstActiveMatch(
    DataSnapshot snap, {
    required int convoyeur,
    required int poste,
  }) {
    final raw = snap.value;
    if (raw is! Map) return null;

    AlertModel? best;
    raw.forEach((key, value) {
      if (value is! Map) return;
      final data = Map<String, dynamic>.from(value);
      final status = (data['status'] ?? '').toString();
      if (status == 'validee') return;

      final c = (data['convoyeur'] as num?)?.toInt();
      final p = (data['poste'] as num?)?.toInt();
      if (c != convoyeur || p != poste) return;

      final alert = AlertModel.fromMap(key.toString(), data);
      // Prefer the most recent non-validated alert at the location.
      if (best == null || alert.timestamp.isAfter(best!.timestamp)) {
        best = alert;
      }
    });
    return best;
  }

  // ---------------------------------------------------------------------------
  // Future upgrade: composite-key query (no in-memory filter).
  // Requires writing `locationKey: "${usine}|${convoyeur}|${poste}"` on every
  // alert and adding `"locationKey": ".indexOn"` under /alerts in the rules.
  // ---------------------------------------------------------------------------
  Stream<AlertModel?> activeAlertsByLocationKey(String locationKey) {
    final query = _db
        .ref('alerts')
        .orderByChild('locationKey')
        .equalTo(locationKey);
    return query.onValue.map((event) {
      final raw = event.snapshot.value;
      if (raw is! Map) return null;
      AlertModel? best;
      raw.forEach((key, value) {
        if (value is! Map) return;
        final data = Map<String, dynamic>.from(value);
        if ((data['status'] ?? '') == 'validee') return;
        final alert = AlertModel.fromMap(key.toString(), data);
        if (best == null || alert.timestamp.isAfter(best!.timestamp)) {
          best = alert;
        }
      });
      return best;
    });
  }
}
