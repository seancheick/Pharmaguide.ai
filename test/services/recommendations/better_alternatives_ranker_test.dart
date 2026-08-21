// Phase 11.7L.F — Better Alternatives ranker regression tests.
//
// The 5 pinned scenarios in `knowledge/better-alternatives-audit.md`
// are encoded here as fixtures. Each test:
//
//   * builds a synthetic current product matching the real catalog
//     entry's shape (dsld_id, supplement_type, audience markers in
//     the name, key_ingredient_tags JSON, score)
//   * builds 3-5 candidate products matching the buggy
//     recommendations that the legacy `findAlternatives` would
//     have surfaced (including the discontinued ones)
//   * asserts the new ranker:
//       a) NEVER returns the buggy recommendation
//       b) DOES return a sensibly-better swap when one is seeded
//       c) NEVER returns an off-market or lower-score product
//
// The fixtures use real catalog dsld_ids so a future scoring or
// catalog rebuild that renames a product fails the test loudly —
// a deliberate trip-wire against silent regressions in the
// recommendation surface.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/services/recommendations/better_alternatives_ranker.dart';

ProductsCoreData _product({
  required String dsldId,
  required String name,
  String? brand,
  String? supplementType,
  String? primaryCategory,
  double? qualityScoreV4100,
  String? qualityTier,
  String? qualityScoreStatus = 'scored',
  String? discontinuedDate,
  String? keyIngredientTags,
  String? goalMatches,
  int containsOmega3 = 0,
  int containsProbiotics = 0,
  int containsCollagen = 0,
  int containsAdaptogens = 0,
  int containsNootropics = 0,
  int isProbiotic = 0,
  int isGlutenFree = 0,
  int isDairyFree = 0,
  int isSoyFree = 0,
  int isVegan = 0,
  int isVegetarian = 0,
  int isOrganic = 0,
  int isNonGmo = 0,
  int hasBannedSubstance = 0,
  int hasRecalledIngredient = 0,
  double? mappedCoverage,
  String? ingredientFingerprint,
}) {
  return ProductsCoreData(
    dsldId: dsldId,
    productName: name,
    brandName: brand,
    supplementType: supplementType,
    primaryCategory: primaryCategory,
    qualityScoreV4100: qualityScoreV4100,
    qualityTier: qualityTier,
    qualityScoreStatus: qualityScoreStatus,
    discontinuedDate: discontinuedDate,
    keyIngredientTags: keyIngredientTags,
    goalMatches: goalMatches,
    containsOmega3: containsOmega3,
    containsProbiotics: containsProbiotics,
    containsCollagen: containsCollagen,
    containsAdaptogens: containsAdaptogens,
    containsNootropics: containsNootropics,
    isProbiotic: isProbiotic,
    isGlutenFree: isGlutenFree,
    isDairyFree: isDairyFree,
    isSoyFree: isSoyFree,
    isVegan: isVegan,
    isVegetarian: isVegetarian,
    isOrganic: isOrganic,
    isNonGmo: isNonGmo,
    hasBannedSubstance: hasBannedSubstance,
    hasRecalledIngredient: hasRecalledIngredient,
    mappedCoverage: mappedCoverage,
    ingredientFingerprint: ingredientFingerprint,
    exportVersion: 'test',
    exportedAt: '2026-05-16T00:00:00Z',
  );
}

Future<void> _insertPoolProduct(
  CoreDatabase db, {
  required String dsldId,
  required String name,
  required String supplementType,
  required double score,
  required String keyIngredientTags,
  String brand = 'Test Brand',
}) {
  return db
      .into(db.productsCore)
      .insert(
        ProductsCoreCompanion.insert(
          dsldId: dsldId,
          productName: name,
          exportVersion: 'test',
          exportedAt: '2026-07-21T00:00:00Z',
          brandName: Value(brand),
          supplementType: Value(supplementType),
          primaryCategory: Value(supplementType),
          qualityScoreV4100: Value(score),
          qualityScoreStatus: const Value('scored'),
          keyIngredientTags: Value(keyIngredientTags),
        ),
      );
}

