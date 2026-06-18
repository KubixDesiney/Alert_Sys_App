part of 'hw_runtime.dart';

abstract class _Node {
  final int line;
  _Node(this.line);
}

// Expressions
class _NumLit extends _Node {
  final num v;
  _NumLit(this.v, int l) : super(l);
}

class _StrLit extends _Node {
  final String v;
  _StrLit(this.v, int l) : super(l);
}

class _BoolLit extends _Node {
  final bool v;
  _BoolLit(this.v, int l) : super(l);
}

class _Ident extends _Node {
  final String name;
  _Ident(this.name, int l) : super(l);
}

class _Unary extends _Node {
  final String op;
  final _Node expr;
  final bool prefix;
  _Unary(this.op, this.expr, this.prefix, int l) : super(l);
}

class _Binary extends _Node {
  final String op;
  final _Node l;
  final _Node r;
  _Binary(this.op, this.l, this.r, int line) : super(line);
}

class _Assign extends _Node {
  final String op;
  final _Node target;
  final _Node value;
  _Assign(this.op, this.target, this.value, int l) : super(l);
}

class _Ternary extends _Node {
  final _Node cond;
  final _Node a;
  final _Node b;
  _Ternary(this.cond, this.a, this.b, int l) : super(l);
}

class _Member extends _Node {
  final _Node obj;
  final String name;
  _Member(this.obj, this.name, int l) : super(l);
}

class _Index extends _Node {
  final _Node arr;
  final _Node idx;
  _Index(this.arr, this.idx, int l) : super(l);
}

class _Call extends _Node {
  final _Node callee;
  final List<_Node> args;
  _Call(this.callee, this.args, int l) : super(l);
}

class _ArrayLit extends _Node {
  final List<_Node> elements;
  _ArrayLit(this.elements, int l) : super(l);
}

// Statements
class _VarDecl extends _Node {
  final String type;
  final List<({String name, _Node? init, bool isArray})> vars;
  _VarDecl(this.type, this.vars, int l) : super(l);
}

class _ExprStmt extends _Node {
  final _Node expr;
  _ExprStmt(this.expr, int l) : super(l);
}

class _Block extends _Node {
  final List<_Node> stmts;
  _Block(this.stmts, int l) : super(l);
}

class _If extends _Node {
  final _Node cond;
  final _Node then;
  final _Node? els;
  _If(this.cond, this.then, this.els, int l) : super(l);
}

class _For extends _Node {
  final _Node? init;
  final _Node? cond;
  final _Node? update;
  final _Node body;
  _For(this.init, this.cond, this.update, this.body, int l) : super(l);
}

class _While extends _Node {
  final _Node cond;
  final _Node body;
  final bool doWhile;
  _While(this.cond, this.body, this.doWhile, int l) : super(l);
}

class _Return extends _Node {
  final _Node? value;
  _Return(this.value, int l) : super(l);
}

class _BreakNode extends _Node {
  _BreakNode(super.line);
}

class _ContinueNode extends _Node {
  _ContinueNode(super.line);
}

class _FuncDecl extends _Node {
  final String name;
  final List<({String type, String name})> params;
  final _Block body;
  _FuncDecl(this.name, this.params, this.body, int l) : super(l);
}

// ─────────────────────────── Parser ───────────────────────────

const _typeKeywords = {
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
  'const',
  'static',
  'volatile',
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
};

/// Library class names we recognise as object declarations.
const _libClasses = {
  'LiquidCrystal_I2C': 'lcd',
  'LiquidCrystal': 'lcd',
  'Servo': 'servo',
  'DHT': 'dht',
  'Adafruit_NeoPixel': 'neopixel',
  'WiFiClient': 'wifi',
  'HTTPClient': 'http',
};
