import 'package:alertsysapp/models/alert_type.dart';
import 'package:alertsysapp/services/alert_type_registry.dart';
import 'package:alertsysapp/services/forecast/alert_record_parser.dart';
import 'package:alertsysapp/theme.dart';
import 'package:alertsysapp/utils/alert_meta.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const t = AppTheme(isDark: false);

  tearDown(() => AlertTypeRegistry.instance.debugReset());

  group('AlertTypeDef', () {
    test('fromMap/toMap round-trip', () {
      const def = AlertTypeDef(
        code: 'overheating',
        label: 'Overheating',
        colorHex: '#EA580C',
        icon: 'thermostat',
        synonyms: ['overheat', 'hot'],
        severityDefault: 'critical',
        order: 3,
      );
      final round = AlertTypeDef.fromMap(def.toMap())!;
      expect(round.code, 'overheating');
      expect(round.label, 'Overheating');
      expect(round.colorHex, '#EA580C');
      expect(round.icon, 'thermostat');
      expect(round.synonyms, ['overheat', 'hot']);
      expect(round.criticalByDefault, isTrue);
      expect(round.order, 3);
    });

    test('parseHexColor handles #RRGGBB and #AARRGGBB and bad input', () {
      expect(parseHexColor('#FF0000'), const Color(0xFFFF0000));
      expect(parseHexColor('00FF00'), const Color(0xFF00FF00));
      expect(parseHexColor('#8000FF00'), const Color(0x8000FF00));
      expect(parseHexColor('nonsense'), const Color(0xFF6B7280));
    });

    test('alertTypeIcon falls back for unknown keys', () {
      expect(alertTypeIcon('thermostat'), Icons.thermostat_outlined);
      expect(alertTypeIcon('does-not-exist'), Icons.notifications_outlined);
    });
  });

  group('AlertTypeRegistry defaults', () {
    test('serves the historical standard set before any remote load', () {
      expect(AlertTypeRegistry.instance.codes, kDefaultAlertTypeCodes);
      expect(AlertTypeRegistry.instance.byCode('qualite')?.label, 'Quality');
      expect(AlertTypeRegistry.instance.byCode('nope'), isNull);
      expect(allAlertTypeCodes(), kDefaultAlertTypeCodes);
    });
  });

  group('AlertTypeRegistry custom set', () {
    setUp(() {
      AlertTypeRegistry.instance.debugSetTypes(const [
        AlertTypeDef(
          code: 'overheating',
          label: 'Overheating',
          colorHex: '#EA580C',
          icon: 'thermostat',
          synonyms: ['overheat', 'temperature'],
          order: 0,
        ),
        AlertTypeDef(
          code: 'vibration',
          label: 'Vibration',
          colorHex: '#7C3AED',
          icon: 'sensors',
          synonyms: ['vibrat', 'shake'],
          order: 1,
        ),
      ]);
    });

    test('drives the active code list and pickers', () {
      expect(allAlertTypeCodes(), ['overheating', 'vibration']);
    });

    test('typeMeta uses the configured label/icon/color for known codes', () {
      final m = typeMeta('overheating', t);
      expect(m.label, 'Overheating');
      expect(m.icon, Icons.thermostat_outlined);
      expect(m.color, parseHexColor('#EA580C'));
    });

    test('typeMeta degrades gracefully for legacy/unknown codes', () {
      final m = typeMeta('qualite', t); // no longer in the registry
      expect(m.label, 'qualite');
      expect(m.icon, Icons.notifications_outlined);
    });

    test('parser normalizeType maps onto the custom synonyms', () {
      final defs = AlertTypeRegistry.instance.types;
      expect(AlertRecordParser.normalizeType('Overheat detected', types: defs),
          'overheating');
      expect(AlertRecordParser.normalizeType('bearing vibration', types: defs),
          'vibration');
      // Unrecognized free text keeps a sanitized bucket.
      expect(AlertRecordParser.normalizeType('Power loss', types: defs),
          'power_loss');
    });
  });
}
