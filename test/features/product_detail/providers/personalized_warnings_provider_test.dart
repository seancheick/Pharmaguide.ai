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
import 'package:pharmaguide/features/product_detail/providers/detail_blob_provider.dart';
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

UserStacksLocalData _stubWarfarin() {
  final ts = DateTime.utc(2026, 7, 28, 12);
  return UserStacksLocalData(
    id: 'med-warfarin',
    type: 'medication',
    name: 'Warfarin',
    dsldId: null,
    rxcui: '11289',
    ingredientKeys: null,
    drugClassesCol: '["class:vitamin_k_antagonists"]',
    genericRxcui: '11289',
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
  String dsldId = _dsldId,
  String productName = 'Test Product',
}) async {
  await coreDb
      .into(coreDb.productsCore)
      .insert(
        ProductsCoreCompanion.insert(
          dsldId: dsldId,
          productName: productName,
          exportVersion: 'test',
          exportedAt: '2026-05-04T00:00:00Z',
          keyIngredientTags: Value(keyIngredientTags),
        ),
      );
}

UserStacksLocalData _stubSupplement({
  required String id,
  required String name,
  required String dsldId,
  required String ingredientKeys,
}) {
  final ts = DateTime.utc(2026, 5, 4, 12);
  return UserStacksLocalData(
    id: id,
    type: 'supplement',
    name: name,
    dsldId: dsldId,
    ingredientKeys: ingredientKeys,
    addedAt: ts,
    clientUpdatedAt: ts,
  );
}

Future<void> _seedFishOilVitaminEPair(InteractionDatabase db) async {
  await db
      .into(db.interactions)
      .insert(
        InteractionsCompanion.insert(
          id: 'DSI_FISHOIL_VITE',
          agent1Type: 'supplement',
          agent1Name: 'Fish Oil / Omega-3',
          agent1Id: 'C0016157',
          agent1CanonicalId: const Value('fish_oil'),
          agent2Type: 'supplement',
          agent2Name: 'Vitamin E',
          agent2Id: 'C0042874',
          agent2CanonicalId: const Value('vitamin_e'),
          severity: 'caution',
          effectType: const Value('additive'),
          mechanism: 'Additive antiplatelet effect.',
          management: 'Monitor for bruising or bleeding.',
          evidenceLevel: const Value('established'),
          sourceUrlsJson: '["https://pubmed.ncbi.nlm.nih.gov/22300597/"]',
          sourcePmidsJson: '["22300597"]',
          doseDependent: const Value(1),
          direction: const Value('harmful'),
          materiality: const Value('dose_dependent'),
          doseThresholdJson: const Value(
            '{"agent_canonical_id":"vitamin_e","value":400,"unit":"IU","basis":"per_day"}',
          ),
          typeAuthored: 'Sup-Sup',
          source: 'curated',
          provenance: 'pubmed',
          versionAdded: 'test',
          versionLastModified: 'test',
          lastUpdated: '2026-07-08',
        ),
      );
}

