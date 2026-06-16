import 'package:flutter_test/flutter_test.dart';
import 'package:alertsysapp/services/infra_config_service.dart';

void main() {
  group('InfraConfig.workers', () {
    test('lists the five workers with our exact names', () {
      final w = const InfraConfig(workersSubdomain: 'acme-co').workers();
      expect(w.length, 5);
      expect(w.map((e) => e.name).toList(), [
        'alert-notifier',
        'alertsys',
        'alertsys-backup',
        'alertsys-monitor',
        'alertsys-scim',
      ]);
    });
    test('derives worker URLs from the subdomain', () {
      final w = const InfraConfig(workersSubdomain: 'acme-co').workers();
      expect(w.first.url, 'https://alert-notifier.acme-co.workers.dev');
      expect(w.last.url, 'https://alertsys-scim.acme-co.workers.dev');
    });
    test('uses a placeholder when subdomain is blank', () {
      final w = const InfraConfig().workers();
      expect(w.first.url, contains('<subdomain>'));
    });
  });

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
        'r2Bucket': 'acme-backups',
        'deployWebhookUrl': 'https://api.github.com/repos/a/b/dispatches',
      });
      expect(c.firebaseProjectId, 'acme-alerts');
      expect(c.workersSubdomain, 'acme-co');
      expect(c.r2Bucket, 'acme-backups');
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
