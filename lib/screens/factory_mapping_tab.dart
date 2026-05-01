// lib/screens/factory_mapping_tab.dart
//
// Production-manager facing map editor. Renders a snap-to-grid canvas where
// the manager places the factory entrance, drops station chips (C1S1, C2S2…)
// from a live left-side palette, and connects stations belonging to the SAME
// conveyor with edges. Mismatched-conveyor connections raise an inline error.
// Save persists the FactoryMap to RTDB; supervisors see updates in real time.

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/factory_map_model.dart';
import '../models/hierarchy_model.dart';
import '../services/hierarchy_service.dart';
import '../theme.dart';

class FactoryMappingTab extends StatefulWidget {
  final List<Factory> factories;
  final HierarchyService service;

  const FactoryMappingTab({
    super.key,
    required this.factories,
    required this.service,
  });

  @override
  State<FactoryMappingTab> createState() => _FactoryMappingTabState();
}

enum _Tool { place, connect, erase, entrance }

class _FactoryMappingTabState extends State<FactoryMappingTab> {
  String? _selectedFactoryId;
  StreamSubscription<FactoryMap>? _mapSub;
  FactoryMap? _liveMap;
  FactoryMap? _draft;
  final List<FactoryMap> _undo = [];
  bool _saving = false;
  _Tool _tool = _Tool.place;
  String? _connectFromKey;

  @override
  void initState() {
    super.initState();
    _selectInitialFactory();
  }

