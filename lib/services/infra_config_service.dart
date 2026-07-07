import 'package:firebase_database/firebase_database.dart';

/// Non-secret infrastructure configuration for a company's dedicated instance,
/// set self-service by the IT team in the SuperAdmin → Infrastructure tab.
///
/// SECURITY: only non-secret config lives in RTDB (`infra_config`). Secrets
/// (service-account JSON, SCIM token) are NEVER persisted here.
class InfraConfig {
  // Database — the company's own Firebase project (deploy target).
  final String firebaseProjectId;
  final String firebaseDbUrl;
  final String firebaseApiKey; // web API key is not a secret
  // The workers.dev subdomain the SCIM worker is deployed under.
  final String workersSubdomain;

  const InfraConfig({
    this.firebaseProjectId = '',
    this.firebaseDbUrl = '',
    this.firebaseApiKey = '',
    this.workersSubdomain = '',
  });

  static const empty = InfraConfig();

  String get scimBaseUrl {
    final sub = workersSubdomain.trim();
    if (sub.isEmpty) return '';
    return 'https://alertsys-scim.$sub.workers.dev/scim/v2';
  }

  InfraConfig copyWith({
    String? firebaseProjectId,
    String? firebaseDbUrl,
    String? firebaseApiKey,
    String? workersSubdomain,
  }) =>
      InfraConfig(
        firebaseProjectId: firebaseProjectId ?? this.firebaseProjectId,
        firebaseDbUrl: firebaseDbUrl ?? this.firebaseDbUrl,
        firebaseApiKey: firebaseApiKey ?? this.firebaseApiKey,
        workersSubdomain: workersSubdomain ?? this.workersSubdomain,
      );

  factory InfraConfig.fromMap(Map<dynamic, dynamic>? m) {
    if (m == null) return empty;
    String s(String k) => m[k]?.toString() ?? '';
    return InfraConfig(
      firebaseProjectId: s('firebaseProjectId'),
      firebaseDbUrl: s('firebaseDbUrl'),
      firebaseApiKey: s('firebaseApiKey'),
      workersSubdomain: s('workersSubdomain'),
    );
  }

  /// Non-secret fields only — safe to persist in RTDB.
  Map<String, dynamic> toMap() => {
        'firebaseProjectId': firebaseProjectId.trim(),
        'firebaseDbUrl': firebaseDbUrl.trim(),
        'firebaseApiKey': firebaseApiKey.trim(),
        'workersSubdomain': workersSubdomain.trim(),
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
}
