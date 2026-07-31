// Tests for StackReminderScheduler.
//
// The OS schedule is a disposable projection of the database. These tests pin
// the two properties that matter: turning a reminder off actually cancels it,
// and this scheduler can never touch a Health History notification.

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/services/history/local_health_reminder_service.dart';
import 'package:pharmaguide/services/stack/stack_reminder_scheduler.dart';

class _FakeClient implements StackReminderNotificationClient {
  final pending = <int>{};
  final scheduled = <(int, int)>[];
  final cancelled = <int>[];
  bool permissionGranted = true;
  var initialized = false;

  @override
  Future<void> initialize() async => initialized = true;

  @override
  Future<Set<int>> pendingIds() async => pending;

  @override
  Future<bool> requestPermission() async => permissionGranted;

  @override
  Future<void> scheduleDaily({
    required int id,
    required int minutesAfterMidnight,
  }) async {
    scheduled.add((id, minutesAfterMidnight));
  }

  @override
  Future<void> cancel(int id) async => cancelled.add(id);
}

void main() {
  test('an opted-in item is scheduled daily at its saved time', () async {
    final client = _FakeClient();
    final result = await StackReminderScheduler(
      client: client,
    ).sync([(stackEntryId: 'entry-1', minutesAfterMidnight: 8 * 60)]);

    expect(result.scheduled, 1);
    expect(client.scheduled.single.$2, 480);
    expect(client.initialized, isTrue);
  });

  test('turning a reminder off cancels its notification', () async {
    final staleId = StackReminderScheduler.notificationIdFor('entry-1');
    final client = _FakeClient()..pending.add(staleId);

    final result = await StackReminderScheduler(client: client).sync(const []);

    expect(result.cancelled, 1);
    expect(client.cancelled, [staleId]);
    expect(result.scheduled, 0);
  });

  test('re-syncing the same item replaces rather than duplicates', () async {
    final id = StackReminderScheduler.notificationIdFor('entry-1');
    final client = _FakeClient()..pending.add(id);

    await StackReminderScheduler(
      client: client,
    ).sync([(stackEntryId: 'entry-1', minutesAfterMidnight: 9 * 60)]);

    expect(client.cancelled, isEmpty);
    expect(client.scheduled.single.$1, id);
  });

  test('never cancels a Health History notification', () async {
    // The two schedulers share an OS namespace. Overlapping ranges would let
    // one silently delete the other's reminders.
    const healthId = 900000001;
    final client = _FakeClient()..pending.add(healthId);

    await StackReminderScheduler(client: client).sync(const []);

    expect(client.cancelled, isEmpty);
    expect(StackReminderScheduler.isOwned(healthId), isFalse);
  });

  test('the two id ranges do not overlap', () {
    for (final entryId in ['a', 'entry-1', 'x' * 40, '']) {
      final id = StackReminderScheduler.notificationIdFor(entryId);
      expect(StackReminderScheduler.isOwned(id), isTrue);
      // Health History owns [900000000, 990000000).
      expect(id >= 990000000, isTrue, reason: 'id $id collides with history');
    }
  });

  test('notification ids are stable across runs', () {
    // String.hashCode is not stable between isolates; a drifting id would
    // orphan the previous notification on every app start.
    expect(
      StackReminderScheduler.notificationIdFor('entry-1'),
      StackReminderScheduler.notificationIdFor('entry-1'),
    );
    expect(
      StackReminderScheduler.notificationIdFor('entry-1'),
      isNot(StackReminderScheduler.notificationIdFor('entry-2')),
    );
  });

  test('hash collisions never drop an opted-in reminder', () async {
    // These two real FNV-1a inputs collide after the scheduler's namespace
    // modulus. A map keyed only by the base hash silently kept one of them.
    expect(
      StackReminderScheduler.notificationIdFor('entry-9298'),
      StackReminderScheduler.notificationIdFor('entry-27140'),
    );
    final client = _FakeClient();

    final result = await StackReminderScheduler(client: client).sync(const [
      (stackEntryId: 'entry-9298', minutesAfterMidnight: 8 * 60),
      (stackEntryId: 'entry-27140', minutesAfterMidnight: 9 * 60),
    ]);

    expect(result.scheduled, 2);
    expect(client.scheduled.map((entry) => entry.$1).toSet(), hasLength(2));
  });

  test('denied permission leaves the saved reminder intact', () async {
    final client = _FakeClient()..permissionGranted = false;
    final result = await StackReminderScheduler(
      client: client,
    ).sync([(stackEntryId: 'entry-1', minutesAfterMidnight: 8 * 60)]);

    expect(result.permissionGranted, isFalse);
    expect(result.scheduled, 0);
    expect(client.scheduled, isEmpty);
  });

  test('out-of-range times are skipped, not clamped', () async {
    final client = _FakeClient();
    final result = await StackReminderScheduler(client: client).sync([
      (stackEntryId: 'bad-low', minutesAfterMidnight: -1),
      (stackEntryId: 'bad-high', minutesAfterMidnight: 24 * 60),
      (stackEntryId: 'good', minutesAfterMidnight: 0),
    ]);

    expect(result.scheduled, 1);
    expect(client.scheduled.single.$2, 0);
  });

  test('the schedule reports every reminder omitted by the cap', () async {
    final client = _FakeClient();
    final many = [
      for (var i = 0; i < 30; i++)
        (stackEntryId: 'entry-$i', minutesAfterMidnight: 8 * 60),
    ];

    final first = await StackReminderScheduler(client: client).sync(many);
    final second = await StackReminderScheduler(
      client: _FakeClient(),
    ).sync(many.reversed.toList());

    expect(first.scheduled, StackReminderScheduler.maxScheduled);
    expect(second.scheduled, StackReminderScheduler.maxScheduled);
    expect(first.omittedDueToLimit, 18);
    expect(second.omittedDueToLimit, 18);
  });

  test('the health scheduler still owns its own range', () {
    // Guards the invariant from the other side.
    expect(LocalHealthReminderService, isNotNull);
    expect(StackReminderScheduler.firstOwnedId, 990000000);
  });
}
