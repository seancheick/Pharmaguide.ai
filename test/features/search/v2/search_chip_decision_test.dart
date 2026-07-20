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
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/features/search/v2/search_v2_screen.dart';

void main() {
  group('searchVerdictTone', () {
    test('SAFE maps to the safe/green tone — not the gray fallback', () {
      expect(searchVerdictTone('SAFE'), V2Colors.safe);
    });

    test('verdict tone matching is case/whitespace-insensitive', () {
      expect(searchVerdictTone(' safe '), V2Colors.safe);
    });

    test('BLOCKED / UNSAFE stay contraindicated', () {
      expect(searchVerdictTone('BLOCKED'), V2Colors.contraindicated);
      expect(searchVerdictTone('UNSAFE'), V2Colors.contraindicated);
    });

    test('NOT_SCORED stays on the neutral fallback', () {
      expect(searchVerdictTone('NOT_SCORED'), V2Colors.fgMuted);
    });
  });

  group('searchScoreChipDisplayFor', () {
    test('scored + trusted coverage renders the tier chip', () {
      expect(
        searchScoreChipDisplayFor(
          score: 85,
          verdict: 'SAFE',
          mappedCoverage: 0.9,
        ),
        SearchScoreChipDisplay.tierScore,
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

  group('searchShowsVerdictChip', () {
    test('positive (green) verdicts are suppressed under low coverage', () {
      expect(
        searchShowsVerdictChip(verdict: 'SAFE', mappedCoverage: 0.1),
        isFalse,
      );
      expect(
        searchShowsVerdictChip(verdict: 'GOOD', mappedCoverage: null),
        isFalse,
      );
      expect(
        searchShowsVerdictChip(verdict: 'RECOMMENDED', mappedCoverage: 0.2),
        isFalse,
      );
    });

    test('positive verdicts render normally with trusted coverage', () {
      expect(
        searchShowsVerdictChip(verdict: 'SAFE', mappedCoverage: 0.9),
        isTrue,
      );
    });

    test('warning verdicts always render — even under low coverage', () {
      expect(
        searchShowsVerdictChip(verdict: 'CAUTION', mappedCoverage: 0.1),
        isTrue,
      );
      expect(
        searchShowsVerdictChip(verdict: 'BLOCKED', mappedCoverage: 0.1),
        isTrue,
      );
      expect(
        searchShowsVerdictChip(verdict: 'UNSAFE', mappedCoverage: null),
        isTrue,
      );
      expect(
        searchShowsVerdictChip(verdict: 'POOR', mappedCoverage: 0.1),
        isTrue,
      );
    });

    test('empty / null verdict renders no chip', () {
      expect(
        searchShowsVerdictChip(verdict: null, mappedCoverage: 0.9),
        isFalse,
      );
      expect(
        searchShowsVerdictChip(verdict: '  ', mappedCoverage: 0.9),
        isFalse,
      );
    });
  });
}
