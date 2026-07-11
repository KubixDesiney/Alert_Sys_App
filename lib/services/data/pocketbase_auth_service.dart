import 'dart:convert';

import 'package:http/http.dart' as http;

import 'onprem_roles.dart';
import 'onprem_session.dart';

/// Thrown with a stable [code] so the UI can localize each failure mode.
class OnPremAuthException implements Exception {
  OnPremAuthException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'OnPremAuthException($code): $message';
}

/// Result of an MFA challenge request. The default deployment ships without a
/// second factor, but the interface is in place so a TOTP/WebAuthn provider
/// can be dropped in without touching the sign-in call sites.
class MfaChallenge {
  const MfaChallenge({required this.required, this.challengeId, this.method});

  final bool required;
  final String? challengeId;
  final String? method;

  static const none = MfaChallenge(required: false);
}

/// MFA seam. Implementations verify a second factor AFTER the password step
/// and BEFORE the session is activated.
abstract class MfaProvider {
  Future<MfaChallenge> begin(String userId);
  Future<bool> complete(String challengeId, String code);
}

/// Default: no second factor configured.
class NoopMfaProvider implements MfaProvider {
  const NoopMfaProvider();
  @override
  Future<MfaChallenge> begin(String userId) async => MfaChallenge.none;
  @override
  Future<bool> complete(String challengeId, String code) async => true;
}

/// Signed-in user info surfaced to the app.
class OnPremUser {
  const OnPremUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.policy,
    this.mustChangePassword = false,
  });

  final String id;
  final String name;
  final String email;
  final OnPremRole role;
  final OnPremRolePolicy policy;
  final bool mustChangePassword;
}

/// Authentication against a self-hosted PocketBase (`users` auth collection).
///
/// Guarantees enforced client-side (and mirrored server-side by the API rules
/// in `deploy/onprem/pocketbase/pb_schema.json`):
///  * disabled accounts cannot start a session;
///  * `vendor_support` accounts need an unexpired access window;
///  * sessions expire with the PocketBase JWT (`exp` claim) — [sessionValid]
///    goes false and callers must [refresh] or sign in again;
///  * vendor sign-ins are always audited.
///
/// No shared credentials: accounts are provisioned individually (PocketBase
/// enforces unique emails); this service never creates or accepts a
/// deployment-wide login.
class PocketBaseAuthService {
  PocketBaseAuthService({
    required String baseUrl,
    http.Client? client,
    MfaProvider mfa = const NoopMfaProvider(),
    OnPremSession? session,
    DateTime Function()? now,
  })  : _base = baseUrl.replaceAll(RegExp(r'/+$'), ''),
        _client = client ?? http.Client(),
        _mfa = mfa,
        _session = session ?? OnPremSession.instance,
        _now = now ?? DateTime.now;

  final String _base;
  final http.Client _client;
  final MfaProvider _mfa;
  final OnPremSession _session;
  final DateTime Function() _now;

  OnPremUser? _current;
  OnPremUser? get currentUser => _current;

  bool get sessionValid => _current != null && _session.isSignedIn;

  Uri _u(String path) => Uri.parse('$_base$path');

  Map<String, String> get _jsonHeaders => {
        'Content-Type': 'application/json',
        if ((_session.token ?? '').isNotEmpty)
          'Authorization': _session.token!,
      };

  // ── Sign in / out ─────────────────────────────────────────────────────────

