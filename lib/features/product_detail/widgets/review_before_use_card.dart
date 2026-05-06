// "Review before use" card — replaces AlertSummaryCard + _ConditionAlertBanner.
//
// Sprint: docs/sprints/product_detail_page_sprint.md — T2A.
//
// Single unified surface for personalized risk:
//   - Profile-matched interaction warnings (was AlertSummaryCard)
//   - Profile-matched condition / drug-class context (was _ConditionAlertBanner)
//   - Personalized allergen rows (new — Phase 8 wired in)
//
// Tone is computed from the highest severity across all three inputs.
// Card auto-expands when tone == danger, collapses otherwise.
//
// When the user has no profile data BUT the product has interactions,
// the card renders a neutral nudge with a "Complete profile" CTA. No
// expandable body in that mode — there's nothing personal to expand to.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_card.dart';
import 'package:pharmaguide/core/widgets/pg_modal.dart';
import 'package:pharmaguide/core/widgets/pg_pressable.dart';
import 'package:pharmaguide/core/widgets/pg_severity_banner.dart';
import 'package:pharmaguide/features/product_detail/allergen_match.dart';
import 'package:pharmaguide/features/product_detail/widgets/interaction_warnings.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';
import 'package:pharmaguide/services/warnings/condition_gate.dart';

class ReviewBeforeUseCard extends ConsumerStatefulWidget {
  /// Profile-filtered interaction warnings (= guardedWarnings from the
  /// screen's filterProductDetailWarningsForProfile pass).
  final List<InteractionWarning> warnings;

  /// Raw JSON from `_product.interactionSummaryHint`. Drives the
  /// no-profile nudge mode and the per-condition context line.
  final String interactionHint;

  /// `detailBlob['interaction_summary']` — passed for dose-aware gating.
  /// Optional for back-compat.
  final Map<String, dynamic>? interactionSummary;

  /// Ingredient-dose map for per-ingredient threshold gating in
  /// [gateInteractionSummary]. Optional.
  final Map<String, IngredientDose>? ingredientDoses;

  /// Result of [matchAllergens] — exact-ID matches between profile
  /// allergens and the product's structured allergen list. Empty when
  /// either side is empty or the pipeline hasn't shipped the structured
  /// list for this product.
  final List<MatchedAllergen> matchedAllergens;

  const ReviewBeforeUseCard({
    super.key,
    required this.warnings,
    required this.interactionHint,
    this.interactionSummary,
    this.ingredientDoses,
    this.matchedAllergens = const [],
  });

  @override
  ConsumerState<ReviewBeforeUseCard> createState() =>
      _ReviewBeforeUseCardState();
}

class _ReviewBeforeUseCardState extends ConsumerState<ReviewBeforeUseCard> {
  bool? _expandedOverride;

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    final hasProfile =
        profile.conditions.isNotEmpty || profile.drugClasses.isNotEmpty;

    // Parse the hint once. Drives the no-profile nudge state.
    final parsedHint = _parseHint(widget.interactionHint);
    final hintHasAny = parsedHint?.hasAny == true;

