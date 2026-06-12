// PersonalFit helpers (pure logic).
//
// Owns the headline/bullet generation contract used by the v2 Personal
// Fit card.
//
// Sean's rules (2026-05-15):
//   • Preserve provider logic — no new fit language. The headlines
//     and bullets come from production's logic + `FitScoreResult.reasons`.
//   • Preserve `computeFitDisplay` — caller passes the resolved
//     `FitDisplay`; helpers never re-derive it.
//   • No numeric FitScore pill — qualitative state only.
//   • Calm + personal — bullets are causal sentences, not gamified.

import 'package:pharmaguide/services/fit_score/fit_display.dart';
import 'package:pharmaguide/services/warnings/condition_thresholds.dart';

/// Generate the personal-fit headline from a [FitDisplay] state and an
/// optional top-goal label.
///
///   • Strong/Good/Limited → "&lt;verb&gt; match for your &lt;X&gt; goal" or
///     "&lt;verb&gt; match for your profile" when no top goal label.
///   • NotRecommended / Hidden → "Not recommended for your profile"
///   • Incomplete → "Add your profile to personalize"
String personalFitHeadline(FitDisplay fit, String? topGoalLabel) {
  final goalSuffix = (topGoalLabel != null && topGoalLabel.trim().isNotEmpty)
      ? 'your ${topGoalLabel.trim()} goal'
      : 'your profile';
  return switch (fit) {
    FitStrongMatch() => 'Strong match for $goalSuffix',
    FitGoodMatch() => 'Good match for $goalSuffix',
    FitLimitedFit() => 'Limited fit for $goalSuffix',
    FitNotRecommended() || FitHidden() => 'Not recommended for your profile',
    FitIncomplete() => 'Add your profile to personalize',
  };
}

/// Build up to 2 causal bullets. Priority:
///   1. Positive-profile bullets (T3 Path A via
///      `generatePositiveProfileBullets`)
///   2. fitReasons fallback (`FitScoreResult.reasons`), cleaned
///
/// FitHidden / FitNotRecommended / FitIncomplete / FitLimitedFit
/// deliberately render NO positive bullets — pairing "Magnesium
/// supports your blood pressure goal" next to "Not recommended for
/// your profile" (or a hedged "Limited fit") is incoherent. The
/// headline alone communicates the state.
List<String> personalFitBullets({
  required FitDisplay fit,
  required List<String> fitReasons,
  required List<String> ingredientNames,
  required List<String> userConditions,
}) {
  if (fit is FitHidden ||
      fit is FitNotRecommended ||
      fit is FitIncomplete ||
      fit is FitLimitedFit) {
    return const [];
  }

  final positives = generatePositiveProfileBullets(
    ingredientNames: ingredientNames,
    userConditionIds: userConditions,
  );

  final bullets = <String>[];
  bullets.addAll(positives);
  if (bullets.length < 2) {
    // Top up from engine-generated reasons. These are already causal
    // sentences (FitScore engine produces them via goal-cluster logic).
    for (final reason in fitReasons) {
      if (bullets.length >= 2) break;
      final clean = cleanFitReason(reason);
      if (clean.isEmpty) continue;
      if (bullets.contains(clean)) continue; // dedupe
      bullets.add(clean);
    }
  }
  return bullets.take(2).toList(growable: false);
}

/// Strip trailing period + drop per-condition warning leaks. Verbatim
/// Returns empty string for reasons that should be filtered out
/// (see [_isConditionWarningReason]).
String cleanFitReason(String reason) {
  final trimmed = reason.trim();
  if (trimmed.isEmpty) return '';
  // T12.1 — drop reasons that duplicate condition-warning surfaces
  // gated by T4. The fit engine generates reasons via a separate code
  // path from warnings; we filter them here so the Personal Fit card
  // doesn't surface false positives the warnings list already
  // suppressed.
  if (_isConditionWarningReason(trimmed)) return '';
  if (trimmed.endsWith('.')) {
    return trimmed.substring(0, trimmed.length - 1);
  }
  return trimmed;
}

/// Condition-label prefixes that mark a reason as a per-condition
/// warning leak ("Diabetes: monitor from Vitamin D"). When the colon
/// prefix matches one of these, the reason is suppressed at clean time.
const Set<String> _conditionLabelPrefixes = {
  'pregnancy',
  'lactation',
  'breastfeeding',
  'ttc',
  'trying to conceive',
  'pre-conception',
  'diabetes',
  'hypertension',
  'high blood pressure',
  'kidney disease',
  'liver disease',
  'thyroid',
  'thyroid disorder',
  'autoimmune',
  'seizure',
  'seizure disorder',
  'high cholesterol',
  'bleeding disorders',
  'heart disease',
  'surgery',
  'upcoming surgery',
};

/// Returns true when [reason] is a per-condition warning leak.
/// Pattern: `"<Condition Label>: <warning text>"`. Verbatim port of
bool _isConditionWarningReason(String reason) {
  final colonIdx = reason.indexOf(':');
  if (colonIdx <= 0 || colonIdx > 30) return false;
  final prefix = reason.substring(0, colonIdx).trim().toLowerCase();
  return _conditionLabelPrefixes.contains(prefix);
}
