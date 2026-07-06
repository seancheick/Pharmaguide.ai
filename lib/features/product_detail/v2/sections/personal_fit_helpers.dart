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
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/services/ingredients/ingredient_canonicalizer.dart';
import 'package:pharmaguide/services/warnings/interaction_warning.dart';

/// Generate the personal-fit headline from a [FitDisplay] state and an
/// optional top-goal label.
///
///   • Strong/Good → "&lt;verb&gt; match for your &lt;X&gt; goal" or
///     "&lt;verb&gt; match for your profile" when no top goal label.
///   • Limited → "Neutral for your profile".
///   • NotRecommended / Hidden → "Not recommended for your profile"
///   • Incomplete → "Add your profile to personalize"
String personalFitHeadline(FitDisplay fit, String? topGoalLabel) {
  final goalSuffix = (topGoalLabel != null && topGoalLabel.trim().isNotEmpty)
      ? 'your ${topGoalLabel.trim()} goal'
      : 'your profile';
  return switch (fit) {
    FitStrongMatch() => 'Strong match for $goalSuffix',
    FitGoodMatch() => 'Good match for $goalSuffix',
    FitLimitedFit() => 'Neutral for your profile',
    FitNotRecommended() || FitHidden() => 'Not recommended for your profile',
    FitIncomplete() => 'Add your profile to personalize',
  };
}

/// Build up to 2 causal bullets. Priority:
///   1. Emitted beneficial profile warnings (`direction == beneficial`)
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
  List<InteractionWarning> profileBenefitWarnings = const [],
}) {
  if (fit is FitHidden ||
      fit is FitNotRecommended ||
      fit is FitIncomplete ||
      fit is FitLimitedFit) {
    return const [];
  }

  final positives = generatePositiveProfileBulletsFromWarnings(
    warnings: profileBenefitWarnings,
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

/// Build "[Ingredient] [phrase]" bullets from pipeline-emitted beneficial
/// condition warnings. This is the Personal Fit replacement for the retired
/// app-owned condition-threshold table.
///
/// The warnings themselves are suppressed before the review surface renders;
/// this helper uses the raw emitted rows as explanatory, positive context.
/// It is deliberately narrow: only `direction == beneficial` rows with a
/// matching user condition and non-hard severity can produce copy.
List<String> generatePositiveProfileBulletsFromWarnings({
  required List<InteractionWarning> warnings,
  required List<String> userConditionIds,
}) {
  if (warnings.isEmpty || userConditionIds.isEmpty) return const [];

  final bullets = <String>[];
  final seenConditions = <String>{};

  for (final rawCondition in userConditionIds) {
    final condition = rawCondition.trim().toLowerCase();
    if (seenConditions.contains(condition)) continue;
    final phrase = _conditionSupportPhrase[condition];
    if (phrase == null) continue;

    for (final warning in warnings) {
      if (warning.direction != 'beneficial') continue;
      if (warning.severity == Severity.contraindicated ||
          warning.severity == Severity.avoid) {
        continue;
      }
      if (!warning.conditionIds
          .map((id) => id.trim().toLowerCase())
          .contains(condition)) {
        continue;
      }

      final ingredient = warning.ingredientName?.trim();
      if (ingredient == null || ingredient.isEmpty) continue;

      bullets.add('${_displayName(ingredient)} $phrase');
      seenConditions.add(condition);
      break;
    }
  }

  return bullets;
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

/// Per-condition phrase appended after the ingredient display name to form
/// positive Personal Fit copy.
const Map<String, String> _conditionSupportPhrase = {
  'pregnancy': 'is recommended during pregnancy',
  'lactation': 'is recommended during breastfeeding',
  'ttc': 'is recommended during pre-conception',
  'diabetes': 'supports your blood sugar goal',
  'hypertension': 'supports your blood pressure goal',
  'thyroid_disorder': 'supports your thyroid health',
  'high_cholesterol': 'supports your cholesterol goal',
};

String _displayName(String raw) {
  final canonical = canonicalizeIngredientName(raw);
  if (canonical.isEmpty) return '';
  const brandedForms = <String, String>{
    'vitamin_d': 'Vitamin D',
    'vitamin_d3': 'Vitamin D3',
    'vitamin_a': 'Vitamin A',
    'vitamin_b6': 'Vitamin B6',
    'vitamin_b12': 'Vitamin B12',
    'vitamin_c': 'Vitamin C',
    'vitamin_e': 'Vitamin E',
    'vitamin_k': 'Vitamin K',
    'vitamin_k2': 'Vitamin K2',
    'omega_3': 'Omega-3',
  };
  final branded = brandedForms[canonical];
  if (branded != null) return branded;

  return canonical
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}
