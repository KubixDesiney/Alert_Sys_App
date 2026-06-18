part of 'hw_runtime.dart';

class _ReturnSignal {
  final Object? value;
  _ReturnSignal(this.value);
}

class _BreakSignal {}

class _ContinueSignal {}

class _Scope {
  final Map<String, Object?> vars = {};
  final _Scope? parent;
  _Scope(this.parent);

  bool has(String name) {
    _Scope? s = this;
    while (s != null) {
      if (s.vars.containsKey(name)) return true;
      s = s.parent;
    }
    return false;
  }

  Object? get(String name) {
    _Scope? s = this;
    while (s != null) {
      if (s.vars.containsKey(name)) return s.vars[name];
      s = s.parent;
    }
    return null;
  }

  void set(String name, Object? v) {
    _Scope? s = this;
    while (s != null) {
      if (s.vars.containsKey(name)) {
        s.vars[name] = v;
        return;
      }
      s = s.parent;
    }
    // Define in current scope if not found (lenient).
    vars[name] = v;
  }

  void define(String name, Object? v) => vars[name] = v;
}

/// What the interpreter needs from the world. The [HwSimulator] implements it.
abstract class HwSimBridge {
  void pinMode(String pin, int mode);
  void digitalWrite(String pin, bool high);
  bool digitalRead(String pin);
  int analogRead(String pin);
  void analogWrite(String pin, int value);
  void serialOut(String text);
  void lcdCommand(String name, List<Object?> args);
  void servoWrite(String instance, int angle);
  void tone(String pin, num freq);
  void noTone(String pin);
  int millisNow();
  void log(String message, {bool error});
  Future<void> firebaseSet(String path, Object? value);
  Future<num> firebaseGet(String path);
}

// ─────────────────────────── Interpreter ───────────────────────────

class ArduinoRuntime {
  final HwSimBridge bridge;
  final void Function(int line)? onLine;
  ArduinoRuntime(this.bridge, {this.onLine});

  late _Parser _parser;
  final Map<String, _FuncDecl> _functions = {};
  final Map<String, String> _instances = {}; // name → kind
  final _Scope _globals = _Scope(null);

  bool _stopped = false;
  int _ops = 0;
  int? currentLine;

  bool get hasLoop => _functions.containsKey('loop');

  /// Parse + register declarations. Throws [HwSimException] on syntax errors.
  void compile(String source) {
    final tokens = _Lexer(_preprocess(source)).tokenize();
    _parser = _Parser(tokens);
    _parser.parse();
    _functions.clear();
    for (final f in _parser.functions) {
      _functions[f.name] = f;
    }
    _instances
      ..clear()
      ..addAll(_parser.instances);
    _seedConstants();
  }

  /// Static checks beyond parsing — surfaced by the Verify button.
  List<HwDiag> lint() {
    final diags = <HwDiag>[];
    if (!_functions.containsKey('setup')) {
      diags.add(const HwDiag("missing 'void setup()'"));
    }
    if (!_functions.containsKey('loop')) {
      diags.add(const HwDiag("missing 'void loop()'"));
    }
    return diags;
  }

  String _preprocess(String src) {
    // Object-like #define substitution; ignore #include / #if.
    final defines = <String, String>{};
    final lines = src.split('\n');
    for (final line in lines) {
      final m = RegExp(
        r'^\s*#define\s+([A-Za-z_]\w*)\s+(.+?)\s*$',
      ).firstMatch(line);
      if (m != null) {
        defines[m.group(1)!] = m.group(2)!;
      }
    }
    if (defines.isEmpty) return src;
    var out = src;
    defines.forEach((k, v) {
      // Don't substitute function-like macros; whole-word only.
      out = out.replaceAll(RegExp('\\b$k\\b'), v);
    });
    return out;
  }

