import 'package:flutter/material.dart';

import 'hardware/hardware_lab.dart';

/// SuperAdmin tab: the Hardware Lab.
///
/// The factory-wide machinery binding map — binds controllers (ESP32,
/// Arduino, …) and their sensors/actuators to real factory machines picked
/// from live plant inventory. Implemented under [hardware/].
class HardwareTab extends StatelessWidget {
  const HardwareTab({super.key});

  @override
  Widget build(BuildContext context) => const HardwareLab();
}
