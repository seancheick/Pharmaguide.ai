import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/features/stack/providers/active_stack_provider.dart';
import 'package:pharmaguide/services/notifications/local_notification_timezone.dart';
import 'package:pharmaguide/services/stack/stack_reminder_scheduler.dart';
import 'package:timezone/timezone.dart' as timezone;

/// Repeating daily reminders for stack items the user opted in per item.
///
/// Kept separate from `healthReminderSyncProvider`: that one projects one-shot
/// appointment reminders from the event log, this one projects repeating
/// item reminders from the stack. Separate id namespaces mean neither can
/// cancel the other's notifications.
final stackReminderSchedulerProvider = Provider<StackReminderScheduler>((ref) {
  return StackReminderScheduler(client: _FlutterStackReminderClient());
});

final stackReminderSyncProvider =
    FutureProvider.autoDispose<StackReminderSyncResult>((ref) async {
      final stack = await ref.watch(activeStackProvider.future);
      final reminders = <StackReminder>[
        for (final entry in stack)
          if (entry.reminderMinutes != null)
            (
              stackEntryId: entry.id,
              minutesAfterMidnight: entry.reminderMinutes!,
            ),
      ];
      return ref.watch(stackReminderSchedulerProvider).sync(reminders);
    });

class _FlutterStackReminderClient implements StackReminderNotificationClient {
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  Future<void>? _initialization;

  static const _channelId = 'stack_item_reminders';

  @override
  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    await initializeLocalNotificationTimezone();
    await _notifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
  }

  @override
  Future<Set<int>> pendingIds() async {
    final requests = await _notifications.pendingNotificationRequests();
    return requests.map((request) => request.id).toSet();
  }

  @override
  Future<bool> requestPermission() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      // Defaults to false so an undeclared or denied permission is reported
      // honestly rather than as a scheduled reminder that never fires.
      return await _notifications
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.requestNotificationsPermission() ??
          false;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return await _notifications
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, badge: false, sound: true) ??
          false;
    }
    return false;
  }

  @override
  Future<void> scheduleDaily({
    required int id,
    required int minutesAfterMidnight,
  }) {
    final now = timezone.TZDateTime.now(timezone.local);
    var first = timezone.TZDateTime(
      timezone.local,
      now.year,
      now.month,
      now.day,
      minutesAfterMidnight ~/ 60,
      minutesAfterMidnight % 60,
    );
    if (!first.isAfter(now)) first = first.add(const Duration(days: 1));

    return _notifications.zonedSchedule(
      id: id,
      // Deliberately generic. A lock screen is a public surface, so no item
      // name, dose, or condition appears here.
      title: 'PharmaGuide reminder',
      body: 'You have an item saved for around now.',
      scheduledDate: first,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Item reminders',
          channelDescription:
              'Private daily reminders for items you opted in to.',
          visibility: NotificationVisibility.private,
        ),
        iOS: DarwinNotificationDetails(threadIdentifier: _channelId),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      // Repeats every day at this wall-clock time, so it survives DST and
      // travel instead of drifting.
      matchDateTimeComponents: DateTimeComponents.time,
      payload: 'stack-reminder',
    );
  }

  @override
  Future<void> cancel(int id) => _notifications.cancel(id: id);
}
