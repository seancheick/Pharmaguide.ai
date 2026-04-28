import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/utils/relative_time.dart';

void main() {
  group('relativeTime', () {
    final now = DateTime(2026, 4, 28, 12, 0, 0);

    test('returns "Just now" for under 60 seconds', () {
      expect(
        relativeTime(now.subtract(const Duration(seconds: 30)), now: now),
        'Just now',
      );
    });

    test('returns "Just now" for exactly 0 seconds', () {
      expect(relativeTime(now, now: now), 'Just now');
    });

    test('returns "1m ago" at the 1-minute boundary', () {
      expect(
        relativeTime(now.subtract(const Duration(minutes: 1)), now: now),
        '1m ago',
      );
    });

    test('returns "59m ago" at the upper minute boundary', () {
      expect(
        relativeTime(now.subtract(const Duration(minutes: 59)), now: now),
        '59m ago',
      );
    });

    test('returns "1h ago" at the 1-hour boundary', () {
      expect(
        relativeTime(now.subtract(const Duration(hours: 1)), now: now),
        '1h ago',
      );
    });

    test('returns "23h ago" at the upper hour boundary', () {
      expect(
        relativeTime(now.subtract(const Duration(hours: 23)), now: now),
        '23h ago',
      );
    });

    test('returns "Yesterday" for exactly 1 day', () {
      expect(
        relativeTime(now.subtract(const Duration(days: 1)), now: now),
        'Yesterday',
      );
    });

    test('returns "2d ago" for 2 days', () {
      expect(
        relativeTime(now.subtract(const Duration(days: 2)), now: now),
        '2d ago',
      );
    });

    test('returns "30d ago" for older entries (no ISO fallback)', () {
      expect(
        relativeTime(now.subtract(const Duration(days: 30)), now: now),
        '30d ago',
      );
    });
  });
}
