import 'package:alertsysapp/models/shift_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ShiftModel.crossFactoryMaxDistanceKm', () {
    ShiftModel build({double? distance}) => ShiftModel(
          id: 's1',
          name: 'Morning',
          startMinutes: 360,
          endMinutes: 840,
          supervisors: const [],
          maxSupervisors: 3,
          aiCommander: true,
          aiModel: 'llama-3.2-3b',
          aiConfidence: 0.65,
          handleAssignments: true,
          handleCollaborations: false,
          handleCrossFactoryTransfer: true,
          fullControl: false,
          randomize: false,
          crossFactoryMaxDistanceKm: distance,
          createdAt: DateTime.parse('2026-05-17T00:00:00Z'),
        );

    test('round-trips a positive value through toMap/fromMap', () {
      final encoded = build(distance: 75).toMap();
      expect(encoded['crossFactoryMaxDistanceKm'], 75);
      final decoded = ShiftModel.fromMap('s1', encoded);
      expect(decoded.crossFactoryMaxDistanceKm, 75);
    });

    test('omits zero or null from toMap so worker treats as unlimited', () {
      expect(build(distance: null).toMap().containsKey('crossFactoryMaxDistanceKm'),
          isFalse);
      expect(build(distance: 0).toMap().containsKey('crossFactoryMaxDistanceKm'),
          isFalse);
    });

    test('fromMap accepts numeric strings and ignores empty strings', () {
      final fromString = ShiftModel.fromMap('s1', {
        'name': 'X',
        'startMinutes': 0,
        'endMinutes': 60,
        'crossFactoryMaxDistanceKm': '120.5',
      });
      expect(fromString.crossFactoryMaxDistanceKm, 120.5);

      final fromEmpty = ShiftModel.fromMap('s1', {
        'name': 'X',
        'startMinutes': 0,
        'endMinutes': 60,
        'crossFactoryMaxDistanceKm': '',
      });
      expect(fromEmpty.crossFactoryMaxDistanceKm, isNull);
    });

    test('copyWith can clear the threshold', () {
      final s = build(distance: 50);
      final cleared = s.copyWith(clearCrossFactoryMaxDistanceKm: true);
      expect(cleared.crossFactoryMaxDistanceKm, isNull);
    });
  });
}
