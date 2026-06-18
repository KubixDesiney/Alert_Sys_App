part of 'hw_runtime.dart';

class _Parser {
  final List<_Token> t;
  int _p = 0;
  final List<_FuncDecl> functions = [];
  final List<_VarDecl> globals = [];

  /// type-name → declared instance kind (for member dispatch).
  final Map<String, String> instances = {};

  _Parser(this.t);

  _Token get _cur => t[_p];
  _Token get _next => t[_p + 1 < t.length ? _p + 1 : t.length - 1];
  bool _isOp(String s) => _cur.kind == _Tk.op && _cur.text == s;
  bool _isId(String s) => _cur.kind == _Tk.id && _cur.text == s;

  Never _err(String msg) =>
      throw HwSimException('Syntax error: $msg', line: _cur.line);

  void _expectOp(String s) {
    if (!_isOp(s)) _err("expected '$s' but found '${_cur.text}'");
    _p++;
  }

  void parse() {
    while (_cur.kind != _Tk.eof) {
      final before = _p;
      _parseTopLevel();
      if (_p == before) {
        _err("unexpected '${_cur.text}'");
      }
    }
  }

  void _parseTopLevel() {
    if (_isOp('}')) {
      _err("unexpected '}'");
    }
    // Consume a type.
    final typeStart = _p;
    final type = _consumeType();
    if (_cur.kind != _Tk.id) {
      // Not a declaration we understand — skip to next semicolon to stay robust.
      _p = typeStart;
      _skipToSemicolon();
      return;
    }
    final name = _cur.text;
    _p++;
    if (_isOp('(')) {
      // Could be function definition or constructor-style decl.
      final save = _p;
      try {
        final params = _parseParams();
        if (_isOp('{')) {
          final body = _parseBlock();
          functions.add(_FuncDecl(name, params, body, body.line));
          return;
        }
      } on HwSimException {
        // Constructor declarations use value args, not typed params:
        // LiquidCrystal_I2C lcd(0x27, 16, 2);
      }
      // Constructor decl, e.g. LiquidCrystal_I2C lcd(0x27,16,2);
      _p = save;
      _parseCtorDecl(type, name);
      return;
    }
    // Plain global variable declaration.
    _p = typeStart;
    final decl = _parseVarDecl();
    globals.add(decl);
  }

  void _parseCtorDecl(String type, String name) {
    // Skip the (...) constructor args.
    _expectOp('(');
    var depth = 1;
    while (depth > 0 && _cur.kind != _Tk.eof) {
      if (_isOp('(')) depth++;
      if (_isOp(')')) depth--;
      _p++;
    }
    if (_isOp(';')) _p++;
    final kind = _libClasses[type];
    if (kind != null) instances[name] = kind;
  }

  String _consumeType() {
    final sb = <String>[];
    while (_cur.kind == _Tk.id && _typeKeywords.contains(_cur.text)) {
      sb.add(_cur.text);
      _p++;
    }
    if (sb.isEmpty && _cur.kind == _Tk.id) {
      // A library/user type name.
      sb.add(_cur.text);
      _p++;
    }
    // Pointer / reference markers.
    while (_isOp('*') || _isOp('&')) {
      _p++;
    }
    return sb.join(' ');
  }

  List<({String type, String name})> _parseParams() {
    _expectOp('(');
    final params = <({String type, String name})>[];
    if (_isOp(')')) {
      _p++;
      return params;
    }
    while (true) {
      if (_isId('void') && _next.text == ')') {
        _p++;
        break;
      }
      final type = _consumeType();
      var pname = '';
      if (_cur.kind == _Tk.id) {
        pname = _cur.text;
        _p++;
      }
      // Array param marker.
      while (_isOp('[')) {
        while (!_isOp(']') && _cur.kind != _Tk.eof) {
          _p++;
        }
        if (_isOp(']')) _p++;
      }
      params.add((type: type, name: pname));
      if (_isOp(',')) {
        _p++;
        continue;
      }
      break;
    }
    _expectOp(')');
    return params;
  }

  _Block _parseBlock() {
    final l = _cur.line;
    _expectOp('{');
    final stmts = <_Node>[];
    while (!_isOp('}') && _cur.kind != _Tk.eof) {
      stmts.add(_parseStmt());
    }
    _expectOp('}');
    return _Block(stmts, l);
  }

