// Spec: INITIATIVE_PRODUCT_DETAIL_CLEANUP.md, Sprint S2.1, T3.
//
// Verifies the threshold table covers the headline false-positive
// cases (vitamin D + TTC, magnesium + diabetes, etc.), the
// canonicalization handles common pipeline-name shapes, and the
// teratogenic-retinol threshold fires correctly. T4 will exercise
// the table from inside the warning generator; here we just lock
// the data + lookup contract.

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/services/warnings/condition_thresholds.dart';

void main() {
  group('lookupConditionThreshold — headline false positives', () {
    test('vitamin D + TTC is positive (the bug-1 fix)', () {
      final entry = lookupConditionThreshold(
        conditionId: 'ttc',
        ingredientName: 'Vitamin D',
      );
      expect(entry, isNotNull);
      expect(entry!.directionality, NutrientDirectionality.positive);
    });

    test('vitamin D3 + TTC also positive (alias resolves)', () {
      final entry = lookupConditionThreshold(
        conditionId: 'ttc',
        ingredientName: 'Vitamin D3',
      );
      expect(entry, isNotNull);
      expect(entry!.directionality, NutrientDirectionality.positive);
    });

    test('vitamin D + diabetes is positive (the bug-2 fix)', () {
      final entry = lookupConditionThreshold(
        conditionId: 'diabetes',
        ingredientName: 'Vitamin D',
      );
      expect(entry, isNotNull);
      expect(entry!.directionality, NutrientDirectionality.positive);
    });

    test('magnesium + diabetes is positive', () {
      final entry = lookupConditionThreshold(
        conditionId: 'diabetes',
        ingredientName: 'Magnesium',
      );
      expect(entry, isNotNull);
      expect(entry!.directionality, NutrientDirectionality.positive);
    });

    test('magnesium glycinate + diabetes resolves via canonical alias', () {
      final entry = lookupConditionThreshold(
        conditionId: 'diabetes',
        ingredientName: 'Magnesium Glycinate',
      );
      expect(entry, isNotNull);
      expect(entry!.directionality, NutrientDirectionality.positive);
    });

    test('T16.2b — alpha-lipoic acid + diabetes is dose-gated at 600 mg', () {
      // PureLean ships 350 mg ALA → below threshold → suppressed.
      // Pipeline-side message itself states the trigger is
      // "≥ 600 mg/day alongside diabetes medications".
      final entry = lookupConditionThreshold(
        conditionId: 'diabetes',
        ingredientName: 'Alpha-lipoic acid',
      );
      expect(entry, isNotNull);
      expect(entry!.directionality, NutrientDirectionality.neutral);
      expect(entry.minDose, 600);
      expect(entry.doseUnit, 'mg');
    });

    test('T16.2b — alpha_lipoic_acid canonical form resolves', () {
      // Pipeline may stamp the canonical underscore form directly.
      final entry = lookupConditionThreshold(
        conditionId: 'diabetes',
        ingredientName: 'alpha_lipoic_acid',
      );
      expect(entry, isNotNull);
      expect(entry!.minDose, 600);
    });

    test('T16.2b — vanadium + diabetes threshold expressed in mcg '
        '(supplement-side units)', () {
      // Vanadium clinical effects: 50-200 mg pharmacologic doses.
      // Supplements ship in mcg (1000× lower). Threshold uses mcg
      // unit so the gate's exact-unit-match requirement doesn't
      // fail-safe-fire at typical supplement doses. PureLean has
      // 50 mcg → far below 50000 mcg threshold → suppressed.
      final entry = lookupConditionThreshold(
        conditionId: 'diabetes',
        ingredientName: 'Vanadium',
      );
      expect(entry, isNotNull);
      expect(entry!.directionality, NutrientDirectionality.neutral);
      expect(entry.minDose, 50000);
      expect(entry.doseUnit, 'mcg');
    });

    test('folate + pregnancy is positive (mandatory supplement)', () {
      final entry = lookupConditionThreshold(
        conditionId: 'pregnancy',
        ingredientName: 'Folate',
      );
      expect(entry, isNotNull);
      expect(entry!.directionality, NutrientDirectionality.positive);
    });

    test('T16.2e — cinnamon variants are positive for diabetes', () {
      // Cinnamomum cassia at 1-6 g/day is directionally beneficial for
      // glycemic control (NIH ODS). Tagging positive suppresses the
      // false-positive concern surface and unlocks the "supports your
      // blood sugar goal" bullet.
      for (final name in ['Cinnamon', 'Cinnamon Extract', 'Cinnamon Bark']) {
        final entry = lookupConditionThreshold(
          conditionId: 'diabetes',
          ingredientName: name,
        );
        expect(entry, isNotNull, reason: '$name should resolve');
        expect(
          entry!.directionality,
          NutrientDirectionality.positive,
          reason: '$name should be positive for diabetes',
        );
      }
    });

    test('T16.2e — inositol variants are positive for diabetes', () {
      // Myo-inositol established benefit for insulin sensitivity (PCOS-
      // related IR, 2-4 g/day).
      for (final name in ['Inositol', 'Myo-inositol', 'D-chiro-inositol']) {
        final entry = lookupConditionThreshold(
          conditionId: 'diabetes',
          ingredientName: name,
        );
        expect(entry, isNotNull, reason: '$name should resolve');
        expect(
          entry!.directionality,
          NutrientDirectionality.positive,
          reason: '$name should be positive for diabetes',
        );
      }
    });

    test('T16.2e — canonicalize strips punctuation (comma, parens)', () {
      // PureLean live walkthrough surfaced "Cinnamon Bark Extract,
      // Dried" leaking past the gate because pre-T16.2e canonicalize
      // preserved punctuation as literal characters in the key. This
      // anchors the punctuation-strip behavior for future regressions.
      expect(
        canonicalizeIngredientName('Cinnamon Bark Extract, Dried'),
        equals('cinnamon_bark_extract_dried'),
      );
      expect(
        canonicalizeIngredientName('Vitamin C (as ascorbic acid)'),
        equals('vitamin_c_as_ascorbic_acid'),
      );
      expect(
        canonicalizeIngredientName('Magnesium (oxide), USP'),
        equals('magnesium_oxide_usp'),
      );
      // Edge: leading/trailing punctuation collapsed and stripped.
      expect(canonicalizeIngredientName('(Iron)'), equals('iron'));
      // Pre-existing behavior preserved.
      expect(canonicalizeIngredientName('Vitamin D'), equals('vitamin_d'));
      expect(canonicalizeIngredientName('Vitamin-D3'), equals('vitamin_d3'));
    });

    test('T16.2e — Cinnamon Bark Extract, Dried resolves to positive', () {
      // Live PureLean leak: full DSLD label form. Should canonicalize
      // through the punctuation-strip and hit the dedicated entry.
      final entry = lookupConditionThreshold(
        conditionId: 'diabetes',
        ingredientName: 'Cinnamon Bark Extract, Dried',
      );
      expect(entry, isNotNull);
      expect(entry!.directionality, NutrientDirectionality.positive);
    });

    test('T16.2f — parenthetical strip fallback: '
        'Cinnamon (Cinnamomum cassia) extract → cinnamon_extract', () {
      // PureLean Pure Pack live walkthrough: pipeline embeds latin
      // name in parens. Direct canonical
      // `cinnamon_cinnamomum_cassia_extract` doesn't match — the
      // fallback strips the paren clause and re-canonicalizes to
      // `cinnamon_extract` which DOES match.
      final entry = lookupConditionThreshold(
        conditionId: 'diabetes',
        ingredientName: 'Cinnamon (Cinnamomum cassia) extract',
      );
      expect(entry, isNotNull);
      expect(entry!.directionality, NutrientDirectionality.positive);
    });

    test('T16.2f — parenthetical fallback handles percentage descriptors', () {
      // Same fallback applies to "(95%)" / "(2.5%)" descriptors.
      // Vitamin D positive for diabetes — must still match through paren.
      final entry = lookupConditionThreshold(
        conditionId: 'diabetes',
        ingredientName: 'Vitamin D (as cholecalciferol)',
      );
      expect(entry, isNotNull);
      expect(entry!.directionality, NutrientDirectionality.positive);
    });

    test('T16.2f — fallback skipped when name has no parens', () {
      // No-paren input takes the fast path (one map hit). Confirm
      // unknown ingredients still return null.
      final entry = lookupConditionThreshold(
        conditionId: 'diabetes',
        ingredientName: 'Reishi Mushroom',
      );
      expect(entry, isNull);
    });
  });

  group('lookupConditionThreshold — teratogenic-retinol gate', () {
    test(
      'retinol + pregnancy has neutral directionality + 3000 IU threshold',
      () {
        final entry = lookupConditionThreshold(
          conditionId: 'pregnancy',
          ingredientName: 'Retinol',
        );
        expect(entry, isNotNull);
        expect(entry!.directionality, NutrientDirectionality.neutral);
        expect(entry.minDose, 3000);
        expect(entry.doseUnit, 'IU');
      },
    );

    test(
      'vitamin A + ttc has 3000 IU threshold (pre-conception teratogenic)',
      () {
        final entry = lookupConditionThreshold(
          conditionId: 'ttc',
          ingredientName: 'Vitamin A',
        );
        expect(entry, isNotNull);
        expect(entry!.directionality, NutrientDirectionality.neutral);
        expect(entry.minDose, 3000);
        expect(entry.doseUnit, 'IU');
      },
    );
  });

  group('lookupConditionThreshold — bleeding-disorder dose gates', () {
    test('omega-3 + bleeding_disorders fires above 3000 mg', () {
      final entry = lookupConditionThreshold(
        conditionId: 'bleeding_disorders',
        ingredientName: 'Omega 3',
      );
      expect(entry, isNotNull);
      expect(entry!.directionality, NutrientDirectionality.neutral);
      expect(entry.minDose, 3000);
      expect(entry.doseUnit, 'mg');
    });

    test('ginkgo + bleeding_disorders fires above 120 mg (standard dose)', () {
      final entry = lookupConditionThreshold(
        conditionId: 'bleeding_disorders',
        ingredientName: 'Ginkgo',
      );
      expect(entry, isNotNull);
      expect(entry!.minDose, 120);
      expect(entry.doseUnit, 'mg');
    });
  });

  group('lookupConditionThreshold — kidney mineral overload gates', () {
    test('magnesium + kidney_disease fires above 400 mg', () {
      final entry = lookupConditionThreshold(
        conditionId: 'kidney_disease',
        ingredientName: 'Magnesium',
      );
      expect(entry, isNotNull);
      expect(entry!.directionality, NutrientDirectionality.neutral);
      expect(entry.minDose, 400);
    });

    test('vitamin D + kidney_disease has 4000 IU threshold (NOT positive)', () {
      // Important: vitamin D is generally positive but kidney disease
      // narrows that — high doses of D drive Ca/P concerns. The table
      // must distinguish this from generic-positive Vit D.
      final entry = lookupConditionThreshold(
        conditionId: 'kidney_disease',
        ingredientName: 'Vitamin D',
      );
      expect(entry, isNotNull);
      expect(entry!.directionality, NutrientDirectionality.neutral);
      expect(entry.minDose, 4000);
      expect(entry.doseUnit, 'IU');
    });
  });

  group('lookupConditionThreshold — canonicalization', () {
    test('whitespace + casing variants resolve to the same key', () {
      final a = lookupConditionThreshold(
        conditionId: 'ttc',
        ingredientName: 'Vitamin D',
      );
      final b = lookupConditionThreshold(
        conditionId: 'ttc',
        ingredientName: '  vitamin d  ',
      );
      final c = lookupConditionThreshold(
        conditionId: 'ttc',
        ingredientName: 'VITAMIN D',
      );
      expect(a, isNotNull);
      expect(b, isNotNull);
      expect(c, isNotNull);
      expect(a!.directionality, b!.directionality);
      expect(b.directionality, c!.directionality);
    });

    test('hyphen-separated names resolve (vitamin-d3 → vitamin_d3)', () {
      final entry = lookupConditionThreshold(
        conditionId: 'pregnancy',
        ingredientName: 'Vitamin-D3',
      );
      expect(entry, isNotNull);
      expect(entry!.directionality, NutrientDirectionality.positive);
    });

    test('multi-word ingredients resolve (Magnesium Glycinate)', () {
      final entry = lookupConditionThreshold(
        conditionId: 'hypertension',
        ingredientName: 'Magnesium Glycinate',
      );
      expect(entry, isNotNull);
      expect(entry!.directionality, NutrientDirectionality.positive);
    });

    test('condition id is also case-trimmed', () {
      final entry = lookupConditionThreshold(
        conditionId: '  TTC  ',
        ingredientName: 'Vitamin D',
      );
      expect(entry, isNotNull);
    });

    test('empty ingredient name returns null', () {
      expect(
        lookupConditionThreshold(conditionId: 'ttc', ingredientName: ''),
        isNull,
      );
      expect(
        lookupConditionThreshold(conditionId: 'ttc', ingredientName: '   '),
        isNull,
      );
    });
  });

  group('lookupConditionThreshold — passthrough fallback', () {
    test('unknown condition returns null (caller falls through)', () {
      expect(
        lookupConditionThreshold(
          conditionId: 'made_up_condition',
          ingredientName: 'Vitamin D',
        ),
        isNull,
      );
    });

    test('unknown ingredient returns null (caller falls through)', () {
      expect(
        lookupConditionThreshold(
          conditionId: 'ttc',
          ingredientName: 'Reishi Mushroom',
        ),
        isNull,
      );
    });

    test('absent (condition, ingredient) pair returns null', () {
      // Iron has TTC + pregnancy entries but not hypertension.
      expect(
        lookupConditionThreshold(
          conditionId: 'hypertension',
          ingredientName: 'Iron',
        ),
        isNull,
      );
    });
  });

  group('ConditionThreshold construction invariants', () {
    test('positive entry has no minDose / doseUnit', () {
      const t = ConditionThreshold.positive(rationale: 'test');
      expect(t.directionality, NutrientDirectionality.positive);
      expect(t.minDose, isNull);
      expect(t.doseUnit, isNull);
    });

    test('aboveDose entry carries dose + unit + neutral directionality', () {
      const t = ConditionThreshold.aboveDose(
        minDose: 100,
        doseUnit: 'mg',
        rationale: 'test',
      );
      expect(t.directionality, NutrientDirectionality.neutral);
      expect(t.minDose, 100);
      expect(t.doseUnit, 'mg');
    });
  });

  group('generatePositiveProfileBullets — Path A extension (T12 prep)', () {
    test('empty ingredients → empty list', () {
      expect(
        generatePositiveProfileBullets(
          ingredientNames: const [],
          userConditionIds: const ['ttc'],
        ),
        isEmpty,
      );
    });

    test('empty conditions → empty list', () {
      expect(
        generatePositiveProfileBullets(
          ingredientNames: const ['Vitamin D'],
          userConditionIds: const [],
        ),
        isEmpty,
      );
    });

    test('vitamin D + TTC → "is recommended during pre-conception"', () {
      final bullets = generatePositiveProfileBullets(
        ingredientNames: const ['Vitamin D'],
        userConditionIds: const ['ttc'],
      );
      expect(bullets, hasLength(1));
      expect(bullets.first, 'Vitamin D is recommended during pre-conception');
    });

    test('magnesium + hypertension → "supports your blood pressure goal"', () {
      final bullets = generatePositiveProfileBullets(
        ingredientNames: const ['Magnesium'],
        userConditionIds: const ['hypertension'],
      );
      expect(bullets, hasLength(1));
      expect(bullets.first, 'Magnesium supports your blood pressure goal');
    });

    test('multiple conditions → multiple bullets, condition-major order', () {
      final bullets = generatePositiveProfileBullets(
        ingredientNames: const ['Vitamin D', 'Magnesium'],
        userConditionIds: const ['hypertension', 'diabetes'],
      );
      expect(bullets, hasLength(2));
      // Hypertension comes first because it's first in the conditions
      // list. Magnesium is the only ingredient positive for it.
      expect(bullets[0], 'Magnesium supports your blood pressure goal');
      // Diabetes second. Vit D is positive for diabetes and comes
      // first in the ingredients list, so it wins (max-one-per-condition
      // rule picks the first matching ingredient).
      expect(bullets[1], 'Vitamin D supports your blood sugar goal');
    });

    test(
      'reordering conditions changes bullet order (caller controls priority)',
      () {
        final bullets = generatePositiveProfileBullets(
          ingredientNames: const ['Vitamin D', 'Magnesium'],
          userConditionIds: const ['diabetes', 'hypertension'],
        );
        expect(bullets, hasLength(2));
        expect(bullets[0], 'Vitamin D supports your blood sugar goal');
        expect(bullets[1], 'Magnesium supports your blood pressure goal');
      },
    );

    test('duplicate ingredient forms emit only ONE bullet per condition', () {
      // Common multi-form magnesium product — `Magnesium`, `Magnesium
      // Glycinate`, `Magnesium Citrate` all positive for hypertension.
      // The 2-bullet card budget shouldn't be burned on one nutrient.
      final bullets = generatePositiveProfileBullets(
        ingredientNames: const [
          'Magnesium',
          'Magnesium Glycinate',
          'Magnesium Citrate',
        ],
        userConditionIds: const ['hypertension'],
      );
      expect(bullets, hasLength(1));
      // First-match wins → 'Magnesium' (the bare form, listed first).
      expect(bullets.first, contains('Magnesium'));
    });

    test('duplicate condition entries dedup', () {
      final bullets = generatePositiveProfileBullets(
        ingredientNames: const ['Vitamin D'],
        userConditionIds: const ['ttc', 'ttc', 'ttc'],
      );
      expect(bullets, hasLength(1));
    });

    test('neutral directionality (Vitamin A + pregnancy) emits NO bullet', () {
      // Vit A is teratogenic above 3000 IU during pregnancy — that's
      // a neutral/threshold entry, not positive. The bullet generator
      // must NOT credit it as beneficial.
      final bullets = generatePositiveProfileBullets(
        ingredientNames: const ['Vitamin A'],
        userConditionIds: const ['pregnancy'],
      );
      expect(bullets, isEmpty);
    });

    test('condition without phrase mapping is silently skipped', () {
      // bleeding_disorders has no `positive` entries AND no phrase —
      // the helper must handle this without throwing or emitting
      // partial bullets.
      final bullets = generatePositiveProfileBullets(
        ingredientNames: const ['Vitamin D', 'Magnesium', 'Omega 3'],
        userConditionIds: const ['bleeding_disorders'],
      );
      expect(bullets, isEmpty);
    });

    test(
      'display name resolves canonical aliases (vitamin_d3 → Vitamin D3)',
      () {
        final bullets = generatePositiveProfileBullets(
          ingredientNames: const ['vitamin_d3'],
          userConditionIds: const ['lactation'],
        );
        expect(bullets, hasLength(1));
        expect(bullets.first, 'Vitamin D3 is recommended during breastfeeding');
      },
    );

    test(
      'multi-word ingredient prettifies (magnesium_glycinate → Magnesium Glycinate)',
      () {
        final bullets = generatePositiveProfileBullets(
          ingredientNames: const ['magnesium_glycinate'],
          userConditionIds: const ['diabetes'],
        );
        expect(bullets, hasLength(1));
        expect(
          bullets.first,
          'Magnesium Glycinate supports your blood sugar goal',
        );
      },
    );

    test('mixed positive and neutral product → only positives surface', () {
      // Product has Vit A (neutral for pregnancy) + Folate (positive)
      // + Iron (positive). User is pregnant. Result: 2 positive bullets,
      // both deduped to one because both are positive for pregnancy
      // and the helper picks the first matching ingredient.
      final bullets = generatePositiveProfileBullets(
        ingredientNames: const ['Vitamin A', 'Folate', 'Iron'],
        userConditionIds: const ['pregnancy'],
      );
      expect(bullets, hasLength(1));
      expect(bullets.first, 'Folate is recommended during pregnancy');
    });
  });
}
