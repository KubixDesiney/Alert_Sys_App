import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:file_saver/file_saver.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../models/hierarchy_model.dart';
import '../services/hierarchy_service.dart';
import '../theme.dart';
import '../utils/google_maps_web_support.dart';
import '../utils/user_friendly_error.dart';
import '../widgets/common/app_loading_indicator.dart';
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
        SnackBar(
            content: Text(
                'Could not create Asset ID: ${UserFriendlyError.message(e)}')),
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
        SnackBar(
            content: Text(
                'Could not relink asset: ${UserFriendlyError.message(e)}')),
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

  Future<void> _deleteStation(Station station) async {
    final factory = _selectedFactory;
    final conveyor = _selectedConveyor;
    final stationNumber = _stationNumber(station);
    if (factory == null || conveyor == null || stationNumber == null) {
      return;
    }

    final activeAlerts = await _service.getActiveAlertsCountForStation(
      usine: factory.name,
      convoyeur: conveyor.number,
      poste: stationNumber,
    );

    if (activeAlerts > 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Cannot delete ${station.name}: $activeAlerts active alert(s) are still disponible/en_cours for this location.',
          ),
          backgroundColor: _red,
        ),
      );
      return;
    }

    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => _StationDeleteDialog(
        stationName: station.name,
        stationId: station.id,
        stationNumber: stationNumber,
        stationAddress: station.address,
        assetId: station.assetId.trim(),
        factoryName: factory.name,
        factoryId: factory.id,
        conveyorNumber: conveyor.number,
        conveyorId: conveyor.id,
      ),
    );

    if (confirm != true) return;

    try {
      await _service.deleteStation(
        factoryId: factory.id,
        factoryName: factory.name,
        conveyorId: conveyor.id,
        conveyorNumber: conveyor.number,
        station: station,
      );
      _loadFactories();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            station.assetId.trim().isEmpty
                ? '${station.name} deleted from the hierarchy.'
                : '${station.name} deleted. Asset ${station.assetId.trim()} was preserved in the database.',
          ),
          backgroundColor: _green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('Could not delete station: ${UserFriendlyError.message(e)}'),
          backgroundColor: _red,
        ),
      );
    }
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
  Future<FactoryLocationSelection?> _openFactoryLocationPicker(
      FactoryLocationSelection initialSelection) {
    return showDialog<FactoryLocationSelection>(
      context: context,
      useSafeArea: false,
      builder: (_) => FactoryLocationPicker(
        initialSelection: initialSelection,
        onCancel: () => Navigator.of(context).pop(),
        onSave: (selection) => Navigator.of(context).pop(selection),
      ),
    );
  }

  Future<FactoryLocationSelection> _factorySelectionFor(Factory factory) async {
    try {
      final metadata = await _service.getFactoryLocationMetadata(factory.id);
      final lat = metadata?['lat'] as double?;
      final lng = metadata?['lng'] as double?;
      final address =
          (metadata?['address']?.toString().trim().isNotEmpty ?? false)
              ? metadata!['address'].toString()
              : factory.location;
      return FactoryLocationSelection(lat: lat, lng: lng, address: address);
    } catch (_) {
      return FactoryLocationSelection(address: factory.location);
    }
  }

  Future<void> _showAddFactoryDialog() async {
    final nameController = TextEditingController();
    final locationController = TextEditingController();
    final conveyorsController = TextEditingController();
    var selectedLocation = const FactoryLocationSelection(address: '');
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
                      labelText: 'Address',
                      hintText: 'Ex: Casablanca',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await _openFactoryLocationPicker(
                        selectedLocation.copyWith(
                          address: locationController.text.trim(),
                        ),
                      );
                      if (picked == null) return;
                      setStateDialog(() {
                        selectedLocation = picked;
                        if (picked.address.trim().isNotEmpty) {
                          locationController.text = picked.address.trim();
                        }
                      });
                    },
                    icon: const Icon(Icons.map_outlined),
                    label: Text(
                      selectedLocation.hasCoordinates
                          ? 'Map pin: ${selectedLocation.lat!.toStringAsFixed(5)}, ${selectedLocation.lng!.toStringAsFixed(5)}'
                          : 'Pick on map',
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
                      id,
                      name,
                      location,
                      numConveyors,
                      lat: selectedLocation.lat,
                      lng: selectedLocation.lng,
                      address: location,
                    );
                    if (!context.mounted) return;
                    Navigator.pop(context);
                    _loadFactories(); // force refresh
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Factory added'),
                          backgroundColor: _green),
                    );
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

  Future<void> _showEditFactoryDialog(Factory factory) async {
    final nameController = TextEditingController(text: factory.name);
    final locationController = TextEditingController(text: factory.location);
    var selectedLocation = await _factorySelectionFor(factory);
    if (selectedLocation.address.trim().isNotEmpty) {
      locationController.text = selectedLocation.address.trim();
    }
    String? error;

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: const Text('Edit Factory'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Factory Name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: locationController,
                    decoration: const InputDecoration(
                      labelText: 'Address',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await _openFactoryLocationPicker(
                        selectedLocation.copyWith(
                          address: locationController.text.trim(),
                        ),
                      );
                      if (picked == null) return;
                      setStateDialog(() {
                        selectedLocation = picked;
                        if (picked.address.trim().isNotEmpty) {
                          locationController.text = picked.address.trim();
                        }
                      });
                    },
                    icon: const Icon(Icons.map_outlined),
                    label: Text(
                      selectedLocation.hasCoordinates
                          ? 'Map pin: ${selectedLocation.lat!.toStringAsFixed(5)}, ${selectedLocation.lng!.toStringAsFixed(5)}'
                          : 'Pick on map',
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
                  final address = locationController.text.trim();
                  if (name.isEmpty) {
                    setStateDialog(() => error = 'Factory name is required');
                    return;
                  }
                  try {
                    await _service.updateFactoryDetails(
                      factoryId: factory.id,
                      name: name,
                      address: address,
                      lat: selectedLocation.lat,
                      lng: selectedLocation.lng,
                    );
                    if (!context.mounted) return;
                    Navigator.pop(context);
                    _loadFactories();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Factory updated'),
                          backgroundColor: _green),
                    );
                  } catch (e) {
                    setStateDialog(() => error = e.toString());
                  }
                },
                child: const Text('Save'),
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
            SnackBar(
                content: Text(UserFriendlyError.message(e)),
                backgroundColor: _red),
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
      return const AppLoadingIndicator();
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
                  FactoryMappingTab(factories: _factories, service: _service),
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
                                              color: isSelected ? _navy : null,
                                            ),
                                          ),
                                          subtitle: Text(
                                            '${factory.location} · ${factory.conveyors.length} conveyor(s)',
                                            style: const TextStyle(
                                                fontSize: 12, color: _muted),
                                          ),
                                          trailing: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              IconButton(
                                                icon: const Icon(Icons.edit,
                                                    size: 18),
                                                onPressed: () =>
                                                    _showEditFactoryDialog(
                                                        factory),
                                              ),
                                              IconButton(
                                                icon: const Icon(
                                                    Icons.delete_outline,
                                                    size: 18,
                                                    color: _red),
                                                onPressed: () =>
                                                    _deleteFactory(factory),
                                              ),
                                            ],
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
                                                  color:
                                                      isSelected ? _navy : null,
                                                ),
                                              ),
                                              subtitle: Text(
                                                '${conveyor.stations.length}/${_service.maxStations} stations',
                                                style: const TextStyle(
                                                    fontSize: 12,
                                                    color: _muted),
                                              ),
                                              trailing: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  IconButton(
                                                    icon: const Icon(Icons.edit,
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
                                                  _selectedConveyor = conveyor),
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
                                          isThreeLine: true,
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 4,
                                          ),
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
                                            ],
                                          ),
                                          trailing: SizedBox(
                                            width: 24,
                                            child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                _StationActionIcon(
                                                  icon: Icons.qr_code_2,
                                                  color: _navy,
                                                  tooltip:
                                                      'Generate station QR',
                                                  onTap: () =>
                                                      _showStationQrDialog(
                                                          station),
                                                ),
                                                const SizedBox(height: 2),
                                                _StationActionIcon(
                                                  icon: Icons.delete_outline,
                                                  color: _red,
                                                  tooltip: 'Delete station',
                                                  onTap: () =>
                                                      _deleteStation(station),
                                                ),
                                              ],
                                            ),
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

