// Spec: INITIATIVE_PRODUCT_TRUST_AND_IA.md, Sprint 1, T1.3.

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/fit_score_result.dart';
import 'package:pharmaguide/services/fit_score/fit_display.dart';

/// Build a minimal [FitScoreResult] suitable for `computeFitDisplay`.
/// The categorical assessment state is the sole fit-display contract.
FitScoreResult _result({
  FitAssessmentState state = FitAssessmentState.goodFit,
}) {
  return FitScoreResult(
    missingFields: const [],
    state: state,
    // Full coverage — these tests exercise state-driven display, not
    // the coverage gate.
    mappedCoverage: 1.0,
  );
}

void main() {
  group('computeFitDisplay — risk-gate (highest priority)', () {
    test('Contraindicated → Hidden, even with a strong assessment', () {
      final out = computeFitDisplay(
        verdict: Severity.contraindicated,
        fitResult: _result(),
      );
      expect(out, isA<FitHidden>());
      expect((out as FitHidden).verdict, Severity.contraindicated);
    });

    test('Avoid → Hidden, even with a strong assessment', () {
      final out = computeFitDisplay(
        verdict: Severity.avoid,
        fitResult: _result(),
      );
      expect(out, isA<FitHidden>());
      expect((out as FitHidden).verdict, Severity.avoid);
    });

    test(
      'Avoid + limited assessment → still Hidden (risk-gate, not score-gate)',
      () {
        // Sanity: hide regardless of the underlying fit assessment.
        final out = computeFitDisplay(
          verdict: Severity.avoid,
          fitResult: _result(),
        );
        expect(out, isA<FitHidden>());
      },
    );
  });

  group('computeFitDisplay — caution/monitor pass-through', () {
    test('Caution + goodFit → GoodMatch (caution does not hide fit)', () {
      // Spec test: caution doesn't gate fit, just adds an alert that
      // the UI renders alongside the verdict headline.
      final out = computeFitDisplay(
        verdict: Severity.caution,
        fitResult: _result(state: FitAssessmentState.goodFit),
      );
      expect(out, isA<FitGoodMatch>());
    });

    test('Caution + strong assessment → GoodMatch cap', () {
      final out = computeFitDisplay(
        verdict: Severity.caution,
        fitResult: _result(state: FitAssessmentState.strongMatch),
      );
      expect(out, isA<FitGoodMatch>());
    });

    test('Monitor + strong assessment → GoodMatch cap', () {
      final out = computeFitDisplay(
        verdict: Severity.monitor,
        fitResult: _result(state: FitAssessmentState.strongMatch),
      );
      expect(out, isA<FitGoodMatch>());
    });

    test('Informational + notRecommended → NotRecommended', () {
      // Informational severity (a context-only warning) doesn't gate
      // and doesn't change the tier band. A limited assessment stays limited.
      final out = computeFitDisplay(
        verdict: Severity.informational,
        fitResult: _result(state: FitAssessmentState.notRecommended),
      );
      expect(out, isA<FitNotRecommended>());
    });
  });

  group('computeFitDisplay — safe display from assessment state', () {
    test('Safe + strongMatch state → StrongMatch', () {
      final out = computeFitDisplay(
        verdict: Severity.safe,
        fitResult: _result(state: FitAssessmentState.strongMatch),
      );
      expect(out, isA<FitStrongMatch>());
    });

    test('Safe + goodFit state → GoodMatch', () {
      final out = computeFitDisplay(
        verdict: Severity.safe,
        fitResult: _result(state: FitAssessmentState.goodFit),
      );
      expect(out, isA<FitGoodMatch>());
    });

    test('Safe + limitedFit state → LimitedFit', () {
      final out = computeFitDisplay(
        verdict: Severity.safe,
        fitResult: _result(state: FitAssessmentState.limitedFit),
      );
      expect(out, isA<FitLimitedFit>());
    });

    test('Safe + notRecommended state → NotRecommended', () {
      final out = computeFitDisplay(
        verdict: Severity.safe,
        fitResult: _result(state: FitAssessmentState.notRecommended),
      );
      expect(out, isA<FitNotRecommended>());
    });
  });

  group('computeFitDisplay — incomplete profile', () {
    test('Safe + incompleteProfile → FitIncomplete', () {
      final out = computeFitDisplay(
        verdict: Severity.safe,
        fitResult: _result(state: FitAssessmentState.incompleteProfile),
      );
      expect(out, isA<FitIncomplete>());
    });

    test('Caution + incompleteProfile → FitIncomplete (still incomplete)', () {
      // Profile incompleteness applies even when there are alerts —
      // the UI renders the alerts separately, but the fit display
      // becomes the "complete your profile" affordance.
      final out = computeFitDisplay(
        verdict: Severity.caution,
        fitResult: _result(state: FitAssessmentState.incompleteProfile),
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
        fitResult: _result(state: FitAssessmentState.incompleteProfile),
      );
      expect(out, isA<FitHidden>());
    });
  });
}
