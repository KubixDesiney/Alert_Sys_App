import 'dart:async';
import 'dart:math' as math;

import 'package:alertsysapp/screens/superadmin/hardware/hw_models.dart';
import 'package:flutter/foundation.dart';

/// Hardware Lab runtime: net extraction, a logic-level circuit solver, and a
/// genuine async Arduino-C interpreter that runs the user's sketch against the
/// virtual board. Pure Dart, no Flutter widgets - the canvas/painters observe
/// the [HwSimulator] (a [ChangeNotifier]).

part 'hw_runtime_netlist.dart';
part 'hw_runtime_lexer.dart';
part 'hw_runtime_ast.dart';
part 'hw_runtime_parser.dart';
part 'hw_runtime_interpreter.dart';
part 'hw_runtime_simulator.dart';
