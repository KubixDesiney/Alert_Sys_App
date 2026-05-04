import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../models/hierarchy_model.dart';
import '../services/hierarchy_service.dart';
import '../theme.dart';
import 'factory_mapping_tab.dart';

const _navy = AppColors.navy;
const _muted = AppColors.mutedDark;
const _green = AppColors.green;
const _red = AppColors.red;

class HierarchyScreen extends StatefulWidget {
  const HierarchyScreen({super.key});

  @override
  State<HierarchyScreen> createState() => _HierarchyScreenState();
}

class _HierarchyScreenState extends State<HierarchyScreen> {
  final HierarchyService _service = HierarchyService();
  List<Factory> _factories = [];
  Factory? _selectedFactory;
  Conveyor? _selectedConveyor;
  bool _loading = true;
  StreamSubscription? _factoriesSubscription;

  @override
  void initState() {
    super.initState();
    _loadFactories();
  }

  void _loadFactories() {
    _factoriesSubscription?.cancel();
    _factoriesSubscription = _service.getFactories().listen((factories) {
      if (!mounted) return;
      setState(() {
        _factories = factories;
        _loading = false;
        // Update selection
        if (_selectedFactory != null) {
          final exists = _factories.any((f) => f.id == _selectedFactory!.id);
          if (!exists) {
            _selectedFactory = null;
            _selectedConveyor = null;
          } else {
            _selectedFactory =
                _factories.firstWhere((f) => f.id == _selectedFactory!.id);
            if (_selectedConveyor != null &&
                !_selectedFactory!.conveyors
                    .containsKey(_selectedConveyor!.id)) {
              _selectedConveyor = null;
            } else if (_selectedConveyor != null) {
              _selectedConveyor =
                  _selectedFactory!.conveyors[_selectedConveyor!.id];
            }
          }
        }
        if (_selectedFactory == null && _factories.isNotEmpty) {
          _selectedFactory = _factories.first;
        }
      });
    });
  }

  @override
  void dispose() {
    _factoriesSubscription?.cancel();
    super.dispose();
  }

  int? _stationNumber(Station station) {
    final fromId = int.tryParse(station.id.replaceAll('station_', ''));
    if (fromId != null) return fromId;
    final embedded = RegExp(r'\d+').firstMatch(station.name);
    return embedded == null ? null : int.tryParse(embedded.group(0)!);
  }

  String _stationQrPayload({
    required String assetId,
    required Factory factory,
    required Conveyor conveyor,
    required int stationNumber,
  }) {
    return const JsonEncoder.withIndent('  ').convert({
      'assetId': assetId,
      'usine': factory.name,
      'convoyeur': conveyor.number,
      'poste': stationNumber,
    });
  }

