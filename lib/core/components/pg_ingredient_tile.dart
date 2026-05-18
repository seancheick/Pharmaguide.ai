import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_ingredient_data.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/features/product_detail/widgets/ingredient_explain_model.dart';

/// v2 mirror of `_IngredientTile` in
///
///
/// **Same structure, semantics preserved verbatim:**
/// - Row 1: name (Geist Sans 500, ellipsis) + dose label right
///   (Geist Mono for tabular figures)
/// - Optional form helper line (12pt onSurfaceVariant, lowercase)
/// - Chips Wrap (spacing 6, runSpacing 4):
///   - `_FormChip` when `formQuality != unknown` — Excellent / Good /
///     Fair / Poor, color from FormQuality (Poor stays amber, not red —
///     bioavailability is form quality, not safety)
///   - `_DoseChip` when `doseCallOut != withinLimits` — High dose /
///     Low dose / Dose not disclosed (High is the only red — real safety)
///   - `_MiniChip` 'Safety concern' when `isSafetyConcern` (red, error tone)
///   - `_MiniChip` 'Inferred from label' when `isInferredFromLabel`
/// - Bottom hairline divider (0.5pt outlineVariant). Final row skips it.
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

  const PGActiveIngredientTile({
    super.key,
    required this.ingredient,
    this.showBottomDivider = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final i = ingredient;
    final showChips =
        i.formQuality != FormQuality.unknown ||
        i.doseCallOut != DoseCallOut.withinLimits ||
        i.isSafetyConcern ||
        i.isInferredFromLabel;
    final hasDose = i.dose != null && i.dose!.isNotEmpty;
    final hasForm = i.formLabel != null && i.formLabel!.isNotEmpty;

    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
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
                          style: V2Typography.bodyMedium(color: V2Colors.fg),
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
                  if (hasForm) ...[
                    const SizedBox(height: 2),
                    Text(
                      i.formLabel!.toLowerCase(),
                      style: V2Typography.caption(color: V2Colors.fgMuted),
                    ),
                  ],
                  if (showChips) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (i.formQuality != FormQuality.unknown)
                          _FormChipV2(quality: i.formQuality, onTap: onTap),
                        if (i.doseCallOut != DoseCallOut.withinLimits)
                          _DoseChipV2(callOut: i.doseCallOut, onTap: onTap),
                        if (i.isSafetyConcern)
                          const _MiniChipV2(
                            label: 'Safety concern',
                            icon: Icons.warning_amber_rounded,
                            color: V2Colors.contraindicated,
                          ),
                        if (i.isInferredFromLabel)
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
        if (showBottomDivider)
          const Divider(height: 0.5, thickness: 0.5, color: V2Colors.outline),
      ],
    );
  }
}

// =============================================================================
// Form chip — mirrors _FormChip color logic from
// =============================================================================

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
