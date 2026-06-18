import 'dart:math' as math;
import 'dart:ui';

/// Data layer + component catalog for the SuperAdmin Hardware Lab.
///
/// The lab is a Proteus/Wokwi-class IoT design + simulation surface. This file
/// owns the *static* definitions (what an ESP32 / LED / sensor is, where its
/// pins sit) and the *placed* instances (a component dropped on the canvas, a
/// wire between two pins, a whole circuit document). It is pure Dart — no
/// Flutter widgets, no Firebase — so the simulator and the painters can both
/// build on it and it stays unit-testable.

/// One grid cell in logical pixels. Components snap to this lattice so wiring
/// lands cleanly and the board reads like real perfboard.
const double kHwGrid = 24.0;

/// Functional class of a pin — drives net colouring, validation and the
/// logic-level simulation.
enum HwPinKind {
  power, // VCC / 5V / 3V3 / VIN
  ground, // GND
  digital, // generic digital IO header pin (Arduino D0..D13)
  analog, // analog-capable input (A0.., ADC GPIOs)
  gpio, // ESP32 general purpose IO (digital + often analog/PWM)
  passive, // resistor / wire-through terminal, no inherent level
  anode, // LED / diode +
  cathode, // LED / diode -
  signal, // sensor / actuator data line
  i2cSda,
  i2cScl,
}

/// Broad palette category for the component drawer.
enum HwCategory { boards, output, input, sensors, passive, power }

extension HwCategoryLabel on HwCategory {
  String get label => switch (this) {
        HwCategory.boards => 'Boards & MCUs',
        HwCategory.output => 'Outputs',
        HwCategory.input => 'Inputs',
        HwCategory.sensors => 'Sensors',
        HwCategory.passive => 'Passives',
        HwCategory.power => 'Power',
      };
}

/// A pin on a component definition. [dx]/[dy] are the pin's centre offset, in
/// logical pixels, from the component's top-left corner in its un-rotated local
/// frame. [busName] (when set) is how firmware addresses the pin — `"13"`,
/// `"A0"`, `"GPIO34"` — used by the interpreter to bind code to silicon.
class HwPinDef {
  final String name;
  final HwPinKind kind;
  final double dx;
  final double dy;
  final String? busName;

  /// Analog-capable digital/gpio pins expose an ADC channel.
  final bool adc;

  /// PWM-capable pins (analogWrite / ledc).
  final bool pwm;

  const HwPinDef(
    this.name,
    this.kind,
    this.dx,
    this.dy, {
    this.busName,
    this.adc = false,
    this.pwm = false,
  });
}

/// Static definition of a component type.
class HwComponentDef {
  final String type;
  final String name;
  final String shortName;
  final HwCategory category;
  final double width;
  final double height;
  final List<HwPinDef> pins;
  final Color accent;
  final String blurb;

  /// True for ESP32 / Arduino — the programmable controllers.
  final bool isController;

  /// Default mutable parameters cloned onto each instance.
  final Map<String, Object?> defaults;

  const HwComponentDef({
    required this.type,
    required this.name,
    required this.shortName,
    required this.category,
    required this.width,
    required this.height,
    required this.pins,
    required this.accent,
    required this.blurb,
    this.isController = false,
    this.defaults = const {},
  });

  HwPinDef? pin(String name) {
    for (final p in pins) {
      if (p.name == name) return p;
    }
    return null;
  }
}

/// A placed instance of a component on the canvas.
class HwComponent {
  final String id;
  final String type;
  double x;
  double y;

  /// Rotation in quarter turns (0..3).
  int rot;
  String label;

  /// Per-instance live parameters: LED colour, resistor ohms, sensor reading…
  final Map<String, Object?> params;

  HwComponent({
    required this.id,
    required this.type,
    required this.x,
    required this.y,
    this.rot = 0,
    this.label = '',
    Map<String, Object?>? params,
  }) : params = params ?? {};

  HwComponentDef get def => kHwCatalog[type] ?? kHwCatalog['led']!;

  Offset get origin => Offset(x, y);

  /// Outer footprint after rotation (axis-aligned bounding box).
  Size get footprint {
    final d = def;
    return (rot % 2 == 0) ? Size(d.width, d.height) : Size(d.height, d.width);
  }

  /// Absolute centre of a pin on the canvas, honouring rotation.
  Offset? pinCenter(String pinName) {
    final p = def.pin(pinName);
    if (p == null) return null;
    return _rotate(Offset(p.dx, p.dy), def.width, def.height, rot)
        .translate(x, y);
  }