  void _seedConstants() {
    const consts = {
      'HIGH': 1,
      'LOW': 0,
      'INPUT': 0,
      'OUTPUT': 1,
      'INPUT_PULLUP': 2,
      'true': 1,
      'false': 0,
      'LED_BUILTIN': 13,
      'PI': 3.1415926535,
      'A0': 14,
      'A1': 15,
      'A2': 16,
      'A3': 17,
      'A4': 18,
      'A5': 19,
      'DEC': 10,
      'HEX': 16,
      'BIN': 2,
      'OCT': 8,
      'CHANGE': 1,
      'RISING': 2,
      'FALLING': 3,
      'OUTPUT_OPEN_DRAIN': 1,
    };
    consts.forEach(_globals.define);
    // Initialise globals.
    for (final g in _parser.globals) {
      try {
        _initGlobalSync(g);
      } catch (_) {
        /* defer init that needs runtime — rare */
      }
    }
  }

  void _initGlobalSync(_VarDecl decl) {
    for (final v in decl.vars) {
      if (v.init == null) {
        _globals.define(v.name, v.isArray ? <Object?>[] : 0);
      } else {
        // Globals init with literal-ish expressions only; evaluate eagerly.
        final value = _evalConst(v.init!);
        _globals.define(v.name, value);
      }
    }
  }

  Object? _evalConst(_Node n) {
    if (n is _NumLit) return n.v;
    if (n is _StrLit) return n.v;
    if (n is _BoolLit) return n.v ? 1 : 0;
    if (n is _Ident) return _globals.get(n.name) ?? 0;
    if (n is _Unary && n.op == '-') {
      final v = _evalConst(n.expr);
      return (v is num) ? -v : 0;
    }
    if (n is _ArrayLit) return n.elements.map(_evalConst).toList();
    if (n is _Binary) {
      final a = _evalConst(n.l);
      final b = _evalConst(n.r);
      return _binOp(n.op, a, b);
    }
    return 0;
  }

  void stop() => _stopped = true;
  bool get stopped => _stopped;

  /// Run setup() once.
  Future<void> runSetup() async {
    _stopped = false;
    final f = _functions['setup'];
    if (f == null) return;
    await _callUser(f, const []);
  }

  /// Run one loop() iteration.
  Future<void> runLoopOnce() async {
    final f = _functions['loop'];
    if (f == null) {
      _stopped = true;
      return;
    }
    await _callUser(f, const []);
  }

  Future<Object?> _callUser(_FuncDecl f, List<Object?> args) async {
    final scope = _Scope(_globals);
    for (var i = 0; i < f.params.length; i++) {
      scope.define(f.params[i].name, i < args.length ? args[i] : 0);
    }
    try {
      await _execBlock(f.body, scope);
    } on _ReturnSignal catch (r) {
      return r.value;
    }
    return null;
  }

  Future<void> _execBlock(_Block b, _Scope parent) async {
    final scope = _Scope(parent);
    for (final s in b.stmts) {
      await _exec(s, scope);
    }
  }

  Future<void> _yieldIfNeeded() async {
    _ops++;
    if (_stopped) throw _ReturnSignal(null);
    if (_ops % 1200 == 0) {
      await Future<void>.delayed(Duration.zero);
      if (_stopped) throw _ReturnSignal(null);
    }
  }

