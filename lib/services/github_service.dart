import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

typedef GithubAuthTokenProvider = Future<String?> Function();

/// Client for the GitHub proxy worker (`cloudflare_github_worker.js`). The worker
/// holds the GitHub token server-side; the app authenticates with the shared
/// worker secret. If the proxy host is unreachable, public read-only GitHub data
/// is loaded directly for public repositories.
class GithubService {
  GithubService({
    required String baseUrl,
    String? sharedSecret,
    String? repo,
    http.Client? client,
    GithubAuthTokenProvider? authTokenProvider,
  }) : _base = baseUrl.replaceAll(RegExp(r'/+$'), ''),
       _secret = sharedSecret ?? '',
       _repo = repo ?? '',
       _client = client ?? http.Client(),
       _authTokenProvider = authTokenProvider ?? _firebaseIdToken;

  final String _base;
  final String _secret;
  final String _repo;
  final http.Client _client;
  final GithubAuthTokenProvider _authTokenProvider;

  static const Map<String, String> _githubHeaders = {
    'Accept': 'application/vnd.github+json',
  };
  static const Duration _proxyReadTimeout = Duration(seconds: 8);
  static const Duration _proxyWriteTimeout = Duration(seconds: 12);
  static final Map<String, ({bool connected, String repo})> _statusCache = {};

  static String normalizeRepo(String? value) {
    var raw = (value ?? '').trim();
    if (raw.isEmpty) return '';
    if (raw.startsWith('git@github.com:')) {
      raw = raw.substring('git@github.com:'.length);
    } else {
      final uri = Uri.tryParse(raw);
      if (uri != null && uri.hasScheme) {
        raw = uri.path;
      }
    }
    raw = raw.replaceFirst(RegExp(r'^/+'), '').replaceFirst(RegExp(r'/+$'), '');
    var parts = raw.split('/').where((p) => p.trim().isNotEmpty).toList();
    if (parts.isNotEmpty &&
        parts.first
            .toLowerCase()
            .replaceFirst('www.', '')
            .endsWith('github.com')) {
      parts = parts.skip(1).toList();
    }
    if (parts.isNotEmpty && parts.first.toLowerCase() == 'repos') {
      parts = parts.skip(1).toList();
    }
    if (parts.length < 2) return '';
    final owner = parts[0].trim();
    final repo = parts[1].trim().replaceFirst(RegExp(r'\.git$'), '');
    if (owner.isEmpty || repo.isEmpty) return '';
    if (owner.contains(RegExp(r'\s')) || repo.contains(RegExp(r'\s'))) {
      return '';
    }
    return '$owner/$repo';
  }

  static String _cacheBase(String baseUrl) =>
      baseUrl.replaceAll(RegExp(r'/+$'), '');

  static String _cacheKey(String baseUrl, String repo) =>
      '${_cacheBase(baseUrl)}|${normalizeRepo(repo)}';

  static void forgetCachedStatus({String? baseUrl, String? repo}) {
    if (baseUrl == null || baseUrl.trim().isEmpty) {
      _statusCache.clear();
      return;
    }
    final base = _cacheBase(baseUrl);
    final normalized = normalizeRepo(repo);
    if (normalized.isEmpty) {
      _statusCache.removeWhere(
        (key, _) => key == '$base|' || key.startsWith('$base|'),
      );
      return;
    }
    _statusCache.remove('$base|$normalized');
    _statusCache.remove('$base|');
  }

