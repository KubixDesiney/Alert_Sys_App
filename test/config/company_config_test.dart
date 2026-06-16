import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alertsysapp/config/company_config.dart';

void main() {
  group('CompanyConfig defaults (demo build)', () {
    test('brand color falls back to the default blue', () {
      expect(CompanyConfig.brandColorValue, 0xFF1565C0);
      expect(CompanyConfig.brandColor, const Color(0xFF1565C0));
    });
    test('optional features are off by default', () {
      expect(CompanyConfig.logoUrl, '');
      expect(CompanyConfig.mfaRequired, isFalse);
      expect(CompanyConfig.ssoEnabled, isFalse);
      expect(CompanyConfig.isConfigured, isFalse);
    });
  });

  group('CompanyConfig.verifyFirebaseProject', () {
    test('passes (null) when no expectation is declared', () {
      // Demo build has no COMPANY_FIREBASE_PROJECT, so any project is accepted.
      expect(CompanyConfig.verifyFirebaseProject('anything'), isNull);
      expect(CompanyConfig.verifyFirebaseProject(''), isNull);
    });
  });
}
