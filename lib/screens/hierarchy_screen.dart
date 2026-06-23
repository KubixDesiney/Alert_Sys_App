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
import '../l10n/app_strings.dart';
import '../theme.dart';
import '../utils/google_maps_web_support.dart';
import '../utils/user_friendly_error.dart';
import '../widgets/common/app_loading_indicator.dart';
import 'factory_mapping_tab.dart';

part 'hierarchy_screen_dialogs.dart';

Color get _navy => brandPrimary(false);
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
        SnackBar(
          content: Text(context
              .tr('Select a valid station before generating a QR code.')),
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
            content: Text(context.tr('Could not create Asset ID: {error}',
                {'error': UserFriendlyError.message(e)}))),
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
                Text(context.tr('Relink Asset ID')),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: controller,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: context.tr('Asset ID'),
                    hintText: 'MACH-001',
                    border: const OutlineInputBorder(),
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
                child: Text(context.tr('Cancel')),
              ),
              FilledButton(
                onPressed: () {
                  final normalized = _service.normalizeAssetId(controller.text);
                  if (normalized.isEmpty) {
                    setStateDialog(
                        () => error = context.tr('Asset ID is required'));
                    return;
                  }
                  Navigator.pop(context, normalized);
                },
                child: Text(context.tr('Relink')),
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
          content: Text(context.tr('Could not delete station: {error}',
              {'error': UserFriendlyError.message(e)})),
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
                Text(context.tr('Move Station')),
              ],
            ),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('Current location'),
                    style: TextStyle(
                      color: t.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${currentFactory.name} > ${context.tr('Conveyor {n}', {
                          'n': '${currentConveyor.number}'
                        })} > ${station.name}',
                    style: TextStyle(color: t.muted),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    context.tr('Asset ID: {id}', {'id': assetId}),
                    style: TextStyle(
                      color: t.navy,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: destinationFactoryId,
                    decoration: InputDecoration(
                      labelText: context.tr('Destination Factory'),
                      border: const OutlineInputBorder(),
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
                    decoration: InputDecoration(
                      labelText: context.tr('Destination Conveyor'),
                      border: const OutlineInputBorder(),
                    ),
                    items: destinationConveyors
                        .map(
                          (conveyor) => DropdownMenuItem<String>(
                            value: conveyor.id,
                            child: Text(context.tr('Conveyor {n}',
                                {'n': '${conveyor.number}'})),
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
                        ? context.tr('Selected conveyor is full.')
                        : context.tr(
                            'The station will be placed in slot {n} and its address will be updated automatically.',
                            {'n': '$nextStationNumber'}),
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
                child: Text(context.tr('Cancel')),
              ),
              FilledButton(
                onPressed: moving
                    ? null
                    : () async {
                        if (destinationFactoryId == currentFactory.id &&
                            destinationConveyorId == currentConveyor.id) {
                          setStateDialog(() {
                            error =
                                context.tr('Select a different destination.');
                          });
                          return;
                        }
                        if (destinationConveyor == null) {
                          setStateDialog(() {
                            error =
                                context.tr('Select a destination conveyor.');
                          });
                          return;
                        }
                        if (nextStationNumber == null) {
                          setStateDialog(() {
                            error = context.tr(
                                'The selected conveyor has no free station slots.');
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
                    : Text(context.tr('Move')),
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
            title: Text(context.tr('Add Factory')),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(context.tr('Add a new factory')),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: context.tr('Factory Name'),
                      hintText: context.tr('Ex: Factory C'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: locationController,
                    decoration: InputDecoration(
                      labelText: context.tr('Address'),
                      hintText: context.tr('Ex: Casablanca'),
                      border: const OutlineInputBorder(),
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
                          ? context.tr('Map pin: {lat}, {lng}', {
                              'lat': selectedLocation.lat!.toStringAsFixed(5),
                              'lng': selectedLocation.lng!.toStringAsFixed(5)
                            })
                          : context.tr('Pick on map'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: conveyorsController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: context.tr('Number of Conveyors'),
                      hintText: context.tr('Ex: 3'),
                      border: const OutlineInputBorder(),
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
                  child: Text(context.tr('Cancel'))),
              ElevatedButton(
                onPressed: () async {
                  final name = nameController.text.trim();
                  final location = locationController.text.trim();
                  final numConveyors =
                      int.tryParse(conveyorsController.text.trim());
                  if (name.isEmpty) {
                    setStateDialog(
                        () => error = context.tr('Factory name is required'));
                    return;
                  }
                  if (numConveyors == null || numConveyors < 1) {
                    setStateDialog(() => error =
                        context.tr('Enter a valid number of conveyors (≥1)'));
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
                      SnackBar(
                          content: Text(context.tr('Factory added')),
                          backgroundColor: _green),
                    );
                  } catch (e) {
                    setStateDialog(() => error = e.toString());
                  }
                },
                child: Text(context.tr('Add Factory')),
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
            title: Text(context.tr('Edit Factory')),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: context.tr('Factory Name'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: locationController,
                    decoration: InputDecoration(
                      labelText: context.tr('Address'),
                      border: const OutlineInputBorder(),
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
                          ? context.tr('Map pin: {lat}, {lng}', {
                              'lat': selectedLocation.lat!.toStringAsFixed(5),
                              'lng': selectedLocation.lng!.toStringAsFixed(5)
                            })
                          : context.tr('Pick on map'),
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
                  child: Text(context.tr('Cancel'))),
              ElevatedButton(
                onPressed: () async {
                  final name = nameController.text.trim();
                  final address = locationController.text.trim();
                  if (name.isEmpty) {
                    setStateDialog(
                        () => error = context.tr('Factory name is required'));
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
                      SnackBar(
                          content: Text(context.tr('Factory updated')),
                          backgroundColor: _green),
                    );
                  } catch (e) {
                    setStateDialog(() => error = e.toString());
                  }
                },
                child: Text(context.tr('Save')),
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
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('Add Conveyor')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.tr('Enter conveyor number')),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration:
                  InputDecoration(labelText: context.tr('Conveyor Number')),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(context.tr('Cancel'))),
          ElevatedButton(
            onPressed: () =>
                Navigator.pop(dialogContext, int.tryParse(controller.text)),
            child: Text(context.tr('Add')),
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
                content: Text(context.tr('Conveyor {n} added',
                    {'n': '$newNumber'})),
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
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('Edit Conveyor')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.tr('Update the conveyor number')),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration:
                  InputDecoration(labelText: context.tr('Conveyor Number')),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(context.tr('Cancel'))),
          ElevatedButton(
            onPressed: () =>
                Navigator.pop(dialogContext, int.tryParse(controller.text)),
            child: Text(context.tr('Save')),
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
          SnackBar(
              content: Text(context.tr('Conveyor updated')),
              backgroundColor: _green),
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
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('Add Station')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.tr('Add stations to Conveyor {n}',
                {'n': '${_selectedConveyor!.number}'})),
            const SizedBox(height: 8),
            Text(context.tr('Current stations: {count}/{max}',
                {'count': '$currentCount', 'max': '${_service.maxStations}'})),
            Text(context.tr('Remaining: {n}', {'n': '$remaining'})),
            const SizedBox(height: 12),
            Text(context.tr('Number of Stations to Add')),
            const SizedBox(height: 4),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(hintText: context.tr('Ex: 2')),
            ),
            Text(
                context.tr('Maximum: {n} station(s)', {'n': '$remaining'}),
                style: const TextStyle(fontSize: 12, color: _muted)),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(context.tr('Cancel'))),
          ElevatedButton(
            onPressed: () {
              final int? count = int.tryParse(controller.text);
              if (count != null && count > 0 && count <= remaining) {
                Navigator.pop(dialogContext, count);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text(context.tr('Invalid number')),
                      backgroundColor: _red),
                );
              }
            },
            child: Text(context.tr('Add')),
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
              content: Text(context.tr('Added {n} station(s)',
                  {'n': '$toAdd'})),
              backgroundColor: _green),
        );
      }
    }
  }

  // ------------------- Delete Factory -------------------
  Future<void> _deleteFactory(Factory factory) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('Delete Factory')),
        content: Text(context.tr(
            'Delete "{name}" and all its conveyors/stations?',
            {'name': factory.name})),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(context.tr('Cancel'))),
          ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: ElevatedButton.styleFrom(backgroundColor: _red),
              child: Text(context.tr('Delete'))),
        ],
      ),
    );
    if (confirm == true) {
      await _service.deleteFactory(factory.id);
      _loadFactories();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(context.tr('Factory deleted')),
              backgroundColor: _red),
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
            context.tr(
                'Cannot delete Conveyor {n}: {count} active alert(s) are still disponible/en_cours.',
                {'n': '${conveyor.number}', 'count': '$activeAlerts'}),
          ),
          backgroundColor: _red,
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('Delete Conveyor')),
        content: Text(context.tr(
            'Delete Conveyor {n} and all its stations?',
            {'n': '${conveyor.number}'})),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(context.tr('Cancel'))),
          ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: ElevatedButton.styleFrom(backgroundColor: _red),
              child: Text(context.tr('Delete'))),
        ],
      ),
    );
    if (confirm == true) {
      await _service.deleteConveyor(_selectedFactory!.id, conveyor.id);
      _loadFactories();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(context.tr('Conveyor deleted')),
              backgroundColor: _red),
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
                  Text(context.tr('Hierarchy'),
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: t.navy)),
                  Text(context.tr('Structure & factory floor map'),
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
                  tabs: [
                    Tab(
                        icon: const Icon(Icons.account_tree_outlined, size: 18),
                        text: context.tr('Structure')),
                    Tab(
                        icon: const Icon(Icons.map_rounded, size: 18),
                        text: context.tr('Factory Mapping')),
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
                                  context.tr('Factories ({n})',
                                      {'n': '${_factories.length}'}),
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: _navy),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.add,
                                    size: 18, color: _green),
                                onPressed: _showAddFactoryDialog,
                                tooltip: context.tr('Add Factory'),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        Expanded(
                            child: _factories.isEmpty
                                ? Center(
                                    child: Text(context.tr('No factories'),
                                        style: const TextStyle(color: _muted)))
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
                                context.tr('Conveyors ({n})',
                                    {'n': '${conveyors.length}'}),
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: _navy),
                              ),
                              if (_selectedFactory != null)
                                IconButton(
                                  icon: const Icon(Icons.add,
                                      size: 18, color: _green),
                                  onPressed: _showAddConveyorDialog,
                                  tooltip: context.tr('Add Conveyor'),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        Expanded(
                            child: _selectedFactory == null
                                ? Center(
                                    child: Text(
                                        context.tr('Select a factory first'),
                                        style: const TextStyle(color: _muted)))
                                : conveyors.isEmpty
                                    ? Center(
                                        child: Text(context.tr('No conveyors'),
                                            style:
                                                const TextStyle(color: _muted)))
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
                                context.tr('Stations ({count}/{max})', {
                                  'count': '${stations.length}',
                                  'max': '${_service.maxStations}'
                                }),
                                style: TextStyle(
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
                                  tooltip: context.tr('Add Stations'),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: _selectedConveyor == null
                              ? Center(
                                  child: Text(
                                      context.tr('Select a conveyor first'),
                                      style: const TextStyle(color: _muted)))
                              : stations.isEmpty
                                  ? Center(
                                      child: Text(context.tr('No stations'),
                                          style:
                                              const TextStyle(color: _muted)))
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
                                                  label: Text(context.tr('Move')),
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
                                                      context.tr('Generate station QR'),
                                                  onTap: () =>
                                                      _showStationQrDialog(
                                                          station),
                                                ),
                                                const SizedBox(height: 2),
                                                _StationActionIcon(
                                                  icon: Icons.delete_outline,
                                                  color: _red,
                                                  tooltip: context.tr('Delete station'),
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

