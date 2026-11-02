import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/features/history/providers/health_history_providers.dart';
import 'package:pharmaguide/features/stack/providers/active_stack_provider.dart';
import 'package:pharmaguide/features/stack/providers/stack_reminder_providers.dart';
import 'package:pharmaguide/services/auth/account_storage.dart';
import 'package:pharmaguide/services/auth/pg_auth_service.dart';
import 'package:pharmaguide/services/history/local_health_reminder_service.dart';
import 'package:pharmaguide/services/notifications/notification_authorization_service.dart';
import 'package:pharmaguide/services/notifications/notification_delivery_policy.dart';
import 'package:pharmaguide/services/settings/app_preferences.dart';
import 'package:pharmaguide/services/stack/stack_reminder_scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent;

class _PendingPlatformWrite {
  final entered = Completer<void>();
  final release = Completer<void>();
  final finished = Completer<void>();
  bool scheduled = false;

  Future<void> run() async {
    entered.complete();
    await release.future;
    scheduled = true;
    finished.complete();
  }
}

class _DelayedHealth implements HealthReminderScheduler {
  _DelayedHealth(this.write);
  final _PendingPlatformWrite write;
  @override
  Future<int> cancelOwned() async => 0;
  @override
  Future<HealthReminderSyncResult> sync(
    List<HealthHistoryEvent> events, {
    bool permissionAlreadyGranted = false,
  }) async {
    await write.run();
    return const HealthReminderSyncResult(
      scheduled: 1,
      cancelled: 0,
      permissionGranted: true,
    );
  }
}

class _DelayedStack implements StackReminderScheduler {
  _DelayedStack(this.write);
  final _PendingPlatformWrite write;
  @override
  StackReminderNotificationClient get client => throw UnimplementedError();
  @override
  Future<int> cancelOwned() async => 0;
  @override
  Future<StackReminderSyncResult> sync(
    List<StackReminder> reminders, {
    bool permissionAlreadyGranted = false,
  }) async {
    await write.run();
    return const StackReminderSyncResult(
      scheduled: 1,
      cancelled: 0,
      permissionGranted: true,
      omittedDueToLimit: 0,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('a reminder job that outlives the sign-out', () {
    late Directory root;
    late int cancels;
    late int changes;
    late AccountSwitchGuard guard;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      root = await Directory.systemTemp.createTemp('reminder_stuck_');
      addTearDown(() => root.delete(recursive: true));
      cancels = 0;
      changes = 0;
      guard = AccountSwitchGuard(
        ownerStore: AccountOwnerStore(),
        storage: AccountStorage(
          supportDirectory: () async => root,
          documentsDirectory: () async => root,
        ),
        openDatabase: (path) async => UserDatabase.open(path),
        onOwnerChange: () async => cancels++,
      )..onChanged = () => changes++;
      addTearDown(guard.close);
      await guard.boot(sessionUid: 'account-a');
      // The first sign-in on record runs the same cleanup.
      cancels = 0;
    });

    test('never blocks the sign-out', () async {
      final stuck = Completer<void>();
      unawaited(
        guard.runNotificationWork(() => stuck.future, account: guard.account),
      );

      await guard
          .onAuthEvent(event: AuthChangeEvent.signedOut, uid: null)
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () => fail('sign-out waited on a stuck OS call'),
          );

      expect(guard.ownerUid, isNull);
      expect(guard.database, isNotNull);
      stuck.complete();
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('is cleaned up again when it finally finishes', () async {
      final late = Completer<void>();
      unawaited(
        guard.runNotificationWork(() => late.future, account: guard.account),
      );

      await guard
          .onAuthEvent(event: AuthChangeEvent.signedOut, uid: null)
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () => fail('sign-out waited on a stuck OS call'),
          );
      expect(cancels, 1);
      final changesAfterSwitch = changes;

      // Its write may land only now, after the first cancel. Cancelling again
      // must also hand the current owner's tree a chance to schedule again.
      late.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(cancels, 2);
      expect(changes, changesAfterSwitch + 1);
      expect(guard.ownerUid, isNull);
    }, timeout: const Timeout(Duration(seconds: 30)));
  });

