part of 'hw_runtime.dart';

enum _Tk { num, str, chr, id, op, eof }

class _Token {
  final _Tk kind;
  final String text;
  final Object? value;
  final int line;
  _Token(this.kind, this.text, this.line, [this.value]);
  @override
  String toString() => '$kind($text)';
}

class _Lexer {
  final String src;
  int _i = 0;
  int _line = 1;
  _Lexer(this.src);

  static const _ops3 = ['<<=', '>>=', '...'];
  static const _ops2 = [
    '==',
    '!=',
    '<=',
    '>=',
    '&&',
    '||',
    '++',
    '--',
    '+=',
    '-=',
    '*=',
    '/=',
    '%=',
    '&=',
    '|=',
    '^=',
    '<<',
    '>>',
    '->',
  ];

  List<_Token> tokenize() {
    final out = <_Token>[];
    while (_i < src.length) {
      final c = src[_i];
      if (c == '\n') {
        _line++;
        _i++;
        continue;
      }
      if (c.trim().isEmpty) {
        _i++;
        continue;
      }
      // Comments.
      if (c == '/' && _peek(1) == '/') {
        while (_i < src.length && src[_i] != '\n') {
          _i++;
        }
        continue;
      }
      if (c == '/' && _peek(1) == '*') {
        _i += 2;
        while (_i < src.length && !(src[_i] == '*' && _peek(1) == '/')) {
          if (src[_i] == '\n') _line++;
          _i++;
        }
        _i += 2;
        continue;
      }
      // Preprocessor lines (#include, #define handled in preprocess()).
      if (c == '#') {
        while (_i < src.length && src[_i] != '\n') {
          _i++;
        }
        continue;
      }
      // Strings.
      if (c == '"') {
        out.add(_readString());
        continue;
      }
      if (c == "'") {
        out.add(_readChar());
        continue;
      }
      // Numbers.
      if (_isDigit(c) || (c == '.' && _isDigit(_peek(1)))) {
        out.add(_readNumber());
        continue;
      }
      // Identifiers / keywords.
      if (_isIdStart(c)) {
        final start = _i;
        while (_i < src.length && _isIdPart(src[_i])) {
          _i++;
        }
        out.add(_Token(_Tk.id, src.substring(start, _i), _line));
        continue;
      }
      // Operators / punctuation.
      final three = _slice(3);
      if (_ops3.contains(three)) {
        out.add(_Token(_Tk.op, three, _line));
        _i += 3;
        continue;
      }
      final two = _slice(2);
      if (_ops2.contains(two)) {
        out.add(_Token(_Tk.op, two, _line));
        _i += 2;
        continue;
      }
      out.add(_Token(_Tk.op, c, _line));
      _i++;
    }
    out.add(_Token(_Tk.eof, '', _line));
    return out;
  }

  String _slice(int n) =>
      (_i + n <= src.length) ? src.substring(_i, _i + n) : '';
  String _peek(int o) => (_i + o < src.length) ? src[_i + o] : '';

  _Token _readString() {
    final ln = _line;
    _i++; // opening quote
    final sb = StringBuffer();
    while (_i < src.length && src[_i] != '"') {
      var ch = src[_i];
      if (ch == '\\' && _i + 1 < src.length) {
        _i++;
        ch = _escape(src[_i]);
      }
      sb.write(ch);
      _i++;
    }
    _i++; // closing quote
    return _Token(_Tk.str, sb.toString(), ln, sb.toString());
  }

  _Token _readChar() {
    final ln = _line;
    _i++;
    var ch = src[_i];
    if (ch == '\\') {
      _i++;
      ch = _escape(src[_i]);
    }
    _i++;
    if (_i < src.length && src[_i] == "'") _i++;
    return _Token(_Tk.chr, ch, ln, ch.codeUnitAt(0));
  }

  String _escape(String c) => switch (c) {
    'n' => '\n',
    't' => '\t',
    'r' => '\r',
    '0' => '\x00',
    _ => c,
  };

  _Token _readNumber() {
    final ln = _line;
    final start = _i;
    if (src[_i] == '0' && (_peek(1) == 'x' || _peek(1) == 'X')) {
      _i += 2;
      while (_i < src.length && _isHex(src[_i])) {
        _i++;
      }
      final t = src.substring(start, _i);
      return _Token(_Tk.num, t, ln, int.parse(t.substring(2), radix: 16));
    }
    if (src[_i] == '0' && (_peek(1) == 'b' || _peek(1) == 'B')) {
      _i += 2;
      while (_i < src.length && (src[_i] == '0' || src[_i] == '1')) {
        _i++;
      }
      final t = src.substring(start, _i);
      return _Token(_Tk.num, t, ln, int.parse(t.substring(2), radix: 2));
    }
    var isDouble = false;
    while (_i < src.length &&
        (_isDigit(src[_i]) ||
            src[_i] == '.' ||
            src[_i] == 'e' ||
            src[_i] == 'E')) {
      if (src[_i] == '.' || src[_i] == 'e' || src[_i] == 'E') isDouble = true;
      _i++;
    }
    // Trailing type suffixes (L, U, f).
    while (_i < src.length && 'fFlLuU'.contains(src[_i])) {
      if (src[_i] == 'f' || src[_i] == 'F') isDouble = true;
      _i++;
    }
    final t = src.substring(start, _i).replaceAll(RegExp('[fFlLuU]'), '');
    final v = isDouble ? double.parse(t) : int.parse(t);
    return _Token(_Tk.num, t, ln, v);
  }

  static bool _isDigit(String c) => c.isNotEmpty && c.codeUnitAt(0) ^ 0x30 < 10;
  static bool _isHex(String c) => _isDigit(c) || 'abcdefABCDEF'.contains(c);
  static bool _isIdStart(String c) =>
      c == '_' || RegExp(r'[A-Za-z]').hasMatch(c);
  static bool _isIdPart(String c) =>
      c == '_' || RegExp(r'[A-Za-z0-9]').hasMatch(c);
}

// ─────────────────────────── AST ───────────────────────────
