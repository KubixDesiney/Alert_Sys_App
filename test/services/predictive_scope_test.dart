import 'package:alertsysapp/services/predictive_scope.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('predictive factory scope', () {
    test('normalizes the all sentinel to a global scope', () {
      expect(normalizePredictiveFactory(null), isNull);
      expect(normalizePredictiveFactory(''), isNull);
      expect(normalizePredictiveFactory('all'), isNull);
      expect(normalizePredictiveFactory(' All '), isNull);
    });

    test('builds the same slug and database paths as the briefing flow', () {
      expect(predictiveFactorySlug('Factory A'), 'factory_a');
      expect(predictiveFactorySlug('Factory-7'), 'factory7');
      expect(
        predictiveBriefingPath('Factory A'),
        'ai_briefing/factory/factory_a/latest',
      );
      expect(
        predictivePredictionsPath('Factory A'),
        'ai_predictions/factory/factory_a/latest',
      );
      expect(predictivePredictionsPath('all'), 'ai_predictions/latest');
    });
  });
}