class _StationDeleteDialog extends StatelessWidget {
  final String stationName;
  final String stationId;
  final int stationNumber;
  final String stationAddress;
  final String assetId;
  final String factoryName;
  final String factoryId;
  final int conveyorNumber;
  final String conveyorId;

  const _StationDeleteDialog({
    required this.stationName,
    required this.stationId,
    required this.stationNumber,
    required this.stationAddress,
    required this.assetId,
    required this.factoryName,
    required this.factoryId,
    required this.conveyorNumber,
    required this.conveyorId,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final preservedAssetLabel =
        assetId.isEmpty ? 'No Asset ID linked yet' : assetId;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Material(
          color: t.card,
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      t.red.withValues(alpha: 0.14),
                      t.orange.withValues(alpha: 0.12),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: t.red.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                        border:
                            Border.all(color: t.red.withValues(alpha: 0.22)),
                      ),
                      child: Icon(
                        Icons.delete_forever_outlined,
                        color: t.red,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Delete Station',
                            style: TextStyle(
                              color: t.text,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'This removes the station from the hierarchy while keeping the asset record archived in the database.',
                            style: TextStyle(
                              color: t.muted,
                              fontSize: 13,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      tooltip: 'Close',
                      icon: Icon(Icons.close, color: t.muted),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: t.scaffold,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: t.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            stationName,
                            style: TextStyle(
                              color: t.text,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$factoryName  •  Conveyor $conveyorNumber  •  Post $stationNumber',
                            style: TextStyle(
                              color: t.muted,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 16),
                          _DeleteDetailRow(
                              label: 'Factory',
                              value: '$factoryName ($factoryId)'),
                          _DeleteDetailRow(
                            label: 'Conveyor',
                            value: 'Conveyor $conveyorNumber ($conveyorId)',
                          ),
                          _DeleteDetailRow(
                            label: 'Station',
                            value: '$stationName ($stationId)',
                          ),
                          _DeleteDetailRow(
                            label: 'Address',
                            value: stationAddress,
                          ),
                          _DeleteDetailRow(
                            label: 'Asset Record',
                            value: preservedAssetLabel,
                            emphasize: assetId.isNotEmpty,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: t.red.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                        border:
                            Border.all(color: t.red.withValues(alpha: 0.18)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: t.red,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              assetId.isEmpty
                                  ? 'The hierarchy entry will be removed immediately.'
                                  : 'Asset $assetId will stay under /assets with its last known location and deletion metadata.',
                              style: TextStyle(
                                color: t.text,
                                fontSize: 12.5,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(22, 14, 22, 18),
                decoration: BoxDecoration(
                  color: t.scaffold,
                  border: Border(top: BorderSide(color: t.border)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => Navigator.of(context).pop(true),
                        style: FilledButton.styleFrom(
                          backgroundColor: t.red,
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('Delete Station'),
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

class _DeleteDetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasize;

  const _DeleteDetailRow({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: TextStyle(
                color: t.muted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: emphasize ? t.navy : t.text,
                fontSize: 12.5,
                fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StationActionIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  const _StationActionIcon({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 22,
            height: 22,
            child: Icon(icon, size: 16, color: color),
          ),
        ),
      ),
    );
  }
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
        SnackBar(
            content: Text('Download failed: ${UserFriendlyError.message(e)}')),
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
        SnackBar(
            content: Text('Print failed: ${UserFriendlyError.message(e)}')),
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

class FactoryLocationSelection {
  final double? lat;
  final double? lng;
  final String address;

  const FactoryLocationSelection({
    this.lat,
    this.lng,
    required this.address,
  });

  bool get hasCoordinates => lat != null && lng != null;

  FactoryLocationSelection copyWith({
    double? lat,
    double? lng,
    String? address,
    bool clearCoordinates = false,
  }) {
    return FactoryLocationSelection(
      lat: clearCoordinates ? null : lat ?? this.lat,
      lng: clearCoordinates ? null : lng ?? this.lng,
      address: address ?? this.address,
    );
  }
}

class _LocationSearchSuggestion {
  final String displayName;
  final String cityCountry;
  final LatLng point;

  const _LocationSearchSuggestion({
    required this.displayName,
    required this.cityCountry,
    required this.point,
  });
}

class FactoryLocationPicker extends StatefulWidget {
  final FactoryLocationSelection initialSelection;
  final VoidCallback onCancel;
  final ValueChanged<FactoryLocationSelection> onSave;
  final bool renderPlatformMap;

  const FactoryLocationPicker({
    super.key,
    required this.initialSelection,
    required this.onCancel,
    required this.onSave,
    this.renderPlatformMap = true,
  });

  @override
  State<FactoryLocationPicker> createState() => _FactoryLocationPickerState();
}

class _FactoryLocationPickerState extends State<FactoryLocationPicker> {
  static const LatLng _defaultTarget = LatLng(33.5731, -7.5898);

  late final TextEditingController _searchController;
  GoogleMapController? _mapController;
  LatLng? _selectedLatLng;
  String _address = '';
  String? _error;
  Timer? _searchDebounce;
  List<_LocationSearchSuggestion> _suggestions = [];
  bool _searching = false;
  bool _loadingSuggestions = false;

  @override
  void initState() {
    super.initState();
    _address = widget.initialSelection.address;
    _searchController = TextEditingController(text: _address);
    if (widget.initialSelection.hasCoordinates) {
      _selectedLatLng = LatLng(
        widget.initialSelection.lat!,
        widget.initialSelection.lng!,
      );
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  LatLng get _cameraTarget => _selectedLatLng ?? _defaultTarget;

  Set<Marker> get _markers {
    final point = _selectedLatLng;
    if (point == null) return {};
    return {
      Marker(
        markerId: const MarkerId('factory-location-pin'),
        position: point,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(
          title: 'Selected location',
          snippet: _displayLocationLabel,
        ),
      ),
    };
  }

  Future<void> _searchAddress() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _searching = true;
      _error = null;
      _suggestions = [];
    });
    try {
      final suggestion = await _bestLocationSuggestion(query);
      if (suggestion == null) {
        setState(() => _error = 'Address not found');
        return;
      }
      await _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(suggestion.point, 15),
      );
      await _selectSuggestion(suggestion, animate: false);
    } catch (e) {
      setState(() => _error = 'Could not search address');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<_LocationSearchSuggestion?> _bestLocationSuggestion(
      String query) async {
    final suggestions = await _fetchLocationSuggestions(query, limit: 1);
    if (suggestions.isNotEmpty) return suggestions.first;

    try {
      final locations = await geo.locationFromAddress(query);
      if (locations.isNotEmpty) {
        final first = locations.first;
        final point = LatLng(first.latitude, first.longitude);
        final cityCountry =
            await _reverseGeocodeCityCountry(point) ?? query.trim();
        return _LocationSearchSuggestion(
          displayName: query.trim(),
          cityCountry: cityCountry,
          point: point,
        );
      }
    } catch (_) {}

    return null;
  }

  Future<List<_LocationSearchSuggestion>> _fetchLocationSuggestions(
    String query, {
    int limit = 6,
  }) async {
    final normalized = query.trim();
    if (normalized.length < 3) return [];
    final googleSuggestions = await googleMapsWebLocationSuggestions(
      normalized,
      limit: limit,
    );
    if (googleSuggestions.isNotEmpty) {
      return googleSuggestions
          .map(
            (suggestion) => _LocationSearchSuggestion(
              displayName: suggestion.displayName,
              cityCountry: suggestion.cityCountry,
              point: LatLng(suggestion.lat, suggestion.lng),
            ),
          )
          .toList();
    }

    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'format': 'json',
        'addressdetails': '1',
        'limit': '$limit',
        'q': normalized,
      });
      final response = await http.get(uri);
      if (response.statusCode != 200) return [];
      final data = jsonDecode(response.body);
      if (data is! List) return [];
      final suggestions = <_LocationSearchSuggestion>[];
      for (final item in data) {
        if (item is! Map) continue;
        final map = Map<Object?, Object?>.from(item);
        final lat = double.tryParse(map['lat']?.toString() ?? '');
        final lon = double.tryParse(map['lon']?.toString() ?? '');
        if (lat == null || lon == null) continue;
        final address = map['address'] is Map
            ? Map<Object?, Object?>.from(map['address'] as Map)
            : const <Object?, Object?>{};
        final cityCountry = _cityCountryFromAddressMap(address);
        suggestions.add(
          _LocationSearchSuggestion(
            displayName: map['display_name']?.toString() ?? query.trim(),
            cityCountry: cityCountry.isNotEmpty ? cityCountry : normalized,
            point: LatLng(lat, lon),
          ),
        );
      }
      return suggestions;
    } catch (_) {
      return [];
    }
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    final query = value.trim();
    if (query.length < 3) {
      setState(() {
        _suggestions = [];
        _loadingSuggestions = false;
      });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 350), () async {
      if (!mounted) return;
      setState(() {
        _loadingSuggestions = true;
        _error = null;
      });
      final suggestions = await _fetchLocationSuggestions(query);
      if (!mounted || _searchController.text.trim() != query) return;
      setState(() {
        _suggestions = suggestions;
        _loadingSuggestions = false;
      });
    });
  }

  Future<void> _selectSuggestion(
    _LocationSearchSuggestion suggestion, {
    bool animate = true,
  }) async {
    _searchDebounce?.cancel();
    FocusScope.of(context).unfocus();
    if (animate) {
      await _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(suggestion.point, 15),
      );
    }
    if (!mounted) return;
    setState(() {
      _selectedLatLng = suggestion.point;
      _address = suggestion.cityCountry;
      _searchController.text = suggestion.cityCountry;
      _suggestions = [];
      _error = null;
    });
  }

  Future<void> _dropPin(LatLng point) async {
    setState(() {
      _selectedLatLng = point;
      _error = null;
      _suggestions = [];
    });
    final formatted = await _reverseGeocodeCityCountry(point);
    if (!mounted) return;
    setState(() {
      _address = formatted ?? _fallbackLocationLabel();
      _searchController.text = _address;
    });
  }

  Future<void> _dropPinFromScreenOffset(Offset offset) async {
    final controller = _mapController;
    if (controller == null) return;
    final point = await controller.getLatLng(
      ScreenCoordinate(x: offset.dx.round(), y: offset.dy.round()),
    );
    await _dropPin(point);
  }

  void _clearPin() {
    if (_selectedLatLng == null) return;
    setState(() {
      _selectedLatLng = null;
      _error = null;
    });
  }

  Future<String?> _reverseGeocodeCityCountry(LatLng point) async {
    final googleFormatted = await googleMapsWebReverseGeocodeCityCountry(
      point.latitude,
      point.longitude,
    );
    if (googleFormatted != null && googleFormatted.trim().isNotEmpty) {
      return googleFormatted.trim();
    }

    try {
      final marks =
          await geo.placemarkFromCoordinates(point.latitude, point.longitude);
      if (marks.isNotEmpty) {
        final formatted = _formatPlacemark(marks.first);
        if (formatted.isNotEmpty) return formatted;
      }
    } catch (_) {}

    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'format': 'json',
        'addressdetails': '1',
        'lat': point.latitude.toString(),
        'lon': point.longitude.toString(),
      });
      final response = await http.get(uri);
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body);
      if (data is! Map || data['address'] is! Map) return null;
      final address = Map<Object?, Object?>.from(data['address'] as Map);
      final formatted = _cityCountryFromAddressMap(address);
      return formatted.isEmpty ? null : formatted;
    } catch (_) {
      return null;
    }
  }

  String _formatPlacemark(geo.Placemark mark) {
    String city = '';
    for (final candidate in [
      mark.locality,
      mark.subAdministrativeArea,
      mark.administrativeArea,
    ]) {
      final normalized = (candidate ?? '').trim();
      if (normalized.isNotEmpty) {
        city = normalized;
        break;
      }
    }
    final country = (mark.country ?? '').trim();
    final parts = <String>[];
    if (city.isNotEmpty) parts.add(city);
    if (country.isNotEmpty && !parts.contains(country)) parts.add(country);
    return parts.join(', ');
  }

  String _cityCountryFromAddressMap(Map<Object?, Object?> address) {
    final city = [
      address['city'],
      address['town'],
      address['village'],
      address['municipality'],
      address['county'],
      address['state'],
    ]
        .map((value) => (value ?? '').toString().trim())
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    final country = (address['country'] ?? '').toString().trim();
    final parts = <String>[];
    if (city.isNotEmpty) parts.add(city);
    if (country.isNotEmpty && !parts.contains(country)) parts.add(country);
    return parts.join(', ');
  }

  String _fallbackLocationLabel() {
    final typed = _searchController.text.trim();
    return typed.isNotEmpty ? typed : 'Selected location';
  }

  String get _displayLocationLabel {
    final address = _address.trim();
    if (address.isNotEmpty) return address;
    return _selectedLatLng == null ? 'No location selected' : 'Selected location';
  }

  void _save() {
    final point = _selectedLatLng;
    widget.onSave(
      FactoryLocationSelection(
        lat: point?.latitude,
        lng: point?.longitude,
        address: _address.trim().isNotEmpty
            ? _address.trim()
            : _searchController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final point = _selectedLatLng;
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Factory Location'),
          actions: [
            TextButton(
              onPressed: widget.onCancel,
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: _save,
              child: const Text('Save'),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('factory-location-search-bar'),
                      controller: _searchController,
                      textInputAction: TextInputAction.search,
                      onChanged: _onSearchChanged,
                      onSubmitted: (_) => _searchAddress(),
                      decoration: const InputDecoration(
                        labelText: 'Search address',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.search),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    onPressed: _searching ? null : _searchAddress,
                    icon: _searching
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.search),
                    tooltip: 'Search',
                  ),
                  if (point != null) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _clearPin,
                      icon: const Icon(Icons.close),
                      tooltip: 'Clear location',
                    ),
                  ],
                ],
              ),
            ),
            if (_loadingSuggestions)
              const LinearProgressIndicator(minHeight: 2),
            if (_suggestions.isNotEmpty)
              Container(
                constraints: const BoxConstraints(maxHeight: 220),
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _suggestions.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, color: Theme.of(context).dividerColor),
                  itemBuilder: (context, index) {
                    final suggestion = _suggestions[index];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.place_outlined),
                      title: Text(
                        suggestion.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        suggestion.cityCountry,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => _selectSuggestion(suggestion),
                    );
                  },
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(left: 12, right: 12, bottom: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(_error!,
                      style: const TextStyle(color: _red, fontSize: 12)),
                ),
              ),
            Expanded(
              child: FactoryLocationMap(
                key: const Key('factory-location-map'),
                initialTarget: _cameraTarget,
                markers: _markers,
                renderPlatformMap: widget.renderPlatformMap,
                onMapCreated: (controller) {
                  _mapController = controller;
                },
                onLongPress: _dropPin,
                onTap: _dropPin,
                onSecondaryTap: _dropPinFromScreenOffset,
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(
                  top: BorderSide(color: Theme.of(context).dividerColor),
                ),
              ),
              child: Text(
                _displayLocationLabel,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FactoryLocationMap extends StatelessWidget {
  final LatLng initialTarget;
  final Set<Marker> markers;
  final ValueChanged<GoogleMapController> onMapCreated;
  final ValueChanged<LatLng> onLongPress;
  final ValueChanged<LatLng> onTap;
  final Future<void> Function(Offset offset) onSecondaryTap;
  final bool renderPlatformMap;

  const FactoryLocationMap({
    super.key,
    required this.initialTarget,
    required this.markers,
    required this.onMapCreated,
    required this.onLongPress,
    required this.onTap,
    required this.onSecondaryTap,
    this.renderPlatformMap = true,
  });

  @override
  Widget build(BuildContext context) {
    final showLiveMap = renderPlatformMap && isGoogleMapsJsLoaded;
    return Listener(
      onPointerDown: (event) {
        if (event.buttons == kSecondaryMouseButton) {
          unawaited(onSecondaryTap(event.localPosition));
        }
      },
      child: showLiveMap
          ? GoogleMap(
              initialCameraPosition: CameraPosition(
                target: initialTarget,
                zoom: 12,
              ),
              markers: markers,
              onMapCreated: onMapCreated,
              onLongPress: onLongPress,
              onTap: onTap,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: true,
            )
          : ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    renderPlatformMap
                        ? 'Interactive map unavailable on web. Search for an address or load the Google Maps JavaScript API to enable map preview.'
                        : 'Map preview disabled for this build.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ),
            ),
    );
  }
}
