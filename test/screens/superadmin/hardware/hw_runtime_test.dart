import 'package:alertsysapp/screens/superadmin/hardware/hw_models.dart';
import 'package:alertsysapp/screens/superadmin/hardware/hw_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ArduinoRuntime.compile', () {
    test('compiles the starter sketch', () {
      final runtime = ArduinoRuntime(_NoopBridge());

      runtime.compile(kStarterSketch);

      expect(runtime.lint(), isEmpty);
    });

    test('throws instead of hanging on an unmatched top-level brace', () {
      final runtime = ArduinoRuntime(_NoopBridge());

      expect(
        () => runtime.compile('void setup() {}\n}\nvoid loop() {}'),
        throwsA(
          isA<HwSimException>().having(
            (e) => e.message,
            'message',
            contains("unexpected '}'"),
          ),
        ),
      );
    });
  });
}

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
