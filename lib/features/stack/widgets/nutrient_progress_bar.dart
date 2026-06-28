// NutrientProgressBar — single-row visualization for one nutrient's
// stack-wide total against RDA and UL benchmarks.
//
// Now expandable: tap to see which supplements contribute and how much.

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_motion.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';

class NutrientProgressBar extends StatefulWidget {
  const NutrientProgressBar({super.key, required this.status});

  final NutrientStatus status;

  static Color tierColorFor(NutrientTier tier) {
    switch (tier) {
      // Only crossing the UL is red, and only 80-99% of the UL is amber — one
      // warning tone, reached only as a real ceiling approaches.
      case NutrientTier.exceedsUl:
        return V2Colors.contraindicated;
      case NutrientTier.approachingUl:
        return V2Colors.caution;
      // High intake that is NOT nearing a ceiling is calm/green, never a
      // warning tone. This covers both no-UL nutrients above target
      // (aboveAdequateNoUl) and UL-bounded nutrients still comfortably below
      // 80% of their UL (abundant/aboveTypical/adequate). Multiples of the RDA
      // are not a hazard when there is headroom to the limit.
      case NutrientTier.aboveTypical:
      case NutrientTier.abundant:
      case NutrientTier.adequate:
      case NutrientTier.aboveAdequateNoUl:
        return V2Colors.safe;
      case NutrientTier.underFifty:
      case NutrientTier.noRda:
        return V2Colors.fgSubtle;
    }
  }

  @override
  State<NutrientProgressBar> createState() => _NutrientProgressBarState();
}

