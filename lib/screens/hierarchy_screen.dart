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
                    initialValue: destinationFactoryId,
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
                    initialValue: destinationConveyorId.isEmpty
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

  Future<void> _openCoordinateEditor() async {
    final factory = _selectedFactory;
    if (factory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select a factory before setting coordinates.'),
          backgroundColor: _red,
        ),
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _CoordinateEditorScreen(
          factory: factory,
          service: _service,
        ),
      ),
    );
  }

  String _coordinateSummary(Factory factory) {
    final stations = factory.conveyors.values
        .expand((conveyor) => conveyor.stations.values)
        .toList();
    if (stations.isEmpty) return 'No stations mapped';
    final mapped = stations.where((station) => station.hasCoordinates).length;
    return '$mapped/${stations.length} mapped';
  }

  String _formatCoord(double? value) {
    if (value == null) return '--';
    return value.toStringAsFixed(2);
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

    final conveyors = _selectedFactory?.conveyors.values.toList() ?? [];
    final stations = _selectedConveyor?.stations.values.toList() ?? [];

    return Scaffold(
      backgroundColor: context.appTheme.scaffold,
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddFactoryDialog,
        backgroundColor: _navy,
        child: const Icon(Icons.add_business),
        tooltip: 'Add Factory',
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Modify Hierarchy',
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold, color: _navy),
            ),
            const Text(
              'Factory → Conveyor → Station',
              style: TextStyle(fontSize: 13, color: _muted),
            ),
            const SizedBox(height: 24),
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
                                if (_selectedFactory != null) ...[
                                  Tooltip(
                                    message:
                                        _coordinateSummary(_selectedFactory!),
                                    child: TextButton.icon(
                                      onPressed: _openCoordinateEditor,
                                      icon: const Icon(
                                        Icons.edit_location_alt_outlined,
                                        size: 16,
                                      ),
                                      label: const Text('Set Coordinates'),
                                      style: TextButton.styleFrom(
                                        foregroundColor: _navy,
                                        visualDensity: VisualDensity.compact,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 0,
                                        ),
                                        textStyle: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 2),
                                ],
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
                                                const SizedBox(height: 2),
                                                Text(
                                                  station.hasCoordinates
                                                      ? 'Coordinates: x ${_formatCoord(station.x)} / y ${_formatCoord(station.y)}'
                                                      : 'Coordinates not set',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color:
                                                        station.hasCoordinates
                                                            ? _green
                                                            : _muted,
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
      ),
    );
  }
}

class _CoordinateEditorScreen extends StatefulWidget {
  final Factory factory;
  final HierarchyService service;

  const _CoordinateEditorScreen({
    required this.factory,
    required this.service,
  });

  @override
  State<_CoordinateEditorScreen> createState() =>
      _CoordinateEditorScreenState();
}

class _CoordinateEditorScreenState extends State<_CoordinateEditorScreen> {
  final List<_CoordinateDraftRow> _rows = [];
  final Map<String, String> _errors = {};
  bool _saving = false;
  bool _dirty = false;

  static const Map<String, List<double>> _deltaSample = {
    'conveyor_1/station_1': [-3.30, 2.20],
    'conveyor_1/station_2': [-3.30, 4.40],
    'conveyor_1/station_3': [-3.30, 6.60],
    'conveyor_2/station_1': [2.20, 2.20],
    'conveyor_2/station_2': [2.20, 4.95],
    'conveyor_2/station_3': [2.20, 7.15],
    'conveyor_3/station_1': [0.00, 2.75],
    'conveyor_3/station_2': [0.00, 3.025],
    'conveyor_3/station_3': [0.00, 3.575],
  };

