import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../theme.dart';

/// Friendly display name for an alert's [source] value.
///
/// The ingest worker stamps `scada:<kind>` (e.g. `scada:modbus`) and the app
/// stamps `Manual`. This strips the transport prefix and maps well-known
/// connector kinds to their proper product names (left untranslated, like
/// other brand/board names in the app).
String alertSourceDisplay(String raw) {
  final lower = raw.trim().toLowerCase();
  final clean = lower.startsWith('scada:') ? lower.substring(6) : lower;
  const map = {
    'manual': 'Manual',
    'modbus': 'Modbus',
    'opcua': 'OPC-UA',
    'opc-ua': 'OPC-UA',
    'mqtt': 'MQTT',
    'rest': 'REST',
    'historian_pi': 'PI Historian',
    'historian_ignition': 'Ignition',
    'microcontroller': 'Microcontroller',
    'webhook': 'Webhook',
    'plc': 'PLC',
    'scada': 'SCADA',
    'custom': 'Custom',
  };
  final mapped = map[clean] ?? map[lower];
  if (mapped != null) return mapped;
  // Title-case an unknown source (e.g. a connector name).
  return clean
      .split(RegExp(r'[_\s-]+'))
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');
}

/// True for the app's "manually raised" marker — those get no badge.
bool _isManualSource(String s) => s.trim().toLowerCase() == 'manual';

/// Compact "from {source}" chip shown on alert cards and the detail screen for
/// alerts that arrived from an external system (SCADA / PLC / Historian / MQTT
/// / a microcontroller). Manual and legacy (unset) alerts render nothing.
class AlertSourceBadge extends StatelessWidget {
  final String? source;

  /// A hair smaller/tighter variant for dense list cards.
  final bool dense;

  const AlertSourceBadge({super.key, required this.source, this.dense = false});

  @override
  Widget build(BuildContext context) {
    final s = (source ?? '').trim();
    if (s.isEmpty || _isManualSource(s)) return const SizedBox.shrink();
    final t = context.appTheme;
    final color = t.blue;
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: dense ? 6 : 8, vertical: dense ? 2 : 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.router_outlined, size: dense ? 11 : 13, color: color),
          const SizedBox(width: 4),
          Text(
            context.tr('from {source}', {'source': alertSourceDisplay(s)}),
            style: TextStyle(
              fontSize: dense ? 10 : 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
