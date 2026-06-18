import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../superadmin_theme.dart';
import 'hw_models.dart';
import 'hw_painters.dart';
import 'hw_runtime.dart';

/// The interactive bench: a pan/zoom schematic canvas you drag components onto
/// and wire pin-to-pin, plus the component palette drawer. Designed so a
/// zero-experience operator can build a working circuit by dragging and
/// connecting — exactly like Wokwi/Proteus, with the Smart Industrial Alert
/// command-center finish.

typedef HwPinRef = ({String comp, String pin});

class HwCanvas extends StatefulWidget {
  final HwCircuit circuit;
  final HwSimulator sim;
  final ValueChanged<String?>? onSelect;
  final VoidCallback onChanged;
  final String? selectedId;

  /// When true, tapping a wire deletes it (scissors mode).
  final bool wireCutMode;

  const HwCanvas({
    super.key,
    required this.circuit,
    required this.sim,
    required this.onChanged,
    this.onSelect,
    this.selectedId,
    this.wireCutMode = false,
  });

  @override
  State<HwCanvas> createState() => HwCanvasState();
}

class HwCanvasState extends State<HwCanvas> with SingleTickerProviderStateMixin {
  final GlobalKey _boardKey = GlobalKey();
  late final AnimationController _pulse;

  Offset _pan = const Offset(40, 40);
  double _scale = 1.0;

  // Gesture bookkeeping.
  Offset _startFocal = Offset.zero;
  Offset _startPan = Offset.zero;
  double _startScale = 1.0;
  String? _dragComp;
  Offset _dragGrab = Offset.zero;
  bool _panning = false;
  String? _pressingButton;

  // Wiring.
  HwPinRef? _pendingPin;
  Offset _wireCursor = Offset.zero;

  String? get _selected => widget.selectedId;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Offset _toWorld(Offset screen) => (screen - _pan) / _scale;
  Offset _snap(Offset w) =>
      Offset((w.dx / kHwGrid).round() * kHwGrid, (w.dy / kHwGrid).round() * kHwGrid);

  void resetView() => setState(() {
        _pan = const Offset(40, 40);
        _scale = 1.0;
      });

  void zoomBy(double factor) {
    setState(() {
      final box = _boardKey.currentContext?.findRenderObject() as RenderBox?;
      final center = box != null
          ? Offset(box.size.width / 2, box.size.height / 2)
          : const Offset(300, 200);
      final before = _toWorld(center);
      _scale = (_scale * factor).clamp(0.35, 3.0);
      _pan = center - before * _scale;
    });
  }

  void addComponent(String type, Offset world) {
    final def = kHwCatalog[type];
    if (def == null) return;
    final c = HwComponent(
      id: hwNewId('cmp'),
      type: type,
      x: _snap(world).dx,
      y: _snap(world).dy,
      params: Map<String, Object?>.from(def.defaults),
    );
    // Prevent two controllers from confusing the sketch target.
    setState(() => widget.circuit.components.add(c));
    widget.sim.setCircuit(widget.circuit);
    widget.onSelect?.call(c.id);
    widget.onChanged();
  }

  void deleteSelected() {
    // A selected wire takes priority over a selected component.
    if (_selectedWire != null) {
      _deleteWire(_selectedWire!);
      return;
    }
    final id = _selected;
    if (id == null) return;
    widget.circuit.components.removeWhere((c) => c.id == id);
    widget.circuit.wires
        .removeWhere((w) => w.fromComp == id || w.toComp == id);
    widget.sim.setCircuit(widget.circuit);
    widget.onSelect?.call(null);
    widget.onChanged();
    setState(() {});
  }

  void _deleteWire(HwWire w) {
    widget.circuit.wires.removeWhere((x) => x.id == w.id);
    if (_selectedWire?.id == w.id) _selectedWire = null;
    widget.sim.setCircuit(widget.circuit);
    widget.onChanged();
    setState(() {});
  }

  void rotateSelected() {
    final c = widget.circuit.byId(_selected ?? '');
    if (c == null) return;
    setState(() => c.rot = (c.rot + 1) % 4);
    widget.sim.setCircuit(widget.circuit);
    widget.onChanged();
  }

