import 'package:firebase_database/firebase_database.dart';

import 'hw_models.dart';

/// RTDB persistence for the Hardware Lab. Circuits, machine bindings and the
/// AI-model config live under `hardware_lab/*` (SuperAdmin-only per rules); the
/// live device telemetry written during the connectivity test lives under
/// `hardware_lab/telemetry/*` and is handled by the connectivity panel.
class HwLabStore {
  HwLabStore({FirebaseDatabase? db})
      : _db = db ?? FirebaseDatabase.instance;

  final FirebaseDatabase _db;

  DatabaseReference get _circuits => _db.ref('hardware_lab/circuits');
  DatabaseReference get _bindings => _db.ref('hardware_lab/bindings');

  // ── circuits ──
  Future<List<HwCircuit>> loadCircuits() async {
    try {
      final snap = await _circuits.get();
      final v = snap.value;
      if (v is Map) {
        final list = v.values
            .whereType<Map>()
            .map(HwCircuit.fromJson)
            .toList()
          ..sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
        return list;
      }
    } catch (_) {}
    return [];
  }

  Future<void> saveCircuit(HwCircuit c) async {
    c.updatedAtMs = DateTime.now().millisecondsSinceEpoch;
    try {
      await _circuits.child(c.id).set(c.toJson());
    } catch (_) {}
  }

  Future<void> deleteCircuit(String id) async {
    try {
      await _circuits.child(id).remove();
    } catch (_) {}
  }

  // ── bindings ──
  Future<List<HwDeviceBinding>> loadBindings() async {
    try {
      final snap = await _bindings.get();
      final v = snap.value;
      if (v is Map) {
        return v.values
            .whereType<Map>()
            .map(HwDeviceBinding.fromJson)
            .toList()
          ..sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
      }
    } catch (_) {}
    return [];
  }

  Future<void> saveBinding(HwDeviceBinding b) async {
    try {
      await _bindings.child(b.id).set(b.toJson());
    } catch (_) {}
  }

  Future<void> deleteBinding(String id) async {
    try {
      await _bindings.child(id).remove();
    } catch (_) {}
  }
}
