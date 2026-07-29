// FIX 1 — the pre-add "Safe to add" sheet must not be medication-blind.
//
// `safetyCheckForAddProvider` now mirrors `stackSafetyReportProvider`:
// curated supplement×supplement + medication×supplement lookups plus the
// legacy fingerprint heuristic, wrapped in a [PreAddSafetyResult] that
// carries a `checksIncomplete` hedge so an empty result under a failed
// check never reads as a clean "Safe to add".

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/interaction_result.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/interaction_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/data/providers/detail_blob_provider.dart';
import 'package:pharmaguide/features/stack/providers/stack_safety_providers.dart';

Future<void> _seedSupplement(
  CoreDatabase coreDb, {
  required String dsldId,
  required String name,
  required List<String> canonicalTags,
}) async {
  final tagsJson = '[${canonicalTags.map((t) => '"$t"').join(',')}]';
  await coreDb
      .into(coreDb.productsCore)
      .insert(
        ProductsCoreCompanion.insert(
          dsldId: dsldId,
          productName: name,
          productStatus: const Value('active'),
          keyIngredientTags: Value(tagsJson),
          exportVersion: 'test',
          exportedAt: '2026-07-05T00:00:00Z',
        ),
      );
}

Future<void> _seedWarfarinGinkgoDdi(InteractionDatabase db) async {
  await db
      .into(db.interactions)
      .insert(
        InteractionsCompanion.insert(
          id: 'DDI_WARFARIN_GINKGO',
          agent1Type: 'drug',
          agent1Name: 'Warfarin',
          agent1Id: '11289',
          agent2Type: 'supplement',
          agent2Name: 'Ginkgo',
          agent2Id: 'umls:ginkgo',
          agent2CanonicalId: const Value('ginkgo'),
          severity: 'avoid',
          mechanism: 'Ginkgo may potentiate anticoagulant bleeding risk.',
          management: 'Avoid combining without clinician oversight.',
          evidenceLevel: const Value('established'),
          sourceUrlsJson: '[]',
          sourcePmidsJson: '[]',
          typeAuthored: 'drug_supplement',
          source: 'curated',
          provenance: 'fixture',
          versionAdded: 'test',
          versionLastModified: 'test',
          lastUpdated: '2026-07-05',
        ),
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
          provenance: 'fixture',
          versionAdded: 'test',
          versionLastModified: 'test',
          lastUpdated: '2026-07-08',
        ),
      );
}

Future<void> _seedMedication(
  UserDatabase userDb, {
  required String id,
  required String name,
  required String rxcui,
  String? drugClasses,
}) async {
  await userDb.addToStack(
    UserStacksLocalCompanion.insert(
      id: id,
      name: name,
      type: const Value('medication'),
      rxcui: Value(rxcui),
      drugClassesCol: Value(drugClasses),
    ),
  );
}

