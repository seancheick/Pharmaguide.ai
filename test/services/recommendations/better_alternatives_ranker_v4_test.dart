// v4 dual-reader regressions for the Better Alternatives ranker.
//
// Complements better_alternatives_ranker_test.dart (which pins the v3
// behavior). These lock the v4 contract:
//   * a safety-suppressed candidate is NEVER recommended, even on-market and
//     same supplement_type;
//   * ranking uses the effective v4 /100 score when no legacy /80 is present;
//   * "strictly higher" compares effective scores.

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/services/recommendations/better_alternatives_ranker.dart';

ProductsCoreData _p({
  required String dsldId,
  required String name,
  String? supplementType,
  String? primaryCategory,
  double? qualityScoreV4100,
  String? qualityScoreStatus = 'scored',
  String? productSafetyStatus,
  String? qualityAssessmentStatus = 'complete',
  String? discontinuedDate,
  int hasBannedSubstance = 0,
  int hasRecalledIngredient = 0,
}) {
  return ProductsCoreData(
    dsldId: dsldId,
    productName: name,
    supplementType: supplementType,
    primaryCategory: primaryCategory,
    qualityScoreV4100: qualityScoreV4100,
    qualityScoreStatus: qualityScoreStatus,
    productSafetyStatus: productSafetyStatus,
    qualityAssessmentStatus: qualityAssessmentStatus,
    discontinuedDate: discontinuedDate,
    hasBannedSubstance: hasBannedSubstance,
    hasRecalledIngredient: hasRecalledIngredient,
    exportVersion: 'test',
    exportedAt: '2026-06-09T00:00:00Z',
  );
}