  static Future<String?> _firebaseIdToken() async {
    try {
      return await FirebaseAuth.instance.currentUser?.getIdToken();
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, String>> _headers() async {
    final token = await _authTokenProvider();
    return {
      if (_secret.isNotEmpty) 'Authorization': 'Bearer $_secret',
      if (token != null && token.isNotEmpty) 'X-Firebase-Auth': 'Bearer $token',
    };
  }

  String _withRepo(String path, [String? preferredRepo]) {
    final repo = _fallbackRepo(preferredRepo);
    if (repo.isEmpty) return path;
    final sep = path.contains('?') ? '&' : '?';
    return '$path${sep}repo=${Uri.encodeQueryComponent(repo)}';
  }

  Uri _uri(String path, [String? preferredRepo]) {
    final target = '$_base${_withRepo(path, preferredRepo)}';
    final parsed = Uri.parse(target);
    return parsed.hasScheme ? parsed : Uri.base.resolve(target);
  }

  String _fallbackRepo([String? preferred]) {
    for (final candidate in [preferred, _repo]) {
      final value = normalizeRepo(candidate);
      if (value.isEmpty) continue;
      return value;
    }
    return '';
  }

  ({bool connected, String repo})? _cachedStatus([String? preferredRepo]) {
    final repo = _fallbackRepo(preferredRepo);
    if (repo.isNotEmpty) return _statusCache[_cacheKey(_base, repo)];
    return _statusCache[_cacheKey(_base, '')];
  }

  void _rememberConnected(String repo) {
    final normalized = normalizeRepo(repo);
    if (normalized.isEmpty) return;
    final status = (connected: true, repo: normalized);
    _statusCache[_cacheKey(_base, normalized)] = status;
    _statusCache[_cacheKey(_base, '')] = status;
  }

  String _proxyReachabilityMessage(Object error) {
    final target = _base.isEmpty ? 'the configured proxy URL' : _base;
    final text = error.toString().toLowerCase();
    if (text.contains('timeout')) {
      return 'Guardian proxy timed out at $target. Token and repo were not checked because the Cloudflare proxy did not answer.';
    }
    return 'Guardian proxy unreachable at $target. Token and repo were not checked because the app could not reach the Cloudflare proxy.';
  }

  Uri _githubUri(
    String repo,
    String path, [
    Map<String, String>? queryParameters,
  ]) => Uri.https('api.github.com', '/repos/$repo$path', queryParameters);

  Future<({int status, Object? body})?> _githubGetJson(
    String repo,
    String path, [
    Map<String, String>? queryParameters,
  ]) async {
    try {
      final res = await _client.get(
        _githubUri(repo, path, queryParameters),
        headers: _githubHeaders,
      );
      Object? body;
      try {
        body = jsonDecode(res.body);
      } catch (_) {
        body = null;
      }
      return (status: res.statusCode, body: body);
    } catch (_) {
      return null;
    }
  }

  Future<({int status, List<Map<String, dynamic>> runs})> _publicRuns(
    String repo, {
    int perPage = 20,
  }) async {
    final res = await _githubGetJson(repo, '/actions/runs', {
      'per_page': '$perPage',
    });
    if (res == null) return (status: 0, runs: <Map<String, dynamic>>[]);
    if (res.status != 200) {
      return (status: res.status, runs: <Map<String, dynamic>>[]);
    }
    final body = res.body;
    final items = (body is Map && body['workflow_runs'] is List)
        ? body['workflow_runs'] as List
        : const [];
    return (status: 200, runs: _mapItems(items, _mapRun));
  }

  Future<({int status, List<Map<String, dynamic>> items})> _publicListResult(
    String path,
    String key,
  ) async {
    final repo = _fallbackRepo();
    if (repo.isEmpty) return (status: 0, items: <Map<String, dynamic>>[]);
    if (key == 'runs') {
      final runs = await _publicRuns(repo);
      return (status: runs.status, items: runs.runs);
    }

    if (key == 'pulls') {
      final res = await _githubGetJson(repo, '/pulls', {
        'state': 'all',
        'per_page': '20',
        'sort': 'updated',
        'direction': 'desc',
      });
      final body = res?.body;
      if (res?.status != 200 || body is! List) {
        return (status: res?.status ?? 0, items: <Map<String, dynamic>>[]);
      }
      return (status: 200, items: _mapItems(body, _mapPull));
    }

    if (key == 'deployments') {
      final res = await _githubGetJson(repo, '/deployments', {
        'per_page': '20',
      });
      final body = res?.body;
      if (res?.status != 200 || body is! List) {
        return (status: res?.status ?? 0, items: <Map<String, dynamic>>[]);
      }
      return (status: 200, items: _mapItems(body, _mapDeployment));
    }

    if (key == 'jobs') {
      final id = Uri.parse('https://local$path').queryParameters['id'];
      if (id == null || id.isEmpty) {
        return (status: 0, items: <Map<String, dynamic>>[]);
      }
      final res = await _githubGetJson(repo, '/actions/runs/$id/jobs');
      if (res?.status != 200) {
        return (status: res?.status ?? 0, items: <Map<String, dynamic>>[]);
      }
      final body = res?.body;
      final items = (body is Map && body['jobs'] is List)
          ? body['jobs'] as List
          : const [];
      return (status: 200, items: _mapItems(items, _mapJob));
    }

    return (status: 0, items: <Map<String, dynamic>>[]);
  }

  static Map<String, dynamic> _asMap(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  static String _login(Object? value) {
    final m = _asMap(value);
    return (m['login'] ?? '').toString();
  }

  static List<Map<String, dynamic>> _mapItems(
    List items,
    Map<String, dynamic> Function(Object?) mapper,
  ) {
    final out = <Map<String, dynamic>>[];
    for (final item in items) {
      out.add(mapper(item));
    }
    return out;
  }

  static Map<String, dynamic> _mapRun(Object? value) {
    final r = _asMap(value);
    final actor = _login(r['actor']);
    return {
      'id': r['id'],
      'name': (r['name'] ?? r['display_title'] ?? '').toString(),
      'workflow': (r['path'] ?? '').toString(),
      'status': (r['status'] ?? '').toString(),
      'conclusion': r['conclusion'],
      'branch': (r['head_branch'] ?? '').toString(),
      'event': (r['event'] ?? '').toString(),
      'actor': actor.isNotEmpty ? actor : _login(r['triggering_actor']),
      'runNumber': r['run_number'],
      'createdAt': (r['created_at'] ?? '').toString(),
      'updatedAt': (r['updated_at'] ?? '').toString(),
      'url': (r['html_url'] ?? '').toString(),
    };
  }

  static Map<String, dynamic> _mapPull(Object? value) {
    final p = _asMap(value);
    final head = _asMap(p['head']);
    return {
      'number': p['number'],
      'title': (p['title'] ?? '').toString(),
      'state': p['merged_at'] != null
          ? 'merged'
          : (p['state'] ?? '').toString(),
      'draft': p['draft'] == true,
      'user': _login(p['user']),
      'branch': (head['ref'] ?? '').toString(),
      'createdAt': (p['created_at'] ?? '').toString(),
      'url': (p['html_url'] ?? '').toString(),
    };
  }

  static Map<String, dynamic> _mapDeployment(Object? value) {
    final d = _asMap(value);
    final sha = (d['sha'] ?? '').toString();
    return {
      'id': d['id'],
      'environment': (d['environment'] ?? '').toString(),
      'ref': (d['ref'] ?? '').toString(),
      'sha': sha.length > 7 ? sha.substring(0, 7) : sha,
      'creator': _login(d['creator']),
      'createdAt': (d['created_at'] ?? '').toString(),
      'description': (d['description'] ?? '').toString(),
    };
  }

  static Map<String, dynamic> _mapJob(Object? value) {
    final j = _asMap(value);
    final steps = j['steps'] is List ? j['steps'] as List : const [];
    return {
      'id': j['id'],
      'name': (j['name'] ?? '').toString(),
      'status': (j['status'] ?? '').toString(),
      'conclusion': j['conclusion'],
      'startedAt': (j['started_at'] ?? '').toString(),
      'completedAt': (j['completed_at'] ?? '').toString(),
      'steps': steps.map((step) {
        final s = _asMap(step);
        return {
          'name': s['name'],
          'status': s['status'],
          'conclusion': s['conclusion'],
          'number': s['number'],
        };
      }).toList(),
    };
  }

  List<Map<String, dynamic>> _decodeProxyList(Object? body, String key) {
    final items = (body is Map && body[key] is List)
        ? body[key] as List
        : const [];
    return items.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> _list(String path, String key) async {
    final public = await _publicListResult(path, key);
    if (public.status == 200) return public.items;
    try {
      final res = await _client
          .get(_uri(path), headers: await _headers())
          .timeout(_proxyReadTimeout);
      if (res.statusCode == 200) {
        return _decodeProxyList(jsonDecode(res.body), key);
      }
    } catch (_) {
      // Fall through to GitHub's public API for public repositories.
    }
    return public.items;
  }

  Future<List<Map<String, dynamic>>> runs() => _list('/runs', 'runs');

  Future<List<Map<String, dynamic>>> pulls() => _list('/pulls', 'pulls');

  Future<List<Map<String, dynamic>>> deployments() =>
      _list('/deployments', 'deployments');

  /// Step-level jobs for a workflow run (drives the live pipeline + terminal).
  Future<List<Map<String, dynamic>>> runJobs(Object runId) =>
      _list('/run-jobs?id=${Uri.encodeQueryComponent('$runId')}', 'jobs');

  /// Raw stdout tail of one job (the real `$ npm test` / build output). Returns
  /// '' while the job is still warming up or on any error. Public fallback does
  /// not fetch logs, because GitHub log archives require the server-side token.
  Future<String> jobLogs(Object jobId) async {
    try {
      final res = await _client
          .get(
            _uri('/job-logs?id=${Uri.encodeQueryComponent('$jobId')}'),
            headers: await _headers(),
          )
          .timeout(_proxyReadTimeout);
      if (res.statusCode != 200) return '';
      final body = jsonDecode(res.body);
      return (body is Map && body['logs'] is String)
          ? body['logs'] as String
          : '';
    } catch (_) {
      return '';
    }
  }

  /// Fire the Guardian drill for real: the proxy worker forwards a
  /// repository_dispatch (guardian_drill) using its server-side GitHub token.
  /// [mode] is 'automatic' (push to main + deploy) or 'human' (open a PR).
  /// Returns true if the dispatch was accepted (HTTP 200).
  Future<bool> dispatchDrill({
    String mode = 'human',
    String target = 'tool/guardian_drill_target.mjs',
  }) async {
    try {
      final res = await _client
          .post(
            _uri('/dispatch'),
            headers: {...await _headers(), 'Content-Type': 'application/json'},
            body: jsonEncode({
              'event_type': 'guardian_drill',
              'client_payload': {'mode': mode, 'target': target},
            }),
          )
          .timeout(_proxyWriteTimeout);
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Resolved repository (`owner/name`) as the proxy worker sees it, plus
  /// whether the proxy token can reach GitHub. A prior verified state is kept
  /// only through transient proxy/network failures.
  Future<({bool connected, String repo})> status() async {
    var repo = _fallbackRepo();
    try {
      final headers = await _headers();
      final res = await _client
          .get(_uri('/config?fresh=1'), headers: headers)
          .timeout(_proxyReadTimeout);
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        if (body is Map) {
          repo = _fallbackRepo((body['repo'] ?? '').toString());
        }
      }
      if (repo.isEmpty || res.statusCode != 200) {
        return (connected: false, repo: repo);
      }
      final runs = await _client
          .get(_uri('/runs?fresh=1', repo), headers: headers)
          .timeout(_proxyReadTimeout);
      if (runs.statusCode == 200) {
        _rememberConnected(repo);
        return (connected: true, repo: repo);
      }
      return (connected: false, repo: repo);
    } catch (_) {
      // Keep a verified connection latched through transient proxy failures.
    }
    final cached = _cachedStatus(repo);
    if (cached != null) return cached;
    return (connected: false, repo: repo);
  }

  Future<bool> connected() async => (await status()).connected;

  /// Deep connection check for the "Verify" affordance: the proxy must be able
  /// to reach GitHub with its server-side token. Public GitHub visibility is not
  /// enough for Guardian, because dispatches and job logs require that token.
  Future<({bool ok, String repo, int runs, String message})> verify() async {
    var repo = _fallbackRepo();
    try {
      final headers = await _headers();
      final cfg = await _client
          .get(_uri('/config?fresh=1'), headers: headers)
          .timeout(_proxyReadTimeout);
      if (cfg.statusCode == 200) {
        final b = jsonDecode(cfg.body);
        if (b is Map) {
          repo = _fallbackRepo((b['repo'] ?? '').toString());
        }
      }
      final res = await _client
          .get(_uri('/runs?fresh=1', repo), headers: headers)
          .timeout(_proxyReadTimeout);
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final n = (body is Map && body['runs'] is List)
            ? (body['runs'] as List).length
            : 0;
        _rememberConnected(repo);
        return (
          ok: true,
          repo: repo,
          runs: n,
          message:
              'Connected to ${repo.isEmpty ? 'repository' : repo} - $n workflow run${n == 1 ? '' : 's'} visible.',
        );
      }
      if (res.statusCode == 401) {
        return (
          ok: false,
          repo: repo,
          runs: 0,
          message:
              'Guardian proxy rejected authentication. Sign in as SuperAdmin or check the worker shared secret.',
        );
      }
      if (res.statusCode == 403) {
        return (
          ok: false,
          repo: repo,
          runs: 0,
          message:
              'Guardian proxy denied access. Use a SuperAdmin account to verify the GitHub connection.',
        );
      }
      if (res.statusCode == 503) {
        return (
          ok: false,
          repo: repo,
          runs: 0,
          message: 'Worker has no repo + token configured.',
        );
      }
      String detail = '';
      try {
        final b = jsonDecode(res.body);
        if (b is Map && b['error'] != null) detail = b['error'].toString();
      } catch (_) {}
      final isAuth =
          detail.contains('404') ||
          detail.contains('403') ||
          detail.contains('401');
      return (
        ok: false,
        repo: repo,
        runs: 0,
        message: isAuth
            ? 'Token cannot reach ${repo.isEmpty ? 'this repo' : repo} - check the repo name and token scopes.'
            : 'Could not reach GitHub${detail.isEmpty ? '' : ' ($detail)'}.',
      );
    } catch (error) {
      return (
        ok: false,
        repo: repo,
        runs: 0,
        message: _proxyReachabilityMessage(error),
      );
    }
  }

  /// Releases the underlying HTTP client. Call from the owner's dispose().
  void close() => _client.close();
}
