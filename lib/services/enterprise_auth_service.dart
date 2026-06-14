import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;

import '../config/company_config.dart';

/// Optional enterprise authentication: per-company **SSO** (OIDC / SAML via the
/// customer's identity provider) and **SMS MFA** (phone second factor).
///
/// This is ADDITIVE and self-contained — it never touches the email/password
/// flow in `AuthService`. Call these methods only when `CompanyConfig` enables
/// the feature, so existing logins are completely unaffected.
///
/// REQUIREMENTS / CAVEATS (read before enabling):
///  * Needs Google Cloud **Identity Platform** (the upgraded Firebase Auth) with
///    the company's SSO provider and MFA configured — see MFA_SSO.md.
///  * The `firebase_auth` MFA API surface varies by version; verify against the
///    pinned version and **test on every target platform** before turning it on.
///  * SSO users get NO role automatically — an admin must grant access, so
///    corporate SSO alone never authorizes anyone.
class EnterpriseAuthService {
  EnterpriseAuthService({FirebaseAuth? auth, DatabaseReference? database})
      : _auth = auth ?? FirebaseAuth.instance,
        _db = database ?? FirebaseDatabase.instance.ref();

  final FirebaseAuth _auth;
  final DatabaseReference _db;

  /// Returned by [signInWithSso] (or any login) when a second factor is needed.
  static const String mfaChallenge = '__mfa_required__';

  MultiFactorResolver? _pendingResolver;
  bool get hasPendingMfa => _pendingResolver != null;

  bool get ssoEnabled => CompanyConfig.ssoEnabled;

  // ── SSO ─────────────────────────────────────────────────────────────────

  /// Launches the company SSO sign-in. Returns:
  ///  * `null` on success,
  ///  * [mfaChallenge] if a second factor is required (then call [startSmsSignIn]
  ///    to text the code and [resolveSmsSignIn] to finish),
  ///  * otherwise a human-readable error string.
  Future<String?> signInWithSso({String? providerId, String? type}) async {
    // Prefer the runtime, IT-configured provider (SuperAdmin → Access & Identity);
    // fall back to the build-time CompanyConfig value.
    final pid = (providerId != null && providerId.trim().isNotEmpty)
        ? providerId.trim()
        : CompanyConfig.ssoProviderId;
    if (pid.isEmpty) {
      return 'SSO is not configured.';
    }
    final isSaml = type == 'saml' || pid.startsWith('saml.');
    try {
      final AuthProvider provider =
          isSaml ? SAMLAuthProvider(pid) : OAuthProvider(pid);
      final UserCredential cred = kIsWeb
          ? await _auth.signInWithPopup(provider)
          : await _auth.signInWithProvider(provider);
      final user = cred.user;
      if (user != null) await _ensureUserRecord(user);
      return null;
    } on FirebaseAuthMultiFactorException catch (e) {
      _pendingResolver = e.resolver;
      return mfaChallenge;
    } on FirebaseAuthException catch (e) {
      return e.message ?? e.code;
    } catch (e) {
      return e.toString();
    }
  }

  /// Ensures an SSO user has an app record. New SSO users are created WITHOUT a
  /// role on purpose — `RoleRouter` treats a missing role as an invalid account,
  /// so an admin must explicitly grant access first.
  Future<void> _ensureUserRecord(User user) async {
    try {
      final ref = _db.child('users/${user.uid}');
      final snap = await ref.get();
      if (snap.exists) {
        await ref.update({
          'status': 'active',
          'lastSeen': DateTime.now().toIso8601String(),
        });
      } else {
        final name = (user.displayName ?? '').trim();
        await ref.set({
          if (name.isNotEmpty) 'fullName': name,
          'status': 'active',
          'createdAt': DateTime.now().toIso8601String(),
          'createdBy': 'sso',
          'authProvider': CompanyConfig.ssoProviderId,
          // No 'role' — access must be granted by an admin.
        });
      }
      final email = (user.email ?? '').trim();
      if (email.isNotEmpty) {
        await _db.child('users_private/${user.uid}').update({'email': email});
      }
    } catch (e) {
      debugPrint('SSO user record ensure skipped: $e');
    }
  }

