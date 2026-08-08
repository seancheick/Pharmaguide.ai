import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/repositories/health_event_repository.dart';
import 'package:pharmaguide/features/history/providers/health_history_providers.dart';
import 'package:pharmaguide/features/settings/providers/app_preferences_provider.dart';
import 'package:pharmaguide/features/settings/providers/notification_settings_provider.dart';
import 'package:pharmaguide/features/stack/providers/active_stack_provider.dart';
import 'package:pharmaguide/features/stack/providers/stack_reminder_providers.dart';
import 'package:pharmaguide/services/history/local_health_reminder_service.dart';
import 'package:pharmaguide/services/notifications/notification_authorization_service.dart';
import 'package:pharmaguide/services/notifications/notification_delivery_policy.dart';
import 'package:pharmaguide/services/settings/app_preferences.dart';
import 'package:pharmaguide/services/stack/stack_reminder_scheduler.dart';

void main() {
  const implementedProducers = NotificationProducerAvailability(
    stackReminders: true,
    healthHistoryReminders: true,
    safetyRecallAlerts: false,
  );

  NotificationDeliveryPolicy policy({
    NotificationAuthorizationStatus authorization =
        NotificationAuthorizationStatus.allowed,
    NotificationPreferences preferences = const NotificationPreferences(),
    NotificationProducerAvailability producers = implementedProducers,
  }) {
    return NotificationDeliveryPolicy(
      authorizationStatus: authorization,
      preferences: preferences,
      producerAvailability: producers,
    );
  }

  group('NotificationDeliveryPolicy', () {
    test('allowed enabled implemented reminder producers schedule', () {
      final delivery = policy();

      expect(
        delivery.actionFor(NotificationCategory.stackReminders),
        NotificationDeliveryAction.schedule,
      );
      expect(
        delivery.actionFor(NotificationCategory.healthHistoryReminders),
        NotificationDeliveryAction.schedule,
      );
    });

    test('master pause cancels both reminder categories', () {
      final delivery = policy(
        preferences: const NotificationPreferences(remindersEnabled: false),
      );

      expect(
        delivery.actionFor(NotificationCategory.stackReminders),
        NotificationDeliveryAction.cancel,
      );
      expect(
        delivery.actionFor(NotificationCategory.healthHistoryReminders),
        NotificationDeliveryAction.cancel,
      );
    });

    test('stack category pause cancels only stack reminders', () {
      final delivery = policy(
        preferences: const NotificationPreferences(
          stackRemindersEnabled: false,
        ),
      );

      expect(
        delivery.actionFor(NotificationCategory.stackReminders),
        NotificationDeliveryAction.cancel,
      );
      expect(
        delivery.actionFor(NotificationCategory.healthHistoryReminders),
        NotificationDeliveryAction.schedule,
      );
    });

    test('Health History category pause cancels only its reminders', () {
      final delivery = policy(
        preferences: const NotificationPreferences(
          healthHistoryRemindersEnabled: false,
        ),
      );

      expect(
        delivery.actionFor(NotificationCategory.stackReminders),
        NotificationDeliveryAction.schedule,
      );
      expect(
        delivery.actionFor(NotificationCategory.healthHistoryReminders),
        NotificationDeliveryAction.cancel,
      );
    });

    for (final authorization in const [
      NotificationAuthorizationStatus.blocked,
      NotificationAuthorizationStatus.restricted,
    ]) {
      test('${authorization.name} cancels every implemented producer', () {
        final delivery = policy(authorization: authorization);

        expect(
          delivery.actionFor(NotificationCategory.stackReminders),
          NotificationDeliveryAction.cancel,
        );
        expect(
          delivery.actionFor(NotificationCategory.healthHistoryReminders),
          NotificationDeliveryAction.cancel,
        );
        expect(
          delivery.actionFor(NotificationCategory.safetyRecallAlerts),
          NotificationDeliveryAction.preserve,
        );
      });
    }

    for (final authorization in const [
      NotificationAuthorizationStatus.unavailable,
      NotificationAuthorizationStatus.notDetermined,
      NotificationAuthorizationStatus.unsupported,
    ]) {
      test('${authorization.name} preserves every OS projection', () {
        final delivery = policy(authorization: authorization);

        for (final category in NotificationCategory.values) {
          expect(
            delivery.actionFor(category),
            NotificationDeliveryAction.preserve,
          );
        }
      });
    }

    test(
      'an unavailable producer preserves instead of adding or cancelling',
      () {
        final delivery = policy(
          producers: const NotificationProducerAvailability(
            stackReminders: false,
            healthHistoryReminders: true,
            safetyRecallAlerts: false,
          ),
        );

        expect(
          delivery.actionFor(NotificationCategory.stackReminders),
          NotificationDeliveryAction.preserve,
        );
      },
    );

    test('future recall alerts ignore all reminder preference booleans', () {
      final delivery = policy(
        preferences: const NotificationPreferences(
          remindersEnabled: false,
          stackRemindersEnabled: false,
          healthHistoryRemindersEnabled: false,
        ),
        producers: const NotificationProducerAvailability(
          stackReminders: true,
          healthHistoryReminders: true,
          safetyRecallAlerts: true,
        ),
      );

      expect(
        delivery.actionFor(NotificationCategory.safetyRecallAlerts),
        NotificationDeliveryAction.schedule,
      );
    });

    test('recall alerts preserve until a producer exists', () {
      expect(
        policy().actionFor(NotificationCategory.safetyRecallAlerts),
        NotificationDeliveryAction.preserve,
      );
    });

    test('policy has no dependency on in-app recall verdict state', () {
      final source = File(
        'lib/services/notifications/notification_delivery_policy.dart',
      ).readAsStringSync();

      expect(source, isNot(contains('RecalledIngredientsReport')));
      expect(source, isNot(contains('StackSafetyReport')));
      expect(source, isNot(contains('recalled_ingredient_result.dart')));
      expect(source, isNot(contains('stack_safety_report.dart')));
      expect(source, isNot(contains('verdict')));
    });
  });

  group('derived delivery policy', () {
    test(
      'watches the shared preferences and authorization controllers',
      () async {
        final preferences = AppPreferencesController(
          repository: AppPreferencesRepository(_MemoryPreferencesStore()),
        );
        final authorizationService = _AuthorizationService([
          NotificationAuthorizationStatus.allowed,
          NotificationAuthorizationStatus.blocked,
          NotificationAuthorizationStatus.allowed,
        ]);
        final notificationSettings = NotificationSettingsController(
          service: authorizationService,
          lifecycleBinding: _LifecycleBinding(),
        );
        await notificationSettings.initialRefresh;
        final container = ProviderContainer(
          overrides: [
            appPreferencesControllerProvider.overrideWith(
              (_) => preferences,
              disposeNotifier: false,
            ),
            notificationSettingsControllerProvider.overrideWith(
              (_) => notificationSettings,
              disposeNotifier: false,
            ),
          ],
        );
        addTearDown(() {
          container.dispose();
          notificationSettings.dispose();
          preferences.dispose();
        });

        NotificationDeliveryAction stackAction() => container
            .read(notificationDeliveryPolicyProvider)
            .actionFor(NotificationCategory.stackReminders);

        expect(stackAction(), NotificationDeliveryAction.schedule);

        await preferences.updateRemindersEnabled(false);
        expect(stackAction(), NotificationDeliveryAction.cancel);

        await preferences.updateRemindersEnabled(true);
        expect(stackAction(), NotificationDeliveryAction.schedule);

        await notificationSettings.refresh();
        expect(stackAction(), NotificationDeliveryAction.cancel);

        await notificationSettings.refresh();
        expect(stackAction(), NotificationDeliveryAction.schedule);
        expect(authorizationService.permissionRequestCount, 0);
      },
    );
  });

  group('provider-driven reminder sync', () {
    test(
      'master pause cancels both namespaces without changing DB inputs',
      () async {
        final database = UserDatabase.memory();
        addTearDown(database.close);
        await database.addToStack(
          const UserStacksLocalCompanion(
            id: Value('entry-1'),
            type: Value('supplement'),
            name: Value('Vitamin D'),
            reminderMinutes: Value(8 * 60),
          ),
        );
        final repository = HealthEventRepository(database);
        await repository.append(
          HealthEventDraft(
            eventType: HealthEventTypes.reminderScheduled,
            source: HealthEventSource.user,
            subjectType: 'reminder',
            subjectId: 'follow-up-1',
            state: HealthEventState.scheduled,
            title: 'Follow up',
            effectiveAt: DateTime.utc(2026, 8, 10),
            reminderAt: DateTime.utc(2026, 8, 10),
          ),
        );
        final stackClient = _StackClient()
          ..pending.add(StackReminderScheduler.notificationIdFor('entry-1'));
        final healthClient = _HealthClient()..pending.add(900000001);
        final container = _syncContainer(
          deliveryPolicy: policy(
            preferences: const NotificationPreferences(remindersEnabled: false),
          ),
          stackClient: stackClient,
          healthClient: healthClient,
        );
        addTearDown(container.dispose);
        final healthSubscription = container.listen(
          healthReminderSyncProvider,
          (_, _) {},
        );
        addTearDown(healthSubscription.close);

        final stackResult = await container.read(
          stackReminderSyncProvider.future,
        );
        final healthResult = await container.read(
          healthReminderSyncProvider.future,
        );

        expect(stackResult.cancelled, 1);
        expect(healthResult.cancelled, 1);
        expect(stackClient.cancelled, hasLength(1));
        expect(healthClient.cancelled, [900000001]);
        expect(await database.getActiveStack(), hasLength(1));
        expect(await repository.getTimeline(), hasLength(1));
        expect(container.read(stackRemindersDeliverableProvider), isFalse);
      },
    );

    for (final authorization in const [
      NotificationAuthorizationStatus.blocked,
      NotificationAuthorizationStatus.restricted,
    ]) {
      test(
        '${authorization.name} cancels both implemented namespaces',
        () async {
          final stackClient = _StackClient()
            ..pending.add(StackReminderScheduler.notificationIdFor('entry-1'));
          final healthClient = _HealthClient()..pending.add(900000001);
          final container = _syncContainer(
            deliveryPolicy: policy(authorization: authorization),
            stackClient: stackClient,
            healthClient: healthClient,
          );
          addTearDown(container.dispose);

          await Future.wait([
            container.read(stackReminderSyncProvider.future),
            container.read(healthReminderSyncProvider.future),
          ]);

          expect(stackClient.cancelled, hasLength(1));
          expect(healthClient.cancelled, [900000001]);
          expect(container.read(stackRemindersDeliverableProvider), isFalse);
        },
      );
    }

    for (final authorization in const [
      NotificationAuthorizationStatus.unavailable,
      NotificationAuthorizationStatus.notDetermined,
      NotificationAuthorizationStatus.unsupported,
    ]) {
      test(
        '${authorization.name} leaves both pending namespaces untouched',
        () async {
          final stackClient = _StackClient()
            ..pending.add(StackReminderScheduler.notificationIdFor('entry-1'));
          final healthClient = _HealthClient()..pending.add(900000001);
          final container = _syncContainer(
            deliveryPolicy: policy(authorization: authorization),
            stackClient: stackClient,
            healthClient: healthClient,
          );
          addTearDown(container.dispose);

          final stackResult = await container.read(
            stackReminderSyncProvider.future,
          );
          final healthResult = await container.read(
            healthReminderSyncProvider.future,
          );

          expect(stackResult.cancelled, 0);
          expect(healthResult.cancelled, 0);
          expect(stackClient.initialized, isFalse);
          expect(healthClient.initialized, isFalse);
          expect(stackClient.cancelled, isEmpty);
          expect(healthClient.cancelled, isEmpty);
        },
      );
    }

    test(
      'allowed background sync schedules without an OS permission request',
      () async {
        final stackClient = _StackClient();
        final healthScheduler = _RecordingHealthScheduler();
        final container = ProviderContainer(
          overrides: [
            notificationDeliveryPolicyProvider.overrideWithValue(policy()),
            activeStackProvider.overrideWith(
              (_) async => [
                UserStacksLocalData(
                  id: 'entry-1',
                  type: 'supplement',
                  name: 'Vitamin D',
                  addedAt: DateTime.utc(2026, 8, 1),
                  reminderMinutes: 8 * 60,
                  clientUpdatedAt: DateTime.utc(2026, 8, 1),
                ),
              ],
            ),
            healthHistoryUpcomingProvider.overrideWith(
              (_) => Stream.value(const <HealthHistoryItem>[]),
            ),
            stackReminderSchedulerProvider.overrideWithValue(
              StackReminderScheduler(client: stackClient),
            ),
            healthReminderSchedulerProvider.overrideWithValue(healthScheduler),
          ],
        );
        addTearDown(container.dispose);
        final healthSubscription = container.listen(
          healthReminderSyncProvider,
          (_, _) {},
        );
        addTearDown(healthSubscription.close);

        final stackResult = await container.read(
          stackReminderSyncProvider.future,
        );
        await container.read(healthReminderSyncProvider.future);

        expect(stackResult.scheduled, 1);
        expect(stackClient.permissionRequestCount, 0);
        expect(healthScheduler.permissionAlreadyGranted, isTrue);
      },
    );
  });
}

