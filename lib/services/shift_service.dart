import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:http/http.dart' as http;

import '../models/shift_model.dart';
import '../models/user_model.dart';
import 'app_logger.dart';

const String _shiftWorkerBaseUrl =
    'https://alert-notifier.aziz-nagati01.workers.dev';

/// CRUD + helpers for the Shifts module. Persists into RTDB under `/shifts`
/// and triggers the Cloudflare worker `/shift-ai-action` endpoint when AI
/// behavior is requested.
class ShiftService {
  ShiftService({AppLogger? logger}) : _logger = logger ?? const AppLogger();

  final AppLogger _logger;
  final FirebaseDatabase _db = FirebaseDatabase.instance;

  DatabaseReference get _root => _db.ref('shifts');

  Stream<List<ShiftModel>> streamShifts() {
    return _root.onValue.map((event) {
      final raw = event.snapshot.value;
      if (raw == null) return <ShiftModel>[];
      final map = Map<String, dynamic>.from(raw as Map);
      final list = <ShiftModel>[];
      for (final entry in map.entries) {
        if (entry.value is Map) {
          list.add(
            ShiftModel.fromMap(
              entry.key,
              Map<String, dynamic>.from(entry.value as Map),
            ),
          );
        }
      }
      list.sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
      return list;
    });
  }

  Future<List<ShiftModel>> fetchShiftsOnce() async {
    final snap = await _root.get();
    final raw = snap.value;
    if (raw == null) return [];
    final map = Map<String, dynamic>.from(raw as Map);
    final list = <ShiftModel>[];
    for (final entry in map.entries) {
      if (entry.value is Map) {
        list.add(
          ShiftModel.fromMap(
            entry.key,
            Map<String, dynamic>.from(entry.value as Map),
          ),
        );
      }
    }
    list.sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
    return list;
  }

  Future<ShiftModel> createShift(ShiftModel s) async {
    final ref = _root.push();
    final shift = ShiftModel(
      id: ref.key!,
      name: s.name,
      startMinutes: s.startMinutes,
      endMinutes: s.endMinutes,
      supervisors: s.supervisors,
      maxSupervisors: s.maxSupervisors,
      aiCommander: s.aiCommander,
      aiModel: s.aiModel,
      aiConfidence: s.aiConfidence,
      randomize: s.randomize,
      createdAt: DateTime.now(),
      isSeeded: s.isSeeded,
    );
    await ref.set(shift.toMap());
    _triggerWorker(shift, action: 'created');
    return shift;
  }

  Future<void> updateShift(ShiftModel s) async {
    await _root.child(s.id).update(s.toMap());
    _triggerWorker(s, action: 'updated');
  }

  Future<void> deleteShift(String id) async {
    await _root.child(id).remove();
  }

  Future<void> setReadyState({
    required String shiftId,
    required String supervisorId,
    required bool ready,
  }) async {
    await _root
        .child('$shiftId/supervisors/$supervisorId/ready')
        .set(ready);
  }

  /// Pick up to [maxSupervisors] from [pool], preferring evenly across factories.
  static List<AssignedSupervisor> randomizePool(
    List<UserModel> pool,
    int maxSupervisors, {
    int? seed,
  }) {
    if (pool.isEmpty) return [];
    final rnd = seed == null ? Random() : Random(seed);
    final shuffled = List<UserModel>.from(pool)..shuffle(rnd);
    final byFactory = <String, List<UserModel>>{};
    for (final u in shuffled) {
      byFactory.putIfAbsent(u.usine, () => []).add(u);
    }
    final picked = <UserModel>[];
    while (picked.length < maxSupervisors && byFactory.values.any((l) => l.isNotEmpty)) {
      for (final entry in byFactory.entries) {
        if (picked.length >= maxSupervisors) break;
        if (entry.value.isNotEmpty) picked.add(entry.value.removeAt(0));
      }
    }
    return picked
        .map((u) => AssignedSupervisor(
              id: u.id,
              name: u.fullName,
              factory: u.usine,
            ))
        .toList();
  }

  /// Returns the shift currently active at [now], if any.
  static ShiftModel? activeShift(List<ShiftModel> shifts, DateTime now) {
    for (final s in shifts) {
      if (s.containsTime(now)) return s;
    }
    return null;
  }

  /// Manually request the worker to perform an AI shift action. The worker
  /// also polls cron, so this is best-effort — a failure is silently logged.
  Future<bool> triggerShiftAiAction(ShiftModel s, {String action = 'evaluate'}) {
    return _triggerWorker(s, action: action);
  }

  Future<bool> _triggerWorker(ShiftModel s, {required String action}) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_shiftWorkerBaseUrl/shift-ai-action'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'shiftId': s.id,
              'action': action,
              'aiCommander': s.aiCommander,
              'aiConfidence': s.aiConfidence,
              'aiModel': s.aiModel,
              'name': s.name,
            }),
          )
          .timeout(const Duration(seconds: 4));
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (e) {
      _logger.warning('shift worker trigger failed: $e');
      return false;
    }
  }

  /// Convenience: ask the worker to generate a handover summary for [shift].
  /// Used by the "Live" tab when a shift is about to end.
  Future<String?> requestHandoverSummary(ShiftModel shift) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_shiftWorkerBaseUrl/shift-ai-action'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'shiftId': shift.id,
              'action': 'handover',
              'name': shift.name,
            }),
          )
          .timeout(const Duration(seconds: 12));
      if (res.statusCode < 200 || res.statusCode >= 300) return null;
      final data = jsonDecode(res.body);
      if (data is Map && data['summary'] is String) {
        return data['summary'] as String;
      }
      return null;
    } catch (e) {
      _logger.warning('handover request failed: $e');
      return null;
    }
  }

  /// Marks the current user's `ready` flag inside the active shift.
  /// Returns the shift id mutated, or null if no active shift was found.
  Future<String?> markCurrentUserReady({
    required List<ShiftModel> shifts,
    required bool ready,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    final now = DateTime.now();
    final active = activeShift(shifts, now);
    if (active == null) return null;
    final inShift = active.supervisors.any((s) => s.id == uid);
    if (!inShift) return null;
    await setReadyState(
      shiftId: active.id,
      supervisorId: uid,
      ready: ready,
    );
    return active.id;
  }
}