  Future<OnPremUser> signIn(String email, String password,
      {String? mfaCode}) async {
    final res = await _client.post(
      _u('/api/collections/users/auth-with-password'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'identity': email, 'password': password}),
    );
    if (res.statusCode != 200) {
      throw OnPremAuthException('invalid_credentials',
          'Sign-in failed (${res.statusCode}).');
    }
    final body = Map<String, dynamic>.from(jsonDecode(res.body) as Map);
    final token = body['token']?.toString() ?? '';
    final record = Map<String, dynamic>.from((body['record'] as Map?) ?? {});
    return _activate(token, record, mfaCode: mfaCode);
  }

  Future<OnPremUser> _activate(String token, Map<String, dynamic> record,
      {String? mfaCode}) async {
    final id = record['id']?.toString() ?? '';
    final role = OnPremRole.parse(record['role']?.toString());
    if (id.isEmpty || role == null) {
      throw OnPremAuthException('unknown_role',
          'Account has no recognised SIAS role.');
    }
    if (record['disabled'] == true) {
      throw OnPremAuthException('account_disabled', 'Account is disabled.');
    }
    if (role == OnPremRole.vendorSupport) {
      final window = VendorAccessWindow(
        enabled: record['disabled'] != true,
        expiresAt: _parseDate(record['vendorAccessExpiresAt']),
      );
      if (!window.isActive(_now())) {
        throw OnPremAuthException('vendor_access_expired',
            'Vendor support access window is closed.');
      }
    }

    // MFA hook (after password, before the session goes live).
    final challenge = await _mfa.begin(id);
    if (challenge.required) {
      if (mfaCode == null ||
          !await _mfa.complete(challenge.challengeId ?? '', mfaCode)) {
        throw OnPremAuthException('mfa_required',
            'A valid second factor is required.');
      }
    }

    final name = _displayName(record);
    _session.update(
      userId: id,
      userName: name,
      role: role.wire,
      token: token,
      tokenExpiresAt: tokenExpiry(token),
    );
    _current = OnPremUser(
      id: id,
      name: name,
      email: record['email']?.toString() ?? '',
      role: role,
      policy: OnPremRolePolicy(role, factories: _factoriesOf(record)),
      mustChangePassword: record['mustChangePassword'] == true,
    );

    // Vendor sessions are always audited; regular sign-ins too (cheap, and the
    // collection is append-only).
    await _audit(
      role == OnPremRole.vendorSupport
          ? 'auth.vendor_sign_in'
          : 'auth.sign_in',
      detail: 'Sign-in (${role.wire})',
    );
    return _current!;
  }

  Future<void> signOut() async {
    if (_current != null) {
      await _audit('auth.sign_out', detail: 'Sign-out');
    }
    _current = null;
    _session.clear();
  }

  /// Refreshes the token (PocketBase `auth-refresh`) and re-checks the
  /// disabled/vendor gates so a mid-session disable takes effect.
  Future<OnPremUser> refresh() async {
    final res = await _client.post(
      _u('/api/collections/users/auth-refresh'),
      headers: _jsonHeaders,
    );
    if (res.statusCode != 200) {
      _current = null;
      _session.clear();
      throw OnPremAuthException('session_expired', 'Session expired.');
    }
    final body = Map<String, dynamic>.from(jsonDecode(res.body) as Map);
    return _activate(
      body['token']?.toString() ?? '',
      Map<String, dynamic>.from((body['record'] as Map?) ?? {}),
    );
  }

  // ── Account management ────────────────────────────────────────────────────

  /// Self-service password change. PocketBase requires the old password and
  /// invalidates the token afterwards, so the caller must sign in again.
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    final user = _current;
    if (user == null) {
      throw OnPremAuthException('not_signed_in', 'No active session.');
    }
    final res = await _client.patch(
      _u('/api/collections/users/records/${user.id}'),
      headers: _jsonHeaders,
      body: jsonEncode({
        'oldPassword': oldPassword,
        'password': newPassword,
        'passwordConfirm': newPassword,
        'mustChangePassword': false,
      }),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw OnPremAuthException(
          'password_change_failed', 'Password change failed (${res.statusCode}).');
    }
    await _audit('account.password_change', detail: 'Password changed');
    _current = null;
    _session.clear(); // token is invalid now — force re-auth
  }

  /// Company-owner action (server rules enforce it): disable/enable a user.
  Future<void> setAccountDisabled(String userId, bool disabled) async {
    _requireOwner();
    final res = await _client.patch(
      _u('/api/collections/users/records/$userId'),
      headers: _jsonHeaders,
      body: jsonEncode({'disabled': disabled}),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw OnPremAuthException(
          'account_update_failed', 'Account update failed (${res.statusCode}).');
    }
    await _audit(disabled ? 'account.disable' : 'account.enable',
        targetId: userId);
  }

  /// Opens a time-boxed vendor-support window on a (named, individual)
  /// vendor account. Audited; auto-expires server-side via the API rules.
  Future<void> grantVendorAccess(String userId, Duration window) async {
    _requireOwner();
    final until = _now().toUtc().add(window);
    final res = await _client.patch(
      _u('/api/collections/users/records/$userId'),
      headers: _jsonHeaders,
      body: jsonEncode({
        'disabled': false,
        'vendorAccessExpiresAt': until.toIso8601String(),
      }),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw OnPremAuthException(
          'vendor_grant_failed', 'Vendor grant failed (${res.statusCode}).');
    }
    await _audit('account.vendor_access_grant',
        targetId: userId, detail: 'Until ${until.toIso8601String()}');
  }

  Future<void> revokeVendorAccess(String userId) async {
    _requireOwner();
    final res = await _client.patch(
      _u('/api/collections/users/records/$userId'),
      headers: _jsonHeaders,
      body: jsonEncode({
        'disabled': true,
        'vendorAccessExpiresAt': '',
      }),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw OnPremAuthException(
          'vendor_revoke_failed', 'Vendor revoke failed (${res.statusCode}).');
    }
    await _audit('account.vendor_access_revoke', targetId: userId);
  }

  void _requireOwner() {
    if (_current?.role != OnPremRole.companyOwner) {
      throw OnPremAuthException(
          'forbidden', 'Only the company owner can manage accounts.');
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Decodes the JWT `exp` claim so the app can expire sessions locally even
  /// before PocketBase rejects the token.
  static DateTime? tokenExpiry(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      final payload = utf8.decode(
          base64Url.decode(base64Url.normalize(parts[1])));
      final claims = Map<String, dynamic>.from(jsonDecode(payload) as Map);
      final exp = claims['exp'];
      if (exp is num) {
        return DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000,
            isUtc: true);
      }
    } catch (_) {/* malformed token -> no local expiry */}
    return null;
  }

  static String _displayName(Map<String, dynamic> record) {
    final name = record['name']?.toString().trim() ?? '';
    if (name.isNotEmpty) return name;
    final first = record['firstName']?.toString().trim() ?? '';
    final last = record['lastName']?.toString().trim() ?? '';
    final joined = [first, last].where((s) => s.isNotEmpty).join(' ');
    if (joined.isNotEmpty) return joined;
    final email = record['email']?.toString() ?? '';
    return email.contains('@') ? email.split('@').first : 'User';
  }

  static List<String> _factoriesOf(Map<String, dynamic> record) {
    final raw = record['factories'];
    if (raw is List) return raw.map((e) => e.toString()).toList();
    final usine = record['usine']?.toString().trim() ?? '';
    return usine.isEmpty ? const [] : [usine];
  }

  static DateTime? _parseDate(Object? raw) {
    if (raw == null) return null;
    final s = raw.toString().trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s.replaceFirst(' ', 'T'));
  }

  Future<void> _audit(String action, {String? targetId, String? detail}) async {
    try {
      await _client.post(
        _u('/api/collections/audit_logs/records'),
        headers: _jsonHeaders,
        body: jsonEncode({
          'at': _now().toUtc().toIso8601String(),
          'action': action,
          'actorId': _session.userId ?? _current?.id ?? 'unauthenticated',
          'actorName': _session.userName ?? '',
          'targetType': 'account',
          if (targetId != null) 'targetId': targetId,
          if (detail != null) 'detail': detail,
        }),
      );
    } catch (_) {/* audit must never break auth flows */}
  }
}