  Future<void> _exec(_Node n, _Scope scope) async {
    await _yieldIfNeeded();
    if (n.line != currentLine) {
      currentLine = n.line;
      onLine?.call(n.line);
    }
    switch (n) {
      case _Block():
        await _execBlock(n, scope);
      case _VarDecl():
        for (final v in n.vars) {
          Object? value = v.isArray ? <Object?>[] : 0;
          if (v.init != null) value = await _eval(v.init!, scope);
          scope.define(v.name, value);
        }
      case _ExprStmt():
        await _eval(n.expr, scope);
      case _If():
        if (_truthy(await _eval(n.cond, scope))) {
          await _exec(n.then, scope);
        } else if (n.els != null) {
          await _exec(n.els!, scope);
        }
      case _For():
        final loopScope = _Scope(scope);
        if (n.init != null) await _exec(n.init!, loopScope);
        var guard = 0;
        while (n.cond == null || _truthy(await _eval(n.cond!, loopScope))) {
          try {
            await _exec(n.body, loopScope);
          } on _BreakSignal {
            break;
          } on _ContinueSignal {
            // fallthrough to update
          }
          if (n.update != null) await _eval(n.update!, loopScope);
          if (++guard > 2000000) {
            throw HwSimException(
              'for-loop exceeded iteration budget',
              line: n.line,
            );
          }
        }
      case _While():
        var guard = 0;
        if (n.doWhile) {
          do {
            try {
              await _exec(n.body, scope);
            } on _BreakSignal {
              break;
            } on _ContinueSignal {
              /* loop */
            }
            if (++guard > 2000000) break;
          } while (_truthy(await _eval(n.cond, scope)));
        } else {
          while (_truthy(await _eval(n.cond, scope))) {
            try {
              await _exec(n.body, scope);
            } on _BreakSignal {
              break;
            } on _ContinueSignal {
              /* loop */
            }
            if (++guard > 2000000) break;
          }
        }
      case _Return():
        throw _ReturnSignal(
          n.value == null ? null : await _eval(n.value!, scope),
        );
      case _BreakNode():
        throw _BreakSignal();
      case _ContinueNode():
        throw _ContinueSignal();
      default:
        // Bare expression node used as a statement.
        await _eval(n, scope);
    }
  }

  Future<Object?> _eval(_Node n, _Scope scope) async {
    await _yieldIfNeeded();
    switch (n) {
      case _NumLit():
        return n.v;
      case _StrLit():
        return n.v;
      case _BoolLit():
        return n.v ? 1 : 0;
      case _ArrayLit():
        final out = <Object?>[];
        for (final e in n.elements) {
          out.add(await _eval(e, scope));
        }
        return out;
      case _Ident():
        if (scope.has(n.name)) return scope.get(n.name);
        if (_instances.containsKey(n.name)) return '@${n.name}';
        if (n.name == 'Serial' ||
            n.name == 'Serial1' ||
            n.name == 'Firebase' ||
            n.name == 'Wire' ||
            n.name == 'WiFi' ||
            n.name == 'Cloud') {
          return '@${n.name}';
        }
        throw HwSimException("'${n.name}' was not declared", line: n.line);
      case _Member():
        // Used standalone (rare) — return object handle.
        return await _eval(n.obj, scope);
      case _Index():
        final arr = await _eval(n.arr, scope);
        final idx = _toInt(await _eval(n.idx, scope));
        if (arr is List && idx >= 0 && idx < arr.length) return arr[idx];
        if (arr is String && idx >= 0 && idx < arr.length) {
          return arr.codeUnitAt(idx);
        }
        return 0;
      case _Unary():
        return _evalUnary(n, scope);
      case _Binary():
        final a = await _eval(n.l, scope);
        // Short-circuit logicals.
        if (n.op == '&&') {
          if (!_truthy(a)) return 0;
          return _truthy(await _eval(n.r, scope)) ? 1 : 0;
        }
        if (n.op == '||') {
          if (_truthy(a)) return 1;
          return _truthy(await _eval(n.r, scope)) ? 1 : 0;
        }
        final b = await _eval(n.r, scope);
        return _binOp(n.op, a, b);
      case _Ternary():
        return _truthy(await _eval(n.cond, scope))
            ? await _eval(n.a, scope)
            : await _eval(n.b, scope);
      case _Assign():
        return _evalAssign(n, scope);
      case _Call():
        return _evalCall(n, scope);
      default:
        return 0;
    }
  }

  Future<Object?> _evalUnary(_Unary n, _Scope scope) async {
    if (n.op == '++' || n.op == '--') {
      final cur = _toNum(await _eval(n.expr, scope));
      final next = n.op == '++' ? cur + 1 : cur - 1;
      await _assignTo(n.expr, _coerceInt(cur, next), scope);
      return n.prefix ? next : cur;
    }
    final v = await _eval(n.expr, scope);
    return switch (n.op) {
      '!' => _truthy(v) ? 0 : 1,
      '-' => -_toNum(v),
      '+' => _toNum(v),
      '~' => ~_toInt(v),
      _ => v,
    };
  }

