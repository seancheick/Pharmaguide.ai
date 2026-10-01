import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/services/scan_limit_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _today() => DateTime.now().toUtc().toIso8601String().split('T').first;

Future<ScanLimitService> _guestAtLimit() async {
  SharedPreferences.setMockInitialValues({
    'guest_daily_scan_count': 3,
    'guest_daily_scan_date': _today(),
  });
  return ScanLimitService(
    prefs: await SharedPreferences.getInstance(),
    isSignedIn: false,
  );
}

void main() {
  // A guest out of scans must still see a safety-critical result: the cap
  // may gate convenience, never a recall or a banned-ingredient finding.
  test(
    'a safety-critical result is admitted and not charged at the cap',
    () async {
      final service = await _guestAtLimit();

      expect(service.canScan, isFalse);
      expect(await service.admitResult(safetyCritical: true), isTrue);
      expect(service.guestScansUsed, 3);
    },
  );

  test('an ordinary result is refused at the cap', () async {
    final service = await _guestAtLimit();

    expect(await service.admitResult(safetyCritical: false), isFalse);
    expect(service.guestScansUsed, 3);
  });

  test('an ordinary result below the cap is charged once', () async {
    SharedPreferences.setMockInitialValues({});
    final service = ScanLimitService(
      prefs: await SharedPreferences.getInstance(),
      isSignedIn: false,
    );

    expect(await service.admitResult(safetyCritical: false), isTrue);
    expect(service.guestScansUsed, 1);
    expect(await service.admitResult(safetyCritical: true), isTrue);
    expect(service.guestScansUsed, 1);
  });
}