  @override
  void didUpdateWidget(covariant FactoryMappingTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selectedFactoryId == null ||
        !widget.factories.any((f) => f.id == _selectedFactoryId)) {
      _selectInitialFactory();
    }
  }

  @override
  void dispose() {
    _mapSub?.cancel();
    super.dispose();
  }

  void _selectInitialFactory() {
    if (widget.factories.isEmpty) return;
    _selectFactory(widget.factories.first.id);
  }

  void _selectFactory(String factoryId) {
    _mapSub?.cancel();
    setState(() {
      _selectedFactoryId = factoryId;
      _liveMap = null;
      _draft = null;
      _undo.clear();
      _connectFromKey = null;
    });
    _mapSub = widget.service.streamFactoryMap(factoryId).listen((map) {
      if (!mounted) return;
      setState(() {
        _liveMap = map;
        // Initialize the draft once with whatever is in storage. Subsequent
        // remote updates do NOT clobber a dirty draft.
        _draft ??= map;
      });
    });
  }

  Factory? get _selectedFactory {
    final id = _selectedFactoryId;
    if (id == null) return null;
    for (final f in widget.factories) {
      if (f.id == id) return f;
    }
    return null;
  }

  bool get _dirty {
    final draft = _draft;
    final live = _liveMap;
    if (draft == null || live == null) return false;
    if (draft.entrance != live.entrance) return true;
    if (draft.nodes.length != live.nodes.length) return true;
    if (draft.edges.length != live.edges.length) return true;
    final dnodes = {for (final n in draft.nodes) n.key: n.cell};
    for (final n in live.nodes) {
      if (dnodes[n.key] != n.cell) return true;
    }
    final dedges = {for (final e in draft.edges) e.id};
    for (final e in live.edges) {
      if (!dedges.contains(e.id)) return true;
    }
    return false;
  }

  void _pushUndo() {
    final draft = _draft;
    if (draft == null) return;
    _undo.add(draft);
    if (_undo.length > 50) _undo.removeAt(0);
  }

  void _mutate(FactoryMap Function(FactoryMap) update) {
    final draft = _draft;
    if (draft == null) return;
    _pushUndo();
    setState(() => _draft = update(draft));
  }

  void _undoLast() {
    if (_undo.isEmpty) return;
    setState(() {
      _draft = _undo.removeLast();
      _connectFromKey = null;
    });
  }

  Future<void> _save() async {
    final draft = _draft;
    final factory = _selectedFactory;
    if (draft == null || factory == null) return;
    setState(() => _saving = true);
    try {
      await widget.service.saveFactoryMap(draft);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Map saved for ${factory.name}'),
          backgroundColor: context.appTheme.green,
        ),
      );
      setState(() {
        _saving = false;
        _undo.clear();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Save failed: $e'),
          backgroundColor: context.appTheme.red,
        ),
      );
    }
  }

  // ── Editing ops ───────────────────────────────────────────────────────────

  void _placeEntrance(MapCell cell) {
    _mutate((m) => m.copyWith(entrance: cell));
  }

  void _placeNode(MapNode candidate, MapCell cell) {
    _mutate((m) {
      if (m.nodes.any((n) => n.cell == cell)) return m;
      final updated = [...m.nodes.where((n) => n.key != candidate.key)];
      updated.add(candidate.copyWith(cell: cell));
      return m.copyWith(nodes: updated);
    });
  }

  void _moveNode(String key, MapCell cell) {
    _mutate((m) {
      if (m.nodes.any((n) => n.cell == cell && n.key != key)) return m;
      final updated = m.nodes
          .map((n) => n.key == key ? n.copyWith(cell: cell) : n)
          .toList();
      return m.copyWith(nodes: updated);
    });
  }

  void _deleteNode(String key) {
    _mutate((m) {
      final nodes = m.nodes.where((n) => n.key != key).toList();
      final edges =
          m.edges.where((e) => e.fromKey != key && e.toKey != key).toList();
      return m.copyWith(nodes: nodes, edges: edges);
    });
  }

  void _deleteEntrance() {
    _mutate((m) => m.copyWith(clearEntrance: true));
  }

  void _toggleConnect(MapNode node) {
    final from = _connectFromKey;
    if (from == null || from == node.key) {
      setState(() => _connectFromKey = node.key);
      return;
    }
    final draft = _draft;
    if (draft == null) return;
    final fromNode = draft.nodeByKey(from);
    if (fromNode == null) {
      setState(() => _connectFromKey = node.key);
      return;
    }
    if (fromNode.conveyorNumber != node.conveyorNumber) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: context.appTheme.red,
          content: Text(
            'Cannot connect ${fromNode.label} (C${fromNode.conveyorNumber}) '
            'to ${node.label} (C${node.conveyorNumber}). Stations on different '
            'conveyors cannot share a line.',
          ),
        ),
      );
      setState(() => _connectFromKey = null);
      return;
    }
    final edge = MapEdge(
      fromKey: fromNode.key,
      toKey: node.key,
      conveyorNumber: node.conveyorNumber,
    );
    _mutate((m) {
      if (m.edges.any((e) => e.id == edge.id)) return m;
      return m.copyWith(edges: [...m.edges, edge]);
    });
    setState(() => _connectFromKey = null);
  }

  void _deleteEdge(MapEdge edge) {
    _mutate((m) => m.copyWith(
        edges: m.edges.where((e) => e.id != edge.id).toList()));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    if (widget.factories.isEmpty) {
      return Center(
        child: Text('Add a factory in the Structure tab first.',
            style: TextStyle(color: t.muted)),
      );
    }
    final factory = _selectedFactory;
    if (factory == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final draft = _draft;
    if (draft == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(
            factories: widget.factories,
            selectedId: _selectedFactoryId!,
            onChanged: _selectFactory,
            tool: _tool,
            onTool: (t) => setState(() {
              _tool = t;
              _connectFromKey = null;
            }),
            onUndo: _undo.isEmpty ? null : _undoLast,
            onSave: (_dirty && !_saving) ? _save : null,
            saving: _saving,
            dirty: _dirty,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 260,
                  child: _StationPalette(
                    factory: factory,
                    placedKeys: draft.nodes.map((n) => n.key).toSet(),
                    onTapNode: (node) {
                      // tap = pulse / select for connect mode
                      if (_tool == _Tool.connect) _toggleConnect(node);
                    },
                    pendingDragNode: null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _MapCanvas(
                    map: draft,
                    factory: factory,
                    tool: _tool,
                    connectFromKey: _connectFromKey,
                    onCellTap: (cell) {
                      if (_tool == _Tool.entrance) {
                        _placeEntrance(cell);
                      }
                    },
                    onNodeTap: (node) {
                      if (_tool == _Tool.connect) {
                        _toggleConnect(node);
                      } else if (_tool == _Tool.erase) {
                        _deleteNode(node.key);
                      }
                    },
                    onEntranceTap: () {
                      if (_tool == _Tool.erase) _deleteEntrance();
                    },
                    onEdgeTap: (edge) {
                      if (_tool == _Tool.erase) _deleteEdge(edge);
                    },
                    onAcceptCandidate: (candidate, cell) {
                      _placeNode(candidate, cell);
                    },
                    onMoveNode: _moveNode,
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

// ─── Header / toolbar ───────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final List<Factory> factories;
  final String selectedId;
  final ValueChanged<String> onChanged;
  final _Tool tool;
  final ValueChanged<_Tool> onTool;
  final VoidCallback? onUndo;
  final VoidCallback? onSave;
  final bool saving;
  final bool dirty;

  const _Header({
    required this.factories,
    required this.selectedId,
    required this.onChanged,
    required this.tool,
    required this.onTool,
    required this.onUndo,
    required this.onSave,
    required this.saving,
    required this.dirty,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: context.isDark ? 0.20 : 0.05),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [t.navy, t.blue],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.map_rounded, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Factory Mapping',
                  style: TextStyle(
                      color: t.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w900)),
              Text('Drag stations onto the grid, then connect each conveyor.',
                  style: TextStyle(color: t.muted, fontSize: 11)),
            ],
          ),
          const SizedBox(width: 18),
          SizedBox(
            width: 220,
            child: DropdownButtonFormField<String>(
              value: selectedId,
              isDense: true,
              decoration: const InputDecoration(
                labelText: 'Factory',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              ),
              items: factories
                  .map((f) =>
                      DropdownMenuItem(value: f.id, child: Text(f.name)))
                  .toList(),
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
          const Spacer(),
          _ToolButton(
            icon: Icons.door_front_door_outlined,
            label: 'Entrance',
            color: t.green,
            active: tool == _Tool.entrance,
            onTap: () => onTool(_Tool.entrance),
          ),
          const SizedBox(width: 6),
          _ToolButton(
            icon: Icons.touch_app_outlined,
            label: 'Place',
            color: t.navy,
            active: tool == _Tool.place,
            onTap: () => onTool(_Tool.place),
          ),
          const SizedBox(width: 6),
          _ToolButton(
            icon: Icons.linear_scale_rounded,
            label: 'Connect',
            color: t.blue,
            active: tool == _Tool.connect,
            onTap: () => onTool(_Tool.connect),
          ),
          const SizedBox(width: 6),
          _ToolButton(
            icon: Icons.delete_sweep_outlined,
            label: 'Erase',
            color: t.red,
            active: tool == _Tool.erase,
            onTap: () => onTool(_Tool.erase),
          ),
          const SizedBox(width: 14),
          OutlinedButton.icon(
            onPressed: onUndo,
            icon: const Icon(Icons.undo_rounded, size: 16),
            label: const Text('Undo'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: onSave,
            icon: saving
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Icon(dirty ? Icons.save_rounded : Icons.check_rounded,
                    size: 16),
            label: Text(saving
                ? 'Saving…'
                : dirty
                    ? 'Save'
                    : 'Saved'),
            style: FilledButton.styleFrom(
              backgroundColor: dirty ? t.green : t.muted,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool active;
  final VoidCallback onTap;

  const _ToolButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: active ? color : color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: active ? 1 : 0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: active ? Colors.white : color),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: active ? Colors.white : t.text,
                )),
          ],
        ),
      ),
    );
  }
}