  HwPinRef? _hitPin(Offset world) {
    final tol = math.max(kHwPinHit, kHwPinHit / _scale);
    for (final c in widget.circuit.components) {
      final centers = c.pinCenters();
      for (final entry in centers.entries) {
        if ((entry.value - world).distance <= tol) {
          return (comp: c.id, pin: entry.key);
        }
      }
    }
    return null;
  }

  String? _hitComponent(Offset world) {
    // Topmost first.
    for (var i = widget.circuit.components.length - 1; i >= 0; i--) {
      final c = widget.circuit.components[i];
      final fp = c.footprint;
      final rect = Rect.fromLTWH(c.x - 4, c.y - 4, fp.width + 8, fp.height + 8);
      if (rect.contains(world)) return c.id;
    }
    return null;
  }

  HwWire? _hitWire(Offset world) {
    final tol = math.max(8.0, 8 / _scale);
    for (final w in widget.circuit.wires) {
      final pts = _wirePointsOf(w);
      if (pts == null) continue;
      if (hwPolylineDistance(pts, world) <= tol) return w;
    }
    return null;
  }

  /// Absolute orthogonal route points for a wire (null if an endpoint is gone).
  List<Offset>? _wirePointsOf(HwWire w) {
    final ca = widget.circuit.byId(w.fromComp);
    final cb = widget.circuit.byId(w.toComp);
    final a = ca?.pinCenter(w.fromPin);
    final b = cb?.pinCenter(w.toPin);
    if (ca == null || cb == null || a == null || b == null) return null;
    return hwRoutePoints(
        a, b, hwPinExitDir(ca, w.fromPin), hwPinExitDir(cb, w.toPin));
  }

  void _commitWire(HwPinRef from, HwPinRef to) {
    if (from.comp == to.comp && from.pin == to.pin) return;
    // No duplicate identical wire.
    final exists = widget.circuit.wires.any((w) =>
        (w.fromComp == from.comp &&
            w.fromPin == from.pin &&
            w.toComp == to.comp &&
            w.toPin == to.pin) ||
        (w.fromComp == to.comp &&
            w.fromPin == to.pin &&
            w.toComp == from.comp &&
            w.toPin == from.pin));
    if (exists) return;
    final fromKind = widget.circuit.byId(from.comp)?.def.pin(from.pin)?.kind;
    final color = _wireColor(fromKind);
    widget.circuit.wires.add(HwWire(
      id: hwNewId('w'),
      fromComp: from.comp,
      fromPin: from.pin,
      toComp: to.comp,
      toPin: to.pin,
      colorValue: color,
    ));
    widget.sim.setCircuit(widget.circuit);
    widget.onChanged();
  }

  int _wireColor(HwPinKind? kind) => switch (kind) {
        HwPinKind.power => 0xFFEF4444,
        HwPinKind.anode => 0xFFEF4444,
        HwPinKind.ground => 0xFF94A3B8,
        HwPinKind.cathode => 0xFF94A3B8,
        HwPinKind.i2cSda => 0xFFA78BFA,
        HwPinKind.i2cScl => 0xFFF59E0B,
        _ => 0xFF22D3EE,
      };

  // ── gesture handlers ──
  void _onScaleStart(ScaleStartDetails d) {
    final world = _toWorld(d.localFocalPoint);
    _startFocal = d.localFocalPoint;
    _startPan = _pan;
    _startScale = _scale;
    _dragComp = null;
    _panning = false;
    _pressingButton = null;

    if (d.pointerCount >= 2) {
      _panning = true;
      return;
    }
    // Scissors mode: tap a wire to cut it; otherwise just pan.
    if (widget.wireCutMode) {
      final wire = _hitWire(world);
      if (wire != null) {
        _deleteWire(wire);
        return;
      }
      _panning = true;
      return;
    }
    // Pin → start wire.
    final pin = _hitPin(world);
    if (pin != null) {
      _pendingPin = pin;
      _wireCursor = world;
      setState(() {});
      return;
    }
    // Component → press button (sim) or drag.
    final compId = _hitComponent(world);
    if (compId != null) {
      final c = widget.circuit.byId(compId);
      widget.onSelect?.call(compId);
      if (c != null && c.type == 'button' && widget.sim.isRunning) {
        _pressingButton = compId;
        widget.sim.setParam(compId, 'pressed', true);
        return;
      }
      _dragComp = compId;
      _dragGrab = world - c!.origin;
      return;
    }
    // Empty → pan, and clear selection / pending wire.
    if (_pendingPin != null) {
      setState(() => _pendingPin = null);
    } else {
      final wire = _hitWire(world);
      widget.onSelect?.call(null);
      if (wire != null) _selectWire(wire);
    }
    _panning = true;
  }

