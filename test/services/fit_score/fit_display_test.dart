// Spec: INITIATIVE_PRODUCT_TRUST_AND_IA.md, Sprint 1, T1.3.

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/fit_score_result.dart';
import 'package:pharmaguide/services/fit_score/fit_display.dart';

/// Build a minimal [FitScoreResult] suitable for `computeFitDisplay`
/// — only the fields the helper actually reads (`scoreCombined100`,
/// `state`) need realistic values.
FitScoreResult _result({
  required double score,
  FitAssessmentState state = FitAssessmentState.goodFit,
}) {
  return FitScoreResult(
    scoreFit20: 0,
    scoreCombined100: score,
    e1: 0,
    e2a: 0,
    e2b: 0,
    e2c: 0,
    missingFields: const [],
    maxPossible: 100,
    state: state,
  );
}

void main() {
  group('computeFitDisplay — risk-gate (highest priority)', () {
    test('Contraindicated → Hidden, even with a high score', () {
      final out = computeFitDisplay(
        verdict: Severity.contraindicated,
        fitResult: _result(score: 95),
      );
      expect(out, isA<FitHidden>());
      expect((out as FitHidden).verdict, Severity.contraindicated);
    });

    test('Avoid → Hidden, even with a high score', () {
      final out = computeFitDisplay(
        verdict: Severity.avoid,
        fitResult: _result(score: 92),
      );
      expect(out, isA<FitHidden>());
      expect((out as FitHidden).verdict, Severity.avoid);
    });

    test('Avoid + low score → still Hidden (risk-gate, not score-gate)', () {
      // Sanity: hide regardless of the underlying score.
      final out = computeFitDisplay(
        verdict: Severity.avoid,
        fitResult: _result(score: 10),
      );
      expect(out, isA<FitHidden>());
    });
  });

  group('computeFitDisplay — caution/monitor pass-through', () {
    test('Caution + score 80 → GoodMatch (caution does not hide fit)', () {
      // Spec test: caution doesn't gate fit, just adds an alert that
      // the UI renders alongside the fit pill.
      final out = computeFitDisplay(
        verdict: Severity.caution,
        fitResult: _result(score: 80),
      );
      expect(out, isA<FitGoodMatch>());
      expect((out as FitGoodMatch).score, 80);
    });

    test('Caution + score 90 → StrongMatch (caution does not cap)', () {
      // Caution doesn't cap the band — a strong-band score under
      // caution is still a StrongMatch (with the caution alert
      // rendered separately by the UI).
      final out = computeFitDisplay(
        verdict: Severity.caution,
        fitResult: _result(score: 90),
      );
      expect(out, isA<FitStrongMatch>());
    });

    test('Monitor + score 88 → StrongMatch', () {
      final out = computeFitDisplay(
        verdict: Severity.monitor,
        fitResult: _result(score: 88),
      );
      expect(out, isA<FitStrongMatch>());
    });

    test('Informational + score 30 → NotRecommended', () {
      // Informational severity (a context-only warning) doesn't gate
      // and doesn't change the score band. A low score is still low.
      final out = computeFitDisplay(
        verdict: Severity.informational,
        fitResult: _result(score: 30),
      );
      expect(out, isA<FitNotRecommended>());
    });
  });

  group('computeFitDisplay — Safe banding by combined score', () {
    test('Safe + score 95 → StrongMatch', () {
      final out = computeFitDisplay(
        verdict: Severity.safe,
        fitResult: _result(score: 95),
      );
      expect(out, isA<FitStrongMatch>());
      expect((out as FitStrongMatch).score, 95);
    });

    test('Safe + score 85.0 (boundary) → StrongMatch', () {
      final out = computeFitDisplay(
        verdict: Severity.safe,
        fitResult: _result(score: 85),
      );
      expect(out, isA<FitStrongMatch>());
    });

    test('Safe + score 84.99 → GoodMatch (just below strong threshold)',
        () {
      final out = computeFitDisplay(
        verdict: Severity.safe,
        fitResult: _result(score: 84.99),
      );
      expect(out, isA<FitGoodMatch>());
    });

    test('Safe + score 70 → GoodMatch', () {
      final out = computeFitDisplay(
        verdict: Severity.safe,
        fitResult: _result(score: 70),
      );
      expect(out, isA<FitGoodMatch>());
    });

    test('Safe + score 60.0 (boundary) → GoodMatch', () {
      final out = computeFitDisplay(
        verdict: Severity.safe,
        fitResult: _result(score: 60),
      );
      expect(out, isA<FitGoodMatch>());
    });

    test('Safe + score 59.99 → LimitedFit (just below good threshold)',
        () {
      final out = computeFitDisplay(
        verdict: Severity.safe,
        fitResult: _result(score: 59.99),
      );
      expect(out, isA<FitLimitedFit>());
    });

    test('Safe + score 45 → LimitedFit', () {
      final out = computeFitDisplay(
        verdict: Severity.safe,
        fitResult: _result(score: 45),
      );
      expect(out, isA<FitLimitedFit>());
    });

    test('Safe + score 35.0 (boundary) → LimitedFit', () {
      final out = computeFitDisplay(
        verdict: Severity.safe,
        fitResult: _result(score: 35),
      );
      expect(out, isA<FitLimitedFit>());
    });

    test('Safe + score 34.99 → NotRecommended (low fit even when safe)',
        () {
      // Per spec: "Verdict Safe + fit<35 → NotRecommended (low fit
      // even when safe)" — the product is safe to take but the
      // personalized math doesn't support a recommendation.
      final out = computeFitDisplay(
        verdict: Severity.safe,
        fitResult: _result(score: 34.99),
      );
      expect(out, isA<FitNotRecommended>());
    });

    test('Safe + score 0 → NotRecommended', () {
      final out = computeFitDisplay(
        verdict: Severity.safe,
        fitResult: _result(score: 0),
      );
      expect(out, isA<FitNotRecommended>());
    });
  });

  group('computeFitDisplay — incomplete profile', () {
    test('Safe + incompleteProfile → FitIncomplete (regardless of score)',
        () {
      final out = computeFitDisplay(
        verdict: Severity.safe,
        fitResult: _result(
          score: 75,
          state: FitAssessmentState.incompleteProfile,
        ),
      );
      expect(out, isA<FitIncomplete>());
    });

    test('Caution + incompleteProfile → FitIncomplete (still incomplete)',
        () {
      // Profile incompleteness applies even when there are alerts —
      // the UI renders the alerts separately, but the fit pill
      // becomes the "complete your profile" affordance.
      final out = computeFitDisplay(
        verdict: Severity.caution,
        fitResult: _result(
          score: 80,
          state: FitAssessmentState.incompleteProfile,
        ),
      );
      expect(out, isA<FitIncomplete>());
    });

    test(
        'Avoid + incompleteProfile → FitHidden (risk-gate trumps '
        'incompleteness)', () {
      // Risk-gate runs BEFORE the incomplete-profile check. A
      // contraindicated/avoid product hides the fit even if profile
      // incomplete — the alert message is the priority signal.
      final out = computeFitDisplay(
        verdict: Severity.avoid,
        fitResult: _result(
          score: 0,
          state: FitAssessmentState.incompleteProfile,
        ),
      );
      expect(out, isA<FitHidden>());
    });
  });

  group('FitDisplayThresholds', () {
    test('threshold constants are stable + ordered', () {
      // Tier ordering must be: strong > good > limited.
      expect(
        FitDisplayThresholds.strongMatch,
        greaterThan(FitDisplayThresholds.goodMatch),
      );
      expect(
        FitDisplayThresholds.goodMatch,
        greaterThan(FitDisplayThresholds.limitedFit),
      );
      // Pin exact values so a refactor that nudges them surfaces in
      // CI. UI copy ("scores ≥85 are a strong match") references
      // these — moving them silently breaks that copy.
      expect(FitDisplayThresholds.strongMatch, 85);
      expect(FitDisplayThresholds.goodMatch, 60);
      expect(FitDisplayThresholds.limitedFit, 35);
    });
  });
}
