import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../superadmin_theme.dart';
import 'hw_ai_codegen.dart';
import 'hw_canvas.dart';
import 'hw_code_panel.dart';
import 'hw_connectivity.dart';
import 'hw_factory_binding.dart';
import 'hw_models.dart';
import 'hw_runtime.dart';
import 'hw_store.dart';

/// SuperAdmin Hardware Lab — a Proteus/Wokwi-class IoT design + simulation
/// bench, an Arduino IDE with AI code generation, a live ESP32→Firebase
/// connectivity tester, and the factory-wide machinery binding map. Built so a
/// zero-experience operator can drag, wire, generate code, simulate and verify
/// connectivity end-to-end.
class HardwareLab extends StatefulWidget {
  const HardwareLab({super.key});

  @override
  State<HardwareLab> createState() => _HardwareLabState();
}

class _HardwareLabState extends State<HardwareLab> {
  final HwLabStore _store = HwLabStore();
  final HwCodegenService _codegen = HwCodegenService();
  final GlobalKey<HwCanvasState> _canvasKey = GlobalKey<HwCanvasState>();

  late HwSimulator _sim;
  HwCircuit? _circuit;
  List<HwCircuit> _circuits = [];
  List<HwDeviceBinding> _bindings = [];
  String? _selected;
  int _view = 0; // 0 design · 1 connect · 2 factory map
  int _rightTab = 0; // 0 code · 1 properties
  bool _loading = true;
  bool _wireCut = false; // scissors mode: tap a wire to delete it

  Timer? _saveDebounce;

  @override
  void initState() {
    super.initState();
    _sim = HwSimulator(HwCircuit(id: 'boot', name: 'boot'));
    _boot();
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _sim.dispose();
    _codegen.close();
    super.dispose();
  }

  Future<void> _boot() async {
    final circuits = await _store.loadCircuits();
    final bindings = await _store.loadBindings();
    HwCircuit current;
    if (circuits.isEmpty) {
      current = _seedStarter();
      await _store.saveCircuit(current);
      circuits.add(current);
    } else {
      current = circuits.first;
    }
    if (!mounted) return;
    setState(() {
      _circuits = circuits;
      _bindings = bindings;
      _circuit = current;
      _sim = HwSimulator(current)..setCircuit(current);
      _loading = false;
    });
    _maybeShowGuide();
  }

