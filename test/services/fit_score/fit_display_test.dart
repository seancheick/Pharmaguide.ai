// Spec: INITIATIVE_PRODUCT_TRUST_AND_IA.md, Sprint 1, T1.3.

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/fit_score_result.dart';
import 'package:pharmaguide/services/fit_score/fit_display.dart';

/// Build a minimal [FitScoreResult] suitable for `computeFitDisplay`
/// — only the fields the helper actually reads (`scoreFit20`,
/// `state`) need realistic values.
FitScoreResult _result({
  required double scoreFit20,
  FitAssessmentState state = FitAssessmentState.goodFit,
}) {
  return FitScoreResult(
    scoreFit20: scoreFit20,
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
    test('Contraindicated → Hidden, even with a high fit fraction', () {
      final out = computeFitDisplay(
        verdict: Severity.contraindicated,
        fitResult: _result(scoreFit20: 19),
      );
      expect(out, isA<FitHidden>());
      expect((out as FitHidden).verdict, Severity.contraindicated);
    });

    test('Avoid → Hidden, even with a high fit fraction', () {
      final out = computeFitDisplay(
        verdict: Severity.avoid,
        fitResult: _result(scoreFit20: 18.4),
      );
      expect(out, isA<FitHidden>());
      expect((out as FitHidden).verdict, Severity.avoid);
    });

    test('Avoid + low fit fraction → still Hidden (risk-gate, not score-gate)',
        () {
      // Sanity: hide regardless of the underlying fit fraction.
      final out = computeFitDisplay(
        verdict: Severity.avoid,
        fitResult: _result(scoreFit20: 2),
      );
      expect(out, isA<FitHidden>());
    });
  });

  group('computeFitDisplay — caution/monitor pass-through', () {
    test('Caution + fit 16/20 → GoodMatch (caution does not hide fit)', () {
      // Spec test: caution doesn't gate fit, just adds an alert that
      // the UI renders alongside the verdict headline.
      final out = computeFitDisplay(
        verdict: Severity.caution,
        fitResult: _result(scoreFit20: 16),
      );
      expect(out, isA<FitGoodMatch>());
    });

    test('Caution + fit 18/20 → StrongMatch (caution does not cap)', () {
      // Caution doesn't cap the band — a strong-band fraction under
      // caution is still a StrongMatch (with the caution alert
      // rendered separately by the UI).
      final out = computeFitDisplay(
        verdict: Severity.caution,
        fitResult: _result(scoreFit20: 18),
      );
      expect(out, isA<FitStrongMatch>());
    });

    test('Monitor + fit 17.5/20 → StrongMatch', () {
      final out = computeFitDisplay(
        verdict: Severity.monitor,
        fitResult: _result(scoreFit20: 17.5),
      );
      expect(out, isA<FitStrongMatch>());
    });

    test('Informational + fit 6/20 → NotRecommended', () {
      // Informational severity (a context-only warning) doesn't gate
      // and doesn't change the tier band. A low fraction is still low.
      final out = computeFitDisplay(
        verdict: Severity.informational,
        fitResult: _result(scoreFit20: 6),
      );
      expect(out, isA<FitNotRecommended>());
    });
  });

  group('computeFitDisplay — Safe banding by fit fraction', () {
    test('Safe + fit 19/20 (0.95) → StrongMatch', () {
      final out = computeFitDisplay(
        verdict: Severity.safe,
        fitResult: _result(scoreFit20: 19),
      );
      expect(out, isA<FitStrongMatch>());
    });

    test('Safe + fit 17.0/20 (0.85, boundary) → StrongMatch', () {
      final out = computeFitDisplay(
        verdict: Severity.safe,
        fitResult: _result(scoreFit20: 17.0),
      );
      expect(out, isA<FitStrongMatch>());
    });

    test('Safe + fit 16.999/20 → GoodMatch (just below strong threshold)', () {
      final out = computeFitDisplay(
        verdict: Severity.safe,
        fitResult: _result(scoreFit20: 16.999),
      );
      expect(out, isA<FitGoodMatch>());
    });

    test('Safe + fit 14/20 (0.70) → GoodMatch', () {
      final out = computeFitDisplay(
        verdict: Severity.safe,
        fitResult: _result(scoreFit20: 14),
      );
      expect(out, isA<FitGoodMatch>());
    });

    test('Safe + fit 12.0/20 (0.60, boundary) → GoodMatch', () {
      final out = computeFitDisplay(
        verdict: Severity.safe,
        fitResult: _result(scoreFit20: 12.0),
      );
      expect(out, isA<FitGoodMatch>());
    });

    test('Safe + fit 11.999/20 → LimitedFit (just below good threshold)', () {
      final out = computeFitDisplay(
        verdict: Severity.safe,
        fitResult: _result(scoreFit20: 11.999),
      );
      expect(out, isA<FitLimitedFit>());
    });

    test('Safe + fit 10/20 (0.50) → LimitedFit', () {
      final out = computeFitDisplay(
        verdict: Severity.safe,
        fitResult: _result(scoreFit20: 10),
      );
      expect(out, isA<FitLimitedFit>());
    });

    test('Safe + fit 7.0/20 (0.35, boundary) → LimitedFit', () {
      final out = computeFitDisplay(
        verdict: Severity.safe,
        fitResult: _result(scoreFit20: 7.0),
      );
      expect(out, isA<FitLimitedFit>());
    });

    test('Safe + fit 6.999/20 → NotRecommended (low fit even when safe)', () {
      // Per spec: fit fraction <0.35 → NotRecommended — the product
      // is safe to take but the personalized math doesn't support a
      // recommendation.
      final out = computeFitDisplay(
        verdict: Severity.safe,
        fitResult: _result(scoreFit20: 6.999),
      );
      expect(out, isA<FitNotRecommended>());
    });

    test('Safe + fit 0 → NotRecommended', () {
      final out = computeFitDisplay(
        verdict: Severity.safe,
        fitResult: _result(scoreFit20: 0),
      );
      expect(out, isA<FitNotRecommended>());
    });
  });

  group('computeFitDisplay — incomplete profile', () {
    test('Safe + incompleteProfile → FitIncomplete (regardless of fit fraction)',
        () {
      final out = computeFitDisplay(
        verdict: Severity.safe,
        fitResult: _result(
          scoreFit20: 15,
          state: FitAssessmentState.incompleteProfile,
        ),
      );
      expect(out, isA<FitIncomplete>());
    });

    test('Caution + incompleteProfile → FitIncomplete (still incomplete)', () {
      // Profile incompleteness applies even when there are alerts —
      // the UI renders the alerts separately, but the fit display
      // becomes the "complete your profile" affordance.
      final out = computeFitDisplay(
        verdict: Severity.caution,
        fitResult: _result(
          scoreFit20: 16,
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
          scoreFit20: 0,
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
      // CI. Banding logic references these — moving them silently
      // changes tier assignments.
      expect(FitDisplayThresholds.strongMatch, 0.85);
      expect(FitDisplayThresholds.goodMatch, 0.60);
      expect(FitDisplayThresholds.limitedFit, 0.35);
    });
  });
}