ProviderContainer _syncContainer({
  required NotificationDeliveryPolicy deliveryPolicy,
  required _StackClient stackClient,
  required _HealthClient healthClient,
}) {
  return ProviderContainer(
    overrides: [
      notificationDeliveryPolicyProvider.overrideWithValue(deliveryPolicy),
      stackReminderSchedulerProvider.overrideWithValue(
        StackReminderScheduler(client: stackClient),
      ),
      healthReminderSchedulerProvider.overrideWithValue(
        LocalHealthReminderService(client: healthClient),
      ),
    ],
  );
}

class _StackClient implements StackReminderNotificationClient {
  final pending = <int>{};
  final cancelled = <int>[];
  var initialized = false;
  var permissionRequestCount = 0;

  @override
  Future<void> initialize() async => initialized = true;

  @override
  Future<Set<int>> pendingIds() async => pending;

  @override
  Future<bool> requestPermission() async {
    permissionRequestCount++;
    return true;
  }

  @override
  Future<void> scheduleDaily({
    required int id,
    required int minutesAfterMidnight,
  }) async {}

  @override
  Future<void> cancel(int id) async => cancelled.add(id);
}

class _HealthClient implements HealthReminderNotificationClient {
  final pending = <int>{};
  final cancelled = <int>[];
  var initialized = false;

