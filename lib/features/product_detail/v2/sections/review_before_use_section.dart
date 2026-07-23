// Profile Relevance section adapter.
//
// Composes one personalized surface from the same data paths that used to
// render separately as PersonalFit and ReviewBeforeUse:
//
//   fitScoreForProductProvider(dsldId) -> FitScoreResult
//   guardedWarnings                    -> profile-filtered warnings only
//   matchAllergens(profile.allergens)  -> profile-matched allergens only
//   matchFreeFromClaims(...)           -> user-relevant free-from flags
//
// The rule is intentionally strict: this section never reads raw product
// allergens or raw warnings. If something is not relevant to the current
// profile, it does not appear here.

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_for_you_extras.dart';
import 'package:pharmaguide/core/components/pg_pill_button.dart';
import 'package:pharmaguide/core/components/pg_review_before_use_card.dart';
import 'package:pharmaguide/core/models/fit_score_result.dart';
import 'package:pharmaguide/core/scoring/coverage.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/widgets/pg_modal.dart';
import 'package:pharmaguide/features/product_detail/allergen_match.dart';
import 'package:pharmaguide/features/product_detail/free_from_match.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/personal_fit_helpers.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/review_before_use_helpers.dart';
import 'package:pharmaguide/features/product_detail/v2/warnings_pipeline.dart';
import 'package:pharmaguide/services/fit_score/fit_display.dart';
import 'package:pharmaguide/services/warnings/interaction_warning.dart';
import 'package:url_launcher/url_launcher.dart';

enum ProfileRelevanceStatus {
  strongMatch,
  goodMatch,
  neutral,
  coverageLimited,
  review,
  notRecommended,
  incomplete,
}

class ProfileRelevanceSummary {
  final ProfileRelevanceStatus status;
  final PGReviewTone tone;
  final String headline;
  final String? body;
  final List<PGReviewRow> rows;
  final List<String> whyThisFitsReasons;
  final bool profileIncomplete;
  final bool needsGoals;
  final bool startExpanded;

  const ProfileRelevanceSummary({
    required this.status,
    required this.tone,
    required this.headline,
    this.body,
    this.rows = const [],
    this.whyThisFitsReasons = const [],
    this.profileIncomplete = false,
    this.needsGoals = false,
    this.startExpanded = false,
  });

  /// A defensive low-coverage state remains silent in consumer UI. Catalog
  /// completeness is enforced by the release gate, not explained here.
  bool get shouldRender => status != ProfileRelevanceStatus.coverageLimited;
}

