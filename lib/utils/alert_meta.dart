import 'package:flutter/material.dart';

import '../theme.dart';

/// Visual metadata for an alert type or status.
///
/// Single source of truth used by every screen that renders alert chips,
/// pills, icons or coloured stripes (alert_scan_screen, alert_tree_visualization,
/// dashboard_screen, etc.). Add new alert types here, not in screens.
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

AlertMeta typeMeta(String type, AppTheme t) {
  switch (type) {
    case 'qualite':
      return AlertMeta(
        label: 'Quality',
        icon: Icons.fact_check_outlined,
        color: t.red,
        bg: t.redLt,
      );
    case 'maintenance':
      return AlertMeta(
        label: 'Maintenance',
        icon: Icons.build_outlined,
        color: t.blue,
        bg: t.blueLt,
      );
    case 'defaut_produit':
      return AlertMeta(
        label: 'Damaged Product',
        icon: Icons.report_problem_outlined,
        color: t.green,
        bg: t.greenLt,
      );
    case 'manque_ressource':
      return AlertMeta(
        label: 'Resource Shortage',
        icon: Icons.inventory_2_outlined,
        color: t.orange,
        bg: t.orangeLt,
      );
    default:
      return AlertMeta(
        label: type,
        icon: Icons.notifications_outlined,
        color: t.muted,
        bg: t.border,
      );
  }
}

AlertMeta statusMeta(String status, AppTheme t) {
  switch (status) {
    case 'disponible':
      return AlertMeta(
        label: 'AVAILABLE',
        icon: Icons.notifications_active_outlined,
        color: t.red,
        bg: t.redLt,
      );
    case 'en_cours':
      return AlertMeta(
        label: 'IN PROGRESS',
        icon: Icons.autorenew,
        color: t.yellow,
        bg: t.yellowLt,
      );
    case 'validee':
      return AlertMeta(
        label: 'RESOLVED',
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

/// Canonical list of known alert types — useful for filter pickers.
const List<String> kAllAlertTypes = [
  'qualite',
  'maintenance',
  'defaut_produit',
  'manque_ressource',
];

const List<String> kAllAlertStatuses = [
  'disponible',
  'en_cours',
  'validee',
];
