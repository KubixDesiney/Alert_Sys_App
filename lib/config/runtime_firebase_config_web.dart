// Web implementation: reads the `window.__SIAS_CONFIG__` blob the shared
// `sias-app` Cloudflare worker injects into index.html before Flutter boots.
// Matches the repo's modern `dart:js_interop` style (see
// lib/utils/google_maps_web_support_web.dart).
import 'dart:js_interop';

@JS('__SIAS_CONFIG__')
external JSAny? get _siasConfig;

/// Returns the decoded config object, or null when the global is absent
/// (e.g. a local `flutter run -d chrome` with no worker in front).
Map<Object?, Object?>? readRuntimeConfigRaw() {
  final cfg = _siasConfig;
  if (cfg == null) return null;
  // `dartify()` recursively turns the JS object graph into Dart Maps/Lists, so
  // the nested `firebase` / `workers` objects come back as Maps too.
  final decoded = cfg.dartify();
  return decoded is Map ? decoded : null;
}
