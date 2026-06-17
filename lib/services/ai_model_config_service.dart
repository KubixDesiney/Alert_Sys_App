import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

/// One selectable LLM for the AI Assist / Briefing agents.
class AiModel {
  final String id; // stable key stored in ai_model_config
  final String provider; // cloudflare | openai | anthropic | google | mistral | xai | deepseek | cohere
  final String brandId; // brand-mark id for the real provider logo (meta/openai/anthropic/gemini/…)
  final String label; // shown in the picker
  final String apiModel; // the exact model string the provider API expects
  final bool needsKey; // false only for the built-in Cloudflare Workers AI Llama
  final Color color;
  final IconData icon; // fallback glyph

  const AiModel({
    required this.id,
    required this.provider,
    required this.brandId,
    required this.label,
    required this.apiModel,
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
    apiModel: '@cf/meta/llama-3.2-3b-instruct',
    needsKey: false,
    color: Color(0xFFF38020),
    icon: Icons.bolt_rounded,
  ),
  AiModel(
    id: 'gpt-4o',
    provider: 'openai',
    brandId: 'openai',
    label: 'OpenAI · GPT-4o',
    apiModel: 'gpt-4o',
    needsKey: true,
    color: Color(0xFF10A37F),
    icon: Icons.auto_awesome,
  ),
  AiModel(
    id: 'gpt-4o-mini',
    provider: 'openai',
    brandId: 'openai',
    label: 'OpenAI · GPT-4o mini',
    apiModel: 'gpt-4o-mini',
    needsKey: true,
    color: Color(0xFF10A37F),
    icon: Icons.auto_awesome_outlined,
  ),
  AiModel(
    id: 'claude-sonnet',
    provider: 'anthropic',
    brandId: 'anthropic',
    label: 'Anthropic · Claude Sonnet',
    apiModel: 'claude-sonnet-4-6',
    needsKey: true,
    color: Color(0xFFD97757),
    icon: Icons.psychology_alt,
  ),
  AiModel(
    id: 'claude-opus',
    provider: 'anthropic',
    brandId: 'anthropic',
    label: 'Anthropic · Claude Opus',
    apiModel: 'claude-opus-4-8',
    needsKey: true,
    color: Color(0xFFD97757),
    icon: Icons.psychology,
  ),
  AiModel(
    id: 'claude-haiku',
    provider: 'anthropic',
    brandId: 'anthropic',
    label: 'Anthropic · Claude Haiku',
    apiModel: 'claude-haiku-4-5-20251001',
    needsKey: true,
    color: Color(0xFFD97757),
    icon: Icons.psychology_outlined,
  ),
  AiModel(
    id: 'gemini-flash',
    provider: 'google',
    brandId: 'gemini',
    label: 'Google · Gemini 1.5 Flash',
    apiModel: 'gemini-1.5-flash',
    needsKey: true,
    color: Color(0xFF4285F4),
    icon: Icons.diamond_outlined,
  ),
  AiModel(
    id: 'gemini-pro',
    provider: 'google',
    brandId: 'gemini',
    label: 'Google · Gemini 1.5 Pro',
    apiModel: 'gemini-1.5-pro',
    needsKey: true,
    color: Color(0xFF4285F4),
    icon: Icons.diamond,
  ),
  AiModel(
    id: 'mistral-large',
    provider: 'mistral',
    brandId: 'mistral',
    label: 'Mistral · Large',
    apiModel: 'mistral-large-latest',
    needsKey: true,
    color: Color(0xFFFA520F),
    icon: Icons.air,
  ),
  AiModel(
    id: 'grok-2',
    provider: 'xai',
    brandId: 'xai',
    label: 'xAI · Grok 2',
    apiModel: 'grok-2-latest',
    needsKey: true,
    color: Color(0xFF111111),
    icon: Icons.bolt,
  ),
  AiModel(
    id: 'deepseek-chat',
    provider: 'deepseek',
    brandId: 'deepseek',
    label: 'DeepSeek · V3',
    apiModel: 'deepseek-chat',
    needsKey: true,
    color: Color(0xFF4D6BFE),
    icon: Icons.travel_explore,
  ),
  AiModel(
    id: 'command-r-plus',
    provider: 'cohere',
    brandId: 'cohere',
    label: 'Cohere · Command R+',
    apiModel: 'command-r-plus',
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

/// Per-agent model selection. The key is stored alongside (superadmin-only
/// node); empty for the built-in Llama.
class AiModelConfig {
  final String modelId;
  final String apiKey;

  const AiModelConfig({this.modelId = kDefaultAiModelId, this.apiKey = ''});

  AiModel get model => aiModelById(modelId);

  factory AiModelConfig.fromMap(Map? m) {
    if (m == null) return const AiModelConfig();
    return AiModelConfig(
      modelId: (m['modelId'] ?? kDefaultAiModelId).toString(),
      apiKey: (m['apiKey'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() => {
        'modelId': modelId,
        'apiKey': apiKey.trim(),
        'updatedAt': DateTime.now().toIso8601String(),
      };
}

class AiModelConfigService {
  AiModelConfigService({FirebaseDatabase? db})
      : _db = db ?? FirebaseDatabase.instance;
  final FirebaseDatabase _db;

  DatabaseReference _ref(String agent) => _db.ref('ai_model_config/$agent');

  Stream<AiModelConfig> stream(String agent) =>
      _ref(agent).onValue.map((e) => AiModelConfig.fromMap(e.snapshot.value as Map?));

  Future<AiModelConfig> fetch(String agent) async {
    final snap = await _ref(agent).get();
    return AiModelConfig.fromMap(snap.value as Map?);
  }

  Future<void> save(String agent, AiModelConfig config) =>
      _ref(agent).set(config.toMap());
}
