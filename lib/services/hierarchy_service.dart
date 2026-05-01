import 'package:firebase_database/firebase_database.dart';
import '../models/hierarchy_model.dart';

class HierarchyService {
  final DatabaseReference _db = FirebaseDatabase.instance.ref();
  final int maxStations = 32;

  String _formatAssetId(int value) =>
      'MACH-${value.toString().padLeft(3, '0')}';

  String normalizeAssetId(String value) =>
      value.trim().replaceAll(' ', '').toUpperCase();

  Stream<List<Factory>> getFactories() {
    return _db.child('hierarchy/factories').onValue.map((event) {
      final data = event.snapshot.value;
      if (data == null) return [];
      if (data is! Map) return [];
      final map = Map<Object?, Object?>.from(data);
      final factories = <Factory>[];
      for (var entry in map.entries) {
        try {
          if (entry.value is Map<Object?, Object?>) {
            factories.add(Factory.fromMap(
                entry.key.toString(), entry.value as Map<Object?, Object?>));
          }
        } catch (e) {
          print('Error parsing factory ${entry.key}: $e');
        }
      }
      return factories;
    });
  }

  /// Checks if the given factory name, conveyor number, and station number exist in the hierarchy.
  Future<bool> validateLocation(
      String factoryName, int conveyorNumber, int stationNumber) async {
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

  Future<String> nextAssetId() async {
    final result = await _db.child('assetCounter').runTransaction((current) {
      final currentVal = (current as num?)?.toInt() ?? 0;
      return Transaction.success(currentVal + 1);
    });
    final committed = (result.snapshot.value as num?)?.toInt() ?? 1;
    return _formatAssetId(committed);
  }

  Future<void> _reserveAssetCounterFloor(String assetId) async {
    final match = RegExp(r'^MACH-(\d+)$').firstMatch(assetId);
    if (match == null) return;
    final numeric = int.tryParse(match.group(1)!);
    if (numeric == null) return;
    await _db.child('assetCounter').runTransaction((current) {
      final currentVal = (current as num?)?.toInt() ?? 0;
      return Transaction.success(currentVal < numeric ? numeric : currentVal);
    });
  }

  Future<String> ensureStationAssetId(
      String factoryId, String conveyorId, String stationId) async {
    final assetRef = _db.child(
        'hierarchy/factories/$factoryId/conveyors/$conveyorId/stations/$stationId/assetId');
    final existing = await assetRef.get();
    final current = existing.value?.toString().trim();
    if (current != null && current.isNotEmpty) {
      return current;
    }
    final assetId = await nextAssetId();
    await assetRef.set(assetId);
    return assetId;
  }

  Future<void> assignAssetIdToStation({
    required String factoryId,
    required String conveyorId,
    required String stationId,
    required String assetId,
  }) async {
    final normalized = normalizeAssetId(assetId);
    if (normalized.isEmpty) {
      throw Exception('Asset ID is required');
    }
    if (!RegExp(r'^[A-Z0-9_-]+$').hasMatch(normalized)) {
      throw Exception('Asset ID can only contain letters, numbers, _ and -');
    }

    final snapshot = await _db.child('hierarchy/factories').get();
    final updates = <String, Object?>{};
    final targetPath =
        'hierarchy/factories/$factoryId/conveyors/$conveyorId/stations/$stationId/assetId';

    if (snapshot.value is Map) {
      final factories = Map<Object?, Object?>.from(snapshot.value as Map);
      factories.forEach((fKey, fValue) {
        if (fValue is! Map) return;
        final conveyors = Map<Object?, Object?>.from(fValue)['conveyors'];
        if (conveyors is! Map) return;
        Map<Object?, Object?>.from(conveyors).forEach((cKey, cValue) {
          if (cValue is! Map) return;
          final stations = Map<Object?, Object?>.from(cValue)['stations'];
          if (stations is! Map) return;
          Map<Object?, Object?>.from(stations).forEach((sKey, sValue) {
            if (sValue is! Map) return;
            final stationMap = Map<Object?, Object?>.from(sValue);
            final existingAssetId =
                normalizeAssetId(stationMap['assetId']?.toString() ?? '');
            if (existingAssetId != normalized) return;
            final existingPath =
                'hierarchy/factories/$fKey/conveyors/$cKey/stations/$sKey/assetId';
            if (existingPath != targetPath) {
              updates[existingPath] = null;
            }
          });
        });
      });
    }

    updates[targetPath] = normalized;
    await _reserveAssetCounterFloor(normalized);
    await _db.update(updates);
  }

  Future<Station?> findStationByLocation(
      String factoryName, int conveyorNumber, int stationNumber) async {
    final factories = await getFactories().first;
    final factory = factories.cast<Factory?>().firstWhere(
          (f) => f?.name == factoryName,
          orElse: () => null,
        );
    if (factory == null) return null;
    final conveyor = factory.conveyors.values.cast<Conveyor?>().firstWhere(
          (c) => c?.number == conveyorNumber,
          orElse: () => null,
        );
    if (conveyor == null) return null;
    return conveyor.stations.values.cast<Station?>().firstWhere(
          (s) => s?.id == 'station_$stationNumber',
          orElse: () => null,
        );
  }

  Future<String?> getAssetIdForLocation(
      String factoryName, int conveyorNumber, int stationNumber) async {
    final station =
        await findStationByLocation(factoryName, conveyorNumber, stationNumber);
    final assetId = station?.assetId.trim();
    if (assetId == null || assetId.isEmpty) return null;
    return assetId;
  }

  Future<void> addFactoryWithConveyors(
      String id, String name, String location, int numConveyors) async {
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
    final conveyorRef =
        _db.child('hierarchy/factories/$factoryId/conveyors/$conveyorId');
    final existing = await conveyorRef.get();
    if (existing.exists) {
      throw Exception(
          'Conveyor $conveyorNumber already exists in this factory');
    }
    final conveyorMap = {
      'number': conveyorNumber,
      'stations': {},
    };
    await conveyorRef.set(conveyorMap);
  }

  Future<void> updateConveyorNumber(
      String factoryId, String conveyorId, int newNumber) async {
    await _db
        .child('hierarchy/factories/$factoryId/conveyors/$conveyorId/number')
        .set(newNumber);
  }

  Future<void> addStation(
      String factoryId, String conveyorId, int stationNumber) async {
    // Use string key to prevent Firebase array conversion
    final stationId = "station_$stationNumber";
    final stationRef = _db.child(
        'hierarchy/factories/$factoryId/conveyors/$conveyorId/stations/$stationId');
    final existing = await stationRef.get();
    if (existing.exists) {
      throw Exception('Station $stationNumber already exists');
    }
    final assetId = await nextAssetId();
    final stationMap = {
      'name': 'Station $stationNumber',
      'address':
          '${factoryId.replaceAll(' ', '_')}_C${conveyorId.replaceAll('conveyor_', '')}_P$stationNumber',
      'assetId': assetId,
    };
    await stationRef.set(stationMap);
  }

  Future<void> deleteFactory(String factoryId) async {
    await _db.child('hierarchy/factories/$factoryId').remove();
  }

  Future<void> deleteConveyor(String factoryId, String conveyorId) async {
    await _db
        .child('hierarchy/factories/$factoryId/conveyors/$conveyorId')
        .remove();
  }

  Future<int> getActiveAlertsCountForConveyor({
    required String usine,
    required int convoyeur,
  }) async {
    final snapshot = await _db.child('alerts').get();
    final data = snapshot.value;
    if (data == null || data is! Map) {
      return 0;
    }

    int count = 0;
    final alerts = Map<Object?, Object?>.from(data);
    for (final value in alerts.values) {
      if (value is! Map) continue;
      final alert = Map<Object?, Object?>.from(value);
      final status = alert['status']?.toString() ?? '';
      final alertUsine = alert['usine']?.toString() ?? '';
      final alertConvoyeur = int.tryParse('${alert['convoyeur']}');

      final isActive = status == 'disponible' || status == 'en_cours';
      if (isActive && alertUsine == usine && alertConvoyeur == convoyeur) {
        count++;
      }
    }
    return count;
  }
}