ProfileRelevanceSummary buildProfileRelevanceSummary({
  required FitScoreResult? fitResult,
  required String? topGoalLabel,
  required List<InteractionWarning> warnings,
  required String interactionHint,
  required List<MatchedAllergen> matchedAllergens,
  required List<String> freeFromConflicts,
  required bool hasInteractionProfile,
  bool hasProfileInformation = true,
  List<String> selectedGoalLabels = const [],
  // True when a substance-level `display_mode_default == 'critical'` note
  // (moderate harmful additive, high-risk ingredient) exists for this product
  // but lives in the calm general "Good to know" bucket rather than the
  // profile card. Such notes carry `caution` severity — hard (avoid /
  // contraindicated) criticals are already routed to the profile bucket and
  // caught by [hasHardWarning]. We deliberately keep the ROW calm and out of
  // "Review for your profile" (the pipeline flags ~33 ubiquitous additives —
  // sucralose, Red 40, polysorbate 80 — this way), but the verdict headline
  // must NOT render a green "safe" all-clear over a flagged substance hazard.
  bool hasCriticalGlobalNote = false,
  void Function(List<String> sourceUrls)? onTapCitations,
}) {
  final allergenRows = rowsForAllergens(matchedAllergens);

  final rows = <PGReviewRow>[];
  rows.addAll(allergenRows);
  for (final warning in sortWarningsBySeverity(warnings)) {
    rows.add(rowForWarning(warning, onTapCitations: onTapCitations));
  }

  final conflictBody = buildConflictFooterBody(freeFromConflicts);
  if (conflictBody != null) {
    rows.add(
      PGReviewRow(
        headline: 'Conflicting label evidence',
        caption: conflictBody,
        rowTone: PGReviewTone.caution,
      ),
    );
  }

  final hasContainsAllergen = matchedAllergens.any(
    (m) => m.presenceType == 'contains',
  );
  final hasMayContainAllergen = matchedAllergens.any(
    (m) => m.presenceType == 'may_contain',
  );
  final hasHardWarning = warnings.any(_isHardWarning);
  final hasReviewWarning = warnings.any(_isReviewWarning);
  final hasFreeFromConflict = freeFromConflicts.isNotEmpty;
  final reviewItemCount =
      allergenRows.length + warnings.length + (hasFreeFromConflict ? 1 : 0);
  final fitDisplay = fitResult == null
      ? const FitIncomplete()
      : computeFitDisplay(
          verdict: worstSeverityOf(warnings),
          fitResult: fitResult,
        );
  final profileIncomplete = !hasProfileInformation;

  if (hasContainsAllergen || hasHardWarning) {
    return ProfileRelevanceSummary(
      status: ProfileRelevanceStatus.notRecommended,
      tone: PGReviewTone.danger,
      headline: 'Not recommended for your profile',
      body: _notRecommendedBody(
        warnings: warnings.where(_isHardWarning).toList(growable: false),
        hasContainsAllergen: hasContainsAllergen,
      ),
      rows: rows,
      profileIncomplete: profileIncomplete,
      startExpanded: rows.isNotEmpty,
    );
  }

  if (hasMayContainAllergen || hasReviewWarning || hasFreeFromConflict) {
    final concern = _primaryConcernBody(
      warnings: warnings.where(_isReviewWarning).toList(growable: false),
      matchedAllergens: matchedAllergens,
      hasFreeFromConflict: hasFreeFromConflict,
    );
    final goalContext = _goalPriorityCopy(topGoalLabel);
    return ProfileRelevanceSummary(
      status: ProfileRelevanceStatus.review,
      tone: PGReviewTone.caution,
      headline: 'Review before use',
      body: [
        concern ?? (reviewItemCount > 0 ? countCopy(reviewItemCount) : null),
        goalContext,
      ].whereType<String>().join(' '),
      rows: rows,
      profileIncomplete: profileIncomplete,
      startExpanded: rows.isNotEmpty,
    );
  }

  if (!hasProfileInformation) {
    return ProfileRelevanceSummary(
      status: ProfileRelevanceStatus.incomplete,
      tone: PGReviewTone.info,
      headline: 'Check this product for you',
      body: _incompleteBody(
        interactionHint: interactionHint,
        hasInteractionProfile: hasInteractionProfile,
      ),
      rows: rows,
      profileIncomplete: true,
      startExpanded: _shouldExpandInformationalRows(rows),
    );
  }

  // Consumer catalog rows must pass the release completeness gate. Keep this
  // defensive branch silent rather than exposing backend coverage language or
  // claiming a profile all-clear from an invalid record.
  if (isLowCoverage(fitResult?.mappedCoverage)) {
    return const ProfileRelevanceSummary(
      status: ProfileRelevanceStatus.coverageLimited,
      tone: PGReviewTone.info,
      headline: 'Profile assessment unavailable',
    );
  }

  return switch (fitDisplay) {
    FitStrongMatch() => _cleanProfileSummary(
      status: ProfileRelevanceStatus.strongMatch,
      tone: hasCriticalGlobalNote ? PGReviewTone.info : PGReviewTone.safe,
      topGoalLabel: topGoalLabel,
      selectedGoalLabels: selectedGoalLabels,
      fitReasons: fitResult?.reasons ?? const [],
      rows: rows,
    ),
    FitGoodMatch() => _cleanProfileSummary(
      status: ProfileRelevanceStatus.goodMatch,
      tone: hasCriticalGlobalNote ? PGReviewTone.info : PGReviewTone.safe,
      topGoalLabel: topGoalLabel,
      selectedGoalLabels: selectedGoalLabels,
      fitReasons: fitResult?.reasons ?? const [],
      rows: rows,
    ),
    FitLimitedFit() || FitNotRecommended() => _cleanProfileSummary(
      status: ProfileRelevanceStatus.neutral,
      tone: hasCriticalGlobalNote ? PGReviewTone.info : PGReviewTone.safe,
      topGoalLabel: null,
      selectedGoalLabels: selectedGoalLabels,
      fitReasons: const [],
      rows: rows,
    ),
    FitHidden() => ProfileRelevanceSummary(
      status: ProfileRelevanceStatus.notRecommended,
      tone: PGReviewTone.danger,
      headline: 'Not recommended for your profile',
      body: _notRecommendedBody(
        warnings: warnings.where(_isHardWarning).toList(growable: false),
        hasContainsAllergen: hasContainsAllergen,
      ),
      rows: rows,
      profileIncomplete: profileIncomplete,
      startExpanded: rows.isNotEmpty,
    ),
    FitIncomplete() => ProfileRelevanceSummary(
      status: ProfileRelevanceStatus.neutral,
      tone: hasCriticalGlobalNote ? PGReviewTone.info : PGReviewTone.safe,
      headline: 'No profile-specific concerns found',
      body: _cleanProfileBody(
        topGoalLabel: null,
        selectedGoalLabels: selectedGoalLabels,
      ),
      rows: rows,
      needsGoals: selectedGoalLabels.isEmpty,
      startExpanded: _shouldExpandInformationalRows(rows),
    ),
  };
}

