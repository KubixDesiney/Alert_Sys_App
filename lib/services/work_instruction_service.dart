import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:rxdart/rxdart.dart';

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
    String? assetId,
  }) async {
    final locationQuery =
        _db.ref('alerts').orderByChild('usine').equalTo(usine);
    final locationSnap = await locationQuery.get();
    final locationMatch = locationSnap.exists && locationSnap.value != null
        ? _firstActiveMatch(locationSnap, convoyeur: convoyeur, poste: poste)
        : null;

    final cleanAssetId = _cleanAssetId(assetId);
    if (cleanAssetId == null) return locationMatch;

    final assetSnap = await _db
        .ref('alerts')
        .orderByChild('assetId')
        .equalTo(cleanAssetId)
        .get();
    final assetMatch = _firstActiveFromSnapshot(assetSnap);
    return _newerActive(assetMatch, locationMatch);
  }

  /// Live stream of the **complete** alert history (every status) at the
  /// given location, sorted most-recent first.
  Stream<List<AlertModel>> historyAtLocation({
    required String usine,
    required int convoyeur,
    required int poste,
    String? assetId,
  }) {
    final locationStream = _historyAtLocationOnly(
      usine: usine,
      convoyeur: convoyeur,
      poste: poste,
    );
    final cleanAssetId = _cleanAssetId(assetId);
    if (cleanAssetId == null) return locationStream;

    return Rx.combineLatest2<List<AlertModel>, List<AlertModel>,
        List<AlertModel>>(
      _historyForAsset(cleanAssetId),
      locationStream,
      (assetHistory, legacyLocationHistory) {
        final byId = <String, AlertModel>{};
        for (final alert in legacyLocationHistory) {
          byId[alert.id] = alert;
        }
        for (final alert in assetHistory) {
          byId[alert.id] = alert;
        }
        final out = byId.values.toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
        return out;
      },
    );
  }

  Stream<List<AlertModel>> _historyAtLocationOnly({
    required String usine,
    required int convoyeur,
    required int poste,
  }) {
    final query = _db.ref('alerts').orderByChild('usine').equalTo(usine);
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

  Stream<List<AlertModel>> _historyForAsset(String assetId) {
    final query = _db.ref('alerts').orderByChild('assetId').equalTo(assetId);
    return query.onValue.map((event) {
      final out = _alertsFromSnapshot(event.snapshot);
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
    String? assetId,
  }) {
    final locationStream = _activeAtLocationOnly(
      usine: usine,
      convoyeur: convoyeur,
      poste: poste,
    );
    final cleanAssetId = _cleanAssetId(assetId);
    if (cleanAssetId == null) return locationStream;

    return Rx.combineLatest2<AlertModel?, AlertModel?, AlertModel?>(
      _activeForAsset(cleanAssetId),
      locationStream,
      _newerActive,
    );
  }

  Stream<AlertModel?> _activeAtLocationOnly({
    required String usine,
    required int convoyeur,
    required int poste,
  }) {
    final query = _db.ref('alerts').orderByChild('usine').equalTo(usine);
    return query.onValue.map(
      (event) => _firstActiveMatch(
        event.snapshot,
        convoyeur: convoyeur,
        poste: poste,
      ),
    );
  }

  Stream<AlertModel?> _activeForAsset(String assetId) {
    final query = _db.ref('alerts').orderByChild('assetId').equalTo(assetId);
    return query.onValue
        .map((event) => _firstActiveFromSnapshot(event.snapshot));
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

  AlertModel? _firstActiveFromSnapshot(DataSnapshot snap) {
    AlertModel? best;
    for (final alert in _alertsFromSnapshot(snap)) {
      if (alert.status == 'validee') continue;
      if (best == null || alert.timestamp.isAfter(best.timestamp)) {
        best = alert;
      }
    }
    return best;
  }

  List<AlertModel> _alertsFromSnapshot(DataSnapshot snap) {
    final raw = snap.value;
    if (raw is! Map) return <AlertModel>[];
    final out = <AlertModel>[];
    raw.forEach((key, value) {
      if (value is! Map) return;
      out.add(AlertModel.fromMap(
        key.toString(),
        Map<String, dynamic>.from(value),
      ));
    });
    return out;
  }

  AlertModel? _newerActive(AlertModel? first, AlertModel? second) {
    if (first == null) return second;
    if (second == null) return first;
    return first.timestamp.isAfter(second.timestamp) ? first : second;
  }

  String? _cleanAssetId(String? assetId) {
    final clean = assetId?.trim();
    if (clean == null || clean.isEmpty) return null;
    return clean;
  }

  // ---------------------------------------------------------------------------
  // Future upgrade: composite-key query (no in-memory filter).
  // Requires writing `locationKey: "${usine}|${convoyeur}|${poste}"` on every
  // alert and adding `"locationKey": ".indexOn"` under /alerts in the rules.
  // ---------------------------------------------------------------------------
  Stream<AlertModel?> activeAlertsByLocationKey(String locationKey) {
    final query =
        _db.ref('alerts').orderByChild('locationKey').equalTo(locationKey);
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
