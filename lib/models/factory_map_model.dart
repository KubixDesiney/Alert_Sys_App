// lib/models/factory_map_model.dart
//
// Factory floor mapping model. The production manager places the factory
// entrance and station nodes on a snap-to-grid canvas, then connects stations
// belonging to the same conveyor with edges. The supervisor's locator screen
// renders the resulting map and animates a route from the entrance to the
// claimed station.

import 'package:flutter/foundation.dart';

@immutable
class MapCell {
  final int row;
  final int col;

  const MapCell(this.row, this.col);

  factory MapCell.fromMap(Object? data) {
    if (data is Map) {
      final map = Map<Object?, Object?>.from(data);
      final row = (map['row'] as num?)?.toInt() ?? 0;
      final col = (map['col'] as num?)?.toInt() ?? 0;
      return MapCell(row, col);
    }
    return const MapCell(0, 0);
  }

  Map<String, int> toMap() => {'row': row, 'col': col};

  @override
  bool operator ==(Object other) =>
      other is MapCell && other.row == row && other.col == col;

  @override
  int get hashCode => Object.hash(row, col);

  @override
  String toString() => 'MapCell(r=$row,c=$col)';
}

@immutable
class MapNode {
  /// Firebase-safe unique key for a station node in the map.
  final String key;
  final String conveyorId;
  final String stationId;
  final int conveyorNumber;
  final int stationNumber;
  final MapCell cell;

  const MapNode({
    required this.key,
    required this.conveyorId,
    required this.stationId,
    required this.conveyorNumber,
    required this.stationNumber,
    required this.cell,
  });

  String get label => 'C${conveyorNumber}S$stationNumber';

  static String composeKey(String conveyorId, String stationId) =>
      '${conveyorId}|${stationId}';

  static String _normalizeKey(
    String rawKey,
    String conveyorId,
    String stationId,
  ) {
    if (conveyorId.isNotEmpty && stationId.isNotEmpty) {
      return composeKey(conveyorId, stationId);
    }
    if (rawKey.contains('/')) {
      final parts = rawKey.split('/');
      if (parts.length == 2) {
        return composeKey(parts[0], parts[1]);
      }
    }
    return rawKey;
  }

  MapNode copyWith({MapCell? cell}) => MapNode(
        key: key,
        conveyorId: conveyorId,
        stationId: stationId,
        conveyorNumber: conveyorNumber,
        stationNumber: stationNumber,
        cell: cell ?? this.cell,
      );

  factory MapNode.fromMap(String key, Map<Object?, Object?> map) {
    final conveyorId = map['conveyorId']?.toString() ?? '';
    final stationId = map['stationId']?.toString() ?? '';
    return MapNode(
      key: _normalizeKey(key, conveyorId, stationId),
      conveyorId: conveyorId,
      stationId: stationId,
      conveyorNumber: (map['conveyorNumber'] as num?)?.toInt() ??
          int.tryParse(conveyorId.replaceAll('conveyor_', '')) ??
          0,
      stationNumber: (map['stationNumber'] as num?)?.toInt() ??
          int.tryParse(stationId.replaceAll('station_', '')) ??
          0,
      cell: MapCell.fromMap(map['cell']),
    );
  }

  Map<String, Object?> toMap() => {
        'conveyorId': conveyorId,
        'stationId': stationId,
        'conveyorNumber': conveyorNumber,
        'stationNumber': stationNumber,
        'cell': cell.toMap(),
      };
}

@immutable
class MapEdge {
  final String fromKey;
  final String toKey;
  final int conveyorNumber;

  const MapEdge({
    required this.fromKey,
    required this.toKey,
    required this.conveyorNumber,
  });

  /// Unordered identity (so reverse-direction duplicates collapse).
  String get id {
    final pair = [fromKey, toKey]..sort();
    return '${pair[0]}::${pair[1]}';
  }

  factory MapEdge.fromMap(Map<Object?, Object?> map) => MapEdge(
        fromKey: map['from']?.toString() ?? '',
        toKey: map['to']?.toString() ?? '',
        conveyorNumber: (map['conveyorNumber'] as num?)?.toInt() ?? 0,
      );

  Map<String, Object?> toMap() => {
        'from': fromKey,
        'to': toKey,
        'conveyorNumber': conveyorNumber,
      };
}

@immutable
class FactoryMap {
  final String factoryId;
  final MapCell? entrance;
  final List<MapNode> nodes;
  final List<MapEdge> edges;
  final int rows;
  final int cols;
  final DateTime? updatedAt;

