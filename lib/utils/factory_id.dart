// lib/utils/factory_id.dart
//
// Single source of truth for factory-id canonicalization. The Cloudflare
// Worker uses the same algorithm — keep both in sync.

/// Lowercase, replace runs of non-alphanumeric chars with `_`, trim leading
/// and trailing underscores. Mirrors aiSanitizeFactoryId in cloudflare_worker.js.
String sanitizeFactoryId(String input) {
  return input
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
}
