// lib/screens/alert_tree_visualization.dart
import 'package:flutter/material.dart';
import '../services/hierarchy_service.dart';
import '../services/auth_service.dart';
import '../models/alert_model.dart';

// Color palette matching the app theme
const _navy = Color(0xFF0D4A75);
const _red = Color(0xFFDC2626);
const _white = Colors.white;
const _bg = Color(0xFFF8FAFC);
const _border = Color(0xFFE2E8F0);
const _muted = Color(0xFF64748B);
const _green = Color(0xFF16A34A);
const _orange = Color(0xFFEA580C);
const _blue = Color(0xFF2563EB);

class AlertNode {
  final String id;
  final String label;
  final int errorCount;
  final List<AlertNode> children;
  final Map<String, dynamic>? alertData;
  final String type; // 'usine', 'conveyor', 'workstation'

  AlertNode({
    required this.id,
    required this.label,
    this.errorCount = 0,
    this.children = const [],
    this.alertData,
    required this.type,
  });

  bool get hasError => errorCount > 0;
}

class AlertTreeVisualization extends StatefulWidget {
  final List<AlertModel> alerts;

  const AlertTreeVisualization({super.key, required this.alerts});

  @override
  State<AlertTreeVisualization> createState() => _AlertTreeVisualizationState();
}

