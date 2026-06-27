import 'dart:convert';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';

/// One selectable LLM for the AI Assist / Briefing agents.
class AiModel {
  final String id; // stable key stored in ai_model_config
  final String provider; // cloudflare | openai | anthropic | google | mistral | xai | deepseek | cohere
  final String brandId; // brand-mark id for the real provider logo (meta/openai/anthropic/gemini/…)
  final String label; // shown in the picker
  final String providerModel; // the exact model string the provider API expects
  final bool needsKey; // false only for the built-in Cloudflare Workers AI Llama
  final Color color;
  final IconData icon; // fallback glyph

  const AiModel({
    required this.id,
    required this.provider,
    required this.brandId,
    required this.label,
    required this.providerModel,
    required this.needsKey,
    required this.color,
    required this.icon,
  });
}

/// The catalog the picker renders. Llama (Cloudflare Workers AI, no key) is the
/// default; every other provider needs the company's own API key. The worker
/// routes the call to the right provider based on the chosen model's id.
const List<AiModel> kAiModels = [
  AiModel(
    id: 'llama-3.2',
    provider: 'cloudflare',
    brandId: 'meta',
    label: 'Llama 3.2 · built-in (no key)',
    providerModel: '@cf/meta/llama-3.2-3b-instruct',
    needsKey: false,
    color: Color(0xFFF38020),
    icon: Icons.bolt_rounded,
  ),
  AiModel(
    id: 'gpt-4o',
    provider: 'openai',
    brandId: 'openai',
    label: 'OpenAI · GPT-4o',
    providerModel: 'gpt-4o',
    needsKey: true,
    color: Color(0xFF10A37F),
    icon: Icons.auto_awesome,
  ),
  AiModel(
    id: 'gpt-4o-mini',
    provider: 'openai',
    brandId: 'openai',
    label: 'OpenAI · GPT-4o mini',
    providerModel: 'gpt-4o-mini',
    needsKey: true,
    color: Color(0xFF10A37F),
    icon: Icons.auto_awesome_outlined,
  ),
  AiModel(
    id: 'claude-sonnet',
    provider: 'anthropic',
    brandId: 'anthropic',
    label: 'Anthropic · Claude Sonnet',
    providerModel: 'claude-sonnet-4-6',
    needsKey: true,
    color: Color(0xFFD97757),
    icon: Icons.psychology_alt,
  ),
  AiModel(
    id: 'claude-opus',
    provider: 'anthropic',
    brandId: 'anthropic',
    label: 'Anthropic · Claude Opus',
    providerModel: 'claude-opus-4-8',
    needsKey: true,
    color: Color(0xFFD97757),
    icon: Icons.psychology,
  ),
  AiModel(
    id: 'claude-haiku',
    provider: 'anthropic',
    brandId: 'anthropic',
    label: 'Anthropic · Claude Haiku',
    providerModel: 'claude-haiku-4-5-20251001',
    needsKey: true,
    color: Color(0xFFD97757),
    icon: Icons.psychology_outlined,
  ),
  AiModel(
    id: 'gemini-flash',
    provider: 'google',
    brandId: 'gemini',
    label: 'Google · Gemini 1.5 Flash',
    providerModel: 'gemini-1.5-flash',
    needsKey: true,
    color: Color(0xFF4285F4),
    icon: Icons.diamond_outlined,
  ),
  AiModel(
    id: 'gemini-pro',
    provider: 'google',
    brandId: 'gemini',
    label: 'Google · Gemini 1.5 Pro',
    providerModel: 'gemini-1.5-pro',
    needsKey: true,
    color: Color(0xFF4285F4),
    icon: Icons.diamond,
  ),
  AiModel(
    id: 'mistral-large',
    provider: 'mistral',
    brandId: 'mistral',
    label: 'Mistral · Large',
    providerModel: 'mistral-large-latest',
    needsKey: true,
    color: Color(0xFFFA520F),
    icon: Icons.air,
  ),
  AiModel(
    id: 'grok-2',
    provider: 'xai',
    brandId: 'xai',
    label: 'xAI · Grok 2',
    providerModel: 'grok-2-latest',
    needsKey: true,
    color: Color(0xFF111111),
    icon: Icons.bolt,
  ),
  AiModel(
    id: 'deepseek-chat',
    provider: 'deepseek',
    brandId: 'deepseek',
    label: 'DeepSeek · V3',
    providerModel: 'deepseek-chat',
    needsKey: true,
    color: Color(0xFF4D6BFE),
    icon: Icons.travel_explore,
  ),
  AiModel(
    id: 'command-r-plus',
    provider: 'cohere',
    brandId: 'cohere',
    label: 'Cohere · Command R+',
    providerModel: 'command-r-plus',
    needsKey: true,
    color: Color(0xFF39594D),
    icon: Icons.forum_outlined,
  ),
];

const String kDefaultAiModelId = 'llama-3.2';

AiModel aiModelById(String? id) => kAiModels.firstWhere(
      (m) => m.id == id,
      orElse: () => kAiModels.first,
    );

