import 'package:firebase_database/firebase_database.dart';

/// Runtime Single Sign-On configuration.
///
/// Owned by the company's IT team through the SuperAdmin "Access & Identity"
/// tab and consumed by the login screen. Stored at `auth_config/sso`.
///
/// Intentionally NON-sensitive: it only holds what the app needs to render and
/// launch the SSO button (provider id, label, issuer for reference). The OAuth
/// client secret lives in Google Identity Platform and is never stored here.
class SsoConfig {
  final bool enabled;
  final String type; // 'oidc' | 'saml'
  final String providerId; // must match the Identity Platform provider, e.g. 'oidc.sias'
  final String label; // sign-in button text
  final String issuer; // reference/display only
  final String template; // 'entra' | 'google' | 'okta' | 'keycloak' | 'custom_oidc' | 'custom_saml'

  const SsoConfig({
    this.enabled = false,
    this.type = 'oidc',
    this.providerId = '',
    this.label = 'Sign in with SSO',
    this.issuer = '',
    this.template = 'custom_oidc',
  });

  /// Usable by the login screen only when switched on and pointed at a provider.
  bool get isUsable => enabled && providerId.trim().isNotEmpty;

  factory SsoConfig.fromMap(Map? m) {
    final map = m ?? const {};
    return SsoConfig(
      enabled: map['enabled'] == true,
      type: (map['type'] ?? 'oidc').toString(),
      providerId: (map['providerId'] ?? '').toString(),
      label: (map['label'] ?? 'Sign in with SSO').toString(),
      issuer: (map['issuer'] ?? '').toString(),
      template: (map['template'] ?? 'custom_oidc').toString(),
    );
  }

  Map<String, dynamic> toMap() => {
        'enabled': enabled,
        'type': type,
        'providerId': providerId.trim(),
        'label': label.trim(),
        'issuer': issuer.trim(),
        'template': template,
        'updatedAt': DateTime.now().toIso8601String(),
      };

  SsoConfig copyWith({
    bool? enabled,
    String? type,
    String? providerId,
    String? label,
    String? issuer,
    String? template,
  }) =>
      SsoConfig(
        enabled: enabled ?? this.enabled,
        type: type ?? this.type,
        providerId: providerId ?? this.providerId,
        label: label ?? this.label,
        issuer: issuer ?? this.issuer,
        template: template ?? this.template,
      );
}

class SsoConfigService {
  SsoConfigService({DatabaseReference? database})
      : _ref = (database ?? FirebaseDatabase.instance.ref())
            .child('auth_config/sso');

  final DatabaseReference _ref;

  /// One-shot read (used by the login screen at startup). Never throws —
  /// returns a disabled config if the node is missing or unreadable.
  Future<SsoConfig> load() async {
    try {
      final snap = await _ref.get();
      return SsoConfig.fromMap(snap.value is Map ? snap.value as Map : null);
    } catch (_) {
      return const SsoConfig();
    }
  }

  /// Live stream (used by the SuperAdmin tab to reflect saved state).
  Stream<SsoConfig> stream() => _ref.onValue.map(
        (e) => SsoConfig.fromMap(
          e.snapshot.value is Map ? e.snapshot.value as Map : null,
        ),
      );

  Future<void> save(SsoConfig config) => _ref.set(config.toMap());
}
