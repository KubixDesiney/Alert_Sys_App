import 'dart:convert';

import 'package:firebase_database/firebase_database.dart';
import 'package:http/http.dart' as http;

/// Non-secret infrastructure configuration for a company's dedicated instance,
/// set self-service by the IT team in the SuperAdmin → Infrastructure tab.
///
/// SECURITY: only non-secret config lives in RTDB (`infra_config`). Secrets
/// (service-account JSON, Cloudflare API token, SCIM token, worker shared
/// secret) are NEVER persisted here — they are sent write-only to the deploy
/// pipeline at deploy time and stored as CI secrets there.
class InfraConfig {
  // Database — the company's own Firebase project (deploy target).
  final String firebaseProjectId;
  final String firebaseDbUrl;
  final String firebaseApiKey; // web API key is not a secret
  // Cloudflare.
  final String cloudflareAccountId;
  final String workersSubdomain;
  final String r2Bucket;
  // Deploy pipeline.
  final String deployWebhookUrl;
  final String lastDeployAt;
  final String lastDeployStatus;

  const InfraConfig({
    this.firebaseProjectId = '',
    this.firebaseDbUrl = '',
    this.firebaseApiKey = '',
    this.cloudflareAccountId = '',
    this.workersSubdomain = '',
    this.r2Bucket = '',
    this.deployWebhookUrl = '',
    this.lastDeployAt = '',
    this.lastDeployStatus = '',
  });

  static const empty = InfraConfig();

  /// The five workers, named exactly like our provisioning setup, derived from
  /// the configured workers.dev subdomain.
  List<({String key, String name, String role, String url})> workers() {
    final sub = workersSubdomain.trim().isEmpty
        ? '<subdomain>'
        : workersSubdomain.trim();
    ({String key, String name, String role, String url}) w(
            String key, String name, String role) =>
        (key: key, name: name, role: role, url: 'https://$name.$sub.workers.dev');
    return [
      w('ai', 'alert-notifier', 'AI · security · escalation · predictions'),
      w('notify', 'alertsys', 'FCM push fan-out'),
      w('backup', 'alertsys-backup', 'Nightly RTDB → R2 backup'),
      w('monitor', 'alertsys-monitor', 'Deadman uptime + webhook alerts'),
      w('scim', 'alertsys-scim', 'SCIM 2.0 user provisioning'),
    ];
  }

  String get scimBaseUrl {
    final sub = workersSubdomain.trim();
    if (sub.isEmpty) return '';
    return 'https://alertsys-scim.$sub.workers.dev/scim/v2';
  }

  InfraConfig copyWith({
    String? firebaseProjectId,
    String? firebaseDbUrl,
    String? firebaseApiKey,
    String? cloudflareAccountId,
    String? workersSubdomain,
    String? r2Bucket,
    String? deployWebhookUrl,
  }) =>
      InfraConfig(
        firebaseProjectId: firebaseProjectId ?? this.firebaseProjectId,
        firebaseDbUrl: firebaseDbUrl ?? this.firebaseDbUrl,
        firebaseApiKey: firebaseApiKey ?? this.firebaseApiKey,
        cloudflareAccountId: cloudflareAccountId ?? this.cloudflareAccountId,
        workersSubdomain: workersSubdomain ?? this.workersSubdomain,
        r2Bucket: r2Bucket ?? this.r2Bucket,
        deployWebhookUrl: deployWebhookUrl ?? this.deployWebhookUrl,
        lastDeployAt: lastDeployAt,
        lastDeployStatus: lastDeployStatus,
      );

  factory InfraConfig.fromMap(Map<dynamic, dynamic>? m) {
    if (m == null) return empty;
    String s(String k) => m[k]?.toString() ?? '';
    return InfraConfig(
      firebaseProjectId: s('firebaseProjectId'),
      firebaseDbUrl: s('firebaseDbUrl'),
      firebaseApiKey: s('firebaseApiKey'),
      cloudflareAccountId: s('cloudflareAccountId'),
      workersSubdomain: s('workersSubdomain'),
      r2Bucket: s('r2Bucket'),
      deployWebhookUrl: s('deployWebhookUrl'),
      lastDeployAt: s('lastDeployAt'),
      lastDeployStatus: s('lastDeployStatus'),
    );
  }

  /// Non-secret fields only — safe to persist in RTDB.
  Map<String, dynamic> toMap() => {
        'firebaseProjectId': firebaseProjectId.trim(),
        'firebaseDbUrl': firebaseDbUrl.trim(),
        'firebaseApiKey': firebaseApiKey.trim(),
        'cloudflareAccountId': cloudflareAccountId.trim(),
        'workersSubdomain': workersSubdomain.trim(),
        'r2Bucket': r2Bucket.trim(),
        'deployWebhookUrl': deployWebhookUrl.trim(),
        'updatedAt': DateTime.now().toIso8601String(),
      };
}

class InfraConfigService {
  InfraConfigService({FirebaseDatabase? db})
      : _ref = (db ?? FirebaseDatabase.instance).ref('infra_config');

  final DatabaseReference _ref;

  Stream<InfraConfig> stream() => _ref.onValue
      .map((e) => InfraConfig.fromMap(e.snapshot.value as Map<dynamic, dynamic>?));

  Future<InfraConfig> fetch() async {
    final snap = await _ref.get();
    return InfraConfig.fromMap(snap.value as Map<dynamic, dynamic>?);
  }

  /// Persists ONLY non-secret config.
  Future<void> save(InfraConfig config) => _ref.update(config.toMap());

  /// Triggers the company's deploy pipeline. Secrets are sent in the POST body
  /// (write-only) and are NOT stored in RTDB — the receiving CI stores them as
  /// its own secrets. The app cannot run wrangler/firebase itself, so this hands
  /// off to a webhook (e.g. a GitHub Actions repository_dispatch endpoint).
  Future<({bool ok, String message})> deploy({
    required InfraConfig config,
    required Map<String, String> secrets,
    String? authToken,
  }) async {
    final url = config.deployWebhookUrl.trim();
    if (url.isEmpty) {
      return (ok: false, message: 'Set a deploy webhook URL first.');
    }
    final cleanSecrets = Map<String, String>.fromEntries(
        secrets.entries.where((e) => e.value.trim().isNotEmpty));
    try {
      final res = await http
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              if (authToken != null && authToken.trim().isNotEmpty)
                'Authorization': 'Bearer ${authToken.trim()}',
            },
            body: jsonEncode({
              'event': 'deploy_instance',
              'config': config.toMap(),
              'secrets': cleanSecrets,
            }),
          )
          .timeout(const Duration(seconds: 20));
      final ok = res.statusCode >= 200 && res.statusCode < 300;
      await _ref.update({
        'lastDeployAt': DateTime.now().toIso8601String(),
        'lastDeployStatus': ok ? 'triggered' : 'failed_${res.statusCode}',
      });
      return (
        ok: ok,
        message: ok
            ? 'Deploy pipeline triggered (HTTP ${res.statusCode}).'
            : 'Webhook returned HTTP ${res.statusCode}.'
      );
    } catch (e) {
      await _ref.update({
        'lastDeployAt': DateTime.now().toIso8601String(),
        'lastDeployStatus': 'error',
      }).catchError((_) {});
      return (ok: false, message: 'Deploy failed: $e');
    }
  }
}