  Future<Object?> _evalAssign(_Assign n, _Scope scope) async {
    Object? value = await _eval(n.value, scope);
    if (n.op != '=') {
      final cur = await _eval(n.target, scope);
      final binOp = n.op.substring(0, n.op.length - 1); // strip '='
      value = _binOp(binOp, cur, value);
    }
    await _assignTo(n.target, value, scope);
    return value;
  }

  Future<void> _assignTo(_Node target, Object? value, _Scope scope) async {
    if (target is _Ident) {
      scope.set(target.name, value);
      return;
    }
    if (target is _Index) {
      final arr = await _eval(target.arr, scope);
      final idx = _toInt(await _eval(target.idx, scope));
      if (arr is List) {
        while (arr.length <= idx) {
          arr.add(0);
        }
        if (idx >= 0) arr[idx] = value;
      }
      return;
    }
    // Member assignment unsupported — ignore gracefully.
  }

  Future<Object?> _evalCall(_Call n, _Scope scope) async {
    // Member call: obj.method(args)
    if (n.callee is _Member) {
      final m = n.callee as _Member;
      final objName = (m.obj is _Ident) ? (m.obj as _Ident).name : '';
      final args = <Object?>[];
      for (final a in n.args) {
        args.add(await _eval(a, scope));
      }
      return _memberCall(objName, m.name, args, n.line);
    }
    final name = (n.callee is _Ident) ? (n.callee as _Ident).name : '';
    // User function?
    final user = _functions[name];
    if (user != null) {
      final args = <Object?>[];
      for (final a in n.args) {
        args.add(await _eval(a, scope));
      }
      return _callUser(user, args);
    }
    // Built-in function.
    final args = <Object?>[];
    for (final a in n.args) {
      args.add(await _eval(a, scope));
    }
    return _builtin(name, args, n.line);
  }

  // ── Member dispatch (Serial / lcd / Servo / Firebase …) ──
  Future<Object?> _memberCall(
    String obj,
    String method,
    List<Object?> args,
    int line,
  ) async {
    final kind = (obj == 'Serial' || obj == 'Serial1')
        ? 'serial'
        : (obj == 'Firebase' || obj == 'Cloud')
        ? 'firebase'
        : (obj == 'Wire')
        ? 'wire'
        : (obj == 'WiFi')
        ? 'wifi'
        : _instances[obj] ?? 'unknown';

    switch (kind) {
      case 'serial':
        switch (method) {
          case 'begin':
          case 'flush':
          case 'setTimeout':
            return 0;
          case 'available':
            return 0;
          case 'print':
            bridge.serialOut(
              _fmt(
                args.isEmpty ? '' : args[0],
                args.length > 1 ? _toInt(args[1]) : null,
              ),
            );
            return 0;
          case 'println':
            bridge.serialOut(
              '${_fmt(args.isEmpty ? '' : args[0], args.length > 1 ? _toInt(args[1]) : null)}\n',
            );
            return 0;
          case 'write':
            bridge.serialOut(_fmt(args.isEmpty ? '' : args[0], null));
            return 0;
          case 'printf':
            bridge.serialOut(_sprintf(args));
            return 0;
          case 'read':
            return -1;
          default:
            return 0;
        }
      case 'lcd':
        bridge.lcdCommand(method, args);
        return 0;
      case 'servo':
        if (method == 'write') {
          bridge.servoWrite(obj, _toInt(args.isEmpty ? 0 : args[0]));
        } else if (method == 'attach') {
          // attach(pin) — bind servo instance to a pin (handled by sim if wired)
        }
        return 0;
      case 'firebase':
        if (method == 'begin' ||
            method == 'reconnectWiFi' ||
            method == 'setDoubleDigits') {
          return 0;
        }
        if (method.startsWith('set') ||
            method == 'setFloat' ||
            method == 'setInt' ||
            method == 'setString' ||
            method == 'setBool') {
          final path = args.isNotEmpty ? '${args[0]}' : '';
          final value = args.length > 1 ? args[1] : 0;
          await bridge.firebaseSet(path, value);
          return 1;
        }
        if (method.startsWith('get')) {
          final path = args.isNotEmpty ? '${args[0]}' : '';
          return bridge.firebaseGet(path);
        }
        return 0;
      case 'wifi':
        if (method == 'status') return 3; // WL_CONNECTED
        if (method == 'localIP') return '192.168.1.50';
        return 0;
      case 'wire':
        return 0;
      default:
        // Unknown library — degrade quietly so unsupported sketches still run.
        return 0;
    }
  }

