import 'package:alertsysapp/services/offline_account_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('offline account cache accepts only routable roles', () {
    expect(OfflineAccountCache.isValidRole('admin'), isTrue);
    expect(OfflineAccountCache.isValidRole('supervisor'), isTrue);
    expect(OfflineAccountCache.isValidRole('operator'), isFalse);
    expect(OfflineAccountCache.isValidRole(null), isFalse);
  });
}
