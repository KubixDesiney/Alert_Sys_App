import 'package:firebase_database/firebase_database.dart';
import '../models/hierarchy_model.dart';

class HierarchyService {
  final DatabaseReference _db = FirebaseDatabase.instance.ref();
  final int maxStations = 32;

  Stream<List<Factory>> getFactories() {
    return _db.child('hierarchy/factories').onValue.map((event) {
      final data = event.snapshot.value;
      if (data == null) return [];
      if (data is! Map) return [];
final map = Map<Object?, Object?>.from(data as Map);
final factories = <Factory>[];
for (var entry in map.entries) {
  try {
    if (entry.value is Map<Object?, Object?>) {
      factories.add(Factory.fromMap(entry.key.toString(), entry.value as Map<Object?, Object?>));
    }
  } catch (e) {
    print('Error parsing factory ${entry.key}: $e');
  }
}
      return factories;
    });
  }
  /// Checks if the given factory name, conveyor number, and station number exist in the hierarchy.
Future<bool> validateLocation(String factoryName, int conveyorNumber, int stationNumber) async {
  final factories = await getFactories().first;
  final factory = factories.cast<Factory?>().firstWhere(
    (f) => f?.name == factoryName,
    orElse: () => null,
  );
  if (factory == null) return false;
  final conveyor = factory.conveyors.values.cast<Conveyor?>().firstWhere(
    (c) => c?.number == conveyorNumber,
    orElse: () => null,
  );
  if (conveyor == null) return false;
  final station = conveyor.stations.values.cast<Station?>().firstWhere(
    (s) => s?.id == 'station_$stationNumber',
    orElse: () => null,
  );
  return station != null;
}

  Future<void> addFactoryWithConveyors(String id, String name, String location, int numConveyors) async {
    final factoryRef = _db.child('hierarchy/factories/$id');
    final existing = await factoryRef.get();
    if (existing.exists) {
      throw Exception('Factory with ID "$id" already exists');
    }

    final conveyorsMap = <String, Map<String, dynamic>>{};
    for (int i = 1; i <= numConveyors; i++) {
      final conveyorId = "conveyor_$i";
      conveyorsMap[conveyorId] = {
        'number': i,
        'stations': {}, // empty map, not list
      };
    }

    final factoryMap = {
      'name': name,
      'location': location,
      'conveyors': conveyorsMap,
    };
    await factoryRef.set(factoryMap);
  }

  Future<void> addConveyor(String factoryId, int conveyorNumber) async {
    final conveyorId = "conveyor_$conveyorNumber";
    final conveyorRef = _db.child('hierarchy/factories/$factoryId/conveyors/$conveyorId');
    final existing = await conveyorRef.get();
    if (existing.exists) {
      throw Exception('Conveyor $conveyorNumber already exists in this factory');
    }
    final conveyorMap = {
      'number': conveyorNumber,
      'stations': {},
    };
    await conveyorRef.set(conveyorMap);
  }

  Future<void> updateConveyorNumber(String factoryId, String conveyorId, int newNumber) async {
    await _db.child('hierarchy/factories/$factoryId/conveyors/$conveyorId/number').set(newNumber);
  }

  Future<void> addStation(String factoryId, String conveyorId, int stationNumber) async {
    // Use string key to prevent Firebase array conversion
    final stationId = "station_$stationNumber";
    final stationRef = _db.child('hierarchy/factories/$factoryId/conveyors/$conveyorId/stations/$stationId');
    final existing = await stationRef.get();
    if (existing.exists) {
      throw Exception('Station $stationNumber already exists');
    }
    final stationMap = {
      'name': 'Station $stationNumber',
      'address': '${factoryId.replaceAll(' ', '_')}_C${conveyorId.replaceAll('conveyor_', '')}_P$stationNumber',
    };
    await stationRef.set(stationMap);
  }

  Future<void> deleteFactory(String factoryId) async {
    await _db.child('hierarchy/factories/$factoryId').remove();
  }

  Future<void> deleteConveyor(String factoryId, String conveyorId) async {
    await _db.child('hierarchy/factories/$factoryId/conveyors/$conveyorId').remove();
  }
}