/// Per-agent model selection. The provider API key is NEVER stored in (or read
/// back from) the client-readable `ai_model_config` node — it lives write-only
/// in the worker-only `ai_model_secrets` vault. The client only ever knows
/// whether a key is configured (`hasKey`), never its value.
class AiModelConfig {
  final String modelId;

  /// Plaintext key, present only on a config the UI is about to *save*. Reads
  /// from RTDB always return this empty — the secret is worker-only.
  final String apiKey;

  /// Whether a key is already on file in the vault (drives the "•••• set"
  /// affordance without ever exposing the value).
  final bool hasKey;

  const AiModelConfig({
    this.modelId = kDefaultAiModelId,
    this.apiKey = '',
    this.hasKey = false,
  });

  AiModel get model => aiModelById(modelId);

  factory AiModelConfig.fromMap(Map? m) {
    if (m == null) return const AiModelConfig();
    return AiModelConfig(
      modelId: (m['modelId'] ?? kDefaultAiModelId).toString(),
      hasKey: m['hasKey'] == true,
    );
  }

  /// Non-secret config persisted to `ai_model_config/{agent}`. The key is
  /// deliberately excluded here.
  Map<String, dynamic> toConfigMap() => {
        'modelId': modelId,
        'hasKey': hasKey || apiKey.trim().isNotEmpty,
        'updatedAt': DateTime.now().toIso8601String(),
      };
}

/// One model's eval score: overall 0..1 plus per-dimension breakdown.
class ModelEvalScore {
  final String modelId;
  final double score;
  final Map<String, double> dims;
  const ModelEvalScore(
      {required this.modelId, required this.score, required this.dims});

  factory ModelEvalScore.fromMap(Map? m) {
    final map = m ?? const {};
    final dims = <String, double>{};
    final raw = map['dims'];
    if (raw is Map) {
      raw.forEach((k, v) {
        if (v is num) dims[k.toString()] = v.toDouble();
      });
    }
    return ModelEvalScore(
      modelId: (map['modelId'] ?? '').toString(),
      score: (map['score'] is num) ? (map['score'] as num).toDouble() : 0.0,
      dims: dims,
    );
  }
}

/// Result of a head-to-head eval: candidate vs the current champion model.
class ModelEvalResult {
  final String verdict; // better | similar | worse
  final double delta;
  final ModelEvalScore candidate;
  final ModelEvalScore champion;
  const ModelEvalResult({
    required this.verdict,
    required this.delta,
    required this.candidate,
    required this.champion,
  });

  factory ModelEvalResult.fromMap(Map m) => ModelEvalResult(
        verdict: (m['verdict'] ?? 'similar').toString(),
        delta: (m['delta'] is num) ? (m['delta'] as num).toDouble() : 0.0,
        candidate:
            ModelEvalScore.fromMap(m['candidate'] is Map ? m['candidate'] as Map : null),
        champion:
            ModelEvalScore.fromMap(m['champion'] is Map ? m['champion'] as Map : null),
      );
}

class AiModelConfigService {
  AiModelConfigService({FirebaseDatabase? db})
      : _db = db ?? FirebaseDatabase.instance;
  final FirebaseDatabase _db;

  DatabaseReference _ref(String agent) => _db.ref('ai_model_config/$agent');
  DatabaseReference _secretRef(String agent) =>
      _db.ref('ai_model_secrets/$agent');

  Stream<AiModelConfig> stream(String agent) =>
      _ref(agent).onValue.map((e) => AiModelConfig.fromMap(e.snapshot.value as Map?));

  Future<AiModelConfig> fetch(String agent) async {
    final snap = await _ref(agent).get();
    return AiModelConfig.fromMap(snap.value as Map?);
  }

  /// Persists the non-secret selection to `ai_model_config`. When a fresh key is
  /// supplied it is written *separately* to the worker-only `ai_model_secrets`
  /// vault (the client never reads it back). An empty key leaves any stored key
  /// untouched, so re-saving the same model without re-typing the key is safe.
  Future<void> save(String agent, AiModelConfig config) async {
    await _ref(agent).set(config.toConfigMap());
    final key = config.apiKey.trim();
    if (key.isNotEmpty) {
      await _secretRef(agent).set({
        'apiKey': key,
        'updatedAt': DateTime.now().toIso8601String(),
      });
    }
  }

  /// Head-to-head eval: runs the candidate model and the current champion on a
  /// set of golden tasks (worker side) and returns scores + a verdict, so a
  /// model swap can be measured before it's deployed.
  Future<ModelEvalResult> evaluate(String agent, AiModelConfig candidate) async {
    final res = await http
        .post(
          Uri.parse(AppConfig.evalModelEndpoint),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'agent': agent,
            'modelId': candidate.modelId,
            'apiKey': candidate.apiKey.trim(),
          }),
        )
        .timeout(const Duration(seconds: 45));
    if (res.statusCode != 200) {
      throw Exception('Eval failed (${res.statusCode})');
    }
    final data = jsonDecode(res.body);
    if (data is! Map) throw Exception('Unexpected eval response');
    return ModelEvalResult.fromMap(data);
  }
}