class _NutrientProgressBarState extends State<NutrientProgressBar> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final total = widget.status.total;
    final tierColor = NutrientProgressBar.tierColorFor(widget.status.tier);
    final fillPct = _fillPercent(widget.status);
    // Every row with at least one contribution is tappable so the user
    // can always trace a nutrient back to the product(s) providing it,
    // even when only a single supplement in the stack contributes.
    final hasContributions = total.contributions.isNotEmpty;

    return GestureDetector(
      onTap: hasContributions
          ? () => setState(() => _expanded = !_expanded)
          : null,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: V2Spacing.space16,
          vertical: V2Spacing.space8,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          total.displayName,
                          style: _labelStyle(V2Colors.fg),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (hasContributions) ...[
                        const SizedBox(width: V2Spacing.space4),
                        AnimatedRotation(
                          turns: _expanded ? 0.5 : 0.0,
                          duration: V2Motion.fast,
                          child: const Icon(
                            Icons.expand_more_rounded,
                            size: 14,
                            color: V2Colors.fgMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Text(
                  _formatAmount(total.totalAmount, total.unit),
                  style: _monoDataStyle(tierColor),
                ),
                const SizedBox(width: V2Spacing.space8),
                // Inline compact subtitle (% RDA / UL) — moved from
                // its own row so each nutrient is a tight single line.
                _buildSubtitleText(),
              ],
            ),
            const SizedBox(height: V2Spacing.space4),
            ClipRRect(
              borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
              child: LinearProgressIndicator(
                value: fillPct.clamp(0.0, 1.0),
                minHeight: 4,
                backgroundColor: V2Colors.outline,
                valueColor: AlwaysStoppedAnimation<Color>(tierColor),
              ),
            ),
            if (widget.status.warning != null) ...[
              const SizedBox(height: V2Spacing.space8),
              _WarningChip(text: widget.status.warning!, color: tierColor),
            ],
            if (total.hasUnitConflict) ...[
              const SizedBox(height: V2Spacing.space4),
              Text(
                'Note: excludes products reported in a different unit.',
                style: _captionStyle(V2Colors.fgMuted),
              ),
            ],

            // Expandable per-supplement breakdown
            AnimatedCrossFade(
              duration: V2Motion.fast,
              crossFadeState: _expanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              firstChild: const SizedBox.shrink(),
              secondChild: _buildContributions(),
            ),
          ],
        ),
      ),
    );
  }

  /// Compact subtitle — rendered inline on the same row as the amount
  /// so each nutrient entry takes a single tight row instead of two.
  /// Appends an asterisk when RDA came from the anonymous baseline
  /// (Female 19-30) so the user knows the value isn't profile-specific.
  Widget _buildSubtitleText() {
    final rda = widget.status.pctOfRda;
    final ul = widget.status.pctOfUl;
    // Prefer UL when the nutrient has a hard ceiling to flag; otherwise
    // show %RDA. Showing both would wrap and defeat the compact layout.
    final String text;
    if (ul != null) {
      text = '${ul.round()}% UL';
    } else if (rda != null) {
      final formatted = _formatTargetPercent(rda);
      text = widget.status.rdaIsBaseline ? '$formatted*' : formatted;
    } else {
      text = '—';
    }

    return Text(text, style: _captionStyle(V2Colors.fgMuted));
  }

  /// Format intake-vs-target percentage. Labeled "target" rather than "RDA"
  /// because many tracked nutrients have an Adequate Intake (AI) or Daily
  /// Value, not an RDA — e.g. vitamin K, biotin, and pantothenic acid use an
  /// AI. Calling those "% RDA" is clinically inaccurate. Extreme values
  /// collapse to "Nx target" instead of "2500% target".
  static String _formatTargetPercent(double pct) {
    if (pct > 1000) {
      final multiplier = (pct / 100).round();
      return '${multiplier}x target';
    }
    return '${pct.round()}% target';
  }

  Widget _buildContributions() {
    final contributions = widget.status.total.contributions;
    if (contributions.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.all(V2Spacing.space8),
        decoration: BoxDecoration(
          color: V2Colors.bg,
          borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
          border: Border.all(color: V2Colors.outline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('From your stack', style: _overlineStyle(V2Colors.fgMuted)),
            const SizedBox(height: V2Spacing.space4),
            ...contributions.map((c) {
              final pctOfTotal = widget.status.total.totalAmount > 0
                  ? (c.amount / widget.status.total.totalAmount * 100).round()
                  : 0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: V2Colors.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: V2Spacing.space8),
                    Expanded(
                      child: Text(
                        _contributionLabel(c),
                        style: _captionStyle(V2Colors.fg),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      _formatAmount(c.amount, c.unit),
                      style: _captionStyle(V2Colors.fg),
                    ),
                    const SizedBox(width: V2Spacing.space8),
                    SizedBox(
                      width: 36,
                      child: Text(
                        '$pctOfTotal%',
                        textAlign: TextAlign.end,
                        style: _captionStyle(V2Colors.fgMuted),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  double _fillPercent(NutrientStatus status) {
    final ul = status.pctOfUl;
    if (ul != null) return ul / 100.0;
    final rda = status.pctOfRda;
    if (rda != null) return (rda / 200.0).clamp(0.0, 1.0);
    return 0.0;
  }

  static String _formatAmount(double amount, String unit) {
    final rounded = amount >= 10
        ? amount.round().toString()
        : amount.toStringAsFixed(amount == amount.roundToDouble() ? 0 : 1);
    return unit.isEmpty ? rounded : '$rounded ${unit.toUpperCase()}';
  }

  static String _contributionLabel(NutrientContribution contribution) {
    final product = contribution.productName.trim();
    final ingredient = contribution.ingredientName.trim();
    if (ingredient.isEmpty || ingredient == product) return product;
    if (product.isEmpty) return ingredient;
    return '$product - $ingredient';
  }
}

class _WarningChip extends StatelessWidget {
  const _WarningChip({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.warning_amber_rounded, size: 14, color: color),
          const SizedBox(width: V2Spacing.space8),
          Flexible(child: Text(text, style: _captionStyle(color))),
        ],
      ),
    );
  }
}

TextStyle _labelStyle(Color color) => TextStyle(
  fontSize: V2Typography.size14,
  fontWeight: FontWeight.w500,
  height: V2Typography.lhSnug,
  color: color,
);

TextStyle _captionStyle(Color color) => TextStyle(
  fontSize: V2Typography.size12,
  fontWeight: FontWeight.w400,
  height: V2Typography.lhSnug,
  color: color,
);

TextStyle _overlineStyle(Color color) => TextStyle(
  fontSize: V2Typography.size10,
  fontWeight: FontWeight.w500,
  height: V2Typography.lhSnug,
  letterSpacing: V2Typography.tsEyebrow,
  color: color,
);

TextStyle _monoDataStyle(Color color) => TextStyle(
  fontSize: V2Typography.size14,
  fontWeight: FontWeight.w500,
  height: V2Typography.lhSnug,
  color: color,
  fontFeatures: const [FontFeature.tabularFigures()],
);
