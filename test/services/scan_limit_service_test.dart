import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/services/scan_limit_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ScanLimitService', () {
    test('guest scans are capped at 10 lifetime scans', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = ScanLimitService(prefs: prefs, isSignedIn: false);

      for (var i = 0; i < 10; i++) {
        expect(await service.recordScan(), isTrue);
      }

      expect(service.canScan, isFalse);
      expect(await service.recordScan(), isFalse);
      expect(service.scansRemaining, 0);
    });

    test('provider constructs from SharedPreferences and auth state', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final service = await container.read(scanLimitServiceProvider.future);

      expect(service.scanLimit, 10);
      expect(service.scansRemaining, 10);
    });
  });
}
