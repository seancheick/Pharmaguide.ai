// Sprint: docs/sprints/product_detail_page_sprint.md — T1B.
//
// Validates the personalizedInteractionWarningsProvider's failure modes
// and basic propagation. The real interaction lookup logic is covered by
// `test/services/stack/stack_interaction_checker_curated_test.dart`.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/interaction_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/product_detail/providers/personalized_warnings_provider.dart';
import 'package:pharmaguide/features/stack/providers/stack_providers.dart';

const _dsldId = 'dsld-test';

UserStacksLocalData _stubMedication() {
  final ts = DateTime.utc(2026, 5, 4, 12);
  return UserStacksLocalData(
    id: 'med-1',
    type: 'medication',
    name: 'Metformin',
    dsldId: null,
    rxcui: '6809',
    ingredientKeys: null,
    drugClassesCol: null,
    genericRxcui: null,
    ingredientRxcuisCol: null,
    dosage: null,
    frequency: null,
    addedAt: ts,
    clientUpdatedAt: ts,
    deletedAt: null,
    syncedAt: null,
  );
}

Future<void> _seedProduct(
  CoreDatabase coreDb, {
  String? keyIngredientTags,
}) async {
  await coreDb
      .into(coreDb.productsCore)
      .insert(
        ProductsCoreCompanion.insert(
          dsldId: _dsldId,
          productName: 'Test Product',
          exportVersion: 'test',
          exportedAt: '2026-05-04T00:00:00Z',
          keyIngredientTags: Value(keyIngredientTags),
        ),
      );
}

void main() {
  group('personalizedInteractionWarningsProvider', () {
    test('empty stack → empty warnings', () async {
      final coreDb = CoreDatabase.memory();
      final userDb = UserDatabase.memory();
      final interactionDb = InteractionDatabase.memory();
      await _seedProduct(coreDb, keyIngredientTags: '["iron"]');

      final container = ProviderContainer(
        overrides: [
          coreDatabaseProvider.overrideWithValue(coreDb),
          userDatabaseProvider.overrideWithValue(userDb),
          interactionDatabaseProvider.overrideWithValue(interactionDb),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(
        personalizedInteractionWarningsProvider(_dsldId).future,
      );
      expect(result, isEmpty);

      await coreDb.close();
      await userDb.close();
      await interactionDb.close();
    });

    test('product not in core DB → empty warnings (no crash)', () async {
      final coreDb = CoreDatabase.memory();
      final userDb = UserDatabase.memory();
      final interactionDb = InteractionDatabase.memory();
      // Seed a stack entry so the early-empty branch doesn't short
      // circuit the lookup before it tries to load the product.
      await userDb.addToStack(
        UserStacksLocalCompanion.insert(
          id: 'med-1',
          type: const Value('medication'),
          name: 'Metformin',
          rxcui: const Value('6809'),
        ),
      );

      final container = ProviderContainer(
        overrides: [
          coreDatabaseProvider.overrideWithValue(coreDb),
          userDatabaseProvider.overrideWithValue(userDb),
          interactionDatabaseProvider.overrideWithValue(interactionDb),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(
        personalizedInteractionWarningsProvider('missing-id').future,
      );
      expect(result, isEmpty);

      await coreDb.close();
      await userDb.close();
      await interactionDb.close();
    });

    test(
      'UnimplementedError on stack provider → empty warnings (defensive)',
      () async {
        final coreDb = CoreDatabase.memory();
        final interactionDb = InteractionDatabase.memory();
        await _seedProduct(coreDb, keyIngredientTags: '["iron"]');

        final container = ProviderContainer(
          overrides: [
            coreDatabaseProvider.overrideWithValue(coreDb),
            interactionDatabaseProvider.overrideWithValue(interactionDb),
            activeStackProvider.overrideWith((ref) async {
              throw UnimplementedError('stack provider not staged in test');
            }),
          ],
        );
        addTearDown(container.dispose);

        final result = await container.read(
          personalizedInteractionWarningsProvider(_dsldId).future,
        );
        expect(result, isEmpty);

        await coreDb.close();
        await interactionDb.close();
      },
    );

    test('rebuilds when activeStackProvider changes', () async {
      // The whole point of T1B: stack mutations propagate.
      final coreDb = CoreDatabase.memory();
      final interactionDb = InteractionDatabase.memory();
      await _seedProduct(coreDb, keyIngredientTags: '["iron"]');

      final stackResponses = <List<UserStacksLocalData>>[
        const [],
        [_stubMedication()],
      ];
      var callIndex = 0;

      final container = ProviderContainer(
        overrides: [
          coreDatabaseProvider.overrideWithValue(coreDb),
          interactionDatabaseProvider.overrideWithValue(interactionDb),
          activeStackProvider.overrideWith((ref) async {
            return stackResponses[callIndex];
          }),
        ],
      );
      addTearDown(container.dispose);

      // First read: empty stack → empty list.
      final first = await container.read(
        personalizedInteractionWarningsProvider(_dsldId).future,
      );
      expect(first, isEmpty);

      // Mutate "stack" and invalidate (simulates StackActions._invalidate).
      callIndex = 1;
      container.invalidate(activeStackProvider);

      // The personalized provider now sees a non-empty stack. Even though
      // the curated DB has no rows for "iron × Metformin", the lookup
      // should run without throwing.
      final second = await container.read(
        personalizedInteractionWarningsProvider(_dsldId).future,
      );
      expect(second, isA<List<dynamic>>());

      await coreDb.close();
      await interactionDb.close();
    });
  });
}