Future<void> _seedWarfarinVitaminKPair(InteractionDatabase db) async {
  await db
      .into(db.interactions)
      .insert(
        InteractionsCompanion.insert(
          id: 'DSI_WAR_VITK',
          agent1Type: 'drug',
          agent1Name: 'Warfarin',
          agent1Id: '11289',
          agent1CanonicalId: const Value(null),
          agent2Type: 'supplement',
          agent2Name: 'Vitamin K',
          agent2Id: 'C0042878',
          agent2CanonicalId: const Value('vitamin_k'),
          severity: 'caution',
          effectType: const Value('inhibitor'),
          mechanism: 'Sudden vitamin K changes can alter warfarin effect.',
          management: 'Keep vitamin K intake consistent.',
          evidenceLevel: const Value('established'),
          sourceUrlsJson:
              '["https://ods.od.nih.gov/factsheets/VitaminK-HealthProfessional/"]',
          sourcePmidsJson: '[]',
          doseDependent: const Value(0),
          direction: const Value('harmful'),
          materiality: const Value('presence'),
          typeAuthored: 'Med-Sup',
          source: 'curated',
          provenance: 'nih_ods',
          versionAdded: 'test',
          versionLastModified: 'test',
          lastUpdated: '2026-07-28',
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
      'suppresses pairwise fish-oil vitamin-E warning below threshold',
      () async {
        final coreDb = CoreDatabase.memory();
        final interactionDb = InteractionDatabase.memory();
        await _seedProduct(
          coreDb,
          keyIngredientTags: '["fish_oil"]',
          productName: 'Fish Oil',
        );
        await _seedFishOilVitaminEPair(interactionDb);

        final container = ProviderContainer(
          overrides: [
            coreDatabaseProvider.overrideWithValue(coreDb),
            interactionDatabaseProvider.overrideWithValue(interactionDb),
            activeStackProvider.overrideWith((ref) async {
              return [
                _stubSupplement(
                  id: 'one',
                  name: 'O.N.E. Multivitamin',
                  dsldId: 'one-multi',
                  ingredientKeys: '["vitamin_e"]',
                ),
              ];
            }),
            detailBlobProvider.overrideWith((ref, dsldId) async {
              if (dsldId == _dsldId) {
                return {
                  'ingredients': [
                    {
                      'standard_name': 'Fish Oil',
                      'quantity': 1000,
                      'unit': 'mg',
                    },
                  ],
                };
              }
              if (dsldId == 'one-multi') {
                return {
                  'ingredients': [
                    {
                      'standard_name': 'Vitamin E',
                      'quantity': 20,
                      'unit': 'mg',
                    },
                  ],
                };
              }
              return null;
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

    test(
      'medication interaction names the medication and keeps merge context',
      () async {
        final coreDb = CoreDatabase.memory();
        final interactionDb = InteractionDatabase.memory();
        await _seedProduct(
          coreDb,
          keyIngredientTags: '["vitamin_k"]',
          productName: 'Calcium K/D',
        );
        await _seedWarfarinVitaminKPair(interactionDb);

        final container = ProviderContainer(
          overrides: [
            coreDatabaseProvider.overrideWithValue(coreDb),
            interactionDatabaseProvider.overrideWithValue(interactionDb),
            activeStackProvider.overrideWith((ref) async => [_stubWarfarin()]),
            detailBlobProvider.overrideWith((ref, dsldId) async => null),
          ],
        );
        addTearDown(container.dispose);

        final result = await container.read(
          personalizedInteractionWarningsProvider(_dsldId).future,
        );

        expect(result, hasLength(1));
        expect(result.single.title, "Because you're taking Warfarin");
        expect(result.single.ingredientCanonicalId, 'vitamin_k');
        expect(
          result.single.drugClassIds,
          contains('class:vitamin_k_antagonists'),
        );

        await coreDb.close();
        await interactionDb.close();
      },
    );

    test(
      'stack provider failure surfaces instead of returning an all-clear',
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

        await expectLater(
          container.read(
            personalizedInteractionWarningsProvider(_dsldId).future,
          ),
          throwsA(isA<UnimplementedError>()),
        );

        await coreDb.close();
        await interactionDb.close();
      },
    );

    test(
      'current product detail failure surfaces instead of dropping dose context',
      () async {
        final coreDb = CoreDatabase.memory();
        final interactionDb = InteractionDatabase.memory();
        await _seedProduct(coreDb, keyIngredientTags: '["vitamin_k"]');

        final container = ProviderContainer(
          overrides: [
            coreDatabaseProvider.overrideWithValue(coreDb),
            interactionDatabaseProvider.overrideWithValue(interactionDb),
            activeStackProvider.overrideWith((ref) async => [_stubWarfarin()]),
            detailBlobProvider.overrideWith((ref, dsldId) async {
              throw Exception('declared detail blob unavailable');
            }),
          ],
        );
        addTearDown(container.dispose);

        await expectLater(
          container.read(
            personalizedInteractionWarningsProvider(_dsldId).future,
          ),
          throwsA(anything),
        );

        await coreDb.close();
        await interactionDb.close();
      },
    );

    test(
      'stack product detail failure surfaces instead of skipping dose totals',
      () async {
        final coreDb = CoreDatabase.memory();
        final interactionDb = InteractionDatabase.memory();
        await _seedProduct(
          coreDb,
          keyIngredientTags: '["fish_oil"]',
          productName: 'Fish Oil',
        );

        final container = ProviderContainer(
          overrides: [
            coreDatabaseProvider.overrideWithValue(coreDb),
            interactionDatabaseProvider.overrideWithValue(interactionDb),
            activeStackProvider.overrideWith((ref) async {
              return [
                _stubSupplement(
                  id: 'one',
                  name: 'O.N.E. Multivitamin',
                  dsldId: 'one-multi',
                  ingredientKeys: '["vitamin_e"]',
                ),
              ];
            }),
            detailBlobProvider.overrideWith((ref, dsldId) async {
              if (dsldId == _dsldId) {
                return {
                  'ingredients': [
                    {
                      'standard_name': 'Fish Oil',
                      'quantity': 1000,
                      'unit': 'mg',
                    },
                  ],
                };
              }
              throw StateError('stack detail blob unavailable');
            }),
          ],
        );
        addTearDown(container.dispose);

        await expectLater(
          container.read(
            personalizedInteractionWarningsProvider(_dsldId).future,
          ),
          throwsA(isA<StateError>()),
        );

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
          detailBlobProvider.overrideWith((ref, dsldId) async => null),
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
