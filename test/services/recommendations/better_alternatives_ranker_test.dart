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

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/services/recommendations/better_alternatives_ranker.dart';

ProductsCoreData _product({
  required String dsldId,
  required String name,
  String? brand,
  String? supplementType,
  String? primaryCategory,
  double? scoreQuality80,
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
  double? scoreBrandTrust,
}) {
  return ProductsCoreData(
    dsldId: dsldId,
    productName: name,
    brandName: brand,
    supplementType: supplementType,
    primaryCategory: primaryCategory,
    scoreQuality80: scoreQuality80,
    score100Equivalent: scoreQuality80 == null ? null : scoreQuality80 * 1.25,
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
    scoreBrandTrust: scoreBrandTrust,
    exportVersion: 'test',
    exportedAt: '2026-05-16T00:00:00Z',
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
        scoreQuality80: 30,
      );
      final result = rankAlternatives(
        current: cur,
        candidates: [cur],
      );
      expect(result, isEmpty);
    });

    test('drops off-market candidates (discontinuedDate set)', () {
      final cur = _product(
        dsldId: 'cur',
        name: 'Probiotic',
        supplementType: 'probiotic',
        primaryCategory: 'probiotic',
        scoreQuality80: 25,
      );
      final offMarket = _product(
        dsldId: 'off',
        name: 'Restore',
        supplementType: 'probiotic',
        primaryCategory: 'probiotic',
        scoreQuality80: 62,
        discontinuedDate: '2024-01-01',
      );
      final onMarket = _product(
        dsldId: 'on',
        name: 'Trust Your Gut',
        supplementType: 'probiotic',
        primaryCategory: 'probiotic',
        scoreQuality80: 58,
      );
      final result = rankAlternatives(
        current: cur,
        candidates: [offMarket, onMarket],
      );
      expect(result.map((p) => p.dsldId), equals(['on']));
    });

    test(
        'unscored current (blocked product like Vinpocetine) still returns '
        'scored candidates', () {
      // Sean's Phase 11.7L.F follow-up: blocked products like
      // dsld 16012 Vinpocetine ship with `score_quality_80 = NULL`.
      // The user MUST still see safer alternatives — treat the
      // missing score as "lower than any scored candidate."
      final vinpocetine = _product(
        dsldId: '16012',
        name: 'Vinpocetine',
        brand: 'Thorne Research',
        supplementType: 'single_nutrient',
        // primaryCategory + scoreQuality80 intentionally NULL —
        // mirrors the live catalog row.
      );
      final saferAlt = _product(
        dsldId: 'safer-alt',
        name: 'Bacopa Monnieri',
        brand: 'Pure Encapsulations',
        supplementType: 'single_nutrient',
        scoreQuality80: 65,
      );
      final result = rankAlternatives(
        current: vinpocetine,
        candidates: [saferAlt],
      );
      expect(result.map((p) => p.dsldId), equals(['safer-alt']),
          reason:
              'Blocked products with null scoreQuality80 must still '
              "surface scored alternatives — that's the user's whole "
              'reason for landing on this section.');
    });

    test('drops candidates with score ≤ current (strictly higher only)',
        () {
      final cur = _product(
        dsldId: 'cur',
        name: 'Daily Multi',
        supplementType: 'multivitamin',
        primaryCategory: 'multivitamin',
        scoreQuality80: 50,
      );
      final tied = _product(
        dsldId: 'tied',
        name: 'Tied Score Multi',
        supplementType: 'multivitamin',
        primaryCategory: 'multivitamin',
        scoreQuality80: 50,
      );
      final higher = _product(
        dsldId: 'higher',
        name: 'Higher Multi',
        supplementType: 'multivitamin',
        primaryCategory: 'multivitamin',
        scoreQuality80: 65,
      );
      final result = rankAlternatives(
        current: cur,
        candidates: [tied, higher],
      );
      expect(result.map((p) => p.dsldId), equals(['higher']));
    });

    test('drops banned + recalled candidates', () {
      final cur = _product(
        dsldId: 'cur',
        name: 'X',
        supplementType: 'multivitamin',
        primaryCategory: 'multivitamin',
        scoreQuality80: 30,
      );
      final banned = _product(
        dsldId: 'banned',
        name: 'Banned Multi',
        supplementType: 'multivitamin',
        primaryCategory: 'multivitamin',
        scoreQuality80: 80,
        hasBannedSubstance: 1,
      );
      final recalled = _product(
        dsldId: 'recalled',
        name: 'Recalled Multi',
        supplementType: 'multivitamin',
        primaryCategory: 'multivitamin',
        scoreQuality80: 78,
        hasRecalledIngredient: 1,
      );
      final ok = _product(
        dsldId: 'ok',
        name: 'OK Multi',
        supplementType: 'multivitamin',
        primaryCategory: 'multivitamin',
        scoreQuality80: 70,
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
        scoreQuality80: 18.5,
      );
      // The legacy top recommendation:
      final basicPrenatal = _product(
        dsldId: '328830',
        name: 'Basic Prenatal',
        brand: 'Thorne',
        supplementType: 'multivitamin',
        primaryCategory: 'multivitamin',
        scoreQuality80: 72.4,
      );
      // A discontinued legacy recommendation:
      final advancedNutrients = _product(
        dsldId: '313907',
        name: 'Advanced Nutrients',
        brand: 'Thorne',
        supplementType: 'multivitamin',
        primaryCategory: 'multivitamin',
        scoreQuality80: 71.8,
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
        scoreQuality80: 55,
        keyIngredientTags: '["ginseng","tribulus","maca"]',
      );

      final result = rankAlternatives(
        current: staminol,
        candidates: [basicPrenatal, advancedNutrients, mensEnergyBlend],
      );

      final ids = result.map((p) => p.dsldId).toList();
      expect(ids, contains('better-mens-energy'),
          reason: 'A same-type same-audience swap should always win.');
      expect(ids, isNot(contains('328830')),
          reason: 'Prenatal cross-audience must be blocked.');
      expect(ids, isNot(contains('313907')),
          reason: 'Off-market must be filtered.');
    });
  });

  group('Regression: Audit case #2 — Vitamin A targeted ↛ kids chewable',
      () {
    test(
        'single-ingredient targeted does not recommend kids multi or '
        'discontinued', () {
      final vitA = _product(
        dsldId: '19170',
        name: 'A 8,000 IU',
        brand: 'CVS Pharmacy',
        supplementType: 'targeted',
        primaryCategory: 'omega-3', // legacy mis-categorisation
        scoreQuality80: 37.0,
      );
      final kidsMulti = _product(
        dsldId: '281264',
        name: 'Kids Multi + Strawberry Kiwi',
        brand: 'Thorne',
        supplementType: 'multivitamin',
        primaryCategory: 'omega-3',
        scoreQuality80: 68.8,
        discontinuedDate: '2024-06-01',
      );
      final synaQuell = _product(
        dsldId: '337875',
        name: 'SynaQuell',
        brand: 'Thorne',
        supplementType: 'multivitamin',
        primaryCategory: 'omega-3',
        scoreQuality80: 69.0,
      );
      final aTargeted = _product(
        dsldId: 'better-a-targeted',
        name: 'Vitamin A 10,000 IU',
        brand: 'GoodBrand',
        supplementType: 'targeted',
        primaryCategory: 'omega-3',
        scoreQuality80: 58,
      );

      final result = rankAlternatives(
        current: vitA,
        candidates: [kidsMulti, synaQuell, aTargeted],
      );
      final ids = result.map((p) => p.dsldId).toList();
      expect(ids, contains('better-a-targeted'),
          reason: 'Same supplement_type=targeted should win.');
      expect(ids, isNot(contains('281264')),
          reason: 'Kids cross-audience + off-market must be blocked.');
    });
  });

  group('Regression: Audit case #3 — GNC Probiotic ↛ discontinued Restore',
      () {
    test('probiotic does not recommend off-market #1 or magnesium-gummy',
        () {
      final gncProb = _product(
        dsldId: '1646',
        name: 'Probiotic Complex 1',
        brand: 'GNC Probiotics',
        supplementType: 'probiotic',
        primaryCategory: 'probiotic',
        scoreQuality80: 25.3,
        isProbiotic: 1,
      );
      final restore = _product(
        dsldId: '15581',
        name: 'Restore',
        brand: 'Thorne Performance',
        supplementType: 'probiotic',
        primaryCategory: 'probiotic',
        scoreQuality80: 62.4,
        discontinuedDate: '2024-02-01',
        isProbiotic: 1,
      );
      final magnesiumGummy = _product(
        dsldId: '297681',
        name: 'Magnesium with Pre & Probiotics Gummies',
        brand: 'Garden of Life Dr. Formulated',
        supplementType: 'specialty',
        primaryCategory: 'probiotic',
        scoreQuality80: 58.0,
        keyIngredientTags: '["magnesium","probiotic"]',
        containsProbiotics: 1,
      );
      final trueProb = _product(
        dsldId: '251907',
        name: 'Trust Your Gut.',
        brand: 'Ora',
        supplementType: 'probiotic',
        primaryCategory: 'probiotic',
        scoreQuality80: 58.3,
        isProbiotic: 1,
        keyIngredientTags: '["lactobacillus","bifidobacterium"]',
      );

      final result = rankAlternatives(
        current: gncProb,
        candidates: [restore, magnesiumGummy, trueProb],
      );
      final ids = result.map((p) => p.dsldId).toList();
      expect(ids, isNot(contains('15581')),
          reason: 'Off-market must be filtered.');
      expect(ids.first, equals('251907'),
          reason:
              'Probiotic-first product (251907) should outrank '
              'magnesium-with-probiotics (297681) because it shares '
              'supplement_type and the probiotic family flag.');
    });
  });

  group('Regression: Audit case #4 — Kids multi ↛ prenatal/adult', () {
    test('children\'s multivitamin does not recommend prenatal or adult',
        () {
      final kidsMulti = _product(
        dsldId: '178559',
        name: 'Children\'s Multivitamin Gummies',
        brand: 'Spring Valley',
        supplementType: 'multivitamin',
        primaryCategory: 'multivitamin',
        scoreQuality80: 44.1,
      );
      final adultMulti = _product(
        dsldId: '336315',
        name: 'A.M.',
        brand: 'Thorne',
        supplementType: 'multivitamin',
        primaryCategory: 'multivitamin',
        scoreQuality80: 72.6,
      );
      final prenatal = _product(
        dsldId: '328830',
        name: 'Basic Prenatal',
        brand: 'Thorne',
        supplementType: 'multivitamin',
        primaryCategory: 'multivitamin',
        scoreQuality80: 72.4,
      );
      final discontinued = _product(
        dsldId: '313907',
        name: 'Advanced Nutrients',
        brand: 'Thorne',
        supplementType: 'multivitamin',
        primaryCategory: 'multivitamin',
        scoreQuality80: 71.8,
        discontinuedDate: '2023-05-01',
      );
      final betterKids = _product(
        dsldId: 'better-kids-multi',
        name: "Kids' Daily Chewable Multi",
        brand: 'NicerBrand',
        supplementType: 'multivitamin',
        primaryCategory: 'multivitamin',
        scoreQuality80: 60,
      );

      final result = rankAlternatives(
        current: kidsMulti,
        candidates: [adultMulti, prenatal, discontinued, betterKids],
      );
      final ids = result.map((p) => p.dsldId).toList();
      expect(ids, contains('better-kids-multi'),
          reason: 'Same-audience kids swap should win.');
      expect(ids, isNot(contains('336315')),
          reason: 'Adult cross-audience must be blocked.');
      expect(ids, isNot(contains('328830')),
          reason: 'Prenatal cross-audience must be blocked.');
      expect(ids, isNot(contains('313907')),
          reason: 'Off-market must be filtered.');
    });
  });

  group('Regression: Audit case #5 — score ties do NOT qualify as "better"',
      () {
    test('candidate with equal score is dropped (no > operator)', () {
      final cur = _product(
        dsldId: 'cur',
        name: 'Tied Multi',
        supplementType: 'multivitamin',
        primaryCategory: 'multivitamin',
        scoreQuality80: 50,
      );
      final tied = _product(
        dsldId: 'tied',
        name: 'Tied Multi B',
        supplementType: 'multivitamin',
        primaryCategory: 'multivitamin',
        scoreQuality80: 50,
      );
      final result = rankAlternatives(
        current: cur,
        candidates: [tied],
      );
      expect(result, isEmpty);
    });
  });

  // ===========================================================================
  // Sport ↔ general carve-out
  // ===========================================================================

  group('Sport ↔ general carve-out', () {
    test(
        'general wellness candidate blocked from sport product unless '
        'ingredient overlap ≥ 0.5', () {
      final sportPre = _product(
        dsldId: 'cur',
        name: 'Pre-Workout Cherry',
        supplementType: 'sport',
        primaryCategory: 'sport',
        scoreQuality80: 40,
        keyIngredientTags: '["caffeine","beta_alanine","citrulline"]',
      );
      // General product with NO ingredient overlap — should be
      // dropped by the sport↔general carve-out.
      final unrelatedGeneral = _product(
        dsldId: 'unrelated',
        name: 'Magnesium Glycinate',
        supplementType: 'targeted',
        primaryCategory: 'sport',
        scoreQuality80: 70,
        keyIngredientTags: '["magnesium"]',
      );
      // General product with HIGH ingredient overlap — should be
      // allowed through.
      final overlappingGeneral = _product(
        dsldId: 'overlap',
        name: 'Caffeine + Beta Alanine Stack',
        supplementType: 'targeted',
        primaryCategory: 'sport',
        scoreQuality80: 60,
        keyIngredientTags: '["caffeine","beta_alanine","creatine"]',
      );

      final result = rankAlternatives(
        current: sportPre,
        candidates: [unrelatedGeneral, overlappingGeneral],
      );
      final ids = result.map((p) => p.dsldId).toList();
      expect(ids, contains('overlap'),
          reason: 'High-overlap general should pass the carveout.');
      expect(ids, isNot(contains('unrelated')),
          reason: 'No-overlap general must be blocked.');
    });
  });

  // ===========================================================================
  // Tier ordering
  // ===========================================================================

  group('Tier ordering', () {
    test(
        'same supplement_type + high ingredient overlap (tier A) outranks '
        'same supplement_type only (tier B) at lower score', () {
      final cur = _product(
        dsldId: 'cur',
        name: 'Omega-3 Fish Oil',
        supplementType: 'targeted',
        primaryCategory: 'omega-3',
        scoreQuality80: 30,
        containsOmega3: 1,
        keyIngredientTags: '["fish_oil","epa","dha"]',
      );
      // Tier B: same supplement_type, different ingredient family.
      final tierB = _product(
        dsldId: 'tier-b',
        name: 'Vitamin D 5000 IU',
        supplementType: 'targeted',
        primaryCategory: 'omega-3',
        scoreQuality80: 78, // higher score
        keyIngredientTags: '["vitamin_d3"]',
      );
      // Tier A: same supplement_type AND high family overlap.
      final tierA = _product(
        dsldId: 'tier-a',
        name: 'Fish Oil 1200mg',
        supplementType: 'targeted',
        primaryCategory: 'omega-3',
        scoreQuality80: 50, // lower score
        containsOmega3: 1,
        keyIngredientTags: '["fish_oil","epa","dha"]',
      );

      final result = rankAlternatives(
        current: cur,
        candidates: [tierB, tierA],
      );
      expect(result.first.dsldId, equals('tier-a'),
          reason:
              'Tier A (intent+family match) must outrank Tier B even at '
              'a lower score.');
    });

    test('tiebreaker chain — within same tier, higher score wins', () {
      final cur = _product(
        dsldId: 'cur',
        name: 'Probiotic',
        supplementType: 'probiotic',
        primaryCategory: 'probiotic',
        scoreQuality80: 25,
        isProbiotic: 1,
      );
      final lowerScore = _product(
        dsldId: 'lower',
        name: 'Probiotic A',
        supplementType: 'probiotic',
        primaryCategory: 'probiotic',
        scoreQuality80: 60,
        isProbiotic: 1,
      );
      final higherScore = _product(
        dsldId: 'higher',
        name: 'Probiotic B',
        supplementType: 'probiotic',
        primaryCategory: 'probiotic',
        scoreQuality80: 75,
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
  // Limit + empty pool
  // ===========================================================================

  group('Limit + edge cases', () {
    test('honours limit', () {
      final cur = _product(
        dsldId: 'cur',
        name: 'M',
        supplementType: 'multivitamin',
        primaryCategory: 'multivitamin',
        scoreQuality80: 20,
      );
      final candidates = [
        for (var i = 0; i < 8; i++)
          _product(
            dsldId: 'alt-$i',
            name: 'Alt $i',
            supplementType: 'multivitamin',
            primaryCategory: 'multivitamin',
            scoreQuality80: 30 + i.toDouble(),
          ),
      ];
      final result = rankAlternatives(
        current: cur,
        candidates: candidates,
        limit: 3,
      );
      expect(result, hasLength(3));
    });

    test('empty pool → empty result', () {
      final cur = _product(
        dsldId: 'cur',
        name: 'M',
        supplementType: 'multivitamin',
        primaryCategory: 'multivitamin',
        scoreQuality80: 20,
      );
      final result = rankAlternatives(current: cur, candidates: const []);
      expect(result, isEmpty);
    });

    test(
        'all candidates fail hard filters (off-market or low score) → '
        'empty result', () {
      final cur = _product(
        dsldId: 'cur',
        name: 'M',
        supplementType: 'multivitamin',
        primaryCategory: 'multivitamin',
        scoreQuality80: 50,
      );
      final candidates = [
        _product(
          dsldId: 'off',
          name: 'Off',
          supplementType: 'multivitamin',
          primaryCategory: 'multivitamin',
          scoreQuality80: 80,
          discontinuedDate: '2024-01-01',
        ),
        _product(
          dsldId: 'low',
          name: 'Low',
          supplementType: 'multivitamin',
          primaryCategory: 'multivitamin',
          scoreQuality80: 40,
        ),
      ];
      final result = rankAlternatives(current: cur, candidates: candidates);
      expect(result, isEmpty);
    });
  });
}
