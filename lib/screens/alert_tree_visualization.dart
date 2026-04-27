// lib/screens/alert_tree_visualization.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/hierarchy_service.dart';
import '../services/auth_service.dart';
import '../services/ai_assignment_service.dart';
import '../models/alert_model.dart';
import '../widgets/ai_logs_panel.dart';
import '../theme.dart';

// Alert/status accent palette
const _red = Color(0xFFDC2626);
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
  static const double _minTreeScale = 0.7;
  static const double _maxTreeScale = 1.8;
  static const double _treeScaleStep = 0.1;

  List<AlertNode> _usines = [];
  AlertNode? _selectedUsine;
  AlertNode? _selectedConveyor;
  AlertNode? _selectedWorkstation;
  Map<String, dynamic>? _popupAlertData;
  Offset? _popupPosition;
  double _treeScale = 1.0;
  bool _showAILogsPanel = false;

  late AnimationController _zoomController;
  late AnimationController _detailController;
  late AnimationController _pulseController;
  late Animation<double> _zoomAnimation;
  late Animation<double> _detailAnimation;

  final HierarchyService _hierarchyService = HierarchyService();
  final AuthService _authService = AuthService();

  AppTheme get _t => context.appTheme;
  Color get _lineColor => context.isDark
      ? Colors.white.withOpacity(0.65)
      : const Color(0xFF111827).withOpacity(0.88);
  Color get _lineSoftColor => context.isDark
      ? Colors.white.withOpacity(0.45)
      : const Color(0xFF111827).withOpacity(0.55);

  @override
  void initState() {
    super.initState();
    _buildHierarchy();
    AIAssignmentService.instance.init().then((_) {
      if (mounted) setState(() {});
      AIAssignmentService.instance.processAlerts(widget.alerts);
    });
    AIAssignmentService.instance.addListener(_onAIChange);

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
      // Feed updated alerts to AI engine for re-evaluation.
      AIAssignmentService.instance.processAlerts(widget.alerts);
    }
  }

  void _onAIChange() {
    if (mounted) setState(() {});
  }

  Future<void> _toggleAI(bool on) async {
    await AIAssignmentService.instance.setEnabled(on);
    if (on) {
      AIAssignmentService.instance.processAlerts(widget.alerts);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(on
              ? 'Global AI ON — all factories auto-assignment enabled'
              : 'Global AI OFF — auto-assignment disabled for all factories'),
          backgroundColor: on ? _t.green : _t.muted,
          duration: const Duration(seconds: 2),
        ),
      );
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
            final stationNumber =
                int.tryParse(station.id.replaceAll('station_', '')) ?? 0;
            final key = '${factory.name}|${conveyor.number}|$stationNumber';
            final errorCount = alertCounts[key] ?? 0;
            final baseStationData = <String, dynamic>{
              'usine': factory.name,
              'convoyeur': conveyor.number,
              'poste': stationNumber,
            };
            return AlertNode(
              id: '${factory.id}|${conveyor.id}|${station.id}',
              label: station.name,
              errorCount: errorCount,
              alertData: errorCount > 0
                  ? {
                      ...baseStationData,
                      ...?firstAlertData[key],
                      'hasActiveAlert': true,
                    }
                  : {
                      ...baseStationData,
                      'hasActiveAlert': false,
                    },
              type: 'workstation',
            );
          }).toList();

          final conveyorErrorCount =
              stationNodes.fold<int>(0, (sum, s) => sum + s.errorCount);
          return AlertNode(
            id: '${factory.id}|${conveyor.id}',
            label: 'Conveyor ${conveyor.number}',
            errorCount: conveyorErrorCount,
            children: stationNodes.toList(),
            type: 'conveyor',
          );
        }).toList();

        final factoryErrorCount =
            conveyorNodes.fold<int>(0, (sum, c) => sum + c.errorCount);
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
    setState(() {
      _selectedWorkstation = workstation;
      _popupAlertData = workstation.alertData;
      _popupPosition = globalPosition;
    });
  }

  void _closePopup() {
    setState(() {
      _popupAlertData = null;
      _popupPosition = null;
      _selectedWorkstation = null;
    });
  }

  void _zoomInTree() {
    setState(() {
      _treeScale =
          (_treeScale + _treeScaleStep).clamp(_minTreeScale, _maxTreeScale);
    });
  }

  void _zoomOutTree() {
    setState(() {
      _treeScale =
          (_treeScale - _treeScaleStep).clamp(_minTreeScale, _maxTreeScale);
    });
  }

  @override
  void dispose() {
    AIAssignmentService.instance.removeListener(_onAIChange);
    _zoomController.dispose();
    _detailController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = _t;
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
            color: t.scaffold,
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: AnimatedBuilder(
                    animation:
                        Listenable.merge([_zoomAnimation, _detailAnimation]),
                    builder: (context, child) {
                      return SingleChildScrollView(
                        child: Center(
                          child: Transform.scale(
                            scale: _treeScale,
                            alignment: Alignment.topCenter,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Level 1: Factories
                                if (_selectedUsine == null)
                                  _buildUsineLayer(_zoomAnimation.value)
                                else
                                  _buildConveyorLayerWithParent(
                                      _zoomAnimation.value),
                                // Level 3: Workstations (visible when conveyor selected)
                                if (_selectedConveyor != null)
                                  Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _buildInterLayerConnector(height: 42),
                                      _buildWorkstationLayerWithParent(
                                          _detailAnimation.value),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: _buildZoomControls(),
        ),
        if (_popupAlertData != null && _popupPosition != null)
          _buildAlertPopup(),
        if (_showAILogsPanel)
          AILogsPanel(
            onClose: () => setState(() => _showAILogsPanel = false),
            hostSize: MediaQuery.of(context).size,
          ),
      ],
    );
  }

  Widget _buildZoomControls() {
    final t = _t;
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(14),
      color: t.card,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: t.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Zoom in',
              onPressed: _treeScale < _maxTreeScale ? _zoomInTree : null,
              icon: Icon(Icons.add, color: t.navy),
            ),
            Container(
              width: 24,
              height: 1,
              color: t.border,
            ),
            IconButton(
              tooltip: 'Zoom out',
              onPressed: _treeScale > _minTreeScale ? _zoomOutTree : null,
              icon: Icon(Icons.remove, color: t.navy),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final t = _t;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.card,
        border: Border(bottom: BorderSide(color: t.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.account_tree, color: t.navy, size: 24),
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
          const SizedBox(height: 10),
          _buildAIControlBar(),
        ],
      ),
    );
  }

  Widget _buildAIControlBar() {
    final t = _t;
    final isOn = AIAssignmentService.instance.enabled;
    final logCount = AIAssignmentService.instance.logs.length;
    final backendSettingsOk =
        AIAssignmentService.instance.isUsingBackendSettings;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isOn
            ? t.greenLt.withOpacity(context.isDark ? 0.32 : 0.55)
            : t.scaffold,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: isOn ? t.green.withOpacity(0.45) : t.border, width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: isOn ? t.green : t.navy,
              borderRadius: BorderRadius.circular(7),
            ),
            child: const Icon(Icons.smart_toy_outlined,
                size: 16, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'AI Assignment',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: t.navy,
                ),
              ),
              Text(
                isOn
                    ? 'Active — auto-assigning new alerts'
                    : 'Off — manual assignment only',
                style: TextStyle(
                    fontSize: 10,
                    color: isOn ? t.green : t.muted,
                    fontWeight: FontWeight.w600),
              ),
              if (!backendSettingsOk)
                Container(
                  margin: const EdgeInsets.only(top: 3),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: t.orangeLt.withOpacity(context.isDark ? 0.32 : 1),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: t.orange.withOpacity(0.35)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          size: 10, color: t.orange),
                      const SizedBox(width: 4),
                      Text(
                        'LOCAL FALLBACK MODE',
                        style: TextStyle(
                          fontSize: 8.5,
                          fontWeight: FontWeight.w800,
                          color: t.orange,
                          letterSpacing: 0.25,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const Spacer(),
          _aiSegment(
            icon: Icons.power_settings_new,
            label: 'ON',
            active: isOn,
            activeColor: _green,
            onTap: isOn ? null : () => _toggleAI(true),
          ),
          const SizedBox(width: 6),
          _aiSegment(
            icon: Icons.stop_circle_outlined,
            label: 'OFF',
            active: !isOn,
            activeColor: t.muted,
            onTap: !isOn ? null : () => _toggleAI(false),
          ),
          const SizedBox(width: 6),
          _aiSegment(
            icon: Icons.receipt_long,
            label: 'AI-LOGS',
            active: _showAILogsPanel,
            activeColor: t.navy,
            badge: logCount > 0 ? '$logCount' : null,
            onTap: () => setState(() => _showAILogsPanel = !_showAILogsPanel),
          ),
        ],
      ),
    );
  }

  Widget _aiSegment({
    required IconData icon,
    required String label,
    required bool active,
    required Color activeColor,
    String? badge,
    VoidCallback? onTap,
  }) {
    final t = _t;
    final bg = active ? activeColor : t.card;
    final fg = active ? Colors.white : t.muted;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            border:
                Border.all(color: active ? activeColor : t.border, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: fg),
              const SizedBox(width: 5),
              Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: fg,
                      letterSpacing: 0.4)),
              if (badge != null) ...[
                const SizedBox(width: 5),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: active
                        ? Colors.white.withOpacity(0.25)
                        : activeColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(badge,
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: active ? Colors.white : activeColor)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBreadcrumb() {
    final t = _t;
    final parts = <Widget>[];
    parts.add(
      Text(
        'All Plants',
        style: TextStyle(
          fontSize: 16,
          fontWeight:
              _selectedUsine == null ? FontWeight.bold : FontWeight.w500,
          color: _selectedUsine == null ? t.navy : t.muted,
        ),
      ),
    );

    if (_selectedUsine != null) {
      parts.add(Padding(
        padding: EdgeInsets.symmetric(horizontal: 8),
        child: Icon(Icons.chevron_right, size: 16, color: t.muted),
      ));
      parts.add(
        Text(
          _selectedUsine!.label,
          style: TextStyle(
            fontSize: 16,
            fontWeight:
                _selectedConveyor == null ? FontWeight.bold : FontWeight.w500,
            color: _selectedConveyor == null ? t.navy : t.muted,
          ),
        ),
      );
    }

    if (_selectedConveyor != null) {
      parts.add(Padding(
        padding: EdgeInsets.symmetric(horizontal: 8),
        child: Icon(Icons.chevron_right, size: 16, color: t.muted),
      ));
      parts.add(
        Text(
          _selectedConveyor!.label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: t.navy,
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
        final selectedIndex =
            conveyors.indexWhere((c) => c.id == _selectedConveyor?.id);
        final selectedX =
            selectedIndex >= 0 ? spacing * (selectedIndex + 1) : null;
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
                lineColor: _lineColor,
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
        final selectedParentIndex =
            parentConveyors.indexWhere((c) => c.id == _selectedConveyor!.id);
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
                lineColor: _lineColor,
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
                        onTap: () =>
                            _onWorkstationClick(workstation, Offset(x, 50)),
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
        final selectedIndex =
            conveyors.indexWhere((c) => c.id == _selectedConveyor!.id);
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
                    color: _lineColor,
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
                lineColor: _lineColor,
                lineSoftColor: _lineSoftColor,
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
    final t = _t;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: usine.hasError ? _red : t.navy, width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.factory, size: 20, color: usine.hasError ? _red : t.navy),
          const SizedBox(width: 8),
          Text(
            usine.label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: usine.hasError ? _red : t.navy,
            ),
          ),
        ],
      ),
    );
  }

  // Node builders (same as original, but using the updated AlertNode fields)
  Widget _buildUsineNode(AlertNode usine) {
    final t = _t;
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
                color: usine.hasError
                    ? _red.withOpacity(0.1)
                    : t.navy.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: usine.hasError ? _red : t.navy,
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: (usine.hasError ? _red : t.navy).withOpacity(0.2),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    Icons.factory,
                    size: 40,
                    color: usine.hasError ? _red : t.navy,
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
                color: t.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: t.border),
              ),
              child: Column(
                children: [
                  Text(
                    usine.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: t.navy,
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
    final t = _t;
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
                color: conveyor.hasError
                    ? _orange.withOpacity(0.1)
                    : _blue.withOpacity(0.1),
                shape: BoxShape.circle,
                border: Border.all(
                  color: conveyor.hasError ? _orange : _blue,
                  width: 3,
                ),
                boxShadow: [
                  BoxShadow(
                    color:
                        (conveyor.hasError ? _orange : _blue).withOpacity(0.3),
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
                color: t.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: t.border),
              ),
              child: Column(
                children: [
                  Text(
                    conveyor.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: t.navy,
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
    final t = _t;
    final isSelected = _selectedWorkstation?.id == workstation.id;
    return GestureDetector(
      onTapDown: (details) {
        _onWorkstationClick(workstation, details.globalPosition);
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
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
                              color: _red.withOpacity(
                                  0.3 * (1 - _pulseController.value)),
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
                color: t.card,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: t.border),
              ),
              child: Text(
                workstation.label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: t.navy,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertPopup() {
    final t = _t;
    final alert = _popupAlertData!;
    final screenSize = MediaQuery.of(context).size;
    final hasActiveAlert = (alert['hasActiveAlert'] as bool?) ?? false;

    // Safe type extraction
    final String alertType = (alert['type'] as String?) ?? 'unknown';

    final String alertId = (alert['id'] as String?) ?? '';
    final String status = (alert['status'] as String?) ?? 'disponible';
    final String? claimedBy = alert['superviseurName'] as String?;
    final String? assistantName = alert['assistantName'] as String?;
    final bool isCritical = (alert['isCritical'] as bool?) ?? false;

    final String usine = (alert['usine'] as String?) ?? 'Unknown';
    final String convoyeur = (alert['convoyeur'] as num?)?.toString() ?? '-';
    final String poste = (alert['poste'] as num?)?.toString() ?? '-';

    final String description = hasActiveAlert
        ? (alert['description'] as String?) ?? 'No description'
        : 'No active alert on this workstation right now. Use history to view previous alerts.';

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
            color: t.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isCritical ? _red : t.border, width: 2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _typeColor(alertType).withOpacity(0.1),
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
                        color: _typeColor(alertType),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _typeIcon(alertType),
                        size: 16,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            hasActiveAlert
                                ? _typeLabel(alertType)
                                : 'Workstation',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: hasActiveAlert
                                  ? _typeColor(alertType)
                                  : t.navy,
                            ),
                          ),
                          Text(
                            hasActiveAlert
                                ? 'Alert #${alertId.length > 8 ? alertId.substring(0, 8) : alertId}'
                                : 'No active alert',
                            style: TextStyle(
                              fontSize: 10,
                              color: t.muted,
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
                      if (hasActiveAlert && isCritical)
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
                      _buildInfoRow('Location', usine),
                      _buildInfoRow('Line', convoyeur),
                      _buildInfoRow('Workstation', poste),
                      const SizedBox(height: 8),
                      const Divider(height: 1),
                      const SizedBox(height: 8),
                      const Text(
                        'Description',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        description,
                        style: TextStyle(
                          fontSize: 12,
                          color: t.text,
                        ),
                      ),
                      if (hasActiveAlert) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _statusColor(status).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _statusColor(status)),
                          ),
                          child: Text(
                            _statusLabel(status),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: _statusColor(status),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        _buildInfoRow(
                          'Claim status',
                          _statusSummary(status, claimedBy, assistantName),
                        ),
                        if (claimedBy != null && claimedBy.isNotEmpty)
                          _buildInfoRow('Claimed by', claimedBy),
                        if (assistantName != null && assistantName.isNotEmpty)
                          _buildInfoRow('Assisted by', assistantName),
                      ],
                      if (hasActiveAlert && status == 'disponible')
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () =>
                                  _showAssignSupervisorDialog(alert),
                              icon:
                                  const Icon(Icons.person_add_alt_1, size: 18),
                              label: const Text('Assign Supervisor'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: t.navy,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () =>
                                _showWorkstationHistoryDialog(alert),
                            icon: const Icon(Icons.history, size: 18),
                            label: const Text('Show Workstation History'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: t.navy,
                              side: BorderSide(color: t.navy.withOpacity(0.35)),
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
    final t = _t;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text(
            '$label:',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: t.muted,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 11,
              color: t.text,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _statusSummary(
      String status, String? claimedBy, String? assistantName) {
    if (status == 'disponible') {
      return 'Unclaimed';
    }
    if (claimedBy != null &&
        assistantName != null &&
        assistantName.isNotEmpty) {
      return 'Claimed by $claimedBy and assisted by $assistantName';
    }
    if (claimedBy != null) {
      return 'Claimed by $claimedBy';
    }
    return 'Being fixed...';
  }

  Future<void> _showAssignSupervisorDialog(Map<String, dynamic> alert) async {
    final supervisors = await _authService.getActiveSupervisors();
    final filtered = supervisors
        .where((supervisor) => supervisor.usine == alert['usine'])
        .toList();

    if (!mounted) return;

    if (filtered.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No active supervisors available for this factory')),
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
                leading: Icon(Icons.person, color: _t.navy),
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

  Future<void> _showWorkstationHistoryDialog(Map<String, dynamic> alert) async {
    final usine = alert['usine']?.toString() ?? '';
    final convoyeur = int.tryParse('${alert['convoyeur']}') ?? -1;
    final poste = int.tryParse('${alert['poste']}') ?? -1;

    final workstationAlerts = widget.alerts
        .where(
          (a) =>
              a.usine == usine && a.convoyeur == convoyeur && a.poste == poste,
        )
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    if (!mounted) return;

    final searchController = TextEditingController();
    String selectedStatus = 'all';
    String selectedDateFilter = '7_days';
    DateTimeRange? customRange;
    String query = '';

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final t = context.appTheme;
            final normalizedQuery = query.trim().toLowerCase();
            final now = DateTime.now();

            bool dateMatches(DateTime timestamp) {
              final ts = timestamp.toLocal();
              switch (selectedDateFilter) {
                case 'today':
                  return ts.year == now.year &&
                      ts.month == now.month &&
                      ts.day == now.day;
                case '7_days':
                  return !ts.isBefore(now.subtract(const Duration(days: 7)));
                case '15_days':
                  return !ts.isBefore(now.subtract(const Duration(days: 15)));
                case '1_month':
                  return !ts.isBefore(now.subtract(const Duration(days: 30)));
                case 'custom':
                  if (customRange == null) return true;
                  final start = DateTime(
                    customRange!.start.year,
                    customRange!.start.month,
                    customRange!.start.day,
                  );
                  final end = DateTime(
                    customRange!.end.year,
                    customRange!.end.month,
                    customRange!.end.day,
                    23,
                    59,
                    59,
                  );
                  return !ts.isBefore(start) && !ts.isAfter(end);
                default:
                  return true;
              }
            }

            final filtered = workstationAlerts.where((a) {
              final statusMatch =
                  selectedStatus == 'all' || a.status == selectedStatus;
              final dateMatch = dateMatches(a.timestamp);
              final searchMatch = normalizedQuery.isEmpty ||
                  a.id.toLowerCase().contains(normalizedQuery) ||
                  _typeLabel(a.type).toLowerCase().contains(normalizedQuery) ||
                  a.description.toLowerCase().contains(normalizedQuery);
              return statusMatch && dateMatch && searchMatch;
            }).toList();

            return AlertDialog(
              title:
                  Text('Workstation History - $usine / C$convoyeur / W$poste'),
              content: SizedBox(
                width: 760,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: 260,
                          child: TextField(
                            controller: searchController,
                            decoration: const InputDecoration(
                              labelText: 'Filter (ID, title, description)',
                              prefixIcon: Icon(Icons.search),
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (value) {
                              setDialogState(() {
                                query = value;
                              });
                            },
                          ),
                        ),
                        SizedBox(
                          width: 180,
                          child: DropdownButtonFormField<String>(
                            value: selectedStatus,
                            decoration: const InputDecoration(
                              labelText: 'Status',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: const [
                              DropdownMenuItem(
                                  value: 'all', child: Text('All statuses')),
                              DropdownMenuItem(
                                  value: 'disponible',
                                  child: Text('Available')),
                              DropdownMenuItem(
                                  value: 'en_cours',
                                  child: Text('Being fixed...')),
                              DropdownMenuItem(
                                  value: 'validee', child: Text('Fixed')),
                            ],
                            onChanged: (value) {
                              if (value == null) return;
                              setDialogState(() {
                                selectedStatus = value;
                              });
                            },
                          ),
                        ),
                        SizedBox(
                          width: 220,
                          child: DropdownButtonFormField<String>(
                            value: selectedDateFilter,
                            decoration: const InputDecoration(
                              labelText: 'Date range',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: const [
                              DropdownMenuItem(
                                  value: 'today', child: Text('Today')),
                              DropdownMenuItem(
                                  value: '7_days', child: Text('7 days')),
                              DropdownMenuItem(
                                  value: '15_days', child: Text('15 days')),
                              DropdownMenuItem(
                                  value: '1_month', child: Text('1 month')),
                              DropdownMenuItem(
                                  value: 'custom', child: Text('Custom range')),
                            ],
                            onChanged: (value) async {
                              if (value == null) return;
                              if (value == 'custom') {
                                final picked = await showDateRangePicker(
                                  context: dialogContext,
                                  initialDateRange: customRange,
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime.now().add(
                                    const Duration(days: 1),
                                  ),
                                );
                                if (picked == null) return;
                                setDialogState(() {
                                  selectedDateFilter = 'custom';
                                  customRange = picked;
                                });
                                return;
                              }

                              setDialogState(() {
                                selectedDateFilter = value;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    if (selectedDateFilter == 'custom' && customRange != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Custom range: ${DateFormat('dd/MM/yyyy').format(customRange!.start)} - ${DateFormat('dd/MM/yyyy').format(customRange!.end)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: t.muted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Text(
                      'Showing ${filtered.length} of ${workstationAlerts.length} alerts',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: t.muted,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Flexible(
                      child: filtered.isEmpty
                          ? Center(
                              child: Padding(
                                padding: EdgeInsets.symmetric(vertical: 20),
                                child: Text(
                                  'No alerts match the current filters.',
                                  style: TextStyle(color: t.muted),
                                ),
                              ),
                            )
                          : ListView.separated(
                              shrinkWrap: true,
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 14),
                              itemBuilder: (_, index) {
                                final item = filtered[index];
                                return Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: t.scaffold,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: t.border),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _buildHistoryRow('Alert ID', item.id),
                                      _buildHistoryRow(
                                          'Title', _typeLabel(item.type)),
                                      _buildHistoryRow(
                                          'Description', item.description),
                                      _buildHistoryRow(
                                        'Date',
                                        DateFormat('dd/MM/yyyy HH:mm:ss')
                                            .format(item.timestamp),
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
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );

    searchController.dispose();
  }

  Widget _buildHistoryRow(String label, String value) {
    final t = _t;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              '$label:',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: t.muted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 11,
                color: t.text,
                fontWeight: FontWeight.w600,
              ),
            ),
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
        _ => _t.muted,
      };

  IconData _typeIcon(String type) => switch (type) {
        'qualite' => Icons.warning_amber_rounded,
        'maintenance' => Icons.build,
        'defaut_produit' => Icons.cancel,
        'manque_ressource' => Icons.inventory_2,
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
        'en_cours' => 'Being fixed...',
        _ => 'Available',
      };
}

// Custom painters for connecting lines (same as original)
class _UsineTreePainter extends CustomPainter {
  final List<AlertNode> usines;
  final double spacing;
  final Animation<double> animation;
  final Color lineColor;
  final Color lineSoftColor;
  _UsineTreePainter(
      {required this.usines,
      required this.spacing,
      required this.animation,
      required this.lineColor,
      required this.lineSoftColor})
      : super(repaint: animation);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Color.lerp(
              lineSoftColor, lineColor, animation.value.clamp(0.0, 1.0)) ??
          lineSoftColor
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
      canvas.drawPath(
          metric.extractPath(0, metric.length * animation.value), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _ConveyorTreePainter extends CustomPainter {
  final List<AlertNode> conveyors;
  final double spacing;
  final double? selectedX;
  final Animation<double> animation;
  final Color lineColor;
  _ConveyorTreePainter({
    required this.conveyors,
    required this.spacing,
    required this.selectedX,
    required this.animation,
    required this.lineColor,
  }) : super(repaint: animation);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lineColor
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
      canvas.drawPath(
          metric.extractPath(0, metric.length * animation.value), paint);
    }

    if (selectedX != null) {
      const selectedNodeBottomY = 120.0;
      final bridgePath = Path()
        ..moveTo(selectedX!, selectedNodeBottomY)
        ..lineTo(selectedX!, size.height);
      final bridgeMetric = bridgePath.computeMetrics().first;
      canvas.drawPath(
          bridgeMetric.extractPath(0, bridgeMetric.length * animation.value),
          paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _WorkstationTreePainter extends CustomPainter {
  final List<AlertNode> workstations;
  final double spacing;
  final double parentX;
  final Animation<double> animation;
  final Color lineColor;
  _WorkstationTreePainter({
    required this.workstations,
    required this.spacing,
    required this.parentX,
    required this.animation,
    required this.lineColor,
  }) : super(repaint: animation);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lineColor
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
      canvas.drawPath(
          metric.extractPath(0, metric.length * animation.value), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