  _Node _parseStmt() {
    if (_isOp('{')) return _parseBlock();
    if (_isId('if')) return _parseIf();
    if (_isId('for')) return _parseFor();
    if (_isId('while')) return _parseWhile();
    if (_isId('do')) return _parseDoWhile();
    if (_isId('return')) {
      final l = _cur.line;
      _p++;
      _Node? v;
      if (!_isOp(';')) v = _parseExpr();
      if (_isOp(';')) _p++;
      return _Return(v, l);
    }
    if (_isId('break')) {
      final l = _cur.line;
      _p++;
      if (_isOp(';')) _p++;
      return _BreakNode(l);
    }
    if (_isId('continue')) {
      final l = _cur.line;
      _p++;
      if (_isOp(';')) _p++;
      return _ContinueNode(l);
    }
    if (_looksLikeDeclStmt()) {
      return _parseVarDecl();
    }
    // Expression statement.
    final l = _cur.line;
    final e = _parseExpr();
    if (_isOp(';')) _p++;
    return _ExprStmt(e, l);
  }

  bool _looksLikeDeclStmt() {
    if (_cur.kind != _Tk.id) return false;
    if (_typeKeywords.contains(_cur.text)) return true;
    if (_libClasses.containsKey(_cur.text)) return true;
    // Two identifiers in a row, second not followed by '(' that suggests a call
    // → declaration ("Foo bar;" / "Foo bar = ...").
    if (_next.kind == _Tk.id) {
      final after = t[_p + 2 < t.length ? _p + 2 : t.length - 1];
      if (after.kind == _Tk.op &&
          (after.text == '=' ||
              after.text == ';' ||
              after.text == '[' ||
              after.text == ',' ||
              after.text == '(')) {
        return true;
      }
    }
    return false;
  }

  _VarDecl _parseVarDecl() {
    final l = _cur.line;
    final type = _consumeType();
    final vars = <({String name, _Node? init, bool isArray})>[];
    while (true) {
      final name = _cur.text;
      _p++;
      var isArray = false;
      if (_isOp('[')) {
        isArray = true;
        _p++;
        // size expr (ignored) until ]
        while (!_isOp(']') && _cur.kind != _Tk.eof) {
          _p++;
        }
        if (_isOp(']')) _p++;
      }
      // Constructor-style local object: Servo s;  (no init) handled below.
      if (_isOp('(')) {
        _parseCtorDecl(type, name);
        return _VarDecl(type, vars, l);
      }
      _Node? init;
      if (_isOp('=')) {
        _p++;
        if (_isOp('{')) {
          init = _parseArrayLit();
        } else {
          init = _parseAssign();
        }
      }
      vars.add((name: name, init: init, isArray: isArray));
      // Register library-class instances.
      if (_libClasses.containsKey(type.split(' ').last)) {
        instances[name] = _libClasses[type.split(' ').last]!;
      }
      if (_isOp(',')) {
        _p++;
        continue;
      }
      break;
    }
    if (_isOp(';')) _p++;
    return _VarDecl(type, vars, l);
  }

  _Node _parseArrayLit() {
    final l = _cur.line;
    _expectOp('{');
    final els = <_Node>[];
    while (!_isOp('}') && _cur.kind != _Tk.eof) {
      els.add(_parseAssign());
      if (_isOp(',')) {
        _p++;
        continue;
      }
      break;
    }
    _expectOp('}');
    return _ArrayLit(els, l);
  }

  _Node _parseIf() {
    final l = _cur.line;
    _p++;
    _expectOp('(');
    final cond = _parseExpr();
    _expectOp(')');
    final then = _parseStmt();
    _Node? els;
    if (_isId('else')) {
      _p++;
      els = _parseStmt();
    }
    return _If(cond, then, els, l);
  }

  _Node _parseFor() {
    final l = _cur.line;
    _p++;
    _expectOp('(');
    _Node? init;
    if (!_isOp(';')) {
      if (_looksLikeDeclStmt()) {
        init = _parseVarDecl();
      } else {
        init = _ExprStmt(_parseExpr(), l);
        if (_isOp(';')) _p++;
      }
    } else {
      _p++;
    }
    _Node? cond;
    if (!_isOp(';')) cond = _parseExpr();
    _expectOp(';');
    _Node? update;
    if (!_isOp(')')) update = _parseExpr();
    _expectOp(')');
    final body = _parseStmt();
    return _For(init, cond, update, body, l);
  }

  _Node _parseWhile() {
    final l = _cur.line;
    _p++;
    _expectOp('(');
    final cond = _parseExpr();
    _expectOp(')');
    final body = _parseStmt();
    return _While(cond, body, false, l);
  }

  _Node _parseDoWhile() {
    final l = _cur.line;
    _p++;
    final body = _parseStmt();
    if (_isId('while')) _p++;
    _expectOp('(');
    final cond = _parseExpr();
    _expectOp(')');
    if (_isOp(';')) _p++;
    return _While(cond, body, true, l);
  }

