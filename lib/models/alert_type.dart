import 'package:flutter/material.dart';

/// A tenant-configurable alert type.
///
/// Each buyer runs a separate single-tenant deployment and can define its own
/// alert-type vocabulary from the SuperAdmin console. An [AlertTypeDef] is the
/// source of truth for how a type is *labelled, coloured, iconed, parsed and
/// defaulted* — the operational DB, every UI surface, and the on-device GBDT
/// forecaster all read the active set through [AlertTypeRegistry].
///
/// The [code] is the stable machine identifier written onto `alerts/{id}/type`
/// and learned by the forecaster; it is **never translated**. [label] is the
/// human string shown in the UI and is localized at render time via
/// `context.tr(def.label)`.
class AlertTypeDef {
  /// Stable identifier (snake_case, lowercase). Written to `alerts/{id}/type`
  /// and used as the forecaster's per-type ensemble key. Never translated.
  final String code;

  /// English display label (localize at render with `context.tr`).
  final String label;

  /// `#RRGGBB` accent colour.
  final String colorHex;

  /// Icon key resolved by [alertTypeIcon].
  final String icon;

  /// Free-form synonyms/substrings used to normalize free-text type values
  /// (uploaded history, SCADA payloads) onto this [code].
  final List<String> synonyms;

  /// `normal` | `critical` — whether new alerts of this type default to
  /// critical.
  final String severityDefault;

  /// Sort order across pickers, filters and the forecaster's per-type layout.
  final int order;

  const AlertTypeDef({
    required this.code,
    required this.label,
    this.colorHex = '#6B7280',
    this.icon = 'notifications',
    this.synonyms = const [],
    this.severityDefault = 'normal',
    this.order = 0,
  });

  bool get criticalByDefault {
    final s = severityDefault.trim().toLowerCase();
    return s == 'critical' || s == 'high' || s == 'haute' || s == 'critique';
  }

  Color get color => parseHexColor(colorHex);

  AlertTypeDef copyWith({
    String? code,
    String? label,
    String? colorHex,
    String? icon,
    List<String>? synonyms,
    String? severityDefault,
    int? order,
  }) =>
      AlertTypeDef(
        code: code ?? this.code,
        label: label ?? this.label,
        colorHex: colorHex ?? this.colorHex,
        icon: icon ?? this.icon,
        synonyms: synonyms ?? this.synonyms,
        severityDefault: severityDefault ?? this.severityDefault,
        order: order ?? this.order,
      );

  Map<String, dynamic> toMap() => {
        'code': code,
        'label': label,
        'color': colorHex,
        'icon': icon,
        'synonyms': synonyms,
        'severityDefault': severityDefault,
        'order': order,
      };

  static AlertTypeDef? fromMap(Object? raw, {String? fallbackCode}) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    final code = (m['code'] ?? fallbackCode ?? '').toString().trim();
    if (code.isEmpty) return null;
    final syn = m['synonyms'];
    return AlertTypeDef(
      code: code,
      label: (m['label'] ?? code).toString(),
      colorHex: (m['color'] ?? '#6B7280').toString(),
      icon: (m['icon'] ?? 'notifications').toString(),
      synonyms: syn is List
          ? syn.map((e) => e.toString().trim().toLowerCase()).where((e) => e.isNotEmpty).toList()
          : const [],
      severityDefault: (m['severityDefault'] ?? 'normal').toString(),
      order: (m['order'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Parses `#RRGGBB` / `#AARRGGBB` (with or without the leading `#`) into a
/// [Color], falling back to a neutral grey.
Color parseHexColor(String hex) {
  var h = hex.trim().replaceAll('#', '');
  if (h.length == 6) h = 'FF$h';
  final v = int.tryParse(h, radix: 16);
  return v == null ? const Color(0xFF6B7280) : Color(v);
}

/// The default seed. **Equal to the historical standard set** so a fresh
/// deployment (empty `app_config/alertTypes`) behaves exactly as before: same
/// codes the forecaster learned, same labels/icons/colours the UI rendered,
/// and synonyms that replicate the previous `normalizeType` substring
/// behaviour so existing history parses identically.
const List<AlertTypeDef> kDefaultAlertTypeDefs = [
  AlertTypeDef(
    code: 'qualite',
    label: 'Quality',
    colorHex: '#DC2626',
    icon: 'fact_check',
    synonyms: ['qual'],
    order: 0,
  ),
  AlertTypeDef(
    code: 'maintenance',
    label: 'Maintenance',
    colorHex: '#2563EB',
    icon: 'build',
    synonyms: ['mainten', 'entretien'],
    order: 1,
  ),
  AlertTypeDef(
    code: 'defaut_produit',
    label: 'Damaged Product',
    colorHex: '#16A34A',
    icon: 'report_problem',
    synonyms: ['defaut', 'defect', 'damag', 'produit', 'product'],
    order: 2,
  ),
  AlertTypeDef(
    code: 'manque_ressource',
    label: 'Resource Deficiency',
    colorHex: '#FBBF24',
    icon: 'inventory_2',
    synonyms: ['ressource', 'resource', 'shortage', 'manque', 'stock'],
    order: 3,
  ),
];

/// Canonical default type codes (order-aligned with [kDefaultAlertTypeDefs]).
/// This is the historical `kForecastAlertTypes` / `kAllAlertTypes` value and is
/// used as the forecaster's default schema when no registry is available.
const List<String> kDefaultAlertTypeCodes = [
  'qualite',
  'maintenance',
  'defaut_produit',
  'manque_ressource',
];

/// Icon palette for alert types. Const [IconData]s keep tree-shaking working.
const Map<String, IconData> kAlertTypeIcons = {
  'fact_check': Icons.fact_check_outlined,
  'build': Icons.build_outlined,
  'report_problem': Icons.report_problem_outlined,
  'inventory_2': Icons.inventory_2_outlined,
  'warning': Icons.warning_amber_outlined,
  'bolt': Icons.bolt_outlined,
  'thermostat': Icons.thermostat_outlined,
  'water_drop': Icons.water_drop_outlined,
  'settings': Icons.settings_outlined,
  'engineering': Icons.engineering_outlined,
  'sensors': Icons.sensors_outlined,
  'power': Icons.power_outlined,
  'gpp_maybe': Icons.gpp_maybe_outlined,
  'science': Icons.science_outlined,
  'construction': Icons.construction_outlined,
  'precision_manufacturing': Icons.precision_manufacturing_outlined,
  'local_fire_department': Icons.local_fire_department_outlined,
  'air': Icons.air_outlined,
  'notifications': Icons.notifications_outlined,
};

/// Resolves an [AlertTypeDef.icon] key to a Material [IconData], with a neutral
/// fallback for unknown keys.
IconData alertTypeIcon(String name) =>
    kAlertTypeIcons[name] ?? Icons.notifications_outlined;

/// Ordered list of selectable icon keys for the SuperAdmin type editor.
const List<String> kAlertTypeIconKeys = [
  'fact_check',
  'build',
  'report_problem',
  'inventory_2',
  'warning',
  'bolt',
  'thermostat',
  'water_drop',
  'settings',
  'engineering',
  'sensors',
  'power',
  'gpp_maybe',
  'science',
  'construction',
  'precision_manufacturing',
  'local_fire_department',
  'air',
  'notifications',
];
