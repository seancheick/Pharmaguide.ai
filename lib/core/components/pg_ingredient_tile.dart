import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_ingredient_data.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/features/product_detail/widgets/ingredient_explain_model.dart';

/// v2 mirror of `_IngredientTile` in
///
///
/// **Label-truth structure:**
/// - Row 1: name (Geist Sans 500, ellipsis) + dose label right
///   (Geist Mono for tabular figures)
/// - Optional parenthetical component amount and exact form text
/// - Chips Wrap (spacing 6, runSpacing 4):
///   - explicit non-quality form states (`Form not disclosed`,
///     `Form listed · not yet assessed`, or `Data needs review`)
///   - `_FormChip` only for an explicitly assessed form
///   - `_DoseChip` when `doseCallOut != withinLimits` — High dose /
///     Low dose / Dose not disclosed (High is the only red — real safety)
///   - `_MiniChip` 'Safety concern' when `isSafetyConcern` (red, error tone)
///   - `_MiniChip` 'Inferred from label' when `isInferredFromLabel`
/// - Bottom hairline divider (0.5pt outlineVariant). Final row skips it.
/// - Source hierarchy is visible as indentation and announced with scoring
///   participation through one row-level Semantics node.
/// - Tap anywhere → `onTap` (parent opens the explain sheet — production
///   delegates to `showIngredientExplainSheet`)
///
/// **What changes in v2:**
/// - Typography: name uses Geist Sans 500 (production used bodyMedium w600)
/// - Dose uses V2Typography.monoData for tabular figures
/// - Chip text uses 500 weight not 700 (v2 weight discipline)
/// - Color tokens use v2 severity colors with the same meaning as the
///   production mappings.
class PGActiveIngredientTile extends StatelessWidget {
  final PGActiveIngredient ingredient;

  /// Whether to render the bottom hairline divider. The composing
  /// [PGIngredientsCard] passes false for the last row so the list ends
  /// flush with the card padding.
  final bool showBottomDivider;

  /// Tap handler — production opens `showIngredientExplainSheet`.
  final VoidCallback? onTap;

  /// Whether this tile should express source depth with left padding. Set to
  /// false when the parent already renders a hierarchy connector.
  final bool showNestedIndent;

  const PGActiveIngredientTile({
    super.key,
    required this.ingredient,
    this.showBottomDivider = true,
    this.onTap,
    this.showNestedIndent = true,
  });

