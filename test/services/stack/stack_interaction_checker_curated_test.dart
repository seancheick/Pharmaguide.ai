import 'dart:convert';
import 'package:pharmaguide/services/stack/medication_profile_gate_evaluator.dart';
// Tests for the M4 curated-DB lookup methods on
// [StackInteractionChecker]:
//
//   - checkSupplementPairInteractions
//   - checkMedicationInteractions
//
// These exercise the bridge between the bundled M2 interaction DB and
// the user's stack. They run against an in-memory [InteractionDatabase]
// with hand-built fixture rows so the assertions don't drift when the
// pipeline curates new entries.
//
// Spec §8.6 done gate: ≥15 tests per checker method.
//
// Run:
//   flutter test test/services/stack/stack_interaction_checker_curated_test.dart

import 'package:drift/drift.dart' as drift;
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/interaction_result.dart';
import 'package:pharmaguide/data/database/interaction_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/services/stack/stack_dose_summer.dart';
import 'package:pharmaguide/services/stack/stack_interaction_checker.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';

// ---------------------------------------------------------------------------
// Fixture row builders.
//
// All rows ship `version_added`, `version_last_modified`, `last_updated`
// with the same dummy timestamp — these are required NOT NULL columns
// the pipeline always populates. We never hit them in assertions.
// ---------------------------------------------------------------------------

const _ts = '2026-04-11T00:00:00Z';

InteractionsCompanion _row({
  required String id,
  required String a1Type,
  required String a1Id,
  required String a1Name,
  String? a1Canonical,
  String? a1Class,
  required String a2Type,
  required String a2Id,
  required String a2Name,
  String? a2Canonical,
  String? a2Class,
  String severity = 'caution',
  String? effectType,
  String mechanism = 'Test mechanism',
  String management = 'Test management',
  String evidenceLevel = 'established',
  String sourceUrlsJson = '["https://example.org/test"]',
  int doseDependent = 0,
  String? direction,
  String? materiality,
  String? doseThresholdJson,
  String? retiredAt,
  String? alertStyle,
  String? noteBody,
  String? practicalGuidance,
  String? profileGateJson,
  String? medicationExceptionsJson,
  String typeAuthored = 'curated',
}) {
  return InteractionsCompanion.insert(
    id: id,
    agent1Type: a1Type,
    agent1Name: a1Name,
    agent1Id: a1Id,
    agent1CanonicalId: a1Canonical == null
        ? const drift.Value.absent()
        : drift.Value(a1Canonical),
    agent1DrugClass: a1Class == null
        ? const drift.Value.absent()
        : drift.Value(a1Class),
    agent2Type: a2Type,
    agent2Name: a2Name,
    agent2Id: a2Id,
    agent2CanonicalId: a2Canonical == null
        ? const drift.Value.absent()
        : drift.Value(a2Canonical),
    agent2DrugClass: a2Class == null
        ? const drift.Value.absent()
        : drift.Value(a2Class),
    severity: severity,
    effectType: effectType == null
        ? const drift.Value.absent()
        : drift.Value(effectType),
    mechanism: mechanism,
    management: management,
    evidenceLevel: drift.Value(evidenceLevel),
    sourceUrlsJson: sourceUrlsJson,
    sourcePmidsJson: '[]',
    doseDependent: drift.Value(doseDependent),
    direction: direction == null
        ? const drift.Value.absent()
        : drift.Value(direction),
    materiality: materiality == null
        ? const drift.Value.absent()
        : drift.Value(materiality),
    doseThresholdJson: doseThresholdJson == null
        ? const drift.Value.absent()
        : drift.Value(doseThresholdJson),
    retiredAt: retiredAt == null
        ? const drift.Value.absent()
        : drift.Value(retiredAt),
    alertStyle: alertStyle == null
        ? const drift.Value.absent()
        : drift.Value(alertStyle),
    noteBody: noteBody == null
        ? const drift.Value.absent()
        : drift.Value(noteBody),
    practicalGuidance: practicalGuidance == null
        ? const drift.Value.absent()
        : drift.Value(practicalGuidance),
    profileGateJson: drift.Value(profileGateJson),
    medicationExceptionsJson: drift.Value(medicationExceptionsJson),
    typeAuthored: typeAuthored,
    source: 'curated',
    provenance: 'test',
    versionAdded: '1.0.0',
    versionLastModified: '1.0.0',
    lastUpdated: _ts,
  );
}

UserStacksLocalData _supplement({
  required String id,
  required String name,
  String? ingredientKeys,
}) {
  final now = DateTime.utc(2026, 4, 11);
  return UserStacksLocalData(
    id: id,
    type: 'supplement',
    name: name,
    ingredientKeys: ingredientKeys,
    addedAt: now,
    clientUpdatedAt: now,
  );
}

UserStacksLocalData _medication({
  required String id,
  required String name,
  String? rxcui,
  String? genericRxcui,
  List<String> ingredientRxcuis = const <String>[],
  String? drugClassesJson,
}) {
  final now = DateTime.utc(2026, 4, 11);
  return UserStacksLocalData(
    id: id,
    type: 'medication',
    name: name,
    rxcui: rxcui,
    genericRxcui: genericRxcui,
    ingredientRxcuisCol: ingredientRxcuis.isEmpty
        ? null
        : '[${ingredientRxcuis.map((e) => '"$e"').join(',')}]',
    drugClassesCol: drugClassesJson,
    addedAt: now,
    clientUpdatedAt: now,
  );
}

