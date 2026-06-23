import 'package:firebase_database/firebase_database.dart';

import 'hw_models.dart';

/// RTDB persistence for the Hardware Lab's Factory Machinery Map. Device
/// bindings live under `hardware_lab/bindings` (SuperAdmin-only per rules).
class HwLabStore {
  HwLabStore({FirebaseDatabase? db})
      : _db = db ?? FirebaseDatabase.instance;

  final FirebaseDatabase _db;

  DatabaseReference get _bindings => _db.ref('hardware_lab/bindings');

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