void main() {
  group('Hard filters', () {
    test('drops self-recommendations', () {
      final cur = _product(
        dsldId: 'self',
        name: 'Multivitamin',
        supplementType: 'multivitamin',
        primaryCategory: 'multivitamin',
        qualityScoreV4100: 30,
      );
      final result = rankAlternatives(current: cur, candidates: [cur]);
      expect(result, isEmpty);
    });

    test('drops off-market candidates (discontinuedDate set)', () {
      final cur = _product(
        dsldId: 'cur',
        name: 'Probiotic',
        supplementType: 'probiotic',
        primaryCategory: 'probiotic',
        qualityScoreV4100: 25,
      );
      final offMarket = _product(
        dsldId: 'off',
        name: 'Restore',
        supplementType: 'probiotic',
        primaryCategory: 'probiotic',
        qualityScoreV4100: 62,
        discontinuedDate: '2024-01-01',
      );
      final onMarket = _product(
        dsldId: 'on',
        name: 'Trust Your Gut',
        supplementType: 'probiotic',
        primaryCategory: 'probiotic',
        qualityScoreV4100: 58,
      );
      final result = rankAlternatives(
        current: cur,
        candidates: [offMarket, onMarket],
      );
      expect(result.map((p) => p.dsldId), equals(['on']));
    });

    test('unscored current still returns a scored same-intent candidate', () {
      // Sean's Phase 11.7L.F follow-up: blocked products like
      // dsld 16012 Vinpocetine ship with `quality_score_v4_100 = NULL`.
      // The user MUST still see safer alternatives — treat the
      // missing score as "lower than any scored candidate."
      final blockedNootropic = _product(
        dsldId: '16012',
        name: 'Blocked Nootropic Support',
        brand: 'Thorne Research',
        supplementType: 'nootropic_support',
        // primaryCategory + qualityScoreV4100 intentionally NULL —
        // mirrors the live catalog row.
      );
      final saferAlt = _product(
        dsldId: 'safer-alt',
        name: 'Scored Nootropic Support',
        brand: 'Pure Encapsulations',
        supplementType: 'nootropic_support',
        qualityScoreV4100: 65,
      );
      final result = rankAlternatives(
        current: blockedNootropic,
        candidates: [saferAlt],
      );
      expect(
        result.map((p) => p.dsldId),
        equals(['safer-alt']),
        reason:
            'Blocked products with null qualityScoreV4100 must still '
            "surface scored alternatives — that's the user's whole "
            'reason for landing on this section.',
      );
    });

    test('drops candidates with score ≤ current (strictly higher only)', () {
      final cur = _product(
        dsldId: 'cur',
        name: 'Daily Multi',
        supplementType: 'multivitamin',
        primaryCategory: 'multivitamin',
        qualityScoreV4100: 50,
      );
      final tied = _product(
        dsldId: 'tied',
        name: 'Tied Score Multi',
        supplementType: 'multivitamin',
        primaryCategory: 'multivitamin',
        qualityScoreV4100: 50,
      );
      final higher = _product(
        dsldId: 'higher',
        name: 'Higher Multi',
        supplementType: 'multivitamin',
        primaryCategory: 'multivitamin',
        qualityScoreV4100: 65,
      );
      final result = rankAlternatives(current: cur, candidates: [tied, higher]);
      expect(result.map((p) => p.dsldId), equals(['higher']));
    });

    test('drops banned + recalled candidates', () {
      final cur = _product(
        dsldId: 'cur',
        name: 'X',
        supplementType: 'multivitamin',
        primaryCategory: 'multivitamin',
        qualityScoreV4100: 30,
      );
      final banned = _product(
        dsldId: 'banned',
        name: 'Banned Multi',
        supplementType: 'multivitamin',
        primaryCategory: 'multivitamin',
        qualityScoreV4100: 80,
        hasBannedSubstance: 1,
      );
      final recalled = _product(
        dsldId: 'recalled',
        name: 'Recalled Multi',
        supplementType: 'multivitamin',
        primaryCategory: 'multivitamin',
        qualityScoreV4100: 78,
        hasRecalledIngredient: 1,
      );
      final ok = _product(
        dsldId: 'ok',
        name: 'OK Multi',
        supplementType: 'multivitamin',
        primaryCategory: 'multivitamin',
        qualityScoreV4100: 70,
      );
      final result = rankAlternatives(
        current: cur,
        candidates: [banned, recalled, ok],
      );
      expect(result.map((p) => p.dsldId), equals(['ok']));
    });
  });

  // ===========================================================================
  // Pinned regression cases — see knowledge/better-alternatives-audit.md
  // for the legacy buggy recommendations these guard against.
  // ===========================================================================

  group('Regression: Audit case #1 — Staminol (men herbal) ↛ prenatal', () {
    test("doesn't recommend prenatal product to male herbal blend", () {
      final staminol = _product(
        dsldId: '315814',
        name: 'Staminol',
        brand: 'GNC Mega Men',
        supplementType: 'herbal_blend',
        primaryCategory: 'multivitamin',
        qualityScoreV4100: 18.5,
      );
      // The legacy top recommendation:
      final basicPrenatal = _product(
        dsldId: '328830',
        name: 'Basic Prenatal',
        brand: 'Thorne',
        supplementType: 'multivitamin',
        primaryCategory: 'multivitamin',
        qualityScoreV4100: 72.4,
      );
      // A discontinued legacy recommendation:
      final advancedNutrients = _product(
        dsldId: '313907',
        name: 'Advanced Nutrients',
        brand: 'Thorne',
        supplementType: 'multivitamin',
        primaryCategory: 'multivitamin',
        qualityScoreV4100: 71.8,
        discontinuedDate: '2023-05-01',
      );
      // What a sensible swap looks like — same supplement_type,
      // same audience (men's herbal energy blend):
      final mensEnergyBlend = _product(
        dsldId: 'better-mens-energy',
        name: "Men's Energy Herbal Stack",
        brand: 'AnotherBrand',
        supplementType: 'herbal_blend',
        primaryCategory: 'multivitamin',
        qualityScoreV4100: 55,
        keyIngredientTags: '["ginseng","tribulus","maca"]',
      );

      final result = rankAlternatives(
        current: staminol,
        candidates: [basicPrenatal, advancedNutrients, mensEnergyBlend],
      );

      final ids = result.map((p) => p.dsldId).toList();
      expect(
        ids,
        contains('better-mens-energy'),
        reason: 'A same-type same-audience swap should always win.',
      );
      expect(
        ids,
        isNot(contains('328830')),
        reason: 'Prenatal cross-audience must be blocked.',
      );
      expect(
        ids,
        isNot(contains('313907')),
        reason: 'Off-market must be filtered.',
      );
    });
  });

  group('Regression: Audit case #2 — Vitamin A targeted ↛ kids chewable', () {
    test('single-ingredient targeted does not recommend kids multi or '
        'discontinued', () {
      final vitA = _product(
        dsldId: '19170',
        name: 'A 8,000 IU',
        brand: 'CVS Pharmacy',
        supplementType: 'targeted',
        primaryCategory: 'omega-3', // legacy mis-categorisation
        qualityScoreV4100: 37.0,
        keyIngredientTags: '["vitamin_a"]',
      );
      final kidsMulti = _product(
        dsldId: '281264',
        name: 'Kids Multi + Strawberry Kiwi',
        brand: 'Thorne',
        supplementType: 'multivitamin',
        primaryCategory: 'omega-3',
        qualityScoreV4100: 68.8,
        discontinuedDate: '2024-06-01',
      );
      final synaQuell = _product(
        dsldId: '337875',
        name: 'SynaQuell',
        brand: 'Thorne',
        supplementType: 'multivitamin',
        primaryCategory: 'omega-3',
        qualityScoreV4100: 69.0,
      );
      final aTargeted = _product(
        dsldId: 'better-a-targeted',
        name: 'Vitamin A 10,000 IU',
        brand: 'GoodBrand',
        supplementType: 'targeted',
        primaryCategory: 'omega-3',
        qualityScoreV4100: 58,
        keyIngredientTags: '["vitamin_a"]',
      );

      final result = rankAlternatives(
        current: vitA,
        candidates: [kidsMulti, synaQuell, aTargeted],
      );
      final ids = result.map((p) => p.dsldId).toList();
      expect(
        ids,
        contains('better-a-targeted'),
        reason: 'Same supplement_type=targeted should win.',
      );
      expect(
        ids,
        isNot(contains('281264')),
        reason: 'Kids cross-audience + off-market must be blocked.',
      );
    });
  });

  group('Regression: Audit case #3 — GNC Probiotic ↛ discontinued Restore', () {
    test('probiotic does not recommend off-market #1 or magnesium-gummy', () {
      final gncProb = _product(
        dsldId: '1646',
        name: 'Probiotic Complex 1',
        brand: 'GNC Probiotics',
        supplementType: 'probiotic',
        primaryCategory: 'probiotic',
        qualityScoreV4100: 25.3,
        isProbiotic: 1,
      );
      final restore = _product(
        dsldId: '15581',
        name: 'Restore',
        brand: 'Thorne Performance',
        supplementType: 'probiotic',
        primaryCategory: 'probiotic',
        qualityScoreV4100: 62.4,
        discontinuedDate: '2024-02-01',
        isProbiotic: 1,
      );
      final magnesiumGummy = _product(
        dsldId: '297681',
        name: 'Magnesium with Pre & Probiotics Gummies',
        brand: 'Garden of Life Dr. Formulated',
        supplementType: 'specialty',
        primaryCategory: 'probiotic',
        qualityScoreV4100: 58.0,
        keyIngredientTags: '["magnesium","probiotic"]',
        containsProbiotics: 1,
      );
      final trueProb = _product(
        dsldId: '251907',
        name: 'Trust Your Gut.',
        brand: 'Ora',
        supplementType: 'probiotic',
        primaryCategory: 'probiotic',
        qualityScoreV4100: 58.3,
        isProbiotic: 1,
        keyIngredientTags: '["lactobacillus","bifidobacterium"]',
      );

      final result = rankAlternatives(
        current: gncProb,
        candidates: [restore, magnesiumGummy, trueProb],
      );
      final ids = result.map((p) => p.dsldId).toList();
      expect(
        ids,
        isNot(contains('15581')),
        reason: 'Off-market must be filtered.',
      );
      expect(
        ids.first,
        equals('251907'),
        reason:
            'Probiotic-first product (251907) should outrank '
            'magnesium-with-probiotics (297681) because it shares '
            'supplement_type and the probiotic family flag.',
      );
    });
  });

  group('Regression: Audit case #4 — Kids multi ↛ prenatal/adult', () {
    test('children\'s multivitamin does not recommend prenatal or adult', () {
      final kidsMulti = _product(
        dsldId: '178559',
        name: 'Children\'s Multivitamin Gummies',
        brand: 'Spring Valley',
        supplementType: 'multivitamin',
        primaryCategory: 'multivitamin',
        qualityScoreV4100: 44.1,
      );
      final adultMulti = _product(
        dsldId: '336315',
        name: 'A.M.',
        brand: 'Thorne',
        supplementType: 'multivitamin',
        primaryCategory: 'multivitamin',
        qualityScoreV4100: 72.6,
      );
      final prenatal = _product(
        dsldId: '328830',
        name: 'Basic Prenatal',
        brand: 'Thorne',
        supplementType: 'multivitamin',
        primaryCategory: 'multivitamin',
        qualityScoreV4100: 72.4,
      );
      final discontinued = _product(
        dsldId: '313907',
        name: 'Advanced Nutrients',
        brand: 'Thorne',
        supplementType: 'multivitamin',
        primaryCategory: 'multivitamin',
        qualityScoreV4100: 71.8,
        discontinuedDate: '2023-05-01',
      );
      final betterKids = _product(
        dsldId: 'better-kids-multi',
        name: "Kids' Daily Chewable Multi",
        brand: 'NicerBrand',
        supplementType: 'multivitamin',
        primaryCategory: 'multivitamin',
        qualityScoreV4100: 60,
      );

      final result = rankAlternatives(
        current: kidsMulti,
        candidates: [adultMulti, prenatal, discontinued, betterKids],
      );
      final ids = result.map((p) => p.dsldId).toList();
      expect(
        ids,
        contains('better-kids-multi'),
        reason: 'Same-audience kids swap should win.',
      );
      expect(
        ids,
        isNot(contains('336315')),
        reason: 'Adult cross-audience must be blocked.',
      );
      expect(
        ids,
        isNot(contains('328830')),
        reason: 'Prenatal cross-audience must be blocked.',
      );
      expect(
        ids,
        isNot(contains('313907')),
        reason: 'Off-market must be filtered.',
      );
    });
  });

  group(
    'Regression: Audit case #5 — score ties do NOT qualify as "better"',
    () {
      test('candidate with equal score is dropped (no > operator)', () {
        final cur = _product(
          dsldId: 'cur',
          name: 'Tied Multi',
          supplementType: 'multivitamin',
          primaryCategory: 'multivitamin',
          qualityScoreV4100: 50,
        );
        final tied = _product(
          dsldId: 'tied',
          name: 'Tied Multi B',
          supplementType: 'multivitamin',
          primaryCategory: 'multivitamin',
          qualityScoreV4100: 50,
        );
        final result = rankAlternatives(current: cur, candidates: [tied]);
        expect(result, isEmpty);
      });
    },
  );

  // ===========================================================================
  // Sport ↔ general carve-out
  // ===========================================================================

  group('Sport ↔ general carve-out', () {
    test('general wellness candidate blocked from sport product unless '
        'ingredient overlap ≥ 0.5', () {
      final sportPre = _product(
        dsldId: 'cur',
        name: 'Pre-Workout Cherry',
        supplementType: 'sport',
        primaryCategory: 'sport',
        qualityScoreV4100: 40,
        keyIngredientTags: '["caffeine","beta_alanine","citrulline"]',
      );
      // General product with NO ingredient overlap — should be
      // dropped by the sport↔general carve-out.
      final unrelatedGeneral = _product(
        dsldId: 'unrelated',
        name: 'Magnesium Glycinate',
        supplementType: 'targeted',
        primaryCategory: 'sport',
        qualityScoreV4100: 70,
        keyIngredientTags: '["magnesium"]',
      );
      // General product with HIGH ingredient overlap — should be
      // allowed through.
      final overlappingGeneral = _product(
        dsldId: 'overlap',
        name: 'Caffeine + Beta Alanine Stack',
        supplementType: 'targeted',
        primaryCategory: 'sport',
        qualityScoreV4100: 60,
        keyIngredientTags: '["caffeine","beta_alanine","creatine"]',
      );

      final result = rankAlternatives(
        current: sportPre,
        candidates: [unrelatedGeneral, overlappingGeneral],
      );
      final ids = result.map((p) => p.dsldId).toList();
      expect(
        ids,
        contains('overlap'),
        reason: 'High-overlap general should pass the carveout.',
      );
      expect(
        ids,
        isNot(contains('unrelated')),
        reason: 'No-overlap general must be blocked.',
      );
    });
  });

  // ===========================================================================
  // Tier ordering
  // ===========================================================================

  group('Tier ordering', () {
    test('same supplement_type + high ingredient overlap (tier A) outranks '
        'same supplement_type only (tier B) at lower score', () {
      final cur = _product(
        dsldId: 'cur',
        name: 'Omega-3 Fish Oil',
        supplementType: 'targeted',
        primaryCategory: 'omega-3',
        qualityScoreV4100: 30,
        containsOmega3: 1,
        keyIngredientTags: '["fish_oil","epa","dha"]',
      );
      // Tier B: same supplement_type, different ingredient family.
      final tierB = _product(
        dsldId: 'tier-b',
        name: 'Vitamin D 5000 IU',
        supplementType: 'targeted',
        primaryCategory: 'omega-3',
        qualityScoreV4100: 78, // higher score
        keyIngredientTags: '["vitamin_d3"]',
      );
      // Tier A: same supplement_type AND high family overlap.
      final tierA = _product(
        dsldId: 'tier-a',
        name: 'Fish Oil 1200mg',
        supplementType: 'targeted',
        primaryCategory: 'omega-3',
        qualityScoreV4100: 55, // lower score, next shipped fallback tier
        containsOmega3: 1,
        keyIngredientTags: '["fish_oil","epa","dha"]',
      );

      final result = rankAlternatives(current: cur, candidates: [tierB, tierA]);
      expect(
        result.first.dsldId,
        equals('tier-a'),
        reason:
            'Tier A (intent+family match) must outrank Tier B even at '
            'a lower score.',
      );
    });

    test('tiebreaker chain — within same tier, higher score wins', () {
      final cur = _product(
        dsldId: 'cur',
        name: 'Probiotic',
        supplementType: 'probiotic',
        primaryCategory: 'probiotic',
        qualityScoreV4100: 25,
        isProbiotic: 1,
      );
      final lowerScore = _product(
        dsldId: 'lower',
        name: 'Probiotic A',
        supplementType: 'probiotic',
        primaryCategory: 'probiotic',
        qualityScoreV4100: 60,
        isProbiotic: 1,
      );
      final higherScore = _product(
        dsldId: 'higher',
        name: 'Probiotic B',
        supplementType: 'probiotic',
        primaryCategory: 'probiotic',
        qualityScoreV4100: 75,
        isProbiotic: 1,
      );
      final result = rankAlternatives(
        current: cur,
        candidates: [lowerScore, higherScore],
      );
      expect(result.first.dsldId, equals('higher'));
    });
  });

  // ===========================================================================
  // userGoals personalization tiebreaker — Phase 11.7L freeze-safe.
  //
  // The ranker accepts an optional `userGoals: Set<String>?` and prefers
  // candidates whose `goal_matches` overlap with the user's saved goals.
  // When `userGoals` is null/empty, the tiebreaker falls back to the
  // product-to-product `goal_matches` Jaccard (no personalization).
  // These tests pin both branches.
  // ===========================================================================

  group('userGoals tiebreaker', () {
    test('when user has goals, candidate matching those goals beats one '
        'that does not — even at the same tier + same score', () {
      final cur = _product(
        dsldId: 'cur',
        name: 'Magnesium Glycinate',
        supplementType: 'targeted',
        primaryCategory: 'mineral',
        qualityScoreV4100: 30,
        keyIngredientTags: '["magnesium","glycinate"]',
      );
      // Both candidates are same tier (same supplement_type + family
      // overlap), same score → ranker would tie-break on the next
      // criterion. Without user goals, the tie is broken by score
      // (same here) → mapped_coverage → allergen compatibility. With user
      // goals, the goal-Jaccard tiebreaker must outrank those.
      final goalAligned = _product(
        dsldId: 'aligned',
        name: 'Magnesium Calm',
        supplementType: 'targeted',
        primaryCategory: 'mineral',
        qualityScoreV4100: 60,
        keyIngredientTags: '["magnesium","glycinate"]',
        goalMatches: '["GOAL_SLEEP_QUALITY","GOAL_REDUCE_STRESS_ANXIETY"]',
      );
      final goalMismatched = _product(
        dsldId: 'mismatched',
        name: 'Magnesium Boost',
        supplementType: 'targeted',
        primaryCategory: 'mineral',
        qualityScoreV4100: 60,
        keyIngredientTags: '["magnesium","glycinate"]',
        goalMatches: '["GOAL_MUSCLE_GROWTH_RECOVERY"]',
      );

      final result = rankAlternatives(
        current: cur,
        candidates: [goalMismatched, goalAligned],
        userGoals: {'GOAL_SLEEP_QUALITY', 'GOAL_IMMUNE_SUPPORT'},
      );
      expect(
        result.first.dsldId,
        equals('aligned'),
        reason:
            "Goal-aligned candidate must outrank the mismatched candidate "
            'when userGoals are present — that is the whole '
            'point of the personalization hook.',
      );
    });

    test('when userGoals is null, ranker falls back to product-to-product '
        'goal Jaccard (no personalization, no crash)', () {
      final cur = _product(
        dsldId: 'cur',
        name: 'Sleep Multi',
        supplementType: 'multivitamin',
        primaryCategory: 'multivitamin',
        qualityScoreV4100: 30,
        goalMatches: '["GOAL_SLEEP_QUALITY"]',
      );
      // Candidate that shares the current product's goal_matches.
      final sharesGoal = _product(
        dsldId: 'shares',
        name: 'Sleep Support Multi',
        supplementType: 'multivitamin',
        primaryCategory: 'multivitamin',
        qualityScoreV4100: 60,
        goalMatches: '["GOAL_SLEEP_QUALITY"]',
      );
      // Candidate that doesn't share goal_matches and carries a vestigial v3
      // brand-trust value; that value must not affect v4 ranking.
      final noShared = _product(
        dsldId: 'no-shared',
        name: 'Daily Multi',
        supplementType: 'multivitamin',
        primaryCategory: 'multivitamin',
        qualityScoreV4100: 60,
        goalMatches: '["GOAL_INCREASE_ENERGY"]',
      );

      final result = rankAlternatives(
        current: cur,
        candidates: [noShared, sharesGoal],
        // userGoals deliberately omitted — fallback path.
      );
      expect(
        result.first.dsldId,
        equals('shares'),
        reason:
            'With userGoals null, the product-to-product '
            'goal-match Jaccard takes over as the tiebreaker. Shares '
            'a goal with current → outranks the '
            'no-overlap candidate.',
      );
    });

    test('empty userGoals set is treated like null (defensive — same as '
        'a user who has not picked any goals yet)', () {
      final cur = _product(
        dsldId: 'cur',
        name: 'B-Complex',
        supplementType: 'targeted',
        primaryCategory: 'b-complex',
        qualityScoreV4100: 30,
        keyIngredientTags: '["b_complex"]',
      );
      final candidate = _product(
        dsldId: 'cand',
        name: 'B-Complex Plus',
        supplementType: 'targeted',
        primaryCategory: 'b-complex',
        qualityScoreV4100: 60,
        keyIngredientTags: '["b_complex"]',
      );
      final result = rankAlternatives(
        current: cur,
        candidates: [candidate],
        userGoals: const <String>{},
      );
      expect(
        result.map((p) => p.dsldId),
        equals(['cand']),
        reason:
            "An empty userGoals set must not blow up or starve the "
            'result list — the personalization tiebreaker just goes '
            'neutral.',
      );
    });
  });

  // ===========================================================================
  // Near-duplicate suppression
  // ===========================================================================

  group('Near-duplicate suppression', () {
    test('does not collapse a potency-bearing product into a bare name', () {
      final cur = _product(
        dsldId: '336897',
        name: 'Vitamin D3 + K2',
        brand: "Paradise Earth's Blend",
        supplementType: 'targeted',
        primaryCategory: 'single_vitamin',
        qualityScoreV4100: 56.5,
        keyIngredientTags: '["vitamin_d","vitamin_k"]',
      );
      final lowerDuplicate = _product(
        dsldId: 'dup-lower',
        name: 'Vitamin D3 + K2',
        brand: 'Thorne',
        supplementType: 'targeted',
        primaryCategory: 'single_vitamin',
        qualityScoreV4100: 71,
        keyIngredientTags: '["vitamin_d","vitamin_k"]',
      );
      final bestDuplicate = _product(
        dsldId: 'dup-best',
        name: 'Vitamin D3 + K2 1000 IU',
        brand: 'Thorne',
        supplementType: 'targeted',
        primaryCategory: 'single_vitamin',
        qualityScoreV4100: 74,
        keyIngredientTags: '["vitamin_d","vitamin_k"]',
      );
      final distinctProduct = _product(
        dsldId: 'distinct',
        name: 'Vitamin D + K2 Drops',
        brand: 'Pure Encapsulations',
        supplementType: 'targeted',
        primaryCategory: 'single_vitamin',
        qualityScoreV4100: 70,
        keyIngredientTags: '["vitamin_d","vitamin_k"]',
      );

      final result = rankAlternatives(
        current: cur,
        candidates: [lowerDuplicate, distinctProduct, bestDuplicate],
        limit: 3,
      );

      expect(
        result.map((p) => p.dsldId),
        equals(['dup-best', 'distinct', 'dup-lower']),
      );
    });

    test('drops pack-size / SKU variants of the product on screen', () {
      // User views "Thorne D3 30 capsules" — must not recommend
      // "Thorne D3 60 capsules" as a "higher quality" alternative.
      final cur = _product(
        dsldId: 'cur-30ct',
        name: 'Vitamin D3 1000 IU 30 capsules',
        brand: 'Thorne',
        supplementType: 'targeted',
        primaryCategory: 'single_vitamin',
        qualityScoreV4100: 60,
        keyIngredientTags: '["vitamin_d"]',
      );
      final sameProductLargerPack = _product(
        dsldId: 'cur-60ct',
        name: 'Vitamin D3 1000 IU 60 capsules',
        brand: 'Thorne',
        supplementType: 'targeted',
        primaryCategory: 'single_vitamin',
        qualityScoreV4100: 68,
        keyIngredientTags: '["vitamin_d"]',
      );
      final realAlt = _product(
        dsldId: 'real-alt',
        name: 'Vitamin D3 Liquid',
        brand: 'Pure Encapsulations',
        supplementType: 'targeted',
        primaryCategory: 'single_vitamin',
        qualityScoreV4100: 72,
        keyIngredientTags: '["vitamin_d"]',
      );

      final result = rankAlternatives(
        current: cur,
        candidates: [sameProductLargerPack, realAlt],
      );

      expect(result.map((p) => p.dsldId), equals(['real-alt']));
    });

    test('normalizes thousands separators before pack-size comparison', () {
      final cur = _product(
        dsldId: 'cur-comma',
        name: 'Vitamin D3 1,000 IU 30 capsules',
        brand: 'Thorne',
        supplementType: 'single_vitamin',
        primaryCategory: 'single_vitamin',
        qualityScoreV4100: 50,
        keyIngredientTags: '["vitamin_d"]',
      );
      final sameProductLargerPack = _product(
        dsldId: 'cur-no-comma',
        name: 'Vitamin D3 1000 IU 60 capsules',
        brand: 'Thorne',
        supplementType: 'single_vitamin',
        primaryCategory: 'single_vitamin',
        qualityScoreV4100: 70,
        keyIngredientTags: '["vitamin_d"]',
      );

      final result = rankAlternatives(
        current: cur,
        candidates: [sameProductLargerPack],
      );

      expect(result, isEmpty);
    });

    test('does not treat a stack-safety fingerprint as product identity', () {
      final cur = _product(
        dsldId: 'cur',
        name: 'Vitamin D3 Tablets',
        brand: 'Brand A',
        supplementType: 'single_vitamin',
        primaryCategory: 'single_vitamin',
        qualityScoreV4100: 50,
        keyIngredientTags: '["vitamin_d"]',
        ingredientFingerprint:
            '{"nutrients":{"vitamin_d":{"amount":25,"unit":"mcg"}},'
            '"herbs":[],"categories":["vitamins"]}',
      );
      final independentlyScoredAlternative = _product(
        dsldId: 'drops',
        name: 'Vitamin D3 Drops',
        brand: 'Brand B',
        supplementType: 'single_vitamin',
        primaryCategory: 'single_vitamin',
        qualityScoreV4100: 70,
        keyIngredientTags: '["vitamin_d"]',
        ingredientFingerprint:
            '{"nutrients":{"vitamin_d":{"amount":25,"unit":"mcg"}},'
            '"herbs":[],"categories":["vitamins"]}',
      );

      final result = rankAlternatives(
        current: cur,
        candidates: [independentlyScoredAlternative],
      );

      expect(
        result.map((p) => p.dsldId),
        equals(['drops']),
        reason:
            'ingredient_fingerprint is a stack-safety dose map, not a '
            'catalog product identity or private-label provenance key',
      );
    });

    test('retains potency in identity while removing package count', () {
      final cur = _product(
        dsldId: 'cur-1000',
        name: 'Vitamin D3 1000 IU 30 capsules',
        brand: 'Thorne',
        supplementType: 'single_vitamin',
        primaryCategory: 'single_vitamin',
        qualityScoreV4100: 50,
        keyIngredientTags: '["vitamin_d"]',
      );
      final differentPotency = _product(
        dsldId: 'cur-5000',
        name: 'Vitamin D3 5000 IU 60 capsules',
        brand: 'Thorne',
        supplementType: 'single_vitamin',
        primaryCategory: 'single_vitamin',
        qualityScoreV4100: 70,
        keyIngredientTags: '["vitamin_d"]',
      );

      final result = rankAlternatives(
        current: cur,
        candidates: [differentPotency],
      );

      expect(
        result.map((p) => p.dsldId),
        equals(['cur-5000']),
        reason:
            '1000 IU and 5000 IU are different labeled products; only the '
            '30/60 capsule package count is identity noise',
      );
    });

    test('uses the shipped tier as the meaningful-quality boundary', () {
      final cur = _product(
        dsldId: 'cur',
        name: 'Multi',
        brand: 'A',
        supplementType: 'multivitamin',
        primaryCategory: 'multivitamin',
        qualityScoreV4100: 80,
        qualityTier: 'Acceptable',
      );
      final nextTier = _product(
        dsldId: 'next-tier',
        name: 'Multi Strong',
        brand: 'B',
        supplementType: 'multivitamin',
        primaryCategory: 'multivitamin',
        qualityScoreV4100: 80,
        qualityTier: 'Strong',
      );

      final result = rankAlternatives(current: cur, candidates: [nextTier]);

      expect(result.map((p) => p.dsldId), equals(['next-tier']));
    });

    test('does not label a same-tier score increase as higher quality', () {
      final cur = _product(
        dsldId: 'cur',
        name: 'Multi Good',
        brand: 'A',
        supplementType: 'multivitamin',
        primaryCategory: 'multivitamin',
        qualityScoreV4100: 70,
        qualityTier: 'Acceptable',
      );
      final sameTier = _product(
        dsldId: 'same-tier',
        name: 'Multi Good Plus',
        brand: 'C',
        supplementType: 'multivitamin',
        primaryCategory: 'multivitamin',
        qualityScoreV4100: 79,
        qualityTier: 'Acceptable',
      );

      final result = rankAlternatives(current: cur, candidates: [sameTier]);

      expect(result, isEmpty);
    });

    test('diversifies brands first, then backfills valid choices', () {
      final cur = _product(
        dsldId: 'cur',
        name: 'Basic Multi',
        brand: 'Generic Co',
        supplementType: 'multivitamin',
        primaryCategory: 'multivitamin',
        qualityScoreV4100: 40,
      );
      final thorneA = _product(
        dsldId: 't1',
        name: 'Multi Basic',
        brand: 'Thorne',
        supplementType: 'multivitamin',
        primaryCategory: 'multivitamin',
        qualityScoreV4100: 80,
      );
      final thorneB = _product(
        dsldId: 't2',
        name: 'Multi Advanced',
        brand: 'Thorne',
        supplementType: 'multivitamin',
        primaryCategory: 'multivitamin',
        qualityScoreV4100: 85,
      );
      final pure = _product(
        dsldId: 'p1',
        name: 'Daily Multi',
        brand: 'Pure Encapsulations',
        supplementType: 'multivitamin',
        primaryCategory: 'multivitamin',
        qualityScoreV4100: 82,
      );

      final result = rankAlternatives(
        current: cur,
        candidates: [thorneA, thorneB, pure],
        limit: 3,
      );

      expect(
        result.map((p) => p.dsldId),
        equals(['t2', 'p1', 't1']),
        reason:
            'brand diversity is a presentation preference, not a reason to '
            'return fewer useful alternatives than the requested limit',
      );
    });

    test('rejects unrelated products inside a broad taxonomy bucket', () {
      final cur = _product(
        dsldId: 'coconut',
        name: 'Coconut Oil',
        brand: 'Brand A',
        supplementType: 'general_supplement',
        primaryCategory: 'general_supplement',
        qualityScoreV4100: 30,
        keyIngredientTags: '["coconut_oil"]',
      );
      final unrelated = _product(
        dsldId: 'licorice',
        name: 'Licorice Root',
        brand: 'Brand B',
        supplementType: 'general_supplement',
        primaryCategory: 'general_supplement',
        qualityScoreV4100: 70,
        keyIngredientTags: '["licorice_root"]',
      );

      final result = rankAlternatives(current: cur, candidates: [unrelated]);

      expect(result, isEmpty);
    });
  });

  group('Database candidate pool', () {
    test(
      'includes cross-type ingredient-family matches before broad noise',
      () async {
        final db = CoreDatabase.memory();
        addTearDown(db.close);

        await _insertPoolProduct(
          db,
          dsldId: 'current',
          name: 'Coconut Oil',
          supplementType: 'general_supplement',
          score: 30,
          keyIngredientTags: '["coconut_oil"]',
        );
        for (var i = 0; i < 55; i++) {
          await _insertPoolProduct(
            db,
            dsldId: 'noise-$i',
            name: 'Unrelated General $i',
            supplementType: 'general_supplement',
            score: 99 - (i / 10),
            keyIngredientTags: '["unrelated_$i"]',
            brand: 'Noise $i',
          );
        }
        await _insertPoolProduct(
          db,
          dsldId: 'family-match',
          name: 'Coconut Extract',
          supplementType: 'herbal_botanical',
          score: 60,
          keyIngredientTags: '["coconut_oil"]',
          brand: 'Relevant Brand',
        );

        final current = await db.findById('current');
        final pool = await db.fetchBetterAlternativesPool(
          current!,
          poolSize: 50,
        );

        expect(
          pool.map((p) => p.dsldId),
          contains('family-match'),
          reason:
              'the SQL pool must not truncate a relevant cross-type family '
              'match behind high-scoring products from a broad category',
        );
      },
    );
  });

  // ===========================================================================
  // Limit + empty pool
  // ===========================================================================

  group('Limit + edge cases', () {
    test('honours limit', () {
      final cur = _product(
        dsldId: 'cur',
        name: 'M',
        supplementType: 'multivitamin',
        primaryCategory: 'multivitamin',
        qualityScoreV4100: 20,
      );
      final candidates = [
        for (var i = 0; i < 8; i++)
          _product(
            dsldId: 'alt-$i',
            name: 'Alt $i',
            supplementType: 'multivitamin',
            primaryCategory: 'multivitamin',
            qualityScoreV4100: 60 + i.toDouble(),
          ),
      ];
      final result = rankAlternatives(
        current: cur,
        candidates: candidates,
        limit: 3,
      );
      expect(result, hasLength(3));
    });

    test('zero limit returns empty result', () {
      final cur = _product(
        dsldId: 'cur',
        name: 'M',
        supplementType: 'multivitamin',
        primaryCategory: 'multivitamin',
        qualityScoreV4100: 20,
      );
      final candidate = _product(
        dsldId: 'alt',
        name: 'Alt',
        supplementType: 'multivitamin',
        primaryCategory: 'multivitamin',
        qualityScoreV4100: 30,
      );
      final result = rankAlternatives(
        current: cur,
        candidates: [candidate],
        limit: 0,
      );
      expect(result, isEmpty);
    });

    test('empty pool → empty result', () {
      final cur = _product(
        dsldId: 'cur',
        name: 'M',
        supplementType: 'multivitamin',
        primaryCategory: 'multivitamin',
        qualityScoreV4100: 20,
      );
      final result = rankAlternatives(current: cur, candidates: const []);
      expect(result, isEmpty);
    });

    test('all candidates fail hard filters (off-market or low score) → '
        'empty result', () {
      final cur = _product(
        dsldId: 'cur',
        name: 'M',
        supplementType: 'multivitamin',
        primaryCategory: 'multivitamin',
        qualityScoreV4100: 50,
      );
      final candidates = [
        _product(
          dsldId: 'off',
          name: 'Off',
          supplementType: 'multivitamin',
          primaryCategory: 'multivitamin',
          qualityScoreV4100: 80,
          discontinuedDate: '2024-01-01',
        ),
        _product(
          dsldId: 'low',
          name: 'Low',
          supplementType: 'multivitamin',
          primaryCategory: 'multivitamin',
          qualityScoreV4100: 40,
        ),
      ];
      final result = rankAlternatives(current: cur, candidates: candidates);
      expect(result, isEmpty);
    });
  });
}