  @override
  Future<void> initialize() async => initialized = true;

  @override
  Future<Set<int>> pendingIds() async => pending;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> schedule({required int id, required DateTime at}) async {}

  @override
  Future<void> cancel(int id) async => cancelled.add(id);
}

class _RecordingHealthScheduler implements HealthReminderScheduler {
  bool? permissionAlreadyGranted;

  @override
  Future<int> cancelOwned() async => 0;

  @override
  Future<HealthReminderSyncResult> sync(
    List<HealthHistoryEvent> upcomingEvents, {
    bool permissionAlreadyGranted = false,
  }) async {
    this.permissionAlreadyGranted = permissionAlreadyGranted;
    return const HealthReminderSyncResult(
      scheduled: 0,
      cancelled: 0,
      permissionGranted: true,
    );
  }
}

class _AuthorizationService implements NotificationAuthorizationService {
  _AuthorizationService(this.statuses);

  final List<NotificationAuthorizationStatus> statuses;
  var permissionRequestCount = 0;

  @override
  Future<NotificationAuthorizationStatus> readStatus() async {
    return statuses.removeAt(0);
  }

  @override
  Future<NotificationAuthorizationStatus> requestPermission() async {
    permissionRequestCount++;
    return NotificationAuthorizationStatus.allowed;
  }

  @override
  Future<void> openNotificationSettings() async {}
}

class _LifecycleBinding implements NotificationLifecycleBinding {
  @override
  void addObserver(WidgetsBindingObserver observer) {}

  @override
  void removeObserver(WidgetsBindingObserver observer) {}
}

class _MemoryPreferencesStore implements AppPreferencesStore {
  final values = <String, Object>{};

  @override
  Future<bool?> getBool(String key) async => values[key] as bool?;

  @override
  Future<String?> getString(String key) async => values[key] as String?;

  @override
  Future<void> setBool(String key, bool value) async => values[key] = value;

  @override
  Future<void> setString(String key, String value) async => values[key] = value;
}
