import 'package:flutter/foundation.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

Future<void>? _initialization;

/// Initializes the one process-wide wall-clock timezone used by every local
/// notification scheduler.
///
/// `timezone.local` defaults to UTC. Each scheduler initializing the timezone
/// package independently creates a race in which a daily "8 AM" reminder can
/// be scheduled at 8 AM UTC before another service installs the device zone.
Future<void> initializeLocalNotificationTimezone() =>
    _initialization ??= _initializeLocalNotificationTimezone();

Future<void> _initializeLocalNotificationTimezone() async {
  final location = await resolveNotificationTimezone(
    readDeviceTimezone: () async =>
        (await FlutterTimezone.getLocalTimezone()).identifier,
  );
  timezone.setLocalLocation(location);
}

/// Returns the next occurrence of a local wall-clock reminder time.
///
/// Calendar construction is deliberate: adding 24 hours to a zoned instant
/// moves an 8 AM reminder to 9 AM or 7 AM when daylight-saving time changes.
timezone.TZDateTime nextLocalNotificationTime({
  required timezone.TZDateTime now,
  required int minutesAfterMidnight,
}) {
  if (minutesAfterMidnight < 0 || minutesAfterMidnight >= 24 * 60) {
    throw RangeError.range(
      minutesAfterMidnight,
      0,
      24 * 60 - 1,
      'minutesAfterMidnight',
    );
  }
  final hour = minutesAfterMidnight ~/ 60;
  final minute = minutesAfterMidnight % 60;
  final today = timezone.TZDateTime(
    now.location,
    now.year,
    now.month,
    now.day,
    hour,
    minute,
  );
  if (today.isAfter(now)) return today;
  return timezone.TZDateTime(
    now.location,
    now.year,
    now.month,
    now.day + 1,
    hour,
    minute,
  );
}

@visibleForTesting
Future<timezone.Location> resolveNotificationTimezone({
  required Future<String> Function() readDeviceTimezone,
}) async {
  timezone_data.initializeTimeZones();
  try {
    final identifier = (await readDeviceTimezone()).trim();
    if (identifier.isEmpty) throw const FormatException('blank timezone');
    return timezone.getLocation(identifier);
  } on Object catch (error) {
    debugPrint('[notifications] timezone fallback to UTC: $error');
    return timezone.UTC;
  }
}
