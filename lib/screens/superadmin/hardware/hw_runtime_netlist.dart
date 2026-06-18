part of 'hw_runtime.dart';

String _nodeKey(String comp, String pin) => '$comp/$pin';

/// Union-find net extraction over the schematic. Wires connect pins; resistors
/// pass through (a↔b); pressed buttons short their terminals. The result lets
/// the solver propagate voltages from drivers (rails, board pins, sensors) to
/// readers (board inputs, LEDs).
class HwNetList {
  final Map<String, int> _parent = {};
  final Map<String, int> nodeNet = {}; // node → canonical net id

  /// All nodes belonging to each net id.
  final Map<int, List<String>> nets = {};

  HwNetList.build(HwCircuit circuit) {
    int counter = 0;
    int idOf(String node) => _parent.putIfAbsent(node, () => counter++);

    final ids = <int, int>{};
    int find(int x) {
      var r = x;
      while (ids[r] != null && ids[r] != r) {
        r = ids[r]!;
      }
      return r;
    }

    void ensure(String node) {
      final i = idOf(node);
      ids.putIfAbsent(i, () => i);
    }

    void union(String a, String b) {
      ensure(a);
      ensure(b);
      final ra = find(idOf(a));
      final rb = find(idOf(b));
      if (ra != rb) ids[ra] = rb;
    }

    // Register every pin as its own node first.
    for (final c in circuit.components) {
      for (final p in c.def.pins) {
        ensure(_nodeKey(c.id, p.name));
      }
    }

    // Wires merge nets.
    for (final w in circuit.wires) {
      union(_nodeKey(w.fromComp, w.fromPin), _nodeKey(w.toComp, w.toPin));
    }

    // Resistors are a straight pass-through for logic-level connectivity.
    for (final c in circuit.components) {
      if (c.type == 'resistor') {
        union(_nodeKey(c.id, 'a'), _nodeKey(c.id, 'b'));
      }
      // A pressed button shorts terminal 1 to terminal 2.
      if (c.type == 'button' && c.params['pressed'] == true) {
        union(_nodeKey(c.id, '1'), _nodeKey(c.id, '2'));
      }
    }

    // Canonicalise.
    final canon = <int, int>{};
    for (final entry in _parent.entries) {
      final root = find(entry.value);
      final net = canon.putIfAbsent(root, () => canon.length);
      nodeNet[entry.key] = net;
      nets.putIfAbsent(net, () => []).add(entry.key);
    }
  }

  int? netOf(String comp, String pin) => nodeNet[_nodeKey(comp, pin)];

  /// Distinct nets a wire could connect to from this pin (for validation).
  int get netCount => nets.length;
}

/// A captured runtime/compile problem surfaced to the IDE panel.
class HwDiag {
  final String message;
  final int? line;
  final bool error; // false → warning
  const HwDiag(this.message, {this.line, this.error = true});
}

class HwSimException implements Exception {
  final String message;
  final int? line;
  HwSimException(this.message, {this.line});
  @override
  String toString() => message;
}

// ─────────────────────────── Lexer ───────────────────────────
