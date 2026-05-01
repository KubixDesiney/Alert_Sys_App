import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

class OfflineDatabaseService {
  static const int _cacheSizeBytes = 100 * 1024 * 1024;
  static bool _configured = false;

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
    'notifications',
    'pm_actions',
    'users',
    'work_instructions',
    'ai_decisions',
    'ai_feedback',
    'ai_master',
    'ai_runtime',
  ];

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

  static Future<void> _keepSynced(
      FirebaseDatabase database, String path) async {
    try {
      await database.ref(path).keepSynced(true);
    } catch (e) {
      debugPrint('Offline keepSynced failed for $path: $e');
    }
  }
}