  @override
  Widget build(BuildContext context) {
    final i = ingredient;
    final needsReview = i.identityNeedsReview;
    final formState = needsReview
        ? PGIngredientFormDisplayState.needsReview
        : i.formDisplayState;
    final dataNeedsReview =
        formState == PGIngredientFormDisplayState.needsReview;
    final suppressClaims = needsReview || dataNeedsReview;
    final isAssessed = formState == PGIngredientFormDisplayState.assessed;
    final formStatusLabel = formState.statusLabel;
    // Unresolved identity: the row shows only its literal label and the shared
    // Data-needs-review state — every quality/dose/safety claim is hidden even
    // if a stale typed model still carries one (defense-in-depth).
    final showChips =
        formStatusLabel != null ||
        (!suppressClaims &&
            ((isAssessed && i.formQuality != FormQuality.unknown) ||
                i.doseCallOut != DoseCallOut.withinLimits ||
                i.isSafetyConcern ||
                i.isInferredFromLabel));
    final hasDose = !suppressClaims && i.dose != null && i.dose!.isNotEmpty;
    final hasParentheticalDose =
        !suppressClaims &&
        i.parentheticalDoseText != null &&
        i.parentheticalDoseText!.trim().isNotEmpty;
    final hasForm =
        !suppressClaims &&
        (isAssessed ||
            formState == PGIngredientFormDisplayState.listedNotAssessed) &&
        i.formLabel != null &&
        i.formLabel!.isNotEmpty;
    final semanticsLabel = _semanticsLabel(
      ingredient: i,
      hasDose: hasDose,
      hasParentheticalDose: hasParentheticalDose,
      hasForm: hasForm,
      formState: formState,
      suppressClaims: suppressClaims,
    );
    final nestedDepth = i.nestedDepth < 0 ? 0 : i.nestedDepth;

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.only(
            left: showNestedIndent ? nestedDepth * V2Spacing.space16 : 0,
          ),
          child: Semantics(
            container: true,
            label: semanticsLabel,
            button: onTap != null,
            onTap: onTap,
            excludeSemantics: true,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: V2Spacing.space8,
                      horizontal: V2Spacing.space4,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Expanded(
                              child: Text(
                                i.name,
                                style: V2Typography.bodyMedium(
                                  color: V2Colors.fg,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (hasDose)
                              Padding(
                                padding: const EdgeInsets.only(
                                  left: V2Spacing.space8,
                                ),
                                child: Text(
                                  i.dose!,
                                  style: V2Typography.monoData(
                                    color: V2Colors.fgMuted,
                                  ).copyWith(fontSize: 12),
                                ),
                              ),
                          ],
                        ),
                        if (hasParentheticalDose) ...[
                          const SizedBox(height: 2),
                          Text(
                            _parenthesize(i.parentheticalDoseText!),
                            style: V2Typography.monoData(
                              color: V2Colors.fgMuted,
                            ).copyWith(fontSize: 12),
                          ),
                        ],
                        if (hasForm) ...[
                          const SizedBox(height: 2),
                          Text(
                            // Casing preserved verbatim — the label-native
                            // form must never collapse to lower case.
                            i.formLabel!,
                            style: V2Typography.caption(
                              color: V2Colors.fgMuted,
                            ),
                          ),
                        ],
                        if (showChips) ...[
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (formStatusLabel != null)
                                _FormStatusChipV2(
                                  state: formState,
                                  label: formStatusLabel,
                                  onTap: onTap,
                                ),
                              if (!suppressClaims &&
                                  isAssessed &&
                                  i.formQuality != FormQuality.unknown)
                                _FormChipV2(
                                  quality: i.formQuality,
                                  onTap: onTap,
                                ),
                              if (!suppressClaims &&
                                  i.doseCallOut != DoseCallOut.withinLimits)
                                _DoseChipV2(
                                  callOut: i.doseCallOut,
                                  onTap: onTap,
                                ),
                              if (!suppressClaims && i.isSafetyConcern)
                                const _MiniChipV2(
                                  label: 'Safety concern',
                                  icon: Icons.warning_amber_rounded,
                                  color: V2Colors.contraindicated,
                                ),
                              if (!suppressClaims && i.isInferredFromLabel)
                                const _MiniChipV2(
                                  label: 'Inferred from label',
                                  icon: Icons.manage_search_rounded,
                                  color: V2Colors.fgSubtle,
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (showBottomDivider)
          const Divider(height: 0.5, thickness: 0.5, color: V2Colors.outline),
      ],
    );
  }
}

String _parenthesize(String text) {
  final trimmed = text.trim();
  if (trimmed.startsWith('(') && trimmed.endsWith(')')) return trimmed;
  return '($trimmed)';
}

String _semanticsLabel({
  required PGActiveIngredient ingredient,
  required bool hasDose,
  required bool hasParentheticalDose,
  required bool hasForm,
  required PGIngredientFormDisplayState formState,
  required bool suppressClaims,
}) {
  final parts = <String>[ingredient.name];
  final nestedDepth = ingredient.nestedDepth < 0 ? 0 : ingredient.nestedDepth;
  if (nestedDepth == 0) {
    parts.add('Top-level label ingredient');
  } else {
    final parent = ingredient.parentLabel?.trim();
    parts.add(
      parent == null || parent.isEmpty
          ? 'Nested level $nestedDepth'
          : 'Nested level $nestedDepth under $parent',
    );
  }
  if (hasDose) parts.add(ingredient.dose!);
  if (hasParentheticalDose) {
    parts.add(_parenthesize(ingredient.parentheticalDoseText!));
  }
  if (hasForm) parts.add(ingredient.formLabel!);
  final formStatusLabel = formState.statusLabel;
  if (formStatusLabel != null) {
    parts.add(formStatusLabel);
  } else if (!suppressClaims &&
      formState == PGIngredientFormDisplayState.assessed &&
      ingredient.formQuality != FormQuality.unknown) {
    parts.add(formChipLabel(ingredient.formQuality));
  }
  if (!suppressClaims && ingredient.doseCallOut != DoseCallOut.withinLimits) {
    parts.add(doseChipLabel(ingredient.doseCallOut));
  }
  if (!suppressClaims && ingredient.isSafetyConcern) {
    parts.add('Safety concern');
  }
  if (!suppressClaims && ingredient.isInferredFromLabel) {
    parts.add('Inferred from label');
  }
  parts.add(ingredient.scoreParticipationLabel);
  return '${parts.join('. ')}.';
}

// =============================================================================
// Form chip — mirrors _FormChip color logic from
// =============================================================================

class _FormStatusChipV2 extends StatelessWidget {
  final PGIngredientFormDisplayState state;
  final String label;
  final VoidCallback? onTap;

  const _FormStatusChipV2({
    required this.state,
    required this.label,
    required this.onTap,
  });

  static Color _color(PGIngredientFormDisplayState state) => switch (state) {
    PGIngredientFormDisplayState.notDisclosed => V2Colors.fgMuted,
    PGIngredientFormDisplayState.listedNotAssessed => V2Colors.accentStrong,
    PGIngredientFormDisplayState.needsReview => V2Colors.caution,
    PGIngredientFormDisplayState.assessed => V2Colors.safe,
    PGIngredientFormDisplayState.notApplicable => V2Colors.fgMuted,
  };

  @override
  Widget build(BuildContext context) {
    return _PillChipV2(label: label, color: _color(state), onTap: onTap);
  }
}

class _FormChipV2 extends StatelessWidget {
  final FormQuality quality;
  final VoidCallback? onTap;

  const _FormChipV2({required this.quality, required this.onTap});

  /// Color mapping mirrors production meaning:
  /// excellent/good → safe, fair → caution,
  /// **poor → severityCaution (amber, NOT red — bioavailability is form
  /// quality, not safety)**, unknown → insufficientData.
  static Color _color(FormQuality q) => switch (q) {
    FormQuality.excellent => V2Colors.safe,
    FormQuality.good => V2Colors.safe,
    FormQuality.fair => V2Colors.caution,
    FormQuality.poor => V2Colors.caution,
    FormQuality.unknown => V2Colors.fgSubtle,
  };

  @override
  Widget build(BuildContext context) {
    return _PillChipV2(
      label: formChipLabel(quality),
      color: _color(quality),
      onTap: onTap,
    );
  }
}

// =============================================================================
// Dose chip — mirrors _DoseChip color logic from
// =============================================================================

class _DoseChipV2 extends StatelessWidget {
  final DoseCallOut callOut;
  final VoidCallback? onTap;

  const _DoseChipV2({required this.callOut, required this.onTap});

  /// Color mapping mirrors production meaning:
  /// **high → avoid (actual safety signal)**, low → caution,
  /// notDisclosed → subtle, withinLimits → safe (chip not rendered).
  static Color _color(DoseCallOut d) => switch (d) {
    DoseCallOut.high => V2Colors.avoid,
    DoseCallOut.low => V2Colors.caution,
    DoseCallOut.notDisclosed => V2Colors.fgSubtle,
    DoseCallOut.withinLimits => V2Colors.safe,
  };

  @override
  Widget build(BuildContext context) {
    return _PillChipV2(
      label: doseChipLabel(callOut),
      color: _color(callOut),
      onTap: onTap,
    );
  }
}

// =============================================================================
// Compact chip primitive — production _PillChip pattern, v2 weight discipline.
// 4-radius (NOT pill), 8h × 3v padding, color @ 12% alpha bg, 11pt label.
// Production used FontWeight.w700; v2 caps at 500 — color carries the meaning.
// =============================================================================

class _PillChipV2 extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _PillChipV2({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: V2Typography.caption(color: color).copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}

/// "Safety concern" / "Inferred from label" mini-chip — mirrors
/// `_IngredientMiniChip` from production_detail_screen.dart:2714.
/// Tighter than _PillChipV2 (6h × 2v padding) and includes an icon.
/// Non-interactive — informational only.
class _MiniChipV2 extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const _MiniChipV2({
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: V2Typography.caption(color: color).copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