  @override
  void initState() {
    super.initState();
    _rows.addAll(_buildRows(widget.factory));
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  List<_CoordinateDraftRow> _buildRows(Factory factory) {
    final conveyors = factory.conveyors.values.toList()
      ..sort((a, b) => a.number.compareTo(b.number));
    final rows = <_CoordinateDraftRow>[];
    for (final conveyor in conveyors) {
      final stations = conveyor.stations.values.toList()
        ..sort((a, b) => _stationNumber(a).compareTo(_stationNumber(b)));
      for (final station in stations) {
        rows.add(
          _CoordinateDraftRow(
            conveyor: conveyor,
            station: station,
            xController: TextEditingController(text: _formatInitial(station.x)),
            yController: TextEditingController(text: _formatInitial(station.y)),
          ),
        );
      }
    }
    return rows;
  }

  int _stationNumber(Station station) {
    return int.tryParse(station.id.replaceFirst('station_', '')) ?? 0;
  }

  String _formatInitial(double? value) {
    if (value == null) return '';
    final rounded = value.toStringAsFixed(3);
    return rounded
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  bool get _isDeltaFactory {
    final id = widget.factory.id.trim().toUpperCase();
    final name = widget.factory.name.trim().toUpperCase();
    return id.contains('DELTA') || name.contains('DELTA');
  }

  int get _mappedCount {
    return _rows.where((row) {
      return row.xController.text.trim().isNotEmpty &&
          row.yController.text.trim().isNotEmpty;
    }).length;
  }

  Map<Conveyor, List<_CoordinateDraftRow>> get _rowsByConveyor {
    final grouped = <Conveyor, List<_CoordinateDraftRow>>{};
    for (final row in _rows) {
      grouped.putIfAbsent(row.conveyor, () => []).add(row);
    }
    return grouped;
  }

  void _markDirty(_CoordinateDraftRow row) {
    if (!_dirty || _errors.containsKey(row.key)) {
      setState(() {
        _dirty = true;
        _errors.remove(row.key);
      });
    } else {
      _dirty = true;
    }
  }

  double? _parseCoordinate(String text) {
    final normalized = text.trim().replaceAll(',', '.');
    if (normalized.isEmpty) return null;
    return double.tryParse(normalized);
  }

  Future<void> _saveAll() async {
    final errors = <String, String>{};
    final updates = <String, Map<String, StationCoordinates>>{};

    for (final row in _rows) {
      final xText = row.xController.text.trim();
      final yText = row.yController.text.trim();
      final xEmpty = xText.isEmpty;
      final yEmpty = yText.isEmpty;

      if (xEmpty != yEmpty) {
        errors[row.key] = 'Enter both X and Y, or leave both empty.';
        continue;
      }

      final x = _parseCoordinate(xText);
      final y = _parseCoordinate(yText);
      if (!xEmpty && (x == null || y == null)) {
        errors[row.key] = 'Use decimal numbers only.';
        continue;
      }

      updates.putIfAbsent(row.conveyor.id,
              () => <String, StationCoordinates>{})[row.station.id] =
          StationCoordinates(x: x, y: y);
    }

    if (errors.isNotEmpty) {
      setState(() => _errors
        ..clear()
        ..addAll(errors));
      return;
    }

    setState(() => _saving = true);
    try {
      await widget.service.updateStationCoordinates(
        factoryId: widget.factory.id,
        coordinates: updates,
      );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _dirty = false;
        _errors.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Station coordinates saved'),
          backgroundColor: _green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save coordinates: $e'),
          backgroundColor: _red,
        ),
      );
    }
  }

  void _applyDeltaSample() {
    for (final row in _rows) {
      final sample = _deltaSample[row.key];
      if (sample == null) continue;
      row.xController.text = sample[0].toStringAsFixed(3);
      row.yController.text = sample[1].toStringAsFixed(3);
    }
    setState(() {
      _dirty = true;
      _errors.clear();
    });
  }