/// Independent allergen alert for BLOCKED products. A blocked verdict hides
/// the full ProfileRelevance card (`shouldShowProfileRelevance == !isBlocked`),
/// but an allergen match is an independent safety signal that must still
/// surface — a "contains peanut" match matters regardless of WHY the product
/// is blocked. Returns null when there are no matched allergens; otherwise a
/// summary carrying ONLY the allergen rows (the rest of profile relevance
/// stays with the hidden full card, no duplication since the two are
/// mutually exclusive on the blocked/not-blocked axis).
ProfileRelevanceSummary? buildBlockedAllergenAlertSummary(
  List<MatchedAllergen> matchedAllergens,
) {
  final rows = rowsForAllergens(matchedAllergens);
  if (rows.isEmpty) return null;
  final hasContains = matchedAllergens.any((m) => m.presenceType == 'contains');
  return ProfileRelevanceSummary(
    status: hasContains
        ? ProfileRelevanceStatus.notRecommended
        : ProfileRelevanceStatus.review,
    tone: hasContains ? PGReviewTone.danger : PGReviewTone.caution,
    headline: hasContains
        ? 'Contains an allergen in your profile'
        : 'May contain an allergen in your profile',
    rows: rows,
    startExpanded: true,
  );
}

class ProfileRelevanceSection extends StatelessWidget {
  final ProfileRelevanceSummary summary;
  final VoidCallback onCompleteProfile;

  const ProfileRelevanceSection({
    super.key,
    required this.summary,
    required this.onCompleteProfile,
  });

  @override
  Widget build(BuildContext context) {
    if (!summary.shouldRender) {
      return const SizedBox.shrink();
    }

    final actionLabel = summary.profileIncomplete
        ? 'Add profile information'
        : summary.needsGoals
        ? 'Add goals'
        : 'Edit profile';
    final hasReasons = summary.whyThisFitsReasons.isNotEmpty;

    return PGReviewBeforeUseCard(
      eyebrow: 'For You',
      tone: summary.tone,
      title: summary.headline,
      body: summary.body,
      rows: summary.rows,
      startExpanded: summary.startExpanded,
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasReasons) ...[
            PGWhyThisFitsExpander(reasons: summary.whyThisFitsReasons),
            const SizedBox(height: V2Spacing.space12),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: PGPillButton(
              label: actionLabel,
              icon: Icons.edit_outlined,
              onPressed: onCompleteProfile,
              variant: PGPillVariant.ghost,
            ),
          ),
        ],
      ),
    );
  }
}

