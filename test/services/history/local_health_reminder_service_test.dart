import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/repositories/health_event_repository.dart';
import 'package:pharmaguide/services/history/local_health_reminder_service.dart';

void main() {
  test(
    'sync schedules future reminders and removes stale projections',
    () async {
      final database = UserDatabase.memory();
      addTearDown(database.close);
      final repository = HealthEventRepository(database);
      final reminderAt = DateTime.utc(2026, 8, 1, 14);
      await repository.append(
        HealthEventDraft(
          eventType: HealthEventTypes.appointmentScheduled,
          source: HealthEventSource.user,
          subjectType: 'appointment',
          subjectId: 'appointment-1',
          state: HealthEventState.scheduled,
          title: 'Oncology follow-up',
          summary: 'Discuss medication and lab results.',
          effectiveAt: DateTime.utc(2026, 8, 2, 14),
          reminderAt: reminderAt,
        ),
      );
      final client = _FakeNotificationClient()..pending.add(900000001);
      final service = LocalHealthReminderService(
        client: client,
        clock: () => DateTime.utc(2026, 7, 30),
      );

      final result = await service.sync(await repository.getTimeline());

      expect(result.scheduled, 1);
      expect(result.cancelled, 1);
      expect(client.cancelled, [900000001]);
      expect(client.scheduled.single.$2, reminderAt);
    },
  );

  test('denied permission preserves the event without scheduling', () async {
    final database = UserDatabase.memory();
    addTearDown(database.close);
    final repository = HealthEventRepository(database);
    await repository.append(
      HealthEventDraft(
        eventType: HealthEventTypes.reminderScheduled,
        source: HealthEventSource.user,
        subjectType: 'reminder',
        subjectId: 'follow-up-1',
        state: HealthEventState.scheduled,
        title: 'Sensitive title remains in the database',
        effectiveAt: DateTime.utc(2026, 8, 5),
        reminderAt: DateTime.utc(2026, 8, 5),
      ),
    );
    final client = _FakeNotificationClient()..permissionGranted = false;
    final service = LocalHealthReminderService(
      client: client,
      clock: () => DateTime.utc(2026, 7, 30),
    );

    final result = await service.sync(await repository.getTimeline());

    expect(result.permissionGranted, isFalse);
    expect(client.scheduled, isEmpty);
    expect(await repository.getTimeline(), hasLength(1));
  });

  test(
    'cancelOwned cancels only Health History ids and reports count',
    () async {
      const first = 900000001;
      const second = 989999999;
      const stackId = 990000001;
      final client = _FakeNotificationClient()
        ..pending.addAll({first, second, stackId, 42});
      final service = LocalHealthReminderService(client: client);

      final cancelled = await service.cancelOwned();

      expect(cancelled, 2);
      expect(client.cancelled, containsAll(<int>[first, second]));
      expect(client.cancelled, isNot(contains(stackId)));
      expect(client.cancelled, isNot(contains(42)));
    },
  );

  test(
    'confirmed policy path schedules without requesting permission',
    () async {
      final database = UserDatabase.memory();
      addTearDown(database.close);
      final repository = HealthEventRepository(database);
      await repository.append(
        HealthEventDraft(
          eventType: HealthEventTypes.reminderScheduled,
          source: HealthEventSource.user,
          subjectType: 'reminder',
          subjectId: 'follow-up-1',
          state: HealthEventState.scheduled,
          title: 'Follow up',
          effectiveAt: DateTime.utc(2026, 8, 5),
          reminderAt: DateTime.utc(2026, 8, 5),
        ),
      );
      final client = _FakeNotificationClient();
      final service = LocalHealthReminderService(
        client: client,
        clock: () => DateTime.utc(2026, 7, 30),
      );

      final result = await service.sync(
        await repository.getTimeline(),
        permissionAlreadyGranted: true,
      );

      expect(result.scheduled, 1);
      expect(client.permissionRequestCount, 0);
    },
  );
}

class _FakeNotificationClient implements HealthReminderNotificationClient {
  final pending = <int>{};
  final cancelled = <int>[];
  final scheduled = <(int, DateTime)>[];
  bool permissionGranted = true;
  var permissionRequestCount = 0;

  @override
  Future<void> initialize() async {}

  @override
  Future<Set<int>> pendingIds() async => pending;

  @override
  Future<bool> requestPermission() async {
    permissionRequestCount++;
    return permissionGranted;
  }

  @override
  Future<void> schedule({required int id, required DateTime at}) async {
    scheduled.add((id, at));
  }

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
  }
}
