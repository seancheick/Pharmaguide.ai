// Risk-gated Fit display selector.
//
// Spec: INITIATIVE_PRODUCT_TRUST_AND_IA.md, Sprint 1, T1.3.
//
// The most important UX decision in the Trust & IA initiative: when a
// product is contraindicated or carries an "avoid" advisory for the
// user, we MUST NOT show a Personal Fit number alongside that warning
// — even if the underlying fit math returns a high score. Showing
// "Avoid + 88/100" sends mixed signals and undermines the safety
// message.
//
// This module is a pure-function helper. Given:
//   - the worst-applicable severity from the product's stack/medical
//     interactions for this user, AND
//   - the FitScoreResult from `FitScoreService.calculate(...)`,
// it returns a sealed [FitDisplay] state telling the UI exactly what
// to render: a labeled match tier, a "Not recommended" banner, or
// nothing at all.
//
// The caller is responsible for resolving the input [Severity] from
// all relevant sources (medication interactions, stack interactions,
// product-side recall/banned flags, etc.). This helper does not look
// at any of those — it consumes the already-resolved severity.

import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/fit_score_result.dart';

/// Display state for the Personal Fit pill in Section 2 ("For You").
sealed class FitDisplay {
  const FitDisplay();
}

/// Score is in the strong band (≥85) and the product is safe-or-mild
/// for this user. Render with the most prominent positive treatment.
final class FitStrongMatch extends FitDisplay {
  /// 0..100 combined fit-and-quality score, used for the "X/100"
  /// visible on the pill.
  final double score;
  const FitStrongMatch({required this.score});
}

/// Score is good (60..84) and product is safe-or-mild. Renders with
/// neutral-positive treatment.
final class FitGoodMatch extends FitDisplay {
  final double score;
  const FitGoodMatch({required this.score});
}

/// Score is in the middle band (35..59). Render with cautious-neutral
/// treatment — the product is safe to take but the fit math doesn't
/// support a strong recommendation.
final class FitLimitedFit extends FitDisplay {
  final double score;
  const FitLimitedFit({required this.score});
}

/// Score is below threshold (<35) even though the product itself is
/// safe-or-mild. Render with concerned-neutral treatment ("Low fit —
/// not recommended for your goals"). Distinct from [FitHidden]: here
/// the product is fine, the fit is the issue.
final class FitNotRecommended extends FitDisplay {
  final double score;
  const FitNotRecommended({required this.score});
}

/// Severity is at the product-blocking tier (contraindicated / avoid).
/// Personal Fit is hidden entirely; the alert IS the message. The UI
/// renders a "Not recommended for your profile" line plus the
/// underlying alert(s); no fit number, no fit pill, no "X/100".
final class FitHidden extends FitDisplay {
  /// The severity that triggered the hide — useful for telemetry and
  /// for the UI to compose its banner copy ("Avoid for…" vs
  /// "Contraindicated for…").
  final Severity verdict;
  const FitHidden({required this.verdict});
}

/// Profile is incomplete — the fit math couldn't produce a useful
/// number. Render with a "Add your profile to personalize" affordance
/// pointing at the profile setup flow. Distinct from [FitNotRecommended]
/// (where the math succeeded but came back low) and [FitHidden] (where
/// the math may have succeeded but is suppressed by safety override).
final class FitIncomplete extends FitDisplay {
  const FitIncomplete();
}

/// Tier thresholds. Public so the UI can describe them in copy
/// ("scores ≥85 are a strong match") without re-hardcoding.
abstract final class FitDisplayThresholds {
  static const double strongMatch = 85;
  static const double goodMatch = 60;
  static const double limitedFit = 35;
}

/// Decide the [FitDisplay] state for the Personal Fit pill.
///
/// Inputs:
///   * [verdict] — the worst-applicable severity affecting this
///     product for this user. Caller composes this from medication
///     interactions, stack interactions, product flags, etc.
///   * [fitResult] — the output of `FitScoreService.calculate(...)`.
///
/// Decision order (highest priority first):
///   1. Contraindicated / Avoid → [FitHidden]. Hides the fit pill
///      regardless of the underlying score, even if the score is
///      high. This is the core risk-gating rule.
///   2. Profile incomplete → [FitIncomplete]. The math couldn't
///      produce a useful fit number, so render the "complete your
///      profile" affordance instead.
///   3. Otherwise band the [FitScoreResult.scoreCombined100] into
///      Strong / Good / Limited / NotRecommended using the
///      thresholds above.
///
/// Caution / Monitor / Informational severities pass through the
/// risk-gate untouched: they don't hide the fit pill — the alert is
/// shown alongside it. (E.g. "Good match — 78/100 · ⚠ Caution: take
/// 4h apart from levothyroxine".)
///
/// Pure function — no I/O, no widget refs, no providers. Test by
/// constructing inputs directly and asserting on the returned state.
FitDisplay computeFitDisplay({
  required Severity verdict,
  required FitScoreResult fitResult,
}) {
  // Step 1: risk-gate. Contraindicated and Avoid are the
  // product-blocking severities — fit is suppressed entirely so the
  // user can't mis-read a high fit number as permission to take
  // something they shouldn't.
  if (verdict == Severity.contraindicated || verdict == Severity.avoid) {
    return FitHidden(verdict: verdict);
  }

  // Step 2: profile completeness. If the math couldn't run, the
  // score number is meaningless and we redirect the user to the
  // profile setup flow.
  if (fitResult.state == FitAssessmentState.incompleteProfile) {
    return const FitIncomplete();
  }

  // Step 3: band by score. We band on `scoreCombined100` (PG quality
  // × personal fit) rather than `scoreFit20` (raw fit) so the user
  // sees a 0–100 number consistent with the product's quality score.
  final score = fitResult.scoreCombined100;

  if (score >= FitDisplayThresholds.strongMatch) {
    return FitStrongMatch(score: score);
  }
  if (score >= FitDisplayThresholds.goodMatch) {
    return FitGoodMatch(score: score);
  }
  if (score >= FitDisplayThresholds.limitedFit) {
    return FitLimitedFit(score: score);
  }
  return FitNotRecommended(score: score);
}
