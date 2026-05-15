// Phase 11.7c.3 — ReviewBeforeUse section adapter.
//
// V2 mirror of production's `ReviewBeforeUseCard` (line 381 in
// product_detail_screen.dart). Composes the v2 PGReviewBeforeUseCard
// using the same data flow production uses:
//
//   guardedWarnings (composeGuardedWarnings pipeline)
//   matchAllergens(profile.allergens, blob['allergens'])
//   matchFreeFromClaims(...)         — gluten/dairy/soy flags
//   findFreeFromConflicts(...)       — label-disagreement detector
//   gateInteractionSummary(...)      — dose-aware condition gate
//   interactionHint (JSON from _product.interactionSummaryHint)
//
// All tone/row composition lives in `review_before_use_helpers.dart`
// to keep this file pure widget composition + provider orchestration.
//
// Sean's rules (2026-05-15) — preserved verbatim:
//   • Preserve provider logic verbatim.
//   • Preserve composeGuardedWarnings / matchAllergens / matchFreeFromClaims
//     /findFreeFromConflicts pipelines.
//   • Preserve no-profile NUDGE state (renders even when warnings exist).
//   • Preserve auto-expand-on-danger behavior.
//   • Allergen `contains` ALWAYS bumps to danger even when a free-from
//     claim is present (matches production line 170).
//   • Calm + clinical voice — no imperative warnings, no alarmist tone.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/components/pg_review_before_use_card.dart';
import 'package:pharmaguide/core/components/pg_pill_button.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/core/widgets/pg_modal.dart';
import 'package:pharmaguide/features/product_detail/allergen_match.dart';
import 'package:pharmaguide/features/product_detail/free_from_match.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/review_before_use_helpers.dart';
import 'package:pharmaguide/features/product_detail/widgets/interaction_warnings.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';
import 'package:pharmaguide/services/warnings/condition_gate.dart';
import 'package:url_launcher/url_launcher.dart';

/// Build the ReviewBeforeUse section.
///
/// Returns:
///   • `_NudgeBanner` (no-profile + product has interactions) — calm
///     prompt to complete profile.
///   • `SizedBox.shrink()` — nothing to surface.
///   • `PGReviewBeforeUseCard` — the unified review card.
///
/// Layout note: the card is wrapped in a sliver-friendly Builder so
/// the connected screen can hand it a `Consumer` for the profile
/// watch without duplicating provider plumbing.
class ReviewBeforeUseSection extends ConsumerWidget {
  /// Profile-filtered interaction warnings (= guardedWarnings).
  final List<InteractionWarning> warnings;

  /// Raw JSON from `_product.interactionSummaryHint`.
  final String interactionHint;

  /// `detailBlob['interaction_summary']` for dose-aware gating.
  final Map<String, dynamic>? interactionSummary;

  /// Ingredient-dose map for per-ingredient threshold gating.
  final Map<String, IngredientDose>? ingredientDoses;

  /// Result of `matchAllergens`.
  final List<MatchedAllergen> matchedAllergens;

  /// Result of `matchFreeFromClaims`.
  final List<FreeFromClaim> freeFromClaims;

  /// Result of `findFreeFromConflicts`.
  final List<String> freeFromConflicts;