void main() {
  test(
    'blocked Vinpocetine source discovers qualified options without score comparison',
    () {
      final source = _p(
        dsldId: '16012',
        name: 'Vinpocetine',
        supplementType: 'nootropic_support',
        qualityScoreV4100: 100,
        productSafetyStatus: 'blocked',
        qualityScoreStatus: 'suppressed_safety',
        qualityAssessmentStatus: 'partial',
      );
      ProductsCoreData candidate(
        String id, {
        double? score = 0,
        String? assessment = 'complete',
        String? safety,
        String? status = 'scored',
        String? discontinued,
        int banned = 0,
        int recalled = 0,
        String name = 'Nootropic Support',
        String type = 'nootropic_support',
      }) => _p(
        dsldId: id,
        name: name,
        supplementType: type,
        qualityScoreV4100: score,
        qualityAssessmentStatus: assessment,
        productSafetyStatus: safety,
        qualityScoreStatus: status,
        discontinuedDate: discontinued,
        hasBannedSubstance: banned,
        hasRecalledIngredient: recalled,
      );
      final result = rankAlternatives(
        current: source,
        candidates: [
          candidate('valid-zero'),
          candidate('partial', score: 99, assessment: 'partial'),
          candidate('missing', score: null),
          candidate('invalid', score: double.nan),
          candidate('blocked', safety: 'blocked'),
          candidate('unsafe', safety: 'unsafe'),
          candidate('suppressed', status: 'suppressed_safety'),
          candidate('banned', banned: 1),
          candidate('recalled', recalled: 1),
          candidate('off', discontinued: '2026-01-01'),
          candidate('kids', name: 'Kids Nootropic Support'),
          candidate('unrelated', type: 'probiotic'),
        ],
      );
      expect(result.map((p) => p.dsldId), ['valid-zero']);
    },
  );

  for (final assessment in [null, 'partial', 'failed']) {
    test(
      'unqualified current $assessment cannot establish a quality comparison',
      () {
        final current = _p(
          dsldId: 'current',
          name: 'Vitamin',
          supplementType: 'vitamin',
          qualityScoreV4100: 20,
          qualityAssessmentStatus: assessment,
        );
        final candidate = _p(
          dsldId: 'candidate',
          name: 'Vitamin Better',
          supplementType: 'vitamin',
          qualityScoreV4100: 80,
        );
        expect(
          rankAlternatives(current: current, candidates: [candidate]),
          isEmpty,
        );
      },
    );
  }

  test(
    'excludes a safety-suppressed candidate even when on-market + same type',
    () {
      final cur = _p(
        dsldId: 'CUR',
        name: 'Creatine A',
        supplementType: 'creatine',
        primaryCategory: 'sports',
        qualityScoreV4100: 50,
      );
      final suppressed = _p(
        dsldId: 'BANNED',
        name: 'Creatine Banned',
        supplementType: 'creatine',
        primaryCategory: 'sports',
        qualityScoreV4100: null,
        qualityScoreStatus: 'suppressed_safety',
      );
      final good = _p(
        dsldId: 'GOOD',
        name: 'Creatine Better',
        supplementType: 'creatine',
        primaryCategory: 'sports',
        qualityScoreV4100: 90,
      );

      final out = rankAlternatives(
        current: cur,
        candidates: [suppressed, good],
      );
      final ids = out.map((p) => p.dsldId);
      expect(
        ids,
        isNot(contains('BANNED')),
        reason: 'a suppressed product must never be a recommended alternative',
      );
      expect(ids, contains('GOOD'));
    },
  );

  test('ranks by the v4 effective score when no legacy /80 is present', () {
    final cur = _p(
      dsldId: 'CUR',
      name: 'Omega A',
      supplementType: 'omega',
      primaryCategory: 'omega',
      qualityScoreV4100: 40,
    );
    final lo = _p(
      dsldId: 'LO',
      name: 'Omega Lo',
      supplementType: 'omega',
      primaryCategory: 'omega',
      qualityScoreV4100: 60,
    );
    final hi = _p(
      dsldId: 'HI',
      name: 'Omega Hi',
      supplementType: 'omega',
      primaryCategory: 'omega',
      qualityScoreV4100: 95,
    );

    final out = rankAlternatives(current: cur, candidates: [lo, hi]);
    expect(
      out.first.dsldId,
      'HI',
      reason: 'the higher v4 score must rank first',
    );
  });

  test('new failed assessment overrides a stale scored field', () {
    final cur = _p(
      dsldId: 'CUR',
      name: 'Omega A',
      supplementType: 'omega',
      primaryCategory: 'omega',
      qualityScoreV4100: 40,
    );
    final failed = _p(
      dsldId: 'FAILED',
      name: 'Stale Score',
      supplementType: 'omega',
      primaryCategory: 'omega',
      qualityScoreV4100: 95,
      qualityAssessmentStatus: 'failed',
    );
    final valid = _p(
      dsldId: 'VALID',
      name: 'Valid Score',
      supplementType: 'omega',
      primaryCategory: 'omega',
      qualityScoreV4100: 90,
      productSafetyStatus: 'no_known_catalog_concern',
      qualityAssessmentStatus: 'complete',
    );

    final out = rankAlternatives(current: cur, candidates: [failed, valid]);
    expect(out.map((p) => p.dsldId), ['VALID']);
  });

  test('a candidate at or below current effective score is filtered out', () {
    final cur = _p(
      dsldId: 'CUR',
      name: 'Mag A',
      supplementType: 'magnesium',
      primaryCategory: 'mineral',
      qualityScoreV4100: 80,
    );
    final tie = _p(
      dsldId: 'TIE',
      name: 'Mag Tie',
      supplementType: 'magnesium',
      primaryCategory: 'mineral',
      qualityScoreV4100: 80,
    );

    final out = rankAlternatives(current: cur, candidates: [tie]);
    expect(
      out,
      isEmpty,
      reason: 'only STRICTLY higher effective scores qualify',
    );
  });

  test('effectiveQualityScore + isCatalogScoreSuppressed helpers behave', () {
    final scored = _p(dsldId: 'S', name: 'S', qualityScoreV4100: 70);
    final suppressed = _p(
      dsldId: 'B',
      name: 'B',
      qualityScoreV4100: null,
      qualityScoreStatus: 'suppressed_safety',
    );
    expect(effectiveQualityScore(scored), 70);
    expect(isCatalogScoreSuppressed(scored), isFalse);
    expect(effectiveQualityScore(suppressed), isNull);
    expect(isCatalogScoreSuppressed(suppressed), isTrue);
  });
}