  void _clearAll() {
    for (final row in _rows) {
      row.xController.clear();
      row.yController.clear();
    }
    setState(() {
      _dirty = true;
      _errors.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final groups = _rowsByConveyor;

    return Scaffold(
      backgroundColor: t.scaffold,
      appBar: AppBar(
        title: Text('Coordinates - ${widget.factory.name}'),
        actions: [
          if (_isDeltaFactory)
            TextButton.icon(
              onPressed: _saving ? null : _applyDeltaSample,
              icon: const Icon(Icons.auto_fix_high, size: 16),
              label: const Text('Prefill DELTA'),
            ),
          IconButton(
            tooltip: 'Clear all coordinates',
            onPressed: _saving ? null : _clearAll,
            icon: const Icon(Icons.cleaning_services_outlined),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          decoration: BoxDecoration(
            color: t.card,
            border: Border(top: BorderSide(color: t.border)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _dirty
                      ? 'Unsaved coordinate changes'
                      : 'Coordinates are ready',
                  style: TextStyle(
                    color: _dirty ? t.orange : t.green,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, size: 16),
                label: const Text('Close'),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: _saving ? null : _saveAll,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_alt_rounded, size: 16),
                label: const Text('Save All'),
              ),
            ],
          ),
        ),
      ),
      body: _rows.isEmpty
          ? Center(
              child: Text(
                'This factory has no stations yet.',
                style: TextStyle(color: t.muted),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                _CoordinateEditorHero(
                  factory: widget.factory,
                  mappedCount: _mappedCount,
                  totalCount: _rows.length,
                  hasErrors: _errors.isNotEmpty,
                ),
                const SizedBox(height: 14),
                ...groups.entries.map(
                  (entry) => _CoordinateConveyorGroup(
                    conveyor: entry.key,
                    rows: entry.value,
                    errors: _errors,
                    onChanged: _markDirty,
                  ),
                ),
              ],
            ),
    );
  }
}

class _CoordinateDraftRow {
  final Conveyor conveyor;
  final Station station;
  final TextEditingController xController;
  final TextEditingController yController;

  const _CoordinateDraftRow({
    required this.conveyor,
    required this.station,
    required this.xController,
    required this.yController,
  });

  String get key => '${conveyor.id}/${station.id}';

  void dispose() {
    xController.dispose();
    yController.dispose();
  }
}

class _CoordinateEditorHero extends StatelessWidget {
  final Factory factory;
  final int mappedCount;
  final int totalCount;
  final bool hasErrors;

  const _CoordinateEditorHero({
    required this.factory,
    required this.mappedCount,
    required this.totalCount,
    required this.hasErrors,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final progress = totalCount == 0 ? 0.0 : mappedCount / totalCount;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasErrors ? t.red.withValues(alpha: 0.5) : t.border,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 620;
          final metrics = Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _CoordinateMetric(
                icon: Icons.factory_outlined,
                label: factory.name,
                color: t.navy,
              ),
              _CoordinateMetric(
                icon: Icons.route_outlined,
                label: '${factory.conveyors.length} conveyors',
                color: t.blue,
              ),
              _CoordinateMetric(
                icon: Icons.pin_drop_outlined,
                label: '$mappedCount/$totalCount mapped',
                color: hasErrors ? t.red : t.green,
              ),
            ],
          );

          final text = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Station Coordinate Editor',
                style: TextStyle(
                  color: t.text,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Type measured X/Y metres for every station. Empty fields stay unset.',
                style: TextStyle(color: t.muted, fontSize: 12),
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  minHeight: 8,
                  value: progress.clamp(0.0, 1.0),
                  backgroundColor: t.border,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    hasErrors ? t.red : t.green,
                  ),
                ),
              ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                text,
                const SizedBox(height: 14),
                metrics,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: text),
              const SizedBox(width: 18),
              SizedBox(width: 290, child: metrics),
            ],
          );
        },
      ),
    );
  }
}

