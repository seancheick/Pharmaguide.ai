// FIX 3 (P1) regression locks — search result chips.
//
// (a) `searchVerdictTone` had no 'SAFE' case, so the pipeline's most common
//     positive verdict fell through to the gray NOT_SCORED fallback.
// (b) The score chip rendered gated only on `score != null` — a scored
//     product with mapped_coverage < 0.3 showed a confident tier-colored
//     number, and an UNSAFE-verdict product could show a positive score
//     next to its block indicator. `searchScoreChipDisplayFor` +
//     `searchShowsVerdictChip` now own those decisions:
//       * unsafe verdict → score chip hidden (verdict chip carries the block)
//       * low coverage   → neutral "Limited data" chip, never a tier color
//       * low coverage   → positive (green) verdict chips suppressed;
//                          warning verdicts still render (under-warning is
//                          the bigger clinical risk).

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/scoring/catalog_product_semantics.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/features/search/v2/search_v2_screen.dart';

void main() {
  group('searchVerdictTone', () {
    test('SAFE maps to the safe/green tone — not the gray fallback', () {
      expect(searchVerdictTone(V2Palette.light, 'SAFE'), V2Palette.light.safe);
    });

    test('verdict tone matching is case/whitespace-insensitive', () {
      expect(
        searchVerdictTone(V2Palette.light, ' safe '),
        V2Palette.light.safe,
      );
    });

    test('BLOCKED / UNSAFE stay contraindicated', () {
      expect(
        searchVerdictTone(V2Palette.light, 'BLOCKED'),
        V2Palette.light.contraindicated,
      );
      expect(
        searchVerdictTone(V2Palette.light, 'UNSAFE'),
        V2Palette.light.contraindicated,
      );
    });

    test('NOT_SCORED stays on the neutral fallback', () {
      expect(
        searchVerdictTone(V2Palette.light, 'NOT_SCORED'),
        V2Palette.light.fgMuted,
      );
    });
  });

  group('searchScoreChipDisplayFor', () {
    test('scored + trusted coverage renders the tier chip', () {
      expect(
        searchScoreChipDisplayFor(
          score: 85,
          verdict: 'SAFE',
          mappedCoverage: 0.9,
          v4Confidence: 'high',
        ),
        SearchScoreChipDisplay.tierScore,
      );
    });

    test('low v4 confidence renders a neutral limited-assessment chip', () {
      expect(
        searchScoreChipDisplayFor(
          score: 85,
          verdict: 'SAFE',
          mappedCoverage: 0.9,
          v4Confidence: 'low',
        ),
        SearchScoreChipDisplay.limitedAssessment,
      );
    });

    test('unknown populated confidence fails closed to limited', () {
      expect(
        searchScoreChipDisplayFor(
          score: 85,
          verdict: 'SAFE',
          mappedCoverage: 0.9,
          v4Confidence: 'future_band',
        ),
        SearchScoreChipDisplay.limitedAssessment,
      );
    });

    test('unsafe verdict hides the score chip (block indicator wins)', () {
      expect(
        searchScoreChipDisplayFor(
          score: 85,
          verdict: 'UNSAFE',
          mappedCoverage: 0.9,
        ),
        SearchScoreChipDisplay.hidden,
      );
      expect(
        searchScoreChipDisplayFor(
          score: 85,
          verdict: 'BLOCKED',
          mappedCoverage: 0.9,
        ),
        SearchScoreChipDisplay.hidden,
      );
    });

    test('failed assessment hides a leaked score', () {
      expect(
        searchScoreChipDisplayFor(
          score: 85,
          isNotScored: true,
          mappedCoverage: 0.9,
          v4Confidence: 'high',
        ),
        SearchScoreChipDisplay.hidden,
      );
    });

    test('null score renders no chip — never a fabricated number', () {
      expect(
        searchScoreChipDisplayFor(
          score: null,
          verdict: 'NOT_SCORED',
          mappedCoverage: 0.9,
        ),
        SearchScoreChipDisplay.hidden,
      );
    });

    test('mapped_coverage < 0.3 renders the neutral limited-data chip', () {
      expect(
        searchScoreChipDisplayFor(
          score: 85,
          verdict: 'SAFE',
          mappedCoverage: 0.2,
        ),
        SearchScoreChipDisplay.limitedData,
      );
    });

    test('null coverage is treated as low coverage (unknown ≠ trusted)', () {
      expect(
        searchScoreChipDisplayFor(
          score: 85,
          verdict: 'SAFE',
          mappedCoverage: null,
        ),
        SearchScoreChipDisplay.limitedData,
      );
    });

    test('coverage exactly at the 0.3 floor is trusted (floor is `< 0.3`)', () {
      expect(
        searchScoreChipDisplayFor(
          score: 85,
          verdict: 'SAFE',
          mappedCoverage: 0.3,
        ),
        SearchScoreChipDisplay.tierScore,
      );
    });
  });

  group('searchScoreChipText', () {
    test('makes known confidence visible beside the score', () {
      expect(searchScoreChipText(score: 85, confidence: 'high'), '85 · High');
      expect(
        searchScoreChipText(score: 85, confidence: 'moderate'),
        '85 · Moderate',
      );
      expect(searchScoreChipText(score: 85, confidence: 'low'), '85 · Limited');
    });

    test('missing confidence does not invent a label', () {
      expect(searchScoreChipText(score: 85, confidence: null), '85');
    });
  });

  group('searchSafetyStatusLabel', () {
    test('no catalog concern does not render a SAFE chip', () {
      expect(
        searchSafetyStatusLabel(
          CatalogProductSafetyStatus.noKnownCatalogConcern,
        ),
        isNull,
      );
    });

    test('actionable and unknown safety states remain visible', () {
      expect(
        searchSafetyStatusLabel(CatalogProductSafetyStatus.caution),
        'Caution',
      );
      expect(
        searchSafetyStatusLabel(CatalogProductSafetyStatus.blocked),
        'Blocked',
      );
      expect(
        searchSafetyStatusLabel(CatalogProductSafetyStatus.notAssessed),
        'Not assessed',
      );
    });
  });
}
