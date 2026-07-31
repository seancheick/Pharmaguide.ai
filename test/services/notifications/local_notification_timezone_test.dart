import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/services/notifications/local_notification_timezone.dart';
import 'package:timezone/timezone.dart' as timezone;

void main() {
  test('resolves a real IANA device timezone', () async {
    final location = await resolveNotificationTimezone(
      readDeviceTimezone: () async => 'America/New_York',
    );

    expect(location.name, 'America/New_York');
  });

  test('falls back to UTC when the platform timezone is unavailable', () async {
    final location = await resolveNotificationTimezone(
      readDeviceTimezone: () async => throw StateError('plugin unavailable'),
    );

    expect(location.name, contains('UTC'));
    expect(location.currentTimeZone.offset, Duration.zero);
  });

  test('next daily reminder keeps its wall-clock hour across DST', () async {
    final location = await resolveNotificationTimezone(
      readDeviceTimezone: () async => 'America/New_York',
    );
    final beforeSpringForward = timezone.TZDateTime(location, 2026, 3, 7, 9);

    final next = nextLocalNotificationTime(
      now: beforeSpringForward,
      minutesAfterMidnight: 8 * 60,
    );

    expect(next.year, 2026);
    expect(next.month, 3);
    expect(next.day, 8);
    expect(next.hour, 8);
    expect(next.minute, 0);
  });

  test('both reminder clients use the single timezone initializer', () {
    for (final path in const [
      'lib/services/history/local_health_reminder_service.dart',
      'lib/features/stack/providers/stack_reminder_providers.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, contains('initializeLocalNotificationTimezone()'));
      expect(source, isNot(contains('initializeTimeZones()')));
    }
  });
}
