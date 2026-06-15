import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:alertsysapp/services/data/data_store.dart';
import 'package:alertsysapp/services/data/pocketbase_data_store.dart';

void main() {
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
    });

    test('resolveAlert sets validee + reason + elapsed', () async {
      http.Request? seen;
      final client = MockClient((req) async {
        seen = req;
        return http.Response('{}', 200);
      });
      final s = PocketBaseDataStore(baseUrl: 'http://pb', client: client);

      await s.resolveAlert('al2', 'fixed belt', 12);

      final body = jsonDecode(seen!.body) as Map<String, dynamic>;
      expect(body['status'], 'validee');
      expect(body['resolutionReason'], 'fixed belt');
      expect(body['elapsedTime'], 12);
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