  static const int defaultRows = 20;
  static const int defaultCols = 28;

  const FactoryMap({
    required this.factoryId,
    required this.entrance,
    required this.nodes,
    required this.edges,
    this.rows = defaultRows,
    this.cols = defaultCols,
    this.updatedAt,
  });

  factory FactoryMap.empty(String factoryId) => FactoryMap(
        factoryId: factoryId,
        entrance: null,
        nodes: const [],
        edges: const [],
      );

  bool get isEmpty => entrance == null && nodes.isEmpty && edges.isEmpty;

  MapNode? nodeForStation(int conveyorNumber, int stationNumber) {
    for (final node in nodes) {
      if (node.conveyorNumber == conveyorNumber &&
          node.stationNumber == stationNumber) {
        return node;
      }
    }
    return null;
  }

  MapNode? nodeByKey(String key) {
    for (final node in nodes) {
      if (node.key == key) return node;
    }
    return null;
  }

  FactoryMap copyWith({
    MapCell? entrance,
    bool clearEntrance = false,
    List<MapNode>? nodes,
    List<MapEdge>? edges,
    int? rows,
    int? cols,
  }) {
    return FactoryMap(
      factoryId: factoryId,
      entrance: clearEntrance ? null : (entrance ?? this.entrance),
      nodes: nodes ?? this.nodes,
      edges: edges ?? this.edges,
      rows: rows ?? this.rows,
      cols: cols ?? this.cols,
      updatedAt: updatedAt,
    );
  }

  factory FactoryMap.fromMap(String factoryId, Object? data) {
    if (data is! Map) return FactoryMap.empty(factoryId);
    final map = Map<Object?, Object?>.from(data);

    final entranceData = map['entrance'];
    final entrance =
        entranceData is Map ? MapCell.fromMap(entranceData) : null;

    final nodes = <MapNode>[];
    final keyAliases = <String, String>{};
    final nodesData = map['nodes'];
    if (nodesData is Map) {
      Map<Object?, Object?>.from(nodesData).forEach((k, v) {
        if (k is! String || v is! Map) return;
        final node = MapNode.fromMap(k, Map<Object?, Object?>.from(v));
        nodes.add(node);
        keyAliases[k] = node.key;
      });
    } else if (nodesData is List) {
      for (final v in nodesData) {
        if (v is! Map) continue;
        final m = Map<Object?, Object?>.from(v);
        final key = m['key']?.toString();
        if (key == null) continue;
        final node = MapNode.fromMap(key, m);
        nodes.add(node);
        keyAliases[key] = node.key;
      }
    }

    final edges = <MapEdge>[];
    final edgesData = map['edges'];
    if (edgesData is List) {
      for (final v in edgesData) {
        if (v is! Map) continue;
        final edge = MapEdge.fromMap(Map<Object?, Object?>.from(v));
        edges.add(
          MapEdge(
            fromKey: keyAliases[edge.fromKey] ?? edge.fromKey,
            toKey: keyAliases[edge.toKey] ?? edge.toKey,
            conveyorNumber: edge.conveyorNumber,
          ),
        );
      }
    } else if (edgesData is Map) {
      Map<Object?, Object?>.from(edgesData).forEach((_, v) {
        if (v is! Map) return;
        final edge = MapEdge.fromMap(Map<Object?, Object?>.from(v));
        edges.add(
          MapEdge(
            fromKey: keyAliases[edge.fromKey] ?? edge.fromKey,
            toKey: keyAliases[edge.toKey] ?? edge.toKey,
            conveyorNumber: edge.conveyorNumber,
          ),
        );
      });
    }

    final updatedAtRaw = map['updatedAt']?.toString();
    DateTime? updatedAt;
    if (updatedAtRaw != null) {
      updatedAt = DateTime.tryParse(updatedAtRaw);
    }

    return FactoryMap(
      factoryId: factoryId,
      entrance: entrance,
      nodes: nodes,
      edges: edges,
      rows: (map['rows'] as num?)?.toInt() ?? defaultRows,
      cols: (map['cols'] as num?)?.toInt() ?? defaultCols,
      updatedAt: updatedAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      if (entrance != null) 'entrance': entrance!.toMap(),
      'nodes': {
        for (final node in nodes) node.key: node.toMap(),
      },
      'edges': edges.map((edge) => edge.toMap()).toList(),
      'rows': rows,
      'cols': cols,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };
  }
}
