part of 'hw_runtime.dart';

enum HwSimState { idle, compiling, running, error }

/// Drives the virtual board. Implements [HwSimBridge] so the interpreter talks
/// straight to it, solves the schematic to a logic-level voltage map every time
/// an output changes, and exposes everything the painters need: LED brightness,
/// LCD text, serial output, servo angles, live pin levels.
class HwSimulator extends ChangeNotifier implements HwSimBridge {
  HwCircuit circuit;
  HwSimulator(this.circuit);

  HwSimState state = HwSimState.idle;
  String? errorMessage;
  int? activeLine;

  ArduinoRuntime? _runtime;
  int _startMs = 0;

  // Board output state, keyed by bus pin name ("13", "A0", "2"…).
  final Map<String, bool> _digitalOut = {};
  final Map<String, int> _pwmOut = {}; // 0..255
  final Map<String, int> _pinModes = {};

  // Net voltages, recomputed on every output change.
  HwNetList? _net;
  final Map<int, double> _netV = {};
  final Set<int> _shorts = {};

  // Display + peripheral state.
  final List<String> lcdLines = ['', ''];
  int _lcdCol = 0, _lcdRow = 0;
  final Map<String, int> servoAngles = {}; // instance → angle
  final Map<String, double> ledBrightness = {}; // componentId → 0..1
  bool buzzerOn = false;

  // Serial monitor (ring buffer).
  final List<String> serialLines = [];
  String _serialPartial = '';
  static const int _maxSerial = 400;

  // Firebase bridge hooks wired by the connectivity panel.
  Future<void> Function(String path, Object? value)? onFirebaseSet;
  Future<num> Function(String path)? onFirebaseGet;

  bool get isRunning => state == HwSimState.running;

  static const _lowVoltageBoards = {'esp32', 'esp32c3', 'esp8266', 'pico'};
  static const _twelveBitAdcBoards = {'esp32', 'esp32c3', 'pico'};

  double get vcc =>
      _lowVoltageBoards.contains(circuit.controller?.type) ? 3.3 : 5.0;
  int get adcMax =>
      _twelveBitAdcBoards.contains(circuit.controller?.type) ? 4095 : 1023;

  Map<String, String> _busToNode = {}; // bus name → "compId/pinName"

  void setCircuit(HwCircuit c) {
    circuit = c;
    _indexBoard();
    recompute();
  }

  void _indexBoard() {
    _busToNode = {};
    final ctrl = circuit.controller;
    if (ctrl == null) return;
    for (final p in ctrl.def.pins) {
      if (p.busName != null) _busToNode[p.busName!] = _nodeKey(ctrl.id, p.name);
      _busToNode.putIfAbsent(p.name, () => _nodeKey(ctrl.id, p.name));
    }
  }

  /// Inject a sensor reading / button press, then re-solve.
  void setParam(String compId, String key, Object? value) {
    final c = circuit.byId(compId);
    if (c == null) return;
    c.params[key] = value;
    recompute();
  }

  // ── lifecycle ──
  Future<void> start() async {
    if (isRunning) return;
    reset();
    state = HwSimState.compiling;
    errorMessage = null;
    notifyListeners();
    _indexBoard();
    _startMs = DateTime.now().millisecondsSinceEpoch;
    final rt = ArduinoRuntime(
      this,
      onLine: (l) {
        activeLine = l;
      },
    );
    _runtime = rt;
    try {
      rt.compile(circuit.sketch);
    } catch (e) {
      _fail(e);
      return;
    }
    for (final d in rt.lint()) {
      _emit(d.error ? '✗ ${d.message}' : 'note: ${d.message}');
    }
    if (!rt.hasLoop && !rt.lint().any((d) => d.message.contains('setup'))) {
      // proceed anyway
    }
    state = HwSimState.running;
    notifyListeners();
    try {
      await rt.runSetup();
      while (isRunning && !rt.stopped) {
        final t0 = DateTime.now().millisecondsSinceEpoch;
        await rt.runLoopOnce();
        if (rt.stopped) break;
        final dt = DateTime.now().millisecondsSinceEpoch - t0;
        if (dt < 6) {
          await Future<void>.delayed(Duration(milliseconds: 6 - dt));
        }
      }
    } catch (e) {
      if (isRunning) _fail(e);
    }
    if (state == HwSimState.running) {
      state = HwSimState.idle;
      notifyListeners();
    }
  }

  void stop() {
    _runtime?.stop();
    if (state == HwSimState.running) state = HwSimState.idle;
    activeLine = null;
    notifyListeners();
  }

  void reset() {
    _runtime?.stop();
    _runtime = null;
    _digitalOut.clear();
    _pwmOut.clear();
    _pinModes.clear();
    ledBrightness.clear();
    servoAngles.clear();
    buzzerOn = false;
    lcdLines[0] = '';
    lcdLines[1] = '';
    _lcdCol = 0;
    _lcdRow = 0;
    serialLines.clear();
    _serialPartial = '';
    state = HwSimState.idle;
    errorMessage = null;
    activeLine = null;
    recompute();
  }

