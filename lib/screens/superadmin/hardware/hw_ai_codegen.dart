import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:http/http.dart' as http;

import '../../../config/app_config.dart';

/// AI firmware generation for the Hardware Lab.
///
/// Mirrors the rest of the console's "configurable AI model + API token"
/// pattern: the operator picks any provider/model and pastes its key in the
/// Code panel; that pair is stored server-side in the RTDB vault
/// (`ai_model_config/hardware`) and the worker's `/hardware-codegen` endpoint
/// reads it and calls the provider. The token never travels in the
/// prompt→code request, and a built-in Llama fallback keeps generation working
/// even with no key configured.

/// Models the worker understands (mirrors LLM_MODELS in cloudflare_ai_worker.js).
const List<({String id, String label})> kHwAiModels = [
  (id: 'llama-3.2', label: 'Llama 3.2 (built-in, no key)'),
  (id: 'gpt-4o', label: 'OpenAI GPT-4o'),
  (id: 'gpt-4o-mini', label: 'OpenAI GPT-4o mini'),
  (id: 'claude-opus', label: 'Claude Opus 4.8'),
  (id: 'claude-sonnet', label: 'Claude Sonnet 4.6'),
  (id: 'claude-haiku', label: 'Claude Haiku 4.5'),
  (id: 'gemini-pro', label: 'Gemini 1.5 Pro'),
  (id: 'gemini-flash', label: 'Gemini 1.5 Flash'),
  (id: 'mistral-large', label: 'Mistral Large'),
  (id: 'grok-2', label: 'xAI Grok-2'),
  (id: 'deepseek-chat', label: 'DeepSeek Chat'),
  (id: 'command-r-plus', label: 'Cohere Command R+'),
];

String hwAiModelLabel(String id) {
  for (final m in kHwAiModels) {
    if (m.id == id) return m.label;
  }
  return id;
}

class HwAiConfig {
  final String modelId;
  final bool hasKey;
  const HwAiConfig({this.modelId = 'llama-3.2', this.hasKey = false});
}

class HwCodegenResult {
  final bool ok;
  final String code;
  final String modelUsed;
  final bool fellBack;
  final String? error;
  const HwCodegenResult({
    required this.ok,
    this.code = '',
    this.modelUsed = '',
    this.fellBack = false,
    this.error,
  });
}

class HwCodegenService {
  HwCodegenService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const _timeout = Duration(seconds: 45);

  DatabaseReference get _cfgRef =>
      FirebaseDatabase.instance.ref('ai_model_config/hardware');

  /// Read which model is configured (and whether a key is stored). Never
  /// returns the key itself to the UI.
  Future<HwAiConfig> loadConfig() async {
    try {
      final snap = await _cfgRef.get();
      final v = snap.value;
      if (v is Map) {
        return HwAiConfig(
          modelId: '${v['modelId'] ?? 'llama-3.2'}',
          hasKey: '${v['apiKey'] ?? ''}'.trim().isNotEmpty,
        );
      }
    } catch (_) {}
    return const HwAiConfig();
  }

  /// Persist the model choice; the API key is written only when non-empty so a
  /// blank field keeps the previously-stored key.
  Future<void> saveConfig({required String modelId, String? apiKey}) async {
    final update = <String, Object?>{
      'modelId': modelId,
      'updatedAt': DateTime.now().toIso8601String(),
    };
    if (apiKey != null && apiKey.trim().isNotEmpty) {
      update['apiKey'] = apiKey.trim();
    }
    await _cfgRef.update(update);
  }

  /// Remove the stored key (revert to the built-in Llama path).
  Future<void> clearKey() async {
    await _cfgRef.child('apiKey').remove();
  }

  Future<Map<String, String>> _headers() async {
    String? token;
    try {
      token = await FirebaseAuth.instance.currentUser?.getIdToken();
    } catch (_) {}
    const secret = AppConfig.workerSharedSecret;
    return {
      'Content-Type': 'application/json',
      if (secret.isNotEmpty) 'Authorization': 'Bearer $secret',
      if (token != null && token.isNotEmpty) 'X-Firebase-Auth': 'Bearer $token',
    };
  }

  /// Generate an Arduino sketch from a natural-language prompt. The worker
  /// loads the configured provider/key from the RTDB vault server-side.
  Future<HwCodegenResult> generate({
    required String prompt,
    required String board,
    List<String> components = const [],
  }) async {
    final uri = Uri.parse('${AppConfig.aiWorkerBase}/hardware-codegen');
    try {
      final res = await _client
          .post(
            uri,
            headers: await _headers(),
            body: jsonEncode({
              'prompt': prompt,
              'board': board,
              'components': components,
            }),
          )
          .timeout(_timeout);
      if (res.statusCode != 200) {
        return HwCodegenResult(
          ok: false,
          error: 'Worker returned ${res.statusCode}. '
              '${_briefBody(res.body)}',
        );
      }
      final body = jsonDecode(res.body);
      if (body is Map && body['code'] is String &&
          (body['code'] as String).trim().isNotEmpty) {
        return HwCodegenResult(
          ok: true,
          code: _stripFences(body['code'] as String),
          modelUsed: '${body['modelUsed'] ?? ''}',
          fellBack: body['fellBack'] == true,
        );
      }
      return const HwCodegenResult(
        ok: false,
        error: 'The model returned no usable code. Try a more specific prompt.',
      );
    } catch (e) {
      return HwCodegenResult(
        ok: false,
        error: 'Could not reach the AI worker: $e',
      );
    }
  }

  String _briefBody(String body) {
    try {
      final j = jsonDecode(body);
      if (j is Map && j['error'] != null) return '${j['error']}';
    } catch (_) {}
    return body.length > 160 ? body.substring(0, 160) : body;
  }

  /// Strip ```cpp / ``` markdown fences the model may wrap the code in.
  static String _stripFences(String code) {
    var c = code.trim();
    final fence = RegExp(r'^```[a-zA-Z+]*\s*\n');
    if (fence.hasMatch(c)) {
      c = c.replaceFirst(fence, '');
      final end = c.lastIndexOf('```');
      if (end >= 0) c = c.substring(0, end);
    }
    return c.trim();
  }

  void close() => _client.close();
}