class _CoordinateMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _CoordinateMetric({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: context.isDark ? 0.14 : 0.09),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: t.text,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _CoordinateConveyorGroup extends StatelessWidget {
  final Conveyor conveyor;
  final List<_CoordinateDraftRow> rows;
  final Map<String, String> errors;
  final void Function(_CoordinateDraftRow row) onChanged;

  const _CoordinateConveyorGroup({
    required this.conveyor,
    required this.rows,
    required this.errors,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            decoration: BoxDecoration(
              color: t.navyLt.withValues(alpha: context.isDark ? 0.42 : 1),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Row(
              children: [
                Icon(Icons.linear_scale_rounded, color: t.navy, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Conveyor ${conveyor.number}',
                    style: TextStyle(
                      color: t.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Text(
                  '${rows.length} stations',
                  style: TextStyle(
                    color: t.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          ...rows.map(
            (row) => _CoordinateStationRow(
              row: row,
              error: errors[row.key],
              onChanged: () => onChanged(row),
            ),
          ),
        ],
      ),
    );
  }
}

class _CoordinateStationRow extends StatelessWidget {
  final _CoordinateDraftRow row;
  final String? error;
  final VoidCallback onChanged;

  const _CoordinateStationRow({
    required this.row,
    required this.error,
    required this.onChanged,
  });

  bool get _complete {
    return row.xController.text.trim().isNotEmpty &&
        row.yController.text.trim().isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.border)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 620;
          final identity = Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: error != null
                      ? t.redLt
                      : (_complete ? t.greenLt : t.scaffold),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: error != null
                        ? t.red
                        : (_complete ? t.green : t.border),
                  ),
                ),
                child: Text(
                  row.station.id.replaceFirst('station_', 'S'),
                  style: TextStyle(
                    color:
                        error != null ? t.red : (_complete ? t.green : t.muted),
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.station.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: t.text,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      row.station.assetId.trim().isEmpty
                          ? row.station.address
                          : '${row.station.assetId} - ${row.station.address}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: t.muted, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          );
          final fields = Row(
            children: [
              Expanded(
                child: _CoordinateTextField(
                  controller: row.xController,
                  label: 'X',
                  hasError: error != null,
                  onChanged: onChanged,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _CoordinateTextField(
                  controller: row.yController,
                  label: 'Y',
                  hasError: error != null,
                  onChanged: onChanged,
                ),
              ),
            ],
          );
          final status = _CoordinateStatusChip(
            complete: _complete,
            hasError: error != null,
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                identity,
                const SizedBox(height: 10),
                fields,
                if (error != null) ...[
                  const SizedBox(height: 6),
                  Text(error!, style: TextStyle(color: t.red, fontSize: 11)),
                ],
              ],
            );
          }

          return Row(
            children: [
              Expanded(flex: 3, child: identity),
              const SizedBox(width: 12),
              SizedBox(width: 260, child: fields),
              const SizedBox(width: 12),
              SizedBox(width: 94, child: status),
            ],
          );
        },
      ),
    );
  }
}

class _CoordinateTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool hasError;
  final VoidCallback onChanged;

  const _CoordinateTextField({
    required this.controller,
    required this.label,
    required this.hasError,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return TextField(
      controller: controller,
      onChanged: (_) => onChanged(),
      keyboardType: const TextInputType.numberWithOptions(
        signed: true,
        decimal: true,
      ),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[-0-9.,]')),
      ],
      decoration: InputDecoration(
        labelText: label,
        suffixText: 'm',
        isDense: true,
        filled: true,
        fillColor: t.scaffold,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: hasError ? t.red : t.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: hasError ? t.red : t.navy, width: 1.5),
        ),
      ),
      style: TextStyle(
        color: t.text,
        fontWeight: FontWeight.w800,
        fontFamily: 'monospace',
      ),
    );
  }
}

class _CoordinateStatusChip extends StatelessWidget {
  final bool complete;
  final bool hasError;

  const _CoordinateStatusChip({
    required this.complete,
    required this.hasError,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final color = hasError ? t.red : (complete ? t.green : t.muted);
    final label = hasError ? 'Check' : (complete ? 'Mapped' : 'Unset');
    final icon = hasError
        ? Icons.error_outline
        : (complete
            ? Icons.check_circle_outline
            : Icons.radio_button_unchecked);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: context.isDark ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: t.text,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
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
