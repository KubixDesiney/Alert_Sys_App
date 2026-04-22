import 'dart:async';
import 'package:flutter/material.dart';
import '../models/hierarchy_model.dart';
import '../services/hierarchy_service.dart';

const _navy = Color(0xFF0D4A75);
const _white = Colors.white;
const _bg = Color(0xFFF8FAFC);
const _border = Color(0xFFE2E8F0);
const _muted = Color(0xFF64748B);
const _green = Color(0xFF16A34A);
const _red = Color(0xFFDC2626);

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
            _selectedFactory = _factories.firstWhere((f) => f.id == _selectedFactory!.id);
            if (_selectedConveyor != null && !_selectedFactory!.conveyors.containsKey(_selectedConveyor!.id)) {
              _selectedConveyor = null;
            } else if (_selectedConveyor != null) {
              _selectedConveyor = _selectedFactory!.conveyors[_selectedConveyor!.id];
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
                  const Text('Add a new factory for Sagem'),
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
                      child: Text(error!, style: const TextStyle(color: _red, fontSize: 12)),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () async {
                  final name = nameController.text.trim();
                  final location = locationController.text.trim();
                  final numConveyors = int.tryParse(conveyorsController.text.trim());
                  if (name.isEmpty) {
                    setStateDialog(() => error = 'Factory name is required');
                    return;
                  }
                  if (numConveyors == null || numConveyors < 1) {
                    setStateDialog(() => error = 'Enter a valid number of conveyors (≥1)');
                    return;
                  }
                  final id = name.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
                  try {
                    await _service.addFactoryWithConveyors(id, name, location, numConveyors);
                    if (context.mounted) Navigator.pop(context);
                    _loadFactories(); // force refresh
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Factory added'), backgroundColor: _green),
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
          TextButton(onPressed: () => Navigator.pop(_), child: const Text('Cancel')),
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
            SnackBar(content: Text('Conveyor $newNumber added'), backgroundColor: _green),
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
    final controller = TextEditingController(text: _selectedConveyor!.number.toString());
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
          TextButton(onPressed: () => Navigator.pop(_), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(_, int.tryParse(controller.text)),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newNumber != null && newNumber != _selectedConveyor!.number) {
      await _service.updateConveyorNumber(_selectedFactory!.id, _selectedConveyor!.id, newNumber);
      _loadFactories();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Conveyor updated'), backgroundColor: _green),
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
            Text('Maximum: $remaining station(s)', style: const TextStyle(fontSize: 12, color: _muted)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(_), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final int? count = int.tryParse(controller.text);
              if (count != null && count > 0 && count <= remaining) {
                Navigator.pop(_, count);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Invalid number'), backgroundColor: _red),
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
        await _service.addStation(_selectedFactory!.id, _selectedConveyor!.id, stationNumber);
      }
      _loadFactories();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added $toAdd station(s)'), backgroundColor: _green),
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
        content: Text('Delete "${factory.name}" and all its conveyors/stations?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(_, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(_, true), style: ElevatedButton.styleFrom(backgroundColor: _red), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm == true) {
      await _service.deleteFactory(factory.id);
      _loadFactories();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Factory deleted'), backgroundColor: _red),
        );
      }
    }
  }

  // ------------------- Delete Conveyor -------------------
  Future<void> _deleteConveyor(Conveyor conveyor) async {
    if (_selectedFactory == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Conveyor'),
        content: Text('Delete Conveyor ${conveyor.number} and all its stations?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(_, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(_, true), style: ElevatedButton.styleFrom(backgroundColor: _red), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm == true) {
      await _service.deleteConveyor(_selectedFactory!.id, conveyor.id);
      _loadFactories();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Conveyor deleted'), backgroundColor: _red),
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
      backgroundColor: _bg,
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
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _navy),
            ),
            const Text(
              'Factory → Conveyor → Station — Sagem',
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
                        color: _white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _border),
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
                                  'Factories (${_factories.length})',
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _navy),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.add, size: 18, color: _green),
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
                                ? const Center(child: Text('No factories', style: TextStyle(color: _muted)))
                                : ListView.builder(
                                    itemCount: _factories.length,
                                    itemBuilder: (context, index) {
                                      final factory = _factories[index];
                                      final isSelected = _selectedFactory?.id == factory.id;
                                      return ListTile(
                                        selected: isSelected,
                                        selectedTileColor: _navy.withOpacity(0.1),
                                        title: Text(factory.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                        subtitle: Text('${factory.location} · ${factory.conveyors.length} conveyor(s)'),
                                        trailing: IconButton(
                                          icon: const Icon(Icons.delete_outline, size: 18, color: _red),
                                          onPressed: () => _deleteFactory(factory),
                                        ),
                                        onTap: () => setState(() {
                                          _selectedFactory = factory;
                                          _selectedConveyor = null;
                                        }),
                                      );
                                    },
                                  ),
                          ),
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
                        color: _white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _border),
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
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _navy),
                                ),
                                if (_selectedFactory != null)
                                  IconButton(
                                    icon: const Icon(Icons.add, size: 18, color: _green),
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
                                ? const Center(child: Text('Select a factory first', style: TextStyle(color: _muted)))
                                : conveyors.isEmpty
                                    ? const Center(child: Text('No conveyors', style: TextStyle(color: _muted)))
                                    : ListView.builder(
                                        itemCount: conveyors.length,
                                        itemBuilder: (context, index) {
                                          final conveyor = conveyors[index];
                                          final isSelected = _selectedConveyor?.id == conveyor.id;
                                          return ListTile(
                                            selected: isSelected,
                                            selectedTileColor: _navy.withOpacity(0.1),
                                            title: Text('Conveyor ${conveyor.number}'),
                                            subtitle: Text('${conveyor.stations.length}/${_service.maxStations} stations'),
                                            trailing: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                IconButton(
                                                  icon: const Icon(Icons.edit, size: 18),
                                                  onPressed: _showEditConveyorDialog,
                                                ),
                                                IconButton(
                                                  icon: const Icon(Icons.delete_outline, size: 18, color: _red),
                                                  onPressed: () => _deleteConveyor(conveyor),
                                                ),
                                              ],
                                            ),
                                            onTap: () => setState(() => _selectedConveyor = conveyor),
                                          );
                                        },
                                      ),
                          ),
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
                        color: _white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _border),
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
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _navy),
                                ),
                                if (_selectedConveyor != null && stations.length < _service.maxStations)
                                  IconButton(
                                    icon: const Icon(Icons.add, size: 18, color: _green),
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
                                ? const Center(child: Text('Select a conveyor first', style: TextStyle(color: _muted)))
                                : stations.isEmpty
                                    ? const Center(child: Text('No stations', style: TextStyle(color: _muted)))
                                    : ListView.builder(
                                        itemCount: stations.length,
                                        itemBuilder: (context, index) {
                                          final station = stations[index];
                                          return ListTile(
                                            title: Text(station.name),
                                            subtitle: Text(station.address, style: const TextStyle(fontSize: 11, color: _muted)),
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