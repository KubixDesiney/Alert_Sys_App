import 'package:alertsysapp/utils/user_friendly_error.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UserFriendlyError.message', () {
    test('timeout errors get a retry message', () {
      expect(
        UserFriendlyError.message(Exception('Connection timeout after 8s')),
        'The request took too long. Please try again.',
      );
    });

    test('network/socket/connection errors get a connectivity message', () {
      expect(
        UserFriendlyError.message(Exception('Network unreachable')),
        'Network connection issue. Please check your internet and try again.',
      );
      expect(
        UserFriendlyError.message(Exception('SocketException: failed')),
        'Network connection issue. Please check your internet and try again.',
      );
      expect(
        UserFriendlyError.message(Exception('Connection refused')),
        'Network connection issue. Please check your internet and try again.',
      );
    });

    test('permission/denied/unauthorized errors get a permission message', () {
      expect(
        UserFriendlyError.message(Exception('Permission denied')),
        'You do not have permission to complete this action.',
      );
      expect(
        UserFriendlyError.message(Exception('unauthorized request')),
        'You do not have permission to complete this action.',
      );
    });

    test('"not found" errors get a not-found message', () {
      expect(
        UserFriendlyError.message(Exception('Document not found')),
        'The requested data could not be found.',
      );
    });

    test('"invalid" errors get a validation message', () {
      expect(
        UserFriendlyError.message(Exception('invalid argument')),
        'Some information is invalid. Please review it and try again.',
      );
    });

    test('firebase errors get a generic server-error message', () {
      expect(
        UserFriendlyError.message(Exception('[firebase_database/permission-denied-elsewhere] weird')),
        // "permission" matches before "firebase" due to branch order
        'You do not have permission to complete this action.',
      );
      expect(
        UserFriendlyError.message(Exception('FirebaseException: internal error')),
        'A server error occurred. Please try again in a moment.',
      );
    });

    test('unrecognized errors fall back to a generic message', () {
      expect(
        UserFriendlyError.message(Exception('some bizarre failure mode')),
        'Something went wrong. Please try again.',
      );
    });

    test('matching is case-insensitive', () {
      expect(
        UserFriendlyError.message(Exception('TIMEOUT')),
        'The request took too long. Please try again.',
      );
    });
  });
}
