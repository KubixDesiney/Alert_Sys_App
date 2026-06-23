import 'package:flutter/material.dart';

import '../../../l10n/app_strings.dart';
import '../superadmin_theme.dart';
import 'hw_factory_binding.dart';
import 'hw_models.dart';
import 'hw_store.dart';

/// SuperAdmin Hardware Lab — the factory-wide machinery binding map. Binds
/// controllers (ESP32, Arduino, …) and their sensors/actuators to real
/// factory machines picked from live plant inventory.
class HardwareLab extends StatefulWidget {
  const HardwareLab({super.key});

  @override
  State<HardwareLab> createState() => _HardwareLabState();
}

class _HardwareLabState extends State<HardwareLab> {
  final HwLabStore _store = HwLabStore();
  List<HwDeviceBinding> _bindings = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final bindings = await _store.loadBindings();
    if (!mounted) return;
    setState(() {
      _bindings = bindings;
      _loading = false;
    });
  }

  Future<void> _saveBinding(HwDeviceBinding b) async {
    await _store.saveBinding(b);
    final i = _bindings.indexWhere((x) => x.id == b.id);
    setState(() {
      if (i >= 0) {
        _bindings[i] = b;
      } else {
        _bindings = [b, ..._bindings];
      }
    });
  }

  Future<void> _deleteBinding(String id) async {
    await _store.deleteBinding(id);
    setState(() => _bindings.removeWhere((x) => x.id == id));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Sa.cyan, strokeWidth: 2.4),
            const SizedBox(height: 14),
            Text(context.tr('Booting hardware bench…'),
                style: Sa.body(size: 12.5, color: Sa.textDim)),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: HwFactoryBindingView(
        bindings: _bindings,
        onSave: _saveBinding,
        onDelete: _deleteBinding,
      ),
    );
  }
}
