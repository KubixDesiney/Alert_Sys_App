import 'package:alertsysapp/widgets/locator_painter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LocatorNodeBadge', () {
    test('stores key, status, alertNumber and assetLabel', () {
      const badge = LocatorNodeBadge(
        key: 'A|1|2',
        status: LocatorNodeStatus.critical,
        alertNumber: 1025,
        assetLabel: 'M-7',
      );
      expect(badge.key, 'A|1|2');
      expect(badge.status, LocatorNodeStatus.critical);
      expect(badge.alertNumber, 1025);
      expect(badge.assetLabel, 'M-7');
    });

    test('alertNumber and assetLabel are optional', () {
      const badge = LocatorNodeBadge(
        key: 'A|1|2',
        status: LocatorNodeStatus.idle,
      );
      expect(badge.alertNumber, isNull);
      expect(badge.assetLabel, isNull);
    });
  });

  group('LocatorNodeStatus enum', () {
    test('contains all five expected states', () {
      expect(LocatorNodeStatus.values, hasLength(5));
      expect(LocatorNodeStatus.values, containsAll([
        LocatorNodeStatus.idle,
        LocatorNodeStatus.available,
        LocatorNodeStatus.inProgress,
        LocatorNodeStatus.resolved,
        LocatorNodeStatus.critical,
      ]));
    });
  });
}