  Future<void> _showStationQrDialog(Station station) async {
    final factory = _selectedFactory;
    final conveyor = _selectedConveyor;
    final stationNumber = _stationNumber(station);
    if (factory == null || conveyor == null || stationNumber == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select a valid station before generating a QR code.'),
          backgroundColor: _red,
        ),
      );
      return;
    }

    var assetId = station.assetId.trim();
    try {
      if (assetId.isEmpty) {
        assetId = await _service.ensureStationAssetId(
          factory.id,
          conveyor.id,
          station.id,
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create Asset ID: $e')),
      );
      return;
    }

    final payload = _stationQrPayload(
      assetId: assetId,
      factory: factory,
      conveyor: conveyor,
      stationNumber: stationNumber,
    );

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _StationQrDialog(
        stationName: station.name,
        factoryName: factory.name,
        conveyorNumber: conveyor.number,
        stationNumber: stationNumber,
        assetId: assetId,
        payload: payload,
        onRelink: () {
          Navigator.of(context).pop();
          _showRelinkAssetDialog(station);
        },
      ),
    );
  }

  Future<void> _showRelinkAssetDialog(Station station) async {
    final factory = _selectedFactory;
    final conveyor = _selectedConveyor;
    if (factory == null || conveyor == null) return;

    final controller = TextEditingController(text: station.assetId);
    String? error;
    final assetId = await showDialog<String>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setStateDialog) {
          final t = context.appTheme;
          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.precision_manufacturing_outlined, color: t.navy),
                const SizedBox(width: 8),
                const Text('Relink Asset ID'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: controller,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Asset ID',
                    hintText: 'MACH-001',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: TextStyle(color: t.red, fontSize: 12)),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final normalized = _service.normalizeAssetId(controller.text);
                  if (normalized.isEmpty) {
                    setStateDialog(() => error = 'Asset ID is required');
                    return;
                  }
                  Navigator.pop(context, normalized);
                },
                child: const Text('Relink'),
              ),
            ],
          );
        },
      ),
    );
    controller.dispose();
    if (assetId == null) return;
    if (!mounted) return;

    try {
      await _service.assignAssetIdToStation(
        factoryId: factory.id,
        conveyorId: conveyor.id,
        stationId: station.id,
        assetId: assetId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$assetId linked to ${station.name}'),
          backgroundColor: _green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not relink asset: $e')),
      );
    }
  }

  int? _nextAvailableStationNumber(Conveyor conveyor) {
    for (int i = 1; i <= _service.maxStations; i++) {
      if (!conveyor.stations.containsKey('station_$i')) {
        return i;
      }
    }
    return null;
  }

  Future<void> _showMoveStationDialog(Station station) async {
    final currentFactory = _selectedFactory;
    final currentConveyor = _selectedConveyor;
    final assetId = station.assetId.trim();
    if (currentFactory == null || currentConveyor == null || assetId.isEmpty) {
      return;
    }

    String destinationFactoryId = currentFactory.id;
    String destinationConveyorId = currentConveyor.id;
    String? error;
    bool moving = false;

    final moved = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setStateDialog) {
          final t = context.appTheme;
          final destinationFactory = _factories.cast<Factory?>().firstWhere(
                (factory) => factory?.id == destinationFactoryId,
                orElse: () => null,
              );
          final destinationConveyors =
              destinationFactory?.conveyors.values.toList() ??
                  const <Conveyor>[];
          if (!destinationConveyors
              .any((conveyor) => conveyor.id == destinationConveyorId)) {
            destinationConveyorId = destinationConveyors.isNotEmpty
                ? destinationConveyors.first.id
                : '';
          }
          final destinationConveyor =
              destinationConveyors.cast<Conveyor?>().firstWhere(
                    (conveyor) => conveyor?.id == destinationConveyorId,
                    orElse: () => null,
                  );
          final nextStationNumber = destinationConveyor == null
              ? null
              : _nextAvailableStationNumber(destinationConveyor);

          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.drive_file_move_outline, color: t.navy),
                const SizedBox(width: 8),
                const Text('Move Station'),
              ],
            ),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Current location',
                    style: TextStyle(
                      color: t.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${currentFactory.name} > Conveyor ${currentConveyor.number} > ${station.name}',
                    style: TextStyle(color: t.muted),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Asset ID: $assetId',
                    style: TextStyle(
                      color: t.navy,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: destinationFactoryId,
                    decoration: const InputDecoration(
                      labelText: 'Destination Factory',
                      border: OutlineInputBorder(),
                    ),
                    items: _factories
                        .map(
                          (factory) => DropdownMenuItem<String>(
                            value: factory.id,
                            child: Text(factory.name),
                          ),
                        )
                        .toList(),
                    onChanged: moving
                        ? null
                        : (value) {
                            if (value == null) return;
                            setStateDialog(() {
                              destinationFactoryId = value;
                              error = null;
                            });
                          },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: destinationConveyorId.isEmpty
                        ? null
                        : destinationConveyorId,
                    decoration: const InputDecoration(
                      labelText: 'Destination Conveyor',
                      border: OutlineInputBorder(),
                    ),
                    items: destinationConveyors
                        .map(
                          (conveyor) => DropdownMenuItem<String>(
                            value: conveyor.id,
                            child: Text('Conveyor ${conveyor.number}'),
                          ),
                        )
                        .toList(),
                    onChanged: moving
                        ? null
                        : (value) {
                            if (value == null) return;
                            setStateDialog(() {
                              destinationConveyorId = value;
                              error = null;
                            });
                          },
                  ),
                  const SizedBox(height: 12),
                  Text(
                    nextStationNumber == null
                        ? 'Selected conveyor is full.'
                        : 'The station will be placed in slot $nextStationNumber and its address will be updated automatically.',
                    style: TextStyle(color: t.muted, fontSize: 12),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      error!,
                      style: TextStyle(color: t.red, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: moving ? null : () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: moving
                    ? null
                    : () async {
                        if (destinationFactoryId == currentFactory.id &&
                            destinationConveyorId == currentConveyor.id) {
                          setStateDialog(() {
                            error = 'Select a different destination.';
                          });
                          return;
                        }
                        if (destinationConveyor == null) {
                          setStateDialog(() {
                            error = 'Select a destination conveyor.';
                          });
                          return;
                        }
                        if (nextStationNumber == null) {
                          setStateDialog(() {
                            error =
                                'The selected conveyor has no free station slots.';
                          });
                          return;
                        }

                        setStateDialog(() {
                          moving = true;
                          error = null;
                        });

                        try {
                          await _service.moveStation(
                            currentFactoryId: currentFactory.id,
                            currentConveyorId: currentConveyor.id,
                            stationId: station.id,
                            destinationFactoryId: destinationFactoryId,
                            destinationConveyorId: destinationConveyorId,
                          );
                          if (!context.mounted) return;
                          Navigator.pop(context, true);
                        } catch (e) {
                          setStateDialog(() {
                            error = e.toString();
                            moving = false;
                          });
                        }
                      },
                child: moving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Move'),
              ),
            ],
          );
        },
      ),
    );

    if (moved == true) {
      _loadFactories();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${station.name} moved successfully'),
          backgroundColor: _green,
        ),
      );
    }
  }


  // ------------------- Add Factory Dialog -------------------
  Future<void> _showAddFactoryDialog() async {
    final nameController = TextEditingController();
    final locationController = TextEditingController();
    final conveyorsController = TextEditingController();
    String? error;

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: const Text('Add Factory'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Add a new factory'),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Factory Name',
                      hintText: 'Ex: Factory C',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: locationController,
                    decoration: const InputDecoration(
                      labelText: 'Location',
                      hintText: 'Ex: Casablanca',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: conveyorsController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Number of Conveyors',
                      hintText: 'Ex: 3',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(error!,
                          style: const TextStyle(color: _red, fontSize: 12)),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () async {
                  final name = nameController.text.trim();
                  final location = locationController.text.trim();
                  final numConveyors =
                      int.tryParse(conveyorsController.text.trim());
                  if (name.isEmpty) {
                    setStateDialog(() => error = 'Factory name is required');
                    return;
                  }
                  if (numConveyors == null || numConveyors < 1) {
                    setStateDialog(
                        () => error = 'Enter a valid number of conveyors (≥1)');
                    return;
                  }
                  final id = name.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
                  try {
                    await _service.addFactoryWithConveyors(
                        id, name, location, numConveyors);
                    if (context.mounted) Navigator.pop(context);
                    _loadFactories(); // force refresh
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Factory added'),
                            backgroundColor: _green),
                      );
                    }
                  } catch (e) {
                    setStateDialog(() => error = e.toString());
                  }
                },
                child: const Text('Add Factory'),
              ),
            ],
          );
        },
      ),
    );
  }

  // ------------------- Add Conveyor Dialog -------------------
  Future<void> _showAddConveyorDialog() async {
    if (_selectedFactory == null) return;
    final controller = TextEditingController();
    final newNumber = await showDialog<int>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add Conveyor'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter conveyor number'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Conveyor Number'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(_), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(_, int.tryParse(controller.text)),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (newNumber != null) {
      try {
        await _service.addConveyor(_selectedFactory!.id, newNumber);
        _loadFactories();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Conveyor $newNumber added'),
                backgroundColor: _green),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: _red),
          );
        }
      }
    }
  }

  // ------------------- Edit Conveyor Dialog -------------------
  Future<void> _showEditConveyorDialog() async {
    if (_selectedConveyor == null || _selectedFactory == null) return;
    final controller =
        TextEditingController(text: _selectedConveyor!.number.toString());
    final newNumber = await showDialog<int>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit Conveyor'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Update the conveyor number'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Conveyor Number'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(_), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(_, int.tryParse(controller.text)),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newNumber != null && newNumber != _selectedConveyor!.number) {
      await _service.updateConveyorNumber(
          _selectedFactory!.id, _selectedConveyor!.id, newNumber);
      _loadFactories();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Conveyor updated'), backgroundColor: _green),
        );
      }
    }
  }

  // ------------------- Add Stations Dialog -------------------
  Future<void> _showAddStationsDialog() async {
    if (_selectedConveyor == null || _selectedFactory == null) return;
    final currentCount = _selectedConveyor!.stations.length;
    final remaining = _service.maxStations - currentCount;
    final controller = TextEditingController();
    final toAdd = await showDialog<int>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add Station'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Add stations to Conveyor ${_selectedConveyor!.number}'),
            const SizedBox(height: 8),
            Text('Current stations: $currentCount/${_service.maxStations}'),
            Text('Remaining: $remaining'),
            const SizedBox(height: 12),
            const Text('Number of Stations to Add'),
            const SizedBox(height: 4),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: 'Ex: 2'),
            ),
            Text('Maximum: $remaining station(s)',
                style: const TextStyle(fontSize: 12, color: _muted)),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(_), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final int? count = int.tryParse(controller.text);
              if (count != null && count > 0 && count <= remaining) {
                Navigator.pop(_, count);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Invalid number'), backgroundColor: _red),
                );
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (toAdd != null) {
      final startIndex = currentCount + 1;
      for (int i = 0; i < toAdd; i++) {
        final stationNumber = startIndex + i;
        await _service.addStation(
            _selectedFactory!.id, _selectedConveyor!.id, stationNumber);
      }
      _loadFactories();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Added $toAdd station(s)'),
              backgroundColor: _green),
        );
      }
    }
  }

  // ------------------- Delete Factory -------------------
  Future<void> _deleteFactory(Factory factory) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Factory'),
        content:
            Text('Delete "${factory.name}" and all its conveyors/stations?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(_, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(_, true),
              style: ElevatedButton.styleFrom(backgroundColor: _red),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirm == true) {
      await _service.deleteFactory(factory.id);
      _loadFactories();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Factory deleted'), backgroundColor: _red),
        );
      }
    }
  }

  // ------------------- Delete Conveyor -------------------
  Future<void> _deleteConveyor(Conveyor conveyor) async {
    if (_selectedFactory == null) return;

    final activeAlerts = await _service.getActiveAlertsCountForConveyor(
      usine: _selectedFactory!.name,
      convoyeur: conveyor.number,
    );

    if (activeAlerts > 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Cannot delete Conveyor ${conveyor.number}: $activeAlerts active alert(s) are still disponible/en_cours.',
          ),
          backgroundColor: _red,
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Conveyor'),
        content:
            Text('Delete Conveyor ${conveyor.number} and all its stations?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(_, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(_, true),
              style: ElevatedButton.styleFrom(backgroundColor: _red),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirm == true) {
      await _service.deleteConveyor(_selectedFactory!.id, conveyor.id);
      _loadFactories();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Conveyor deleted'), backgroundColor: _red),
        );
      }
    }
  }

  // ------------------- UI -------------------
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final t = context.appTheme;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: t.scaffold,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Hierarchy',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: t.navy)),
                  Text('Structure & factory floor map',
                      style: TextStyle(fontSize: 13, color: t.muted)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Container(
                decoration: BoxDecoration(
                  color: t.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: t.border),
                ),
                child: TabBar(
                  labelColor: t.navy,
                  unselectedLabelColor: t.muted,
                  indicator: BoxDecoration(
                    color: t.navy.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicatorPadding: const EdgeInsets.all(4),
                  dividerColor: Colors.transparent,
                  labelStyle: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w900),
                  tabs: const [
                    Tab(
                        icon: Icon(Icons.account_tree_outlined, size: 18),
                        text: 'Structure'),
                    Tab(
                        icon: Icon(Icons.map_rounded, size: 18),
                        text: 'Factory Mapping'),
                  ],
                ),
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _buildStructureTab(),
                  FactoryMappingTab(
                      factories: _factories, service: _service),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStructureTab() {
    final conveyors = _selectedFactory?.conveyors.values.toList() ?? [];
    final stations = _selectedConveyor?.stations.values.toList() ?? [];

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Factories Panel
                  Expanded(
                    flex: 1,
                    child: Container(
                      decoration: BoxDecoration(
                        color: context.appTheme.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: context.appTheme.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Factories (${_factories.length})',
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: _navy),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.add,
                                      size: 18, color: _green),
                                  onPressed: _showAddFactoryDialog,
                                  tooltip: 'Add Factory',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 1),
                          Expanded(
                              child: _factories.isEmpty
                                  ? const Center(
                                      child: Text('No factories',
                                          style: TextStyle(color: _muted)))
                                  : ListView.builder(
                                      itemCount: _factories.length,
                                      itemBuilder: (context, index) {
                                        final factory = _factories[index];
                                        final isSelected =
                                            _selectedFactory?.id == factory.id;
                                        return Container(
                                          color: isSelected
                                              ? _navy.withValues(alpha: 0.1)
                                              : Colors.transparent,
                                          child: ListTile(
                                            title: Text(
                                              factory.name,
                                              style: TextStyle(
                                                fontWeight: isSelected
                                                    ? FontWeight.bold
                                                    : FontWeight.w600,
                                                color:
                                                    isSelected ? _navy : null,
                                              ),
                                            ),
                                            subtitle: Text(
                                              '${factory.location} · ${factory.conveyors.length} conveyor(s)',
                                              style: const TextStyle(
                                                  fontSize: 12, color: _muted),
                                            ),
                                            trailing: IconButton(
                                              icon: const Icon(
                                                  Icons.delete_outline,
                                                  size: 18,
                                                  color: _red),
                                              onPressed: () =>
                                                  _deleteFactory(factory),
                                            ),
                                            onTap: () => setState(() {
                                              _selectedFactory = factory;
                                              _selectedConveyor = null;
                                            }),
                                          ),
                                        );
                                      },
                                    )),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Conveyors Panel
                  Expanded(
                    flex: 1,
                    child: Container(
                      decoration: BoxDecoration(
                        color: context.appTheme.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: context.appTheme.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Conveyors (${conveyors.length})',
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: _navy),
                                ),
                                if (_selectedFactory != null)
                                  IconButton(
                                    icon: const Icon(Icons.add,
                                        size: 18, color: _green),
                                    onPressed: _showAddConveyorDialog,
                                    tooltip: 'Add Conveyor',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  ),
                              ],
                            ),
                          ),
                          const Divider(height: 1),
                          Expanded(
                              child: _selectedFactory == null
                                  ? const Center(
                                      child: Text('Select a factory first',
                                          style: TextStyle(color: _muted)))
                                  : conveyors.isEmpty
                                      ? const Center(
                                          child: Text('No conveyors',
                                              style: TextStyle(color: _muted)))
                                      : ListView.builder(
                                          itemCount: conveyors.length,
                                          itemBuilder: (context, index) {
                                            final conveyor = conveyors[index];
                                            final isSelected =
                                                _selectedConveyor?.id ==
                                                    conveyor.id;
                                            return Container(
                                              color: isSelected
                                                  ? _navy.withValues(alpha: 0.1)
                                                  : Colors.transparent,
                                              child: ListTile(
                                                title: Text(
                                                  'Conveyor ${conveyor.number}',
                                                  style: TextStyle(
                                                    fontWeight: isSelected
                                                        ? FontWeight.bold
                                                        : FontWeight.w600,
                                                    color: isSelected
                                                        ? _navy
                                                        : null,
                                                  ),
                                                ),
                                                subtitle: Text(
                                                  '${conveyor.stations.length}/${_service.maxStations} stations',
                                                  style: const TextStyle(
                                                      fontSize: 12,
                                                      color: _muted),
                                                ),
                                                trailing: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    IconButton(
                                                      icon: const Icon(
                                                          Icons.edit,
                                                          size: 18),
                                                      onPressed:
                                                          _showEditConveyorDialog,
                                                    ),
                                                    IconButton(
                                                      icon: const Icon(
                                                          Icons.delete_outline,
                                                          size: 18,
                                                          color: _red),
                                                      onPressed: () =>
                                                          _deleteConveyor(
                                                              conveyor),
                                                    ),
                                                  ],
                                                ),
                                                onTap: () => setState(() =>
                                                    _selectedConveyor =
                                                        conveyor),
                                              ),
                                            );
                                          },
                                        )),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Stations Panel
                  Expanded(
                    flex: 1,
                    child: Container(
                      decoration: BoxDecoration(
                        color: context.appTheme.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: context.appTheme.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Stations (${stations.length}/${_service.maxStations})',
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: _navy),
                                ),
                                if (_selectedConveyor != null &&
                                    stations.length < _service.maxStations)
                                  IconButton(
                                    icon: const Icon(Icons.add,
                                        size: 18, color: _green),
                                    onPressed: _showAddStationsDialog,
                                    tooltip: 'Add Stations',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  ),
                              ],
                            ),
                          ),
                          const Divider(height: 1),
                          Expanded(
                            child: _selectedConveyor == null
                                ? const Center(
                                    child: Text('Select a conveyor first',
                                        style: TextStyle(color: _muted)))
                                : stations.isEmpty
                                    ? const Center(
                                        child: Text('No stations',
                                            style: TextStyle(color: _muted)))
                                    : ListView.builder(
                                        itemCount: stations.length,
                                        itemBuilder: (context, index) {
                                          final station = stations[index];
                                          return ListTile(
                                            title: Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    station.name,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                if (station.assetId
                                                    .trim()
                                                    .isNotEmpty)
                                                  TextButton.icon(
                                                    onPressed: () =>
                                                        _showMoveStationDialog(
                                                            station),
                                                    icon: const Icon(
                                                      Icons
                                                          .drive_file_move_outline,
                                                      size: 16,
                                                    ),
                                                    label: const Text('Move'),
                                                    style: TextButton.styleFrom(
                                                      foregroundColor: _navy,
                                                      visualDensity:
                                                          VisualDensity.compact,
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                        horizontal: 8,
                                                        vertical: 0,
                                                      ),
                                                    ),
                                                  ),
                                                IconButton(
                                                  icon: const Icon(
                                                    Icons.qr_code_2,
                                                    size: 18,
                                                  ),
                                                  color: _navy,
                                                  tooltip:
                                                      'Generate station QR',
                                                  onPressed: () =>
                                                      _showStationQrDialog(
                                                          station),
                                                  padding: EdgeInsets.zero,
                                                  constraints:
                                                      const BoxConstraints(
                                                    minWidth: 32,
                                                    minHeight: 32,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            subtitle: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  station.address,
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    color: _muted,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  station.assetId.trim().isEmpty
                                                      ? 'Asset ID pending'
                                                      : station.assetId,
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: station.assetId
                                                            .trim()
                                                            .isEmpty
                                                        ? _muted
                                                        : _navy,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
    );
  }
}
Future<Uint8List> _renderQrPng(String data) async {
  final painter = QrPainter(
    data: data,
    version: QrVersions.auto,
    gapless: false,
    eyeStyle: const QrEyeStyle(
      eyeShape: QrEyeShape.square,
      color: Color(0xFF0F172A),
    ),
    dataModuleStyle: const QrDataModuleStyle(
      dataModuleShape: QrDataModuleShape.square,
      color: Color(0xFF0F172A),
    ),
  );
  final image = await painter.toImage(512);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}

class _StationQrDialog extends StatefulWidget {
  final String stationName;
  final String factoryName;
  final int conveyorNumber;
  final int stationNumber;
  final String assetId;
  final String payload;
  final VoidCallback onRelink;

  const _StationQrDialog({
    required this.stationName,
    required this.factoryName,
    required this.conveyorNumber,
    required this.stationNumber,
    required this.assetId,
    required this.payload,
    required this.onRelink,
  });

  @override
  State<_StationQrDialog> createState() => _StationQrDialogState();
}

class _StationQrDialogState extends State<_StationQrDialog> {
  bool _downloading = false;
  bool _printing = false;

  Future<void> _downloadPng() async {
    setState(() => _downloading = true);
    try {
      final bytes = await _renderQrPng(widget.payload);
      final name = 'qr_${widget.assetId}';
      await FileSaver.instance.saveFile(
        name: name,
        bytes: bytes,
        ext: 'png',
        mimeType: MimeType.png,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('QR saved as $name.png')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _printQr() async {
    setState(() => _printing = true);
    try {
      final bytes = await _renderQrPng(widget.payload);
      final doc = pw.Document();
      final image = pw.MemoryImage(bytes);
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (_) => pw.Center(
            child: pw.Column(
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                pw.Image(image, width: 300, height: 300),
                pw.SizedBox(height: 16),
                pw.Text(
                  widget.stationName,
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  '${widget.factoryName} · Conveyor ${widget.conveyorNumber} · Post ${widget.stationNumber}',
                  style: const pw.TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      );
      await Printing.layoutPdf(onLayout: (_) async => doc.save());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Print failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Material(
          color: t.card,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(height: 4, color: t.navy),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: t.navyLt,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.qr_code_2, color: t.navy, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Station QR Code',
                            style: TextStyle(
                              color: t.text,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.stationName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: t.muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      icon: Icon(Icons.close, color: t.muted),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 520),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: t.border),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.08),
                                blurRadius: 18,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: QrImageView(
                            data: widget.payload,
                            version: QrVersions.auto,
                            size: 220,
                            backgroundColor: Colors.white,
                            gapless: false,
                            eyeStyle: const QrEyeStyle(
                              eyeShape: QrEyeShape.square,
                              color: Color(0xFF0F172A),
                            ),
                            dataModuleStyle: const QrDataModuleStyle(
                              dataModuleShape: QrDataModuleShape.square,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _QrMetaChip(
                              icon: Icons.precision_manufacturing_outlined,
                              label: widget.assetId),
                          _QrMetaChip(
                              icon: Icons.factory, label: widget.factoryName),
                          _QrMetaChip(
                              icon: Icons.linear_scale,
                              label: 'Conveyor ${widget.conveyorNumber}'),
                          _QrMetaChip(
                              icon: Icons.settings,
                              label: 'Post ${widget.stationNumber}'),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: widget.onRelink,
                          icon: const Icon(Icons.link, size: 16),
                          label: const Text('Relink Asset ID'),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: t.scaffold,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: t.border),
                        ),
                        child: SelectableText(
                          widget.payload,
                          style: TextStyle(
                            color: t.text,
                            fontSize: 12,
                            height: 1.35,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                decoration: BoxDecoration(
                  color: t.scaffold,
                  border: Border(top: BorderSide(color: t.border)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close, size: 16),
                        label: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _printing ? null : _printQr,
                        icon: _printing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.print, size: 16),
                        label: const Text('Print QR'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _downloading ? null : _downloadPng,
                        icon: _downloading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.download, size: 16),
                        label: const Text('Download PNG'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QrMetaChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _QrMetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: t.navyLt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.navy.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: t.navy),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: t.navy,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
