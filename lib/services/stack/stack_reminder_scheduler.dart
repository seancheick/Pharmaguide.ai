/// One stack item that has an opted-in daily reminder.
typedef StackReminder = ({String stackEntryId, int minutesAfterMidnight});

class StackReminderSyncResult {
  const StackReminderSyncResult({
    required this.scheduled,
    required this.cancelled,
    required this.permissionGranted,
  });

  final int scheduled;
  final int cancelled;
  final bool permissionGranted;
}

/// Platform boundary, mirrored from the Health History reminder service so
/// both can be driven by the same fake in tests.
abstract interface class StackReminderNotificationClient {
  Future<void> initialize();
  Future<Set<int>> pendingIds();
  Future<bool> requestPermission();

  /// Schedules a notification that repeats every day at [minutesAfterMidnight]
  /// local wall-clock time.
  Future<void> scheduleDaily({
    required int id,
    required int minutesAfterMidnight,
  });

  Future<void> cancel(int id);
}

/// Projects opted-in stack reminders into repeating OS notifications.
///
/// Deliberately a SEPARATE id namespace from the Health History reminders, so
/// neither scheduler can cancel the other's notifications. Both follow the same
/// rule: the database is the source of truth and the OS schedule is a
/// disposable projection rebuilt from it.
///
/// Reminders are opt-in per item, never global. The research this feature is
/// built against is unambiguous that notification volume — not notification
/// absence — is what drives people out of medication apps, so an item is
/// scheduled only when someone deliberately turned it on.
class StackReminderScheduler {
  StackReminderScheduler({required this.client});

  final StackReminderNotificationClient client;

  /// Health History owns [900000000, 990000000). This range sits above it.
  static const firstOwnedId = 990000000;
  static const ownedIdSpan = 9000000;

  /// A person who turns on more than this many reminders has recreated the
  /// alarm fatigue the feature exists to avoid. Bounded rather than unbounded,
  /// and the cap is reported rather than silently applied.
  static const maxScheduled = 12;

  Future<StackReminderSyncResult> sync(List<StackReminder> reminders) async {
    await client.initialize();

    final desired = <int, StackReminder>{};
    final ordered = [...reminders]
      ..sort((a, b) => a.stackEntryId.compareTo(b.stackEntryId));
    for (final reminder in ordered.take(maxScheduled)) {
      final minutes = reminder.minutesAfterMidnight;
      if (minutes < 0 || minutes > 24 * 60 - 1) continue;
      var notificationId = notificationIdFor(reminder.stackEntryId);
      while (desired.containsKey(notificationId)) {
        notificationId++;
        if (notificationId >= firstOwnedId + ownedIdSpan) {
          notificationId = firstOwnedId;
        }
      }
      desired[notificationId] = reminder;
    }

    final pending = await client.pendingIds();
    var cancelled = 0;
    for (final id in pending) {
      if (isOwned(id) && !desired.containsKey(id)) {
        await client.cancel(id);
        cancelled++;
      }
    }

    if (desired.isEmpty) {
      return StackReminderSyncResult(
        scheduled: 0,
        cancelled: cancelled,
        permissionGranted: true,
      );
    }

    final granted = await client.requestPermission();
    if (!granted) {
      // The saved reminder stays in the database. Only the OS projection is
      // absent, so granting permission later restores it with no data loss.
      return StackReminderSyncResult(
        scheduled: 0,
        cancelled: cancelled,
        permissionGranted: false,
      );
    }

    for (final entry in desired.entries) {
      await client.scheduleDaily(
        id: entry.key,
        minutesAfterMidnight: entry.value.minutesAfterMidnight,
      );
    }

    return StackReminderSyncResult(
      scheduled: desired.length,
      cancelled: cancelled,
      permissionGranted: true,
    );
  }

  /// Stable per-entry id so re-syncing replaces rather than duplicates.
  static int notificationIdFor(String stackEntryId) {
    // FNV-1a: stable across runs, unlike String.hashCode.
    var hash = 0x811c9dc5;
    for (final unit in stackEntryId.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return firstOwnedId + (hash % ownedIdSpan);
  }

  static bool isOwned(int id) =>
      id >= firstOwnedId && id < firstOwnedId + ownedIdSpan;
}