  void clearSerial() {
    serialLines.clear();
    _serialPartial = '';
    notifyListeners();
  }

  void _fail(Object e) {
    state = HwSimState.error;
    final line = (e is HwSimException) ? e.line : null;
    errorMessage = e.toString();
    _emit('✗ ${e.toString()}${line != null ? '  (line $line)' : ''}');
    _runtime?.stop();
    notifyListeners();
  }

  void _emit(String line) {
    serialLines.add(line);
    while (serialLines.length > _maxSerial) {
      serialLines.removeAt(0);
    }
  }

  // ── bridge implementation ──
  @override
  void pinMode(String pin, int mode) {
    _pinModes[pin] = mode;
    recompute();
  }

  @override
  void digitalWrite(String pin, bool high) {
    _pwmOut.remove(pin);
    _digitalOut[pin] = high;
    recompute();
  }

  @override
  void analogWrite(String pin, int value) {
    _digitalOut.remove(pin);
    _pwmOut[pin] = value.clamp(0, 255);
    recompute();
  }

  @override
  bool digitalRead(String pin) {
    final node = _busToNode[pin];
    final mode = _pinModes[pin];
    if (node == null) return false;
    final net = _net?.nodeNet[node];
    final v = (net != null) ? (_netV[net] ?? 0) : 0;
    if (mode == 2) {
      // INPUT_PULLUP: HIGH unless something pulls the net to ground.
      return v > vcc * 0.5;
    }
    return v > vcc * 0.5;
  }

  @override
  int analogRead(String pin) {
    final node = _busToNode[pin];
    if (node == null) return 0;
    final net = _net?.nodeNet[node];
    final v = (net != null) ? (_netV[net] ?? 0) : 0;
    return (v / vcc * adcMax).clamp(0, adcMax).round();
  }

  @override
  void serialOut(String text) {
    final combined = _serialPartial + text;
    final parts = combined.split('\n');
    _serialPartial = parts.removeLast();
    for (final p in parts) {
      _emit(p);
    }
    notifyListeners();
  }

  @override
  void lcdCommand(String name, List<Object?> args) {
    switch (name) {
      case 'clear':
        lcdLines[0] = '';
        lcdLines[1] = '';
        _lcdCol = 0;
        _lcdRow = 0;
      case 'home':
        _lcdCol = 0;
        _lcdRow = 0;
      case 'setCursor':
        _lcdCol = args.isNotEmpty ? _intOf(args[0]) : 0;
        _lcdRow = args.length > 1 ? _intOf(args[1]) : 0;
      case 'print':
      case 'write':
        final s = '${args.isEmpty ? '' : args[0]}';
        _lcdWrite(s);
      default:
        break; // begin/backlight/noBacklight/init etc → no-op
    }
    notifyListeners();
  }

  void _lcdWrite(String s) {
    final row = _lcdRow.clamp(0, 1);
    final line = lcdLines[row].padRight(16);
    final chars = line.split('');
    for (var i = 0; i < s.length; i++) {
      final col = _lcdCol + i;
      if (col >= 0 && col < 16) chars[col] = s[i];
    }
    _lcdCol = (_lcdCol + s.length).clamp(0, 16);
    lcdLines[row] = chars.join().trimRight();
  }

  @override
  void servoWrite(String instance, int angle) {
    servoAngles[instance] = angle.clamp(0, 180);
    notifyListeners();
  }

  @override
  void tone(String pin, num freq) {
    buzzerOn = freq > 0;
    notifyListeners();
  }

  @override
  void noTone(String pin) {
    buzzerOn = false;
    notifyListeners();
  }

  @override
  int millisNow() => DateTime.now().millisecondsSinceEpoch - _startMs;

  @override
  void log(String message, {bool error = true}) {
    _emit(error ? '✗ $message' : message);
    notifyListeners();
  }

  @override
  Future<void> firebaseSet(String path, Object? value) async {
    final cb = onFirebaseSet;
    if (cb != null) {
      try {
        await cb(path, value);
      } catch (_) {
        /* surfaced by the connectivity panel */
      }
    }
  }

  @override
  Future<num> firebaseGet(String path) async {
    final cb = onFirebaseGet;
    if (cb != null) {
      try {
        return await cb(path);
      } catch (_) {}
    }
    return 0;
  }

  int _intOf(Object? v) => (v is num) ? v.toInt() : int.tryParse('$v') ?? 0;

