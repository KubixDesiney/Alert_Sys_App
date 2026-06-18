import 'package:alertsysapp/screens/superadmin/hardware/hw_machines.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HwMachine.fromAssetMap', () {
    test('parses assets with ISO updatedAt timestamps', () {
      final machine = HwMachine.fromAssetMap('MACH-001', {
        'name': 'Station 1',
        'factoryId': 'factory_a',
        'factoryName': 'Usine A',
        'conveyorId': 'conveyor_1',
        'conveyorNumber': 1,
        'updatedAt': '2026-06-18T12:00:00.000Z',
      });

      expect(machine.id, 'MACH-001');
      expect(machine.name, 'Station 1');
      expect(
        machine.updatedAtMs,
        DateTime.parse('2026-06-18T12:00:00.000Z').millisecondsSinceEpoch,
      );
    });

    test('accepts legacy asset field aliases', () {
      final machine = HwMachine.fromAssetMap('push-key', {
        'assetId': 'MACH-007',
        'usine': 'Usine A',
        'convoyeur': 2,
        'status': 'inactive',
      });

      expect(machine.id, 'MACH-007');
      expect(machine.factoryId, 'Usine A');
      expect(machine.factoryName, 'Usine A');
      expect(machine.conveyorId, 'conveyor_2');
      expect(machine.conveyorNumber, 2);
      expect(machine.status, HwMachineStatus.outOfService);
    });
  });

  group('HwFactoryCatalog matching', () {
    test('matches machine factory and conveyor by aliases', () {
      final catalog = HwFactoryCatalog(
        factories: const [HwFactoryRef(id: 'factory_a', name: 'Usine A')],
        conveyorsByFactory: {
          'factory_a': [
            HwConveyorRef(id: 'conveyor_2', number: 2, factoryId: 'factory_a'),
          ],
        },
      );
      final machine = HwMachine(
        id: 'MACH-007',
        factoryId: 'Usine A',
        conveyorId: '2',
      );

      expect(catalog.machineMatchesFactory(machine, 'factory_a'), isTrue);
      expect(
        catalog.machineMatchesConveyor(machine, 'factory_a', 'conveyor_2'),
        isTrue,
      );
    });
  });
}