    // Gate the summary so condition IDs whose ingredients are all
    // sub-clinical drop out — matches the per-condition cards below.
    final gatedSummary = gateInteractionSummary(
      widget.interactionSummary,
      ingredientDoses: widget.ingredientDoses,
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
    final hasWarnings = widget.warnings.isNotEmpty;
    final hasAllergens = widget.matchedAllergens.isNotEmpty;

    // No profile + product has interactions → neutral nudge mode.
    // (Allergens require a profile too, so allergens.isEmpty here.)
    if (!hasProfile && hintHasAny && !hasWarnings && !hasAllergens) {
      return _NudgeBanner(
        onCompleteProfile: () => GoRouter.of(context).push(Routes.profileSetup),
      );
    }

    // Nothing to show.
    if (!hasWarnings && !hasAllergens && !hasInteractionContext) {
      return const SizedBox.shrink();
    }

    // Compute card tone from highest severity across all three inputs.
    final tone = _computeTone(
      warnings: widget.warnings,
      allergens: widget.matchedAllergens,
    );

    final autoExpand = tone == PGBannerTone.danger;
    final expanded = _expandedOverride ?? autoExpand;
    final count = widget.warnings.length + widget.matchedAllergens.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.space20,
        0,
        AppTheme.space20,
        AppTheme.space12,
      ),
      child: PGCard(
        variant: PGCardVariant.plain,
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(
              tone: tone,
              count: count,
              expanded: expanded,
              canExpand: hasWarnings || hasAllergens,
              onTap: () => setState(() => _expandedOverride = !expanded),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              child: expanded
                  ? _ExpandedBody(
                      warnings: widget.warnings,
                      matchedAllergens: widget.matchedAllergens,
                      matchedConditions: matchedConditions,
                      matchedDrugClasses: matchedDrugClasses,
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header (tappable)
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  final PGBannerTone tone;
  final int count;
  final bool expanded;
  final bool canExpand;
  final VoidCallback onTap;

  const _Header({
    required this.tone,
    required this.count,
    required this.expanded,
    required this.canExpand,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final iconColor = _toneColor(tone);

    final body = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.space16,
        vertical: AppTheme.space12,
      ),
      child: Row(
        children: [
          Icon(_toneIcon(tone), size: 20, color: iconColor),
          const SizedBox(width: AppTheme.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Review before use',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                    letterSpacing: -0.1,
                  ),
                ),
                if (count > 0) ...[
                  const SizedBox(height: 2),
                  Text(
                    _countCopy(count),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (canExpand) ...[
            const SizedBox(width: AppTheme.space8),
            AnimatedRotation(
              turns: expanded ? 0.5 : 0,
              duration: const Duration(milliseconds: 180),
              child: Icon(
                Icons.expand_more_rounded,
                size: 20,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );

    if (!canExpand) return body;
    return PGPressable(onTap: onTap, pressedScale: 0.98, child: body);
  }

  static String _countCopy(int count) {
    if (count == 1) return '1 thing to review before use';
    return '$count things to review before use';
  }
}

// ---------------------------------------------------------------------------
// Expanded body
// ---------------------------------------------------------------------------

class _ExpandedBody extends StatelessWidget {
  final List<InteractionWarning> warnings;
  final List<MatchedAllergen> matchedAllergens;
  final List<String> matchedConditions;
  final List<String> matchedDrugClasses;

  const _ExpandedBody({
    required this.warnings,
    required this.matchedAllergens,
    required this.matchedConditions,
    required this.matchedDrugClasses,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final hasContextLine =
        matchedConditions.isNotEmpty || matchedDrugClasses.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.space16,
        0,
        AppTheme.space16,
        AppTheme.space12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(
            height: 1,
            thickness: 0.6,
            color: scheme.outlineVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: AppTheme.space12),
          // Allergen rows first — they're concrete personal facts.
          for (final m in matchedAllergens) _AllergenRow(match: m),
          // Condition / drug-class match context line.
          if (hasContextLine) ...[
            if (matchedAllergens.isNotEmpty)
              const SizedBox(height: AppTheme.space8),
            _ContextLine(
              matchedConditions: matchedConditions,
              matchedDrugClasses: matchedDrugClasses,
            ),
            if (warnings.isNotEmpty) const SizedBox(height: AppTheme.space12),
          ] else if (matchedAllergens.isNotEmpty && warnings.isNotEmpty) ...[
            const SizedBox(height: AppTheme.space8),
          ],
          // Alert rows — sorted by severity desc.
          for (final w in _sortedBySeverity(warnings)) _AlertRow(warning: w),
        ],
      ),
    );
  }

  static List<InteractionWarning> _sortedBySeverity(
    List<InteractionWarning> input,
  ) {
    final sorted = List<InteractionWarning>.from(input);
    sorted.sort((a, b) => b.severity.weight.compareTo(a.severity.weight));
    return sorted;
  }
}

// ---------------------------------------------------------------------------
// Sub-rows
// ---------------------------------------------------------------------------

class _AllergenRow extends StatelessWidget {
  final MatchedAllergen match;

  const _AllergenRow({required this.match});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tone = _allergenTone(match.presenceType);
    final color = _toneColor(tone);

    String tagLabel;
    String body;
    switch (match.presenceType) {
      case 'contains':
        tagLabel = 'Contains';
        body = '${match.displayName} is listed in your allergy profile.';
        break;
      case 'may_contain':
        tagLabel = 'May contain';
        body = 'This product includes a precautionary allergen statement.';
        break;
      case 'manufactured_in_facility':
        tagLabel = 'Facility';
        body = 'May matter for highly sensitive users.';
        break;
      default:
        tagLabel = 'Allergen';
        body = match.displayName;
    }

    final isSevereContains =
        match.presenceType == 'contains' && match.severityLevel == 'high';

    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.space12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  tagLabel,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: color,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: AppTheme.space8),
              Expanded(
                child: Text(
                  match.displayName,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (isSevereContains) ...[
                const SizedBox(width: AppTheme.space8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.severityContraindicated.withValues(
                      alpha: 0.12,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'severe',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.severityContraindicated,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
          if (match.evidence != null && match.evidence!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              match.evidence!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ContextLine extends StatelessWidget {
  final List<String> matchedConditions;
  final List<String> matchedDrugClasses;

  const _ContextLine({
    required this.matchedConditions,
    required this.matchedDrugClasses,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final lines = <String>[];
    if (matchedConditions.isNotEmpty) {
      lines.add(
        'Your conditions: ${matchedConditions.map(_humanLabel).join(', ')}',
      );
    }
    if (matchedDrugClasses.isNotEmpty) {
      lines.add(
        'Your medications: ${matchedDrugClasses.map(_humanLabel).join(', ')}',
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.space12,
        vertical: AppTheme.space8,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in lines)
            Padding(
              padding: EdgeInsets.only(top: line == lines.first ? 0 : 2),
              child: Text(
                line,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Single profile-matched warning row.
///
/// Renders severity pill + title + mechanism + management, plus
/// (when present) an evidence chip and a tappable citations chip
/// that opens a bottom sheet listing source URLs. Lifted from
/// `WithYourStackSection._ExpandedDetail` 2026-05-05 when that
/// section was retired into this card.
class _AlertRow extends StatelessWidget {
  final InteractionWarning warning;

  const _AlertRow({required this.warning});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = _severityColor(warning.severity);
    final hasCitations = warning.sourceUrls.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.space12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  warning.severity.label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: color,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: AppTheme.space8),
              Expanded(
                child: Text(
                  warning.title,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (warning.mechanism.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              warning.mechanism,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ],
          if (warning.management.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              warning.management,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
                height: 1.35,
              ),
            ),
          ],
          // Evidence + citations chips. Both surfaces lifted from the
          // retired WithYourStackSection so users still have one tap
          // to source URLs.
          const SizedBox(height: AppTheme.space8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _EvidenceChip(level: warning.evidenceLevel),
              if (hasCitations)
                _CitationsChip(
                  count: warning.sourceUrls.length,
                  onTap: () => _showCitationsSheet(context, warning.sourceUrls),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Color _severityColor(Severity severity) {
    switch (severity) {
      case Severity.contraindicated:
      case Severity.avoid:
        return AppTheme.severityContraindicated;
      case Severity.caution:
        return AppTheme.severityCaution;
      case Severity.monitor:
        return AppTheme.severityMonitor;
      case Severity.informational:
      case Severity.safe:
        return AppTheme.severityCaution;
    }
  }
}

class _EvidenceChip extends StatelessWidget {
  final EvidenceLevel level;

  const _EvidenceChip({required this.level});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppTheme.radiusFull),
      ),
      child: Text(
        level.label,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _CitationsChip extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _CitationsChip({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusFull),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppTheme.radiusFull),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.menu_book_outlined,
              size: 13,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Text(
              '$count citation${count == 1 ? '' : 's'}',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void _showCitationsSheet(BuildContext context, List<String> sourceUrls) {
  PGModal.bottomSheet<void>(
    context: context,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          AppTheme.space20,
          AppTheme.space12,
          AppTheme.space20,
          AppTheme.space24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Citations',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: AppTheme.space12),
            for (final url in sourceUrls)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  url,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

// ---------------------------------------------------------------------------
// No-profile nudge mode
// ---------------------------------------------------------------------------

class _NudgeBanner extends StatelessWidget {
  final VoidCallback onCompleteProfile;

  const _NudgeBanner({required this.onCompleteProfile});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.space20,
        AppTheme.space8,
        AppTheme.space20,
        AppTheme.space12,
      ),
      child: PGSeverityBanner(
        tone: PGBannerTone.neutral,
        title: 'This product has known interactions',
        body:
            'Add your health conditions and medications to get warnings '
            'personalized to your profile.',
        actionLabel: 'Complete profile',
        onAction: onCompleteProfile,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tone / severity helpers
// ---------------------------------------------------------------------------

PGBannerTone _computeTone({
  required List<InteractionWarning> warnings,
  required List<MatchedAllergen> allergens,
}) {
  // Walk warnings for highest severity.
  var hasDanger = false;
  var hasCaution = false;
  var hasInfo = false;
  for (final w in warnings) {
    switch (w.severity) {
      case Severity.contraindicated:
      case Severity.avoid:
        hasDanger = true;
        break;
      case Severity.caution:
        hasCaution = true;
        break;
      case Severity.monitor:
      case Severity.informational:
      case Severity.safe:
        hasInfo = true;
        break;
    }
  }
  // Allergen presence.
  for (final m in allergens) {
    switch (m.presenceType) {
      case 'contains':
        hasDanger = true;
        break;
      case 'may_contain':
        hasCaution = true;
        break;
      case 'manufactured_in_facility':
        hasInfo = true;
        break;
    }
  }
  if (hasDanger) return PGBannerTone.danger;
  if (hasCaution) return PGBannerTone.caution;
  if (hasInfo) return PGBannerTone.info;
  return PGBannerTone.info;
}

PGBannerTone _allergenTone(String presenceType) {
  switch (presenceType) {
    case 'contains':
      return PGBannerTone.danger;
    case 'may_contain':
      return PGBannerTone.caution;
    case 'manufactured_in_facility':
      return PGBannerTone.info;
    default:
      return PGBannerTone.caution;
  }
}

Color _toneColor(PGBannerTone tone) {
  switch (tone) {
    case PGBannerTone.danger:
      return AppTheme.severityContraindicated;
    case PGBannerTone.caution:
      return AppTheme.severityCaution;
    case PGBannerTone.info:
      return AppTheme.info;
    case PGBannerTone.success:
      return AppTheme.severitySafe;
    case PGBannerTone.neutral:
      return AppTheme.insufficientData;
  }
}

IconData _toneIcon(PGBannerTone tone) {
  switch (tone) {
    case PGBannerTone.danger:
      return Icons.error_outline_rounded;
    case PGBannerTone.caution:
      return Icons.warning_amber_rounded;
    case PGBannerTone.info:
      return Icons.info_outline_rounded;
    case PGBannerTone.success:
      return Icons.check_circle_outline_rounded;
    case PGBannerTone.neutral:
      return Icons.help_outline_rounded;
  }
}

// ---------------------------------------------------------------------------
// Hint parsing (lifted from _ConditionAlertBanner)
// ---------------------------------------------------------------------------

class _ParsedHint {
  final bool hasAny;
  final List<String> conditionIds;
  final List<String> drugClassIds;

  _ParsedHint({
    required this.hasAny,
    required this.conditionIds,
    required this.drugClassIds,
  });
}

_ParsedHint? _parseHint(String raw) {
  if (raw.isEmpty) return null;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    final map = Map<String, dynamic>.from(decoded);
    return _ParsedHint(
      hasAny: map['has_any'] == true,
      conditionIds: _listOfStrings(map['condition_ids']),
      drugClassIds: _listOfStrings(map['drug_class_ids']),
    );
  } on FormatException {
    return null;
  }
}

List<String> _listOfStrings(Object? raw) {
  if (raw is List) {
    return raw.map((e) => e.toString()).toList(growable: false);
  }
  return const [];
}

/// snake_case → human label, with overrides for medical acronyms.
String _humanLabel(String id) {
  const overrides = {
    'ttc': 'Trying to conceive',
    'nsaids': 'NSAIDs',
    'ssris': 'SSRIs',
    'snris': 'SNRIs',
    'maois': 'MAOIs',
    'gi_disorders': 'GI disorders',
    'gerd': 'GERD',
    'ibs': 'IBS',
    'ibd': 'IBD',
    'copd': 'COPD',
    'pcos': 'PCOS',
    'adhd': 'ADHD',
    'hiv_aids': 'HIV/AIDS',
  };
  final lower = id.toLowerCase();
  if (overrides.containsKey(lower)) return overrides[lower]!;
  return lower
      .split('_')
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');
}
