// Tests for the pure helpers powering the "Safe to Take Together?" quick
// check feature. The widget itself has presentation-only concerns; all
// interesting logic lives in `quick_check_logic.dart` and is exercised here.

import 'dart:convert';

import 'package:drift/drift.dart' as drift;
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/utils/product_canonical_ids.dart'
    as canonical_ids;
import 'package:pharmaguide/core/widgets/pg_severity_banner.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/interaction_database.dart';
import 'package:pharmaguide/features/quick_check/quick_check_logic.dart';

void main() {
  group('extractCanonicalIds', () {
    test('null fingerprint returns empty', () {
      expect(extractCanonicalIds(null), isEmpty);
    });

    test('empty string returns empty', () {
      expect(extractCanonicalIds(''), isEmpty);
    });

    test('malformed JSON returns empty (does not throw)', () {
      expect(extractCanonicalIds('{not json'), isEmpty);
    });

    test('non-object/list JSON (string literal) returns empty', () {
      expect(extractCanonicalIds('"just a string"'), isEmpty);
    });

    test('numeric JSON returns empty', () {
      expect(extractCanonicalIds('42'), isEmpty);
    });

    test('object keyed by canonical id returns lowercase keys', () {
      final out = extractCanonicalIds(
        '{"Calcium":{"dose":500},"IRON":{"dose":18}}',
      );
      expect(out, containsAll(['calcium', 'iron']));
      expect(out.length, 2);
    });

    test('bare list of canonical ids lowercases entries', () {
      expect(
        extractCanonicalIds('["Vitamin_D","MAGNESIUM"]'),
        equals(['vitamin_d', 'magnesium']),
      );
    });

    test('list with nulls drops them', () {
      expect(
        extractCanonicalIds('["calcium",null,"iron"]'),
        equals(['calcium', 'iron']),
      );
    });

    // Phase 11.11 safety fix (Sean 2026-05-17): the current pipeline
    // emits a structured shape. Previous parser returned the top-level
    // structure keys ("nutrients", "herbs", ...) as if they were
    // canonical ids — silently breaking every supplement-involved
    // Quick Check.
    test(
      'structured shape pulls canonical ids from nutrients keys + herbs list',
      () {
        final out = extractCanonicalIds(
          '{"nutrients":{"Potassium":{},"VITAMIN_D":{}},'
          '"herbs":["Ashwagandha","ginger"],'
          '"categories":["minerals","vitamins"],'
          '"pharmacological_flags":{"stimulant":false}}',
        );
        expect(
          out,
          containsAll(['potassium', 'vitamin_d', 'ashwagandha', 'ginger']),
        );
        expect(out, hasLength(4));
        // categories + pharmacological_flags are NOT canonical ids —
        // never include them.
        expect(out.contains('minerals'), isFalse);
        expect(out.contains('stimulant'), isFalse);
      },
    );

    test(
      'structured shape canonicalizes legacy label names into ID format',
      () {
        final out = extractCanonicalIds(
          '{"nutrients":{"Vitamin D":{},"N-Acetyl Cysteine":{}},'
          '"herbs":["St. John\\u0027s Wort","5-HTP"],'
          '"categories":["herbs"],'
          '"pharmacological_flags":{}}',
        );

        expect(
          out,
          containsAll([
            'vitamin_d',
            'n_acetyl_cysteine',
            'st_johns_wort',
            '5_htp',
          ]),
        );
        expect(out, isNot(contains("st. john's wort")));
      },
    );

    test(
      'structured shape with empty nutrients + empty herbs returns empty',
      () {
        // The Spring Valley Potassium failure mode that masked the
        // ACE inhibitor + Potassium rule on TestFlight 1.0.0+4.
        // Empty canonical ids must propagate so callers can surface
        // "ingredient data is incomplete" rather than imply clean check.
        expect(
          extractCanonicalIds(
            '{"nutrients":{},"herbs":[],"categories":["minerals"],'
            '"pharmacological_flags":{}}',
          ),
          isEmpty,
        );
      },
    );
  });

  group('canonicalIdsForProduct', () {
    test(
      'does not return structured fingerprint keys from current catalog shape',
      () {
        const product = ProductsCoreData(
          dsldId: 'STRUCTURED',
          productName: 'Structured Product',
          productStatus: 'active',
          keyIngredientTags:
              '["nutrients","herbs","categories",'
              '"pharmacological_flags"]',
          ingredientFingerprint:
              '{"nutrients":{"Potassium":{},"MAGNESIUM":{}},'
              '"herbs":["Ashwagandha"],'
              '"categories":["minerals"],'
              '"pharmacological_flags":{"sedative":false}}',
          exportVersion: 'test',
          exportedAt: '2026-05-17T00:00:00Z',
        );

        final out = canonical_ids.canonicalIdsForProduct(product);

        expect(QuickCheckItem.supplement(product).canonicalIds, equals(out));
        expect(out, containsAll(['potassium', 'magnesium', 'ashwagandha']));
        expect(out, isNot(contains('nutrients')));
        expect(out, isNot(contains('herbs')));
        expect(out, isNot(contains('categories')));
        expect(out, isNot(contains('pharmacological_flags')));
      },
    );

    test(
      'empty product-row carriers fall back to detail blob canonical_id',
      () {
        const product = ProductsCoreData(
          dsldId: '210621',
          productName: 'Natural Potassium 99 mg',
          brandName: 'Spring Valley',
          productStatus: 'active',
          keyIngredientTags: '[]',
          ingredientFingerprint:
              '{"nutrients":{},"herbs":[],"categories":["minerals"],'
              '"pharmacological_flags":{}}',
          exportVersion: 'test',
          exportedAt: '2026-05-17T00:00:00Z',
        );

        final out = canonical_ids.canonicalIdsForProduct(
          product,
          detailBlob: {
            'ingredients': [
              {'name': 'Potassium', 'canonical_id': 'potassium'},
              {'name': 'Potassium Gluconate', 'canonical_id': 'potassium'},
            ],
          },
        );

        expect(out, equals(['potassium']));
      },
    );
  });

  group('toneForSeverity', () {
    test('contraindicated → danger', () {
      expect(toneForSeverity(Severity.contraindicated), PGBannerTone.danger);
    });
    test('avoid → danger', () {
      expect(toneForSeverity(Severity.avoid), PGBannerTone.danger);
    });
    test('caution → caution', () {
      expect(toneForSeverity(Severity.caution), PGBannerTone.caution);
    });
    test('monitor → info', () {
      expect(toneForSeverity(Severity.monitor), PGBannerTone.info);
    });
    test('safe → info', () {
      expect(toneForSeverity(Severity.safe), PGBannerTone.info);
    });
  });

  group('runPairCheck', () {
    late InteractionDatabase db;

    setUp(() {
      db = InteractionDatabase.memory();
    });

    tearDown(() async {
      await db.close();
    });

    test(
      'returns empty when product A has no ingredient fingerprint',
      () async {
        final a = _product('A', 'Product A', null);
        final b = _product('B', 'Product B', '{"iron":{}}');
        expect(await runPairCheck(a, b, db), isEmpty);
      },
    );

    test(
      'returns empty when product B has no ingredient fingerprint',
      () async {
        final a = _product('A', 'Product A', '{"calcium":{}}');
        final b = _product('B', 'Product B', null);
        expect(await runPairCheck(a, b, db), isEmpty);
      },
    );

    test('returns empty when DB has no matching interactions', () async {
      final a = _product('A', 'Vitamin C', '["vitamin_c"]');
      final b = _product('B', 'Vitamin E', '["vitamin_e"]');
      expect(await runPairCheck(a, b, db), isEmpty);
    });

    test(
      'finds a direction-agnostic match and applies name overrides',
      () async {
        await db.batch((batch) {
          batch.insert(
            db.interactions,
            _interactionRow(
              id: 'CA_FE_1',
              a1Canonical: 'calcium',
              a2Canonical: 'iron',
              severity: 'caution',
            ),
          );
        });

        final a = _product('A', 'Calcium Citrate', '["calcium"]');
        final b = _product('B', 'Iron Bisglycinate', '["iron"]');

        final results = await runPairCheck(a, b, db);
        expect(results, hasLength(1));
        expect(results.first.severity, Severity.caution);
        expect(results.first.agent1Name, 'Calcium Citrate');
        expect(results.first.agent2Name, 'Iron Bisglycinate');
      },
    );

    test('sorts results with highest severity first', () async {
      await db.batch((batch) {
        batch.insert(
          db.interactions,
          _interactionRow(
            id: 'LOW',
            a1Canonical: 'ingredient_a',
            a2Canonical: 'ingredient_b',
            severity: 'monitor',
          ),
        );
        batch.insert(
          db.interactions,
          _interactionRow(
            id: 'HIGH',
            a1Canonical: 'ingredient_a',
            a2Canonical: 'ingredient_c',
            severity: 'contraindicated',
          ),
        );
        batch.insert(
          db.interactions,
          _interactionRow(
            id: 'MED',
            a1Canonical: 'ingredient_a',
            a2Canonical: 'ingredient_d',
            severity: 'caution',
          ),
        );
      });

      final a = _product('A', 'Product A', '["ingredient_a"]');
      final b = _product(
        'B',
        'Product B',
        '["ingredient_b","ingredient_c","ingredient_d"]',
      );

      final results = await runPairCheck(a, b, db);
      expect(
        results.map((r) => r.severity).toList(),
        equals([Severity.contraindicated, Severity.caution, Severity.monitor]),
      );
    });

    test(
      'deduplicates same interaction id across multiple A-side lookups',
      () async {
        // This row would be returned on both sides of the lookup if we
        // didn't dedupe — A has both canonical ids, so iterating A's ids
        // would find the same row twice.
        await db.batch((batch) {
          batch.insert(
            db.interactions,
            _interactionRow(
              id: 'SELF_PAIR',
              a1Canonical: 'xx',
              a2Canonical: 'yy',
              severity: 'caution',
            ),
          );
        });

        final a = _product('A', 'Product A', '["xx","yy"]');
        final b = _product('B', 'Product B', '["xx","yy"]');

        final results = await runPairCheck(a, b, db);
        expect(results, hasLength(1));
      },
    );
  });

  group('runQuickCheckPair', () {
    late InteractionDatabase db;

    setUp(() {
      db = InteractionDatabase.memory();
    });

    tearDown(() async {
      await db.close();
    });

    test('finds supplement-medication interaction by drug class', () async {
      await db.batch((batch) {
        batch.insert(
          db.interactions,
          _interactionRow(
            id: 'ACE_POTASSIUM',
            a1Canonical: 'potassium',
            a2Type: 'drug_class',
            a2Id: 'class:ace_inhibitors',
            a2Name: 'ACE inhibitors',
            severity: 'caution',
          ),
        );
      });

      final supplement = QuickCheckItem.supplement(
        _product('POTASSIUM', 'Potassium Complex', '["potassium"]'),
      );
      final medication = QuickCheckItem.medication(
        name: 'Lisinopril',
        rxcui: '29046',
        drugClasses: const ['class:ace_inhibitors'],
      );

      final results = await runQuickCheckPair(supplement, medication, db);

      expect(results, hasLength(1));
      expect(results.first.severity, Severity.caution);
      expect(results.first.agent1Name, 'Lisinopril');
      expect(results.first.agent2Name, 'Potassium Complex');
    });

    test(
      'finds safety-canonical interaction when DB row casing differs from catalog tag',
      () async {
        await db.batch((batch) {
          batch.insert(
            db.interactions,
            _interactionRow(
              id: 'STATINS_RYR',
              a1Type: 'drug_class',
              a1Id: 'class:statins',
              a1Name: 'Statins',
              a1Canonical: null,
              a2Canonical: 'BANNED_RED_YEAST_RICE',
              a2Name: 'Red Yeast Rice',
              severity: 'avoid',
            ),
          );
        });

        final supplement = QuickCheckItem.supplement(
          _product('RYR', 'Red Yeast Rice 600 mg', '["banned_red_yeast_rice"]'),
        );
        final medication = QuickCheckItem.medication(
          name: 'Atorvastatin',
          rxcui: '83367',
          drugClasses: const ['class:statins'],
        );

        final results = await runQuickCheckPair(supplement, medication, db);

        expect(results, hasLength(1));
        expect(results.single.id, 'STATINS_RYR');
        expect(results.single.severity, Severity.avoid);
      },
    );

    test('finds medication-medication interaction by RXCUI pair', () async {
      await db.batch((batch) {
        batch.insert(
          db.interactions,
          _interactionRow(
            id: 'WARFARIN_IBUPROFEN',
            a1Type: 'drug',
            a1Id: '11289',
            a1Name: 'Warfarin',
            a1Canonical: null,
            a2Type: 'drug',
            a2Id: '5640',
            a2Name: 'Ibuprofen',
            a2Canonical: null,
            severity: 'avoid',
          ),
        );
      });

      final a = QuickCheckItem.medication(name: 'Warfarin', rxcui: '11289');
      final b = QuickCheckItem.medication(name: 'Ibuprofen', rxcui: '5640');

      final results = await runQuickCheckPair(a, b, db);

      expect(results, hasLength(1));
      expect(results.first.severity, Severity.avoid);
      expect(results.first.agent1Name, 'Warfarin');
      expect(results.first.agent2Name, 'Ibuprofen');
    });

    // Phase 11.7L safety fix (Sean 2026-05-17): the previous
    // lookupPair-only loop missed "class-tag-on-a-drug" rows where a
    // curated row stores its class via the `agent_drug_class`
    // cross-ref column rather than as an explicit `agent_type =
    // drug_class` agent. lookupByDrugClass picks both shapes up; the
    // new class-fallback walks through it for every medication class
    // on either side.
    test(
      'finds med-med interaction via class-tag-on-a-drug cross-ref column',
      () async {
        await db.batch((batch) {
          batch.insert(
            db.interactions,
            _interactionRow(
              id: 'METH_TRIMETHOPRIM',
              a1Type: 'drug',
              a1Id: '6851',
              a1Name: 'Methotrexate',
              a1Canonical: null,
              a2Type: 'drug',
              a2Id: '10829',
              a2Name: 'Trimethoprim',
              a2Canonical: null,
              // Trimethoprim row tagged with antifolate class — the
              // exact shape lookupPair(drug, drug_class) misses.
              a2DrugClass: 'class:antifolates',
              severity: 'contraindicated',
            ),
          );
        });

        // User's drug doesn't match either explicit RXCUI but is in
        // the antifolate class — must still surface the row.
        final a = QuickCheckItem.medication(
          name: 'Methotrexate',
          rxcui: '6851',
        );
        final b = QuickCheckItem.medication(
          name: 'Sulfamethoxazole-Trimethoprim',
          rxcui: '99999', // not 10829
          drugClasses: const ['class:antifolates'],
        );

        final results = await runQuickCheckPair(a, b, db);
        expect(results, hasLength(1));
        expect(results.first.severity, Severity.contraindicated);
      },
    );

    test(
      'finds med-med via class-fallback when neither rxcui has a curated row',
      () async {
        // Sibling-class case: curated row is class-class only, the
        // user's specific brand RXCUIs aren't in the DB. Mirrors
        // StackInteractionChecker behavior.
        await db.batch((batch) {
          batch.insert(
            db.interactions,
            _interactionRow(
              id: 'ACE_NSAID',
              a1Type: 'drug_class',
              a1Id: 'class:ace_inhibitors',
              a1Name: 'ACE inhibitors',
              a1Canonical: null,
              a2Type: 'drug_class',
              a2Id: 'class:nsaids',
              a2Name: 'NSAIDs',
              a2Canonical: null,
              severity: 'caution',
            ),
          );
        });

        final a = QuickCheckItem.medication(
          name: 'Brand-X Lisinopril',
          rxcui: '111111',
          drugClasses: const ['class:ace_inhibitors'],
        );
        final b = QuickCheckItem.medication(
          name: 'Brand-Y Ibuprofen',
          rxcui: '222222',
          drugClasses: const ['class:nsaids'],
        );

        final results = await runQuickCheckPair(a, b, db);
        expect(results, hasLength(1));
        expect(results.first.severity, Severity.caution);
      },
    );

    test('returns empty when curated DB has no row for the pair', () async {
      // Safety rule: no row → empty list. Downstream UI must NOT
      // imply "safe" — only "no known interaction in our database."
      final a = QuickCheckItem.medication(
        name: 'Drug A',
        rxcui: '1',
        drugClasses: const ['class:a'],
      );
      final b = QuickCheckItem.medication(
        name: 'Drug B',
        rxcui: '2',
        drugClasses: const ['class:b'],
      );
      expect(await runQuickCheckPair(a, b, db), isEmpty);
    });
  });

  group('QuickCheckItem.hydrationIncomplete', () {
    test('supplements never report incomplete hydration', () {
      final supp = QuickCheckItem.supplement(
        _product('S', 'Vitamin D', '["vitamin_d"]'),
      );
      expect(supp.hydrationIncomplete, isFalse);
    });

    test('medication with no class / generic / ingredient is incomplete', () {
      // Freshly-picked med where RxNorm hydration failed or returned
      // nothing — only the bare brand RXCUI is set.
      final med = QuickCheckItem.medication(name: 'Brand-X', rxcui: '12345');
      expect(med.hydrationIncomplete, isTrue);
    });

    test('medication with at least one class is complete', () {
      final med = QuickCheckItem.medication(
        name: 'Lisinopril',
        rxcui: '29046',
        drugClasses: const ['class:ace_inhibitors'],
      );
      expect(med.hydrationIncomplete, isFalse);
    });

    test('medication with generic rxcui only is complete', () {
      final med = QuickCheckItem.medication(
        name: 'Brand-X',
        rxcui: '12345',
        genericRxcui: '67890',
      );
      expect(med.hydrationIncomplete, isFalse);
    });

    test('medication with ingredient rxcui only is complete', () {
      // Combination drug — multiple generic ingredients.
      final med = QuickCheckItem.medication(
        name: 'Combo',
        rxcui: '12345',
        ingredientRxcuis: const ['111', '222'],
      );
      expect(med.hydrationIncomplete, isFalse);
    });

    test('whitespace-only genericRxcui counts as missing', () {
      final med = QuickCheckItem.medication(
        name: 'Brand',
        rxcui: '12345',
        genericRxcui: '  ',
      );
      expect(med.hydrationIncomplete, isTrue);
    });
  });
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

// Test product fixture. `fingerprint` accepts either the legacy bare-
// list shape (`'["calcium"]'`) or the legacy keyed-map shape
// (`'{"calcium": {...}}'`) and projects the canonical ids into
// `keyIngredientTags` — the column production reads via
// `canonicalIdsForProduct`. Lets the pair-matching tests focus on
// interaction semantics instead of fingerprint parsing edge cases.
ProductsCoreData _product(String id, String name, String? fingerprint) {
  String? tagsJson;
  if (fingerprint != null && fingerprint.isNotEmpty) {
    try {
      final decoded = jsonDecode(fingerprint);
      List<String> ids = const [];
      if (decoded is List) {
        ids = decoded
            .where((e) => e != null)
            .map((e) => e.toString())
            .toList(growable: false);
      } else if (decoded is Map) {
        ids = decoded.keys.map((k) => k.toString()).toList(growable: false);
      }
      tagsJson = jsonEncode(ids);
    } on FormatException {
      tagsJson = null;
    }
  }
  return ProductsCoreData(
    dsldId: id,
    productName: name,
    productStatus: 'active',
    ingredientFingerprint: fingerprint,
    keyIngredientTags: tagsJson,
    exportVersion: 'test',
    exportedAt: '2026-04-16T00:00:00Z',
  );
}

InteractionsCompanion _interactionRow({
  required String id,
  String? a1Canonical,
  String? a2Canonical,
  String a1Type = 'supplement',
  String a2Type = 'supplement',
  String? a1Id,
  String? a2Id,
  String? a1Name,
  String? a2Name,
  String? a1DrugClass,
  String? a2DrugClass,
  String severity = 'caution',
}) {
  return InteractionsCompanion.insert(
    id: id,
    agent1Type: a1Type,
    agent1Name: a1Name ?? (a1Canonical ?? a1Id ?? 'Agent A'),
    agent1Id: a1Id ?? 'c_$a1Canonical',
    agent1CanonicalId: drift.Value(a1Canonical),
    agent1DrugClass: drift.Value(a1DrugClass),
    agent2Type: a2Type,
    agent2Name: a2Name ?? (a2Canonical ?? a2Id ?? 'Agent B'),
    agent2Id: a2Id ?? 'c_$a2Canonical',
    agent2CanonicalId: drift.Value(a2Canonical),
    agent2DrugClass: drift.Value(a2DrugClass),
    severity: severity,
    mechanism: 'Test mechanism',
    management: 'Test management',
    evidenceLevel: const drift.Value('established'),
    sourceUrlsJson: '["https://example.org/test"]',
    sourcePmidsJson: '[]',
    typeAuthored: 'curated',
    source: 'curated',
    provenance: 'test',
    versionAdded: '1.0.0',
    versionLastModified: '1.0.0',
    lastUpdated: '2026-04-11T00:00:00Z',
  );
}