  Future<void> _maybeShowGuide() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('hw_lab_seen_guide') == true) return;
      await prefs.setBool('hw_lab_seen_guide', true);
    } catch (_) {}
    if (!mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (mounted) _openGuide();
  }

  void _persistSoon() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 800), () {
      final c = _circuit;
      if (c != null) _store.saveCircuit(c);
    });
  }

  void _onCircuitChanged() {
    _persistSoon();
    if (mounted) setState(() {});
  }

  // ── starter circuit: ESP32 + resistor + LED, pre-wired & blinking ──
  HwCircuit _seedStarter() {
    final esp = HwComponent(
        id: 'starter-esp', type: 'esp32', x: 48, y: 72);
    final res = HwComponent(
        id: 'starter-res',
        type: 'resistor',
        x: 288,
        y: 120,
        params: {'ohms': 220});
    final led = HwComponent(
        id: 'starter-led',
        type: 'led',
        x: 432,
        y: 96,
        params: {'color': 'green'});
    return HwCircuit(
      id: hwNewId('cir'),
      name: 'Blink starter',
      components: [esp, res, led],
      wires: [
        HwWire(
            id: 'sw1',
            fromComp: 'starter-esp',
            fromPin: 'GPIO2',
            toComp: 'starter-res',
            toPin: 'a',
            colorValue: 0xFF22D3EE),
        HwWire(
            id: 'sw2',
            fromComp: 'starter-res',
            fromPin: 'b',
            toComp: 'starter-led',
            toPin: 'A',
            colorValue: 0xFF22D3EE),
        HwWire(
            id: 'sw3',
            fromComp: 'starter-led',
            fromPin: 'K',
            toComp: 'starter-esp',
            toPin: 'GND',
            colorValue: 0xFF94A3B8),
      ],
      sketch: '''// Welcome to the Hardware Lab! Press UPLOAD ▶ to run.
// This blinks the green LED wired to GPIO2 through a 220Ω resistor.
int led = 2;

void setup() {
  pinMode(led, OUTPUT);
  Serial.begin(115200);
  Serial.println("Smart Industrial Alert · device online");
}

void loop() {
  digitalWrite(led, HIGH);
  Serial.println("LED ON");
  delay(600);
  digitalWrite(led, LOW);
  Serial.println("LED OFF");
  delay(600);
}
''',
    );
  }

  // ── circuit management ──
  Future<void> _newCircuit() async {
    final name = await _promptText('New circuit', 'Circuit name', 'Untitled circuit');
    if (name == null) return;
    final c = HwCircuit(id: hwNewId('cir'), name: name.isEmpty ? 'Untitled circuit' : name);
    await _store.saveCircuit(c);
    setState(() {
      _circuits = [c, ..._circuits];
      _switchTo(c);
    });
  }

  void _switchTo(HwCircuit c) {
    _sim.stop();
    _circuit = c;
    _selected = null;
    _sim.setCircuit(c);
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _canvasKey.currentState?.resetView();
    });
  }

  Future<void> _renameCircuit() async {
    final c = _circuit;
    if (c == null) return;
    final name = await _promptText('Rename circuit', 'Circuit name', c.name);
    if (name == null || name.isEmpty) return;
    setState(() => c.name = name);
    _persistSoon();
  }

  Future<void> _deleteCircuit() async {
    final c = _circuit;
    if (c == null || _circuits.length <= 1) {
      _toast('Keep at least one circuit.');
      return;
    }
    final ok = await _confirm('Delete "${c.name}"?',
        'This removes the schematic and sketch permanently.');
    if (ok != true) return;
    await _store.deleteCircuit(c.id);
    _circuits.removeWhere((x) => x.id == c.id);
    _switchTo(_circuits.first);
  }

  // ── bindings ──
  Future<void> _saveBinding(HwDeviceBinding b) async {
    await _store.saveBinding(b);
    final i = _bindings.indexWhere((x) => x.id == b.id);
    setState(() {
      if (i >= 0) {
        _bindings[i] = b;
      } else {
        _bindings = [b, ..._bindings];
      }
    });
  }

  Future<void> _deleteBinding(String id) async {
    await _store.deleteBinding(id);
    setState(() => _bindings.removeWhere((x) => x.id == id));
  }

  void _openCircuitById(String id) {
    final c = _circuits.where((x) => x.id == id).firstOrNull;
    if (c != null) {
      _switchTo(c);
      setState(() => _view = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _circuit == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Sa.cyan, strokeWidth: 2.4),
            const SizedBox(height: 14),
            Text('Booting hardware bench…',
                style: Sa.body(size: 12.5, color: Sa.textDim)),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _topBar(),
          const SizedBox(height: 12),
          Expanded(
            child: IndexedStack(
              index: _view,
              children: [
                _designer(),
                _connect(),
                HwFactoryBindingView(
                  bindings: _bindings,
                  circuits: _circuits,
                  onSave: _saveBinding,
                  onDelete: _deleteBinding,
                  onOpenCircuit: _openCircuitById,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _topBar() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _viewSeg(),
        if (_view == 0 || _view == 1) _circuitSelector(),
        const Spacer(),
        SaButton(
          label: 'GUIDE',
          icon: Icons.help_outline,
          color: Sa.violet,
          outlined: true,
          onPressed: _openGuide,
        ),
      ],
    );
  }

  Widget _viewSeg() {
    const items = [
      (0, 'DESIGN', Icons.dashboard_customize),
      (1, 'CONNECT', Icons.cell_tower),
      (2, 'FACTORY MAP', Icons.account_tree),
    ];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Sa.bgRaised.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Sa.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, label, icon) in items)
            InkWell(
              onTap: () => setState(() => _view = i),
              borderRadius: BorderRadius.circular(9),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  gradient: _view == i
                      ? LinearGradient(colors: [
                          Sa.cyan.withValues(alpha: 0.2),
                          Sa.violet.withValues(alpha: 0.12),
                        ])
                      : null,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                      color: _view == i
                          ? Sa.cyan.withValues(alpha: 0.5)
                          : Colors.transparent),
                ),
                child: Row(
                  children: [
                    Icon(icon,
                        size: 15,
                        color: _view == i ? Sa.cyan : Sa.muted),
                    const SizedBox(width: 7),
                    Text(label,
                        style: Sa.heading(
                            size: 12,
                            color: _view == i ? Sa.text : Sa.muted)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _circuitSelector() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 6, 4),
      decoration: BoxDecoration(
        color: Sa.bgRaised.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Sa.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.schema, size: 14, color: Sa.cyan),
          const SizedBox(width: 8),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _circuit!.id,
              dropdownColor: Sa.panelSolid,
              style: Sa.body(size: 12.5),
              borderRadius: BorderRadius.circular(10),
              items: [
                for (final c in _circuits)
                  DropdownMenuItem(value: c.id, child: Text(c.name)),
              ],
              onChanged: (id) {
                final c = _circuits.where((x) => x.id == id).firstOrNull;
                if (c != null) _switchTo(c);
              },
            ),
          ),
          _iconBtn(Icons.add, Sa.green, _newCircuit, 'New circuit'),
          _iconBtn(Icons.edit_outlined, Sa.amber, _renameCircuit, 'Rename'),
          _iconBtn(Icons.delete_outline, Sa.red, _deleteCircuit, 'Delete'),
        ],
      ),
    );
  }

  Widget _iconBtn(IconData icon, Color color, VoidCallback onTap, String tip) {
    return Tooltip(
      message: tip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: Icon(icon, size: 15, color: color),
        ),
      ),
    );
  }

  // ── DESIGN view ──
  Widget _designer() {
    final narrow = MediaQuery.of(context).size.width < 1080;
    final palette = SizedBox(
      width: 150,
      child: GlassPanel(
        padding: const EdgeInsets.all(4),
        child: HwPalette(onPick: (type) {
          _canvasKey.currentState?.addComponent(type, const Offset(160, 140));
        }),
      ),
    );
    final canvas = _canvasArea();
    final right = SizedBox(
      width: narrow ? null : 400,
      child: _rightPanel(),
    );

    if (narrow) {
      return Column(
        children: [
          Expanded(
            flex: 3,
            child: Row(children: [palette, const SizedBox(width: 12), Expanded(child: canvas)]),
          ),
          const SizedBox(height: 12),
          Expanded(flex: 2, child: right),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        palette,
        const SizedBox(width: 12),
        Expanded(child: canvas),
        const SizedBox(width: 12),
        right,
      ],
    );
  }

  Widget _canvasArea() {
    return Stack(
      children: [
        Positioned.fill(
          child: HwCanvas(
            key: _canvasKey,
            circuit: _circuit!,
            sim: _sim,
            selectedId: _selected,
            wireCutMode: _wireCut,
            onSelect: (id) => setState(() {
              _selected = id;
              if (id != null) _rightTab = 1;
            }),
            onChanged: _onCircuitChanged,
          ),
        ),
        Positioned(left: 12, top: 12, child: _canvasToolbar()),
        Positioned(
          right: 12,
          bottom: 12,
          child: _hintChip(),
        ),
      ],
    );
  }

  Widget _canvasToolbar() {
    return AnimatedBuilder(
      animation: _sim,
      builder: (_, __) {
        final running = _sim.isRunning;
        return Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Sa.panelSolid.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Sa.border),
            boxShadow: [BoxShadow(color: Sa.shadow, blurRadius: 12)],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _tool(
                running ? Icons.stop_rounded : Icons.play_arrow_rounded,
                running ? Sa.red : Sa.green,
                running ? 'Stop' : 'Run',
                () => running ? _sim.stop() : unawaited(_sim.start()),
              ),
              _divider(),
              _tool(Icons.add, Sa.cyan, 'Zoom in',
                  () => _canvasKey.currentState?.zoomBy(1.2)),
              _tool(Icons.remove, Sa.cyan, 'Zoom out',
                  () => _canvasKey.currentState?.zoomBy(0.8)),
              _tool(Icons.fit_screen, Sa.cyan, 'Reset view',
                  () => _canvasKey.currentState?.resetView()),
              _divider(),
              _tool(Icons.rotate_right, Sa.amber, 'Rotate',
                  () => _canvasKey.currentState?.rotateSelected()),
              _tool(Icons.delete_outline, Sa.red, 'Delete selected',
                  () => _canvasKey.currentState?.deleteSelected()),
              _toolToggle(
                Icons.content_cut,
                Sa.red,
                _wireCut ? 'Cut wires: ON' : 'Cut wires',
                _wireCut,
                () => setState(() => _wireCut = !_wireCut),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _toolToggle(IconData icon, Color color, String tip, bool active,
      VoidCallback onTap) {
    return Tooltip(
      message: tip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 1),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: active ? color.withValues(alpha: 0.18) : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
                color: active ? color.withValues(alpha: 0.6) : Colors.transparent),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }

  Widget _tool(IconData icon, Color color, String tip, VoidCallback onTap) {
    return Tooltip(
      message: tip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 22,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        color: Sa.border,
      );

  Widget _hintChip() {
    return AnimatedBuilder(
      animation: _sim,
      builder: (_, __) {
        if (_wireCut) {
          return GlowChip(
              label: '✂ CUT MODE · tap a wire to delete',
              color: Sa.red,
              pulse: true);
        }
        if (_sim.isRunning) {
          return GlowChip(label: 'SIMULATION LIVE', color: Sa.green, pulse: true);
        }
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: Sa.panelSolid.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Sa.border),
          ),
          child: Text('Drag parts · click pin → pin to wire · ✂ to cut · ▶ Run',
              style: Sa.mono(size: 9.5, color: Sa.textDim)),
        );
      },
    );
  }

  Widget _rightPanel() {
    return GlassPanel(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _rightTabBtn(0, 'CODE', Icons.code),
              const SizedBox(width: 8),
              _rightTabBtn(1, 'PROPERTIES', Icons.tune),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _rightTab == 0
                ? HwIdePanel(
                    key: ValueKey('ide-${_circuit!.id}'),
                    circuit: _circuit!,
                    sim: _sim,
                    codegen: _codegen,
                    onSketchChanged: _persistSoon,
                  )
                : _InspectorPanel(
                    circuit: _circuit!,
                    sim: _sim,
                    selectedId: _selected,
                    onChanged: _onCircuitChanged,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _rightTabBtn(int i, String label, IconData icon) {
    final active = _rightTab == i;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _rightTab = i),
        borderRadius: BorderRadius.circular(9),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? Sa.cyan.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
                color: active ? Sa.cyan.withValues(alpha: 0.45) : Sa.border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: active ? Sa.cyan : Sa.muted),
              const SizedBox(width: 7),
              Text(label,
                  style: Sa.heading(
                      size: 11.5, color: active ? Sa.text : Sa.muted)),
            ],
          ),
        ),
      ),
    );
  }

  // ── CONNECT view ──
  Widget _connect() {
    final ctrl = _circuit!.controller;
    return HwConnectivityPanel(
      sim: _sim,
      deviceId: hwSanitizeId('${_circuit!.name}-${_circuit!.id}'),
      deviceLabel: ctrl?.def.shortName ?? _circuit!.name,
    );
  }

  // ── dialogs ──
  void _openGuide() {
    showDialog(context: context, builder: (_) => const _GuideDialog());
  }

  Future<String?> _promptText(String title, String label, String initial) {
    final c = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Sa.panelSolid,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Sa.border),
        ),
        title: Text(title, style: Sa.heading(size: 16)),
        content: SaTextField(controller: c, label: label),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: Sa.body(color: Sa.textDim))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: Text('OK', style: Sa.body(color: Sa.cyan))),
        ],
      ),
    );
  }

  Future<bool?> _confirm(String title, String body) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Sa.panelSolid,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Sa.border),
        ),
        title: Text(title, style: Sa.heading(size: 16)),
        content: Text(body, style: Sa.body(size: 12.5, color: Sa.textDim)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: Sa.body(color: Sa.textDim))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Delete', style: Sa.body(color: Sa.red))),
        ],
      ),
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Sa.panelSolid,
    ));
  }
}