  HwWire? _selectedWire;
  void _selectWire(HwWire w) => setState(() => _selectedWire = w);

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (_pendingPin != null) {
      setState(() => _wireCursor = _toWorld(d.localFocalPoint));
      return;
    }
    if (d.pointerCount >= 2 || (d.scale - 1.0).abs() > 0.01) {
      final newScale = (_startScale * d.scale).clamp(0.35, 3.0);
      final worldBefore = (_startFocal - _startPan) / _startScale;
      setState(() {
        _scale = newScale;
        _pan = d.localFocalPoint - worldBefore * newScale;
      });
      return;
    }
    if (_dragComp != null) {
      final c = widget.circuit.byId(_dragComp!);
      if (c == null) return;
      final world = _toWorld(d.localFocalPoint);
      final p = _snap(world - _dragGrab);
      setState(() {
        c.x = p.dx;
        c.y = p.dy;
      });
      return;
    }
    if (_panning) {
      setState(() => _pan = _startPan + (d.localFocalPoint - _startFocal));
    }
  }

  void _onScaleEnd(ScaleEndDetails d) {
    if (_pendingPin != null) {
      final target = _hitPin(_wireCursor);
      if (target != null && target.comp != _pendingPin!.comp) {
        _commitWire(_pendingPin!, target);
        setState(() => _pendingPin = null);
      } else if (target == null) {
        // Keep armed for tap-tap completion only if it was a tap (no drag).
        setState(() {});
      } else {
        setState(() => _pendingPin = null);
      }
    }
    if (_dragComp != null) {
      widget.onChanged();
      widget.sim.setCircuit(widget.circuit);
      _dragComp = null;
    }
    if (_pressingButton != null) {
      widget.sim.setParam(_pressingButton!, 'pressed', false);
      _pressingButton = null;
    }
    _panning = false;
  }

  void _onPointerSignal(PointerSignalEvent e) {
    if (e is PointerScrollEvent) {
      final box = _boardKey.currentContext?.findRenderObject() as RenderBox?;
      if (box == null) return;
      final local = box.globalToLocal(e.position);
      final before = _toWorld(local);
      setState(() {
        _scale = (_scale * (e.scrollDelta.dy < 0 ? 1.1 : 0.9)).clamp(0.35, 3.0);
        _pan = local - before * _scale;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DragTarget<String>(
      onAcceptWithDetails: (d) {
        final box = _boardKey.currentContext?.findRenderObject() as RenderBox?;
        if (box == null) return;
        final local = box.globalToLocal(d.offset);
        addComponent(d.data, _toWorld(local + const Offset(20, 20)));
      },
      builder: (context, candidate, rejected) {
        final hot = candidate.isNotEmpty;
        return Listener(
          onPointerSignal: _onPointerSignal,
          child: GestureDetector(
            onScaleStart: _onScaleStart,
            onScaleUpdate: _onScaleUpdate,
            onScaleEnd: _onScaleEnd,
            child: Container(
              key: _boardKey,
              clipBehavior: Clip.hardEdge,
              decoration: BoxDecoration(
                color: const Color(0xFF050B16),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: hot ? Sa.cyan : Sa.border,
                    width: hot ? 1.6 : 1),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: AnimatedBuilder(
                  animation: Listenable.merge([widget.sim, _pulse]),
                  builder: (context, _) {
                    return CustomPaint(
                      painter: _SchematicPainter(
                        circuit: widget.circuit,
                        sim: widget.sim,
                        pan: _pan,
                        scale: _scale,
                        selectedId: _selected,
                        selectedWireId: _selectedWire?.id,
                        pending: _pendingPin,
                        wireCursor: _wireCursor,
                        pulse: _pulse.value,
                      ),
                      child: const SizedBox.expand(),
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
}

class _SchematicPainter extends CustomPainter {
  final HwCircuit circuit;
  final HwSimulator sim;
  final Offset pan;
  final double scale;
  final String? selectedId;
  final String? selectedWireId;
  final HwPinRef? pending;
  final Offset wireCursor;
  final double pulse;

  _SchematicPainter({
    required this.circuit,
    required this.sim,
    required this.pan,
    required this.scale,
    required this.selectedId,
    required this.selectedWireId,
    required this.pending,
    required this.wireCursor,
    required this.pulse,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(pan.dx, pan.dy);
    canvas.scale(scale);

    final visible = Rect.fromLTWH(
      -pan.dx / scale,
      -pan.dy / scale,
      size.width / scale,
      size.height / scale,
    );
    drawHwGrid(canvas, visible, scale);

    // Wires under components, routed orthogonally so they never dive through a
    // component body (Proteus-clean).
    for (final w in circuit.wires) {
      final ca = circuit.byId(w.fromComp);
      final cb = circuit.byId(w.toComp);
      final a = ca?.pinCenter(w.fromPin);
      final b = cb?.pinCenter(w.toPin);
      if (ca == null || cb == null || a == null || b == null) continue;
      final pts = hwRoutePoints(
          a, b, hwPinExitDir(ca, w.fromPin), hwPinExitDir(cb, w.toPin));
      final hot = sim.pinIsHot(w.fromComp, w.fromPin) ||
          sim.pinIsHot(w.toComp, w.toPin);
      drawHwWire(canvas, pts, w.color,
          hot: hot, selected: w.id == selectedWireId);
      if (hot && sim.isRunning) {
        drawHwWirePulse(canvas, pts, pulse, const Color(0xFF6EE7B7));
      }
    }

    // Pending wire rubber-band.
    if (pending != null) {
      final ca = circuit.byId(pending!.comp);
      final a = ca?.pinCenter(pending!.pin);
      if (ca != null && a != null) {
        final da = hwPinExitDir(ca, pending!.pin);
        final delta = a - wireCursor;
        final db = (delta.dx.abs() >= delta.dy.abs())
            ? Offset(delta.dx >= 0 ? 1 : -1, 0)
            : Offset(0, delta.dy >= 0 ? 1 : -1);
        drawHwWire(canvas, hwRoutePoints(a, wireCursor, da, db), Sa.cyan,
            selected: true);
      }
    }

    // Components.
    for (final c in circuit.components) {
      drawHwComponent(canvas, c, sim: sim, selected: c.id == selectedId);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SchematicPainter old) => true;
}

// ───────────────────────── Component palette ─────────────────────────

class HwPalette extends StatelessWidget {
  /// Tapping a component (instead of dragging) drops it at canvas centre.
  final ValueChanged<String> onPick;
  const HwPalette({super.key, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final byCat = <HwCategory, List<HwComponentDef>>{};
    for (final def in kHwCatalog.values) {
      byCat.putIfAbsent(def.category, () => []).add(def);
    }
    final cats = HwCategory.values
        .where((c) => byCat.containsKey(c))
        .toList(growable: false);

    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 14),
      children: [
        for (final cat in cats) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
            child: Text(cat.label.toUpperCase(),
                style: Sa.mono(size: 9, color: Sa.muted, weight: FontWeight.w700)),
          ),
          ...byCat[cat]!.map((def) => _PaletteItem(def: def, onPick: onPick)),
        ],
      ],
    );
  }
}

class _PaletteItem extends StatelessWidget {
  final HwComponentDef def;
  final ValueChanged<String> onPick;
  const _PaletteItem({required this.def, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final tile = _tile(context, dragging: false);
    return Draggable<String>(
      data: def.type,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Transform.translate(
        offset: const Offset(-60, -24),
        child: Material(color: Colors.transparent, child: _tile(context, dragging: true)),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: tile),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => onPick(def.type),
        child: tile,
      ),
    );
  }

  Widget _tile(BuildContext context, {required bool dragging}) {
    return Container(
      width: 120,
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: dragging ? Sa.panelSolid : Sa.bgRaised.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: def.accent.withValues(alpha: dragging ? 0.9 : 0.35)),
        boxShadow: dragging
            ? [BoxShadow(color: def.accent.withValues(alpha: 0.3), blurRadius: 16)]
            : null,
      ),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: def.accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: def.accent.withValues(alpha: 0.5)),
            ),
            alignment: Alignment.center,
            child: Text(def.shortName.characters.take(3).toString(),
                style: Sa.mono(size: 7.5, color: def.accent, weight: FontWeight.w800)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(def.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Sa.body(size: 10.5, weight: FontWeight.w600)),
                Text(def.category.label,
                    style: Sa.mono(size: 7.5, color: Sa.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