/// A `drug_class_map` row: the class membership a direct pair is checked against.
DrugClassMapCompanion _classMembers(String classId, List<String> rxcuis) =>
    DrugClassMapCompanion.insert(
      classId: classId,
      className: classId,
      drugRxcuisJson: '[${rxcuis.map((e) => '"$e"').join(',')}]',
      source: 'fixture',
      lastUpdated: '2026-11-11',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InteractionDatabase db;
  late StackInteractionChecker checker;

  setUp(() async {
    db = InteractionDatabase.memory();
    checker = StackInteractionChecker();

    await db.batch((b) {
      // sup ↔ sup: calcium ↔ iron (canonical ids on both sides).
      b.insert(
        db.interactions,
        _row(
          id: 'DDI_IRON_CALCIUM',
          a1Type: 'supplement',
          a1Id: 'C0006675',
          a1Name: 'Calcium',
          a1Canonical: 'calcium',
          a2Type: 'supplement',
          a2Id: 'C0302583',
          a2Name: 'Iron',
          a2Canonical: 'iron',
          severity: 'caution',
          effectType: 'inhibitor',
        ),
      );
      // sup ↔ sup: zinc ↔ copper, slot order intentionally reversed
      // to test direction-agnostic lookup.
      b.insert(
        db.interactions,
        _row(
          id: 'DDI_ZINC_COPPER',
          a1Type: 'supplement',
          a1Id: 'C0011336',
          a1Name: 'Copper',
          a1Canonical: 'copper',
          a2Type: 'supplement',
          a2Id: 'C0043481',
          a2Name: 'Zinc',
          a2Canonical: 'zinc',
          severity: 'monitor',
        ),
      );
      // drug ↔ supplement: warfarin RXCUI ↔ vitamin K.
      b.insert(
        db.interactions,
        _row(
          id: 'DDI_WARFARIN_VITK',
          a1Type: 'drug',
          a1Id: '11289',
          a1Name: 'Warfarin',
          a2Type: 'supplement',
          a2Id: 'C0042847',
          a2Name: 'Vitamin K',
          a2Canonical: 'vitamin_k',
          severity: 'avoid',
          effectType: 'inhibitor',
        ),
      );
      // drug_class ↔ supplement: ACE inhibitors ↔ potassium.
      b.insert(
        db.interactions,
        _row(
          id: 'DDI_ACE_POTASSIUM',
          a1Type: 'drug_class',
          a1Id: 'class:ace_inhibitors',
          a1Name: 'ACE inhibitors',
          a2Type: 'supplement',
          a2Id: 'C0032821',
          a2Name: 'Potassium',
          a2Canonical: 'potassium',
          severity: 'avoid',
        ),
      );
      // drug_class ↔ supplement: SSRIs ↔ St. John's wort, slot order
      // reversed (supplement is agent1, class is agent2) to test
      // direction-agnostic class lookup.
      b.insert(
        db.interactions,
        _row(
          id: 'DDI_SSRI_SJW',
          a1Type: 'supplement',
          a1Id: 'C0085175',
          a1Name: 'St. Johns Wort',
          a1Canonical: 'st_johns_wort',
          a2Type: 'drug_class',
          a2Id: 'class:ssris',
          a2Name: 'SSRIs',
          severity: 'contraindicated',
        ),
      );
      // drug_class ↔ drug_class: MAOIs ↔ CNS stimulants.
      b.insert(
        db.interactions,
        _row(
          id: 'DDI_MAOI_STIMULANTS',
          a1Type: 'drug_class',
          a1Id: 'class:maois',
          a1Name: 'MAOIs',
          a2Type: 'drug_class',
          a2Id: 'class:stimulants',
          a2Name: 'CNS stimulants',
          severity: 'contraindicated',
        ),
      );
      // Tombstoned row that must NEVER appear in results.
      b.insert(
        db.interactions,
        _row(
          id: 'DDI_RETIRED_FAKE',
          a1Type: 'supplement',
          a1Id: 'C0000001',
          a1Name: 'Fake',
          a1Canonical: 'fake_supp',
          a2Type: 'supplement',
          a2Id: 'C0000002',
          a2Name: 'Other Fake',
          a2Canonical: 'other_fake',
          severity: 'avoid',
          retiredAt: '2025-01-01T00:00:00Z',
        ),
      );
      b.insert(
        db.interactions,
        _row(
          id: 'DSI_LEVOTHYROXINE_COFFEE',
          a1Type: 'drug',
          a1Id: '10582',
          a1Name: 'Levothyroxine',
          a2Type: 'food',
          a2Id: 'food:coffee',
          a2Name: 'Coffee',
          severity: 'monitor',
          alertStyle: 'food_advisory_note',
          noteBody:
              'Coffee can reduce how much levothyroxine your body absorbs.',
          practicalGuidance:
              'Take levothyroxine with water and wait before coffee.',
        ),
      );
      b.insert(
        db.interactions,
        _row(
          id: 'DSI_STATINS_GRAPEFRUIT',
          a1Type: 'drug_class',
          a1Id: 'class:statins',
          a1Name: 'Statins',
          a2Type: 'food',
          a2Id: 'food:grapefruit',
          a2Name: 'Grapefruit',
          severity: 'avoid',
          alertStyle: 'food_advisory_note',
          noteBody: 'Grapefruit can raise levels of some statins.',
          practicalGuidance: 'Skip grapefruit or ask about another statin.',
        ),
      );
    });
  });

  tearDown(() async {
    await db.close();
  });

  // -------------------------------------------------------------------------
  // checkSupplementPairInteractions
  // -------------------------------------------------------------------------
  group('checkSupplementPairInteractions', () {
    test('returns empty for empty new product canonical ids', () async {
      final results = await checker.checkSupplementPairInteractions(
        newProductCanonicalIds: const <String>[],
        stackSupplements: [
          _supplement(id: 'u1', name: 'Iron 30mg', ingredientKeys: '["iron"]'),
        ],
        db: db,
      );
      expect(results, isEmpty);
    });

    test(
      'legacy structured ingredient_keys object still yields canonical ids',
      () async {
        final results = await checker.checkSupplementPairInteractions(
          newProductCanonicalIds: const <String>['calcium'],
          stackSupplements: [
            _supplement(
              id: 'legacy_iron',
              name: 'Legacy Iron',
              ingredientKeys:
                  '{"nutrients":{"iron":{}},"herbs":[],"categories":["minerals"],'
                  '"pharmacological_flags":{"stimulant":false}}',
            ),
          ],
          db: db,
          newProductName: 'Calcium',
        );

        expect(results, hasLength(1));
        expect(results.first.id, 'DDI_IRON_CALCIUM');
        expect(results.first.severity, Severity.caution);
      },
    );

    test(
      'legacy structured herb names are canonicalized before interaction lookup',
      () async {
        await db
            .into(db.interactions)
            .insert(
              _row(
                id: 'DDI_CALCIUM_SJW_LEGACY',
                a1Type: 'supplement',
                a1Id: 'C0006675',
                a1Name: 'Calcium',
                a1Canonical: 'calcium',
                a2Type: 'supplement',
                a2Id: 'C0085175',
                a2Name: 'St. Johns Wort',
                a2Canonical: 'st_johns_wort',
                severity: 'avoid',
              ),
            );

        final results = await checker.checkSupplementPairInteractions(
          newProductCanonicalIds: const <String>['calcium'],
          stackSupplements: [
            _supplement(
              id: 'legacy_sjw',
              name: 'Legacy St. John\'s Wort',
              ingredientKeys:
                  '{"nutrients":{},"herbs":["St. John\\u0027s Wort"],'
                  '"categories":["herbs"],"pharmacological_flags":{}}',
            ),
          ],
          db: db,
          newProductName: 'Calcium',
        );

        expect(results, hasLength(1));
        expect(results.single.id, 'DDI_CALCIUM_SJW_LEGACY');
        expect(results.single.severity, Severity.avoid);
      },
    );

    test('returns empty for empty stack', () async {
      final results = await checker.checkSupplementPairInteractions(
        newProductCanonicalIds: const ['calcium'],
        stackSupplements: const <UserStacksLocalData>[],
        db: db,
      );
      expect(results, isEmpty);
    });

    test('finds calcium ↔ iron in canonical row order', () async {
      final results = await checker.checkSupplementPairInteractions(
        newProductCanonicalIds: const ['calcium'],
        stackSupplements: [
          _supplement(id: 'u1', name: 'Iron 30mg', ingredientKeys: '["iron"]'),
        ],
        db: db,
        newProductName: 'Cal-Mag Complex',
      );
      expect(results, hasLength(1));
      expect(results.single.id, 'DDI_IRON_CALCIUM');
      expect(results.single.severity, Severity.caution);
      expect(results.single.type, InteractionType.supplementSupplement);
      expect(results.single.source, InteractionSource.pipeline);
    });

    test(
      'suppresses a dose-dependent pair below its structured threshold',
      () async {
        await db
            .into(db.interactions)
            .insert(
              _row(
                id: 'SSI_VITE_VITK_LOW_TEST',
                a1Type: 'supplement',
                a1Id: 'C0016157',
                a1Name: 'Fish Oil',
                a1Canonical: 'fish_oil',
                a2Type: 'supplement',
                a2Id: 'C0042874',
                a2Name: 'Vitamin E',
                a2Canonical: 'vitamin_e',
                doseDependent: 1,
                direction: 'harmful',
                materiality: 'dose_dependent',
                doseThresholdJson:
                    '{"agent_canonical_id":"vitamin_e","value":180,"unit":"mg","basis":"per_day"}',
              ),
            );

        final doseTotals = const StackDoseSummer().sum([
          const StackItemNutrients(
            stackEntryId: 'fish_oil',
            productName: 'Fish Oil',
            ingredients: [
              {'standard_name': 'Fish Oil', 'quantity': 1000, 'unit': 'mg'},
            ],
          ),
          const StackItemNutrients(
            stackEntryId: 'one_multi',
            productName: 'O.N.E. Multivitamin',
            ingredients: [
              {'standard_name': 'Vitamin E', 'quantity': 20, 'unit': 'mg'},
            ],
          ),
        ]);

        final results = await checker.checkSupplementPairInteractions(
          newProductCanonicalIds: const ['fish_oil'],
          stackSupplements: [
            _supplement(
              id: 'one_multi',
              name: 'O.N.E. Multivitamin',
              ingredientKeys: '["vitamin_e"]',
            ),
          ],
          db: db,
          newProductName: 'Fish Oil',
          stackDoseTotals: doseTotals,
        );

        expect(results, isEmpty);
      },
    );

    test(
      'keeps a dose-dependent pair at or above its structured threshold',
      () async {
        await db
            .into(db.interactions)
            .insert(
              _row(
                id: 'SSI_VITE_VITK_THRESHOLD_TEST',
                a1Type: 'supplement',
                a1Id: 'C0016157',
                a1Name: 'Fish Oil',
                a1Canonical: 'fish_oil',
                a2Type: 'supplement',
                a2Id: 'C0042874',
                a2Name: 'Vitamin E',
                a2Canonical: 'vitamin_e',
                doseDependent: 1,
                direction: 'harmful',
                materiality: 'dose_dependent',
                doseThresholdJson:
                    '{"agent_canonical_id":"vitamin_e","value":180,"unit":"mg","basis":"per_day"}',
              ),
            );

        final doseTotals = const StackDoseSummer().sum([
          const StackItemNutrients(
            stackEntryId: 'fish_oil',
            productName: 'Fish Oil',
            ingredients: [
              {'standard_name': 'Fish Oil', 'quantity': 1000, 'unit': 'mg'},
            ],
          ),
          const StackItemNutrients(
            stackEntryId: 'vitamin_e_high',
            productName: 'Vitamin E 180 mg',
            ingredients: [
              {'standard_name': 'Vitamin E', 'quantity': 180, 'unit': 'mg'},
            ],
          ),
        ]);

        final results = await checker.checkSupplementPairInteractions(
          newProductCanonicalIds: const ['fish_oil'],
          stackSupplements: [
            _supplement(
              id: 'vitamin_e_high',
              name: 'Vitamin E 180 mg',
              ingredientKeys: '["vitamin_e"]',
            ),
          ],
          db: db,
          newProductName: 'Fish Oil',
          stackDoseTotals: doseTotals,
        );

        expect(results, hasLength(1));
        expect(results.single.id, 'SSI_VITE_VITK_THRESHOLD_TEST');
      },
    );

    test(
      'suppresses a future pipeline-normalized pairwise mass threshold',
      () async {
        await db
            .into(db.interactions)
            .insert(
              _row(
                id: 'DSI_FISHOIL_VITE_MG_TEST',
                a1Type: 'supplement',
                a1Id: 'C0016157',
                a1Name: 'Fish Oil',
                a1Canonical: 'fish_oil',
                a2Type: 'supplement',
                a2Id: 'C0042874',
                a2Name: 'Vitamin E',
                a2Canonical: 'vitamin_e',
                doseDependent: 1,
                direction: 'harmful',
                materiality: 'dose_dependent',
                doseThresholdJson:
                    '{"agent_canonical_id":"vitamin_e","value":180,"unit":"mg","basis":"per_day"}',
              ),
            );

        final doseTotals = const StackDoseSummer().sum([
          const StackItemNutrients(
            stackEntryId: 'fish_oil',
            productName: 'Fish Oil',
            ingredients: [
              {'standard_name': 'Fish Oil', 'quantity': 1000, 'unit': 'mg'},
            ],
          ),
          const StackItemNutrients(
            stackEntryId: 'one_multi',
            productName: 'O.N.E. Multivitamin',
            ingredients: [
              {'standard_name': 'Vitamin E', 'quantity': 20, 'unit': 'mg'},
            ],
          ),
        ]);

        final results = await checker.checkSupplementPairInteractions(
          newProductCanonicalIds: const ['fish_oil'],
          stackSupplements: [
            _supplement(
              id: 'one_multi',
              name: 'O.N.E. Multivitamin',
              ingredientKeys: '["vitamin_e"]',
            ),
          ],
          db: db,
          newProductName: 'Fish Oil',
          stackDoseTotals: doseTotals,
        );

        expect(results, isEmpty);
      },
    );

    test('fails open when structured pairwise dose context is missing', () async {
      await db
          .into(db.interactions)
          .insert(
            _row(
              id: 'DSI_FISHOIL_VITE_FAIL_OPEN_TEST',
              a1Type: 'supplement',
              a1Id: 'C0016157',
              a1Name: 'Fish Oil',
              a1Canonical: 'fish_oil',
              a2Type: 'supplement',
              a2Id: 'C0042874',
              a2Name: 'Vitamin E',
              a2Canonical: 'vitamin_e',
              doseDependent: 1,
              direction: 'harmful',
              materiality: 'dose_dependent',
              doseThresholdJson:
                  '{"agent_canonical_id":"vitamin_e","value":400,"unit":"IU","basis":"per_day"}',
            ),
          );

      final results = await checker.checkSupplementPairInteractions(
        newProductCanonicalIds: const ['fish_oil'],
        stackSupplements: [
          _supplement(
            id: 'one_multi',
            name: 'O.N.E. Multivitamin',
            ingredientKeys: '["vitamin_e"]',
          ),
        ],
        db: db,
        newProductName: 'Fish Oil',
      );

      expect(results, hasLength(1));
      expect(results.single.id, 'DSI_FISHOIL_VITE_FAIL_OPEN_TEST');
    });

    test(
      'NEVER dose-suppresses a hard (contraindicated) pair below threshold',
      () async {
        // Defense-in-depth (mirrors the condition floor gate's G3): a hard
        // warning is NEVER dropped for being below a dose floor. Even a
        // dose-dependent contraindicated row with a 20 mg (< 400 IU) vitamin E
        // must still surface.
        await db
            .into(db.interactions)
            .insert(
              _row(
                id: 'DSI_HARD_DOSE_DEP_TEST',
                a1Type: 'supplement',
                a1Id: 'C0016157',
                a1Name: 'Fish Oil',
                a1Canonical: 'fish_oil',
                a2Type: 'supplement',
                a2Id: 'C0042874',
                a2Name: 'Vitamin E',
                a2Canonical: 'vitamin_e',
                severity: 'contraindicated',
                doseDependent: 1,
                direction: 'harmful',
                materiality: 'dose_dependent',
                doseThresholdJson:
                    '{"agent_canonical_id":"vitamin_e","value":400,"unit":"IU","basis":"per_day"}',
              ),
            );

        final doseTotals = const StackDoseSummer().sum([
          const StackItemNutrients(
            stackEntryId: 'fish_oil',
            productName: 'Fish Oil',
            ingredients: [
              {'standard_name': 'Fish Oil', 'quantity': 1000, 'unit': 'mg'},
            ],
          ),
          const StackItemNutrients(
            stackEntryId: 'one_multi',
            productName: 'O.N.E. Multivitamin',
            ingredients: [
              {'standard_name': 'Vitamin E', 'quantity': 20, 'unit': 'mg'},
            ],
          ),
        ]);

        final results = await checker.checkSupplementPairInteractions(
          newProductCanonicalIds: const ['fish_oil'],
          stackSupplements: [
            _supplement(
              id: 'one_multi',
              name: 'O.N.E. Multivitamin',
              ingredientKeys: '["vitamin_e"]',
            ),
          ],
          db: db,
          newProductName: 'Fish Oil',
          stackDoseTotals: doseTotals,
        );

        expect(results, hasLength(1));
        expect(results.single.id, 'DSI_HARD_DOSE_DEP_TEST');
      },
    );

    test(
      'NEVER dose-suppresses a pair with an unknown / drifted severity token',
      () async {
        // Severity.fromString coerces "severe" → caution (suppressible); the
        // raw-string fail-safe must keep the row visible below threshold so a
        // future OTA severity-vocab drift can't silently hide a serious pair.
        await db
            .into(db.interactions)
            .insert(
              _row(
                id: 'DSI_UNKNOWN_SEV_TEST',
                a1Type: 'supplement',
                a1Id: 'C0016157',
                a1Name: 'Fish Oil',
                a1Canonical: 'fish_oil',
                a2Type: 'supplement',
                a2Id: 'C0042874',
                a2Name: 'Vitamin E',
                a2Canonical: 'vitamin_e',
                severity: 'severe',
                doseDependent: 1,
                direction: 'harmful',
                materiality: 'dose_dependent',
                doseThresholdJson:
                    '{"agent_canonical_id":"vitamin_e","value":400,"unit":"IU","basis":"per_day"}',
              ),
            );

        final doseTotals = const StackDoseSummer().sum([
          const StackItemNutrients(
            stackEntryId: 'fish_oil',
            productName: 'Fish Oil',
            ingredients: [
              {'standard_name': 'Fish Oil', 'quantity': 1000, 'unit': 'mg'},
            ],
          ),
          const StackItemNutrients(
            stackEntryId: 'one_multi',
            productName: 'O.N.E. Multivitamin',
            ingredients: [
              {'standard_name': 'Vitamin E', 'quantity': 20, 'unit': 'mg'},
            ],
          ),
        ]);

        final results = await checker.checkSupplementPairInteractions(
          newProductCanonicalIds: const ['fish_oil'],
          stackSupplements: [
            _supplement(
              id: 'one_multi',
              name: 'O.N.E. Multivitamin',
              ingredientKeys: '["vitamin_e"]',
            ),
          ],
          db: db,
          newProductName: 'Fish Oil',
          stackDoseTotals: doseTotals,
        );

        expect(results, hasLength(1));
        expect(results.single.id, 'DSI_UNKNOWN_SEV_TEST');
      },
    );

    test(
      'fails open when the vitamin E total dropped a mismatched-unit source',
      () async {
        // Stack holds vitamin E in BOTH mg and IU: sum() excludes the
        // non-anchor unit as a conflict, so the total is an undercount. An
        // undercount must NOT justify suppressing the bleeding warning below
        // the floor — the true combined dose could be over it.
        await db
            .into(db.interactions)
            .insert(
              _row(
                id: 'DSI_FISHOIL_VITE_MIXED_UNIT_TEST',
                a1Type: 'supplement',
                a1Id: 'C0016157',
                a1Name: 'Fish Oil',
                a1Canonical: 'fish_oil',
                a2Type: 'supplement',
                a2Id: 'C0042874',
                a2Name: 'Vitamin E',
                a2Canonical: 'vitamin_e',
                severity: 'caution',
                doseDependent: 1,
                direction: 'harmful',
                materiality: 'dose_dependent',
                doseThresholdJson:
                    '{"agent_canonical_id":"vitamin_e","value":400,"unit":"IU","basis":"per_day"}',
              ),
            );

        final doseTotals = const StackDoseSummer().sum([
          const StackItemNutrients(
            stackEntryId: 'fish_oil',
            productName: 'Fish Oil',
            ingredients: [
              {'standard_name': 'Fish Oil', 'quantity': 1000, 'unit': 'mg'},
            ],
          ),
          const StackItemNutrients(
            stackEntryId: 'multi_mg',
            productName: 'Multivitamin',
            ingredients: [
              {'standard_name': 'Vitamin E', 'quantity': 20, 'unit': 'mg'},
            ],
          ),
          const StackItemNutrients(
            stackEntryId: 'vite_iu',
            productName: 'Vitamin E 300 IU',
            ingredients: [
              {'standard_name': 'Vitamin E', 'quantity': 300, 'unit': 'IU'},
            ],
          ),
        ]);

        final results = await checker.checkSupplementPairInteractions(
          newProductCanonicalIds: const ['fish_oil'],
          stackSupplements: [
            _supplement(
              id: 'multi_mg',
              name: 'Multivitamin',
              ingredientKeys: '["vitamin_e"]',
            ),
            _supplement(
              id: 'vite_iu',
              name: 'Vitamin E 300 IU',
              ingredientKeys: '["vitamin_e"]',
            ),
          ],
          db: db,
          newProductName: 'Fish Oil',
          stackDoseTotals: doseTotals,
        );

        expect(results, hasLength(1));
        expect(results.single.id, 'DSI_FISHOIL_VITE_MIXED_UNIT_TEST');
      },
    );

    test('finds calcium ↔ iron in reverse direction', () async {
      // New product is iron, stack supplement is calcium — pipeline
      // stored row as (calcium, iron), the symmetric lookup must still
      // hit it.
      final results = await checker.checkSupplementPairInteractions(
        newProductCanonicalIds: const ['iron'],
        stackSupplements: [
          _supplement(
            id: 'u1',
            name: 'Calcium Citrate',
            ingredientKeys: '["calcium"]',
          ),
        ],
        db: db,
      );
      expect(results, hasLength(1));
      expect(results.single.id, 'DDI_IRON_CALCIUM');
    });

    test('dedupes when multiple new ingredients hit same row', () async {
      // calcium AND iron in the new product would each separately hit
      // DDI_IRON_CALCIUM via the stack — must surface once.
      final results = await checker.checkSupplementPairInteractions(
        newProductCanonicalIds: const ['calcium', 'iron'],
        stackSupplements: [
          _supplement(
            id: 'u1',
            name: 'Multi-mineral',
            ingredientKeys: '["iron", "calcium"]',
          ),
        ],
        db: db,
      );
      expect(results, hasLength(1));
      expect(results.single.id, 'DDI_IRON_CALCIUM');
    });

    test('dedupes when multiple stack supplements hit same row', () async {
      // Two stack supplements both contain iron; the new product is
      // calcium. Same row would fire twice without dedup.
      final results = await checker.checkSupplementPairInteractions(
        newProductCanonicalIds: const ['calcium'],
        stackSupplements: [
          _supplement(id: 'u1', name: 'Iron Plus', ingredientKeys: '["iron"]'),
          _supplement(id: 'u2', name: 'Hema Boost', ingredientKeys: '["iron"]'),
        ],
        db: db,
      );
      expect(results, hasLength(1));
    });

    test('returns multiple distinct rows for multiple distinct hits', () async {
      // New product has calcium + zinc; stack has iron and copper.
      // Should fire both DDI_IRON_CALCIUM and DDI_ZINC_COPPER.
      final results = await checker.checkSupplementPairInteractions(
        newProductCanonicalIds: const ['calcium', 'zinc'],
        stackSupplements: [
          _supplement(id: 'u1', name: 'Iron Plus', ingredientKeys: '["iron"]'),
          _supplement(
            id: 'u2',
            name: 'Copper 2mg',
            ingredientKeys: '["copper"]',
          ),
        ],
        db: db,
      );
      expect(results, hasLength(2));
      expect(
        results.map((r) => r.id),
        containsAll(<String>['DDI_IRON_CALCIUM', 'DDI_ZINC_COPPER']),
      );
    });

    test(
      'skips a stack supplement with malformed ingredient_keys JSON',
      () async {
        // Garbage JSON on one row must NOT abort the call. The valid row
        // should still match.
        final results = await checker.checkSupplementPairInteractions(
          newProductCanonicalIds: const ['calcium'],
          stackSupplements: [
            _supplement(id: 'u1', name: 'Garbage', ingredientKeys: 'not-json'),
            _supplement(
              id: 'u2',
              name: 'Iron Plus',
              ingredientKeys: '["iron"]',
            ),
          ],
          db: db,
        );
        expect(results, hasLength(1));
        expect(results.single.id, 'DDI_IRON_CALCIUM');
      },
    );

    test('skips a stack supplement with null ingredient_keys', () async {
      final results = await checker.checkSupplementPairInteractions(
        newProductCanonicalIds: const ['calcium'],
        stackSupplements: [
          _supplement(id: 'u1', name: 'No Ingredients'),
          _supplement(id: 'u2', name: 'Iron Plus', ingredientKeys: '["iron"]'),
        ],
        db: db,
      );
      expect(results, hasLength(1));
    });

    test('decodes legacy keyed-map ingredient_keys', () async {
      final results = await checker.checkSupplementPairInteractions(
        newProductCanonicalIds: const ['calcium'],
        stackSupplements: [
          _supplement(
            id: 'u1',
            name: 'Object Body',
            ingredientKeys: '{"iron": true}',
          ),
        ],
        db: db,
      );
      expect(results, hasLength(1));
      expect(results.first.id, 'DDI_IRON_CALCIUM');
    });

    test('does NOT match an ingredient against itself', () async {
      // The new product and the stack supplement both contain calcium —
      // a calcium↔calcium "self pair" must not be queried.
      final results = await checker.checkSupplementPairInteractions(
        newProductCanonicalIds: const ['calcium'],
        stackSupplements: [
          _supplement(
            id: 'u1',
            name: 'Other Calcium',
            ingredientKeys: '["calcium"]',
          ),
        ],
        db: db,
      );
      expect(results, isEmpty);
    });

    test('normalizes uppercase + whitespace canonical ids', () async {
      final results = await checker.checkSupplementPairInteractions(
        newProductCanonicalIds: const ['  CALCIUM  '],
        stackSupplements: [
          _supplement(id: 'u1', name: 'Iron', ingredientKeys: '["IRON"]'),
        ],
        db: db,
      );
      expect(results, hasLength(1));
      expect(results.single.id, 'DDI_IRON_CALCIUM');
    });

    test('does NOT return a tombstoned row even when ids match', () async {
      final results = await checker.checkSupplementPairInteractions(
        newProductCanonicalIds: const ['fake_supp'],
        stackSupplements: [
          _supplement(
            id: 'u1',
            name: 'Other Fake',
            ingredientKeys: '["other_fake"]',
          ),
        ],
        db: db,
      );
      expect(results, isEmpty);
    });

    test('overrides agent names so new product is always agent1', () async {
      final results = await checker.checkSupplementPairInteractions(
        newProductCanonicalIds: const ['calcium'],
        stackSupplements: [
          _supplement(
            id: 'u1',
            name: 'Custom Iron Brand',
            ingredientKeys: '["iron"]',
          ),
        ],
        db: db,
        newProductName: 'Custom Calcium Brand',
      );
      expect(results.single.agent1Name, 'Custom Calcium Brand');
      expect(results.single.agent2Name, 'Custom Iron Brand');
    });

    test('preserves effect_type when present on the row', () async {
      final results = await checker.checkSupplementPairInteractions(
        newProductCanonicalIds: const ['calcium'],
        stackSupplements: [
          _supplement(id: 'u1', name: 'Iron', ingredientKeys: '["iron"]'),
        ],
        db: db,
      );
      expect(results.single.effectType, EffectType.inhibitor);
    });

    test('parses source URLs from JSON column', () async {
      final results = await checker.checkSupplementPairInteractions(
        newProductCanonicalIds: const ['calcium'],
        stackSupplements: [
          _supplement(id: 'u1', name: 'Iron', ingredientKeys: '["iron"]'),
        ],
        db: db,
      );
      expect(results.single.sourceUrls, contains('https://example.org/test'));
    });

    test('finds zinc ↔ copper across reversed slot ordering', () async {
      // The fixture stored copper as agent1 and zinc as agent2; lookup
      // must find it whether the user's product is zinc-first or
      // copper-first.
      final asZinc = await checker.checkSupplementPairInteractions(
        newProductCanonicalIds: const ['zinc'],
        stackSupplements: [
          _supplement(
            id: 'u1',
            name: 'Copper 2mg',
            ingredientKeys: '["copper"]',
          ),
        ],
        db: db,
      );
      final asCopper = await checker.checkSupplementPairInteractions(
        newProductCanonicalIds: const ['copper'],
        stackSupplements: [
          _supplement(id: 'u1', name: 'Zinc 50mg', ingredientKeys: '["zinc"]'),
        ],
        db: db,
      );
      expect(asZinc, hasLength(1));
      expect(asCopper, hasLength(1));
      expect(asZinc.single.id, 'DDI_ZINC_COPPER');
      expect(asCopper.single.id, 'DDI_ZINC_COPPER');
    });
  });

  group('checkMedicationFoodAdvisories', () {
    test(
      'surfaces a drug-specific food note without a food stack item',
      () async {
        final results = await checker.checkMedicationFoodAdvisories(
          stackMedications: [
            _medication(id: 'm1', name: 'Synthroid', rxcui: '10582'),
          ],
          db: db,
        );

        expect(results, hasLength(1));
        expect(results.single.id, 'DSI_LEVOTHYROXINE_COFFEE');
        expect(results.single.severity, Severity.informational);
        expect(results.single.isFoodAdvisoryNote, isTrue);
        expect(results.single.agent1Name, 'Synthroid');
        expect(results.single.agent2Name, 'Coffee');
        expect(results.single.mechanism, contains('Coffee can reduce'));
        expect(results.single.management, contains('wait before coffee'));
      },
    );

    test('surfaces a class-level food note from medication classes', () async {
      final results = await checker.checkMedicationFoodAdvisories(
        stackMedications: [
          _medication(
            id: 'm1',
            name: 'Atorvastatin',
            drugClassesJson: '["class:statins"]',
          ),
        ],
        db: db,
      );

      expect(results, hasLength(1));
      expect(results.single.id, 'DSI_STATINS_GRAPEFRUIT');
      expect(results.single.agent1Name, 'Atorvastatin');
      expect(results.single.agent2Name, 'Grapefruit');
    });
  });

  // -------------------------------------------------------------------------
  // checkMedicationPairInteractions
  // -------------------------------------------------------------------------
  group('checkMedicationPairInteractions', () {
    test('matches class-level MAOI and CNS stimulant interaction', () async {
      final directRows = await db.lookupByDrugClass('class:maois');
      expect(directRows.map((row) => row.id), contains('DDI_MAOI_STIMULANTS'));

      final results = await checker.checkMedicationPairInteractions(
        newMedications: [
          _medication(
            id: 'm1',
            name: 'Phenelzine',
            drugClassesJson: '["class:maois"]',
          ),
        ],
        existingMedications: [
          _medication(
            id: 'm2',
            name: 'Adderall XR',
            drugClassesJson: '["class:stimulants"]',
          ),
        ],
        db: db,
      );

      expect(results, hasLength(1));
      expect(results.single.id, 'DDI_MAOI_STIMULANTS');
      expect(results.single.severity, Severity.contraindicated);
      expect(results.single.type, InteractionType.drugDrug);
      expect(results.single.agent1Name, 'Phenelzine');
      expect(results.single.agent2Name, 'Adderall XR');

      final reversed = await checker.checkMedicationPairInteractions(
        newMedications: [
          _medication(
            id: 'm2',
            name: 'Adderall XR',
            drugClassesJson: '["class:stimulants"]',
          ),
        ],
        existingMedications: [
          _medication(
            id: 'm1',
            name: 'Phenelzine',
            drugClassesJson: '["class:maois"]',
          ),
        ],
        db: db,
      );

      expect(reversed, hasLength(1));
      expect(reversed.single.id, 'DDI_MAOI_STIMULANTS');
      expect(reversed.single.agent1Name, 'Adderall XR');
      expect(reversed.single.agent2Name, 'Phenelzine');
    });

    test(
      'matches existing combination medication by ingredient RxCUI',
      () async {
        await db
            .into(db.interactions)
            .insert(
              _row(
                id: 'DDI_METHOTREXATE_SULFASALAZINE',
                a1Type: 'drug',
                a1Id: '6851',
                a1Name: 'Methotrexate',
                a2Type: 'drug',
                a2Id: '9524',
                a2Name: 'Sulfasalazine',
                severity: 'caution',
              ),
            );

        final results = await checker.checkMedicationPairInteractions(
          newMedications: [
            _medication(id: 'm1', name: 'Methotrexate', rxcui: '6851'),
          ],
          existingMedications: [
            _medication(
              id: 'm2',
              name: 'Combination medication',
              rxcui: '999999',
              ingredientRxcuis: const ['9524'],
            ),
          ],
          db: db,
        );

        expect(results, hasLength(1));
        expect(results.single.id, 'DDI_METHOTREXATE_SULFASALAZINE');
        expect(results.single.agent1Name, 'Methotrexate');
        expect(results.single.agent2Name, 'Combination medication');
      },
    );

    // Dr. Pham 2026-11-11: an exact-drug result takes precedence over a weaker
    // class result for the same two medications (simvastatin + gemfibrozil is
    // contraindicated; the statin class pair is avoid).
    test(
      'an exact medication pair replaces the class pair for the same two medications',
      () async {
        await db.batch((b) {
          b.insert(
            db.interactions,
            _row(
              id: 'DDI_STATIN_GEMFIBROZIL',
              a1Type: 'drug_class',
              a1Id: 'class:statins',
              a1Name: 'Statins (class)',
              a2Type: 'drug',
              a2Id: '4719',
              a2Name: 'Gemfibrozil',
              severity: 'avoid',
            ),
          );
          b.insert(
            db.interactions,
            _row(
              id: 'DDI_SIMVASTATIN_GEMFIBROZIL',
              a1Type: 'drug',
              a1Id: '36567',
              a1Name: 'Simvastatin',
              a2Type: 'drug',
              a2Id: '4719',
              a2Name: 'Gemfibrozil',
              severity: 'contraindicated',
            ),
          );
          b.insert(
            db.drugClassMap,
            _classMembers('class:statins', const ['36567', '83367']),
          );
        });
        final simvastatin = _medication(
          id: 'simva',
          name: 'Simvastatin',
          rxcui: '36567',
          drugClassesJson: '["class:statins"]',
        );
        final atorvastatin = _medication(
          id: 'atorva',
          name: 'Atorvastatin',
          rxcui: '83367',
          drugClassesJson: '["class:statins"]',
        );
        final gemfibrozil = _medication(
          id: 'gem',
          name: 'Gemfibrozil',
          rxcui: '4719',
        );

        for (final (newMeds, existing) in [
          ([simvastatin], [gemfibrozil]),
          ([gemfibrozil], [simvastatin]),
        ]) {
          final results = await checker.checkMedicationPairInteractions(
            newMedications: newMeds,
            existingMedications: existing,
            db: db,
          );
          expect(results.map((r) => r.id), ['DDI_SIMVASTATIN_GEMFIBROZIL']);
          expect(results.single.severity, Severity.contraindicated);
        }

        // A statin without its own pair keeps the class result.
        final control = await checker.checkMedicationPairInteractions(
          newMedications: [gemfibrozil],
          existingMedications: [atorvastatin, simvastatin],
          db: db,
        );
        expect(control.map((r) => '${r.id}:${r.agent2Name}').toSet(), {
          'DDI_STATIN_GEMFIBROZIL:Atorvastatin',
          'DDI_SIMVASTATIN_GEMFIBROZIL:Simvastatin',
        });
      },
    );

    test(
      'an exact pair replaces the class pair for every saved record of that medicine',
      () async {
        await db.batch((b) {
          b.insert(
            db.interactions,
            _row(
              id: 'DDI_STATIN_GEMFIBROZIL',
              a1Type: 'drug_class',
              a1Id: 'class:statins',
              a1Name: 'Statins (class)',
              a2Type: 'drug',
              a2Id: '4719',
              a2Name: 'Gemfibrozil',
              severity: 'avoid',
            ),
          );
          b.insert(
            db.interactions,
            _row(
              id: 'DDI_SIMVASTATIN_GEMFIBROZIL',
              a1Type: 'drug',
              a1Id: '36567',
              a1Name: 'Simvastatin',
              a2Type: 'drug',
              a2Id: '4719',
              a2Name: 'Gemfibrozil',
              severity: 'contraindicated',
            ),
          );
          b.insert(
            db.drugClassMap,
            _classMembers('class:statins', const ['36567', '83367']),
          );
        });
        // Two saved records of the same medicine share its RxCUI.
        final simvastatin = _medication(
          id: 'simva',
          name: 'Simvastatin',
          rxcui: '36567',
          drugClassesJson: '["class:statins"]',
        );
        final zocor = _medication(
          id: 'zocor',
          name: 'Zocor',
          rxcui: '104490',
          genericRxcui: '36567',
          drugClassesJson: '["class:statins"]',
        );
        final gemfibrozil = _medication(
          id: 'gem',
          name: 'Gemfibrozil',
          rxcui: '4719',
        );

        final results = await checker.checkMedicationPairInteractions(
          newMedications: [gemfibrozil],
          existingMedications: [simvastatin, zocor],
          db: db,
        );
        expect(results.map((r) => r.id), ['DDI_SIMVASTATIN_GEMFIBROZIL']);
      },
    );

    test(
      'a combination medicine keeps the class warning another ingredient matches',
      () async {
        await db.batch((b) {
          b.insert(
            db.interactions,
            _row(
              id: 'DDI_WARFARIN_ACETAMINOPHEN',
              a1Type: 'drug',
              a1Id: '11289',
              a1Name: 'Warfarin',
              a2Type: 'drug',
              a2Id: '161',
              a2Name: 'Acetaminophen',
              severity: 'caution',
            ),
          );
          b.insert(
            db.interactions,
            _row(
              id: 'DDI_ANTICOAGULANT_NSAID',
              a1Type: 'drug_class',
              a1Id: 'class:anticoagulants',
              a1Name: 'Anticoagulants (class)',
              a2Type: 'drug_class',
              a2Id: 'class:nsaids',
              a2Name: 'NSAIDs (class)',
              severity: 'avoid',
            ),
          );
          b.insert(
            db.drugClassMap,
            _classMembers('class:anticoagulants', const ['11289']),
          );
          b.insert(
            db.drugClassMap,
            _classMembers('class:nsaids', const ['5640']),
          );
        });
        final warfarin = _medication(
          id: 'warf',
          name: 'Warfarin',
          rxcui: '11289',
          drugClassesJson: '["class:anticoagulants"]',
        );
        final combination = _medication(
          id: 'combo',
          name: 'Acetaminophen and ibuprofen',
          rxcui: '2373261',
          ingredientRxcuis: const ['161', '5640'],
          drugClassesJson: '["class:nsaids"]',
        );

        for (final (newMeds, existing) in [
          ([warfarin], [combination]),
          ([combination], [warfarin]),
        ]) {
          final results = await checker.checkMedicationPairInteractions(
            newMedications: newMeds,
            existingMedications: existing,
            db: db,
          );
          expect(results.map((r) => r.id).toSet(), {
            'DDI_WARFARIN_ACETAMINOPHEN',
            'DDI_ANTICOAGULANT_NSAID',
          });
        }
      },
    );

    test(
      'a partial ingredient list cannot hide another ingredient\'s class warning',
      () async {
        await db.batch((b) {
          b.insert(
            db.interactions,
            _row(
              id: 'DDI_WARFARIN_ACETAMINOPHEN',
              a1Type: 'drug',
              a1Id: '11289',
              a1Name: 'Warfarin',
              a2Type: 'drug',
              a2Id: '161',
              a2Name: 'Acetaminophen',
              severity: 'caution',
            ),
          );
          b.insert(
            db.interactions,
            _row(
              id: 'DDI_ANTICOAGULANT_NSAID',
              a1Type: 'drug_class',
              a1Id: 'class:anticoagulants',
              a1Name: 'Anticoagulants (class)',
              a2Type: 'drug_class',
              a2Id: 'class:nsaids',
              a2Name: 'NSAIDs (class)',
              severity: 'avoid',
            ),
          );
          b.insert(
            db.drugClassMap,
            _classMembers('class:anticoagulants', const ['11289']),
          );
          b.insert(
            db.drugClassMap,
            _classMembers('class:nsaids', const ['5640']),
          );
        });
        final warfarin = _medication(
          id: 'warf',
          name: 'Warfarin',
          rxcui: '11289',
          drugClassesJson: '["class:anticoagulants"]',
        );
        // Saved records whose ingredient list names only acetaminophen, or
        // only a generic, although the product also contains ibuprofen.
        final partialLists = [
          _medication(
            id: 'combo-partial',
            name: 'Acetaminophen and ibuprofen',
            rxcui: '2373261',
            ingredientRxcuis: const ['161'],
            drugClassesJson: '["class:nsaids"]',
          ),
          _medication(
            id: 'combo-generic-only',
            name: 'Acetaminophen and ibuprofen',
            rxcui: '2373261',
            genericRxcui: '161',
            drugClassesJson: '["class:nsaids"]',
          ),
        ];

        for (final combination in partialLists) {
          for (final (newMeds, existing) in [
            ([warfarin], [combination]),
            ([combination], [warfarin]),
          ]) {
            final results = await checker.checkMedicationPairInteractions(
              newMedications: newMeds,
              existingMedications: existing,
              db: db,
            );
            expect(results.map((r) => r.id).toSet(), {
              'DDI_WARFARIN_ACETAMINOPHEN',
              'DDI_ANTICOAGULANT_NSAID',
            }, reason: combination.id);
          }
        }
      },
    );

    test('unknown class membership keeps both warnings', () async {
      // No drug_class_map row: the direct pair cannot be shown to cover the class.
      await db.batch((b) {
        b.insert(
          db.interactions,
          _row(
            id: 'DDI_STATIN_GEMFIBROZIL',
            a1Type: 'drug_class',
            a1Id: 'class:statins',
            a1Name: 'Statins (class)',
            a2Type: 'drug',
            a2Id: '4719',
            a2Name: 'Gemfibrozil',
            severity: 'avoid',
          ),
        );
        b.insert(
          db.interactions,
          _row(
            id: 'DDI_SIMVASTATIN_GEMFIBROZIL',
            a1Type: 'drug',
            a1Id: '36567',
            a1Name: 'Simvastatin',
            a2Type: 'drug',
            a2Id: '4719',
            a2Name: 'Gemfibrozil',
            severity: 'contraindicated',
          ),
        );
      });
      final results = await checker.checkMedicationPairInteractions(
        newMedications: [
          _medication(id: 'gem', name: 'Gemfibrozil', rxcui: '4719'),
        ],
        existingMedications: [
          _medication(
            id: 'simva',
            name: 'Simvastatin',
            rxcui: '36567',
            drugClassesJson: '["class:statins"]',
          ),
        ],
        db: db,
      );
      expect(results.map((r) => r.id).toSet(), {
        'DDI_STATIN_GEMFIBROZIL',
        'DDI_SIMVASTATIN_GEMFIBROZIL',
      });
    });
  });

  // -------------------------------------------------------------------------
  // checkMedicationInteractions
  // -------------------------------------------------------------------------
  group('checkMedicationInteractions', () {
    test(
      'does not apply ciprofloxacin-only calcium advice to moxifloxacin',
      () async {
        await db
            .into(db.interactions)
            .insert(
              _row(
                id: 'DSI_CALCIUM_CIPROFLOXACIN',
                a1Type: 'drug',
                a1Id: '2551',
                a1Name: 'Ciprofloxacin',
                a1Class: 'class:fluoroquinolones',
                a2Type: 'supplement',
                a2Id: 'C0006675',
                a2Name: 'Calcium',
                a2Canonical: 'calcium',
                severity: 'avoid',
              ),
            );

        Future<List<InteractionResult>> check(UserStacksLocalData medication) =>
            checker.checkMedicationInteractions(
              newProductCanonicalIds: const ['calcium'],
              stackMedications: [medication],
              db: db,
              newProductName: 'Calcium supplement',
            );

        expect(
          await check(
            _medication(
              id: 'cipro',
              name: 'Ciprofloxacin',
              rxcui: '2551',
              drugClassesJson: '["class:fluoroquinolones"]',
            ),
          ),
          hasLength(1),
        );
        expect(
          await check(
            _medication(
              id: 'moxi',
              name: 'Moxifloxacin',
              rxcui: '139462',
              drugClassesJson: '["class:fluoroquinolones"]',
            ),
          ),
          isEmpty,
        );
      },
    );

    test(
      'levodopa + iron reaches combination products by ingredient, not carbidopa alone',
      () async {
        // DSI_LEVODOPA_IRON (Dr. Pham 2026-11-11, batch 3b part 2) is keyed on
        // levodopa's ingredient RxCUI 6375. Combination products carry it in
        // their ingredient list (RxNav, 2026-11-11): carbidopa/levodopa
        // 25/100 mg (SCD 197444: 2019 + 6375) and carbidopa/entacapone/
        // levodopa (SCD 403851: 2019 + 60307 + 6375). Carbidopa alone (2019)
        // is not levodopa.
        await db
            .into(db.interactions)
            .insert(
              _row(
                id: 'DSI_LEVODOPA_IRON',
                a1Type: 'drug',
                a1Id: '6375',
                a1Name: 'Levodopa',
                a2Type: 'supplement',
                a2Id: 'C0302583',
                a2Name: 'Iron (supplement)',
                a2Canonical: 'iron',
                severity: 'caution',
              ),
            );

        Future<List<InteractionResult>> check(UserStacksLocalData medication) =>
            checker.checkMedicationInteractions(
              newProductCanonicalIds: const ['iron'],
              stackMedications: [medication],
              db: db,
              newProductName: 'Multivitamin with iron',
            );

        final sinemet = await check(
          _medication(
            id: 'carbidopa-levodopa',
            name: 'Carbidopa / Levodopa',
            rxcui: '197444',
            ingredientRxcuis: const ['2019', '6375'],
          ),
        );
        expect(sinemet.map((r) => r.id), ['DSI_LEVODOPA_IRON']);

        // The populated fixture proves the matcher does not extrapolate the
        // iron concern into a blanket B6 warning for a combination user.
        // Pipeline source guards separately census all authored B6 records.
        final b6 = await checker.checkMedicationInteractions(
          newProductCanonicalIds: const ['vitamin_b6_pyridoxine'],
          stackMedications: [
            _medication(
              id: 'carbidopa-levodopa',
              name: 'Sinemet',
              rxcui: '197444',
              ingredientRxcuis: const ['2019', '6375'],
            ),
          ],
          db: db,
          newProductName: 'Vitamin B6',
        );
        expect(b6, isEmpty);

        final stalevo = await check(
          _medication(
            id: 'carbidopa-entacapone-levodopa',
            name: 'Carbidopa / Entacapone / Levodopa',
            rxcui: '403851',
            ingredientRxcuis: const ['2019', '60307', '6375'],
          ),
        );
        expect(stalevo.map((r) => r.id), ['DSI_LEVODOPA_IRON']);

        expect(
          await check(
            _medication(
              id: 'carbidopa',
              name: 'Carbidopa',
              rxcui: '2019',
              genericRxcui: '2019',
            ),
          ),
          isEmpty,
        );
      },
    );

    test('honors an authored medication-pair dose threshold', () async {
      await db
          .into(db.interactions)
          .insert(
            _row(
              id: 'DDI_METFORMIN_CHROMIUM_THRESHOLD',
              a1Type: 'drug',
              a1Id: '6809',
              a1Name: 'Metformin',
              a2Type: 'supplement',
              a2Id: 'C0000001',
              a2Name: 'Chromium',
              a2Canonical: 'chromium',
              doseDependent: 1,
              direction: 'harmful',
              materiality: 'dose_dependent',
              doseThresholdJson:
                  '{"agent_canonical_id":"chromium","value":200,"unit":"mcg","basis":"per_day"}',
            ),
          );

      Map<String, StackDoseTotal> totals(double chromiumMcg) =>
          const StackDoseSummer().sum([
            StackItemNutrients(
              stackEntryId: 'multi',
              productName: 'Multivitamin',
              ingredients: [
                {
                  'canonical_id': 'chromium',
                  'name': 'Chromium',
                  'quantity': chromiumMcg,
                  'unit': 'mcg',
                },
              ],
            ),
          ]);

      Future<List<InteractionResult>> check(
        Map<String, StackDoseTotal>? doseTotals,
      ) => checker.checkMedicationInteractions(
        newProductCanonicalIds: const ['chromium'],
        stackMedications: [
          _medication(id: 'metformin', name: 'Metformin', rxcui: '6809'),
        ],
        db: db,
        newProductName: 'Multivitamin',
        stackDoseTotals: doseTotals,
      );

      expect(await check(totals(199)), isEmpty);
      expect(await check(totals(200)), hasLength(1));
      expect(
        await check(null),
        hasLength(1),
        reason: 'unknown dose remains fail-open',
      );
    });

    test(
      'prefers a medication-specific rule over a broader class rule for the same nutrient',
      () async {
        await db.batch((batch) {
          batch.insert(
            db.interactions,
            _row(
              id: 'DSI_WAR_VITE_DIRECT',
              a1Type: 'drug',
              a1Id: '11289',
              a1Name: 'Warfarin',
              a2Type: 'supplement',
              a2Id: 'C0042874',
              a2Name: 'Vitamin E',
              a2Canonical: 'vitamin_e',
              severity: 'caution',
            ),
          );
          batch.insert(
            db.interactions,
            _row(
              id: 'DSI_VITE_ANTICOAG_CLASS',
              a1Type: 'drug_class',
              a1Id: 'class:anticoagulants',
              a1Name: 'Anticoagulants',
              a2Type: 'supplement',
              a2Id: 'C0042874',
              a2Name: 'Vitamin E',
              a2Canonical: 'vitamin_e',
              severity: 'avoid',
            ),
          );
        });

        final results = await checker.checkMedicationInteractions(
          newProductCanonicalIds: const ['vitamin_e'],
          stackMedications: [
            _medication(
              id: 'warfarin',
              name: 'Warfarin',
              rxcui: '11289',
              drugClassesJson: '["class:anticoagulants"]',
            ),
          ],
          db: db,
          newProductName: 'Vitamin E',
        );

        expect(results, hasLength(1));
        expect(results.single.id, 'DSI_WAR_VITE_DIRECT');
      },
    );

    test('returns empty for empty new product canonical ids', () async {
      final results = await checker.checkMedicationInteractions(
        newProductCanonicalIds: const <String>[],
        stackMedications: [
          _medication(id: 'm1', name: 'Warfarin', rxcui: '11289'),
        ],
        db: db,
      );
      expect(results, isEmpty);
    });

    test('returns empty for empty medication list', () async {
      final results = await checker.checkMedicationInteractions(
        newProductCanonicalIds: const ['vitamin_k'],
        stackMedications: const <UserStacksLocalData>[],
        db: db,
      );
      expect(results, isEmpty);
    });

    test('finds drug ↔ supplement via RXCUI', () async {
      final results = await checker.checkMedicationInteractions(
        newProductCanonicalIds: const ['vitamin_k'],
        stackMedications: [
          _medication(id: 'm1', name: 'Coumadin', rxcui: '11289'),
        ],
        db: db,
        newProductName: 'Vitamin K2 100mcg',
      );
      expect(results, hasLength(1));
      expect(results.single.id, 'DDI_WARFARIN_VITK');
      expect(results.single.severity, Severity.avoid);
      expect(results.single.type, InteractionType.drugSupplement);
    });

    test('finds drug_class ↔ supplement via classes JSON', () async {
      final results = await checker.checkMedicationInteractions(
        newProductCanonicalIds: const ['potassium'],
        stackMedications: [
          _medication(
            id: 'm1',
            name: 'Lisinopril 10mg',
            drugClassesJson: '["class:ace_inhibitors"]',
          ),
        ],
        db: db,
      );
      expect(results, hasLength(1));
      expect(results.single.id, 'DDI_ACE_POTASSIUM');
    });

    test('finds drug_class row stored in reversed slot order', () async {
      // SSRI row was inserted with St John's wort as agent1 (supplement)
      // and class:ssris as agent2 (drug_class). Lookup must still find
      // it when called drug_class-side first.
      final results = await checker.checkMedicationInteractions(
        newProductCanonicalIds: const ['st_johns_wort'],
        stackMedications: [
          _medication(
            id: 'm1',
            name: 'Sertraline',
            drugClassesJson: '["class:ssris"]',
          ),
        ],
        db: db,
      );
      expect(results, hasLength(1));
      expect(results.single.id, 'DDI_SSRI_SJW');
      expect(results.single.severity, Severity.contraindicated);
    });

    test(
      'finds safety-canonical rows when bundle casing differs from stack IDs',
      () async {
        await db
            .into(db.interactions)
            .insert(
              _row(
                id: 'DDI_STATINS_RYR_CASE',
                a1Type: 'drug_class',
                a1Id: 'class:statins',
                a1Name: 'Statins',
                a2Type: 'supplement',
                a2Id: 'BANNED_RED_YEAST_RICE',
                a2Name: 'Red Yeast Rice',
                a2Canonical: 'BANNED_RED_YEAST_RICE',
                severity: 'avoid',
              ),
            );

        final results = await checker.checkMedicationInteractions(
          newProductCanonicalIds: const ['banned_red_yeast_rice'],
          stackMedications: [
            _medication(
              id: 'm1',
              name: 'Atorvastatin',
              drugClassesJson: '["class:statins"]',
            ),
          ],
          db: db,
        );

        expect(results, hasLength(1));
        expect(results.single.id, 'DDI_STATINS_RYR_CASE');
        expect(results.single.severity, Severity.avoid);
      },
    );

    test('dedupes when same row reachable via rxcui AND class', () async {
      // Synthesise: medication has both an rxcui AND a class — but the
      // bundle row keys off only one. Deduping logic should still
      // collapse double hits down to one. To exercise this we use the
      // ACE row, set the med's class AND give it a fake rxcui that
      // happens to also resolve. Since the rxcui isn't actually in any
      // row, we'll instead use TWO classes that BOTH resolve to the
      // same row by inserting a sibling class-tag below.
      //
      // Simpler check: ensure two probes that legitimately hit the same
      // row collapse to one result. We use the same class twice.
      final results = await checker.checkMedicationInteractions(
        newProductCanonicalIds: const ['potassium'],
        stackMedications: [
          _medication(
            id: 'm1',
            name: 'Enalapril',
            drugClassesJson: '["class:ace_inhibitors", "class:ace_inhibitors"]',
          ),
        ],
        db: db,
      );
      expect(results, hasLength(1));
    });

    test('skips a medication with neither rxcui nor classes', () async {
      final results = await checker.checkMedicationInteractions(
        newProductCanonicalIds: const ['vitamin_k'],
        stackMedications: [
          _medication(id: 'm1', name: 'Unknown Med'),
          _medication(id: 'm2', name: 'Coumadin', rxcui: '11289'),
        ],
        db: db,
      );
      expect(results, hasLength(1));
      expect(results.single.id, 'DDI_WARFARIN_VITK');
    });

    test('falls through malformed drug_classes JSON to rxcui path', () async {
      final results = await checker.checkMedicationInteractions(
        newProductCanonicalIds: const ['vitamin_k'],
        stackMedications: [
          _medication(
            id: 'm1',
            name: 'Coumadin',
            rxcui: '11289',
            drugClassesJson: 'not-json',
          ),
        ],
        db: db,
      );
      expect(results, hasLength(1));
      expect(results.single.id, 'DDI_WARFARIN_VITK');
    });

    test('returns empty when neither rxcui nor any class matches', () async {
      final results = await checker.checkMedicationInteractions(
        newProductCanonicalIds: const ['vitamin_k'],
        stackMedications: [
          _medication(
            id: 'm1',
            name: 'Random Med',
            rxcui: '999999',
            drugClassesJson: '["class:does_not_exist"]',
          ),
        ],
        db: db,
      );
      expect(results, isEmpty);
    });

    test('overrides agent names so medication is always agent1', () async {
      final results = await checker.checkMedicationInteractions(
        newProductCanonicalIds: const ['vitamin_k'],
        stackMedications: [
          _medication(id: 'm1', name: 'Brand-Name Coumadin', rxcui: '11289'),
        ],
        db: db,
        newProductName: 'Brand K2',
      );
      expect(results.single.agent1Name, 'Brand-Name Coumadin');
      expect(results.single.agent2Name, 'Brand K2');
    });

    test(
      'preserves effect_type from row (warfarin/vit K = inhibitor)',
      () async {
        final results = await checker.checkMedicationInteractions(
          newProductCanonicalIds: const ['vitamin_k'],
          stackMedications: [
            _medication(id: 'm1', name: 'Warfarin', rxcui: '11289'),
          ],
          db: db,
        );
        expect(results.single.effectType, EffectType.inhibitor);
      },
    );

    test('does NOT return tombstoned rows', () async {
      // Build a fake retired row keyed off a med rxcui by inserting it
      // into the same DB.
      await db
          .into(db.interactions)
          .insert(
            _row(
              id: 'DDI_RETIRED_DRUG',
              a1Type: 'drug',
              a1Id: '888',
              a1Name: 'Retired Drug',
              a2Type: 'supplement',
              a2Id: 'C0000003',
              a2Name: 'Some Vitamin',
              a2Canonical: 'some_vitamin',
              severity: 'avoid',
              retiredAt: '2025-01-01T00:00:00Z',
            ),
          );
      final results = await checker.checkMedicationInteractions(
        newProductCanonicalIds: const ['some_vitamin'],
        stackMedications: [
          _medication(id: 'm1', name: 'Whatever', rxcui: '888'),
        ],
        db: db,
      );
      expect(results, isEmpty);
    });

    test(
      'multiple meds and multiple new ingredients produce correct hits',
      () async {
        final results = await checker.checkMedicationInteractions(
          newProductCanonicalIds: const ['vitamin_k', 'potassium'],
          stackMedications: [
            _medication(id: 'm1', name: 'Coumadin', rxcui: '11289'),
            _medication(
              id: 'm2',
              name: 'Lisinopril',
              drugClassesJson: '["class:ace_inhibitors"]',
            ),
          ],
          db: db,
        );
        expect(results, hasLength(2));
        final ids = results.map((r) => r.id).toSet();
        expect(ids, contains('DDI_WARFARIN_VITK'));
        expect(ids, contains('DDI_ACE_POTASSIUM'));
      },
    );

    test('trims whitespace inside drug class json', () async {
      final results = await checker.checkMedicationInteractions(
        newProductCanonicalIds: const ['potassium'],
        stackMedications: [
          _medication(
            id: 'm1',
            name: 'Enalapril',
            drugClassesJson: '["  class:ace_inhibitors  "]',
          ),
        ],
        db: db,
      );
      expect(results, hasLength(1));
    });

    test('treats empty rxcui string as missing', () async {
      // Empty rxcui must NOT call the lookupPair path with ''.
      final results = await checker.checkMedicationInteractions(
        newProductCanonicalIds: const ['vitamin_k'],
        stackMedications: [_medication(id: 'm1', name: 'Coumadin', rxcui: '')],
        db: db,
      );
      expect(results, isEmpty);
    });

    test('marks results with InteractionSource.pipeline', () async {
      final results = await checker.checkMedicationInteractions(
        newProductCanonicalIds: const ['vitamin_k'],
        stackMedications: [
          _medication(id: 'm1', name: 'Coumadin', rxcui: '11289'),
        ],
        db: db,
      );
      expect(results.single.source, InteractionSource.pipeline);
    });

    test('hydrates evidenceLevel from row', () async {
      final results = await checker.checkMedicationInteractions(
        newProductCanonicalIds: const ['vitamin_k'],
        stackMedications: [
          _medication(id: 'm1', name: 'Coumadin', rxcui: '11289'),
        ],
        db: db,
      );
      expect(results.single.evidenceLevel, EvidenceLevel.established);
    });
  });
  group('approved pairwise form and confirmed context contract', () {
    late InteractionDatabase db;
    setUp(() async {
      db = InteractionDatabase.memory();
      await db
          .into(db.interactions)
          .insert(
            _row(
              id: 'NIACIN_FORM',
              a1Type: 'drug_class',
              a1Id: 'class:statins',
              a1Class: 'class:statins',
              a1Name: 'Statin',
              a2Type: 'supplement',
              a2Id: 'C0027996',
              a2Name: 'Nicotinic acid',
              a2Canonical: 'vitamin_b3_niacin',
              doseDependent: 1,
              direction: 'harmful',
              materiality: 'dose_dependent',
              doseThresholdJson: jsonEncode({
                'agent_canonical_id': 'vitamin_b3_niacin',
                'value': 1000,
                'unit': 'mg',
                'form_scope': ['nicotinic acid'],
              }),
              profileGateJson: jsonEncode({
                'gate_type': 'nutrient_form',
                'requires': {
                  'conditions_any': <String>[],
                  'drug_classes_any': <String>[],
                  'profile_flags_any': <String>[],
                },
                'excludes': {
                  'conditions_any': <String>[],
                  'drug_classes_any': <String>[],
                  'profile_flags_any': <String>[],
                  'product_forms_any': <String>[],
                  'nutrient_forms_any': ['niacinamide'],
                },
              }),
            ),
          );
      await db
          .into(db.interactions)
          .insert(
            _row(
              id: 'EMSAM_FOOD',
              a1Type: 'drug_class',
              a1Id: 'class:maois',
              a1Class: 'class:maois',
              a1Name: 'MAOI',
              a2Type: 'reference',
              a2Id: 'ref:food',
              a2Name: 'Food',
              severity: 'contraindicated',
              alertStyle: 'food_advisory_note',
              medicationExceptionsJson: jsonEncode([
                {
                  'ingredient_rxcuis': ['9639'],
                  'dose_mg_exact': 6,
                  'route': 'transdermal',
                  'use_context': 'confirmed_no_recent_high_dose',
                },
              ]),
            ),
          );
      await db
          .into(db.interactions)
          .insert(
            _row(
              id: 'CONTRAST',
              a1Type: 'drug',
              a1Id: '6809',
              a1Class: 'class:antidiabetics',
              a1Name: 'Metformin',
              a2Type: 'reference',
              a2Id: 'ref:iodinated_contrast',
              a2Name: 'Procedure',
              typeAuthored: 'Med-Procedure',
              medicationExceptionsJson: jsonEncode([
                {
                  'ingredient_rxcuis': ['6809'],
                  'use_context': 'confirmed_iv_over60_no_risk',
                },
              ]),
            ),
          );
    });
    tearDown(() => db.close());
    for (final scenario in <(String, Map<String, double>?, Set<String>?, bool)>[
      ('amide only', {'niacinamide': 1500}, {'niacinamide'}, false),
      ('acid below', {'nicotinic acid': 999}, {'nicotinic acid'}, false),
      ('acid at', {'nicotinic acid': 1000}, {'nicotinic acid'}, true),
      (
        'mixed known below',
        {'nicotinic acid': 100, 'niacinamide': 1500},
        {'nicotinic acid', 'niacinamide'},
        false,
      ),
      (
        'mixed known at',
        {'nicotinic acid': 1000, 'niacinamide': 1500},
        {'nicotinic acid', 'niacinamide'},
        true,
      ),
      ('unknown form', null, null, true),
      ('unknown acid dose', null, {'nicotinic acid'}, true),
      (
        'other B3 form',
        {'inositol hexanicotinate': 500},
        {'inositol hexanicotinate'},
        true,
      ),
    ]) {
      test(scenario.$1, () async {
        final amount = scenario.$2?.values.fold(0.0, (a, b) => a + b) ?? 1500;
        final hits = await StackInteractionChecker()
            .checkMedicationInteractions(
              newProductCanonicalIds: ['vitamin_b3_niacin'],
              stackMedications: [
                _medication(
                  id: 'statin',
                  name: 'Statin',
                  drugClassesJson: '["class:statins"]',
                ),
              ],
              db: db,
              productForms: {'vitamin_b3_niacin': scenario.$3},
              stackDoseTotals: {
                'vitamin_b3_niacin': StackDoseTotal(
                  canonicalId: 'vitamin_b3_niacin',
                  displayName: 'B3',
                  totalValue: amount,
                  unit: 'mg',
                  formTotals: scenario.$2,
                  isDailyExposureConfirmed: true,
                  contributions: [
                    StackDoseContribution(
                      stackEntryId: 'p',
                      productName: 'P',
                      amount: amount,
                      unit: 'mg',
                    ),
                  ],
                ),
              },
            );
        expect(hits.any((r) => r.id == 'NIACIN_FORM'), scenario.$4);
      });
    }
    for (final context in <MedicationUseContext>[
      const MedicationUseContext(
        dailyDoseMg: 6,
        route: 'transdermal',
        useContext: 'confirmed_no_recent_high_dose',
        isCurrentCheck: true,
      ),
      const MedicationUseContext(
        dailyDoseMg: 6,
        route: 'transdermal',
        useContext: 'confirmed_no_recent_high_dose',
      ),
      const MedicationUseContext(
        dailyDoseMg: 6,
        route: 'transdermal',
        isCurrentCheck: true,
      ),
      const MedicationUseContext(
        dailyDoseMg: 9,
        route: 'transdermal',
        useContext: 'confirmed_no_recent_high_dose',
        isCurrentCheck: true,
      ),
      const MedicationUseContext(
        dailyDoseMg: 20,
        route: 'transdermal',
        useContext: 'confirmed_no_recent_high_dose',
        isCurrentCheck: true,
      ),
      const MedicationUseContext(
        dailyDoseMg: 6,
        route: 'oral',
        useContext: 'confirmed_no_recent_high_dose',
        isCurrentCheck: true,
      ),
    ]) {
      test(
        'EMSAM context ${context.dailyDoseMg}/${context.route}/${context.isCurrentCheck}/${context.useContext}',
        () async {
          final hits = await StackInteractionChecker()
              .checkMedicationFoodAdvisories(
                stackMedications: [
                  _medication(
                    id: 's',
                    name: 'Selegiline',
                    rxcui: '9639',
                    drugClassesJson: '["class:maois"]',
                  ),
                ],
                db: db,
                currentMedicationContexts: {'s': context},
              );
          expect(
            hits.isEmpty,
            context.isCurrentCheck &&
                context.dailyDoseMg == 6 &&
                context.route == 'transdermal' &&
                context.useContext != null,
          );
        },
      );
    }
    test('procedural context never applies without an actual event', () async {
      final meds = [_medication(id: 'm', name: 'Metformin', rxcui: '6809')];
      final checker = StackInteractionChecker();
      expect(
        await checker.checkMedicationProcedureInteractions(
          referenceId: '',
          stackMedications: meds,
          db: db,
        ),
        isEmpty,
      );
      expect(
        await checker.checkMedicationProcedureInteractions(
          referenceId: 'ref:iodinated_contrast',
          stackMedications: meds,
          db: db,
        ),
        hasLength(1),
      );
      expect(
        await checker.checkMedicationProcedureInteractions(
          referenceId: 'ref:iodinated_contrast',
          stackMedications: meds,
          db: db,
          currentMedicationContexts: {
            'm': const MedicationUseContext(
              useContext: 'confirmed_iv_over60_no_risk',
              isCurrentCheck: true,
            ),
          },
        ),
        isEmpty,
      );
      expect(
        await checker.checkMedicationProcedureInteractions(
          referenceId: 'ref:iodinated_contrast',
          stackMedications: meds,
          db: db,
          currentMedicationContexts: {
            'm': const MedicationUseContext(
              useContext: 'confirmed_iv_over60_no_risk',
            ),
          },
        ),
        hasLength(1),
      );
    });
    test(
      'procedural lookup never treats another drug in the class as metformin',
      () async {
        final hits = await StackInteractionChecker()
            .checkMedicationProcedureInteractions(
              referenceId: 'ref:iodinated_contrast',
              stackMedications: [
                _medication(
                  id: 'i',
                  name: 'Insulin',
                  rxcui: '5856',
                  drugClassesJson: '["class:antidiabetics"]',
                ),
              ],
              db: db,
            );
        expect(hits, isEmpty);
      },
    );

    test(
      'ingredient-only pairwise exception cannot clear a contextual warning',
      () async {
        await db.customStatement(
          'UPDATE interactions SET medication_exceptions_json = ? WHERE id = ?',
          [
            jsonEncode([
              {
                'ingredient_rxcuis': ['9639'],
              },
            ]),
            'EMSAM_FOOD',
          ],
        );
        final hits = await StackInteractionChecker()
            .checkMedicationFoodAdvisories(
              stackMedications: [
                _medication(
                  id: 's',
                  name: 'Selegiline',
                  rxcui: '9639',
                  drugClassesJson: '["class:maois"]',
                ),
              ],
              db: db,
              currentMedicationContexts: {
                's': const MedicationUseContext(
                  useContext: 'confirmed_no_recent_high_dose',
                  isCurrentCheck: true,
                ),
              },
            );
        expect(hits.any((r) => r.id == 'EMSAM_FOOD'), isTrue);
      },
    );

    test(
      'a low label-serving amount cannot establish the actual daily dose',
      () async {
        final hits = await StackInteractionChecker()
            .checkMedicationInteractions(
              newProductCanonicalIds: ['vitamin_b3_niacin'],
              stackMedications: [
                _medication(
                  id: 's',
                  name: 'Statin',
                  drugClassesJson: '["class:statins"]',
                ),
              ],
              db: db,
              productForms: {
                'niacin': {'nicotinic acid'},
              },
              stackDoseTotals: {
                'niacin': const StackDoseTotal(
                  canonicalId: 'niacin',
                  displayName: 'B3',
                  totalValue: 500,
                  unit: 'mg',
                  formTotals: {'nicotinic acid': 500},
                  contributions: [
                    StackDoseContribution(
                      stackEntryId: 'p',
                      productName: 'Label',
                      amount: 500,
                      unit: 'mg',
                    ),
                  ],
                ),
              },
            );
        expect(hits.any((r) => r.id == 'NIACIN_FORM'), isTrue);
      },
    );
  });
}
