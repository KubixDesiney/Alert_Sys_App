import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'runtime_firebase_config_stub.dart'
    if (dart.library.html) 'runtime_firebase_config_web.dart';

/// Parsed view of the `window.__SIAS_CONFIG__` blob injected by the shared
/// `sias-app` Cloudflare worker at request time (see `cloudflare_app_worker.js`
/// and CLAUDE.md → "Per-Tenant App Delivery").
///
/// On web, the worker resolves the tenant from the Host header and stamps that
/// tenant's PUBLIC Firebase config + worker URLs into index.html before Flutter
/// boots. This lets ONE web build serve every customer: the app reads its
/// Firebase project and worker endpoints at runtime instead of at build time.
/// On Android / desktop / local dev the global is absent, so [loadRuntimeSiasConfig]
/// returns null and the app falls back to `DefaultFirebaseOptions` + dart-defines.
class RuntimeSiasConfig {
  const RuntimeSiasConfig({
    this.tenant,
    this.tenantCode,
    this.company,
    this.firebaseOptions,
    this.aiWorkerBase,
    this.notifyWorkerBase,
    this.ingestWorkerBase,
    this.copilotUrl,
  });

  final String? tenant;
  final String? tenantCode;
  final String? company;
  final FirebaseOptions? firebaseOptions;
  final String? aiWorkerBase;
  final String? notifyWorkerBase;
  final String? ingestWorkerBase;
  final String? copilotUrl;

  bool get hasFirebase => firebaseOptions != null;
  bool get hasWorkerOverrides =>
      (aiWorkerBase != null && aiWorkerBase!.isNotEmpty) ||
      (notifyWorkerBase != null && notifyWorkerBase!.isNotEmpty) ||
      (ingestWorkerBase != null && ingestWorkerBase!.isNotEmpty) ||
      (copilotUrl != null && copilotUrl!.isNotEmpty);
}

RuntimeSiasConfig? _cached;
bool _loaded = false;

/// Reads and parses `window.__SIAS_CONFIG__` exactly once. Returns null when the
/// global is absent (native builds, local dev, provider-less widget tests).
RuntimeSiasConfig? loadRuntimeSiasConfig() {
  if (_loaded) return _cached;
  _loaded = true;
  try {
    final raw = readRuntimeConfigRaw();
    _cached = raw == null ? null : parseRuntimeSiasConfig(raw);
  } catch (_) {
    _cached = null;
  }
  return _cached;
}

@visibleForTesting
void debugResetRuntimeConfig() {
  _cached = null;
  _loaded = false;
}

/// Pure parser over the decoded JS object — tolerant of missing keys, and
/// unit-tested on the VM (see test/config/runtime_firebase_config_test.dart).
RuntimeSiasConfig? parseRuntimeSiasConfig(Map<Object?, Object?> raw) {
  String? str(Object? v) {
    if (v == null) return null;
    final s = v.toString();
    return s.isEmpty ? null : s;
  }

  final workers = raw['workers'];
  final workersMap = workers is Map ? workers : const {};
  final firebase = raw['firebase'];
  return RuntimeSiasConfig(
    tenant: str(raw['tenant']),
    tenantCode: str(raw['tenantCode']),
    company: str(raw['company']),
    firebaseOptions: firebaseOptionsFromMap(firebase is Map ? firebase : null),
    aiWorkerBase: str(workersMap['ai']),
    notifyWorkerBase: str(workersMap['notify']),
    ingestWorkerBase: str(workersMap['ingest']),
    copilotUrl: str(workersMap['copilotUrl']),
  );
}

/// Builds [FirebaseOptions] from the injected `firebase` map, or null when the
/// required identity fields (apiKey/appId/messagingSenderId/projectId) are
/// missing — in which case the caller keeps the compile-time default options.
FirebaseOptions? firebaseOptionsFromMap(Map? m) {
  if (m == null) return null;
  String? str(Object? v) {
    if (v == null) return null;
    final s = v.toString();
    return s.isEmpty ? null : s;
  }

  final apiKey = str(m['apiKey']);
  final appId = str(m['appId']);
  final sender = str(m['messagingSenderId']);
  final project = str(m['projectId']);
  if (apiKey == null || appId == null || sender == null || project == null) {
    return null;
  }
  return FirebaseOptions(
    apiKey: apiKey,
    appId: appId,
    messagingSenderId: sender,
    projectId: project,
    authDomain: str(m['authDomain']),
    storageBucket: str(m['storageBucket']),
    databaseURL: str(m['databaseURL']),
  );
}
