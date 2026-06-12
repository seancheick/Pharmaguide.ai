// Spec: INITIATIVE_PRODUCT_TRUST_AND_IA.md, Sprint 1, T1.3.

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/fit_score_result.dart';
import 'package:pharmaguide/services/fit_score/fit_display.dart';

/// Build a minimal [FitScoreResult] suitable for `computeFitDisplay`
/// — the assessment `state` is authoritative for display; score stays
/// internal/debug-only.
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
    // Full coverage — these tests exercise state-driven display, not
    // the coverage gate.
    mappedCoverage: 1.0,
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

    test(
      'Avoid + low fit fraction → still Hidden (risk-gate, not score-gate)',
      () {
        // Sanity: hide regardless of the underlying fit fraction.
        final out = computeFitDisplay(
          verdict: Severity.avoid,
          fitResult: _result(scoreFit20: 2),
        );
        expect(out, isA<FitHidden>());
      },
    );
  });

  group('computeFitDisplay — caution/monitor pass-through', () {
    test('Caution + fit 16/20 → GoodMatch (caution does not hide fit)', () {
      // Spec test: caution doesn't gate fit, just adds an alert that
      // the UI renders alongside the verdict headline.
      final out = computeFitDisplay(
        verdict: Severity.caution,
        fitResult: _result(scoreFit20: 16, state: FitAssessmentState.goodFit),
      );
      expect(out, isA<FitGoodMatch>());
    });

    test('Caution + strong assessment → GoodMatch cap', () {
      final out = computeFitDisplay(
        verdict: Severity.caution,
        fitResult: _result(
          scoreFit20: 18,
          state: FitAssessmentState.strongMatch,
        ),
      );
      expect(out, isA<FitGoodMatch>());
    });

    test('Monitor + strong assessment → GoodMatch cap', () {
      final out = computeFitDisplay(
        verdict: Severity.monitor,
        fitResult: _result(
          scoreFit20: 17.5,
          state: FitAssessmentState.strongMatch,
        ),
      );
      expect(out, isA<FitGoodMatch>());
    });

    test('Informational + fit 6/20 → NotRecommended', () {
      // Informational severity (a context-only warning) doesn't gate
      // and doesn't change the tier band. A low fraction is still low.
      final out = computeFitDisplay(
        verdict: Severity.informational,
        fitResult: _result(
          scoreFit20: 6,
          state: FitAssessmentState.notRecommended,
        ),
      );
      expect(out, isA<FitNotRecommended>());
    });
  });

  group('computeFitDisplay — safe display from assessment state', () {
    test('Safe + strongMatch state → StrongMatch', () {
      final out = computeFitDisplay(
        verdict: Severity.safe,
        fitResult: _result(
          scoreFit20: 19,
          state: FitAssessmentState.strongMatch,
        ),
      );
      expect(out, isA<FitStrongMatch>());
    });

    test('Safe + goodFit state → GoodMatch', () {
      final out = computeFitDisplay(
        verdict: Severity.safe,
        fitResult: _result(scoreFit20: 17, state: FitAssessmentState.goodFit),
      );
      expect(out, isA<FitGoodMatch>());
    });

    test(
      'Safe + limitedFit state → LimitedFit even with high internal score',
      () {
        final out = computeFitDisplay(
          verdict: Severity.safe,
          fitResult: _result(
            scoreFit20: 19,
            state: FitAssessmentState.limitedFit,
          ),
        );
        expect(out, isA<FitLimitedFit>());
      },
    );

    test('Safe + notRecommended state → NotRecommended', () {
      final out = computeFitDisplay(
        verdict: Severity.safe,
        fitResult: _result(
          scoreFit20: 18,
          state: FitAssessmentState.notRecommended,
        ),
      );
      expect(out, isA<FitNotRecommended>());
    });
  });

  group('computeFitDisplay — incomplete profile', () {
    test(
      'Safe + incompleteProfile → FitIncomplete (regardless of fit fraction)',
      () {
        final out = computeFitDisplay(
          verdict: Severity.safe,
          fitResult: _result(
            scoreFit20: 15,
            state: FitAssessmentState.incompleteProfile,
          ),
        );
        expect(out, isA<FitIncomplete>());
      },
    );

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

    test('Avoid + incompleteProfile → FitHidden (risk-gate trumps '
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
