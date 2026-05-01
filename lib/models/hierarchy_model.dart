// lib/models/hierarchy_model.dart

class Factory {
  final String id;
  final String name;
  final String location;
  final Map<String, Conveyor> conveyors;

  Factory({
    required this.id,
    required this.name,
    required this.location,
    required this.conveyors,
  });

  factory Factory.fromMap(String id, Map<Object?, Object?> map) {
    final conveyorsMap = <String, Conveyor>{};
    final conveyorsData = map['conveyors'];
    if (conveyorsData is Map<Object?, Object?>) {
      conveyorsData.forEach((key, value) {
        if (key is String && value is Map<Object?, Object?>) {
          conveyorsMap[key] = Conveyor.fromMap(key, value);
        }
      });
    }
    return Factory(
      id: id,
      name: map['name']?.toString() ?? id,
      location: map['location']?.toString() ?? '',
      conveyors: conveyorsMap,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'location': location,
      'conveyors': conveyors.map((key, value) => MapEntry(key, value.toMap())),
    };
  }
}

class Conveyor {
  final String id;
  final int number;
  final Map<String, Station> stations;

  Conveyor({
    required this.id,
    required this.number,
    required this.stations,
  });

  factory Conveyor.fromMap(String id, Map<Object?, Object?> map) {
    final stationsMap = <String, Station>{};
    final stationsData = map['stations'];
    if (stationsData is Map<Object?, Object?>) {
      stationsData.forEach((key, value) {
        if (key is String && value is Map<Object?, Object?>) {
          stationsMap[key] = Station.fromMap(key, value);
        }
      });
    }
    return Conveyor(
      id: id,
      number: (map['number'] as num?)?.toInt() ?? int.tryParse(id) ?? 0,
      stations: stationsMap,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'number': number,
      'stations': stations.map((key, value) => MapEntry(key, value.toMap())),
    };
  }
}

class Station {
  final String id;
  final String name;
  final String address;
  final String assetId;
  final double? x;
  final double? y;

  Station({
    required this.id,
    required this.name,
    required this.address,
    required this.assetId,
    this.x,
    this.y,
  });

  factory Station.fromMap(String id, Map<Object?, Object?> map) {
    return Station(
      id: id,
      name:
          map['name']?.toString() ?? 'Station ${id.replaceAll('station_', '')}',
      address: map['address']?.toString() ?? '',
      assetId: map['assetId']?.toString().trim() ?? '',
      x: _parseCoordinate(map['x']),
      y: _parseCoordinate(map['y']),
    );
  }

  bool get hasCoordinates => x != null && y != null;

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'name': name,
      'address': address,
      'assetId': assetId,
    };
    if (x != null) map['x'] = x;
    if (y != null) map['y'] = y;
    return map;
  }

  static double? _parseCoordinate(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) {
      return double.tryParse(value.trim().replaceAll(',', '.'));
    }
    return null;
  }
}

class StationCoordinates {
  final double? x;
  final double? y;

  const StationCoordinates({this.x, this.y});

  bool get isEmpty => x == null && y == null;
}
