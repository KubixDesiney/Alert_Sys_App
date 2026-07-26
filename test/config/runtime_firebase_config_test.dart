// Pure-VM tests for the per-tenant runtime config layer (Prompt 1). The web
// implementation that reads window.__SIAS_CONFIG__ is browser-only; here we
// test the pure parser + the AppConfig runtime-override layer that main.dart
// wires up from it.
import 'package:alertsysapp/config/app_config.dart';
import 'package:alertsysapp/config/runtime_firebase_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('firebaseOptionsFromMap', () {
    test('builds options when the required identity fields are present', () {
      final o = firebaseOptionsFromMap({
        'apiKey': 'k',
        'appId': 'a',
        'messagingSenderId': 'm',
        'projectId': 'sias-nagati',
        'authDomain': 'sias-nagati.firebaseapp.com',
        'storageBucket': 'sias-nagati.appspot.com',
        'databaseURL': 'https://sias-nagati-default-rtdb.firebaseio.com',
      });
      expect(o, isNotNull);
      expect(o!.projectId, 'sias-nagati');
      expect(o.databaseURL, 'https://sias-nagati-default-rtdb.firebaseio.com');
    });

    test('returns null when a required field is missing or blank', () {
      expect(firebaseOptionsFromMap(null), isNull);
      expect(firebaseOptionsFromMap({'apiKey': 'k'}), isNull);
      expect(
        firebaseOptionsFromMap(
            {'apiKey': '', 'appId': 'a', 'messagingSenderId': 'm', 'projectId': 'p'}),
        isNull,
      );
    });
  });

  group('parseRuntimeSiasConfig', () {
    test('parses tenant, company, firebase options and worker overrides', () {
      final c = parseRuntimeSiasConfig(<Object?, Object?>{
        'tenant': 'nagati',
        'tenantCode': 'NSW#7K2F',
        'company': 'Nagati Steel Works',
        'firebase': <Object?, Object?>{
          'apiKey': 'k',
          'appId': 'a',
          'messagingSenderId': 'm',
          'projectId': 'sias-nagati',
        },
        'workers': <Object?, Object?>{
          'ai': 'https://ai',
          'notify': 'https://notify',
          'ingest': 'https://ingest',
          'copilotUrl': 'https://copilot',
        },
      });
      expect(c, isNotNull);
      expect(c!.tenant, 'nagati');
      expect(c.tenantCode, 'NSW#7K2F');
      expect(c.company, 'Nagati Steel Works');
      expect(c.hasFirebase, isTrue);
      expect(c.firebaseOptions!.projectId, 'sias-nagati');
      expect(c.aiWorkerBase, 'https://ai');
      expect(c.notifyWorkerBase, 'https://notify');
      expect(c.ingestWorkerBase, 'https://ingest');
      expect(c.copilotUrl, 'https://copilot');
      expect(c.hasWorkerOverrides, isTrue);
    });

    test('tolerates a config with no firebase / no workers sections', () {
      final c = parseRuntimeSiasConfig(<Object?, Object?>{'tenant': 'x'});
      expect(c, isNotNull);
      expect(c!.firebaseOptions, isNull);
      expect(c.hasFirebase, isFalse);
      expect(c.hasWorkerOverrides, isFalse);
    });
  });

  group('AppConfig runtime worker overrides', () {
    tearDown(AppConfig.debugResetRuntimeOverrides);

    test('override repoints the resolved base + derived endpoints', () {
      AppConfig.applyRuntimeWorkerOverrides(
        aiWorkerBase: 'https://tenant-ai',
        notifyWorkerBase: 'https://tenant-notify',
        ingestWorkerBase: 'https://tenant-ingest',
        copilotUrl: 'https://tenant-copilot',
      );
      expect(AppConfig.resolvedAiWorkerBase, 'https://tenant-ai');
      expect(AppConfig.configEndpoint, 'https://tenant-ai/config');
      expect(AppConfig.notifyEndpoint, 'https://tenant-notify/notify');
      expect(AppConfig.connectorVerifyEndpoint, 'https://tenant-ingest/verify');
      expect(AppConfig.resolvedCopilotUrl, 'https://tenant-copilot');
    });

    test('null/empty values are a no-op (a good compile-time default is kept)', () {
      final defaultAi = AppConfig.resolvedAiWorkerBase;
      AppConfig.applyRuntimeWorkerOverrides(aiWorkerBase: '');
      expect(AppConfig.resolvedAiWorkerBase, defaultAi);
      AppConfig.applyRuntimeWorkerOverrides(aiWorkerBase: null);
      expect(AppConfig.resolvedAiWorkerBase, defaultAi);
    });

    test('with no override, resolved falls back to the compile-time const', () {
      expect(AppConfig.resolvedAiWorkerBase, AppConfig.aiWorkerBase);
      expect(AppConfig.resolvedCopilotUrl, AppConfig.copilotUrl);
    });
  });
}
