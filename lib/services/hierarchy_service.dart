import 'package:firebase_database/firebase_database.dart';
import '../models/factory_map_model.dart';
import '../models/hierarchy_model.dart';

class HierarchyService {
  final DatabaseReference _db = FirebaseDatabase.instance.ref();
  final int maxStations = 32;

  String _formatAssetId(int value) =>
      'MACH-${value.toString().padLeft(3, '0')}';

  String normalizeAssetId(String value) =>
      value.trim().replaceAll(' ', '').toUpperCase();

  String _buildStationAddress(
    String factoryId,
    String conveyorId,
    int stationNumber,
  ) {
    return '${factoryId.replaceAll(' ', '_')}_C${conveyorId.replaceAll('conveyor_', '')}_P$stationNumber';
  }

  int? _nextAvailableStationNumber(Map<String, Station> stations) {
    for (int i = 1; i <= maxStations; i++) {
      if (!stations.containsKey('station_$i')) {
        return i;
      }
    }
    return null;
  }

  Future<void> _ensureAssetHistoryNode(String assetId) async {
    final historyRef = _db.child('assets/$assetId/history');
    final snapshot = await historyRef.get();
    if (!snapshot.exists) {
      await historyRef.set(<Object?>[]);
    }
  }

  Future<void> _upsertAssetNode({
    required String assetId,
    required String stationName,
    required String factoryId,
    required String factoryName,
    required String conveyorId,
    required int conveyorNumber,
    required String stationId,
    required int stationNumber,
    required String address,
  }) async {
    await _db.child('assets/$assetId').update({
      'assetId': assetId,
      'name': stationName,
      'factoryId': factoryId,
      'factoryName': factoryName,
      'conveyorId': conveyorId,
      'conveyorNumber': conveyorNumber,
      'stationId': stationId,
      'stationNumber': stationNumber,
      'address': address,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    });
    await _ensureAssetHistoryNode(assetId);
  }

  Future<void> _appendAssetHistory({
    required String assetId,
    required Map<String, Object?> entry,
  }) async {
    final historyRef = _db.child('assets/$assetId/history');
    await historyRef.runTransaction((current) {
      final history = <Object?>[];
      if (current is List) {
        history.addAll(List<Object?>.from(current));
      }
      history.add(entry);
      return Transaction.success(history);
    });
  }

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
    final factories = await getFactories().first;
    final factory = factories.cast<Factory?>().firstWhere(
          (item) => item?.id == factoryId,
          orElse: () => null,
        );
    final conveyor = factory?.conveyors[conveyorId];
    final station = conveyor?.stations[stationId];
    final stationNumber =
        int.tryParse(stationId.replaceFirst('station_', '')) ?? 0;
    await _upsertAssetNode(
      assetId: assetId,
      stationName: station?.name ?? 'Station $stationNumber',
      factoryId: factoryId,
      factoryName: factory?.name ?? factoryId,
      conveyorId: conveyorId,
      conveyorNumber: conveyor?.number ?? 0,
      stationId: stationId,
      stationNumber: stationNumber,
      address: station?.address ??
          _buildStationAddress(factoryId, conveyorId, stationNumber),
    );
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