  /// All pin centres keyed by pin name.
  Map<String, Offset> pinCenters() {
    final out = <String, Offset>{};
    for (final p in def.pins) {
      out[p.name] =
          _rotate(Offset(p.dx, p.dy), def.width, def.height, rot)
              .translate(x, y);
    }
    return out;
  }

  static Offset _rotate(Offset local, double w, double h, int rot) {
    switch (rot % 4) {
      case 1:
        return Offset(h - local.dy, local.dx);
      case 2:
        return Offset(w - local.dx, h - local.dy);
      case 3:
        return Offset(local.dy, w - local.dx);
      default:
        return local;
    }
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'type': type,
        'x': x,
        'y': y,
        'rot': rot,
        'label': label,
        'params': params,
      };

  factory HwComponent.fromJson(Map data) => HwComponent(
        id: '${data['id']}',
        type: '${data['type']}',
        x: (data['x'] as num?)?.toDouble() ?? 0,
        y: (data['y'] as num?)?.toDouble() ?? 0,
        rot: (data['rot'] as num?)?.toInt() ?? 0,
        label: '${data['label'] ?? ''}',
        params: (data['params'] is Map)
            ? Map<String, Object?>.from(data['params'] as Map)
            : {},
      );
}

/// A wire between two component pins.
class HwWire {
  final String id;
  final String fromComp;
  final String fromPin;
  final String toComp;
  final String toPin;
  final int colorValue;

  const HwWire({
    required this.id,
    required this.fromComp,
    required this.fromPin,
    required this.toComp,
    required this.toPin,
    required this.colorValue,
  });

  Color get color => Color(colorValue);

  Map<String, Object?> toJson() => {
        'id': id,
        'fromComp': fromComp,
        'fromPin': fromPin,
        'toComp': toComp,
        'toPin': toPin,
        'color': colorValue,
      };

  factory HwWire.fromJson(Map data) => HwWire(
        id: '${data['id']}',
        fromComp: '${data['fromComp']}',
        fromPin: '${data['fromPin']}',
        toComp: '${data['toComp']}',
        toPin: '${data['toPin']}',
        colorValue: (data['color'] as num?)?.toInt() ?? 0xFF22D3EE,
      );
}

/// A complete circuit document: the board sketch plus the schematic.
class HwCircuit {
  String id;
  String name;
  final List<HwComponent> components;
  final List<HwWire> wires;
  String sketch;
  int updatedAtMs;

  HwCircuit({
    required this.id,
    required this.name,
    List<HwComponent>? components,
    List<HwWire>? wires,
    String? sketch,
    int? updatedAtMs,
  })  : components = components ?? [],
        wires = wires ?? [],
        sketch = sketch ?? kStarterSketch,
        updatedAtMs = updatedAtMs ?? DateTime.now().millisecondsSinceEpoch;