  // Expression precedence
  _Node _parseExpr() => _parseAssign();

  _Node _parseAssign() {
    final left = _parseTernary();
    if (_cur.kind == _Tk.op &&
        const [
          '=',
          '+=',
          '-=',
          '*=',
          '/=',
          '%=',
          '&=',
          '|=',
          '^=',
          '<<=',
          '>>=',
        ].contains(_cur.text)) {
      final op = _cur.text;
      final l = _cur.line;
      _p++;
      final value = _parseAssign();
      return _Assign(op, left, value, l);
    }
    return left;
  }

  _Node _parseTernary() {
    final cond = _parseBinary(0);
    if (_isOp('?')) {
      final l = _cur.line;
      _p++;
      final a = _parseAssign();
      _expectOp(':');
      final b = _parseAssign();
      return _Ternary(cond, a, b, l);
    }
    return cond;
  }

  static const List<List<String>> _binLevels = [
    ['||'],
    ['&&'],
    ['|'],
    ['^'],
    ['&'],
    ['==', '!='],
    ['<', '<=', '>', '>='],
    ['<<', '>>'],
    ['+', '-'],
    ['*', '/', '%'],
  ];

  _Node _parseBinary(int level) {
    if (level >= _binLevels.length) return _parseUnary();
    var left = _parseBinary(level + 1);
    while (_cur.kind == _Tk.op && _binLevels[level].contains(_cur.text)) {
      final op = _cur.text;
      final l = _cur.line;
      _p++;
      final right = _parseBinary(level + 1);
      left = _Binary(op, left, right, l);
    }
    return left;
  }

  _Node _parseUnary() {
    if (_cur.kind == _Tk.op &&
        const ['!', '~', '-', '+', '++', '--'].contains(_cur.text)) {
      final op = _cur.text;
      final l = _cur.line;
      _p++;
      final e = _parseUnary();
      return _Unary(op, e, true, l);
    }
    return _parsePostfix();
  }

  _Node _parsePostfix() {
    var e = _parsePrimary();
    while (true) {
      if (_isOp('.') || _isOp('->')) {
        final l = _cur.line;
        _p++;
        final name = _cur.text;
        _p++;
        e = _Member(e, name, l);
      } else if (_isOp('(')) {
        final l = _cur.line;
        final args = _parseArgs();
        e = _Call(e, args, l);
      } else if (_isOp('[')) {
        final l = _cur.line;
        _p++;
        final idx = _parseExpr();
        _expectOp(']');
        e = _Index(e, idx, l);
      } else if (_isOp('++') || _isOp('--')) {
        final op = _cur.text;
        final l = _cur.line;
        _p++;
        e = _Unary(op, e, false, l);
      } else {
        break;
      }
    }
    return e;
  }

  List<_Node> _parseArgs() {
    _expectOp('(');
    final args = <_Node>[];
    if (_isOp(')')) {
      _p++;
      return args;
    }
    while (true) {
      args.add(_parseAssign());
      if (_isOp(',')) {
        _p++;
        continue;
      }
      break;
    }
    _expectOp(')');
    return args;
  }

  _Node _parsePrimary() {
    final tok = _cur;
    if (tok.kind == _Tk.num) {
      _p++;
      return _NumLit(tok.value! as num, tok.line);
    }
    if (tok.kind == _Tk.str) {
      _p++;
      return _StrLit(tok.value! as String, tok.line);
    }
    if (tok.kind == _Tk.chr) {
      _p++;
      return _NumLit(tok.value! as int, tok.line);
    }
    if (tok.kind == _Tk.id) {
      if (tok.text == 'true') {
        _p++;
        return _BoolLit(true, tok.line);
      }
      if (tok.text == 'false') {
        _p++;
        return _BoolLit(false, tok.line);
      }
      // A C-style cast like (int)x is handled where we see '(' primary.
      _p++;
      return _Ident(tok.text, tok.line);
    }
    if (_isOp('(')) {
      _p++;
      // Possible cast: (type) expr
      if (_cur.kind == _Tk.id &&
          _typeKeywords.contains(_cur.text) &&
          _next.text == ')') {
        _p++; // type
        _expectOp(')');
        return _parseUnary(); // ignore cast, evaluate operand
      }
      final e = _parseExpr();
      _expectOp(')');
      return e;
    }
    if (_isOp('{')) {
      return _parseArrayLit();
    }
    _err("unexpected '${tok.text}'");
  }

  void _skipToSemicolon() {
    while (_cur.kind != _Tk.eof && !_isOp(';') && !_isOp('}')) {
      _p++;
    }
    if (_isOp(';')) _p++;
  }
}

// ─────────────────────────── Runtime values & signals ───────────────────────────
