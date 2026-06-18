import 'dart:async';

import 'package:alertsysapp/screens/superadmin/hardware/hw_ai_codegen.dart';
import 'package:alertsysapp/screens/superadmin/hardware/hw_models.dart';
import 'package:alertsysapp/screens/superadmin/hardware/hw_runtime.dart';
import 'package:alertsysapp/screens/superadmin/superadmin_theme.dart';
import 'package:flutter/material.dart';

/// The Arduino IDE panel: a syntax-highlighted editor, Verify (compile/lint),
/// Upload (run the simulation), a live Serial Monitor, and AI code generation
/// (prompt → sketch) with any configurable model + API token.

class HwIdePanel extends StatefulWidget {
  final HwCircuit circuit;
  final HwSimulator sim;
  final HwCodegenService codegen;
  final VoidCallback onSketchChanged;

  const HwIdePanel({
    super.key,
    required this.circuit,
    required this.sim,
    required this.codegen,
    required this.onSketchChanged,
  });

  @override
  State<HwIdePanel> createState() => _HwIdePanelState();
}

class _HwIdePanelState extends State<HwIdePanel> {
  late final _ArduinoController _code;
  final ScrollController _editorScroll = ScrollController();
  final ScrollController _gutterScroll = ScrollController();
  final ScrollController _serialScroll = ScrollController();
  Timer? _persistDebounce;
  String _status = 'Ready';
  Color _statusColor = const Color(0xFF94A3B8);
  bool _verifying = false;

  static const double _lineHeight = 19.0;
  static const double _fontSize = 13.0;

  @override
  void initState() {
    super.initState();
    _code = _ArduinoController(text: widget.circuit.sketch);
    _code.addListener(_onCodeChanged);
    _editorScroll.addListener(() {
      if (_gutterScroll.hasClients) {
        _gutterScroll.jumpTo(
          _editorScroll.offset.clamp(0, _gutterScroll.position.maxScrollExtent),
        );
      }
    });
    widget.sim.addListener(_onSim);
  }

  @override
  void dispose() {
    _persistDebounce?.cancel();
    _code.removeListener(_onCodeChanged);
    _code.dispose();
    _editorScroll.dispose();
    _gutterScroll.dispose();
    _serialScroll.dispose();
    widget.sim.removeListener(_onSim);
    super.dispose();
  }

