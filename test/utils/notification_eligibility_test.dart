import 'package:alertsysapp/utils/notification_eligibility.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('sanitizeFactoryId', () {
    test('mirrors the worker aiSanitizeFactoryId behaviour', () {
      expect(sanitizeFactoryId('Usine A'), 'usine_a');
      expect(sanitizeFactoryId('  North--Plant 7 '), 'north_plant_7');
      expect(sanitizeFactoryId('usine_a'), 'usine_a');
      expect(sanitizeFactoryId(''), '');
      expect(sanitizeFactoryId(null), '');
    });
  });

  group('factoryCandidates', () {
    test('expands every factory-identifying field', () {
      expect(
        factoryCandidates({'factoryId': 'plant-7', 'usine': 'North Plant'}),
        {'plant_7', 'north_plant'},
      );
      expect(factoryCandidates('Usine A'), {'usine_a'});
      expect(factoryCandidates(null), isEmpty);
      expect(factoryCandidates({'other': 'x'}), isEmpty);
    });
  });

  group('factoryMatches', () {
    test('matches on any intersection across identifier styles', () {
      expect(
        factoryMatches(
          factoryCandidates({'usine': 'Usine A'}),
          factoryCandidates({'factoryId': 'usine_a'}),
        ),
        isTrue,
      );
      expect(
        factoryMatches(
          factoryCandidates({'usine': 'Usine A'}),
          factoryCandidates({'usine': 'Usine B'}),
        ),
        isFalse,
      );
    });

    test('empty target passes, empty user blocks', () {
      expect(factoryMatches(<String>{}, {'usine_a'}), isTrue);
      expect(factoryMatches({'usine_a'}, <String>{}), isFalse);
    });
  });

  group('busySupervisorIds', () {
    final enCours = <Object?, Object?>{
      'a1': {'status': 'en_cours', 'superviseurId': 'owner1'},
      'a2': {
        'status': 'en_cours',
        'superviseurId': 'owner2',
        'assistantId': 'helper1',
      },
    };

    test('owners and assistants of en_cours alerts are busy', () {
      final busy = busySupervisorIds(enCoursAlerts: enCours, activeClaims: {});
      expect(busy, containsAll(['owner1', 'owner2', 'helper1']));
    });

    test('claims pointing at en_cours alerts are busy; stale claims are not', () {
      final busy = busySupervisorIds(
        enCoursAlerts: enCours,
        activeClaims: <Object?, Object?>{
          'claimer': {'alertId': 'a1'},
          'staleClaimer': {'alertId': 'resolved-long-ago'},
        },
      );
      expect(busy, contains('claimer'));
      expect(busy, isNot(contains('staleClaimer')));
    });

    test('empty inputs produce no busy supervisors', () {
      expect(
        busySupervisorIds(enCoursAlerts: {}, activeClaims: {}),
        isEmpty,
      );
    });
  });

  group('isEligibleNewAlertRecipient', () {
    final target = factoryCandidates({'usine': 'Usine A'});

    test('free same-factory supervisor with a token is eligible', () {
      expect(
        isEligibleNewAlertRecipient(
          uid: 'sup1',
          user: {'role': 'supervisor', 'usine': 'Usine A', 'fcmToken': 't'},
          targetFactories: target,
          busyIds: const {},
        ),
        isTrue,
      );
    });

    test('busy supervisors, wrong factory, missing token, and admins are not', () {
      expect(
        isEligibleNewAlertRecipient(
          uid: 'busy',
          user: {'role': 'supervisor', 'usine': 'Usine A', 'fcmToken': 't'},
          targetFactories: target,
          busyIds: const {'busy'},
        ),
        isFalse,
      );
      expect(
        isEligibleNewAlertRecipient(
          uid: 'far',
          user: {'role': 'supervisor', 'usine': 'Usine B', 'fcmToken': 't'},
          targetFactories: target,
          busyIds: const {},
        ),
        isFalse,
      );
      expect(
        isEligibleNewAlertRecipient(
          uid: 'noToken',
          user: {'role': 'supervisor', 'usine': 'Usine A', 'fcmToken': ' '},
          targetFactories: target,
          busyIds: const {},
        ),
        isFalse,
      );
      expect(
        isEligibleNewAlertRecipient(
          uid: 'pm',
          user: {'role': 'admin', 'usine': 'Usine A', 'fcmToken': 't'},
          targetFactories: target,
          busyIds: const {},
        ),
        isFalse,
      );
    });

    test('factoryId-keyed user matches usine-keyed alert', () {
      expect(
        isEligibleNewAlertRecipient(
          uid: 'idKeyed',
          user: {'role': 'supervisor', 'factoryId': 'usine_a', 'fcmToken': 't'},
          targetFactories: target,
          busyIds: const {},
        ),
        isTrue,
      );
    });
  });
}