ProviderContainer _container({
  required CoreDatabase coreDb,
  required InteractionDatabase interactionDb,
  required UserDatabase userDb,
}) {
  return ProviderContainer(
    overrides: [
      coreDatabaseProvider.overrideWithValue(coreDb),
      interactionDatabaseProvider.overrideWithValue(interactionDb),
      userDatabaseProvider.overrideWithValue(userDb),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('safetyCheckForAddProvider — medication interactions', () {
    test('warfarin med + ginkgo candidate surfaces the curated DDI', () async {
      final coreDb = CoreDatabase.memory();
      final interactionDb = InteractionDatabase.memory();
      final userDb = UserDatabase.memory();
      addTearDown(() async {
        await coreDb.close();
        await interactionDb.close();
        await userDb.close();
      });

      await _seedSupplement(
        coreDb,
        dsldId: 'SUPP_GINKGO',
        name: 'Ginkgo Biloba',
        canonicalTags: ['ginkgo'],
      );
      await _seedWarfarinGinkgoDdi(interactionDb);
      // Warfarin with a resolvable drug class so normalization does NOT
      // mark the result incomplete — the only reason to warn is the DDI.
      await _seedMedication(
        userDb,
        id: 'med_warfarin',
        name: 'Warfarin',
        rxcui: '11289',
        drugClasses: '["class:anticoagulants"]',
      );

      final container = _container(
        coreDb: coreDb,
        interactionDb: interactionDb,
        userDb: userDb,
      );
      addTearDown(container.dispose);

      final result = await container.read(
        safetyCheckForAddProvider('SUPP_GINKGO').future,
      );

      expect(result.results, isNotEmpty);
      expect(result.results.any((r) => r.id == 'DDI_WARFARIN_GINKGO'), isTrue);
      // A real interaction was found → the sheet must not affirm "Safe to add".
      expect(result.isConfidentClear, isFalse);
    });

    test(
      'unresolvable medication with no interaction hit marks checks incomplete',
      () async {
        final coreDb = CoreDatabase.memory();
        final interactionDb = InteractionDatabase.memory();
        final userDb = UserDatabase.memory();
        addTearDown(() async {
          await coreDb.close();
          await interactionDb.close();
          await userDb.close();
        });

        // Candidate has canonical ids but there is NO curated row for it.
        await _seedSupplement(
          coreDb,
          dsldId: 'SUPP_VIT_C',
          name: 'Vitamin C',
          canonicalTags: ['vitamin_c'],
        );
        // Advil brand RxCUI with no drug classes → bridge resolves nothing →
        // its class-level checks cannot run → result must hedge.
        await _seedMedication(
          userDb,
          id: 'med_advil',
          name: 'Advil',
          rxcui: '153010',
        );

        final container = _container(
          coreDb: coreDb,
          interactionDb: interactionDb,
          userDb: userDb,
        );
        addTearDown(container.dispose);

        final result = await container.read(
          safetyCheckForAddProvider('SUPP_VIT_C').future,
        );

        expect(result.results, isEmpty);
        expect(result.checksIncomplete, isTrue);
        // Empty results but incomplete → NOT an affirmative clean bill.
        expect(result.isConfidentClear, isFalse);
      },
    );

    test('empty stack is a confident clear (safe to affirm)', () async {
      final coreDb = CoreDatabase.memory();
      final interactionDb = InteractionDatabase.memory();
      final userDb = UserDatabase.memory();
      addTearDown(() async {
        await coreDb.close();
        await interactionDb.close();
        await userDb.close();
      });

      await _seedSupplement(
        coreDb,
        dsldId: 'SUPP_GINKGO',
        name: 'Ginkgo Biloba',
        canonicalTags: ['ginkgo'],
      );

      final container = _container(
        coreDb: coreDb,
        interactionDb: interactionDb,
        userDb: userDb,
      );
      addTearDown(container.dispose);

      final result = await container.read(
        safetyCheckForAddProvider('SUPP_GINKGO').future,
      );

      expect(result.results, isEmpty);
      expect(result.checksIncomplete, isFalse);
      expect(result.isConfidentClear, isTrue);
    });

    test(
      'fish oil candidate plus ordinary multivitamin vitamin E stays clear',
      () async {
        final coreDb = CoreDatabase.memory();
        final interactionDb = InteractionDatabase.memory();
        final userDb = UserDatabase.memory();
        addTearDown(() async {
          await coreDb.close();
          await interactionDb.close();
          await userDb.close();
        });

        await _seedSupplement(
          coreDb,
          dsldId: 'SUPP_FISH_OIL',
          name: 'Fish Oil',
          canonicalTags: ['fish_oil'],
        );
        await _seedSupplement(
          coreDb,
          dsldId: 'SUPP_ONE_MULTI',
          name: 'O.N.E. Multivitamin',
          canonicalTags: ['vitamin_e'],
        );
        await _seedFishOilVitaminEPair(interactionDb);
        await userDb.addToStack(
          UserStacksLocalCompanion.insert(
            id: 'one_multi',
            type: const Value('supplement'),
            name: 'O.N.E. Multivitamin',
            dsldId: const Value('SUPP_ONE_MULTI'),
            ingredientKeys: const Value('["vitamin_e"]'),
          ),
        );

        final container = ProviderContainer(
          overrides: [
            coreDatabaseProvider.overrideWithValue(coreDb),
            interactionDatabaseProvider.overrideWithValue(interactionDb),
            userDatabaseProvider.overrideWithValue(userDb),
            detailBlobProvider.overrideWith((ref, dsldId) async {
              if (dsldId == 'SUPP_FISH_OIL') {
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
              if (dsldId == 'SUPP_ONE_MULTI') {
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
          safetyCheckForAddProvider('SUPP_FISH_OIL').future,
        );

        expect(result.results, isEmpty);
        expect(result.isConfidentClear, isTrue);
      },
    );

    test(
      'missing dose blob marks dose-dependent interaction checks incomplete',
      () async {
        final coreDb = CoreDatabase.memory();
        final interactionDb = InteractionDatabase.memory();
        final userDb = UserDatabase.memory();
        addTearDown(() async {
          await coreDb.close();
          await interactionDb.close();
          await userDb.close();
        });

        await _seedSupplement(
          coreDb,
          dsldId: 'SUPP_FISH_OIL',
          name: 'Fish Oil',
          canonicalTags: ['fish_oil'],
        );
        await _seedSupplement(
          coreDb,
          dsldId: 'SUPP_ONE_MULTI',
          name: 'O.N.E. Multivitamin',
          canonicalTags: ['vitamin_e'],
        );
        await _seedFishOilVitaminEPair(interactionDb);
        await userDb.addToStack(
          UserStacksLocalCompanion.insert(
            id: 'one_multi',
            type: const Value('supplement'),
            name: 'O.N.E. Multivitamin',
            dsldId: const Value('SUPP_ONE_MULTI'),
          ),
        );

        final container = ProviderContainer(
          overrides: [
            coreDatabaseProvider.overrideWithValue(coreDb),
            interactionDatabaseProvider.overrideWithValue(interactionDb),
            userDatabaseProvider.overrideWithValue(userDb),
            detailBlobProvider.overrideWith((ref, dsldId) async => null),
          ],
        );
        addTearDown(container.dispose);

        final result = await container.read(
          safetyCheckForAddProvider('SUPP_FISH_OIL').future,
        );

        expect(result.results, isEmpty);
        expect(result.checksIncomplete, isTrue);
        expect(result.isConfidentClear, isFalse);
      },
    );
  });

  group('PreAddSafetyResult.isConfidentClear — pure decision', () {
    InteractionResult sampleResult() => const InteractionResult(
      id: 'X',
      type: InteractionType.drugSupplement,
      severity: Severity.avoid,
      evidenceLevel: EvidenceLevel.established,
      agent1Name: 'A',
      agent2Name: 'B',
      mechanism: 'm',
      management: 'g',
      doseDependant: false,
      doseThreshold: null,
      sourceUrls: [],
      source: InteractionSource.pipeline,
    );

    test('empty + complete → confident clear (green allowed)', () {
      const r = PreAddSafetyResult(results: [], checksIncomplete: false);
      expect(r.isConfidentClear, isTrue);
    });

    test('empty + incomplete → NOT clear (must hedge)', () {
      const r = PreAddSafetyResult(results: [], checksIncomplete: true);
      expect(r.isConfidentClear, isFalse);
    });

    test('non-empty → NOT clear regardless of incomplete flag', () {
      final r = PreAddSafetyResult(
        results: [sampleResult()],
        checksIncomplete: false,
      );
      expect(r.isConfidentClear, isFalse);
    });
  });
}
