import 'package:flutter_test/flutter_test.dart';
import 'package:alertsysapp/services/telemetry_service.dart';

void main() {
  group('TelemetryService.crashFreeRate', () {
    test('is 1.0 when there are no sessions', () {
      expect(TelemetryService.crashFreeRate(sessions: 0, errorSessions: 0), 1.0);
    });
    test('computes the crash-free fraction', () {
      expect(
        TelemetryService.crashFreeRate(sessions: 100, errorSessions: 5),
        0.95,
      );
    });
    test('clamps when errorSessions exceeds sessions', () {
      expect(
        TelemetryService.crashFreeRate(sessions: 10, errorSessions: 20),
        0.0,
      );
    });
  });

  group('TelemetryService.errorRate', () {
    test('is 0 with no sessions', () {
      expect(TelemetryService.errorRate(sessions: 0, errors: 5), 0.0);
    });
    test('is errors per session', () {
      expect(TelemetryService.errorRate(sessions: 50, errors: 100), 2.0);
    });
  });

  group('TelemetryService.todayKey', () {
    test('is an ISO yyyy-MM-dd date', () {
      expect(TelemetryService.todayKey(), matches(r'^\d{4}-\d{2}-\d{2}$'));
    });
  });
}
