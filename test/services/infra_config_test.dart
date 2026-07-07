import 'package:flutter_test/flutter_test.dart';
import 'package:alertsysapp/services/infra_config_service.dart';

void main() {
  group('InfraConfig.scimBaseUrl', () {
    test('builds the SCIM v2 base from the subdomain', () {
      expect(
        const InfraConfig(workersSubdomain: 'acme-co').scimBaseUrl,
        'https://alertsys-scim.acme-co.workers.dev/scim/v2',
      );
    });
    test('is empty without a subdomain', () {
      expect(const InfraConfig().scimBaseUrl, '');
    });
  });

  group('InfraConfig.fromMap / toMap', () {
    test('null map yields empty config', () {
      expect(InfraConfig.fromMap(null).firebaseProjectId, '');
    });
    test('round-trips non-secret config', () {
      final c = InfraConfig.fromMap({
        'firebaseProjectId': 'acme-alerts',
        'firebaseDbUrl': 'https://acme-alerts-default-rtdb.firebaseio.com',
        'workersSubdomain': 'acme-co',
      });
      expect(c.firebaseProjectId, 'acme-alerts');
      expect(c.workersSubdomain, 'acme-co');
    });
    test('toMap trims values and stamps updatedAt', () {
      final m = const InfraConfig(
        firebaseProjectId: '  acme-alerts  ',
        workersSubdomain: 'acme-co',
      ).toMap();
      expect(m['firebaseProjectId'], 'acme-alerts');
      expect(m['workersSubdomain'], 'acme-co');
      expect(m.containsKey('updatedAt'), isTrue);
    });
    test('toMap never carries secret fields', () {
      final m = const InfraConfig(firebaseProjectId: 'p').toMap();
      for (final k in const [
        'FIREBASE_SERVICE_ACCOUNT',
        'CLOUDFLARE_API_TOKEN',
        'SCIM_TOKEN',
        'WORKER_SHARED_SECRET',
      ]) {
        expect(m.containsKey(k), isFalse);
      }
    });
  });

  group('InfraConfig.copyWith', () {
    test('overrides only the given field', () {
      final c = const InfraConfig().copyWith(firebaseProjectId: 'x');
      expect(c.firebaseProjectId, 'x');
      expect(c.workersSubdomain, '');
    });
  });
}
