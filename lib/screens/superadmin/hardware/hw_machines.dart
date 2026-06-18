import 'package:alertsysapp/screens/superadmin/superadmin_theme.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

/// Machine / conveyor / factory catalog for the Hardware Lab factory map.
///
/// Real machines are the `MACH-XXX` assets the Production-Manager hierarchy
/// already owns (`/assets`, including archived ones), surfaced read-only here so
/// the operator picks from live plant inventory instead of typing IDs. The lab
/// can also register extra machines of its own under `hardware_lab/machines`
/// (SuperAdmin-writable), which is where "Add machine" lands — `/assets` itself
/// is admin-only.

enum HwMachineStatus { active, outOfService, deleted }

extension HwMachineStatusX on HwMachineStatus {
  String get label => switch (this) {
    HwMachineStatus.active => 'ACTIVE',
    HwMachineStatus.outOfService => 'OUT OF SERVICE',
    HwMachineStatus.deleted => 'DELETED',
  };

  String get key => switch (this) {
    HwMachineStatus.active => 'active',
    HwMachineStatus.outOfService => 'out_of_service',
    HwMachineStatus.deleted => 'deleted',
  };

  Color get color => switch (this) {
    HwMachineStatus.active => Sa.green,
    HwMachineStatus.outOfService => Sa.amber,
    HwMachineStatus.deleted => Sa.muted,
  };

  IconData get icon => switch (this) {
    HwMachineStatus.active => Icons.check_circle,
    HwMachineStatus.outOfService => Icons.do_not_disturb_on,
    HwMachineStatus.deleted => Icons.archive,
  };

  static HwMachineStatus parse(String? raw, {bool isDeleted = false}) {
    if (isDeleted) return HwMachineStatus.deleted;
    switch ((raw ?? '').toLowerCase()) {
      case 'deleted':
        return HwMachineStatus.deleted;
      case 'out_of_service':
      case 'inactive':
      case 'offline':
        return HwMachineStatus.outOfService;
      default:
        return HwMachineStatus.active;
    }
  }
}

class HwMachine {
  final String id; // MACH-001
  String name;
  String description;
  String factoryId;
  String factoryName;
  String conveyorId;
  int conveyorNumber;
  HwMachineStatus status;
  final bool fromAsset; // true → real plant asset (read-only here)
  int updatedAtMs;

  HwMachine({
    required this.id,
    this.name = '',
    this.description = '',
    this.factoryId = '',
    this.factoryName = '',
    this.conveyorId = '',
    this.conveyorNumber = 0,
    this.status = HwMachineStatus.active,
    this.fromAsset = false,
    int? updatedAtMs,
  }) : updatedAtMs = updatedAtMs ?? DateTime.now().millisecondsSinceEpoch;

  String get displayName => name.trim().isEmpty ? id : name.trim();

  String get conveyorLabel => conveyorId.isEmpty
      ? ''
      : 'Conveyor ${conveyorNumber == 0 ? conveyorId : conveyorNumber}';

  factory HwMachine.fromAssetMap(String id, Map data) {
    final machineId = _firstText(data, const ['assetId', 'id']);
    final conveyorNumber = _firstInt(data, const [
      'conveyorNumber',
      'convoyeur',
      'conveyor',
    ]);
    final conveyorId = _firstText(data, const ['conveyorId', 'convoyeurId']);
    final factoryName = _firstText(data, const [
      'factoryName',
      'factory',
      'usine',
    ]);
    return HwMachine(
      id: machineId.isEmpty ? id.trim() : machineId,
      name: _firstText(data, const ['name', 'stationName', 'label', 'address']),
      description: _firstText(data, const ['description', 'details']),
      factoryId: _firstText(data, const ['factoryId', 'factory', 'usine']),
      factoryName: factoryName,
      conveyorId: conveyorId.isNotEmpty
          ? conveyorId
          : (conveyorNumber > 0 ? 'conveyor_$conveyorNumber' : ''),
      conveyorNumber: conveyorNumber,
      status: HwMachineStatusX.parse(
        _firstText(data, const ['status', 'state']),
        isDeleted: _truthy(data['isDeleted']),
      ),
      fromAsset: true,
      updatedAtMs:
          _timestampMs(
            data['updatedAt'] ?? data['updatedAtMs'] ?? data['lastUpdatedAt'],
          ) ??
          DateTime.now().millisecondsSinceEpoch,
    );
  }