class _AlertTreeVisualizationState extends State<AlertTreeVisualization>
    with TickerProviderStateMixin {
  List<AlertNode> _usines = [];
  AlertNode? _selectedUsine;
  AlertNode? _selectedConveyor;
  AlertNode? _selectedWorkstation;
  Map<String, dynamic>? _popupAlertData;
  Offset? _popupPosition;

  late AnimationController _zoomController;
  late AnimationController _detailController;
  late AnimationController _pulseController;
  late Animation<double> _zoomAnimation;
  late Animation<double> _detailAnimation;

  final HierarchyService _hierarchyService = HierarchyService();
  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    _buildHierarchy();

    _zoomController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _detailController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _zoomAnimation = CurvedAnimation(
      parent: _zoomController,
      curve: Curves.easeInOutCubic,
    );

    _detailAnimation = CurvedAnimation(
      parent: _detailController,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void didUpdateWidget(AlertTreeVisualization oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.alerts != oldWidget.alerts) {
      _buildHierarchy();
    }
  }

  void _buildHierarchy() {
    _hierarchyService.getFactories().listen((factories) {
      // Build alert counts per location (usine|conveyor|workstation)
      final Map<String, int> alertCounts = {};
      final Map<String, Map<String, dynamic>> firstAlertData = {};

      for (var alert in widget.alerts) {
        if (alert.status == 'disponible' || alert.status == 'en_cours') {
          final key = '${alert.usine}|${alert.convoyeur}|${alert.poste}';
          alertCounts[key] = (alertCounts[key] ?? 0) + 1;
          if (!firstAlertData.containsKey(key)) {
            firstAlertData[key] = _alertToMap(alert);
          }
        }
      }

      final usineNodes = factories.map((factory) {
        final conveyorNodes = factory.conveyors.values.map((conveyor) {
          final stationNodes = conveyor.stations.values.map((station) {
            final stationNumber = int.tryParse(station.id.replaceAll('station_', '')) ?? 0;
            final key = '${factory.name}|${conveyor.number}|$stationNumber';
            final errorCount = alertCounts[key] ?? 0;
            return AlertNode(
              id: '${factory.id}|${conveyor.id}|${station.id}',
              label: station.name,
              errorCount: errorCount,
              alertData: errorCount > 0 ? firstAlertData[key] : null,
              type: 'workstation',
            );
          }).toList();

          final conveyorErrorCount = stationNodes.fold<int>(0, (sum, s) => sum + s.errorCount);
          return AlertNode(
            id: '${factory.id}|${conveyor.id}',
            label: 'Conveyor ${conveyor.number}',
            errorCount: conveyorErrorCount,
            children: stationNodes.toList(),
            type: 'conveyor',
          );
        }).toList();

        final factoryErrorCount = conveyorNodes.fold<int>(0, (sum, c) => sum + c.errorCount);
        return AlertNode(
          id: factory.id,
          label: factory.name,
          errorCount: factoryErrorCount,
          children: conveyorNodes.toList(),
          type: 'usine',
        );
      }).toList();

      setState(() {
        _usines = usineNodes;
      });
    });
  }

  Map<String, dynamic> _alertToMap(AlertModel alert) {
    return {
      'id': alert.id,
      'type': alert.type,
      'status': alert.status,
      'description': alert.description,
      'usine': alert.usine,
      'convoyeur': alert.convoyeur,
      'poste': alert.poste,
      'superviseurId': alert.superviseurId,
      'superviseurName': alert.superviseurName,
      'assistantId': alert.assistantId,
      'assistantName': alert.assistantName,
      'timestamp': alert.timestamp.toString(),
      'isCritical': alert.isCritical,
    };
  }

  void _onUsineClick(AlertNode usine) {
    setState(() {
      if (_selectedUsine?.id == usine.id) {
        _selectedUsine = null;
        _selectedConveyor = null;
        _selectedWorkstation = null;
        _popupAlertData = null;
        _detailController.reverse();
        _zoomController.reverse();
      } else {
        _selectedUsine = usine;
        _selectedConveyor = null;
        _selectedWorkstation = null;
        _popupAlertData = null;
        _detailController.reverse();
        _zoomController.forward(from: 0);
      }
    });
  }

  void _onConveyorClick(AlertNode conveyor) {
    setState(() {
      if (_selectedConveyor?.id == conveyor.id) {
        _selectedConveyor = null;
        _selectedWorkstation = null;
        _popupAlertData = null;
        _detailController.reverse();
      } else {
        _selectedConveyor = conveyor;
        _selectedWorkstation = null;
        _popupAlertData = null;
        _detailController.forward(from: 0);
      }
    });
  }

  void _onWorkstationClick(AlertNode workstation, Offset globalPosition) {
    if (workstation.hasError && workstation.alertData != null) {
      setState(() {
        _selectedWorkstation = workstation;
        _popupAlertData = workstation.alertData;
        _popupPosition = globalPosition;
      });
    }
  }

  void _closePopup() {
    setState(() {
      _popupAlertData = null;
      _popupPosition = null;
      _selectedWorkstation = null;
    });
  }

  @override
  void dispose() {
    _zoomController.dispose();
    _detailController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GestureDetector(
          onTap: () {
            if (_popupAlertData != null) {
              _closePopup();
            } else if (_selectedConveyor != null) {
              setState(() {
                _selectedConveyor = null;
                _selectedWorkstation = null;
              });
            } else if (_selectedUsine != null) {
              setState(() {
                _selectedUsine = null;
                _selectedConveyor = null;
                _selectedWorkstation = null;
                _zoomController.reverse();
              });
            }
          },
          child: Container(
            color: _bg,
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_zoomAnimation, _detailAnimation]),
                    builder: (context, child) {
                      return SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Level 1: Factories
                            if (_selectedUsine == null)
                              _buildUsineLayer(_zoomAnimation.value)
                            else
                              _buildConveyorLayerWithParent(_zoomAnimation.value),
                            // Level 3: Workstations (visible when conveyor selected)
                            if (_selectedConveyor != null)
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildInterLayerConnector(height: 42),
                                  _buildWorkstationLayerWithParent(_detailAnimation.value),
                                ],
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
        if (_popupAlertData != null && _popupPosition != null)
          _buildAlertPopup(),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _white,
        border: Border(bottom: BorderSide(color: _border)),
      ),
      child: Row(
        children: [
          Icon(Icons.account_tree_outlined, color: _navy, size: 24),
          const SizedBox(width: 12),
          Expanded(child: _buildBreadcrumb()),
          if (_selectedUsine != null || _selectedConveyor != null)
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              onPressed: () {
                setState(() {
                  _selectedUsine = null;
                  _selectedConveyor = null;
                  _selectedWorkstation = null;
                  _popupAlertData = null;
                  _zoomController.reverse();
                });
              },
              tooltip: 'Reset view',
            ),
        ],
      ),
    );
  }

  Widget _buildBreadcrumb() {
    final parts = <Widget>[];
    parts.add(
      Text(
        'All Plants',
        style: TextStyle(
          fontSize: 16,
          fontWeight: _selectedUsine == null ? FontWeight.bold : FontWeight.w500,
          color: _selectedUsine == null ? _navy : _muted,
        ),
      ),
    );

    if (_selectedUsine != null) {
      parts.add(const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8),
        child: Icon(Icons.chevron_right, size: 16, color: _muted),
      ));
      parts.add(
        Text(
          _selectedUsine!.label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: _selectedConveyor == null ? FontWeight.bold : FontWeight.w500,
            color: _selectedConveyor == null ? _navy : _muted,
          ),
        ),
      );
    }

    if (_selectedConveyor != null) {
      parts.add(const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8),
        child: Icon(Icons.chevron_right, size: 16, color: _muted),
      ));
      parts.add(
        Text(
          _selectedConveyor!.label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: _navy,
          ),
        ),
      );
    }

    return Row(children: parts);
  }

  Widget _buildConveyorLayerWithParent(double progress) {
    if (_selectedUsine == null) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final conveyors = _selectedUsine!.children;
        final spacing = constraints.maxWidth / (conveyors.length + 1);
        final selectedIndex = conveyors.indexWhere((c) => c.id == _selectedConveyor?.id);
        final selectedX = selectedIndex >= 0 ? spacing * (selectedIndex + 1) : null;
        return Padding(
          padding: EdgeInsets.only(bottom: _selectedConveyor != null ? 0 : 16),
          child: SizedBox(
            height: 200,
            child: CustomPaint(
              painter: _ConveyorTreePainter(
                conveyors: conveyors,
                spacing: spacing,
                selectedX: selectedX,
                animation: _zoomAnimation,
              ),
              child: Stack(
                children: [
                  // Parent badge at top center
                  Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: _buildUsineNodeSmall(_selectedUsine!),
                    ),
                  ),
                  // Conveyor nodes
                  ...conveyors.asMap().entries.map((entry) {
                    final index = entry.key;
                    final conveyor = entry.value;
                    final x = spacing * (index + 1);
                    final isSelected = _selectedConveyor?.id == conveyor.id;
                    return Positioned(
                      left: x - 35,
                      top: 50,
                      child: GestureDetector(
                        onTap: () => _onConveyorClick(conveyor),
                        child: AnimatedScale(
                          scale: isSelected ? 0.94 : 1,
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOutBack,
                          child: _buildConveyorNode(conveyor),
                        ),
                      ),
                    );
                  }).toList(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildWorkstationLayerWithParent(double progress) {
    if (_selectedConveyor == null) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final workstations = _selectedConveyor!.children;
        final parentConveyors = _selectedUsine?.children ?? const <AlertNode>[];
        final selectedParentIndex = parentConveyors.indexWhere((c) => c.id == _selectedConveyor!.id);
        final parentSpacing = parentConveyors.isEmpty
            ? constraints.maxWidth / 2
            : constraints.maxWidth / (parentConveyors.length + 1);
        final parentX = selectedParentIndex >= 0
            ? parentSpacing * (selectedParentIndex + 1)
            : constraints.maxWidth / 2;
        final spacing = constraints.maxWidth / (workstations.length + 1);
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: SizedBox(
            height: 200,
            child: CustomPaint(
              painter: _WorkstationTreePainter(
                workstations: workstations,
                spacing: spacing,
                parentX: parentX,
                animation: _detailAnimation,
              ),
              child: Stack(
                children: [
                  // Workstation nodes
                  ...workstations.asMap().entries.map((entry) {
                    final index = entry.key;
                    final workstation = entry.value;
                    final x = spacing * (index + 1);
                    return Positioned(
                      left: x - 30,
                      top: 50,
                      child: GestureDetector(
                        onTap: () => _onWorkstationClick(workstation, Offset(x, 50)),
                        child: _buildWorkstationNode(workstation),
                      ),
                    );
                  }).toList(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildInterLayerConnector({double height = 42}) {
    if (_selectedUsine == null || _selectedConveyor == null) {
      return SizedBox(height: height);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final conveyors = _selectedUsine!.children;
        final selectedIndex = conveyors.indexWhere((c) => c.id == _selectedConveyor!.id);
        if (selectedIndex < 0 || conveyors.isEmpty) {
          return SizedBox(height: height);
        }

        final spacing = constraints.maxWidth / (conveyors.length + 1);
        final selectedX = spacing * (selectedIndex + 1);

        return SizedBox(
          width: double.infinity,
          height: height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: selectedX - 2,
                top: -1,
                child: Container(
                  width: 4,
                  height: height + 2,
                  decoration: BoxDecoration(
                    color: const Color(0xFF111827).withOpacity(0.88),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildUsineLayer(double progress) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final spacing = constraints.maxWidth / (_usines.length + 1);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: SizedBox(
            height: 200,
            child: CustomPaint(
              painter: _UsineTreePainter(
                usines: _usines,
                spacing: spacing,
                animation: _pulseController,
              ),
              child: Stack(
                children: _usines.asMap().entries.map((entry) {
                  final index = entry.key;
                  final usine = entry.value;
                  final x = spacing * (index + 1);
                  final isSelected = _selectedUsine?.id == usine.id;
                  return Positioned(
                    left: x - 40,
                    top: 50,
                    child: GestureDetector(
                      onTap: () => _onUsineClick(usine),
                      child: AnimatedScale(
                        scale: isSelected ? 0.94 : 1,
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOutBack,
                        child: _buildUsineNode(usine),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildUsineNodeSmall(AlertNode usine) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: usine.hasError ? _red : _navy, width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.factory_outlined, size: 20, color: usine.hasError ? _red : _navy),
          const SizedBox(width: 8),
          Text(
            usine.label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: usine.hasError ? _red : _navy,
            ),
          ),
        ],
      ),
    );
  }

  // Node builders (same as original, but using the updated AlertNode fields)
  Widget _buildUsineNode(AlertNode usine) {
    return GestureDetector(
      onTap: () => _onUsineClick(usine),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              key: ValueKey('usine-node-${usine.id}'),
              duration: const Duration(milliseconds: 300),
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: usine.hasError ? _red.withOpacity(0.1) : _navy.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: usine.hasError ? _red : _navy,
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: (usine.hasError ? _red : _navy).withOpacity(0.2),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    Icons.factory_outlined,
                    size: 40,
                    color: usine.hasError ? _red : _navy,
                  ),
                  if (usine.hasError)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          return Container(
                            width: 12 + (_pulseController.value * 4),
                            height: 12 + (_pulseController.value * 4),
                            decoration: BoxDecoration(
                              color: _red,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: _red.withOpacity(0.6),
                                  blurRadius: 8 * _pulseController.value,
                                  spreadRadius: 2 * _pulseController.value,
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
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _border),
              ),
              child: Column(
                children: [
                  Text(
                    usine.label,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: _navy,
                    ),
                  ),
                  if (usine.hasError)
                    Text(
                      '${usine.errorCount} alert${usine.errorCount > 1 ? 's' : ''}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: _red,
                        fontWeight: FontWeight.w600,
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

  Widget _buildConveyorNode(AlertNode conveyor) {
    return GestureDetector(
      onTap: () => _onConveyorClick(conveyor),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              key: ValueKey('conveyor-node-${conveyor.id}'),
              duration: const Duration(milliseconds: 300),
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                color: conveyor.hasError ? _orange.withOpacity(0.1) : _blue.withOpacity(0.1),
                shape: BoxShape.circle,
                border: Border.all(
                  color: conveyor.hasError ? _orange : _blue,
                  width: 3,
                ),
                boxShadow: [
                  BoxShadow(
                    color: (conveyor.hasError ? _orange : _blue).withOpacity(0.3),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    Icons.linear_scale,
                    size: 32,
                    color: conveyor.hasError ? _orange : _blue,
                  ),
                  if (conveyor.hasError)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          return Container(
                            width: 10 + (_pulseController.value * 3),
                            height: 10 + (_pulseController.value * 3),
                            decoration: BoxDecoration(
                              color: _orange,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: _orange.withOpacity(0.6),
                                  blurRadius: 6 * _pulseController.value,
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
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _border),
              ),
              child: Column(
                children: [
                  Text(
                    conveyor.label,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _navy,
                    ),
                  ),
                  if (conveyor.hasError)
                    Text(
                      '${conveyor.errorCount}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: _orange,
                        fontWeight: FontWeight.bold,
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

  Widget _buildWorkstationNode(AlertNode workstation) {
    final isSelected = _selectedWorkstation?.id == workstation.id;
    return GestureDetector(
      onTapDown: (details) {
        if (workstation.hasError) {
          _onWorkstationClick(workstation, details.globalPosition);
        }
      },
      child: MouseRegion(
        cursor: workstation.hasError ? SystemMouseCursors.click : MouseCursor.defer,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              key: ValueKey('workstation-node-${workstation.id}'),
              duration: const Duration(milliseconds: 300),
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: workstation.hasError
                    ? _red.withOpacity(isSelected ? 0.2 : 0.1)
                    : _green.withOpacity(0.1),
                shape: BoxShape.circle,
                border: Border.all(
                  color: workstation.hasError ? _red : _green,
                  width: isSelected ? 3 : 2,
                ),
                boxShadow: [
                  if (workstation.hasError)
                    BoxShadow(
                      color: _red.withOpacity(isSelected ? 0.4 : 0.3),
                      blurRadius: isSelected ? 12 : 8,
                      spreadRadius: isSelected ? 2 : 0,
                    ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    Icons.settings,
                    size: 28,
                    color: workstation.hasError ? _red : _green,
                  ),
                  if (workstation.hasError)
                    AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        return Container(
                          width: 60 + (_pulseController.value * 8),
                          height: 60 + (_pulseController.value * 8),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _red.withOpacity(0.3 * (1 - _pulseController.value)),
                              width: 2,
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _border),
              ),
              child: Text(
                workstation.label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _navy,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertPopup() {
    final alert = _popupAlertData!;
    final screenSize = MediaQuery.of(context).size;
    final status = (alert['status'] as String?) ?? 'disponible';
    final claimedBy = alert['superviseurName'] as String?;
    final assistantName = alert['assistantName'] as String?;

    double left = _popupPosition!.dx + 20;
    double top = _popupPosition!.dy - 100;

    if (left + 320 > screenSize.width) {
      left = _popupPosition!.dx - 340;
    }
    if (top < 20) {
      top = 20;
    }
    if (top + 200 > screenSize.height) {
      top = screenSize.height - 220;
    }

    return Positioned(
      left: left,
      top: top,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 320,
          constraints: const BoxConstraints(maxHeight: 400),
          decoration: BoxDecoration(
            color: _white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: alert['isCritical'] ? _red : _border, width: 2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _typeColor(alert['type']).withOpacity(0.1),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(10),
                    topRight: Radius.circular(10),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: _typeColor(alert['type']),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _typeIcon(alert['type']),
                        size: 16,
                        color: _white,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _typeLabel(alert['type']),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: _typeColor(alert['type']),
                            ),
                          ),
                          Text(
                            'Alert #${alert['id'].substring(0, 8)}',
                            style: const TextStyle(
                              fontSize: 10,
                              color: _muted,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: _closePopup,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (alert['isCritical'])
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(8),
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: _red.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: _red),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.warning, color: _red, size: 16),
                              const SizedBox(width: 8),
                              const Text(
                                'CRITICAL ALERT',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: _red,
                                ),
                              ),
                            ],
                          ),
                        ),
                      _buildInfoRow('Location', alert['usine']),
                      _buildInfoRow('Line', '${alert['convoyeur']}'),
                      _buildInfoRow('Workstation', '${alert['poste']}'),
                      const SizedBox(height: 8),
                      const Divider(height: 1),
                      const SizedBox(height: 8),
                      const Text(
                        'Description',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: _muted,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        alert['description'] ?? 'No description',
                        style: const TextStyle(
                          fontSize: 12,
                          color: _navy,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _statusColor(alert['status']).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _statusColor(alert['status'])),
                        ),
                        child: Text(
                          _statusLabel(alert['status']),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: _statusColor(alert['status']),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _buildInfoRow('Claim status', _statusSummary(status, claimedBy, assistantName)),
                      if (claimedBy != null)
                        _buildInfoRow('Claimed by', claimedBy),
                      if (assistantName != null && assistantName.isNotEmpty)
                        _buildInfoRow('Assisted by', assistantName),
                      if (status == 'disponible')
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () => _showAssignSupervisorDialog(alert),
                              icon: const Icon(Icons.person_add_alt_1, size: 18),
                              label: const Text('Assign Supervisor'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _navy,
                                foregroundColor: _white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text(
            '$label:',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: _muted,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 11,
              color: _navy,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _statusSummary(String status, String? claimedBy, String? assistantName) {
    if (status == 'disponible') {
      return 'Unclaimed';
    }
    if (claimedBy != null && assistantName != null && assistantName.isNotEmpty) {
      return 'Claimed by $claimedBy and assisted by $assistantName';
    }
    if (claimedBy != null) {
      return 'Claimed by $claimedBy';
    }
    return 'In progress';
  }

  Future<void> _showAssignSupervisorDialog(Map<String, dynamic> alert) async {
    final supervisors = await _authService.getActiveSupervisors();
    final filtered = supervisors.where((supervisor) => supervisor.usine == alert['usine']).toList();

    if (!mounted) return;

    if (filtered.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No active supervisors available for this factory')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Assign Supervisor'),
        content: SizedBox(
          width: 320,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: filtered.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, index) {
              final supervisor = filtered[index];
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person, color: _navy),
                title: Text(supervisor.fullName),
                subtitle: Text(supervisor.email),
                onTap: () async {
                  Navigator.of(dialogContext).pop();
                  await _authService.assignSupervisorToAlert(
                    alert['id'] as String,
                    supervisor.id,
                    supervisor.fullName,
                  );
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Assigned to ${supervisor.fullName}'),
                      backgroundColor: _green,
                    ),
                  );
                  _closePopup();
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Color _typeColor(String type) => switch (type) {
    'qualite' => _red,
    'maintenance' => _blue,
    'defaut_produit' => _green,
    'manque_ressource' => _orange,
    _ => _muted,
  };

  IconData _typeIcon(String type) => switch (type) {
    'qualite' => Icons.warning_amber_rounded,
    'maintenance' => Icons.build_outlined,
    'defaut_produit' => Icons.cancel_outlined,
    'manque_ressource' => Icons.inventory_2_outlined,
    _ => Icons.notifications_outlined,
  };

  String _typeLabel(String type) => switch (type) {
    'qualite' => 'Quality Issues',
    'maintenance' => 'Maintenance',
    'defaut_produit' => 'Damaged Product',
    'manque_ressource' => 'Resource Deficiency',
    _ => type,
  };

  Color _statusColor(String status) => switch (status) {
    'validee' => _green,
    'en_cours' => _blue,
    _ => _orange,
  };

  String _statusLabel(String status) => switch (status) {
    'validee' => 'Fixed',
    'en_cours' => 'In Progress',
    _ => 'Available',
  };
}

// Custom painters for connecting lines (same as original)
class _UsineTreePainter extends CustomPainter {
  final List<AlertNode> usines;
  final double spacing;
  final Animation<double> animation;
  _UsineTreePainter({required this.usines, required this.spacing, required this.animation}) : super(repaint: animation);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF111827).withOpacity(0.55 + (animation.value * 0.25))
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    const parentY = 30.0;
    const childY = 50.0;
    for (var i = 0; i < usines.length; i++) {
      final childX = spacing * (i + 1);
      final path = Path()
        ..moveTo(childX, parentY)
        ..cubicTo(childX, parentY + 10, childX, childY - 10, childX, childY);
      final metric = path.computeMetrics().first;
      canvas.drawPath(metric.extractPath(0, metric.length * animation.value), paint);
    }
  }
  @override bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _ConveyorTreePainter extends CustomPainter {
  final List<AlertNode> conveyors;
  final double spacing;
  final double? selectedX;
  final Animation<double> animation;
  _ConveyorTreePainter({
    required this.conveyors,
    required this.spacing,
    required this.selectedX,
    required this.animation,
  }) : super(repaint: animation);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF111827).withOpacity(0.88)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final parentX = size.width / 2;
    const parentY = 38.0;
    const childY = 50.0;
    for (var i = 0; i < conveyors.length; i++) {
      final childX = spacing * (i + 1);
      final path = Path();
      path.moveTo(parentX, parentY);
      path.cubicTo(parentX, parentY + 6, childX, childY - 6, childX, childY);
      final metric = path.computeMetrics().first;
      canvas.drawPath(metric.extractPath(0, metric.length * animation.value), paint);
    }

    if (selectedX != null) {
      const selectedNodeBottomY = 120.0;
      final bridgePath = Path()
        ..moveTo(selectedX!, selectedNodeBottomY)
        ..lineTo(selectedX!, size.height);
      final bridgeMetric = bridgePath.computeMetrics().first;
      canvas.drawPath(bridgeMetric.extractPath(0, bridgeMetric.length * animation.value), paint);
    }
  }
  @override bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _WorkstationTreePainter extends CustomPainter {
  final List<AlertNode> workstations;
  final double spacing;
  final double parentX;
  final Animation<double> animation;
  _WorkstationTreePainter({
    required this.workstations,
    required this.spacing,
    required this.parentX,
    required this.animation,
  }) : super(repaint: animation);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF111827).withOpacity(0.88)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    const parentY = 0.0;
    const childY = 50.0;

    for (var i = 0; i < workstations.length; i++) {
      final childX = spacing * (i + 1);
      final path = Path();
      path.moveTo(parentX, parentY);
      path.cubicTo(parentX, parentY + 14, childX, childY - 10, childX, childY);
      final metric = path.computeMetrics().first;
      canvas.drawPath(metric.extractPath(0, metric.length * animation.value), paint);
    }
  }
  @override bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}