// Tests for `topGoalLabelFromFit` — extracts the user-facing goal
// label from a FitScoreResult's `reasons` list for the For You
// section's verdict headline copy.
//
// AUDIT NOTE 2026-04-29:
//   The original regex `[a-z\s]` rejected 11 of 18 SchemaIds goal
//   labels — anything containing `/`, `&`, `,` (e.g. "Reduce Stress/
//   Anxiety", "Focus & Mental Clarity", "Skin, Hair, & Nails") fell
//   through to a null result and the verdict headline degraded to
//   "your profile". This test locks the fix and covers every goal
//   label that ships in `core/constants/schema_ids.dart`.

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/schema_ids.dart';
import 'package:pharmaguide/core/models/fit_score_result.dart';
import 'package:pharmaguide/features/product_detail/product_detail_helpers.dart';

FitScoreResult _result(List<String> reasons) {
  return FitScoreResult(
    scoreFit20: 0,
    e1: 0,
    e2a: 0,
    e2b: 0,
    e2c: 0,
    missingFields: const [],
    maxPossible: 100,
    state: FitAssessmentState.goodFit,
    reasons: reasons,
  );
}

void main() {
  group('topGoalLabelFromFit — null + empty', () {
    test('null result → null', () {
      expect(topGoalLabelFromFit(null), isNull);
    });

    test('empty reasons → null', () {
      expect(topGoalLabelFromFit(_result(const [])), isNull);
    });

    test('reason without "your … goal" pattern → null', () {
      // E2c medical-compatibility reasons, dosage feedback, etc.
      // None of these match the goal pattern.
      expect(
        topGoalLabelFromFit(
          _result(const [
            'Effective magnesium dose for sleep',
            'Brand has third-party testing',
            'No conditions on file conflict',
          ]),
        ),
        isNull,
      );
    });
  });

  group('topGoalLabelFromFit — every SchemaIds goal label', () {
    // Coverage gate: every label that lives in
    // SchemaIds.goalLabels MUST extract cleanly from the canonical
    // "Supports your <label> goal." reason that FitScoreService
    // produces. The original regex rejected ~60% of these — this
    // test makes sure that regression can never re-land silently.
    for (final entry in SchemaIds.goalLabels.entries) {
      final label = entry.value;
      test('extracts "$label" from canonical reason', () {
        final reason = 'Supports your $label goal.';
        expect(topGoalLabelFromFit(_result([reason])), label);
      });
    }
  });

  group('topGoalLabelFromFit — pattern robustness', () {
    test('takes the first matching reason in order', () {
      // FitScoreService's reasons list is already ordered by
      // relevance — the engine's call site gives us the top match
      // first. Verify we honor that order.
      expect(
        topGoalLabelFromFit(
          _result(const [
            'Supports your Sleep Quality goal.',
            'Supports your Increase Energy goal.',
          ]),
        ),
        'Sleep Quality',
      );
    });

    test('skips non-matching reasons until a goal-shaped one appears', () {
      expect(
        topGoalLabelFromFit(
          _result(const [
            'Effective magnesium dose for sleep',
            'No conditions on file conflict',
            'Supports your Sleep Quality goal.',
          ]),
        ),
        'Sleep Quality',
      );
    });

    test('case-insensitive on the surrounding text', () {
      // FitScoreService capitalizes "Supports", but be tolerant if
      // the producer changes capitalization.
      expect(
        topGoalLabelFromFit(
          _result(const ['SUPPORTS YOUR Sleep Quality GOAL.']),
        ),
        'Sleep Quality',
      );
    });

    test('handles trailing punctuation (period after "goal")', () {
      // The canonical form ends with ". The regex anchor `\s+goal\b`
      // matches the word boundary, so the period doesn't enter the
      // capture.
      expect(
        topGoalLabelFromFit(
          _result(const ['Supports your Sleep Quality goal.']),
        ),
        'Sleep Quality',
      );
    });

    test('handles trailing exclamation', () {
      expect(
        topGoalLabelFromFit(
          _result(const ['Supports your Sleep Quality goal!']),
        ),
        'Sleep Quality',
      );
    });

    test('non-greedy capture stops at first " goal" boundary', () {
      // Pathological input: the word "goal" appears twice. We pick
      // the FIRST match. Acceptable behavior; the alternative (last
      // match) would require a different anchor and the spec
      // doesn't call for it.
      expect(
        topGoalLabelFromFit(
          _result(const [
            'Supports your Sleep Quality goal — also a secondary goal.',
          ]),
        ),
        'Sleep Quality',
      );
    });

    test('rejects "goal" as substring (e.g. "goalkeeper")', () {
      // \b word boundary anchor ensures we don't false-match on
      // longer words containing "goal".
      expect(
        topGoalLabelFromFit(
          _result(const ['Supports your Sleep Quality goalkeeper.']),
        ),
        isNull,
      );
    });

    test('handles whitespace variants (tabs, multiple spaces)', () {
      expect(
        topGoalLabelFromFit(
          _result(const ['Supports  your   Sleep Quality   goal.']),
        ),
        'Sleep Quality',
      );
    });

    test('returns null when label captures empty', () {
      // "your  goal" with no label between — regex requires `(.+?)`
      // (one or more chars), so this should NOT match.
      expect(
        topGoalLabelFromFit(_result(const ['Supports your goal'])),
        isNull,
      );
    });
  });

  group('topGoalLabelFromFit — labels with special characters', () {
    // These are the labels the original (broken) regex silently
    // dropped. Each one lives in production SchemaIds.goalLabels.
    test('"Reduce Stress/Anxiety" — has /', () {
      expect(
        topGoalLabelFromFit(
          _result(const ['Supports your Reduce Stress/Anxiety goal.']),
        ),
        'Reduce Stress/Anxiety',
      );
    });

    test('"Cardiovascular/Heart Health" — has /', () {
      expect(
        topGoalLabelFromFit(
          _result(const ['Supports your Cardiovascular/Heart Health goal.']),
        ),
        'Cardiovascular/Heart Health',
      );
    });

    test('"Focus & Mental Clarity" — has &', () {
      expect(
        topGoalLabelFromFit(
          _result(const ['Supports your Focus & Mental Clarity goal.']),
        ),
        'Focus & Mental Clarity',
      );
    });

    test('"Skin, Hair, & Nails" — has comma + &', () {
      expect(
        topGoalLabelFromFit(
          _result(const ['Supports your Skin, Hair, & Nails goal.']),
        ),
        'Skin, Hair, & Nails',
      );
    });

    test('"Healthy Aging/Longevity" — has /', () {
      expect(
        topGoalLabelFromFit(
          _result(const ['Supports your Healthy Aging/Longevity goal.']),
        ),
        'Healthy Aging/Longevity',
      );
    });

    test('"Prenatal/Pregnancy Support" — has /', () {
      expect(
        topGoalLabelFromFit(
          _result(const ['Supports your Prenatal/Pregnancy Support goal.']),
        ),
        'Prenatal/Pregnancy Support',
      );
    });
  });
}