  factory HwMachine.fromLabMap(String id, Map data) => HwMachine(
    id: _firstText(data, const ['id']).isEmpty
        ? id.trim()
        : _firstText(data, const ['id']),
    name: _firstText(data, const ['name']),
    description: _firstText(data, const ['description']),
    factoryId: _firstText(data, const ['factoryId']),
    factoryName: _firstText(data, const ['factoryName']),
    conveyorId: _firstText(data, const ['conveyorId']),
    conveyorNumber: _firstInt(data, const ['conveyorNumber']),
    status: HwMachineStatusX.parse(_firstText(data, const ['status'])),
    fromAsset: false,
    updatedAtMs:
        _timestampMs(data['updatedAtMs'] ?? data['updatedAt']) ??
        DateTime.now().millisecondsSinceEpoch,
  );

  Map<String, Object?> toLabJson() => {
    'id': id,
    'name': name,
    'description': description,
    'factoryId': factoryId,
    'factoryName': factoryName,
    'conveyorId': conveyorId,
    'conveyorNumber': conveyorNumber,
    'status': status.key,
    'updatedAtMs': updatedAtMs,
  };
}

class HwConveyorRef {
  final String id;
  final int number;
  final String factoryId;
  HwMachineStatus status;
  HwConveyorRef({
    required this.id,
    required this.number,
    required this.factoryId,
    this.status = HwMachineStatus.active,
  });

  String get label => 'Conveyor $number';
}

class HwFactoryRef {
  final String id;
  final String name;
  const HwFactoryRef({required this.id, required this.name});
}

/// Loaded factory → conveyor → machine catalog the binding editor reads.
class _HierarchyAssetLocation {
  final String assetId;
  final String name;
  final String factoryId;
  final String factoryName;
  final String conveyorId;
  final int conveyorNumber;

  const _HierarchyAssetLocation({
    required this.assetId,
    required this.name,
    required this.factoryId,
    required this.factoryName,
    required this.conveyorId,
    required this.conveyorNumber,
  });

  HwMachine toMachine() => HwMachine(
    id: assetId,
    name: name,
    factoryId: factoryId,
    factoryName: factoryName,
    conveyorId: conveyorId,
    conveyorNumber: conveyorNumber,
    fromAsset: true,
  );

  void applyTo(HwMachine machine) {
    if (machine.name.trim().isEmpty) machine.name = name;
    if (machine.factoryId.trim().isEmpty) machine.factoryId = factoryId;
    if (machine.factoryName.trim().isEmpty) machine.factoryName = factoryName;
    if (machine.conveyorId.trim().isEmpty) machine.conveyorId = conveyorId;
    if (machine.conveyorNumber == 0) machine.conveyorNumber = conveyorNumber;
  }
}

class HwFactoryCatalog {
  final List<HwFactoryRef> factories;
  final Map<String, List<HwConveyorRef>> conveyorsByFactory;
  final List<HwMachine> machines;

  const HwFactoryCatalog({
    this.factories = const [],
    this.conveyorsByFactory = const {},
    this.machines = const [],
  });

  List<HwConveyorRef> conveyorsFor(String factoryId) =>
      conveyorsByFactory[factoryId] ?? const [];

  HwFactoryRef? factoryById(String? factoryId) {
    if (factoryId == null || factoryId.trim().isEmpty) return null;
    final wanted = _norm(factoryId);
    for (final f in factories) {
      if (_norm(f.id) == wanted) return f;
    }
    return null;
  }

  HwFactoryRef? factoryForMachine(HwMachine machine) {
    final actual = {_norm(machine.factoryId), _norm(machine.factoryName)}
      ..remove('');
    if (actual.isEmpty) return null;
    for (final f in factories) {
      if (actual.contains(_norm(f.id)) || actual.contains(_norm(f.name))) {
        return f;
      }
    }
    return null;
  }