  for (final health in [false, true]) {
    test(
      '${health ? 'history' : 'stack'} sign-out finishes when the data read is still loading',
      () async {
        SharedPreferences.setMockInitialValues({});
        final root = await Directory.systemTemp.createTemp('reminder_loading_');
        addTearDown(() => root.delete(recursive: true));
        final guard = AccountSwitchGuard(
          ownerStore: AccountOwnerStore(),
          storage: AccountStorage(
            supportDirectory: () async => root,
            documentsDirectory: () async => root,
          ),
          openDatabase: (path) async => UserDatabase.open(path),
        );
        addTearDown(guard.close);
        await guard.boot(sessionUid: 'account-a');
        final write = _PendingPlatformWrite();
        final container = ProviderContainer(
          overrides: [
            accountSwitchGuardProvider.overrideWithValue(guard),
            activeAccountProvider.overrideWithValue(guard.account),
            notificationDeliveryPolicyProvider.overrideWithValue(
              const NotificationDeliveryPolicy(
                authorizationStatus: NotificationAuthorizationStatus.allowed,
                preferences: NotificationPreferences(),
                producerAvailability: NotificationProducerAvailability(
                  stackReminders: true,
                  healthHistoryReminders: true,
                  safetyRecallAlerts: false,
                ),
              ),
            ),
            // The real path awaits these inside the registered job.
            activeStackProvider.overrideWith(
              (ref) => Completer<Never>().future,
            ),
            healthHistoryUpcomingProvider.overrideWith(
              (ref) => StreamController<Never>().stream,
            ),
            stackReminderSchedulerProvider.overrideWithValue(
              _DelayedStack(write),
            ),
            healthReminderSchedulerProvider.overrideWithValue(
              _DelayedHealth(write),
            ),
          ],
        );
        guard.releaseConsumers = () async => container.dispose();
        if (health) {
          container.listen(healthReminderSyncProvider, (_, _) {});
        } else {
          container.listen(stackReminderSyncProvider, (_, _) {});
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));

        await guard
            .onAuthEvent(event: AuthChangeEvent.signedOut, uid: null)
            .timeout(
              const Duration(seconds: 3),
              onTimeout: () => fail('sign-out waited on a disposed read'),
            );

        expect(guard.ownerUid, isNull);
        expect(write.entered.isCompleted, isFalse);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  }

  for (final health in [false, true]) {
    test(
      '${health ? 'history' : 'stack'} scheduling drains before sign-out cancels notifications',
      () async {
        SharedPreferences.setMockInitialValues({});
        final root = await Directory.systemTemp.createTemp('reminder_owner_');
        addTearDown(() => root.delete(recursive: true));
        final write = _PendingPlatformWrite();
        final guard = AccountSwitchGuard(
          ownerStore: AccountOwnerStore(),
          storage: AccountStorage(
            supportDirectory: () async => root,
            documentsDirectory: () async => root,
          ),
          openDatabase: (path) async => UserDatabase.open(path),
          onOwnerChange: () async => write.scheduled = false,
        );
        addTearDown(guard.close);
        await guard.boot(sessionUid: 'account-a');
        final container = ProviderContainer(
          overrides: [
            accountSwitchGuardProvider.overrideWithValue(guard),
            activeAccountProvider.overrideWithValue(guard.account),
            notificationDeliveryPolicyProvider.overrideWithValue(
              const NotificationDeliveryPolicy(
                authorizationStatus: NotificationAuthorizationStatus.allowed,
                preferences: NotificationPreferences(),
                producerAvailability: NotificationProducerAvailability(
                  stackReminders: true,
                  healthHistoryReminders: true,
                  safetyRecallAlerts: false,
                ),
              ),
            ),
            activeStackProvider.overrideWith((ref) async => []),
            healthHistoryUpcomingProvider.overrideWith(
              (ref) => Stream.value([]),
            ),
            stackReminderSchedulerProvider.overrideWithValue(
              _DelayedStack(write),
            ),
            healthReminderSchedulerProvider.overrideWithValue(
              _DelayedHealth(write),
            ),
          ],
        );
        guard.releaseConsumers = () async => container.dispose();
        if (health) {
          container.listen(healthReminderSyncProvider, (_, _) {});
        } else {
          container.listen(stackReminderSyncProvider, (_, _) {});
        }
        await write.entered.future;
        final switching = guard.onAuthEvent(
          event: AuthChangeEvent.signedOut,
          uid: null,
        );
        // Let sign-out reach its cleanup while the OS write is still in flight.
        await Future<void>.delayed(const Duration(milliseconds: 20));
        write.release.complete();
        await switching;
        await write.finished.future;
        expect(
          write.scheduled,
          isFalse,
          reason:
              'the outgoing scheduler must not recreate a cancelled reminder',
        );
        expect(guard.ownerUid, isNull);
      },
    );
  }
}
