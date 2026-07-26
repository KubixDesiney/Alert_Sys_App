import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

import '../models/alert_type.dart';

/// App-global source of truth for the deployment's alert-type vocabulary.
///
/// Streams `app_config/alertTypes` (SuperAdmin-writable, plus entitled
/// Production Manager adaptive additions; `auth != null` readable) and exposes
/// the active ordered list plus lookup-by-code. Mirrors
/// the `context.tr` null-safe pattern: before the stream resolves — and in
/// provider-less widget tests that never call [start] — it synchronously
/// serves [kDefaultAlertTypeDefs], which equals the historical standard set.
/// So nothing ever crashes for lack of a live registry, and a fresh deployment
/// behaves exactly as before.
class AlertTypeRegistry extends ChangeNotifier {
  AlertTypeRegistry._();

  static final AlertTypeRegistry instance = AlertTypeRegistry._();

  static const String nodePath = 'app_config/alertTypes';

  List<AlertTypeDef> _types = List<AlertTypeDef>.of(kDefaultAlertTypeDefs);
  bool _loadedFromRemote = false;
  StreamSubscription<DatabaseEvent>? _sub;
  DatabaseReference? _ref;

  /// Active alert types, ordered by [AlertTypeDef.order] then label.
  List<AlertTypeDef> get types => List.unmodifiable(_types);

  /// Active type codes in order (the forecaster's schema / UI picker order).
  List<String> get codes => [for (final t in _types) t.code];

  /// True once a non-empty remote registry has been applied (so the UI can
  /// tell "seeded defaults" from "operator-configured").
  bool get loadedFromRemote => _loadedFromRemote;

  AlertTypeDef? byCode(String? code) {
    if (code == null) return null;
    final c = code.trim();
    for (final t in _types) {
      if (t.code == c) return t;
    }
    return null;
  }

  /// Begins streaming the registry. Safe to call more than once. Seeds the node
  /// with the defaults on first read if it is empty (best-effort — the write is
  /// SuperAdmin-gated, so it silently no-ops for other roles while the
  /// in-memory defaults keep serving).
  void start({FirebaseDatabase? database}) {
    if (_sub != null) return;
    try {
      _ref = (database ?? FirebaseDatabase.instance).ref(nodePath);
    } catch (_) {
      return; // Firebase unavailable (e.g. pure unit test) — defaults stand.
    }
    _sub = _ref!.onValue.listen(
      (event) {
        final parsed = _parse(event.snapshot.value);
        if (parsed.isEmpty) {
          // Empty node: keep defaults in memory and attempt a one-time seed.
          _types = List<AlertTypeDef>.of(kDefaultAlertTypeDefs);
          _loadedFromRemote = false;
          unawaited(_seedIfEmpty());
        } else {
          _types = parsed;
          _loadedFromRemote = true;
        }
        notifyListeners();
      },
      onError: (_) {
        // Rules hiccup / offline: defaults continue to serve.
      },
    );
  }

  static List<AlertTypeDef> _parse(Object? value) {
    if (value is! Map) return const [];
    final out = <AlertTypeDef>[];
    value.forEach((key, v) {
      final def = AlertTypeDef.fromMap(v, fallbackCode: key?.toString());
      if (def != null) out.add(def);
    });
    out.sort((a, b) {
      final byOrder = a.order.compareTo(b.order);
      return byOrder != 0 ? byOrder : a.label.compareTo(b.label);
    });
    return out;
  }

  bool _seeding = false;

  Future<void> _seedIfEmpty() async {
    if (_seeding || _ref == null) return;
    _seeding = true;
    try {
      await saveAll(kDefaultAlertTypeDefs);
    } catch (_) {
      // Non-SuperAdmin clients can't seed; that's fine.
    } finally {
      _seeding = false;
    }
  }

  /// Injects a type set directly (tests only), bypassing Firebase, so
  /// registry-driven code can be exercised with custom vocabularies.
  @visibleForTesting
  void debugSetTypes(List<AlertTypeDef> defs) {
    _types = List<AlertTypeDef>.of(defs);
    _loadedFromRemote = true;
    notifyListeners();
  }

  /// Restores the built-in defaults (tests only).
  @visibleForTesting
  void debugReset() {
    _types = List<AlertTypeDef>.of(kDefaultAlertTypeDefs);
    _loadedFromRemote = false;
    notifyListeners();
  }

  /// Overwrites the whole registry node (SuperAdmin only). Codes are the child
  /// keys so lookups are cheap and reorders are diff-friendly.
  Future<void> saveAll(List<AlertTypeDef> defs) async {
    final ref = _ref ?? FirebaseDatabase.instance.ref(nodePath);
    final payload = <String, dynamic>{for (final d in defs) d.code: d.toMap()};
    await ref.set(payload);
  }

  /// Adds inferred dataset types without rewriting existing operator choices.
  /// RTDB rules allow this to an `admin` only when the paid tenant entitlement
  /// `adaptiveAlertSchema` is true.
  Future<void> saveMissing(List<AlertTypeDef> defs) async {
    if (defs.isEmpty) return;
    final ref = _ref ?? FirebaseDatabase.instance.ref(nodePath);
    await ref.update({for (final def in defs) def.code: def.toMap()});
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
