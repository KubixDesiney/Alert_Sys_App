import 'package:flutter_test/flutter_test.dart';
import 'package:alertsysapp/services/ai_model_config_service.dart';

void main() {
  group('kAiModels catalog', () {
    test('Llama is the default, built-in, no-key model', () {
      final llama = kAiModels.firstWhere((m) => m.id == kDefaultAiModelId);
      expect(llama.needsKey, isFalse);
      expect(llama.provider, 'cloudflare');
      expect(kAiModels.first.id, kDefaultAiModelId); // shown first in the grid
    });

    test('every non-default model requires an API key', () {
      for (final m in kAiModels.where((m) => m.id != kDefaultAiModelId)) {
        expect(m.needsKey, isTrue, reason: '${m.id} should need a key');
      }
    });

    test('ids are unique and non-empty', () {
      final ids = kAiModels.map((m) => m.id).toList();
      expect(ids.toSet().length, ids.length);
      expect(ids.every((id) => id.isNotEmpty), isTrue);
    });

    test('every model has a brandId for its real provider logo', () {
      for (final m in kAiModels) {
        expect(m.brandId.isNotEmpty, isTrue, reason: '${m.id} missing brandId');
      }
      // Llama shows the Meta mark; ChatGPT the OpenAI mark; etc.
      expect(aiModelById('llama-3.2').brandId, 'meta');
      expect(aiModelById('gpt-4o').brandId, 'openai');
      expect(aiModelById('claude-opus').brandId, 'anthropic');
      expect(aiModelById('gemini-pro').brandId, 'gemini');
    });

    test('covers the major providers', () {
      final providers = kAiModels.map((m) => m.provider).toSet();
      expect(
        providers,
        containsAll(<String>[
          'cloudflare',
          'openai',
          'anthropic',
          'google',
          'mistral',
          'xai',
          'deepseek',
          'cohere',
        ]),
      );
    });
  });

  group('aiModelById', () {
    test('returns the matching model', () {
      expect(aiModelById('gpt-4o').provider, 'openai');
      expect(aiModelById('claude-sonnet').apiModel, 'claude-sonnet-4-6');
    });

    test('falls back to the default (Llama) for unknown or null ids', () {
      expect(aiModelById('nope').id, kDefaultAiModelId);
      expect(aiModelById(null).id, kDefaultAiModelId);
    });
  });

  group('AiModelConfig', () {
    test('defaults to Llama with no key', () {
      const c = AiModelConfig();
      expect(c.modelId, kDefaultAiModelId);
      expect(c.apiKey, '');
      expect(c.model.needsKey, isFalse);
    });

    test('fromMap reads modelId + apiKey', () {
      final c =
          AiModelConfig.fromMap({'modelId': 'claude-opus', 'apiKey': 'sk-x'});
      expect(c.modelId, 'claude-opus');
      expect(c.apiKey, 'sk-x');
      expect(c.model.provider, 'anthropic');
    });

    test('fromMap null -> default', () {
      final c = AiModelConfig.fromMap(null);
      expect(c.modelId, kDefaultAiModelId);
      expect(c.apiKey, '');
    });

    test('toMap trims the key and stamps updatedAt', () {
      final m =
          const AiModelConfig(modelId: 'gpt-4o', apiKey: '  sk-y  ').toMap();
      expect(m['modelId'], 'gpt-4o');
      expect(m['apiKey'], 'sk-y');
      expect(m['updatedAt'], isA<String>());
    });
  });
}
