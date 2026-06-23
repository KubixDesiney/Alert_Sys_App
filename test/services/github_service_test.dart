import 'dart:async';
import 'dart:convert';

import 'package:alertsysapp/services/github_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  setUp(GithubService.forgetCachedStatus);

  test('normalizeRepo accepts owner/name and GitHub URLs', () {
    expect(GithubService.normalizeRepo('owner/repo'), 'owner/repo');
    expect(
      GithubService.normalizeRepo('https://github.com/owner/repo'),
      'owner/repo',
    );
    expect(
      GithubService.normalizeRepo('git@github.com:owner/repo.git'),
      'owner/repo',
    );
    expect(
      GithubService.normalizeRepo('https://api.github.com/repos/owner/repo'),
      'owner/repo',
    );
  });

  test(
    'status keeps a verified connection through a transient proxy failure',
    () async {
      var configCalls = 0;
      final client = MockClient((request) async {
        if (request.url.host == 'proxy.test' && request.url.path == '/config') {
          configCalls++;
          if (configCalls == 1) {
            return http.Response(
              jsonEncode({'connected': true, 'repo': 'owner/repo'}),
              200,
            );
          }
          throw Exception('temporary network failure');
        }
        if (request.url.host == 'proxy.test' && request.url.path == '/runs') {
          return http.Response(jsonEncode({'runs': []}), 200);
        }
        if (request.url.host == 'api.github.com') {
          return http.Response(jsonEncode({'message': 'not found'}), 404);
        }
        return http.Response('{}', 404);
      });
      final service = GithubService(
        baseUrl: 'https://proxy.test',
        sharedSecret: 'secret',
        repo: 'owner/repo',
        client: client,
        authTokenProvider: () async => null,
      );

      final first = await service.status();
      final second = await service.status();

      expect(first.connected, isTrue);
      expect(first.repo, 'owner/repo');
      expect(second.connected, isTrue);
      expect(second.repo, 'owner/repo');
    },
  );

  test(
    'verify requires the token-backed proxy even for public repositories',
    () async {
      final service = GithubService(
        baseUrl: 'https://proxy.test',
        sharedSecret: 'secret',
        repo: 'owner/repo',
        client: MockClient((request) async {
          if (request.url.host == 'proxy.test' &&
              request.url.path == '/config') {
            return http.Response(
              jsonEncode({'connected': false, 'repo': 'owner/repo'}),
              200,
            );
          }
          if (request.url.host == 'proxy.test' && request.url.path == '/runs') {
            return http.Response(jsonEncode({'error': 'not_configured'}), 503);
          }
          if (request.url.host == 'api.github.com') {
            return http.Response(jsonEncode({'workflow_runs': []}), 200);
          }
          return http.Response('{}', 404);
        }),
        authTokenProvider: () async => null,
      );

      final result = await service.verify();

      expect(result.ok, isFalse);
      expect(result.message, 'Worker has no repo + token configured.');
    },
  );

  test('status does not use public GitHub as a connected signal', () async {
    final service = GithubService(
      baseUrl: 'https://proxy.test',
      sharedSecret: 'secret',
      repo: 'owner/repo',
      client: MockClient((request) async {
        if (request.url.host == 'proxy.test') {
          throw Exception('proxy down');
        }
        if (request.url.host == 'api.github.com') {
          return http.Response(jsonEncode({'workflow_runs': []}), 200);
        }
        return http.Response('{}', 404);
      }),
      authTokenProvider: () async => null,
    );

    final result = await service.status();

    expect(result.connected, isFalse);
    expect(result.repo, 'owner/repo');
  });

  test(
    'status verifies through the proxy runs endpoint with fresh creds',
    () async {
      final seen = <String>[];
      final service = GithubService(
        baseUrl: 'https://proxy.test',
        sharedSecret: 'secret',
        repo: '',
        client: MockClient((request) async {
          seen.add('${request.url.path}?${request.url.query}');
          if (request.url.path == '/config') {
            return http.Response(
              jsonEncode({'connected': true, 'repo': 'owner/repo'}),
              200,
            );
          }
          if (request.url.path == '/runs') {
            return http.Response(jsonEncode({'runs': []}), 200);
          }
          return http.Response('{}', 404);
        }),
        authTokenProvider: () async => null,
      );

      final result = await service.status();

      expect(result.connected, isTrue);
      expect(result.repo, 'owner/repo');
      expect(seen, contains('/config?fresh=1'));
      expect(seen, contains('/runs?fresh=1&repo=owner%2Frepo'));
    },
  );

  test('verify reports proxy timeout before credential checks', () async {
    final service = GithubService(
      baseUrl: 'https://proxy.test/github-proxy',
      sharedSecret: 'secret',
      repo: 'owner/repo',
      client: MockClient((request) async {
        throw TimeoutException('proxy timed out');
      }),
      authTokenProvider: () async => null,
    );

    final result = await service.verify();

    expect(result.ok, isFalse);
    expect(result.repo, 'owner/repo');
    expect(result.message, contains('Guardian proxy timed out'));
    expect(result.message, contains('https://proxy.test/github-proxy'));
    expect(result.message, contains('Token and repo were not checked'));
  });
}