  const ReviewBeforeUseSection({
    super.key,
    required this.warnings,
    required this.interactionHint,
    this.interactionSummary,
    this.ingredientDoses,
    this.matchedAllergens = const [],
    this.freeFromClaims = const [],
    this.freeFromConflicts = const [],
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final hasProfile =
        profile.conditions.isNotEmpty || profile.drugClasses.isNotEmpty;

    final parsedHint = parseInteractionHint(interactionHint);
    final hintHasAny = parsedHint?.hasAny == true;

    // Dose-aware condition gate — drops condition IDs whose ingredients
    // are all sub-clinical.
    final gatedSummary = gateInteractionSummary(
      interactionSummary,
      ingredientDoses: ingredientDoses,
    );
    final survivingConditionIds =
        (gatedSummary?['condition_summary'] as Map<String, dynamic>?)?.keys
            .toSet();
    final filteredHintConditionIds = parsedHint == null
        ? const <String>[]
        : (survivingConditionIds == null
              ? parsedHint.conditionIds
              : parsedHint.conditionIds
                    .where(survivingConditionIds.contains)
                    .toList(growable: false));
    final hintDrugClassIds = parsedHint?.drugClassIds ?? const <String>[];

    final matchedConditions = filteredHintConditionIds
        .where(profile.conditions.contains)
        .toList(growable: false);
    final matchedDrugClasses = hintDrugClassIds
        .where(profile.drugClasses.contains)
        .toList(growable: false);

    final hasInteractionContext =
        matchedConditions.isNotEmpty || matchedDrugClasses.isNotEmpty;
    final hasWarnings = warnings.isNotEmpty;
    final hasAllergens = matchedAllergens.isNotEmpty;

    // Free-from claims: filter `notClaimed` (absence of claim = no signal).
    final renderableClaims = freeFromClaims
        .where((c) => c.status != FreeFromStatus.notClaimed)
        .toList(growable: false);
    final hasFreeFromCertified = renderableClaims.any(
      (c) => c.status == FreeFromStatus.certified,
    );
    final hasFreeFromClaims = renderableClaims.isNotEmpty;
    final hasFreeFromConflicts = freeFromConflicts.isNotEmpty;

    // No profile + product has interactions → calm nudge mode.
    if (!hasProfile && hintHasAny && !hasWarnings && !hasAllergens) {
      return _NudgeBanner(
        onCompleteProfile: () =>
            GoRouter.of(context).push(Routes.profileSetup),
      );
    }

    // Nothing to surface — section hides.
    if (!hasWarnings &&
        !hasAllergens &&
        !hasInteractionContext &&
        !hasFreeFromClaims) {
      return const SizedBox.shrink();
    }

    final hasOnlyAffirmatives =
        !hasWarnings && !hasAllergens && !hasInteractionContext;

    final tone = computeReviewTone(
      warnings: warnings,
      allergens: matchedAllergens,
      hasOnlyAffirmatives: hasOnlyAffirmatives,
      hasFreeFromCertified: hasFreeFromCertified,
    );

    // Title + body copy — verbatim from production lines 277–306.
    final affirmativeCertifiedCount = hasOnlyAffirmatives
        ? renderableClaims
              .where((c) => c.status == FreeFromStatus.certified)
              .length
        : 0;
    final title = hasOnlyAffirmatives
        ? (affirmativeCertifiedCount > 0
              ? 'Allergen check passed'
              : 'Allergen check')
        : 'Review before use';

    final rowCount = warnings.length + matchedAllergens.length;
    String? body;
    if (rowCount > 0) {
      body = countCopy(rowCount);
    } else if (hasOnlyAffirmatives) {
      body = affirmativeCertifiedCount > 0
          ? affirmativeCopy(affirmativeCertifiedCount)
          : 'No verified free-from claims for your profile';
    }
    // Append context line under the body when relevant.
    final contextLine = buildInteractionContextLine(
      matchedConditions: matchedConditions,
      matchedDrugClasses: matchedDrugClasses,
    );
    if (contextLine != null) {
      body = body == null ? contextLine : '$body · $contextLine';
    }

    // Build rows: allergens first (concrete personal facts), warnings
    // sorted by severity desc, then free-from rows.
    final rows = <PGReviewRow>[];
    for (final m in matchedAllergens) {
      rows.add(rowForAllergen(m));
    }
    for (final w in sortWarningsBySeverity(warnings)) {
      rows.add(
        rowForWarning(
          w,
          onTapCitations: (urls) => _showCitationsSheet(context, urls),
        ),
      );
    }
    for (final c in renderableClaims) {
      rows.add(rowForFreeFromClaim(c));
    }

    final conflictBody = buildConflictFooterBody(freeFromConflicts);

    final card = PGReviewBeforeUseCard(
      tone: tone,
      title: title,
      body: body,
      rows: rows,
      // Auto-expand on danger OR on affirmatives so users see the
      // confirmation/warning without a tap (matches production line 181).
      startExpanded: tone == PGReviewTone.danger || hasOnlyAffirmatives,
    );

    if (hasFreeFromConflicts && conflictBody != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          card,
          const SizedBox(height: V2Spacing.space8),
          _ConflictFooter(body: conflictBody),
        ],
      );
    }
    return card;
  }
}

/// Calm "complete profile" nudge — renders when the user has no profile
/// data but the product has known interactions. Matches production's
/// `_NudgeBanner` (line 1043) but in v2 tones (no severity color — this
/// is informational, not a warning).
class _NudgeBanner extends StatelessWidget {
  final VoidCallback onCompleteProfile;

  const _NudgeBanner({required this.onCompleteProfile});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(V2Spacing.space16),
      decoration: BoxDecoration(
        color: V2Colors.surface,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        border: Border.all(color: V2Colors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.info_outline_rounded,
                size: 20,
                color: V2Colors.fgMuted,
              ),
              const SizedBox(width: V2Spacing.space12),
              Expanded(
                child: Text(
                  'This product has known interactions',
                  style: V2Typography.titleSm(color: V2Colors.fg),
                ),
              ),
            ],
          ),
          const SizedBox(height: V2Spacing.space8),
          Text(
            'Add your health conditions and medications to get warnings '
            'personalized to your profile.',
            style: V2Typography.bodySm(color: V2Colors.fgMuted),
          ),
          const SizedBox(height: V2Spacing.space12),
          Align(
            alignment: Alignment.centerLeft,
            child: PGPillButton(
              label: 'Complete profile',
              onPressed: onCompleteProfile,
              variant: PGPillVariant.secondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// "Label disagreement detected" footer — renders below the card when
/// findFreeFromConflicts returned non-empty. Matches production's
/// `_ConflictFooter` (line 666) but in v2 tones.
class _ConflictFooter extends StatelessWidget {
  final String body;

  const _ConflictFooter({required this.body});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(V2Spacing.space12),
      decoration: BoxDecoration(
        color: V2Colors.caution.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        border: Border.all(
          color: V2Colors.caution.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 18,
            color: V2Colors.caution,
          ),
          const SizedBox(width: V2Spacing.space8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Conflicting label evidence',
                  style: V2Typography.titleSm(color: V2Colors.caution),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: V2Typography.bodySm(color: V2Colors.fgMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Show the citations bottom sheet. Mirrors production's
/// `_showCitationsSheet` (line 997) — same modal, v2 typography.
void _showCitationsSheet(BuildContext context, List<String> sourceUrls) {
  PGModal.bottomSheet<void>(
    context: context,
    builder: (sheetContext) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          V2Spacing.space16,
          V2Spacing.space12,
          V2Spacing.space16,
          V2Spacing.space24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Citations',
              style: V2Typography.titleSm(color: V2Colors.fg),
            ),
            const SizedBox(height: V2Spacing.space12),
            for (final url in sourceUrls)
              Padding(
                padding: const EdgeInsets.only(bottom: V2Spacing.space8),
                child: InkWell(
                  onTap: () async {
                    final uri = Uri.tryParse(url);
                    if (uri != null) {
                      await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      );
                    }
                  },
                  child: Text(
                    url,
                    style: V2Typography.bodySm(color: V2Colors.accent)
                        .copyWith(decoration: TextDecoration.underline),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}
