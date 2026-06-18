import 'dart:convert';

import 'package:http/http.dart' as http;

/// Client for the GitHub proxy worker (`cloudflare_github_worker.js`). The worker
/// holds the GitHub token server-side; we authenticate with the shared worker
/// secret. Read-only: workflow runs, pull requests, deployments.
class GithubService {
  GithubService({
    required String baseUrl,
    String? sharedSecret,
    String? repo,
    http.Client? client,
  })  : _base = baseUrl.replaceAll(RegExp(r'/+$'), ''),
        _secret = sharedSecret ?? '',
        _repo = repo ?? '',
        _client = client ?? http.Client();

  final String _base;
  final String _secret;
  final String _repo;
  final http.Client _client;

  Map<String, String> get _headers =>
      {if (_secret.isNotEmpty) 'Authorization': 'Bearer $_secret'};

  String _withRepo(String path) {
    if (_repo.isEmpty) return path;
    final sep = path.contains('?') ? '&' : '?';
    return '$path${sep}repo=${Uri.encodeQueryComponent(_repo)}';
  }

  Future<List<Map<String, dynamic>>> _list(String path, String key) async {
    final res = await _client.get(Uri.parse('$_base${_withRepo(path)}'), headers: _headers);
    if (res.statusCode != 200) return <Map<String, dynamic>>[];
    final body = jsonDecode(res.body);
    final items = (body is Map && body[key] is List) ? body[key] as List : const [];
    return items.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> runs() => _list('/runs', 'runs');
  Future<List<Map<String, dynamic>>> pulls() => _list('/pulls', 'pulls');
  Future<List<Map<String, dynamic>>> deployments() => _list('/deployments', 'deployments');

  /// Step-level jobs for a workflow run (drives the live pipeline + terminal).
  Future<List<Map<String, dynamic>>> runJobs(Object runId) =>
      _list('/run-jobs?id=${Uri.encodeQueryComponent('$runId')}', 'jobs');

  /// Raw stdout tail of one job (the real `$ npm test` / build output). Returns
  /// '' while the job is still warming up or on any error — best-effort so the
  /// terminal degrades gracefully to step-level lines.
  Future<String> jobLogs(Object jobId) async {
    try {
      final res = await _client.get(
        Uri.parse('$_base${_withRepo('/job-logs?id=${Uri.encodeQueryComponent('$jobId')}')}'),
        headers: _headers,
      );
      if (res.statusCode != 200) return '';
      final body = jsonDecode(res.body);
      return (body is Map && body['logs'] is String) ? body['logs'] as String : '';
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
      final res = await _client.post(
        Uri.parse('$_base${_withRepo('/dispatch')}'),
        headers: {..._headers, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'event_type': 'guardian_drill',
          'client_payload': {'mode': mode, 'target': target},
        }),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Resolved repository (`owner/name`) as the proxy worker sees it, plus whether
  /// a server-side token is present. Drives the GitHub-faithful console header.
  Future<({bool connected, String repo})> status() async {
    try {
      final res = await _client.get(Uri.parse('$_base/config'), headers: _headers);
      if (res.statusCode != 200) return (connected: false, repo: '');
      final b = jsonDecode(res.body);
      if (b is! Map) return (connected: false, repo: '');
      return (connected: b['connected'] == true, repo: (b['repo'] ?? '').toString());
    } catch (_) {
      return (connected: false, repo: '');
    }
  }

  Future<bool> connected() async => (await status()).connected;

  /// Deep connection check for the "Verify" affordance: not only is a token
  /// present, but the proxy worker can actually reach the repo with it. Returns
  /// a human-readable [message] suitable for an inline status line.
  Future<({bool ok, String repo, int runs, String message})> verify() async {
    String repo = '';
    try {
      final cfg = await _client.get(Uri.parse('$_base/config'), headers: _headers);
      if (cfg.statusCode == 401) {
        return (ok: false, repo: '', runs: 0, message: 'Worker rejected the shared secret.');
      }
      if (cfg.statusCode == 200) {
        final b = jsonDecode(cfg.body);
        if (b is Map) {
          repo = (b['repo'] ?? '').toString();
          if (b['connected'] != true) {
            return (ok: false, repo: repo, runs: 0, message: 'No GitHub token set on the proxy worker yet.');
          }
        }
      }
      final res = await _client.get(Uri.parse('$_base${_withRepo('/runs')}'), headers: _headers);
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final n = (body is Map && body['runs'] is List) ? (body['runs'] as List).length : 0;
        return (ok: true, repo: repo, runs: n, message: 'Connected to ${repo.isEmpty ? 'repository' : repo} · $n workflow run${n == 1 ? '' : 's'} visible.');
      }
      if (res.statusCode == 401) {
        return (ok: false, repo: repo, runs: 0, message: 'Worker rejected the shared secret.');
      }
      if (res.statusCode == 503) {
        return (ok: false, repo: repo, runs: 0, message: 'Worker has no repo + token configured.');
      }
      String detail = '';
      try {
        final b = jsonDecode(res.body);
        if (b is Map && b['error'] != null) detail = b['error'].toString();
      } catch (_) {}
      final isAuth = detail.contains('404') || detail.contains('403') || detail.contains('401');
      return (
        ok: false,
        repo: repo,
        runs: 0,
        message: isAuth
            ? 'Token cannot reach ${repo.isEmpty ? 'this repo' : repo} — check the repo name and token scopes.'
            : 'Could not reach GitHub${detail.isEmpty ? '' : ' ($detail)'}.',
      );
    } catch (e) {
      return (ok: false, repo: repo, runs: 0, message: 'Proxy worker unreachable.');
    }
  }

  /// Releases the underlying HTTP client. Call from the owner's dispose().
  void close() => _client.close();
}
