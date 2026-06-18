import 'package:flutter/material.dart';

import 'hardware/hardware_lab.dart';

/// SuperAdmin tab: the Hardware Lab.
///
/// A Proteus/Wokwi-class IoT design + simulation bench for the hardware/IoT
/// engineering team: drag-and-drop electronics design (ESP32, Arduino UNO,
/// sensors, LEDs, buttons, LCD, …), a real circuit simulator, an Arduino IDE
/// with AI code generation, a live ESP32→Firebase connectivity tester, and the
/// factory-wide machinery binding map. Implemented under [hardware/].
class HardwareTab extends StatelessWidget {
  const HardwareTab({super.key});

  @override
  Widget build(BuildContext context) => const HardwareLab();
}
