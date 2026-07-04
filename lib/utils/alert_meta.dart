import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../models/alert_type.dart';
import '../services/alert_type_registry.dart';
import '../theme.dart';

/// Visual metadata for an alert type or status.
///
/// Single source of truth used by every screen that renders alert chips,
/// pills, icons or coloured stripes (alert_scan_screen, alert_tree_visualization,
/// dashboard_screen, etc.). Alert-type appearance is driven by the
/// tenant-configurable [AlertTypeRegistry]; unknown/legacy codes degrade to a
/// neutral chip showing the raw string.
class AlertMeta {
  final String label;
  final IconData icon;
  final Color color;
  final Color bg;
  const AlertMeta({
    required this.label,
    required this.icon,
    required this.color,
    required this.bg,
  });
}

/// Visual metadata for an alert [type], resolved through the configurable
/// [AlertTypeRegistry]. [context] is optional so existing call sites keep
/// compiling without localization; pass it whenever a BuildContext is
/// available so the label renders in the active app language.
///
/// The registry serves the default seed synchronously (identical to the
/// historical standard set) before its stream resolves, so this never depends
/// on a live Firebase connection. Codes absent from the registry — legacy
/// alerts written before a type was removed, or foreign SCADA type strings —
/// render as a neutral chip with the raw code, never crashing.
AlertMeta typeMeta(String type, AppTheme t, [BuildContext? context]) {
  String tr(String s) => context == null ? s : context.tr(s);
  final def = AlertTypeRegistry.instance.byCode(type);
  if (def != null) {
    final color = def.color;
    return AlertMeta(
      label: tr(def.label),
      icon: alertTypeIcon(def.icon),
      color: color,
      bg: color.withValues(alpha: t.isDark ? 0.22 : 0.12),
    );
  }
  return AlertMeta(
    label: type,
    icon: Icons.notifications_outlined,
    color: t.muted,
    bg: t.border,
  );
}

AlertMeta statusMeta(String status, AppTheme t, [BuildContext? context]) {
  String tr(String s) => context == null ? s : context.tr(s);
  switch (status) {
    case 'disponible':
      return AlertMeta(
        label: tr('PENDING'),
        icon: Icons.notifications_active_outlined,
        color: t.red,
        bg: t.redLt,
      );
    case 'en_cours':
      return AlertMeta(
        label: tr('CLAIMED'),
        icon: Icons.autorenew,
        color: t.yellow,
        bg: t.yellowLt,
      );
    case 'validee':
      return AlertMeta(
        label: tr('RESOLVED'),
        icon: Icons.verified,
        color: t.green,
        bg: t.greenLt,
      );
    default:
      return AlertMeta(
        label: status.toUpperCase(),
        icon: Icons.help_outline,
        color: t.muted,
        bg: t.border,
      );
  }
}

/// Returns true for any status that should count as "active" (not yet
/// resolved).
bool isActiveStatus(String status) =>
    status == 'disponible' || status == 'en_cours';

/// Active alert-type codes from the configurable registry — used by filter
/// pickers and type dropdowns. Falls back to the default seed synchronously.
List<String> allAlertTypeCodes() => AlertTypeRegistry.instance.codes;

/// Active alert types (full defs) in registry order.
List<AlertTypeDef> allAlertTypes() => AlertTypeRegistry.instance.types;

const List<String> kAllAlertStatuses = [
  'disponible',
  'en_cours',
  'validee',
];