/// Material global safety notes from the [partitionProfileWarnings] general
/// bucket. Neutral education, benefits, and unmatched FYIs do not become
/// warning cards; only actionable rows explicitly marked critical remain.
Widget? buildGeneralNotesSection({
  required List<InteractionWarning> warnings,
  List<FreeFromClaim> freeFromClaims = const [],
  void Function(List<String> sourceUrls)? onTapCitations,
}) {
  final materialWarnings = warnings
      .where((warning) {
        return warning.severity.isActionable &&
            isCriticalDisplayMode(warning.displayModeDefault);
      })
      .toList(growable: false);
  final profileNotes = warnings
      .where(
        (warning) =>
            !materialWarnings.contains(warning) && isCalmProfileNote(warning),
      )
      .toList(growable: false);
  final reassuringClaims = freeFromClaims
      .where((claim) => claim.status == FreeFromStatus.certified)
      .toList(growable: false);
  if (materialWarnings.isEmpty &&
      profileNotes.isEmpty &&
      reassuringClaims.isEmpty) {
    return null;
  }

  final sections = <Widget>[];
  if (profileNotes.isNotEmpty || reassuringClaims.isNotEmpty) {
    sections.add(
      PGReviewBeforeUseCard(
        eyebrow: 'Good to know',
        tone: PGReviewTone.info,
        title: 'Information for your profile',
        rows: [
          for (final warning in sortWarningsBySeverity(profileNotes))
            _rowForProfileNote(warning, onTapCitations: onTapCitations),
          for (final claim in reassuringClaims) rowForFreeFromClaim(claim),
        ],
      ),
    );
  }

  final materialRows = [
    for (final w in sortWarningsBySeverity(materialWarnings))
      rowForWarning(w, onTapCitations: onTapCitations),
  ];
  if (materialRows.isNotEmpty) {
    final count = materialRows.length;
    if (sections.isNotEmpty) {
      sections.add(const SizedBox(height: V2Spacing.space12));
    }
    sections.add(
      PGReviewBeforeUseCard(
        eyebrow: 'Product safety',
        tone: PGReviewTone.caution,
        title: 'Review this product',
        body: count == 1
            ? '1 material safety note'
            : '$count material safety notes',
        rows: materialRows,
      ),
    );
  }
  return sections.length == 1 ? sections.single : Column(children: sections);
}

PGReviewRow _rowForProfileNote(
  InteractionWarning warning, {
  void Function(List<String> sourceUrls)? onTapCitations,
}) {
  final captionParts = <String>[];
  final body = warning.displayBody.trim();
  if (body.isNotEmpty) captionParts.add(body);
  captionParts.add(warning.evidenceLevel.label);
  final citationCount = warning.sourceUrls.length;
  if (citationCount > 0) {
    captionParts.add('$citationCount citation${citationCount == 1 ? '' : 's'}');
  }
  return PGReviewRow(
    headline: warning.displayHeadline,
    caption: captionParts.join(' · '),
    rowTone: PGReviewTone.info,
    onTap: citationCount > 0 && onTapCitations != null
        ? () => onTapCitations(warning.sourceUrls)
        : null,
  );
}

ProfileRelevanceSummary _cleanProfileSummary({
  required ProfileRelevanceStatus status,
  required PGReviewTone tone,
  required String? topGoalLabel,
  required List<String> selectedGoalLabels,
  required List<String> fitReasons,
  required List<PGReviewRow> rows,
}) {
  return ProfileRelevanceSummary(
    status: status,
    tone: tone,
    headline: 'No profile-specific concerns found',
    body: _cleanProfileBody(
      topGoalLabel: topGoalLabel,
      selectedGoalLabels: selectedGoalLabels,
    ),
    rows: rows,
    whyThisFitsReasons: _cleanWhyThisFitsReasons(fitReasons),
    needsGoals: selectedGoalLabels.isEmpty,
    startExpanded: _shouldExpandInformationalRows(rows),
  );
}

bool _isHardWarning(InteractionWarning warning) => warning.severity.isHard;

bool _isReviewWarning(InteractionWarning warning) =>
    warning.severity.isActionable;

