import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/services/notifications/local_notification_timezone.dart';

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
