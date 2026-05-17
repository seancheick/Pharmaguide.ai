// Phase 11.7c.2 — PersonalFit section adapter.
//
// V2 mirror of production's `PersonalFitCard`. Composes the v2 PGPersonalFitCard
// using the same data flow production uses:
//
//   fitScoreForProductProvider(dsldId) → FitScoreResult
//   worstSeverityOf(guardedWarnings)   → Severity verdict
//   computeFitDisplay(verdict, result) → FitDisplay (production-side fn)
//   topGoalLabelFromFit(fitResult)     → String? (production-side fn)
//   ingredients from detailBlob        → List<String>
//   profile.conditions                 → user conditions for bullets
//
// All headline/bullet generation lives in `personal_fit_helpers.dart`
// to keep this file pure widget composition.
//
// Sean's rules (2026-05-15) — preserved verbatim:
//   • Preserve fitScoreForProductProvider chain.
//   • Preserve computeFitDisplay logic (caller passes resolved fit).
//   • Preserve edit-pencil → Routes.profileSetup callback.
//   • No invented fit language — use FitStrongMatch/GoodMatch/
//     LimitedFit/NotRecommended/Hidden/Incomplete enum production
//     emits.
//   • No numeric FitScore pill — qualitative state only.
//   • Calm + personal — shield icon + headline + max 2 causal bullets
//     + edit pencil, matching production card's restraint.

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_for_you_extras.dart';
import 'package:pharmaguide/core/components/pg_personal_fit_card.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/personal_fit_helpers.dart';
import 'package:pharmaguide/services/fit_score/fit_display.dart';

/// Build the PersonalFit section widget. Composes the v1 ForYouSection's
/// 5-signal Section-2 block:
///   1. Context chips (which profile signals drive the verdict)
///   2. Verdict + bullets (via PGPersonalFitCard)
///   3. "Why this fits you" expandable (top-4 FitScore reasons)
///
/// Alerts (the v1 4th signal) live in `review_before_use_section` in
/// v2 — separated for cleaner information architecture.
///
/// `FitHidden` returns `SizedBox.shrink()` to mirror production's
/// T16.1 dedup rule (hero already surfaces a BlockedBanner or
/// "Avoid" banner for contraindicated/avoid verdicts — re-rendering
/// "Not recommended for your profile" here would be redundant).
Widget buildPersonalFitSection({
  required FitDisplay fit,
  required String? topGoalLabel,
  required List<String> fitReasons,
  required List<String> ingredientNames,
  required List<String> userConditions,
  required List<String> contextChips,
  required VoidCallback onEditProfile,
}) {
  if (fit is FitHidden) return const SizedBox.shrink();

  final headline = personalFitHeadline(fit, topGoalLabel);
  final bullets = personalFitBullets(
    fit: fit,
    fitReasons: fitReasons,
    ingredientNames: ingredientNames,
    userConditions: userConditions,
  );

  final hasChips = contextChips.isNotEmpty;
  final hasReasons = fitReasons.isNotEmpty;

  // When neither chips nor reasons exist, render the card alone —
  // avoids an empty wrapper Column that would still pad the layout.
  if (!hasChips && !hasReasons) {
    return PGPersonalFitCard(
      fit: fit,
      headline: headline,
      bullets: bullets,
      onEditProfile: onEditProfile,
    );
  }

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (hasChips) ...[
        PGContextChips(chips: contextChips),
        const SizedBox(height: V2Spacing.space12),
      ],
      PGPersonalFitCard(
        fit: fit,
        headline: headline,
        bullets: bullets,
        onEditProfile: onEditProfile,
      ),
      if (hasReasons) ...[
        const SizedBox(height: V2Spacing.space12),
        PGWhyThisFitsExpander(reasons: fitReasons),
      ],
    ],
  );
}

/// Build the context-chips list from a user profile. Mirrors v1
/// ForYouSection._buildContextChips: up to 2 goals + 2 conditions +
/// 2 drug classes, then capped at 4 total.
List<String> contextChipsFromProfile({
  required List<String> goals,
  required List<String> conditions,
  required List<String> drugClasses,
}) {
  final chips = <String>[
    ...goals.take(2),
    ...conditions.take(2),
    ...drugClasses.take(2),
  ];
  return chips.take(4).toList(growable: false);
}

/// Pure helper — extract ingredient names from a raw detail blob.
/// Mirrors production's inline extraction at line 322–328:
///   `(blob['ingredients'] as List?)?.whereType<Map<...>>().map(...)`
/// Splitting it here keeps the connected screen orchestration-only.
List<String> ingredientNamesFromBlob(Map<String, dynamic>? blob) {
  final raw = blob?['ingredients'] as List?;
  if (raw == null) return const [];
  return raw
      .whereType<Map<String, dynamic>>()
      .map((e) => e['name']?.toString() ?? '')
      .where((n) => n.isNotEmpty)
      .toList(growable: false);
}