  // ── Built-in functions ──
  Future<Object?> _builtin(String name, List<Object?> a, int line) async {
    num n(int i) => i < a.length ? _toNum(a[i]) : 0;
    int ni(int i) => i < a.length ? _toInt(a[i]) : 0;
    String pinName(int i) => _pinToken(a.length > i ? a[i] : 0);

    switch (name) {
      case 'pinMode':
        bridge.pinMode(pinName(0), ni(1));
        return 0;
      case 'digitalWrite':
        bridge.digitalWrite(pinName(0), ni(1) != 0);
        return 0;
      case 'digitalRead':
        return bridge.digitalRead(pinName(0)) ? 1 : 0;
      case 'analogRead':
        return bridge.analogRead(pinName(0));
      case 'analogWrite':
      case 'ledcWrite':
        bridge.analogWrite(pinName(0), ni(1));
        return 0;
      case 'delay':
        await _sleep(ni(0));
        return 0;
      case 'delayMicroseconds':
        await _sleep((ni(0) / 1000).ceil());
        return 0;
      case 'millis':
        return bridge.millisNow();
      case 'micros':
        return bridge.millisNow() * 1000;
      case 'map':
        return _mapFn(n(0), n(1), n(2), n(3), n(4));
      case 'constrain':
        final x = n(0);
        return x < n(1) ? n(1) : (x > n(2) ? n(2) : x);
      case 'min':
        return math.min(n(0), n(1));
      case 'max':
        return math.max(n(0), n(1));
      case 'abs':
        return n(0).abs();
      case 'sqrt':
        return math.sqrt(n(0));
      case 'pow':
        return math.pow(n(0), n(1));
      case 'sq':
        return n(0) * n(0);
      case 'sin':
        return math.sin(n(0));
      case 'cos':
        return math.cos(n(0));
      case 'tan':
        return math.tan(n(0));
      case 'floor':
        return n(0).floor();
      case 'ceil':
        return n(0).ceil();
      case 'round':
        return n(0).round();
      case 'random':
        if (a.length >= 2) {
          return ni(0) + _rng.nextInt(math.max(1, ni(1) - ni(0)));
        }
        return _rng.nextInt(math.max(1, ni(0)));
      case 'randomSeed':
        return 0;
      case 'tone':
        bridge.tone(pinName(0), n(1));
        return 0;
      case 'noTone':
        bridge.noTone(pinName(0));
        return 0;
      case 'String':
        return _fmt(a.isEmpty ? '' : a[0], a.length > 1 ? ni(1) : null);
      case 'analogReadResolution':
      case 'attachInterrupt':
      case 'detachInterrupt':
      case 'yield':
      case 'ledcSetup':
      case 'ledcAttachPin':
      case 'Serial':
        return 0;
      default:
        // Unknown call — return 0 and note it once, so partial sketches run.
        bridge.log(
          "note: unsupported function '$name()' ignored",
          error: false,
        );
        return 0;
    }
  }

  final math.Random _rng = math.Random();