  HwConveyorRef? conveyorById(String? factoryId, String? conveyorId) {
    if (factoryId == null || conveyorId == null || conveyorId.trim().isEmpty) {
      return null;
    }
    final wantedId = _norm(conveyorId);
    final wantedNumber = _numberFromText(conveyorId);
    for (final c in conveyorsFor(factoryId)) {
      if (_norm(c.id) == wantedId) return c;
      if (wantedNumber > 0 && c.number == wantedNumber) return c;
    }
    return null;
  }

  HwMachine? machineById(String id) {
    for (final m in machines) {
      if (m.id == id) return m;
    }
    return null;
  }

  bool machineMatchesFactory(HwMachine machine, String? factoryId) {
    if (factoryId == null || factoryId.trim().isEmpty) return true;
    final actual = {_norm(machine.factoryId), _norm(machine.factoryName)}
      ..remove('');
    if (actual.isEmpty) return true;

    final selected = factoryById(factoryId);
    final wanted = {
      _norm(factoryId),
      if (selected != null) _norm(selected.name),
    }..remove('');
    return actual.any(wanted.contains);
  }

  bool machineMatchesConveyor(
    HwMachine machine,
    String? factoryId,
    String? conveyorId,
  ) {
    if (conveyorId == null || conveyorId.trim().isEmpty) return true;
    final actualId = _norm(machine.conveyorId);
    final actualNumber = machine.conveyorNumber > 0
        ? machine.conveyorNumber
        : _numberFromText(machine.conveyorId);
    if (actualId.isEmpty && actualNumber == 0) return true;

    final selected = conveyorById(factoryId, conveyorId);
    final wantedId = _norm(conveyorId);
    final wantedNumber = selected?.number ?? _numberFromText(conveyorId);
    if (actualId.isNotEmpty &&
        (actualId == wantedId ||
            (wantedNumber > 0 && actualId == 'conveyor_$wantedNumber'))) {
      return true;
    }
    return actualNumber > 0 && wantedNumber > 0 && actualNumber == wantedNumber;
  }

  /// Suggest the next free `MACH-NNN` id across both assets and lab machines.
  String suggestNextMachineId() {
    var maxN = 0;
    final re = RegExp(r'^MACH-(\d+)$');
    for (final m in machines) {
      final mt = re.firstMatch(m.id);
      if (mt != null) {
        final n = int.tryParse(mt.group(1)!) ?? 0;
        if (n > maxN) maxN = n;
      }
    }
    return 'MACH-${(maxN + 1).toString().padLeft(3, '0')}';
  }
}

/// Reads the catalog and persists lab-owned machines.
class HwMachineStore {
  HwMachineStore({FirebaseDatabase? db})
    : _db = db ?? FirebaseDatabase.instance;
  final FirebaseDatabase _db;

  DatabaseReference get _labMachines => _db.ref('hardware_lab/machines');

  Future<HwFactoryCatalog> loadCatalog() async {
    final factories = <HwFactoryRef>[];
    final conveyorsByFactory = <String, List<HwConveyorRef>>{};
    final machines = <String, HwMachine>{};
    final hierarchyAssets = <String, _HierarchyAssetLocation>{};

    // 1) Factories + conveyors from the hierarchy.
    try {
      final snap = await _db.ref('hierarchy/factories').get();
      final v = snap.value;
      if (v is Map) {
        v.forEach((fId, fac) {
          if (fac is! Map) return;
          final name = '${fac['name'] ?? fac['usine'] ?? fId}';
          factories.add(HwFactoryRef(id: '$fId', name: name));
          final convs = <HwConveyorRef>[];
          final cData = fac['conveyors'];
          if (cData is Map) {
            cData.forEach((cId, conv) {
              if (conv is! Map) return;
              final number =
                  _intFromValue(conv['number']) ?? _numberFromText('$cId');
              convs.add(
                HwConveyorRef(id: '$cId', number: number, factoryId: '$fId'),
              );
              final stations = conv['stations'];
              if (stations is Map) {
                stations.forEach((sId, station) {
                  if (station is! Map) return;
                  final assetId = _firstText(station, const ['assetId']);
                  if (assetId.isEmpty) return;
                  hierarchyAssets[assetId] = _HierarchyAssetLocation(
                    assetId: assetId,
                    name: _firstText(station, const ['name', 'label']),
                    factoryId: '$fId',
                    factoryName: name,
                    conveyorId: '$cId',
                    conveyorNumber: number,
                  );
                });
              }
            });
          }
          convs.sort((a, b) => a.number.compareTo(b.number));
          conveyorsByFactory['$fId'] = convs;
        });
      }
    } catch (_) {}
    factories.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );

    // 2) Real machines from /assets (read-only, includes archived).
    try {
      final snap = await _db.ref('assets').get();
      final v = snap.value;
      if (v is Map) {
        v.forEach((id, data) {
          if (data is! Map) return;
          try {
            final machine = HwMachine.fromAssetMap('$id', data);
            final loc = hierarchyAssets[machine.id] ?? hierarchyAssets['$id'];
            loc?.applyTo(machine);
            machines[machine.id] = machine;
          } catch (_) {}
        });
      }
    } catch (_) {}

    for (final loc in hierarchyAssets.values) {
      machines.putIfAbsent(loc.assetId, loc.toMachine);
    }

    // 3) Lab machines override / extend (SuperAdmin-owned).
    try {
      final snap = await _labMachines.get();
      final v = snap.value;
      if (v is Map) {
        v.forEach((id, data) {
          if (data is Map) {
            final machine = HwMachine.fromLabMap('$id', data);
            machines[machine.id] = machine;
          }
        });
      }
    } catch (_) {}

    // 4) Derive conveyor status from its machines (out of service if every
    //    machine on the line is down/archived).
    final byConveyor = <String, List<HwMachine>>{};
    for (final m in machines.values) {
      if (m.conveyorId.isEmpty) continue;
      byConveyor.putIfAbsent('${m.factoryId}/${m.conveyorId}', () => []).add(m);
    }
    for (final convs in conveyorsByFactory.values) {
      for (final c in convs) {
        final ms = byConveyor['${c.factoryId}/${c.id}'] ?? const [];
        if (ms.isEmpty) continue;
        final anyActive = ms.any((m) => m.status == HwMachineStatus.active);
        if (!anyActive) c.status = HwMachineStatus.outOfService;
      }
    }

    final list = machines.values.toList()..sort((a, b) => a.id.compareTo(b.id));
    return HwFactoryCatalog(
      factories: factories,
      conveyorsByFactory: conveyorsByFactory,
      machines: list,
    );
  }

  Future<void> saveMachine(HwMachine m) async {
    m.updatedAtMs = DateTime.now().millisecondsSinceEpoch;
    try {
      await _labMachines.child(m.id).set(m.toLabJson());
    } catch (_) {}
  }

  Future<void> deleteMachine(String id) async {
    try {
      await _labMachines.child(id).remove();
    } catch (_) {}
  }
}

String _firstText(Map data, List<String> keys) {
  for (final key in keys) {
    final text = _text(data[key]);
    if (text.isNotEmpty) return text;
  }
  return '';
}

int _firstInt(Map data, List<String> keys) {
  for (final key in keys) {
    final value = _intFromValue(data[key]);
    if (value != null) return value;
  }
  return 0;
}

String _text(Object? value) => value?.toString().trim() ?? '';

String _norm(String value) => value.trim().toLowerCase();

bool _truthy(Object? value) {
  if (value is bool) return value;
  final text = _norm(_text(value));
  return text == 'true' || text == '1' || text == 'yes';
}

int? _intFromValue(Object? value) {
  if (value is num) return value.toInt();
  final text = _text(value);
  if (text.isEmpty) return null;
  final direct = int.tryParse(text);
  if (direct != null) return direct;
  final match = RegExp(r'\d+').firstMatch(text);
  return match == null ? null : int.tryParse(match.group(0)!);
}

int _numberFromText(String value) => _intFromValue(value) ?? 0;

int? _timestampMs(Object? value) {
  if (value is num) return value.toInt();
  final text = _text(value);
  if (text.isEmpty) return null;
  final millis = int.tryParse(text);
  if (millis != null) return millis;
  return DateTime.tryParse(text)?.millisecondsSinceEpoch;
}
