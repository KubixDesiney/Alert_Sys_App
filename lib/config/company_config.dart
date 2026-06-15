import 'dart:ui' show Color;

/// Per-company identity for the **dedicated-instance** deployment model.
///
/// Each customer runs in its own Firebase project (wired via
/// `flutterfire configure`) and its own Cloudflare workers. Isolation therefore
/// comes from *separate deployments*, not a shared tenant layer — so there is no
/// cross-company data path to leak through.
///
/// This file is the single source of truth for the company-facing identity of a
/// build. Everything here is overridable at build time with `--dart-define`, so
/// one codebase produces every customer's app:
///
/// ```bash
/// flutter build apk \
///   --dart-define=COMPANY_ID=acme \
///   --dart-define=COMPANY_NAME="ACME Manufacturing" \
///   --dart-define=COMPANY_FIREBASE_PROJECT=acme-alerts \
///   --dart-define=ALERTSYS_AI_WORKER_URL=https://acme-ai.<acct>.workers.dev \
///   --dart-define=ALERTSYS_NOTIFY_WORKER_URL=https://acme-notify.<acct>.workers.dev
/// ```
class CompanyConfig {
  const CompanyConfig._();

  /// Stable machine id for the company (e.g. `acme`, `globex`). Appears in logs
  /// and support, and anchors the build-vs-project safety check below.
  static const String companyId =
      String.fromEnvironment('COMPANY_ID', defaultValue: 'demo');

  /// Display name shown in the app shell, reports, briefings, and notifications.
  static const String companyName =
      String.fromEnvironment('COMPANY_NAME', defaultValue: 'Smart Industrial Alert');

  /// Short product/app title for the title bar and launchers.
  static const String appTitle =
      String.fromEnvironment('COMPANY_APP_TITLE', defaultValue: 'Smart Industrial Alert');

  /// Primary brand color as a hex ARGB int literal, e.g. `0xFF1565C0`.
  static const String _brandHex =
      String.fromEnvironment('COMPANY_BRAND_COLOR', defaultValue: '0xFF1565C0');
  static int get brandColorValue => int.tryParse(_brandHex) ?? 0xFF1565C0;

  /// Primary brand color as a Flutter [Color], driving the app's primary/accent
  /// across the theme (buttons, nav, switches, login glyph).
  static Color get brandColor => Color(brandColorValue);

  /// Optional company logo shown on the login screen and shell. HTTPS URL to a
  /// raster image; empty = fall back to the default factory glyph (tinted with
  /// the brand color).
  static const String logoUrl =
      String.fromEnvironment('COMPANY_LOGO_URL', defaultValue: '');

  /// Support contact surfaced in error / empty states (optional).
  static const String supportEmail =
      String.fromEnvironment('COMPANY_SUPPORT_EMAIL', defaultValue: '');

  /// The Firebase project id this build is *expected* to be wired to. Set it to
  /// the SAME project `flutterfire configure` generated for this company.
  static const String expectedFirebaseProjectId =
      String.fromEnvironment('COMPANY_FIREBASE_PROJECT', defaultValue: '');

  // ── Enterprise SSO (the company's own identity provider) ──────────────────
  /// Identity-Platform provider id for the company's SSO. Examples:
  /// `oidc.acme-azure` (OIDC / Microsoft Entra), `saml.acme-okta` (SAML / Okta).
  /// Empty = SSO disabled, email/password only.
  static const String ssoProviderId =
      String.fromEnvironment('COMPANY_SSO_PROVIDER', defaultValue: '');

  /// Button label, e.g. "Sign in with ACME SSO".
  static const String ssoButtonLabel =
      String.fromEnvironment('COMPANY_SSO_LABEL', defaultValue: 'Sign in with SSO');

  static bool get ssoEnabled => ssoProviderId.isNotEmpty;

  // ── Multi-factor authentication ───────────────────────────────────────────
  /// When true, users without a second factor are nudged to enrol after login.
  /// (Hard enforcement is configured in the Identity Platform console; this only
  /// drives the in-app prompt.)
  static const bool mfaRequired =
      bool.fromEnvironment('COMPANY_MFA_REQUIRED', defaultValue: false);

  /// True once a real company override is in place (not the demo default).
  static bool get isConfigured => companyId != 'demo';

  /// Isolation safety check: confirms the build's company is pointed at the
  /// Firebase project we expect. Catches the dangerous misconfiguration of
  /// shipping Company A's app wired to Company B's data.
  ///
  /// Pass the runtime project id (from `DefaultFirebaseOptions.currentPlatform
  /// .projectId`). Returns null when OK, or a human-readable error when the
  /// build is mismatched. Callers should treat a non-null result as fatal in
  /// release builds.
  static String? verifyFirebaseProject(String actualProjectId) {
    if (expectedFirebaseProjectId.isEmpty) {
      return null; // No expectation declared (e.g. demo build) — skip.
    }
    if (expectedFirebaseProjectId == actualProjectId) {
      return null;
    }
    return 'Company isolation check FAILED: build "$companyId" expected Firebase '
        'project "$expectedFirebaseProjectId" but is wired to "$actualProjectId". '
        'Rebuild with the correct --dart-define / firebase_options for this company.';
  }
}