  void _onSim() {
    if (!mounted) return;
    // Auto-scroll serial monitor to the newest line.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_serialScroll.hasClients) {
        _serialScroll.jumpTo(_serialScroll.position.maxScrollExtent);
      }
    });
    setState(() {});
  }

  void _onCodeChanged() {
    widget.circuit.sketch = _code.text;
    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(milliseconds: 1500), () {
      widget.onSketchChanged();
    });
  }

  Future<void> _verify() async {
    if (_verifying) return;
    widget.circuit.sketch = _code.text;
    setState(() {
      _verifying = true;
      _status = 'Verifying sketch...';
      _statusColor = Sa.cyan;
    });
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;

    final rt = ArduinoRuntime(_NoopBridge());
    try {
      rt.compile(_code.text);
      final diags = rt.lint();
      if (diags.isEmpty) {
        _setStatus('✓ Compiled — no problems found', Sa.green);
      } else {
        _setStatus('⚠ ${diags.map((d) => d.message).join('  ·  ')}', Sa.amber);
      }
    } catch (e) {
      final line = (e is HwSimException) ? e.line : null;
      _setStatus(
        '✗ ${e.toString()}${line != null ? '  (line $line)' : ''}',
        Sa.red,
      );
    }
    if (mounted) {
      setState(() => _verifying = false);
    }
  }

  Future<void> _toggleRun() async {
    if (widget.sim.isRunning) {
      widget.sim.stop();
      _setStatus('Simulation stopped', Sa.textDim);
      return;
    }
    widget.circuit.sketch = _code.text;
    widget.onSketchChanged();
    _setStatus('Uploading…', Sa.cyan);
    // start() runs the full setup/loop lifecycle; it returns when stopped.
    unawaited(widget.sim.start());
  }

  void _setStatus(String s, Color c) {
    if (!mounted) return;
    setState(() {
      _status = s;
      _statusColor = c;
    });
  }

  Future<void> _openAiDialog() async {
    final code = await showDialog<String>(
      context: context,
      builder: (_) => _AiCodegenDialog(
        codegen: widget.codegen,
        board: widget.circuit.controller?.type ?? 'esp32',
        components: widget.circuit.components
            .map((c) => c.def.name)
            .toSet()
            .toList(),
      ),
    );
    if (code != null && code.trim().isNotEmpty) {
      _code.text = code;
      widget.circuit.sketch = code;
      widget.onSketchChanged();
      _setStatus('✓ AI sketch loaded — press Upload to run', Sa.violet);
    }
  }

  @override
  Widget build(BuildContext context) {
    final running = widget.sim.isRunning;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _toolbar(running),
        const SizedBox(height: 8),
        Expanded(flex: 3, child: _editor()),
        const SizedBox(height: 8),
        Expanded(flex: 2, child: _serialMonitor()),
      ],
    );
  }

  Widget _toolbar(bool running) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _btn(
          running ? 'STOP' : 'UPLOAD',
          running ? Icons.stop_rounded : Icons.bolt,
          running ? Sa.red : Sa.green,
          _toggleRun,
        ),
        _btn(
          'VERIFY',
          Icons.fact_check_outlined,
          Sa.cyan,
          _verifying ? null : () => unawaited(_verify()),
          busy: _verifying,
        ),
        _btn('AI GENERATE', Icons.auto_awesome, Sa.violet, _openAiDialog),
        _btn(
          'FORMAT',
          Icons.format_align_left,
          Sa.blue,
          _format,
          outlined: true,
        ),
        _btn(
          'CLEAR LOG',
          Icons.delete_sweep_outlined,
          Sa.muted,
          widget.sim.clearSerial,
          outlined: true,
        ),
        if (widget.sim.activeLine != null && running)
          GlowChip(
            label: '▶ LINE ${widget.sim.activeLine}',
            color: Sa.amber,
            pulse: true,
          ),
        if (widget.sim.hasShorts)
          const GlowChip(label: '⚠ SHORT CIRCUIT', color: Color(0xFFF87171)),
      ],
    );
  }

  Widget _btn(
    String label,
    IconData icon,
    Color color,
    VoidCallback? onTap, {
    bool outlined = false,
    bool busy = false,
  }) {
    return SaButton(
      label: label,
      icon: icon,
      color: color,
      outlined: outlined,
      busy: busy,
      onPressed: onTap,
    );
  }

  void _format() {
    // Lightweight re-indent: normalise braces indentation.
    final lines = _code.text.split('\n');
    final out = <String>[];
    var depth = 0;
    for (final raw in lines) {
      final line = raw.trim();
      if (line.startsWith('}')) depth = (depth - 1).clamp(0, 99);
      out.add('${'  ' * depth}$line');
      // Count net braces on the line (ignoring those in strings is overkill here).
      final opens = '{'.allMatches(line).length;
      final closes = '}'.allMatches(line).length;
      depth = (depth + opens - closes).clamp(0, 99);
    }
    _code.text = out.join('\n');
    _setStatus('Formatted', Sa.blue);
  }

  Widget _editor() {
    final lineCount = '\n'.allMatches(_code.text).length + 1;
    final active = widget.sim.activeLine;
    return Container(
      decoration: BoxDecoration(
        color: Sa.termBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Sa.termBorder),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        children: [
          _editorTitleBar(),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Gutter.
                Container(
                  width: 46,
                  color: const Color(0xFF0A1220),
                  child: SingleChildScrollView(
                    controller: _gutterScroll,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(top: 12, bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 1; i <= lineCount; i++)
                          SizedBox(
                            height: _lineHeight,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                if (active == i)
                                  const Icon(
                                    Icons.play_arrow,
                                    size: 11,
                                    color: Color(0xFFFBBF24),
                                  ),
                                const SizedBox(width: 2),
                                Text(
                                  '$i',
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                    height: _lineHeight / 11,
                                    color: active == i
                                        ? const Color(0xFFFBBF24)
                                        : const Color(0xFF40516B),
                                  ),
                                ),
                                const SizedBox(width: 6),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _code,
                    scrollController: _editorScroll,
                    maxLines: null,
                    expands: true,
                    cursorColor: Sa.cyan,
                    keyboardType: TextInputType.multiline,
                    textAlignVertical: TextAlignVertical.top,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: _fontSize,
                      height: _lineHeight / _fontSize,
                      color: Color(0xFFD4D4D4),
                    ),
                    decoration: const InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.fromLTRB(10, 12, 12, 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          _statusBar(),
        ],
      ),
    );
  }

  Widget _editorTitleBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: const BoxDecoration(
        color: Color(0xFF0A1220),
        border: Border(bottom: BorderSide(color: Color(0xFF16243B))),
      ),
      child: Row(
        children: [
          const Icon(Icons.code, size: 14, color: Color(0xFF22D3EE)),
          const SizedBox(width: 8),
          Text('sketch.ino', style: Sa.mono(size: 11.5, color: Sa.termText)),
          const Spacer(),
          Text(
            '${widget.circuit.controller?.def.shortName ?? 'No board'} · Arduino C++',
            style: Sa.mono(size: 9, color: Sa.termMuted),
          ),
        ],
      ),
    );
  }

  Widget _statusBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: const BoxDecoration(
        color: Color(0xFF0A1220),
        border: Border(top: BorderSide(color: Color(0xFF16243B))),
      ),
      child: Text(
        _status,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Sa.mono(size: 10.5, color: _statusColor),
      ),
    );
  }

  Widget _serialMonitor() {
    final text = widget.sim.serialText;
    return Container(
      decoration: BoxDecoration(
        color: Sa.termBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Sa.termBorder),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: const BoxDecoration(
              color: Color(0xFF0A1220),
              border: Border(bottom: BorderSide(color: Color(0xFF16243B))),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.terminal,
                  size: 14,
                  color: widget.sim.isRunning ? Sa.green : Sa.termMuted,
                ),
                const SizedBox(width: 8),
                Text(
                  'Serial Monitor · 115200 baud',
                  style: Sa.mono(size: 11, color: Sa.termText),
                ),
                const Spacer(),
                if (widget.sim.isRunning) PulseDot(color: Sa.green, size: 6),
              ],
            ),
          ),
          Expanded(
            child: text.trim().isEmpty
                ? Center(
                    child: Text(
                      'Upload a sketch to see Serial output here.',
                      style: Sa.mono(size: 11, color: Sa.termMuted),
                    ),
                  )
                : SingleChildScrollView(
                    controller: _serialScroll,
                    padding: const EdgeInsets.all(12),
                    child: SelectableText(
                      text,
                      style: Sa.mono(
                        size: 11.5,
                        color: const Color(0xFF8FE3B0),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// No-op bridge used by Verify (compile only, no execution side-effects).
class _NoopBridge implements HwSimBridge {
  @override
  void analogWrite(String pin, int value) {}
  @override
  int analogRead(String pin) => 0;
  @override
  bool digitalRead(String pin) => false;
  @override
  void digitalWrite(String pin, bool high) {}
  @override
  Future<void> firebaseSet(String path, Object? value) async {}
  @override
  Future<num> firebaseGet(String path) async => 0;
  @override
  void lcdCommand(String name, List<Object?> args) {}
  @override
  void log(String message, {bool error = true}) {}
  @override
  int millisNow() => 0;
  @override
  void noTone(String pin) {}
  @override
  void pinMode(String pin, int mode) {}
  @override
  void serialOut(String text) {}
  @override
  void servoWrite(String instance, int angle) {}
  @override
  void tone(String pin, num freq) {}
}

// ───────────────────────── AI codegen dialog ─────────────────────────

class _AiCodegenDialog extends StatefulWidget {
  final HwCodegenService codegen;
  final String board;
  final List<String> components;
  const _AiCodegenDialog({
    required this.codegen,
    required this.board,
    required this.components,
  });

  @override
  State<_AiCodegenDialog> createState() => _AiCodegenDialogState();
}

class _AiCodegenDialogState extends State<_AiCodegenDialog> {
  final TextEditingController _prompt = TextEditingController();
  final TextEditingController _key = TextEditingController();
  String _model = 'llama-3.2';
  bool _hasStoredKey = false;
  bool _busy = false;
  bool _showSettings = false;
  String? _error;
  String? _preview;
  String _modelUsed = '';

  @override
  void initState() {
    super.initState();
    unawaited(
      widget.codegen.loadConfig().then((cfg) {
        if (!mounted) return;
        setState(() {
          _model = cfg.modelId;
          _hasStoredKey = cfg.hasKey;
        });
      }),
    );
  }

  @override
  void dispose() {
    _prompt.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final p = _prompt.text.trim();
    if (p.isEmpty) {
      setState(() => _error = 'Describe what the firmware should do.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _preview = null;
    });
    // Persist model/key choice so the worker can use it server-side.
    try {
      await widget.codegen.saveConfig(
        modelId: _model,
        apiKey: _key.text.isEmpty ? null : _key.text,
      );
    } catch (_) {}
    final res = await widget.codegen.generate(
      prompt: p,
      board: widget.board,
      components: widget.components,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (res.ok) {
        _preview = res.code;
        _modelUsed = res.fellBack ? 'Llama (fallback)' : res.modelUsed;
      } else {
        _error = res.error;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Sa.panelSolid,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Sa.violet.withValues(alpha: 0.5)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_awesome, color: Sa.violet, size: 20),
                  const SizedBox(width: 10),
                  Text('AI Firmware Generator', style: Sa.heading(size: 17)),
                  const Spacer(),
                  IconButton(
                    onPressed: () =>
                        setState(() => _showSettings = !_showSettings),
                    icon: Icon(
                      Icons.tune,
                      color: _showSettings ? Sa.violet : Sa.muted,
                      size: 18,
                    ),
                    tooltip: 'Model & API key',
                  ),
                ],
              ),
              Text(
                'Describe the behaviour in plain language — the model writes the '
                'Arduino sketch for your board and components.',
                style: Sa.body(size: 12, color: Sa.textDim),
              ),
              const SizedBox(height: 14),
              if (_showSettings) _settings(),
              TextField(
                controller: _prompt,
                maxLines: 3,
                style: Sa.body(size: 13),
                cursorColor: Sa.violet,
                decoration: _dec(
                  'e.g. "Read the heat sensor every second; if above 60°C turn '
                  'on the red LED and push the reading to Firebase at '
                  'machines/MACH-001/temp"',
                ),
              ),
              const SizedBox(height: 10),
              GlowChip(
                label:
                    'BOARD: ${widget.board.toUpperCase()} · ${widget.components.length} PARTS',
                color: Sa.cyan,
              ),
              const SizedBox(height: 12),
              if (_error != null)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Sa.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Sa.red.withValues(alpha: 0.4)),
                  ),
                  child: Text(_error!, style: Sa.body(size: 12, color: Sa.red)),
                ),
              if (_preview != null) ...[
                Row(
                  children: [
                    Text('PREVIEW', style: Sa.mono(size: 9, color: Sa.muted)),
                    const SizedBox(width: 8),
                    if (_modelUsed.isNotEmpty)
                      Text(
                        _modelUsed,
                        style: Sa.mono(size: 9, color: Sa.violet),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Flexible(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Sa.termBg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Sa.termBorder),
                    ),
                    child: SingleChildScrollView(
                      child: Text(
                        _preview!,
                        style: Sa.mono(
                          size: 11,
                          color: const Color(0xFF8FE3B0),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Cancel', style: Sa.body(color: Sa.textDim)),
                  ),
                  const SizedBox(width: 8),
                  if (_preview != null)
                    SaButton(
                      label: 'USE THIS CODE',
                      icon: Icons.check,
                      color: Sa.green,
                      onPressed: () => Navigator.pop(context, _preview),
                    )
                  else
                    SaButton(
                      label: 'GENERATE',
                      icon: Icons.auto_awesome,
                      color: Sa.violet,
                      busy: _busy,
                      onPressed: _busy ? null : _generate,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _settings() {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Sa.bgRaised.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Sa.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('MODEL', style: Sa.mono(size: 9, color: Sa.muted)),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            initialValue: _model,
            isExpanded: true,
            dropdownColor: Sa.panelSolid,
            style: Sa.body(size: 12.5),
            decoration: _dec(null, dense: true),
            items: [
              for (final m in kHwAiModels)
                DropdownMenuItem(value: m.id, child: Text(m.label)),
            ],
            onChanged: (v) => setState(() => _model = v ?? 'llama-3.2'),
          ),
          const SizedBox(height: 10),
          Text(
            'API KEY${_hasStoredKey ? ' · stored ✓' : ''}',
            style: Sa.mono(size: 9, color: Sa.muted),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _key,
            obscureText: true,
            style: Sa.body(size: 12.5),
            cursorColor: Sa.violet,
            decoration: _dec(
              _hasStoredKey
                  ? 'Leave blank to keep the stored key'
                  : 'Paste provider API key (kept server-side)',
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'The key is stored in the secure RTDB vault and only used by the '
            'worker — it never ships to clients. Llama needs no key.',
            style: Sa.body(size: 10.5, color: Sa.muted),
          ),
        ],
      ),
    );
  }

  InputDecoration _dec(String? hint, {bool dense = false}) => InputDecoration(
    hintText: hint,
    hintStyle: Sa.body(size: 12, color: Sa.muted),
    filled: true,
    fillColor: Sa.bgRaised.withValues(alpha: 0.6),
    isDense: dense,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: BorderSide(color: Sa.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: BorderSide(color: Sa.violet),
    ),
  );
}

/// Arduino-C syntax highlighter for [TextField].
class _ArduinoController extends TextEditingController {
  _ArduinoController({super.text});

  static final RegExp _pattern = RegExp(
    r'(//[^\n]*|/\*[\s\S]*?\*/)' // comments
    r'|(#[A-Za-z_]+)' // preprocessor
    r'''|("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')''' // strings/chars
    r'|(\b0[xX][0-9a-fA-F]+\b|\b\d+\.?\d*[fFlLuU]?\b)' // numbers
    r'|([A-Za-z_]\w*)', // identifiers
    multiLine: true,
  );

  static const _keywords = {
    'if',
    'else',
    'for',
    'while',
    'do',
    'return',
    'break',
    'continue',
    'switch',
    'case',
    'default',
    'goto',
    'sizeof',
    'true',
    'false',
    'const',
    'static',
    'volatile',
    'struct',
    'class',
    'public',
    'private',
    'new',
    'delete',
  };
  static const _types = {
    'void',
    'int',
    'long',
    'short',
    'float',
    'double',
    'bool',
    'boolean',
    'byte',
    'char',
    'unsigned',
    'signed',
    'String',
    'uint8_t',
    'uint16_t',
    'uint32_t',
    'int8_t',
    'int16_t',
    'int32_t',
    'size_t',
    'word',
    'auto',
    'LiquidCrystal_I2C',
    'LiquidCrystal',
    'Servo',
    'DHT',
  };
  static const _builtins = {
    'pinMode',
    'digitalWrite',
    'digitalRead',
    'analogRead',
    'analogWrite',
    'delay',
    'delayMicroseconds',
    'millis',
    'micros',
    'map',
    'constrain',
    'min',
    'max',
    'abs',
    'sqrt',
    'pow',
    'random',
    'randomSeed',
    'tone',
    'noTone',
    'setup',
    'loop',
    'Serial',
    'Firebase',
    'Wire',
    'WiFi',
    'lcd',
    'HIGH',
    'LOW',
    'INPUT',
    'OUTPUT',
    'INPUT_PULLUP',
    'LED_BUILTIN',
  };

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final base = style ?? const TextStyle();
    final spans = <TextSpan>[];
    final src = text;
    var last = 0;
    for (final m in _pattern.allMatches(src)) {
      if (m.start > last) {
        spans.add(TextSpan(text: src.substring(last, m.start), style: base));
      }
      final tok = m.group(0)!;
      Color? color;
      if (m.group(1) != null) {
        color = const Color(0xFF6A9955); // comment
      } else if (m.group(2) != null) {
        color = const Color(0xFF9CDCFE); // preprocessor
      } else if (m.group(3) != null) {
        color = const Color(0xFFCE9178); // string
      } else if (m.group(4) != null) {
        color = const Color(0xFFB5CEA8); // number
      } else {
        if (_keywords.contains(tok)) {
          color = const Color(0xFFC586C0);
        } else if (_types.contains(tok)) {
          color = const Color(0xFF4EC9B0);
        } else if (_builtins.contains(tok)) {
          color = const Color(0xFFDCDCAA);
        }
      }
      spans.add(
        TextSpan(
          text: tok,
          style: color == null ? base : base.copyWith(color: color),
        ),
      );
      last = m.end;
    }
    if (last < src.length) {
      spans.add(TextSpan(text: src.substring(last), style: base));
    }
    return TextSpan(style: base, children: spans);
  }
}