  Future<void> _sleep(int ms) async {
    if (ms <= 0) {
      await _yieldIfNeeded();
      return;
    }
    // Cap a single delay so a delay(60000) doesn't freeze the session.
    final capped = math.min(ms, 4000);
    final end = DateTime.now().millisecondsSinceEpoch + capped;
    while (DateTime.now().millisecondsSinceEpoch < end) {
      if (_stopped) throw _ReturnSignal(null);
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
  }

  // ── helpers ──
  String _pinToken(Object? v) {
    if (v is num) return '${v.toInt()}';
    return '$v';
  }

  num _mapFn(num x, num inMin, num inMax, num outMin, num outMax) {
    if (inMax == inMin) return outMin;
    final r = (x - inMin) * (outMax - outMin) / (inMax - inMin) + outMin;
    final allInt =
        x is int &&
        inMin is int &&
        inMax is int &&
        outMin is int &&
        outMax is int;
    return allInt ? r.truncate() : r;
  }

  String _fmt(Object? v, int? radix) {
    if (v is String) return v;
    if (v is num) {
      if (radix == 16) return v.toInt().toRadixString(16).toUpperCase();
      if (radix == 2) return v.toInt().toRadixString(2);
      if (radix == 8) return v.toInt().toRadixString(8);
      if (v is double) {
        // Default Arduino prints 2 decimals.
        return v.toStringAsFixed(radix ?? 2);
      }
      return v.toString();
    }
    if (v == null) return '';
    return v.toString();
  }

  String _sprintf(List<Object?> args) {
    if (args.isEmpty) return '';
    final fmt = '${args[0]}';
    var i = 1;
    return fmt.replaceAllMapped(RegExp(r'%[-+ 0-9.]*[dioxXfsc%]'), (m) {
      final spec = m.group(0)!;
      if (spec == '%%') return '%';
      if (i >= args.length) return spec;
      final v = args[i++];
      if (spec.endsWith('f')) return _toNum(v).toStringAsFixed(2);
      if (spec.endsWith('x')) return _toInt(v).toRadixString(16);
      if (spec.endsWith('X')) return _toInt(v).toRadixString(16).toUpperCase();
      if (spec.endsWith('s')) return '$v';
      if (spec.endsWith('c')) return String.fromCharCode(_toInt(v));
      return '${_toInt(v)}';
    });
  }

  Object? _binOp(String op, Object? a, Object? b) {
    // String concatenation.
    if (op == '+' && (a is String || b is String)) {
      return '${_str(a)}${_str(b)}';
    }
    final x = _toNum(a);
    final y = _toNum(b);
    switch (op) {
      case '+':
        return _coerceInt2(a, b, x + y);
      case '-':
        return _coerceInt2(a, b, x - y);
      case '*':
        return _coerceInt2(a, b, x * y);
      case '/':
        if (a is int && b is int) {
          return y == 0 ? 0 : (x ~/ y);
        }
        return y == 0 ? 0 : x / y;
      case '%':
        return y == 0 ? 0 : (x.toInt() % y.toInt());
      case '==':
        return _looseEq(a, b) ? 1 : 0;
      case '!=':
        return _looseEq(a, b) ? 0 : 1;
      case '<':
        return x < y ? 1 : 0;
      case '<=':
        return x <= y ? 1 : 0;
      case '>':
        return x > y ? 1 : 0;
      case '>=':
        return x >= y ? 1 : 0;
      case '&':
        return x.toInt() & y.toInt();
      case '|':
        return x.toInt() | y.toInt();
      case '^':
        return x.toInt() ^ y.toInt();
      case '<<':
        return x.toInt() << y.toInt();
      case '>>':
        return x.toInt() >> y.toInt();
      default:
        return 0;
    }
  }

  bool _looseEq(Object? a, Object? b) {
    if (a is String || b is String) return _str(a) == _str(b);
    return _toNum(a) == _toNum(b);
  }

  num _coerceInt(num oldV, num newV) => oldV is int ? newV.toInt() : newV;
  num _coerceInt2(Object? a, Object? b, num r) =>
      (a is int && b is int) ? r.toInt() : r;

  static bool _truthyStatic(Object? v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) return v.isNotEmpty;
    return v != null;
  }

  bool _truthy(Object? v) => _truthyStatic(v);
  num _toNum(Object? v) {
    if (v is num) return v;
    if (v is bool) return v ? 1 : 0;
    if (v is String) return num.tryParse(v) ?? 0;
    return 0;
  }

  int _toInt(Object? v) => _toNum(v).toInt();
  String _str(Object? v) {
    if (v is double) return v.toStringAsFixed(2);
    return '${v ?? ''}';
  }
}

// ─────────────────────────── Simulator engine ───────────────────────────
