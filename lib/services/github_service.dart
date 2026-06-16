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

  /// Step-level jobs for a workflow run (drives the live terminal stream).
  Future<List<Map<String, dynamic>>> runJobs(Object runId) =>
      _list('/run-jobs?id=${Uri.encodeQueryComponent('$runId')}', 'jobs');

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

  Future<bool> connected() async {
    try {
      final res = await _client.get(Uri.parse('$_base/config'), headers: _headers);
      if (res.statusCode != 200) return false;
      final b = jsonDecode(res.body);
      return b is Map && b['connected'] == true;
    } catch (_) {
      return false;
    }
  }
}
