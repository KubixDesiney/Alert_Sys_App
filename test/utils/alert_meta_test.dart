import 'package:alertsysapp/theme.dart';
import 'package:alertsysapp/utils/alert_meta.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // AppTheme is a const value object keyed off isDark — no Flutter binding
  // is required to instantiate it for these pure metadata tests.
  const t = AppTheme(isDark: false);

  group('typeMeta', () {
    test('returns Quality label for qualite', () {
      expect(typeMeta('qualite', t).label, 'Quality');
      expect(typeMeta('qualite', t).icon, Icons.fact_check_outlined);
    });

    test('returns Maintenance for maintenance', () {
      expect(typeMeta('maintenance', t).label, 'Maintenance');
    });

    test('returns Damaged Product for defaut_produit', () {
      expect(typeMeta('defaut_produit', t).label, 'Damaged Product');
    });

    test('returns Resource Deficiency for manque_ressource', () {
      expect(typeMeta('manque_ressource', t).label, 'Resource Deficiency');
    });

    test('falls back to type string for unknown types', () {
      final m = typeMeta('newcomer', t);
      expect(m.label, 'newcomer');
      expect(m.icon, Icons.notifications_outlined);
    });
  });

  group('statusMeta', () {
    test('AVAILABLE for disponible', () {
      expect(statusMeta('disponible', t).label, 'AVAILABLE');
    });

    test('IN PROGRESS for en_cours', () {
      expect(statusMeta('en_cours', t).label, 'IN PROGRESS');
    });

    test('RESOLVED for validee', () {
      expect(statusMeta('validee', t).label, 'RESOLVED');
    });

    test('upper-cases unknown status as fallback', () {
      expect(statusMeta('escalated', t).label, 'ESCALATED');
    });
  });

  group('isActiveStatus', () {
    test('true for disponible and en_cours', () {
      expect(isActiveStatus('disponible'), isTrue);
      expect(isActiveStatus('en_cours'), isTrue);
    });

    test('false for validee and unknown', () {
      expect(isActiveStatus('validee'), isFalse);
      expect(isActiveStatus(''), isFalse);
      expect(isActiveStatus('whatever'), isFalse);
    });
  });

  group('canonical lists', () {
    test('kAllAlertTypes contains expected types', () {
      expect(kAllAlertTypes, [
        'qualite',
        'maintenance',
        'defaut_produit',
        'manque_ressource',
      ]);
    });

    test('kAllAlertStatuses contains expected statuses', () {
      expect(kAllAlertStatuses, ['disponible', 'en_cours', 'validee']);
    });
  });
}