  // ── the logic-level solver ──
  void recompute() {
    final net = HwNetList.build(circuit);
    _net = net;
    _netV.clear();
    _shorts.clear();

    for (final entry in net.nets.entries) {
      final id = entry.key;
      final nodes = entry.value;
      var gnd = false;
      var high = 0.0;
      var pull = false;
      for (final node in nodes) {
        final slash = node.indexOf('/');
        final compId = node.substring(0, slash);
        final pinName = node.substring(slash + 1);
        final comp = circuit.byId(compId);
        if (comp == null) continue;
        final type = comp.type;

        if (comp.def.isController) {
          // Board pin acting as a source/sink/rail.
          final pinDef = comp.def.pin(pinName);
          final bus = pinDef?.busName;
          if (pinName.startsWith('GND')) {
            gnd = true;
          } else if (pinName == '5V' || pinName == 'VIN') {
            high = math.max(high, 5.0);
          } else if (pinName == '3V3') {
            high = math.max(high, 3.3);
          } else if (bus != null && _pwmOut.containsKey(bus)) {
            high = math.max(high, vcc * (_pwmOut[bus]! / 255.0));
          } else if (bus != null && _digitalOut.containsKey(bus)) {
            if (_digitalOut[bus]!) {
              high = math.max(high, vcc);
            } else {
              gnd = true;
            }
          } else if (bus != null && _pinModes[bus] == 2) {
            pull = true;
          }
          continue;
        }

        switch (type) {
          case 'power-5v':
            if (pinName == '5V') high = math.max(high, 5.0);
            if (pinName == '3V3') high = math.max(high, 3.3);
            if (pinName == 'GND') gnd = true;
          case 'gnd':
            gnd = true;
          case 'vcc':
            final volts = (comp.params['volts'] as num?)?.toDouble() ?? 5.0;
            high = math.max(high, volts);
          case 'temp-sensor':
            if (pinName == 'OUT') {
              final tC = (comp.params['tempC'] as num?)?.toDouble() ?? 25.0;
              high = math.max(high, (tC * 0.01).clamp(0, vcc));
            }
            if (pinName == 'GND') {
              gnd = false; // sensor GND is a sink, not a rail driver
            }
          case 'potentiometer':
            if (pinName == 'WIPER') {
              final f = (comp.params['value'] as num?)?.toDouble() ?? 0.5;
              high = math.max(high, (f * vcc).clamp(0, vcc));
            }
          case 'vibration-sensor':
            if (pinName == 'DO' && comp.params['vibrating'] == true) {
              high = math.max(high, vcc);
            }
          case 'pir-sensor':
            if (pinName == 'OUT' && comp.params['motion'] == true) {
              high = math.max(high, vcc);
            }
          default:
            break;
        }
      }
      double v;
      if (gnd && high > 0.2) {
        _shorts.add(id);
        v = 0;
      } else if (gnd) {
        v = 0;
      } else if (high > 0) {
        v = high;
      } else if (pull) {
        v = vcc;
      } else {
        v = 0;
      }
      _netV[id] = v;
    }

    _updatePeripherals(net);
    notifyListeners();
  }

  void _updatePeripherals(HwNetList net) {
    for (final c in circuit.components) {
      if (c.type == 'led' || c.type == 'rgb-led') {
        if (c.type == 'led') {
          final va = _pinV(net, c.id, 'A');
          final vk = _pinV(net, c.id, 'K');
          ledBrightness[c.id] = _ledLevel(va, vk);
        } else {
          // RGB: brightness is the strongest leg vs the common cathode.
          final com = _pinV(net, c.id, 'COM');
          final r = _ledLevel(_pinV(net, c.id, 'R'), com);
          final g = _ledLevel(_pinV(net, c.id, 'G'), com);
          final b = _ledLevel(_pinV(net, c.id, 'B'), com);
          ledBrightness[c.id] = math.max(r, math.max(g, b));
        }
      } else if (c.type == 'buzzer') {
        final vp = _pinV(net, c.id, '+');
        final vm = _pinV(net, c.id, '-');
        if (vp - vm > vcc * 0.4) buzzerOn = true;
      }
    }
  }

  double _ledLevel(double anode, double cathode) {
    const fwd = 1.7;
    final delta = anode - cathode;
    if (delta <= fwd) return 0;
    return ((delta - fwd) / (vcc - fwd)).clamp(0.0, 1.0);
  }

  double _pinV(HwNetList net, String comp, String pin) {
    final n = net.netOf(comp, pin);
    if (n == null) return 0;
    return _netV[n] ?? 0;
  }

  // ── query helpers for painters ──
  double netVoltageAt(String comp, String pin) {
    final net = _net;
    if (net == null) return 0;
    return _pinV(net, comp, pin);
  }

  bool pinIsHot(String comp, String pin) => netVoltageAt(comp, pin) > vcc * 0.5;

  double ledLevelOf(String compId) => ledBrightness[compId] ?? 0;

  /// A driven net was shorted straight to ground — surfaced as a warning.
  bool get hasShorts => _shorts.isNotEmpty;

  String get serialText {
    final all = [...serialLines];
    if (_serialPartial.isNotEmpty) all.add(_serialPartial);
    return all.join('\n');
  }

  /// Connectivity validation for the binding view: is [compId]'s key pin wired
  /// to anything else?
  bool pinConnected(String comp, String pin) {
    final net = _net;
    if (net == null) return false;
    final id = net.netOf(comp, pin);
    if (id == null) return false;
    return (net.nets[id]?.length ?? 0) > 1;
  }

  @override
  void dispose() {
    _runtime?.stop();
    super.dispose();
  }
}
