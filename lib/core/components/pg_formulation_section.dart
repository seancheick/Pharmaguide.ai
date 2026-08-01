import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

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
        color: context.v2.surface,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        border: Border.all(color: context.v2.outline),
        boxShadow: V2Shadows.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: V2Typography.titleSm(color: context.v2.fg)),
          if (form != null) ...[
            const SizedBox(height: V2Spacing.space12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    form!,
                    style: V2Typography.bodyMedium(color: context.v2.fg),
                  ),
                ),
                if (formTierLabel != null) ...[
                  const SizedBox(width: V2Spacing.space8),
                  _TierBadge(
                    label: formTierLabel!,
                    color: formTierColor ?? context.v2.monitor,
                  ),
                ],
              ],
            ),
          ],
          if (absorptionEnhancers.isNotEmpty) ...[
            const SizedBox(height: V2Spacing.space12),
            Text(
              'Absorption enhancers',
              style: V2Typography.caption(color: context.v2.fgMuted),
            ),
            const SizedBox(height: V2Spacing.space4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final e in absorptionEnhancers)
                  _IngredientPill(label: e, color: context.v2.safe),
              ],
            ),
          ],
          if (botanicals.isNotEmpty) ...[
            const SizedBox(height: V2Spacing.space12),
            Text(
              'Botanicals',
              style: V2Typography.caption(color: context.v2.fgMuted),
            ),
            const SizedBox(height: V2Spacing.space4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final b in botanicals)
                  _IngredientPill(
                    label: b,
                    color: context.v2.safe,
                    icon: Icons.eco_outlined,
                  ),
              ],
            ),
          ],
          if (demotedEnhancers.isNotEmpty) ...[
            const SizedBox(height: V2Spacing.space12),
            Text(
              'Listed but not credited',
              style: V2Typography.caption(color: context.v2.fgMuted),
            ),
            const SizedBox(height: V2Spacing.space4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final d in demotedEnhancers)
                  _IngredientPill(label: d, color: context.v2.fgSubtle),
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
    final style = context.v2.tintedLabel(color, fillAlpha: 0.12);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: style.fill,
        borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
      ),
      child: Text(
        label.toUpperCase(),
        style: V2Typography.overline(color: style.foreground),
      ),
    );
  }
}

class _IngredientPill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const _IngredientPill({required this.label, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    final style = context.v2.tintedLabel(color);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: style.fill,
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
            style: V2Typography.caption(
              color: style.foreground,
            ).copyWith(fontSize: 11, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
