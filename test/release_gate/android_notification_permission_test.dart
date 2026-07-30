import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Release gate: Health History reminders are scheduled through
/// `flutter_local_notifications`. From Android 13 (API 33) a notification
/// cannot be posted unless POST_NOTIFICATIONS is declared in the manifest —
/// the runtime request silently becomes a no-op, so every reminder is
/// dropped without an error surface.
///
/// This guards the declaration itself because the failure is invisible in
/// unit tests: `LocalHealthReminderService` takes an injected client, so a
/// fake always reports success regardless of what the platform would do.
void main() {
  group('release gate: android notification permissions', () {
    late String manifest;

    setUpAll(() {
      manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
    });

    test('POST_NOTIFICATIONS is declared for Android 13+ reminders', () {
      expect(
        manifest,
        contains('android.permission.POST_NOTIFICATIONS'),
        reason:
            'Without POST_NOTIFICATIONS, requestNotificationsPermission() is '
            'a no-op on API 33+ and Health History reminders never fire.',
      );
    });

    test('boot receiver is declared so reminders survive a restart', () {
      expect(manifest, contains('android.permission.RECEIVE_BOOT_COMPLETED'));
      expect(manifest, contains('ScheduledNotificationBootReceiver'));
    });

    test('no exact-alarm permission is requested', () {
      // The scheduler uses AndroidScheduleMode.inexactAllowWhileIdle.
      // SCHEDULE_EXACT_ALARM triggers Play Store policy review and is not
      // needed for appointment-grade reminders.
      expect(manifest, isNot(contains('SCHEDULE_EXACT_ALARM')));
      expect(manifest, isNot(contains('USE_EXACT_ALARM')));
    });
  });
}
