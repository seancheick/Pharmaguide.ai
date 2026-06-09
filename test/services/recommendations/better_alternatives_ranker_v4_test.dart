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
  String? discontinuedDate,
  int hasBannedSubstance = 0,
}) {
  return ProductsCoreData(
    dsldId: dsldId,
    productName: name,
    supplementType: supplementType,
    primaryCategory: primaryCategory,
    qualityScoreV4100: qualityScoreV4100,
    // Mirror the pipeline invariant: score_100_equivalent mirrors the v4
    // score when scored, and is NULL when suppressed.
    score100Equivalent: qualityScoreStatus == 'scored'
        ? qualityScoreV4100
        : null,
    qualityScoreStatus: qualityScoreStatus,
    discontinuedDate: discontinuedDate,
    hasBannedSubstance: hasBannedSubstance,
    exportVersion: 'test',
    exportedAt: '2026-06-09T00:00:00Z',
  );
}

void main() {
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

  test('effectiveQualityScore + isSafetySuppressed helpers behave', () {
    final scored = _p(dsldId: 'S', name: 'S', qualityScoreV4100: 70);
    final suppressed = _p(
      dsldId: 'B',
      name: 'B',
      qualityScoreV4100: null,
      qualityScoreStatus: 'suppressed_safety',
    );
    expect(effectiveQualityScore(scored), 70);
    expect(isSafetySuppressed(scored), isFalse);
    expect(effectiveQualityScore(suppressed), isNull);
    expect(isSafetySuppressed(suppressed), isTrue);
  });
}
