import 'dart:math' as math;

/// Data layer for the SuperAdmin Hardware Lab's Factory Machinery Map: which
/// controller + sensors/actuators are bound to which real factory machine.

/// Static definition of a controller board offered in the binding picker.
class HwControllerDef {
  final String type;
  final String name;

  const HwControllerDef({required this.type, required this.name});
}

/// Every programmable controller board the binding picker offers.
const List<HwControllerDef> kHwControllers = [
  HwControllerDef(type: 'esp32', name: 'ESP32 DevKit V1'),
  HwControllerDef(type: 'esp32c3', name: 'ESP32-C3 Super Mini'),
  HwControllerDef(type: 'esp8266', name: 'ESP8266 NodeMCU'),
  HwControllerDef(type: 'arduino-uno', name: 'Arduino UNO R3'),
  HwControllerDef(type: 'arduino-nano', name: 'Arduino Nano'),
  HwControllerDef(type: 'arduino-mega', name: 'Arduino Mega 2560'),
  HwControllerDef(type: 'pico', name: 'Raspberry Pi Pico'),
];

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

/// Every programmable controller board, for the binding picker.
List<HwControllerDef> hwControllers() => kHwControllers;

/// Binds a controller to a real factory machine for the factory machinery map.
class HwDeviceBinding {
  String id;
  String factoryId;
  String machineLabel; // e.g. MACH-001
  String conveyor; // e.g. Conveyor 1
  String controllerType; // esp32 / arduino-uno
  List<String> peripherals; // human labels: "Heat sensor", "4 colored buttons"
  String status; // designed / wired / verified / live
  int updatedAtMs;

  HwDeviceBinding({
    required this.id,
    this.factoryId = '',
    this.machineLabel = '',
    this.conveyor = '',
    this.controllerType = 'esp32',
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
