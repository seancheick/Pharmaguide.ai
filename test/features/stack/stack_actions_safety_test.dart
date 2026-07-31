// FLTR-16 — Stack safety override.
//
// [StackActions.addProduct] must refuse to add a product whose verdict
// is BLOCKED or UNSAFE, throwing [StackAddBlockedException]. This is
// the defense-in-depth domain guard that protects any caller bypassing
// the UI short-circuit (deep links, bulk import, automation).

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/interaction_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/data/repositories/health_event_repository.dart';
import 'package:pharmaguide/features/stack/providers/active_stack_provider.dart';
import 'package:pharmaguide/features/stack/services/stack_sync_queue.dart';
import 'package:pharmaguide/services/auth_state_service.dart';

/// Minimal product fixture for guard assertions. We never reach the
/// Drift code path because the guard throws first, so the other
/// columns are unused.
ProductsCoreData _product({required String dsldId, required String verdict}) {
  return ProductsCoreData(
    dsldId: dsldId,
    productName: 'Test Product',
    productStatus: 'active',
    verdict: verdict,
    mappedCoverage: 0.0,
    exportVersion: 'test',
    exportedAt: '2026-04-23T00:00:00Z',
  );
}

void main() {
  group('StackActions.addProduct FLTR-16 verdict guard', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() => container.dispose());

    test('rejects BLOCKED verdict with StackAddBlockedException', () async {
      final actions = container.read(stackActionsProvider);
      final product = _product(dsldId: 'DS_BLOCKED', verdict: 'BLOCKED');

      expect(
        () => actions.addProduct(product),
        throwsA(
          isA<StackAddBlockedException>()
              .having((e) => e.dsldId, 'dsldId', 'DS_BLOCKED')
              .having((e) => e.verdict, 'verdict', 'BLOCKED'),
        ),
      );
    });

    test('rejects UNSAFE verdict with StackAddBlockedException', () async {
      final actions = container.read(stackActionsProvider);
      final product = _product(dsldId: 'DS_UNSAFE', verdict: 'UNSAFE');

      expect(
        () => actions.addProduct(product),
        throwsA(isA<StackAddBlockedException>()),
      );
    });

    test('lowercase blocked is normalized and still rejected', () async {
      final actions = container.read(stackActionsProvider);
      final product = _product(dsldId: 'DS_LC', verdict: 'blocked');

      expect(
        () => actions.addProduct(product),
        throwsA(isA<StackAddBlockedException>()),
      );
    });

    test('non-blocked verdicts pass the guard (reach Drift layer)', () async {
      container.read(authStateProvider.notifier).onSignedIn();
      final actions = container.read(stackActionsProvider);
      final product = _product(dsldId: 'DS_OK', verdict: 'RECOMMENDED');

      // We don't override userDatabaseProvider, so the call proceeds
      // past the guard and fails inside Drift. Any thrown type OTHER
      // than StackAddBlockedException confirms the guard let it
      // through — which is the invariant we want to prove.
      try {
        await actions.addProduct(product);
      } on StackAddBlockedException {
        fail('Non-blocked verdict must not trigger the safety guard');
      } on Object {
        // Expected — downstream database failure is fine for this
        // assertion; we only care that the verdict guard did not fire.
      }
    });

    test('guest users cannot save stack entries', () async {
      final actions = container.read(stackActionsProvider);
      final product = _product(dsldId: 'DS_OK', verdict: 'RECOMMENDED');

      expect(
        () => actions.addProduct(product),
        throwsA(isA<StackRequiresSignInException>()),
      );
      expect(
        () => actions.addMedication(
          name: 'Metformin',
          drugClasses: const ['class:biguanides'],
        ),
        throwsA(isA<StackRequiresSignInException>()),
      );
    });

    test('StackAddBlockedException toString includes both fields', () {
      const e = StackAddBlockedException(dsldId: 'DS_X', verdict: 'BLOCKED');
      expect(e.toString(), contains('DS_X'));
      expect(e.toString(), contains('BLOCKED'));
    });

    test(
      'addMedication persists curated class ids with runtime RxClass slugs',
      () async {
        final userDb = UserDatabase.memory();
        final interactionDb = InteractionDatabase.memory();
        addTearDown(userDb.close);
        addTearDown(interactionDb.close);

        await interactionDb
            .into(interactionDb.drugClassMap)
            .insert(
              DrugClassMapCompanion.insert(
                classId: 'class:nsaids',
                className: 'NSAIDs',
                drugRxcuisJson: '["5640"]',
                source: 'fixture',
                lastUpdated: '2026-06-27',
              ),
            );

        final localContainer = ProviderContainer(
          overrides: [
            userDatabaseProvider.overrideWithValue(userDb),
            interactionDatabaseProvider.overrideWithValue(interactionDb),
          ],
        );
        addTearDown(localContainer.dispose);
        localContainer.read(authStateProvider.notifier).onSignedIn();

        final actions = localContainer.read(stackActionsProvider);
        await actions.addMedication(
          name: 'Motrin',
          rxcui: '5640',
          drugClasses: const ['class:anti_inflammatory_agents_non_steroidal'],
        );

        final row = (await userDb.getActiveStack()).single;
        expect(jsonDecode(row.drugClassesCol!) as List, [
          'class:anti_inflammatory_agents_non_steroidal',
          'class:nsaids',
        ]);
        final history = await HealthEventRepository(userDb).getTimeline();
        expect(history, hasLength(1));
        expect(history.single.eventType, HealthEventTypes.stackItemAdded);
        expect(history.single.subjectType, 'medication');
        expect(history.single.title, 'Started Motrin');
      },
    );

    test(
      'dose and schedule changes use the same local history transaction',
      () async {
        final userDb = UserDatabase.memory();
        addTearDown(userDb.close);
        await userDb.addToStack(
          UserStacksLocalCompanion.insert(
            id: 'med-1',
            type: const Value('medication'),
            name: 'Metformin',
            dosage: const Value('500 mg'),
            frequency: const Value('Daily'),
          ),
        );
        final localContainer = ProviderContainer(
          overrides: [userDatabaseProvider.overrideWithValue(userDb)],
        );
        addTearDown(localContainer.dispose);
        localContainer.read(authStateProvider.notifier).onSignedIn();

        final actions = localContainer.read(stackActionsProvider);
        expect(
          await actions.updateSchedule(
            entryId: 'med-1',
            dosage: ' 1000 mg ',
            frequency: 'Twice daily',
          ),
          isTrue,
        );

        final row = (await userDb.getActiveStack()).single;
        expect(row.dosage, '1000 mg');
        expect(row.frequency, 'Twice daily');
        final history = await HealthEventRepository(userDb).getTimeline();
        expect(history, hasLength(1));
        expect(history.single.eventType, HealthEventTypes.stackItemChanged);
        expect(history.single.subjectId, 'med-1');
        expect(history.single.previousValueJson, contains('500 mg'));
        expect(history.single.currentValueJson, contains('1000 mg'));

        expect(
          await actions.updateSchedule(
            entryId: 'med-1',
            dosage: '1000 mg',
            frequency: 'Twice daily',
          ),
          isFalse,
        );
        expect(await HealthEventRepository(userDb).getTimeline(), hasLength(1));
      },
    );

    test(
      'a thirteenth reminder is rejected instead of silently ignored',
      () async {
        final userDb = UserDatabase.memory();
        addTearDown(userDb.close);
        for (var index = 0; index < 13; index++) {
          await userDb.addToStack(
            UserStacksLocalCompanion.insert(
              id: 'med-$index',
              type: const Value('medication'),
              name: 'Medication $index',
              reminderMinutes: index < 12
                  ? const Value(8 * 60)
                  : const Value.absent(),
            ),
          );
        }
        final localContainer = ProviderContainer(
          overrides: [userDatabaseProvider.overrideWithValue(userDb)],
        );
        addTearDown(localContainer.dispose);
        localContainer.read(authStateProvider.notifier).onSignedIn();

        final actions = localContainer.read(stackActionsProvider);
        await expectLater(
          actions.updateSchedule(
            entryId: 'med-12',
            reminderMinutes: const Value(9 * 60),
          ),
          throwsA(isA<StackReminderLimitException>()),
        );

        final target = (await userDb.getActiveStack()).singleWhere(
          (row) => row.id == 'med-12',
        );
        expect(target.reminderMinutes, isNull);
      },
    );

    test('device-only schedule fields do not dirty cloud sync state', () async {
      final userDb = UserDatabase.memory();
      addTearDown(userDb.close);
      final syncStamp = DateTime.utc(2026, 7, 30, 12);
      await userDb.addToStack(
        UserStacksLocalCompanion.insert(
          id: 'supplement-1',
          name: 'Vitamin D',
          dsldId: const Value('278454'),
          clientUpdatedAt: Value(syncStamp),
          syncedAt: Value(syncStamp),
        ),
      );
      final localContainer = ProviderContainer(
        overrides: [userDatabaseProvider.overrideWithValue(userDb)],
      );
      addTearDown(localContainer.dispose);
      localContainer.read(authStateProvider.notifier).onSignedIn();

      final actions = localContainer.read(stackActionsProvider);
      expect(
        await actions.updateSchedule(
          entryId: 'supplement-1',
          startedAt: Value(DateTime.utc(2020, 1, 1)),
          reminderMinutes: const Value(8 * 60),
        ),
        isTrue,
      );

      final row = (await userDb.getActiveStack()).single;
      expect(row.clientUpdatedAt.toUtc(), syncStamp);
      expect(await StackSyncQueue(userDb).dirtyRows(), isEmpty);
    });
  });
}