// ───────────────────────── Component inspector ─────────────────────────

class _InspectorPanel extends StatelessWidget {
  final HwCircuit circuit;
  final HwSimulator sim;
  final String? selectedId;
  final VoidCallback onChanged;

  const _InspectorPanel({
    required this.circuit,
    required this.sim,
    required this.selectedId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = circuit.byId(selectedId ?? '');
    if (c == null) {
      return const SaEmptyState(
        icon: Icons.touch_app,
        title: 'No part selected',
        message:
            'Tap a component on the canvas to tune it — LED colour, resistor '
            'value, or live sensor readings while the simulation runs.',
      );
    }
    return AnimatedBuilder(
      animation: sim,
      builder: (_, __) => ListView(
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: c.def.accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: c.def.accent.withValues(alpha: 0.5)),
                ),
                alignment: Alignment.center,
                child: Text(c.def.shortName,
                    style: Sa.mono(size: 8, color: c.def.accent, weight: FontWeight.w800)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.def.name, style: Sa.heading(size: 14)),
                    Text(c.def.blurb,
                        style: Sa.body(size: 10, color: Sa.muted)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ..._controls(context, c),
          const SizedBox(height: 16),
          _pinTable(c),
        ],
      ),
    );
  }

  List<Widget> _controls(BuildContext context, HwComponent c) {
    switch (c.type) {
      case 'led':
      case 'rgb-led':
        return [_colorPicker(c)];
      case 'button':
        return [
          _colorPicker(c),
          const SizedBox(height: 14),
          _toggle('Pressed', c.params['pressed'] == true,
              (v) => sim.setParam(c.id, 'pressed', v)),
        ];
      case 'resistor':
        return [
          _slider('Resistance (Ω)', (c.params['ohms'] as num?)?.toDouble() ?? 220,
              10, 10000, (v) {
            c.params['ohms'] = v.round();
            sim.recompute();
            onChanged();
          }, suffix: 'Ω'),
        ];
      case 'potentiometer':
        return [
          _liveSlider('Wiper', (c.params['value'] as num?)?.toDouble() ?? 0.5,
              0, 1, (v) => sim.setParam(c.id, 'value', v),
              fmt: (v) => '${(v * 100).round()}%'),
        ];
      case 'temp-sensor':
        return [
          _liveSlider('Temperature',
              (c.params['tempC'] as num?)?.toDouble() ?? 25, 0, 120,
              (v) => sim.setParam(c.id, 'tempC', v),
              fmt: (v) => '${v.round()} °C'),
        ];
      case 'vibration-sensor':
        return [_toggle('Vibrating', c.params['vibrating'] == true,
            (v) => sim.setParam(c.id, 'vibrating', v))];
      case 'pir-sensor':
        return [_toggle('Motion detected', c.params['motion'] == true,
            (v) => sim.setParam(c.id, 'motion', v))];
      case 'vcc':
        final v = (c.params['volts'] as num?)?.toDouble() ?? 5.0;
        return [
          Text('RAIL VOLTAGE', style: Sa.mono(size: 9, color: Sa.muted)),
          const SizedBox(height: 8),
          Row(
            children: [
              _voltSeg(c, '5V', 5.0, v),
              const SizedBox(width: 8),
              _voltSeg(c, '3V3', 3.3, v),
            ],
          ),
        ];
      default:
        return [
          Text('No tunable properties.',
              style: Sa.body(size: 12, color: Sa.muted)),
        ];
    }
  }

  Widget _colorPicker(HwComponent c) {
    final current = '${c.params['color'] ?? 'red'}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('COLOUR', style: Sa.mono(size: 9, color: Sa.muted)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: kHwColorSwatches.entries.map((e) {
            final on = e.key == current;
            return InkWell(
              onTap: () {
                c.params['color'] = e.key;
                sim.recompute();
                onChanged();
              },
              borderRadius: BorderRadius.circular(99),
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: Color(e.value),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: on ? Colors.white : Sa.border,
                      width: on ? 2.4 : 1),
                  boxShadow: on
                      ? [BoxShadow(color: Color(e.value).withValues(alpha: 0.6), blurRadius: 10)]
                      : null,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _voltSeg(HwComponent c, String label, double volts, double current) {
    final active = (current - volts).abs() < 0.05;
    return Expanded(
      child: InkWell(
        onTap: () {
          c.params['volts'] = volts;
          sim.recompute();
          onChanged();
        },
        borderRadius: BorderRadius.circular(9),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? Sa.red.withValues(alpha: 0.14) : Sa.bgRaised.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
                color: active ? Sa.red : Sa.border, width: active ? 1.4 : 1),
          ),
          child: Text(label,
              style: Sa.heading(size: 12, color: active ? Sa.red : Sa.textDim)),
        ),
      ),
    );
  }

  Widget _slider(String label, double value, double min, double max,
      ValueChanged<double> onChange,
      {String suffix = ''}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label.toUpperCase(), style: Sa.mono(size: 9, color: Sa.muted)),
            const Spacer(),
            Text('${value.round()}$suffix',
                style: Sa.mono(size: 11, color: Sa.cyan)),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: Sa.cyan,
            inactiveTrackColor: Sa.border,
            thumbColor: Sa.cyan,
            overlayColor: Sa.cyan.withValues(alpha: 0.15),
            trackHeight: 3,
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChange,
          ),
        ),
      ],
    );
  }

  Widget _liveSlider(String label, double value, double min, double max,
      ValueChanged<double> onChange,
      {required String Function(double) fmt}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label.toUpperCase(), style: Sa.mono(size: 9, color: Sa.muted)),
            const Spacer(),
            Text(fmt(value), style: Sa.mono(size: 11, color: Sa.green)),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: Sa.green,
            inactiveTrackColor: Sa.border,
            thumbColor: Sa.green,
            overlayColor: Sa.green.withValues(alpha: 0.15),
            trackHeight: 3,
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChange,
          ),
        ),
        Text('Drag while the simulation runs to feed the sketch live.',
            style: Sa.body(size: 9.5, color: Sa.muted)),
      ],
    );
  }

  Widget _toggle(String label, bool value, ValueChanged<bool> onChange) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Sa.bgRaised.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Sa.border),
      ),
      child: Row(
        children: [
          Expanded(child: Text(label, style: Sa.body(size: 12.5))),
          Switch(
            value: value,
            activeThumbColor: Sa.green,
            onChanged: onChange,
          ),
        ],
      ),
    );
  }

  Widget _pinTable(HwComponent c) {
    return AnimatedBuilder(
      animation: sim,
      builder: (_, __) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('PINS · LIVE', style: Sa.mono(size: 9, color: Sa.muted)),
          const SizedBox(height: 8),
          ...c.def.pins.map((p) {
            final v = sim.netVoltageAt(c.id, p.name);
            final connected = sim.pinConnected(c.id, p.name);
            final hot = sim.pinIsHot(c.id, p.name);
            return Container(
              margin: const EdgeInsets.only(bottom: 5),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: Sa.bgRaised.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: hot ? Sa.green.withValues(alpha: 0.5) : Sa.border),
              ),
              child: Row(
                children: [
                  Icon(connected ? Icons.link : Icons.link_off,
                      size: 13,
                      color: connected ? Sa.cyan : Sa.muted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(p.name, style: Sa.mono(size: 11, color: Sa.text)),
                  ),
                  Text('${v.toStringAsFixed(2)} V',
                      style: Sa.mono(
                          size: 10.5,
                          color: hot ? Sa.green : Sa.textDim)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ───────────────────────── Guide / onboarding ─────────────────────────

class _GuideDialog extends StatelessWidget {
  const _GuideDialog();

  static const _steps = [
    (Icons.drag_indicator, 'Drag a part',
        'Pull components from the left palette onto the bench — start with an ESP32 or Arduino UNO.'),
    (Icons.timeline, 'Wire pin to pin',
        'Click a pin and drag to another pin to draw a wire. Power pins glow red, ground grey.'),
    (Icons.auto_awesome, 'Write or generate code',
        'Type Arduino code in the Code panel, or hit AI GENERATE and describe what it should do.'),
    (Icons.play_arrow_rounded, 'Upload & simulate',
        'Press UPLOAD ▶. LEDs light, the LCD shows text, sensors feed your sketch — all live.'),
    (Icons.cell_tower, 'Test the cloud link',
        'Open CONNECT to run a real ESP32→Firebase handshake and watch telemetry reach the backend.'),
    (Icons.account_tree, 'Map the factory',
        'In FACTORY MAP, bind each device to a machine (MACH-001 ← ESP32 + sensors + buttons).'),
  ];

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Sa.panelSolid,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Sa.cyan.withValues(alpha: 0.5)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [Sa.cyan, Sa.violet]),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(Icons.memory, color: Sa.onAccent, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Hardware Lab', style: Sa.display(size: 17)),
                        Text('Design · simulate · connect · deploy',
                            style: Sa.mono(size: 9.5, color: Sa.muted)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              for (var i = 0; i < _steps.length; i++) ...[
                _step(i + 1, _steps[i].$1, _steps[i].$2, _steps[i].$3),
                if (i < _steps.length - 1) const SizedBox(height: 12),
              ],
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerRight,
                child: SaButton(
                  label: 'START BUILDING',
                  icon: Icons.rocket_launch,
                  color: Sa.cyan,
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _step(int n, IconData icon, String title, String body) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: Sa.cyan.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: Sa.cyan.withValues(alpha: 0.4)),
          ),
          child: Icon(icon, size: 17, color: Sa.cyan),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$n. $title', style: Sa.heading(size: 13)),
              const SizedBox(height: 2),
              Text(body, style: Sa.body(size: 11.5, color: Sa.textDim)),
            ],
          ),
        ),
      ],
    );
  }
}