// ─── Left palette ────────────────────────────────────────────────────────────

class _StationPalette extends StatelessWidget {
  final Factory factory;
  final Set<String> placedKeys;
  final ValueChanged<MapNode> onTapNode;
  final MapNode? pendingDragNode;

  const _StationPalette({
    required this.factory,
    required this.placedKeys,
    required this.onTapNode,
    required this.pendingDragNode,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final conveyors = factory.conveyors.values.toList()
      ..sort((a, b) => a.number.compareTo(b.number));

    return Container(
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
            child: Row(
              children: [
                Icon(Icons.dashboard_customize_rounded, color: t.navy, size: 18),
                const SizedBox(width: 8),
                Text('Stations',
                    style: TextStyle(
                        color: t.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w900)),
                const Spacer(),
                Text('${placedKeys.length} placed',
                    style: TextStyle(color: t.muted, fontSize: 11)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: Text(
              'Drag a chip onto the grid. Live updates from Hierarchy.',
              style: TextStyle(color: t.muted, fontSize: 11),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: conveyors.isEmpty
                ? Center(
                    child: Text('No conveyors yet',
                        style: TextStyle(color: t.muted)))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: conveyors.length,
                    itemBuilder: (context, idx) {
                      final c = conveyors[idx];
                      final color = _conveyorColor(c.number, t);
                      final stations = c.stations.values.toList()
                        ..sort((a, b) =>
                            _stationNum(a).compareTo(_stationNum(b)));
                      return Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text('Conveyor ${c.number}',
                                    style: TextStyle(
                                        color: t.text,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w900)),
                                const Spacer(),
                                Text('${stations.length}',
                                    style: TextStyle(
                                        color: t.muted, fontSize: 11)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: stations.map((s) {
                                final stationNumber = _stationNum(s);
                                final node = MapNode(
                                  key: '${c.id}/${s.id}',
                                  conveyorId: c.id,
                                  stationId: s.id,
                                  conveyorNumber: c.number,
                                  stationNumber: stationNumber,
                                  cell: const MapCell(0, 0),
                                );
                                final placed = placedKeys.contains(node.key);
                                return _PaletteChip(
                                  node: node,
                                  color: color,
                                  placed: placed,
                                  onTap: () => onTapNode(node),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  static int _stationNum(Station s) =>
      int.tryParse(s.id.replaceFirst('station_', '')) ?? 0;
}

class _PaletteChip extends StatelessWidget {
  final MapNode node;
  final Color color;
  final bool placed;
  final VoidCallback onTap;

  const _PaletteChip({
    required this.node,
    required this.color,
    required this.placed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final body = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: placed
            ? color.withValues(alpha: 0.10)
            : color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: color.withValues(alpha: placed ? 0.3 : 0.7),
          width: 1.4,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text('${node.stationNumber}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w900)),
          ),
          const SizedBox(width: 6),
          Text(node.label,
              style: TextStyle(
                color: placed ? t.muted : t.text,
                fontSize: 12,
                fontWeight: FontWeight.w900,
                decoration: placed ? TextDecoration.lineThrough : null,
              )),
        ],
      ),
    );

    if (placed) {
      return Opacity(opacity: 0.55, child: body);
    }

    return Draggable<MapNode>(
      data: node,
      feedback: Material(
        color: Colors.transparent,
        child: Transform.scale(scale: 1.08, child: body),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: body),
      child: GestureDetector(onTap: onTap, child: body),
    );
  }
}

// ─── Canvas ─────────────────────────────────────────────────────────────────

class _MapCanvas extends StatefulWidget {
  final FactoryMap map;
  final Factory factory;
  final _Tool tool;
  final String? connectFromKey;
  final ValueChanged<MapCell> onCellTap;
  final ValueChanged<MapNode> onNodeTap;
  final VoidCallback onEntranceTap;
  final ValueChanged<MapEdge> onEdgeTap;
  final void Function(MapNode node, MapCell cell) onAcceptCandidate;
  final void Function(String key, MapCell cell) onMoveNode;

  const _MapCanvas({
    required this.map,
    required this.factory,
    required this.tool,
    required this.connectFromKey,
    required this.onCellTap,
    required this.onNodeTap,
    required this.onEntranceTap,
    required this.onEdgeTap,
    required this.onAcceptCandidate,
    required this.onMoveNode,
  });

  @override
  State<_MapCanvas> createState() => _MapCanvasState();
}

class _MapCanvasState extends State<_MapCanvas> {
  MapCell? _hoverCell;

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final cellSize = math.max(
          24.0,
          math.min(
            constraints.maxWidth / widget.map.cols,
            constraints.maxHeight / widget.map.rows,
          ),
        );
        final width = cellSize * widget.map.cols;
        final height = cellSize * widget.map.rows;

        return Container(
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: t.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black
                    .withValues(alpha: context.isDark ? 0.22 : 0.06),
                blurRadius: 22,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 3,
              boundaryMargin: const EdgeInsets.all(160),
              child: SizedBox(
                width: width,
                height: height,
                child: DragTarget<MapNode>(
                  onWillAcceptWithDetails: (_) => true,
                  onMove: (details) {
                    final box = context.findRenderObject() as RenderBox?;
                    if (box == null) return;
                    final local = box.globalToLocal(details.offset);
                    setState(() => _hoverCell = _cellAt(local, cellSize));
                  },
                  onLeave: (_) => setState(() => _hoverCell = null),
                  onAcceptWithDetails: (details) {
                    final box = context.findRenderObject() as RenderBox?;
                    if (box == null) return;
                    final local = box.globalToLocal(details.offset);
                    final cell = _cellAt(local, cellSize);
                    if (cell == null) return;
                    final existing = widget.map.nodes
                        .where((n) => n.key == details.data.key)
                        .firstOrNull;
                    if (existing != null) {
                      widget.onMoveNode(details.data.key, cell);
                    } else {
                      widget.onAcceptCandidate(details.data, cell);
                    }
                    setState(() => _hoverCell = null);
                  },
                  builder: (context, candidate, _) {
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (details) {
                        final cell = _cellAt(details.localPosition, cellSize);
                        if (cell == null) return;
                        // hit test nodes / entrance / edges
                        final node = _hitNode(cell);
                        if (node != null) {
                          widget.onNodeTap(node);
                          return;
                        }
                        if (widget.map.entrance == cell) {
                          widget.onEntranceTap();
                          return;
                        }
                        final edge = _hitEdge(details.localPosition, cellSize);
                        if (edge != null) {
                          widget.onEdgeTap(edge);
                          return;
                        }
                        widget.onCellTap(cell);
                      },
                      child: CustomPaint(
                        size: Size(width, height),
                        painter: _MapCanvasPainter(
                          map: widget.map,
                          theme: t,
                          isDark: context.isDark,
                          cellSize: cellSize,
                          tool: widget.tool,
                          connectFromKey: widget.connectFromKey,
                          hoverCell: _hoverCell,
                          dragging: candidate.isNotEmpty,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  MapCell? _cellAt(Offset pos, double cellSize) {
    if (pos.dx < 0 || pos.dy < 0) return null;
    final col = (pos.dx / cellSize).floor();
    final row = (pos.dy / cellSize).floor();
    if (row < 0 || col < 0) return null;
    if (row >= widget.map.rows || col >= widget.map.cols) return null;
    return MapCell(row, col);
  }

  MapNode? _hitNode(MapCell cell) {
    for (final n in widget.map.nodes) {
      if (n.cell == cell) return n;
    }
    return null;
  }

  MapEdge? _hitEdge(Offset pos, double cellSize) {
    const tolerance = 8.0;
    for (final edge in widget.map.edges) {
      final from = widget.map.nodeByKey(edge.fromKey);
      final to = widget.map.nodeByKey(edge.toKey);
      if (from == null || to == null) continue;
      final p1 = _centerOf(from.cell, cellSize);
      final p2 = _centerOf(to.cell, cellSize);
      if (_distanceToSegment(pos, p1, p2) <= tolerance) return edge;
    }
    return null;
  }

  Offset _centerOf(MapCell cell, double cellSize) =>
      Offset(cell.col * cellSize + cellSize / 2,
          cell.row * cellSize + cellSize / 2);

  double _distanceToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final t = ((p - a).dx * ab.dx + (p - a).dy * ab.dy) /
        (ab.distanceSquared.clamp(1e-6, double.infinity));
    final tt = t.clamp(0.0, 1.0);
    final projection = a + ab * tt;
    return (p - projection).distance;
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class _MapCanvasPainter extends CustomPainter {
  final FactoryMap map;
  final AppTheme theme;
  final bool isDark;
  final double cellSize;
  final _Tool tool;
  final String? connectFromKey;
  final MapCell? hoverCell;
  final bool dragging;

  _MapCanvasPainter({
    required this.map,
    required this.theme,
    required this.isDark,
    required this.cellSize,
    required this.tool,
    required this.connectFromKey,
    required this.hoverCell,
    required this.dragging,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawBackground(canvas, size);
    _drawGrid(canvas, size);
    _drawHover(canvas);
    _drawEdges(canvas);
    _drawEntrance(canvas);
    _drawNodes(canvas);
  }

  void _drawBackground(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        Offset(size.width, size.height),
        [
          isDark ? const Color(0xFF111C32) : const Color(0xFFF4F7FB),
          isDark ? const Color(0xFF0B1322) : const Color(0xFFE8EEF7),
        ],
      );
    canvas.drawRect(Offset.zero & size, paint);
  }

  void _drawGrid(Canvas canvas, Size size) {
    final line = Paint()
      ..color = theme.border.withValues(alpha: isDark ? 0.32 : 0.6)
      ..strokeWidth = 0.6;
    for (var c = 0; c <= map.cols; c++) {
      final x = c * cellSize;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
    for (var r = 0; r <= map.rows; r++) {
      final y = r * cellSize;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
  }

  void _drawHover(Canvas canvas) {
    final cell = hoverCell;
    if (cell == null) return;
    final rect = Rect.fromLTWH(
        cell.col * cellSize, cell.row * cellSize, cellSize, cellSize);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(2), const Radius.circular(8)),
      Paint()
        ..color = (dragging ? theme.green : theme.blue).withValues(alpha: 0.18),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(2), const Radius.circular(8)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = (dragging ? theme.green : theme.blue),
    );
  }

  void _drawEdges(Canvas canvas) {
    for (final edge in map.edges) {
      final from = map.nodeByKey(edge.fromKey);
      final to = map.nodeByKey(edge.toKey);
      if (from == null || to == null) continue;
      final color = _conveyorColor(edge.conveyorNumber, theme);
      final p1 = _center(from.cell);
      final p2 = _center(to.cell);
      final outer = Paint()
        ..color = color.withValues(alpha: isDark ? 0.20 : 0.18)
        ..strokeWidth = 14
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      canvas.drawLine(p1, p2, outer);
      final core = Paint()
        ..color = color
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      canvas.drawLine(p1, p2, core);
    }
  }

  void _drawEntrance(Canvas canvas) {
    final cell = map.entrance;
    if (cell == null) return;
    final center = _center(cell);
    final size = cellSize * 0.78;
    final rect = Rect.fromCenter(center: center, width: size, height: size);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(10)),
      Paint()..color = theme.green,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.inflate(3), const Radius.circular(12)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = theme.green.withValues(alpha: 0.45),
    );
    final iconPainter = TextPainter(
      text: const TextSpan(
        text: '🏭',
        style: TextStyle(fontSize: 18),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    iconPainter.paint(
      canvas,
      center - Offset(iconPainter.width / 2, iconPainter.height / 2),
    );
    _label(canvas, 'Factory Entrance (0,0)',
        center + Offset(0, size / 2 + 12), theme.green);
  }

  void _drawNodes(Canvas canvas) {
    for (final node in map.nodes) {
      final color = _conveyorColor(node.conveyorNumber, theme);
      final center = _center(node.cell);
      final radius = cellSize * 0.34;
      final isConnectFrom = connectFromKey == node.key;

      if (isConnectFrom) {
        canvas.drawCircle(center, radius + 8,
            Paint()..color = color.withValues(alpha: 0.22));
      }
      canvas.drawCircle(center, radius, Paint()..color = color);
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = isConnectFrom ? theme.text : theme.card,
      );
      final txt = TextPainter(
        text: TextSpan(
          text: node.label,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w900),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      txt.paint(canvas,
          center - Offset(txt.width / 2, txt.height / 2));
    }
  }

  void _label(Canvas canvas, String text, Offset anchor, Color accent) {
    final tp = TextPainter(
      text: TextSpan(
          text: text,
          style: TextStyle(
              color: theme.text,
              fontSize: 10,
              fontWeight: FontWeight.w800)),
      textDirection: TextDirection.ltr,
    )..layout();
    final rect = Rect.fromCenter(
      center: anchor,
      width: tp.width + 14,
      height: tp.height + 8,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(6)),
      Paint()..color = theme.card.withValues(alpha: 0.96),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(6)),
      Paint()
        ..style = PaintingStyle.stroke
        ..color = accent.withValues(alpha: 0.4)
        ..strokeWidth = 1,
    );
    tp.paint(canvas, anchor - Offset(tp.width / 2, tp.height / 2));
  }

  Offset _center(MapCell cell) =>
      Offset(cell.col * cellSize + cellSize / 2,
          cell.row * cellSize + cellSize / 2);

  @override
  bool shouldRepaint(covariant _MapCanvasPainter old) =>
      old.map != map ||
      old.cellSize != cellSize ||
      old.hoverCell != hoverCell ||
      old.dragging != dragging ||
      old.connectFromKey != connectFromKey ||
      old.tool != tool ||
      old.isDark != isDark;
}

// ─── Shared color helper ─────────────────────────────────────────────────────

Color _conveyorColor(int number, AppTheme t) {
  // Deterministic, well-spaced hues per conveyor — never relies on the user
  // remembering a legend; same conveyor gets the same color across both the
  // editor and supervisor locator.
  const palette = <Color>[
    Color(0xFF2563EB), // blue
    Color(0xFFEA580C), // orange
    Color(0xFF16A34A), // green
    Color(0xFF9333EA), // purple
    Color(0xFFE11D48), // rose
    Color(0xFF0891B2), // cyan
    Color(0xFFCA8A04), // amber
    Color(0xFF65A30D), // lime
  ];
  return palette[(number - 1).abs() % palette.length];
}

/// Exported for use by the locator painter so colors stay in sync.
Color factoryMapConveyorColor(int number, AppTheme theme) =>
    _conveyorColor(number, theme);
