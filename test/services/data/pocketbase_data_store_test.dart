import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:alertsysapp/services/data/data_store.dart';
import 'package:alertsysapp/services/data/onprem_session.dart';
import 'package:alertsysapp/services/data/pocketbase_data_store.dart';

void main() {
  tearDown(() => OnPremSession.instance.clear());

  group('PocketBaseDataStore', () {
    test('implements DataStore and reports its backend', () {
      final s = PocketBaseDataStore(
        baseUrl: 'http://pb',
        client: MockClient((_) async => http.Response('', 200)),
      );
      expect(s, isA<DataStore>());
      expect(s.backendName, 'pocketbase');
    });

    test('claimAlert PATCHes the record to en_cours with the supervisor', () async {
      http.Request? seen;
      final client = MockClient((req) async {
        seen = req;
        return http.Response(jsonEncode({'id': 'al1'}), 200);
      });
      final s = PocketBaseDataStore(baseUrl: 'http://pb/', token: 'T', client: client);

      await s.claimAlert('al1', 'sup1', 'Sam One');

      expect(seen!.method, 'PATCH');
      expect(seen!.url.toString(), contains('/api/collections/alerts/records/al1'));
      expect(seen!.headers['Authorization'], 'T');
      final body = jsonDecode(seen!.body) as Map<String, dynamic>;
      expect(body['status'], 'en_cours');
      expect(body['superviseurId'], 'sup1');
      expect(body['superviseurName'], 'Sam One');
      expect(body['takenAtTimestamp'], isNotEmpty);
    });

    test('the signed-in session token wins over the build-time token', () async {
      http.Request? seen;
      final client = MockClient((req) async {
        seen = req;
        return http.Response('{}', 200);
      });
      OnPremSession.instance.update(
        userId: 'u9',
        userName: 'Uma',
        role: 'supervisor',
        token: 'SESSION-TOKEN',
      );
      final s = PocketBaseDataStore(
          baseUrl: 'http://pb', token: 'BUILD-TOKEN', client: client);

      await s.setCritical('al1', true);

      expect(seen!.headers['Authorization'], 'SESSION-TOKEN');
    });

    test('resolveAlert sets validee + reason + elapsed + assistant credit', () async {
      http.Request? seen;
      final client = MockClient((req) async {
        seen = req;
        return http.Response('{}', 200);
      });
      final s = PocketBaseDataStore(baseUrl: 'http://pb', client: client);

      await s.resolveAlert('al2', 'fixed belt', 12,
          assistingSupervisorId: 'sup2', assistingSupervisorName: 'Alex');

      final body = jsonDecode(seen!.body) as Map<String, dynamic>;
      expect(body['status'], 'validee');
      expect(body['resolutionReason'], 'fixed belt');
      expect(body['elapsedTime'], 12);
      expect(body['assistingSupervisorId'], 'sup2');
      expect(body['assistingSupervisorName'], 'Alex');
    });

    test('returnAlertToQueue clears the claim and records the suspend reason',
        () async {
      http.Request? seen;
      final client = MockClient((req) async {
        seen = req;
        return http.Response('{}', 200);
      });
      final s = PocketBaseDataStore(baseUrl: 'http://pb', client: client);

      await s.returnAlertToQueue('al3', reason: 'end of shift');

      final body = jsonDecode(seen!.body) as Map<String, dynamic>;
      expect(body['status'], 'disponible');
      expect(body['superviseurId'], '');
      expect(body['superviseurName'], '');
      expect(body['takenAtTimestamp'], '');
      expect(body['suspendReason'], 'end of shift');
    });

    test('setCritical PATCHes the flag and optional note', () async {
      http.Request? seen;
      final client = MockClient((req) async {
        seen = req;
        return http.Response('{}', 200);
      });
      final s = PocketBaseDataStore(baseUrl: 'http://pb', client: client);

      await s.setCritical('al4', true, note: 'sparks visible');

      final body = jsonDecode(seen!.body) as Map<String, dynamic>;
      expect(body['isCritical'], true);
      expect(body['criticalNote'], 'sparks visible');
    });

    test('addComment appends to the existing comment list', () async {
      final requests = <http.Request>[];
      final client = MockClient((req) async {
        requests.add(req);
        if (req.method == 'GET') {
          return http.Response(
            jsonEncode({'id': 'al5', 'comments': ['[08:00] Sam: first']}),
            200,
          );
        }
        return http.Response('{}', 200);
      });
      final s = PocketBaseDataStore(baseUrl: 'http://pb', client: client);

      await s.addComment('al5', '[09:00] Alex: second');

      final patch = requests.lastWhere((r) => r.method == 'PATCH');
      final body = jsonDecode(patch.body) as Map<String, dynamic>;
      expect(body['comments'], ['[08:00] Sam: first', '[09:00] Alex: second']);
    });

    test('createAlert POSTs the canonical alert shape and audits it', () async {
      final requests = <http.Request>[];
      final client = MockClient((req) async {
        requests.add(req);
        if (req.method == 'GET') {
          // alertNumber lookup: current max is 41.
          return http.Response(
            jsonEncode({'items': [{'id': 'x', 'alertNumber': 41}]}),
            200,
          );
        }
        if (req.url.path.contains('audit_logs')) {
          return http.Response(jsonEncode({'id': 'audit1'}), 200);
        }
        return http.Response(jsonEncode({'id': 'new-alert'}), 200);
      });
      final s = PocketBaseDataStore(baseUrl: 'http://pb', client: client);

      final id = await s.createAlert(
        type: 'maintenance',
        usine: 'Usine A',
        convoyeur: 2,
        poste: 3,
        description: 'belt drift',
        isCritical: true,
      );

      expect(id, 'new-alert');
      final post = requests.firstWhere(
          (r) => r.method == 'POST' && r.url.path.contains('/alerts/'));
      final body = jsonDecode(post.body) as Map<String, dynamic>;
      expect(body['type'], 'maintenance');
      expect(body['usine'], 'Usine A');
      expect(body['alertNumber'], 42);
      expect(body['status'], 'disponible');
      expect(body['isCritical'], true);
      expect(body['adresse'], 'Usine_A_C2_P3');
      expect(body['source'], 'Manual');

      final audit = requests.where(
          (r) => r.method == 'POST' && r.url.path.contains('audit_logs'));
      expect(audit, hasLength(1));
      expect(jsonDecode(audit.first.body)['action'], 'alert.create');
    });

    test('fetchOlderAlerts filters on timestamp and usine', () async {
      Uri? seen;
      final client = MockClient((req) async {
        seen = req.url;
        return http.Response(jsonEncode({'items': []}), 200);
      });
      final s = PocketBaseDataStore(baseUrl: 'http://pb', client: client);

      await s.fetchOlderAlerts(
        usine: 'Usine A',
        before: DateTime.utc(2026, 3, 1),
        limit: 40,
      );

      final filter = seen!.queryParameters['filter']!;
      expect(filter, contains("timestamp<'2026-03-01"));
      expect(filter, contains("usine='Usine A'"));
      expect(seen!.queryParameters['perPage'], '40');
    });

    test('writeAudit never throws even when PocketBase is down', () async {
      final client = MockClient((_) async => http.Response('boom', 500));
      final s = PocketBaseDataStore(baseUrl: 'http://pb', client: client);
      await s.writeAudit(
        action: 'alert.claim',
        targetType: 'alert',
        targetId: 'a1',
      ); // must complete without throwing
    });

    test('fetchUserRole returns the role field', () async {
      final client = MockClient(
        (_) async => http.Response(jsonEncode({'id': 'u1', 'role': 'admin'}), 200),
      );
      final s = PocketBaseDataStore(baseUrl: 'http://pb', client: client);
      expect(await s.fetchUserRole('u1'), 'admin');
    });

    test('fetchUserRole returns null on a non-200', () async {
      final client = MockClient((_) async => http.Response('', 404));
      final s = PocketBaseDataStore(baseUrl: 'http://pb', client: client);
      expect(await s.fetchUserRole('missing'), isNull);
    });
  });
}
