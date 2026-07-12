import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:alertsysapp/services/data/onprem_roles.dart';
import 'package:alertsysapp/services/data/onprem_session.dart';
import 'package:alertsysapp/services/data/pocketbase_auth_service.dart';

String _fakeJwt({int? expEpochSeconds}) {
  String b64(Map<String, dynamic> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  final payload = <String, dynamic>{
    'id': 'u1',
    if (expEpochSeconds != null) 'exp': expEpochSeconds,
  };
  return '${b64({'alg': 'none'})}.${b64(payload)}.sig';
}

void main() {
  final session = OnPremSession.instance;
  tearDown(session.clear);

  group('OnPremRolePolicy matrix', () {
    test('company owner manages branding/users/connectors but never secrets', () {
      const p = OnPremRolePolicy(OnPremRole.companyOwner);
      expect(p.canManageBranding, isTrue);
      expect(p.canManageUsers, isTrue);
      expect(p.canManageConnectors, isTrue);
      expect(p.canAccessDeploymentSecrets, isFalse);
      expect(p.canAccessFactory('Anything'), isTrue);
    });

    test('production manager runs operations but no deployment surface', () {
      const p = OnPremRolePolicy(OnPremRole.productionManager);
      expect(p.canManageFactoryOperations, isTrue);
      expect(p.canManageEscalationPolicy, isTrue);
      expect(p.canManageBranding, isFalse);
      expect(p.canManageUsers, isFalse);
      expect(p.canManageConnectors, isFalse);
      expect(p.canAccessDeploymentSecrets, isFalse);
    });

    test('supervisor is scoped to assigned factories and fails closed', () {
      const p =
          OnPremRolePolicy(OnPremRole.supervisor, factories: ['Usine A']);
      expect(p.canAccessFactory('Usine A'), isTrue);
      expect(p.canAccessFactory('usine a '), isTrue); // case/space tolerant
      expect(p.canAccessFactory('Usine B'), isFalse);
      expect(const OnPremRolePolicy(OnPremRole.supervisor)
          .canAccessFactory('Usine A'), isFalse);
    });

    test('vendor support is read-only diagnostics with no factory access', () {
      const p = OnPremRolePolicy(OnPremRole.vendorSupport);
      expect(p.isReadOnly, isTrue);
      expect(p.canReadDiagnostics, isTrue);
      expect(p.canAccessFactory('Usine A'), isFalse);
      expect(p.canManageFactoryOperations, isFalse);
    });

    test('vendor access window: disabled by default, active only inside window', () {
      final now = DateTime.utc(2026, 7, 11);
      expect(const VendorAccessWindow().isActive(now), isFalse);
      expect(
        VendorAccessWindow(enabled: true, expiresAt: DateTime.utc(2026, 7, 12))
            .isActive(now),
        isTrue,
      );
      expect(
        VendorAccessWindow(enabled: true, expiresAt: DateTime.utc(2026, 7, 10))
            .isActive(now),
        isFalse,
      );
      expect(
        VendorAccessWindow(enabled: false, expiresAt: DateTime.utc(2026, 7, 12))
            .isActive(now),
        isFalse,
      );
    });

    test('legacy "admin" role maps to production manager, unknown maps to null', () {
      expect(OnPremRole.parse('admin'), OnPremRole.productionManager);
      expect(OnPremRole.parse('COMPANY_OWNER'), OnPremRole.companyOwner);
      expect(OnPremRole.parse('superadmin'), isNull); // platform role stays out
      expect(OnPremRole.parse(''), isNull);
    });
  });

  group('PocketBaseAuthService', () {
    PocketBaseAuthService serviceWith(
      MockClient client, {
      MfaProvider mfa = const NoopMfaProvider(),
      DateTime Function()? now,
    }) =>
        PocketBaseAuthService(
          baseUrl: 'http://pb',
          client: client,
          mfa: mfa,
          now: now ?? () => DateTime.utc(2026, 7, 11),
        );

    Map<String, dynamic> record({
      String role = 'supervisor',
      bool disabled = false,
      String? vendorUntil,
    }) =>
        {
          'id': 'u1',
          'email': 'sam@plant.local',
          'name': 'Sam One',
          'role': role,
          'usine': 'Usine A',
          'disabled': disabled,
          if (vendorUntil != null) 'vendorAccessExpiresAt': vendorUntil,
        };

    test('sign-in activates the session and decodes token expiry', () async {
      // Deliberately far in the future so the assertion never collides with
      // the real wall clock OnPremSession.isSignedIn checks against.
      final exp = DateTime.utc(2099, 7, 12).millisecondsSinceEpoch ~/ 1000;
      final client = MockClient((req) async {
        if (req.url.path.contains('auth-with-password')) {
          return http.Response(
            jsonEncode({'token': _fakeJwt(expEpochSeconds: exp), 'record': record()}),
            200,
          );
        }
        return http.Response('{}', 200); // audit append
      });

      final auth = serviceWith(client);
      final user = await auth.signIn('sam@plant.local', 'pw');

      expect(user.role, OnPremRole.supervisor);
      expect(session.userId, 'u1');
      expect(session.token, isNotEmpty);
      expect(session.tokenExpiresAt, DateTime.utc(2099, 7, 12));
      expect(auth.sessionValid, isTrue);
    });

    test('disabled accounts cannot sign in', () async {
      final client = MockClient((req) async {
        if (req.url.path.contains('auth-with-password')) {
          return http.Response(
            jsonEncode({'token': _fakeJwt(), 'record': record(disabled: true)}),
            200,
          );
        }
        return http.Response('{}', 200);
      });
      expect(
        () => serviceWith(client).signIn('x', 'y'),
        throwsA(isA<OnPremAuthException>()
            .having((e) => e.code, 'code', 'account_disabled')),
      );
    });

    test('vendor accounts need an unexpired access window and get audited', () async {
      final audits = <Map<String, dynamic>>[];
      final client = MockClient((req) async {
        if (req.url.path.contains('auth-with-password')) {
          return http.Response(
            jsonEncode({
              'token': _fakeJwt(),
              'record': record(
                  role: 'vendor_support',
                  vendorUntil: '2026-07-12T00:00:00.000Z'),
            }),
            200,
          );
        }
        if (req.url.path.contains('audit_logs')) {
          audits.add(Map<String, dynamic>.from(jsonDecode(req.body) as Map));
        }
        return http.Response('{}', 200);
      });

      final user = await serviceWith(client).signIn('vendor@sias.dev', 'pw');
      expect(user.role, OnPremRole.vendorSupport);
      expect(audits.single['action'], 'auth.vendor_sign_in');
    });

    test('expired vendor window is rejected', () async {
      final client = MockClient((req) async {
        return http.Response(
          jsonEncode({
            'token': _fakeJwt(),
            'record': record(
                role: 'vendor_support',
                vendorUntil: '2026-07-01T00:00:00.000Z'),
          }),
          200,
        );
      });
      expect(
        () => serviceWith(client).signIn('vendor@sias.dev', 'pw'),
        throwsA(isA<OnPremAuthException>()
            .having((e) => e.code, 'code', 'vendor_access_expired')),
      );
    });

    test('MFA provider gates activation when it requires a factor', () async {
      final client = MockClient((req) async {
        if (req.url.path.contains('auth-with-password')) {
          return http.Response(
            jsonEncode({'token': _fakeJwt(), 'record': record()}),
            200,
          );
        }
        return http.Response('{}', 200);
      });
      final mfa = _StubMfa();

      // No code -> blocked.
      await expectLater(
        serviceWith(client, mfa: mfa).signIn('sam', 'pw'),
        throwsA(isA<OnPremAuthException>()
            .having((e) => e.code, 'code', 'mfa_required')),
      );
      // Correct code -> session opens.
      final user =
          await serviceWith(client, mfa: mfa).signIn('sam', 'pw', mfaCode: '123456');
      expect(user.id, 'u1');
    });

    test('password change requires the old password and closes the session',
        () async {
      http.Request? patch;
      final client = MockClient((req) async {
        if (req.url.path.contains('auth-with-password')) {
          return http.Response(
            jsonEncode({'token': _fakeJwt(), 'record': record()}),
            200,
          );
        }
        if (req.method == 'PATCH') {
          patch = req;
          return http.Response('{}', 200);
        }
        return http.Response('{}', 200);
      });

      final auth = serviceWith(client);
      await auth.signIn('sam', 'pw');
      await auth.changePassword(oldPassword: 'pw', newPassword: 'better-pw-9');

      final body = jsonDecode(patch!.body) as Map<String, dynamic>;
      expect(body['oldPassword'], 'pw');
      expect(body['password'], 'better-pw-9');
      expect(body['passwordConfirm'], 'better-pw-9');
      expect(auth.sessionValid, isFalse); // token invalidated -> re-auth
      expect(session.userId, isNull);
    });

    test('expired JWT makes the local session invalid', () async {
      final past = DateTime.utc(2026, 7, 10).millisecondsSinceEpoch ~/ 1000;
      final client = MockClient((req) async {
        if (req.url.path.contains('auth-with-password')) {
          return http.Response(
            jsonEncode(
                {'token': _fakeJwt(expEpochSeconds: past), 'record': record()}),
            200,
          );
        }
        return http.Response('{}', 200);
      });

      final auth = serviceWith(client);
      await auth.signIn('sam', 'pw');
      expect(auth.sessionValid, isFalse);
    });

    test('failed refresh clears the session', () async {
      var calls = 0;
      final client = MockClient((req) async {
        calls++;
        if (req.url.path.contains('auth-with-password')) {
          return http.Response(
            jsonEncode({'token': _fakeJwt(), 'record': record()}),
            200,
          );
        }
        if (req.url.path.contains('auth-refresh')) {
          return http.Response('', 401);
        }
        return http.Response('{}', 200);
      });

      final auth = serviceWith(client);
      await auth.signIn('sam', 'pw');
      await expectLater(
        auth.refresh(),
        throwsA(isA<OnPremAuthException>()
            .having((e) => e.code, 'code', 'session_expired')),
      );
      expect(session.userId, isNull);
      expect(calls, greaterThan(1));
    });

    test('only the company owner can disable accounts or grant vendor windows',
        () async {
      final client = MockClient((req) async {
        if (req.url.path.contains('auth-with-password')) {
          return http.Response(
            jsonEncode({'token': _fakeJwt(), 'record': record()}),
            200,
          );
        }
        return http.Response('{}', 200);
      });

      final auth = serviceWith(client);
      await auth.signIn('sam', 'pw'); // supervisor
      expect(
        () => auth.setAccountDisabled('u2', true),
        throwsA(isA<OnPremAuthException>()
            .having((e) => e.code, 'code', 'forbidden')),
      );
      expect(
        () => auth.grantVendorAccess('u2', const Duration(hours: 4)),
        throwsA(isA<OnPremAuthException>()
            .having((e) => e.code, 'code', 'forbidden')),
      );
    });

    test('owner vendor grant PATCHes an expiry and audits the grant', () async {
      final patches = <http.Request>[];
      final audits = <Map<String, dynamic>>[];
      final client = MockClient((req) async {
        if (req.url.path.contains('auth-with-password')) {
          return http.Response(
            jsonEncode(
                {'token': _fakeJwt(), 'record': record(role: 'company_owner')}),
            200,
          );
        }
        if (req.method == 'PATCH') patches.add(req);
        if (req.url.path.contains('audit_logs')) {
          audits.add(Map<String, dynamic>.from(jsonDecode(req.body) as Map));
        }
        return http.Response('{}', 200);
      });

      final auth = serviceWith(client);
      await auth.signIn('owner', 'pw');
      await auth.grantVendorAccess('u_vendor', const Duration(hours: 8));

      final body = jsonDecode(patches.single.body) as Map<String, dynamic>;
      expect(body['disabled'], false);
      expect(body['vendorAccessExpiresAt'], '2026-07-11T08:00:00.000Z');
      expect(
        audits.map((a) => a['action']),
        contains('account.vendor_access_grant'),
      );
    });
  });
}

class _StubMfa implements MfaProvider {
  @override
  Future<MfaChallenge> begin(String userId) async =>
      const MfaChallenge(required: true, challengeId: 'c1', method: 'totp');

  @override
  Future<bool> complete(String challengeId, String code) async =>
      challengeId == 'c1' && code == '123456';
}