  // ── SMS MFA (phone second factor) ─────────────────────────────────────────

  /// Enrolment step 1: send an SMS code to [phoneNumber] (international format,
  /// e.g. `+21655123456`) for the signed-in user. Returns the verificationId to
  /// pass to [finishPhoneEnrollment], or an error.
  ///
  /// Android/iOS flow. On web, phone MFA additionally needs a reCAPTCHA verifier.
  Future<({String? verificationId, String? error})> startPhoneEnrollment(
    String phoneNumber,
  ) async {
    final user = _auth.currentUser;
    if (user == null) {
      return (verificationId: null, error: 'Not signed in.');
    }
    try {
      final session = await user.multiFactor.getSession();
      final completer = Completer<({String? verificationId, String? error})>();
      await _auth.verifyPhoneNumber(
        multiFactorSession: session,
        phoneNumber: phoneNumber,
        verificationCompleted: (_) {},
        verificationFailed: (e) {
          if (!completer.isCompleted) {
            completer.complete((verificationId: null, error: e.message ?? e.code));
          }
        },
        codeSent: (verificationId, _) {
          if (!completer.isCompleted) {
            completer.complete((verificationId: verificationId, error: null));
          }
        },
        codeAutoRetrievalTimeout: (_) {},
      );
      return completer.future;
    } catch (e) {
      return (verificationId: null, error: e.toString());
    }
  }

  /// Enrolment step 2: finalize with the SMS [code] from step 1.
  Future<String?> finishPhoneEnrollment(
    String verificationId,
    String code, {
    String label = 'Phone',
  }) async {
    final user = _auth.currentUser;
    if (user == null) return 'Not signed in.';
    try {
      final cred = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: code,
      );
      final assertion = PhoneMultiFactorGenerator.getAssertion(cred);
      await user.multiFactor.enroll(assertion, displayName: label);
      return null;
    } on FirebaseAuthException catch (e) {
      return e.message ?? e.code;
    }
  }

  /// Sign-in challenge step 1: send an SMS to the enrolled phone for the pending
  /// resolver. Returns the verificationId to pass to [resolveSmsSignIn].
  Future<({String? verificationId, String? error})> startSmsSignIn({
    MultiFactorResolver? resolver,
  }) async {
    final r = resolver ?? _pendingResolver;
    if (r == null) {
      return (verificationId: null, error: 'No MFA challenge is pending.');
    }
    try {
      final hint = r.hints.firstWhere(
        (h) => h is PhoneMultiFactorInfo,
        orElse: () => r.hints.first,
      );
      final completer = Completer<({String? verificationId, String? error})>();
      await _auth.verifyPhoneNumber(
        multiFactorSession: r.session,
        multiFactorInfo: hint as PhoneMultiFactorInfo,
        verificationCompleted: (_) {},
        verificationFailed: (e) {
          if (!completer.isCompleted) {
            completer.complete((verificationId: null, error: e.message ?? e.code));
          }
        },
        codeSent: (verificationId, _) {
          if (!completer.isCompleted) {
            completer.complete((verificationId: verificationId, error: null));
          }
        },
        codeAutoRetrievalTimeout: (_) {},
      );
      return completer.future;
    } catch (e) {
      return (verificationId: null, error: e.toString());
    }
  }

  /// Sign-in challenge step 2: complete the challenged sign-in with the SMS
  /// [code]. Call after [startSmsSignIn] returns a verificationId.
  Future<String?> resolveSmsSignIn(
    String verificationId,
    String code, {
    MultiFactorResolver? resolver,
  }) async {
    final r = resolver ?? _pendingResolver;
    if (r == null) return 'No MFA challenge is pending.';
    try {
      final cred = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: code,
      );
      final assertion = PhoneMultiFactorGenerator.getAssertion(cred);
      await r.resolveSignIn(assertion);
      _pendingResolver = null;
      return null;
    } on FirebaseAuthException catch (e) {
      return e.message ?? e.code;
    }
  }

  /// True if the signed-in user already has a second factor enrolled.
  Future<bool> hasEnrolledMfa() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    try {
      final factors = await user.multiFactor.getEnrolledFactors();
      return factors.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}