    final factories = await getFactories().first;
    final factory = factories.cast<Factory?>().firstWhere(
          (item) => item?.id == factoryId,
          orElse: () => null,
        );
    final conveyor = factory?.conveyors[conveyorId];
    final station = conveyor?.stations[stationId];
    final stationNumber =
        int.tryParse(stationId.replaceFirst('station_', '')) ?? 0;
    await _upsertAssetNode(
      assetId: normalized,
      stationName: station?.name ?? 'Station $stationNumber',
      factoryId: factoryId,
      factoryName: factory?.name ?? factoryId,
      conveyorId: conveyorId,
      conveyorNumber: conveyor?.number ?? 0,
      stationId: stationId,
      stationNumber: stationNumber,
      address: station?.address ??
          _buildStationAddress(factoryId, conveyorId, stationNumber),
    );
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
    final stationName = 'Station $stationNumber';
    final address = _buildStationAddress(factoryId, conveyorId, stationNumber);
    final stationMap = {
      'name': stationName,
      'address': address,
      'assetId': assetId,
    };
    await stationRef.set(stationMap);
    final factories = await getFactories().first;
    final factory = factories.cast<Factory?>().firstWhere(
          (item) => item?.id == factoryId,
          orElse: () => null,
        );
    final conveyor = factory?.conveyors[conveyorId];
    await _upsertAssetNode(
      assetId: assetId,
      stationName: stationName,
      factoryId: factoryId,
      factoryName: factory?.name ?? factoryId,
      conveyorId: conveyorId,
      conveyorNumber: conveyor?.number ?? 0,
      stationId: stationId,
      stationNumber: stationNumber,
      address: address,
    );
  }

  // ── Factory Mapping ────────────────────────────────────────────────────────
  // Persists the production manager's drag-and-drop map at
  // hierarchy/factories/{factoryId}/map/. Streamed live to supervisors so any
  // edit (place, move, connect, delete) shows up immediately on their locator.

  Stream<FactoryMap> streamFactoryMap(String factoryId) {
    return _db
        .child('hierarchy/factories/$factoryId/map')
        .onValue
        .map((event) => FactoryMap.fromMap(factoryId, event.snapshot.value));
  }

  Future<FactoryMap> getFactoryMap(String factoryId) async {
    final snap = await _db.child('hierarchy/factories/$factoryId/map').get();
    return FactoryMap.fromMap(factoryId, snap.value);
  }

  Future<void> saveFactoryMap(FactoryMap map) async {
    await _db
        .child('hierarchy/factories/${map.factoryId}/map')
        .set(map.toMap());
  }

  Future<void> clearFactoryMap(String factoryId) async {
    await _db.child('hierarchy/factories/$factoryId/map').remove();
  }

  Future<String> moveStation({
    required String currentFactoryId,
    required String currentConveyorId,
    required String stationId,
    required String destinationFactoryId,
    required String destinationConveyorId,
  }) async {
    if (currentFactoryId == destinationFactoryId &&
        currentConveyorId == destinationConveyorId) {
      throw Exception('Choose a different destination before moving.');
    }

    final factories = await getFactories().first;
    final currentFactory = factories.cast<Factory?>().firstWhere(
          (item) => item?.id == currentFactoryId,
          orElse: () => null,
        );
    final destinationFactory = factories.cast<Factory?>().firstWhere(
          (item) => item?.id == destinationFactoryId,
          orElse: () => null,
        );
    if (currentFactory == null || destinationFactory == null) {
      throw Exception('Could not resolve the selected factory.');
    }

    final currentConveyor = currentFactory.conveyors[currentConveyorId];
    final destinationConveyor =
        destinationFactory.conveyors[destinationConveyorId];
    if (currentConveyor == null || destinationConveyor == null) {
      throw Exception('Could not resolve the selected conveyor.');
    }

    final oldStationRef = _db.child(
      'hierarchy/factories/$currentFactoryId/conveyors/$currentConveyorId/stations/$stationId',
    );
    final oldSnapshot = await oldStationRef.get();
    if (!oldSnapshot.exists || oldSnapshot.value is! Map) {
      throw Exception('The station no longer exists.');
    }

    final stationMap = Map<Object?, Object?>.from(oldSnapshot.value as Map);
    final station = Station.fromMap(stationId, stationMap);
    final assetId = station.assetId.trim();
    if (assetId.isEmpty) {
      throw Exception('Only stations with an Asset ID can be moved.');
    }

    final newStationNumber =
        _nextAvailableStationNumber(destinationConveyor.stations);
    if (newStationNumber == null) {
      throw Exception(
          'Conveyor ${destinationConveyor.number} already has $maxStations stations.');
    }

    final newStationId = 'station_$newStationNumber';
    final newAddress = _buildStationAddress(
      destinationFactoryId,
      destinationConveyorId,
      newStationNumber,
    );
    final now = DateTime.now().toUtc().toIso8601String();
    final oldStationNumber =
        int.tryParse(stationId.replaceFirst('station_', '')) ?? 0;

    await _db.update({
      'hierarchy/factories/$destinationFactoryId/conveyors/$destinationConveyorId/stations/$newStationId':
          {
        'name': station.name,
        'address': newAddress,
        'assetId': assetId,
      },
      'hierarchy/factories/$currentFactoryId/conveyors/$currentConveyorId/stations/$stationId':
          null,
      'assets/$assetId/assetId': assetId,
      'assets/$assetId/name': station.name,
      'assets/$assetId/factoryId': destinationFactoryId,
      'assets/$assetId/factoryName': destinationFactory.name,
      'assets/$assetId/conveyorId': destinationConveyorId,
      'assets/$assetId/conveyorNumber': destinationConveyor.number,
      'assets/$assetId/stationId': newStationId,
      'assets/$assetId/stationNumber': newStationNumber,
      'assets/$assetId/address': newAddress,
      'assets/$assetId/updatedAt': now,
    });

    await _ensureAssetHistoryNode(assetId);
    await _appendAssetHistory(
      assetId: assetId,
      entry: {
        'movedAt': now,
        'from': {
          'factoryId': currentFactoryId,
          'factoryName': currentFactory.name,
          'conveyorId': currentConveyorId,
          'conveyorNumber': currentConveyor.number,
          'stationId': stationId,
          'stationNumber': oldStationNumber,
          'address': station.address,
        },
        'to': {
          'factoryId': destinationFactoryId,
          'factoryName': destinationFactory.name,
          'conveyorId': destinationConveyorId,
          'conveyorNumber': destinationConveyor.number,
          'stationId': newStationId,
          'stationNumber': newStationNumber,
          'address': newAddress,
        },
      },
    );

    return newStationId;
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
