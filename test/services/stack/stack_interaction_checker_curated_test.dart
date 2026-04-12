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
import 'package:pharmaguide/services/stack/stack_interaction_checker.dart';

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
  String? retiredAt,
}) {
  return InteractionsCompanion.insert(
    id: id,
    agent1Type: a1Type,
    agent1Name: a1Name,
    agent1Id: a1Id,
    agent1CanonicalId:
        a1Canonical == null ? const drift.Value.absent() : drift.Value(a1Canonical),
    agent1DrugClass:
        a1Class == null ? const drift.Value.absent() : drift.Value(a1Class),
    agent2Type: a2Type,
    agent2Name: a2Name,
    agent2Id: a2Id,
    agent2CanonicalId:
        a2Canonical == null ? const drift.Value.absent() : drift.Value(a2Canonical),
    agent2DrugClass:
        a2Class == null ? const drift.Value.absent() : drift.Value(a2Class),
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
    retiredAt:
        retiredAt == null ? const drift.Value.absent() : drift.Value(retiredAt),
    typeAuthored: 'curated',
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
  String? drugClassesJson,
}) {
  final now = DateTime.utc(2026, 4, 11);
  return UserStacksLocalData(
    id: id,
    type: 'medication',
    name: name,
    rxcui: rxcui,
    drugClassesCol: drugClassesJson,
    addedAt: now,
    clientUpdatedAt: now,
  );
}

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
          _supplement(
            id: 'u1',
            name: 'Iron 30mg',
            ingredientKeys: '["iron"]',
          ),
        ],
        db: db,
      );
      expect(results, isEmpty);
    });

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
          _supplement(
            id: 'u1',
            name: 'Iron 30mg',
            ingredientKeys: '["iron"]',
          ),
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
          _supplement(
            id: 'u1',
            name: 'Iron Plus',
            ingredientKeys: '["iron"]',
          ),
          _supplement(
            id: 'u2',
            name: 'Hema Boost',
            ingredientKeys: '["iron"]',
          ),
        ],
        db: db,
      );
      expect(results, hasLength(1));
    });

    test('returns multiple distinct rows for multiple distinct hits',
        () async {
      // New product has calcium + zinc; stack has iron and copper.
      // Should fire both DDI_IRON_CALCIUM and DDI_ZINC_COPPER.
      final results = await checker.checkSupplementPairInteractions(
        newProductCanonicalIds: const ['calcium', 'zinc'],
        stackSupplements: [
          _supplement(
            id: 'u1',
            name: 'Iron Plus',
            ingredientKeys: '["iron"]',
          ),
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

    test('skips a stack supplement with malformed ingredient_keys JSON',
        () async {
      // Garbage JSON on one row must NOT abort the call. The valid row
      // should still match.
      final results = await checker.checkSupplementPairInteractions(
        newProductCanonicalIds: const ['calcium'],
        stackSupplements: [
          _supplement(
            id: 'u1',
            name: 'Garbage',
            ingredientKeys: 'not-json',
          ),
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
    });

    test('skips a stack supplement with null ingredient_keys', () async {
      final results = await checker.checkSupplementPairInteractions(
        newProductCanonicalIds: const ['calcium'],
        stackSupplements: [
          _supplement(id: 'u1', name: 'No Ingredients'),
          _supplement(
            id: 'u2',
            name: 'Iron Plus',
            ingredientKeys: '["iron"]',
          ),
        ],
        db: db,
      );
      expect(results, hasLength(1));
    });

    test('skips a stack supplement with non-array ingredient_keys', () async {
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
      expect(results, isEmpty);
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
          _supplement(
            id: 'u1',
            name: 'Iron',
            ingredientKeys: '["IRON"]',
          ),
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
          _supplement(
            id: 'u1',
            name: 'Iron',
            ingredientKeys: '["iron"]',
          ),
        ],
        db: db,
      );
      expect(results.single.effectType, EffectType.inhibitor);
    });

    test('parses source URLs from JSON column', () async {
      final results = await checker.checkSupplementPairInteractions(
        newProductCanonicalIds: const ['calcium'],
        stackSupplements: [
          _supplement(
            id: 'u1',
            name: 'Iron',
            ingredientKeys: '["iron"]',
          ),
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
          _supplement(
            id: 'u1',
            name: 'Zinc 50mg',
            ingredientKeys: '["zinc"]',
          ),
        ],
        db: db,
      );
      expect(asZinc, hasLength(1));
      expect(asCopper, hasLength(1));
      expect(asZinc.single.id, 'DDI_ZINC_COPPER');
      expect(asCopper.single.id, 'DDI_ZINC_COPPER');
    });
  });

  // -------------------------------------------------------------------------
  // checkMedicationInteractions
  // -------------------------------------------------------------------------
  group('checkMedicationInteractions', () {
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

    test('preserves effect_type from row (warfarin/vit K = inhibitor)',
        () async {
      final results = await checker.checkMedicationInteractions(
        newProductCanonicalIds: const ['vitamin_k'],
        stackMedications: [
          _medication(id: 'm1', name: 'Warfarin', rxcui: '11289'),
        ],
        db: db,
      );
      expect(results.single.effectType, EffectType.inhibitor);
    });

    test('does NOT return tombstoned rows', () async {
      // Build a fake retired row keyed off a med rxcui by inserting it
      // into the same DB.
      await db.into(db.interactions).insert(_row(
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
          ));
      final results = await checker.checkMedicationInteractions(
        newProductCanonicalIds: const ['some_vitamin'],
        stackMedications: [
          _medication(id: 'm1', name: 'Whatever', rxcui: '888'),
        ],
        db: db,
      );
      expect(results, isEmpty);
    });

    test('multiple meds and multiple new ingredients produce correct hits',
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
    });

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
        stackMedications: [
          _medication(id: 'm1', name: 'Coumadin', rxcui: ''),
        ],
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
}