bool _shouldExpandInformationalRows(List<PGReviewRow> rows) {
  if (rows.isEmpty) return false;
  return rows.every((row) {
    final tone = row.rowTone;
    return tone == PGReviewTone.safe || tone == PGReviewTone.info;
  });
}

String _cleanProfileBody({
  required String? topGoalLabel,
  required List<String> selectedGoalLabels,
}) {
  const scope = 'Based on the profile information you’ve shared.';
  final goal = topGoalLabel?.trim();
  if (goal != null && goal.isNotEmpty) {
    return '$scope\nMatches your goal: $goal.';
  }
  if (selectedGoalLabels.isNotEmpty) {
    return '$scope\nNo specific match found for your selected goals.';
  }
  return '$scope\nAdd goals to see whether this product matches what you '
      'want to improve.';
}

String? _goalPriorityCopy(String? topGoalLabel) {
  final goal = topGoalLabel?.trim();
  if (goal == null || goal.isEmpty) return null;
  return 'This product matches your $goal goal, but the concern takes priority.';
}

String? _primaryConcernBody({
  required List<InteractionWarning> warnings,
  required List<MatchedAllergen> matchedAllergens,
  required bool hasFreeFromConflict,
}) {
  final allergen = matchedAllergens.isEmpty ? null : matchedAllergens.first;
  if (allergen != null) {
    final verb = allergen.presenceType == 'contains'
        ? 'Contains'
        : 'May contain';
    return '$verb ${allergen.displayName}, which is in your allergy profile.';
  }
  final warning = warnings.isEmpty ? null : warnings.first;
  if (warning != null && warning.displayHeadline.trim().isNotEmpty) {
    return _withPeriod(warning.displayHeadline);
  }
  if (hasFreeFromConflict) {
    return 'The label contains conflicting claim information.';
  }
  return null;
}

List<String> _cleanWhyThisFitsReasons(List<String> reasons) {
  return reasons
      .map(cleanFitReason)
      .where((reason) => reason.isNotEmpty)
      .take(4)
      .toList(growable: false);
}

String _withPeriod(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return trimmed;
  if (trimmed.endsWith('.') || trimmed.endsWith('!') || trimmed.endsWith('?')) {
    return trimmed;
  }
  return '$trimmed.';
}

String _notRecommendedBody({
  required List<InteractionWarning> warnings,
  required bool hasContainsAllergen,
}) {
  var factors = 0;
  if (hasContainsAllergen) factors++;
  final hasMedicationConflict = warnings.any((w) => w.drugClassIds.isNotEmpty);
  final hasConditionConflict = warnings.any((w) => w.conditionIds.isNotEmpty);
  if (hasMedicationConflict) factors++;
  if (hasConditionConflict) factors++;

  if (factors > 1) return 'Multiple profile factors need attention.';
  if (hasContainsAllergen) return 'Contains an allergen in your profile.';
  if (hasMedicationConflict) return 'Conflicts with your medication profile.';
  if (hasConditionConflict) return 'Conflicts with your health profile.';
  return 'This product has a profile-specific warning.';
}

String _incompleteBody({
  required String interactionHint,
  required bool hasInteractionProfile,
}) {
  final parsedHint = parseInteractionHint(interactionHint);
  if (!hasInteractionProfile && parsedHint?.hasAny == true) {
    return 'Add your medications, conditions, and allergies to check known '
        'interactions for your profile.';
  }
  return 'Add your medications, conditions, allergies, and relevant life-stage '
      'information to run a personalized check.';
}

/// Show the citations bottom sheet. Mirrors production's citation modal,
/// but is kept public so the connected screen can build one centralized
/// ProfileRelevanceSummary without a second warning-rendering path.
void showProfileRelevanceCitationsSheet(
  BuildContext context,
  List<String> sourceUrls,
) {
  PGModal.bottomSheet<void>(
    context: context,
    builder: (sheetContext) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Citations',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: V2Colors.fg),
            ),
            const SizedBox(height: 12),
            for (final url in sourceUrls)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
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
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: V2Colors.accent,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}
