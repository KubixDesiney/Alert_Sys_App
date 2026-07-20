import 'package:alertsysapp/utils/alert_claim_error.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatAlertClaimError', () {
    test('recognizes "already have an alert in progress"', () {
      expect(
        formatAlertClaimError(Exception('You already have an alert in progress')),
        'You already have a claimed alert. Resolve it before claiming another one.',
      );
    });

    test('recognizes "already have a claimed alert"', () {
      expect(
        formatAlertClaimError(Exception('already have a claimed alert')),
        'You already have a claimed alert. Resolve it before claiming another one.',
      );
    });

    test('recognizes "already claimed by someone else"', () {
      expect(
        formatAlertClaimError(Exception('already claimed by someone else')),
        'This alert was claimed by someone else before you could claim it.',
      );
    });

    test('recognizes "this alert was already claimed"', () {
      expect(
        formatAlertClaimError(Exception('This alert was already claimed')),
        'This alert was claimed by someone else before you could claim it.',
      );
    });

    test('matching is case-insensitive', () {
      expect(
        formatAlertClaimError(Exception('ALREADY CLAIMED BY SOMEONE ELSE')),
        'This alert was claimed by someone else before you could claim it.',
      );
    });

    test('falls back to a generic claim-failed message with the raw error text', () {
      final err = Exception('network timeout');
      expect(formatAlertClaimError(err), 'Claim failed: ${err.toString()}');
    });

    test('handles a plain string error, not just Exception objects', () {
      expect(formatAlertClaimError('random failure'), 'Claim failed: random failure');
    });
  });
}
