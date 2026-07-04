import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

class OfflineDatabaseService {
  static const int _cacheSizeBytes = 100 * 1024 * 1024;
  static bool _configured = false;

  // Per-user nodes (notifications, pm_actions, collaboration_alerts) are
  // privileged-read at the root since the rules hardening — they are synced
  // per-uid via [syncUserScopedPaths] once the user is known.
  static const List<String> _syncedPaths = [
    'alerts',
    'alertCounter',
    'assets',
    'assetCounter',
    'collaboration_requests',
    'escalation_settings',
    'factories',
    'help_requests',
    'hierarchy',
    'users',
    'ai_decisions',
    'ai_feedback',
    'ai_master',
    'ai_runtime',
  ];

  static const List<String> _userScopedPaths = [
    'notifications',
    'pm_actions',
    'collaboration_alerts',
  ];
  static String? _syncedUid;

  static Future<void> configure() async {
    if (_configured) return;
    _configured = true;

    final database = FirebaseDatabase.instance;

    if (!kIsWeb) {
      try {
        database.setPersistenceEnabled(true);
        database.setPersistenceCacheSizeBytes(_cacheSizeBytes);
      } catch (e) {
        debugPrint('Offline database persistence setup skipped: $e');
      }
    }

    for (final path in _syncedPaths) {
      unawaited(_keepSynced(database, path));
    }
  }

  /// Keeps the signed-in user's own notification/action/collaboration nodes
  /// synced. Root-level sync of these nodes is no longer permitted by the
  /// database rules, so they are cached per-uid after sign-in.
  static Future<void> syncUserScopedPaths(String uid) async {
    if (uid.isEmpty || _syncedUid == uid) return;
    final database = FirebaseDatabase.instance;
    final previous = _syncedUid;
    _syncedUid = uid;
    for (final path in _userScopedPaths) {
      if (previous != null) {
        unawaited(_setKeepSynced(database, '$path/$previous', false));
      }
      unawaited(_keepSynced(database, '$path/$uid'));
    }
  }

  static Future<void> _keepSynced(
    FirebaseDatabase database,
    String path,
  ) =>
      _setKeepSynced(database, path, true);

  static Future<void> _setKeepSynced(
    FirebaseDatabase database,
    String path,
    bool value,
  ) async {
    try {
      await database.ref(path).keepSynced(value);
    } catch (e) {
      debugPrint('Offline keepSynced failed for $path: $e');
    }
  }
}