  HwComponent? byId(String id) {
    for (final c in components) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// The first programmable controller on the canvas (drives the sketch).
  HwComponent? get controller {
    for (final c in components) {
      if (c.def.isController) return c;
    }
    return null;
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'sketch': sketch,
        'updatedAtMs': updatedAtMs,
        'components': components.map((c) => c.toJson()).toList(),
        'wires': wires.map((w) => w.toJson()).toList(),
      };

  factory HwCircuit.fromJson(Map data) => HwCircuit(
        id: '${data['id']}',
        name: '${data['name'] ?? 'Untitled circuit'}',
        sketch: '${data['sketch'] ?? kStarterSketch}',
        updatedAtMs: (data['updatedAtMs'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch,
        components: _list(data['components'])
            .map((e) => HwComponent.fromJson(e as Map))
            .toList(),
        wires: _list(data['wires'])
            .map((e) => HwWire.fromJson(e as Map))
            .toList(),
      );

  static List _list(Object? v) {
    if (v is List) return v;
    if (v is Map) return v.values.toList();
    return const [];
  }
}

/// Binds a circuit / controller to a real factory machine for the global view.
class HwDeviceBinding {
  String id;
  String factoryId;
  String machineLabel; // e.g. MACH-001
  String conveyor; // e.g. Conveyor 1
  String controllerType; // esp32 / arduino-uno
  String circuitId; // linked circuit document
  List<String> peripherals; // human labels: "Heat sensor", "4 colored buttons"
  String status; // designed / wired / verified / live
  int updatedAtMs;

  HwDeviceBinding({
    required this.id,
    this.factoryId = '',
    this.machineLabel = '',
    this.conveyor = '',
    this.controllerType = 'esp32',
    this.circuitId = '',
    List<String>? peripherals,
    this.status = 'designed',
    int? updatedAtMs,
  })  : peripherals = peripherals ?? [],
        updatedAtMs = updatedAtMs ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, Object?> toJson() => {
        'id': id,
        'factoryId': factoryId,
        'machineLabel': machineLabel,
        'conveyor': conveyor,
        'controllerType': controllerType,
        'circuitId': circuitId,
        'peripherals': peripherals,
        'status': status,
        'updatedAtMs': updatedAtMs,
      };

  factory HwDeviceBinding.fromJson(Map data) => HwDeviceBinding(
        id: '${data['id']}',
        factoryId: '${data['factoryId'] ?? ''}',
        machineLabel: '${data['machineLabel'] ?? ''}',
        conveyor: '${data['conveyor'] ?? ''}',
        controllerType: '${data['controllerType'] ?? 'esp32'}',
        circuitId: '${data['circuitId'] ?? ''}',
        peripherals: (data['peripherals'] is List)
            ? (data['peripherals'] as List).map((e) => '$e').toList()
            : <String>[],
        status: '${data['status'] ?? 'designed'}',
        updatedAtMs: (data['updatedAtMs'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch,
      );
}

String hwNewId([String prefix = 'c']) {
  final r = math.Random();
  final n = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final s = r.nextInt(0x7fffffff).toRadixString(36);
  return '$prefix-$n$s';
}

// ───────────────────────── Wire routing ─────────────────────────

/// Outward exit direction (a unit, axis-aligned offset) for a pin — which way a
/// wire should leave the pad so it never cuts back across the component body.
Offset hwPinExitDir(HwComponent c, String pinName) {
  final center = c.pinCenter(pinName);
  if (center == null) return const Offset(1, 0);
  final fp = c.footprint;
  final mid = Offset(c.x + fp.width / 2, c.y + fp.height / 2);
  final d = center - mid;
  if (d.dx.abs() >= d.dy.abs()) {
    return Offset(d.dx >= 0 ? 1 : -1, 0);
  }
  return Offset(0, d.dy >= 0 ? 1 : -1);
}

/// Clean orthogonal (Manhattan) route between two pins — Proteus-style: a short
/// stub out of each pad in its exit direction, then right-angle segments. The
/// painter draws this with rounded corners; the canvas hit-tests the same
/// points, so what you see is exactly what you can click.
List<Offset> hwRoutePoints(Offset a, Offset b, Offset da, Offset db,
    {double stub = 18}) {
  final p1 = a + da * stub;
  final p2 = b + db * stub;
  final mids = <Offset>[];
  final aH = da.dx != 0;
  final bH = db.dx != 0;
  if (aH && bH) {
    final mx = (p1.dx + p2.dx) / 2;
    mids..add(Offset(mx, p1.dy))..add(Offset(mx, p2.dy));
  } else if (!aH && !bH) {
    final my = (p1.dy + p2.dy) / 2;
    mids..add(Offset(p1.dx, my))..add(Offset(p2.dx, my));
  } else if (aH && !bH) {
    mids.add(Offset(p2.dx, p1.dy));
  } else {
    mids.add(Offset(p1.dx, p2.dy));
  }
  return _simplifyPolyline(<Offset>[a, p1, ...mids, p2, b]);
}

List<Offset> _simplifyPolyline(List<Offset> pts) {
  final dedup = <Offset>[];
  for (final p in pts) {
    if (dedup.isNotEmpty && (dedup.last - p).distance < 0.5) continue;
    dedup.add(p);
  }
  if (dedup.length <= 2) return dedup;
  final res = <Offset>[dedup.first];
  for (var i = 1; i < dedup.length - 1; i++) {
    final a = res.last, b = dedup[i], c = dedup[i + 1];
    final cross =
        (b.dx - a.dx) * (c.dy - a.dy) - (b.dy - a.dy) * (c.dx - a.dx);
    if (cross.abs() < 0.01) continue; // collinear → drop the midpoint
    res.add(b);
  }
  res.add(dedup.last);
  return res;
}

/// Squared distance from [p] to the polyline [pts] (for wire hit-testing).
double hwPolylineDistance(List<Offset> pts, Offset p) {
  var best = double.infinity;
  for (var i = 0; i < pts.length - 1; i++) {
    final d = _segDist(pts[i], pts[i + 1], p);
    if (d < best) best = d;
  }
  return best;
}

double _segDist(Offset a, Offset b, Offset p) {
  final ab = b - a;
  final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
  if (len2 == 0) return (p - a).distance;
  var t = ((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / len2;
  t = t.clamp(0.0, 1.0);
  final proj = Offset(a.dx + ab.dx * t, a.dy + ab.dy * t);
  return (p - proj).distance;
}

// ───────────────────────── Component catalog ─────────────────────────

/// Common LED / button colour swatches the UI offers.
const Map<String, int> kHwColorSwatches = {
  'red': 0xFFFF4D4D,
  'green': 0xFF34D399,
  'blue': 0xFF3B82F6,
  'yellow': 0xFFFBBF24,
  'white': 0xFFF1F5F9,
  'orange': 0xFFFB923C,
};

/// Default Arduino blink that lights GPIO/D13 — gives first-time users an
/// immediate, satisfying result the moment they hit Upload.
const String kStarterSketch = '''// Smart Industrial Alert — Hardware Lab
// Blink the on-board / D13 LED. Press "Upload" to run the simulation.
int led = 13;

void setup() {
  pinMode(led, OUTPUT);
  Serial.begin(115200);
  Serial.println("Boot OK");
}

void loop() {
  digitalWrite(led, HIGH);
  Serial.println("LED ON");
  delay(500);
  digitalWrite(led, LOW);
  Serial.println("LED OFF");
  delay(500);
}
''';

List<HwPinDef> _unoPins() {
  // Digital header along the top, analog + power along the bottom.
  final pins = <HwPinDef>[];
  const top = 8.0;
  const bottom = 132.0;
  const startX = 20.0;
  const step = 18.0;
  // D0..D13 across the top (14 pins).
  for (var d = 13; d >= 0; d--) {
    final i = 13 - d;
    pins.add(HwPinDef('D$d', HwPinKind.digital, startX + i * step, top,
        busName: '$d', pwm: d == 3 || d == 5 || d == 6 || d == 9 || d == 10 || d == 11));
  }
  // Power + analog along the bottom.
  final bottomRow = <(String, HwPinKind, String?, bool)>[
    ('VIN', HwPinKind.power, null, false),
    ('5V', HwPinKind.power, null, false),
    ('3V3', HwPinKind.power, null, false),
    ('GND', HwPinKind.ground, null, false),
    ('A0', HwPinKind.analog, '14', true),
    ('A1', HwPinKind.analog, '15', true),
    ('A2', HwPinKind.analog, '16', true),
    ('A3', HwPinKind.analog, '17', true),
    ('A4', HwPinKind.analog, '18', true),
    ('A5', HwPinKind.analog, '19', true),
  ];
  for (var i = 0; i < bottomRow.length; i++) {
    final (n, k, bus, adc) = bottomRow[i];
    pins.add(HwPinDef(n, k, startX + i * step, bottom, busName: bus, adc: adc));
  }
  return pins;
}

List<HwPinDef> _esp32Pins() {
  // Left and right pin rails, 30-pin DevKit subset of the most-used GPIOs.
  final left = <(String, HwPinKind, String?, bool, bool)>[
    ('3V3', HwPinKind.power, null, false, false),
    ('GND', HwPinKind.ground, null, false, false),
    ('GPIO15', HwPinKind.gpio, '15', true, true),
    ('GPIO2', HwPinKind.gpio, '2', true, true),
    ('GPIO4', HwPinKind.gpio, '4', true, true),
    ('GPIO5', HwPinKind.gpio, '5', false, true),
    ('GPIO18', HwPinKind.gpio, '18', false, true),
    ('GPIO19', HwPinKind.gpio, '19', false, true),
    ('GPIO21', HwPinKind.i2cSda, '21', false, true),
    ('GPIO22', HwPinKind.i2cScl, '22', false, true),
    ('GPIO23', HwPinKind.gpio, '23', false, true),
  ];
  final right = <(String, HwPinKind, String?, bool, bool)>[
    ('VIN', HwPinKind.power, null, false, false),
    ('GND2', HwPinKind.ground, null, false, false),
    ('GPIO13', HwPinKind.gpio, '13', true, true),
    ('GPIO12', HwPinKind.gpio, '12', true, true),
    ('GPIO14', HwPinKind.gpio, '14', true, true),
    ('GPIO27', HwPinKind.gpio, '27', true, true),
    ('GPIO26', HwPinKind.gpio, '26', true, true),
    ('GPIO25', HwPinKind.gpio, '25', true, true),
    ('GPIO33', HwPinKind.gpio, '33', true, true),
    ('GPIO32', HwPinKind.gpio, '32', true, true),
    ('GPIO34', HwPinKind.analog, '34', true, false),
  ];
  final pins = <HwPinDef>[];
  const topY = 18.0;
  const step = 17.0;
  for (var i = 0; i < left.length; i++) {
    final (n, k, bus, adc, pwm) = left[i];
    pins.add(HwPinDef(n, k, 6, topY + i * step, busName: bus, adc: adc, pwm: pwm));
  }
  for (var i = 0; i < right.length; i++) {
    final (n, k, bus, adc, pwm) = right[i];
    pins.add(HwPinDef(n, k, 134, topY + i * step,
        busName: bus, adc: adc, pwm: pwm));
  }
  return pins;
}

/// Build a two-rail (left/right) header layout shared by most dev boards.
List<HwPinDef> _dualRail(
  List<(String, HwPinKind, String?, bool, bool)> left,
  List<(String, HwPinKind, String?, bool, bool)> right,
  double width, {
  double topY = 16,
  double step = 15,
}) {
  final pins = <HwPinDef>[];
  for (var i = 0; i < left.length; i++) {
    final (n, k, bus, adc, pwm) = left[i];
    pins.add(HwPinDef(n, k, 6, topY + i * step, busName: bus, adc: adc, pwm: pwm));
  }
  for (var i = 0; i < right.length; i++) {
    final (n, k, bus, adc, pwm) = right[i];
    pins.add(HwPinDef(n, k, width - 6, topY + i * step,
        busName: bus, adc: adc, pwm: pwm));
  }
  return pins;
}

bool _avrPwm(int d) => d == 3 || d == 5 || d == 6 || d == 9 || d == 10 || d == 11;

List<HwPinDef> _nanoPins() {
  final left = <(String, HwPinKind, String?, bool, bool)>[
    ('3V3', HwPinKind.power, null, false, false),
    ('GND', HwPinKind.ground, null, false, false),
    for (var d = 2; d <= 13; d++)
      ('D$d', HwPinKind.digital, '$d', false, _avrPwm(d)),
  ];
  final right = <(String, HwPinKind, String?, bool, bool)>[
    ('5V', HwPinKind.power, null, false, false),
    ('VIN', HwPinKind.power, null, false, false),
    ('GND2', HwPinKind.ground, null, false, false),
    for (var a = 0; a <= 7; a++)
      ('A$a', HwPinKind.analog, '${14 + a}', true, false),
  ];
  return _dualRail(left, right, 110, topY: 16, step: 15);
}

List<HwPinDef> _megaPins() {
  final left = <(String, HwPinKind, String?, bool, bool)>[
    ('5V', HwPinKind.power, null, false, false),
    ('GND', HwPinKind.ground, null, false, false),
    for (var d = 2; d <= 19; d++)
      ('D$d', HwPinKind.digital, '$d', false, d >= 2 && d <= 13),
  ];
  final right = <(String, HwPinKind, String?, bool, bool)>[
    ('VIN', HwPinKind.power, null, false, false),
    ('GND2', HwPinKind.ground, null, false, false),
    ('3V3', HwPinKind.power, null, false, false),
    for (var a = 0; a <= 7; a++)
      ('A$a', HwPinKind.analog, '${54 + a}', true, false),
    ('SDA', HwPinKind.i2cSda, '20', false, false),
    ('SCL', HwPinKind.i2cScl, '21', false, false),
  ];
  return _dualRail(left, right, 150, topY: 16, step: 14);
}

List<HwPinDef> _esp8266Pins() {
  final left = <(String, HwPinKind, String?, bool, bool)>[
    ('3V3', HwPinKind.power, null, false, false),
    ('GND', HwPinKind.ground, null, false, false),
    ('D0/16', HwPinKind.gpio, '16', false, false),
    ('D1/5', HwPinKind.i2cScl, '5', false, true),
    ('D2/4', HwPinKind.i2cSda, '4', false, true),
    ('D3/0', HwPinKind.gpio, '0', false, true),
    ('D4/2', HwPinKind.gpio, '2', false, true),
  ];
  final right = <(String, HwPinKind, String?, bool, bool)>[
    ('VIN', HwPinKind.power, null, false, false),
    ('GND2', HwPinKind.ground, null, false, false),
    ('D5/14', HwPinKind.gpio, '14', false, true),
    ('D6/12', HwPinKind.gpio, '12', false, true),
    ('D7/13', HwPinKind.gpio, '13', false, true),
    ('D8/15', HwPinKind.gpio, '15', false, true),
    ('A0', HwPinKind.analog, 'A0', true, false),
  ];
  return _dualRail(left, right, 130, topY: 18, step: 17);
}

List<HwPinDef> _esp32c3Pins() {
  final left = <(String, HwPinKind, String?, bool, bool)>[
    ('5V', HwPinKind.power, null, false, false),
    ('GND', HwPinKind.ground, null, false, false),
    ('GPIO0', HwPinKind.gpio, '0', true, true),
    ('GPIO1', HwPinKind.gpio, '1', true, true),
    ('GPIO2', HwPinKind.gpio, '2', true, true),
    ('GPIO3', HwPinKind.gpio, '3', true, true),
    ('GPIO4', HwPinKind.gpio, '4', true, true),
  ];
  final right = <(String, HwPinKind, String?, bool, bool)>[
    ('3V3', HwPinKind.power, null, false, false),
    ('GND2', HwPinKind.ground, null, false, false),
    ('GPIO5', HwPinKind.gpio, '5', true, true),
    ('GPIO6', HwPinKind.gpio, '6', false, true),
    ('GPIO7', HwPinKind.gpio, '7', false, true),
    ('GPIO8', HwPinKind.i2cSda, '8', false, true),
    ('GPIO9', HwPinKind.i2cScl, '9', false, true),
  ];
  return _dualRail(left, right, 112, topY: 18, step: 17);
}

List<HwPinDef> _picoPins() {
  final left = <(String, HwPinKind, String?, bool, bool)>[
    ('3V3', HwPinKind.power, null, false, false),
    ('GND', HwPinKind.ground, null, false, false),
    for (var g = 0; g <= 15; g++)
      (
        'GP$g',
        g == 4 ? HwPinKind.i2cSda : (g == 5 ? HwPinKind.i2cScl : HwPinKind.gpio),
        '$g',
        false,
        true
      ),
  ];
  final right = <(String, HwPinKind, String?, bool, bool)>[
    ('VBUS', HwPinKind.power, null, false, false),
    ('VSYS', HwPinKind.power, null, false, false),
    ('GND2', HwPinKind.ground, null, false, false),
    for (var g = 16; g <= 22; g++)
      ('GP$g', HwPinKind.gpio, '$g', false, true),
    ('GP26', HwPinKind.analog, '26', true, false),
    ('GP27', HwPinKind.analog, '27', true, false),
    ('GP28', HwPinKind.analog, '28', true, false),
  ];
  return _dualRail(left, right, 122, topY: 16, step: 14);
}

/// The full catalog, keyed by type id.
final Map<String, HwComponentDef> kHwCatalog = {
  'esp32': HwComponentDef(
    type: 'esp32',
    name: 'ESP32 DevKit V1',
    shortName: 'ESP32',
    category: HwCategory.boards,
    width: 140,
    height: 220,
    accent: const Color(0xFF22D3EE),
    isController: true,
    blurb: 'WiFi/BLE microcontroller. Programmable, talks to Firebase.',
    pins: _esp32Pins(),
  ),
  'arduino-uno': HwComponentDef(
    type: 'arduino-uno',
    name: 'Arduino UNO R3',
    shortName: 'UNO',
    category: HwCategory.boards,
    width: 290,
    height: 150,
    accent: const Color(0xFF2DD4BF),
    isController: true,
    blurb: 'ATmega328P classic. 14 digital + 6 analog pins.',
    pins: _unoPins(),
  ),
  'arduino-nano': HwComponentDef(
    type: 'arduino-nano',
    name: 'Arduino Nano',
    shortName: 'NANO',
    category: HwCategory.boards,
    width: 110,
    height: 232,
    accent: const Color(0xFF2DD4BF),
    isController: true,
    blurb: 'Breadboard-friendly ATmega328. Same pins as the UNO.',
    pins: _nanoPins(),
  ),
  'arduino-mega': HwComponentDef(
    type: 'arduino-mega',
    name: 'Arduino Mega 2560',
    shortName: 'MEGA',
    category: HwCategory.boards,
    width: 150,
    height: 324,
    accent: const Color(0xFF14B8A6),
    isController: true,
    blurb: 'ATmega2560. 54 digital + 16 analog pins for big builds.',
    pins: _megaPins(),
  ),
  'esp8266': HwComponentDef(
    type: 'esp8266',
    name: 'ESP8266 NodeMCU',
    shortName: 'ESP8266',
    category: HwCategory.boards,
    width: 130,
    height: 200,
    accent: const Color(0xFF38BDF8),
    isController: true,
    blurb: 'WiFi MCU. D1..D8 map to GPIOs. One analog input (A0).',
    pins: _esp8266Pins(),
  ),
  'esp32c3': HwComponentDef(
    type: 'esp32c3',
    name: 'ESP32-C3 Super Mini',
    shortName: 'C3',
    category: HwCategory.boards,
    width: 112,
    height: 190,
    accent: const Color(0xFF22D3EE),
    isController: true,
    blurb: 'RISC-V WiFi/BLE MCU. Compact, talks to Firebase.',
    pins: _esp32c3Pins(),
  ),
  'pico': HwComponentDef(
    type: 'pico',
    name: 'Raspberry Pi Pico',
    shortName: 'PICO',
    category: HwCategory.boards,
    width: 122,
    height: 286,
    accent: const Color(0xFF8B5CF6),
    isController: true,
    blurb: 'RP2040 dual-core. GP0..GP28, 3 ADC channels.',
    pins: _picoPins(),
  ),
  'led': const HwComponentDef(
    type: 'led',
    name: 'LED (5mm)',
    shortName: 'LED',
    category: HwCategory.output,
    width: 44,
    height: 64,
    accent: Color(0xFFFF4D4D),
    blurb: 'Light emitting diode. Anode (+) to a driven pin via a resistor.',
    defaults: {'color': 'red'},
    pins: [
      HwPinDef('A', HwPinKind.anode, 14, 60),
      HwPinDef('K', HwPinKind.cathode, 30, 60),
    ],
  ),
  'rgb-led': const HwComponentDef(
    type: 'rgb-led',
    name: 'RGB LED',
    shortName: 'RGB',
    category: HwCategory.output,
    width: 60,
    height: 70,
    accent: Color(0xFFA78BFA),
    blurb: 'Common-cathode RGB. Drive R/G/B legs with PWM.',
    pins: [
      HwPinDef('R', HwPinKind.anode, 10, 66),
      HwPinDef('COM', HwPinKind.cathode, 26, 66),
      HwPinDef('G', HwPinKind.anode, 42, 66),
      HwPinDef('B', HwPinKind.anode, 56, 66),
    ],
  ),
  'button': const HwComponentDef(
    type: 'button',
    name: 'Push Button',
    shortName: 'BTN',
    category: HwCategory.input,
    width: 72,
    height: 72,
    accent: Color(0xFFFBBF24),
    blurb: 'Momentary tactile switch. Closes its two terminals while pressed.',
    defaults: {'color': 'red', 'pressed': false},
    pins: [
      HwPinDef('1', HwPinKind.passive, 6, 36),
      HwPinDef('2', HwPinKind.passive, 66, 36),
    ],
  ),
  'potentiometer': const HwComponentDef(
    type: 'potentiometer',
    name: 'Potentiometer 10k',
    shortName: 'POT',
    category: HwCategory.input,
    width: 70,
    height: 78,
    accent: Color(0xFF38BDF8),
    blurb: 'Variable divider. Wiper voltage feeds analogRead().',
    defaults: {'value': 0.5},
    pins: [
      HwPinDef('VCC', HwPinKind.power, 10, 74),
      HwPinDef('WIPER', HwPinKind.signal, 35, 74),
      HwPinDef('GND', HwPinKind.ground, 60, 74),
    ],
  ),
  'lcd1602': const HwComponentDef(
    type: 'lcd1602',
    name: 'LCD 16×2 (I²C)',
    shortName: 'LCD',
    category: HwCategory.output,
    width: 200,
    height: 96,
    accent: Color(0xFF34D399),
    blurb: '16×2 character display over I²C (SDA/SCL). 0x27 default.',
    defaults: {'addr': '0x27'},
    pins: [
      HwPinDef('GND', HwPinKind.ground, 60, 92),
      HwPinDef('VCC', HwPinKind.power, 90, 92),
      HwPinDef('SDA', HwPinKind.i2cSda, 120, 92),
      HwPinDef('SCL', HwPinKind.i2cScl, 150, 92),
    ],
  ),
  'buzzer': const HwComponentDef(
    type: 'buzzer',
    name: 'Piezo Buzzer',
    shortName: 'BUZ',
    category: HwCategory.output,
    width: 60,
    height: 64,
    accent: Color(0xFFF472B6),
    blurb: 'Active buzzer. Sounds while its + pin is driven HIGH.',
    pins: [
      HwPinDef('+', HwPinKind.anode, 20, 60),
      HwPinDef('-', HwPinKind.ground, 40, 60),
    ],
  ),
  'servo': const HwComponentDef(
    type: 'servo',
    name: 'Micro Servo SG90',
    shortName: 'SERVO',
    category: HwCategory.output,
    width: 84,
    height: 70,
    accent: Color(0xFFFB923C),
    blurb: 'PWM hobby servo, 0–180°. Signal on SIG, powered from 5V.',
    defaults: {'angle': 0},
    pins: [
      HwPinDef('VCC', HwPinKind.power, 12, 66),
      HwPinDef('GND', HwPinKind.ground, 30, 66),
      HwPinDef('SIG', HwPinKind.signal, 48, 66),
    ],
  ),
  'temp-sensor': const HwComponentDef(
    type: 'temp-sensor',
    name: 'Heat / Temp Sensor',
    shortName: 'TEMP',
    category: HwCategory.sensors,
    width: 78,
    height: 84,
    accent: Color(0xFFFB7185),
    blurb: 'Analog temperature probe (LM35-class). °C on OUT → analogRead.',
    defaults: {'tempC': 25.0},
    pins: [
      HwPinDef('VCC', HwPinKind.power, 14, 80),
      HwPinDef('OUT', HwPinKind.signal, 39, 80),
      HwPinDef('GND', HwPinKind.ground, 64, 80),
    ],
  ),
  'vibration-sensor': const HwComponentDef(
    type: 'vibration-sensor',
    name: 'Vibration Sensor SW-420',
    shortName: 'VIB',
    category: HwCategory.sensors,
    width: 86,
    height: 84,
    accent: Color(0xFFFACC15),
    blurb: 'Digital vibration switch. DO goes HIGH when shaking.',
    defaults: {'vibrating': false},
    pins: [
      HwPinDef('VCC', HwPinKind.power, 16, 80),
      HwPinDef('GND', HwPinKind.ground, 43, 80),
      HwPinDef('DO', HwPinKind.signal, 70, 80),
    ],
  ),
  'pir-sensor': const HwComponentDef(
    type: 'pir-sensor',
    name: 'PIR Motion Sensor',
    shortName: 'PIR',
    category: HwCategory.sensors,
    width: 84,
    height: 84,
    accent: Color(0xFF818CF8),
    blurb: 'Passive IR motion detector. OUT HIGH on motion.',
    defaults: {'motion': false},
    pins: [
      HwPinDef('VCC', HwPinKind.power, 14, 80),
      HwPinDef('OUT', HwPinKind.signal, 42, 80),
      HwPinDef('GND', HwPinKind.ground, 70, 80),
    ],
  ),
  'resistor': const HwComponentDef(
    type: 'resistor',
    name: 'Resistor',
    shortName: 'R',
    category: HwCategory.passive,
    width: 84,
    height: 28,
    accent: Color(0xFFE5C07B),
    blurb: 'Current-limiting resistor. 220Ω in series with each LED.',
    defaults: {'ohms': 220},
    pins: [
      HwPinDef('a', HwPinKind.passive, 4, 14),
      HwPinDef('b', HwPinKind.passive, 80, 14),
    ],
  ),
  'power-5v': const HwComponentDef(
    type: 'power-5v',
    name: 'Power Supply',
    shortName: 'PWR',
    category: HwCategory.power,
    width: 78,
    height: 80,
    accent: Color(0xFF34D399),
    blurb: 'Bench supply rails: 5V, 3V3 and GND.',
    pins: [
      HwPinDef('5V', HwPinKind.power, 14, 76),
      HwPinDef('3V3', HwPinKind.power, 39, 76),
      HwPinDef('GND', HwPinKind.ground, 64, 76),
    ],
  ),
  'gnd': const HwComponentDef(
    type: 'gnd',
    name: 'Ground (GND)',
    shortName: 'GND',
    category: HwCategory.power,
    width: 46,
    height: 50,
    accent: Color(0xFF94A3B8),
    blurb: 'Common 0V reference. Every circuit returns here.',
    pins: [
      HwPinDef('GND', HwPinKind.ground, 23, 6),
    ],
  ),
  'vcc': const HwComponentDef(
    type: 'vcc',
    name: 'VCC Rail',
    shortName: 'VCC',
    category: HwCategory.power,
    width: 46,
    height: 50,
    accent: Color(0xFFEF4444),
    blurb: 'Positive supply rail. Toggle 5V / 3V3 in the inspector.',
    defaults: {'volts': 5.0},
    pins: [
      HwPinDef('VCC', HwPinKind.power, 23, 44),
    ],
  ),
};

/// Pretty controller label for binding UI.
String hwControllerLabel(String type) => switch (type) {
      'esp32' => 'ESP32 DevKit',
      'esp32c3' => 'ESP32-C3',
      'esp8266' => 'ESP8266 NodeMCU',
      'arduino-uno' => 'Arduino UNO',
      'arduino-nano' => 'Arduino Nano',
      'arduino-mega' => 'Arduino Mega 2560',
      'pico' => 'Raspberry Pi Pico',
      _ => type,
    };

/// Every programmable controller in the catalog, for the binding picker.
List<HwComponentDef> hwControllers() =>
    kHwCatalog.values.where((d) => d.isController).toList(growable: false);
