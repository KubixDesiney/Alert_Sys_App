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

  Station({
    required this.id,
    required this.name,
    required this.address,
  });

  factory Station.fromMap(String id, Map<Object?, Object?> map) {
    return Station(
      id: id,
      name: map['name']?.toString() ?? 'Station ${id.replaceAll('station_', '')}',
      address: map['address']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'address': address,
    };
  }
}