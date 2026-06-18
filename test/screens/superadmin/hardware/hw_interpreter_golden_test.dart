import 'package:alertsysapp/screens/superadmin/hardware/hw_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ArduinoRuntime golden programs', () {
    for (final golden in _goldenPrograms) {
      test(golden.name, () async {
        final bridge = _GoldenBridge(analogInputs: golden.analogInputs);
        final runtime = ArduinoRuntime(bridge);

        runtime.compile(golden.sketch);
        expect(runtime.lint(), isEmpty);

        await runtime.runSetup();
        for (var i = 0; i < golden.loopIterations; i++) {
          await runtime.runLoopOnce();
        }

        _expectMapContains(bridge.pinModes, golden.pinModes, 'pin mode');
        _expectMapContains(
          bridge.digitalPins,
          golden.digitalPins,
          'digital pin',
        );
        _expectMapContains(bridge.pwmPins, golden.pwmPins, 'PWM pin');
        expect(bridge.serialText, golden.serialText);
        expect(bridge.lcdLines, golden.lcdLines);
      });
    }
  });
}

void _expectMapContains<K, V>(
  Map<K, V> actual,
  Map<K, V> expected,
  String name,
) {
  for (final entry in expected.entries) {
    expect(
      actual[entry.key],
      entry.value,
      reason: '$name ${entry.key} should be ${entry.value}',
    );
  }
}

final _goldenPrograms = <_GoldenProgram>[
  const _GoldenProgram(
    name: 'setup drives digital pins and writes a Serial banner',
    sketch: '''
void setup() {
  pinMode(13, OUTPUT);
  pinMode(2, OUTPUT);
  digitalWrite(13, HIGH);
  digitalWrite(2, LOW);
  Serial.begin(115200);
  Serial.print("BOOT ");
  Serial.println("MACH-001");
}

void loop() {}
''',
    pinModes: {'13': 1, '2': 1},
    digitalPins: {'13': true, '2': false},
    serialText: 'BOOT MACH-001\n',
  ),
  const _GoldenProgram(
    name: 'loop reads an analog sensor and raises an alarm pin',
    sketch: '''
void setup() {
  pinMode(2, OUTPUT);
}

void loop() {
  int adc = analogRead(A0);
  if (adc > 700) {
    digitalWrite(2, HIGH);
    Serial.println("HOT");
  } else {
    digitalWrite(2, LOW);
    Serial.println("OK");
  }
}
''',
    analogInputs: {'14': 812},
    loopIterations: 1,
    pinModes: {'2': 1},
    digitalPins: {'2': true},
    serialText: 'HOT\n',
  ),
  const _GoldenProgram(
    name: 'analog input maps to PWM output',
    sketch: '''
void setup() {
  pinMode(5, OUTPUT);
}

void loop() {
  int duty = map(analogRead(A1), 0, 1023, 0, 255);
  analogWrite(5, duty);
  Serial.println(duty);
}
''',
    analogInputs: {'15': 512},
    loopIterations: 1,
    pinModes: {'5': 1},
    pwmPins: {'5': 127},
    serialText: '127\n',
  ),
  const _GoldenProgram(
    name: 'LiquidCrystal sketch writes machine status rows',
    sketch: '''
LiquidCrystal_I2C lcd(0x27, 16, 2);

void setup() {
  lcd.init();
  lcd.clear();
  lcd.setCursor(0, 0);
  lcd.print("MACH-042");
  lcd.setCursor(0, 1);
  lcd.print("RUNNING");
}

void loop() {}
''',
    lcdLines: ['MACH-042', 'RUNNING'],
  ),
];

class _GoldenProgram {
  final String name;
  final String sketch;
  final Map<String, int> analogInputs;
  final int loopIterations;
  final Map<String, int> pinModes;
  final Map<String, bool> digitalPins;
  final Map<String, int> pwmPins;
  final String serialText;
  final List<String> lcdLines;

  const _GoldenProgram({
    required this.name,
    required this.sketch,
    this.analogInputs = const {},
    this.loopIterations = 0,
    this.pinModes = const {},
    this.digitalPins = const {},
    this.pwmPins = const {},
    this.serialText = '',
    this.lcdLines = const ['', ''],
  });
}

class _GoldenBridge implements HwSimBridge {
  final Map<String, int> analogInputs;
  final Map<String, int> pinModes = {};
  final Map<String, bool> digitalPins = {};
  final Map<String, int> pwmPins = {};
  final StringBuffer _serial = StringBuffer();
  final List<String> lcdLines = ['', ''];

  int _lcdCol = 0;
  int _lcdRow = 0;

  _GoldenBridge({this.analogInputs = const {}});

  String get serialText => _serial.toString();

  @override
  void analogWrite(String pin, int value) {
    digitalPins.remove(pin);
    pwmPins[pin] = value;
  }

  @override
  int analogRead(String pin) => analogInputs[pin] ?? 0;

  @override
  bool digitalRead(String pin) => digitalPins[pin] ?? false;

  @override
  void digitalWrite(String pin, bool high) {
    pwmPins.remove(pin);
    digitalPins[pin] = high;
  }

  @override
  Future<num> firebaseGet(String path) async => 0;

  @override
  Future<void> firebaseSet(String path, Object? value) async {}

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
        _lcdWrite('${args.isEmpty ? '' : args[0]}');
      default:
        break;
    }
  }

  @override
  void log(String message, {bool error = true}) {}

  @override
  int millisNow() => 0;

  @override
  void noTone(String pin) {}

  @override
  void pinMode(String pin, int mode) {
    pinModes[pin] = mode;
  }

  @override
  void serialOut(String text) {
    _serial.write(text);
  }

  @override
  void servoWrite(String instance, int angle) {}

  @override
  void tone(String pin, num freq) {}

  int _intOf(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }

  void _lcdWrite(String text) {
    final row = _lcdRow.clamp(0, 1);
    final line = lcdLines[row].padRight(16);
    final chars = line.split('');
    for (var i = 0; i < text.length; i++) {
      final col = _lcdCol + i;
      if (col >= 0 && col < 16) chars[col] = text[i];
    }
    _lcdCol = (_lcdCol + text.length).clamp(0, 16);
    lcdLines[row] = chars.join().trimRight();
  }
}
