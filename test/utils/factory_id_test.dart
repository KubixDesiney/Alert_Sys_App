import 'package:alertsysapp/utils/factory_id.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('sanitizeFactoryId', () {
    test('lowercases input', () {
      expect(sanitizeFactoryId('USINE A'), 'usine_a');
    });

    test('replaces non-alphanumeric runs with underscore', () {
      expect(sanitizeFactoryId('Usine-A.North/2'), 'usine_a_north_2');
    });

    test('trims leading and trailing underscores', () {
      expect(sanitizeFactoryId('---factory---'), 'factory');
    });

    test('returns empty string for non-alpha input', () {
      expect(sanitizeFactoryId('!!!'), '');
    });

    test('preserves digits', () {
      expect(sanitizeFactoryId('Plant 42'), 'plant_42');
    });

    test('matches the worker regex semantics', () {
      // Matches the JS regex pattern in cloudflare_worker.js aiSanitizeFactoryId
      expect(sanitizeFactoryId('  Usine A  '), 'usine_a');
      expect(sanitizeFactoryId('a__b'), 'a_b');
    });
  });
}
