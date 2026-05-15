import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

/// v2 mirror of `FormulationDetailSection`
/// (lib/features/product_detail/widgets/pipeline_sections/
/// formulation_detail_section.dart).
///
/// Shows delivery form + bioavailability enhancers + plant compounds.
/// Each section is a chip row beneath a small eyebrow label.
class PGFormulationSection extends StatelessWidget {
  /// Delivery form (e.g. "Liposomal", "Sublingual", "Enteric-coated").
  /// Production highlights premium forms in a tier badge.
  final String? form;

  /// Optional tier badge text alongside the form ("Premium", "Standard").
  final String? formTierLabel;

  /// Color for the form tier badge — green for absorbed-fast forms,
  /// muted-grey for standard.
  final Color? formTierColor;

  /// Absorption enhancers — green-tinted chips ("Black pepper extract",
  /// "Phospholipid carrier"). Optional.
  final List<String> absorptionEnhancers;

  /// Botanicals + adaptogens — leaf-icon chips ("Ashwagandha root",
  /// "Rhodiola rosea"). Optional.
  final List<String> botanicals;

  /// "Demoted" absorption enhancers — present but pipeline doesn't
  /// credit them (insufficient dose, wrong form). Caller flags these
  /// so they render quieter.
  final List<String> demotedEnhancers;

  final String title;

  const PGFormulationSection({
    super.key,
    this.form,
    this.formTierLabel,
    this.formTierColor,
    this.absorptionEnhancers = const [],
    this.botanicals = const [],
    this.demotedEnhancers = const [],
    this.title = 'Formulation',
  });

  bool get _hasContent =>
      form != null ||
      absorptionEnhancers.isNotEmpty ||
      botanicals.isNotEmpty ||
      demotedEnhancers.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    if (!_hasContent) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(V2Spacing.space16),
      decoration: BoxDecoration(
        color: V2Colors.surface,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        border: Border.all(color: V2Colors.outline),
        boxShadow: V2Shadows.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: V2Typography.titleSm(color: V2Colors.fg)),
          if (form != null) ...[
            const SizedBox(height: V2Spacing.space12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    form!,
                    style: V2Typography.bodyMedium(color: V2Colors.fg),
                  ),
                ),
                if (formTierLabel != null) ...[
                  const SizedBox(width: V2Spacing.space8),
                  _TierBadge(
                    label: formTierLabel!,
                    color: formTierColor ?? AppTheme.scoreGood,
                  ),
                ],
              ],
            ),
          ],
          if (absorptionEnhancers.isNotEmpty) ...[
            const SizedBox(height: V2Spacing.space12),
            Text(
              'Absorption enhancers',
              style: V2Typography.caption(color: V2Colors.fgMuted),
            ),
            const SizedBox(height: V2Spacing.space4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final e in absorptionEnhancers)
                  _IngredientPill(
                    label: e,
                    color: AppTheme.severitySafe,
                  ),
              ],
            ),
          ],
          if (botanicals.isNotEmpty) ...[
            const SizedBox(height: V2Spacing.space12),
            Text(
              'Botanicals',
              style: V2Typography.caption(color: V2Colors.fgMuted),
            ),
            const SizedBox(height: V2Spacing.space4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final b in botanicals)
                  _IngredientPill(
                    label: b,
                    color: AppTheme.scoreGood,
                    icon: Icons.eco_outlined,
                  ),
              ],
            ),
          ],
          if (demotedEnhancers.isNotEmpty) ...[
            const SizedBox(height: V2Spacing.space12),
            Text(
              'Listed but not credited',
              style: V2Typography.caption(color: V2Colors.fgMuted),
            ),
            const SizedBox(height: V2Spacing.space4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final d in demotedEnhancers)
                  _IngredientPill(
                    label: d,
                    color: V2Colors.fgSubtle,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _TierBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _TierBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
      ),
      child: Text(
        label.toUpperCase(),
        style: V2Typography.overline(color: color),
      ),
    );
  }
}

class _IngredientPill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const _IngredientPill({
    required this.label,
    required this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: V2Typography.caption(color: color).copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
