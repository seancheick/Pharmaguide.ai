// NutrientProgressBar — single-row visualization for one nutrient's
// stack-wide total against intake-target and UL benchmarks.
//
// Tap to review contributing supplements in a scrollable bottom sheet.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_eyebrow.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/core/widgets/pg_modal.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';

class NutrientProgressBar extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final total = status.total;
    final tierColor = NutrientProgressBar.tierColorFor(status.tier);
    final fillPct = _fillPercent(status);
    // Every row with at least one contribution is tappable so the user
    // can always trace a nutrient back to the product(s) providing it,
    // even when only a single supplement in the stack contributes.
    final hasContributions = total.contributions.isNotEmpty;

    return Semantics(
      button: hasContributions,
      label: hasContributions
          ? '${total.displayName}, view contributors from your stack'
          : total.displayName,
      child: InkWell(
        onTap: hasContributions
            ? () => _showContributions(context, status)
            : null,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: V2Spacing.space16,
            vertical: V2Spacing.space8,
          ),
          constraints: const BoxConstraints(minHeight: 44),
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
                          const Icon(
                            Icons.chevron_right_rounded,
                            size: 16,
                            color: V2Colors.fgMuted,
                          ),
                        ],
                      ],
                    ),
                  ),
                  Text(
                    _formatAmountRange(
                      total.minimumTotalAmount,
                      total.totalAmount,
                      total.unit,
                    ),
                    style: _monoDataStyle(tierColor),
                  ),
                  const SizedBox(width: V2Spacing.space8),
                  // Inline compact subtitle (% target / UL) — moved from
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
              if (status.warning != null) ...[
                const SizedBox(height: V2Spacing.space8),
                _WarningChip(text: status.warning!, color: tierColor),
              ],
              if (status.ulAssessmentIndeterminate) ...[
                const SizedBox(height: V2Spacing.space4),
                Text(
                  'UL not calculated: the label does not provide enough '
                  'form detail.',
                  style: _captionStyle(V2Colors.fgMuted),
                ),
              ],
              if (total.hasUnitConflict) ...[
                const SizedBox(height: V2Spacing.space4),
                Text(
                  'Note: excludes products reported in a different unit.',
                  style: _captionStyle(V2Colors.fgMuted),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showContributions(BuildContext context, NutrientStatus status) {
    unawaited(
      PGModal.bottomSheet<void>(
        context: context,
        builder: (_) => _NutrientContributorsSheet(status: status),
      ),
    );
  }

  /// Compact subtitle — rendered inline on the same row as the amount
  /// so each nutrient entry takes a single tight row instead of two.
  /// Appends an asterisk when RDA came from the anonymous baseline
  /// (Female 19-30) so the user knows the value isn't profile-specific.
  Widget _buildSubtitleText() {
    final rda = status.pctOfRda;
    final ul = status.pctOfUl;
    // Prefer UL when the nutrient has a hard ceiling to flag; otherwise
    // show % target. Showing both would wrap and defeat the compact layout.
    final String text;
    if (ul != null) {
      text = '${ul.round()}% UL';
    } else if (rda != null) {
      final maximumRda = status.maximumPctOfRda;
      final formatted = maximumRda != null && (maximumRda - rda).abs() > 0.05
          ? _formatTargetRange(rda, maximumRda)
          : _formatTargetPercent(rda);
      text = status.rdaIsBaseline ? '$formatted*' : formatted;
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
    return '${_formatTargetValue(pct)} target';
  }

  static String _formatTargetValue(double pct) {
    if (pct > 1000) {
      final multiplier = (pct / 100).round();
      return '${multiplier}x';
    }
    return '${pct.round()}%';
  }

  static String _formatTargetRange(double minimum, double maximum) {
    if (minimum <= 1000 && maximum <= 1000) {
      return '${minimum.round()}–${maximum.round()}% target';
    }
    return '${_formatTargetValue(minimum)}–'
        '${_formatTargetValue(maximum)} target';
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

  static String _formatAmountRange(
    double? minimum,
    double maximum,
    String unit,
  ) {
    if (minimum == null || (minimum - maximum).abs() <= 0.000001) {
      return _formatAmount(maximum, unit);
    }
    final minimumText = _formatAmount(minimum, '');
    final maximumText = _formatAmount(maximum, unit);
    return '$minimumText–$maximumText';
  }

  static String _contributionLabel(NutrientContribution contribution) {
    final product = contribution.productName.trim();
    final ingredient = contribution.ingredientName.trim();
    if (ingredient.isEmpty || ingredient == product) return product;
    if (product.isEmpty) return ingredient;
    return '$product - $ingredient';
  }
}

class _NutrientContributorsSheet extends StatelessWidget {
  const _NutrientContributorsSheet({required this.status});

  final NutrientStatus status;

  @override
  Widget build(BuildContext context) {
    final total = status.total;
    final contributions = total.contributions;
    final totalBasis = total.hasDoseRange ? 'daily range' : 'daily total';

    return Semantics(
      label: '${total.displayName} contributors from your stack',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          V2Spacing.space24,
          V2Spacing.space8,
          V2Spacing.space24,
          V2Spacing.space24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PGEyebrow('From your stack', color: V2Colors.fgMuted),
            const SizedBox(height: V2Spacing.space8),
            Text(
              '${total.displayName} contributors',
              style: V2Typography.titleSm(color: V2Colors.fg),
            ),
            const SizedBox(height: V2Spacing.space4),
            Text(
              '${NutrientProgressBar._formatAmountRange(total.minimumTotalAmount, total.totalAmount, total.unit)} $totalBasis from the supplement labels in your stack.',
              style: V2Typography.bodySm(color: V2Colors.fgMuted),
            ),
            const SizedBox(height: V2Spacing.space16),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: contributions.length,
                separatorBuilder: (_, _) => const Divider(
                  height: V2Spacing.space24,
                  color: V2Colors.outline,
                ),
                itemBuilder: (_, index) {
                  final contribution = contributions[index];
                  final pctOfTotal = total.totalAmount > 0
                      ? (contribution.amount / total.totalAmount * 100).round()
                      : 0;
                  return Semantics(
                    label:
                        '${NutrientProgressBar._contributionLabel(contribution)}, '
                        '${NutrientProgressBar._formatAmountRange(contribution.minimumAmount, contribution.amount, contribution.unit)}, '
                        '$pctOfTotal percent of the stack total',
                    child: Row(
                      children: [
                        const Icon(
                          Icons.inventory_2_outlined,
                          size: 20,
                          color: V2Colors.accent,
                        ),
                        const SizedBox(width: V2Spacing.space12),
                        Expanded(
                          child: Text(
                            NutrientProgressBar._contributionLabel(
                              contribution,
                            ),
                            style: _captionStyle(V2Colors.fg),
                          ),
                        ),
                        const SizedBox(width: V2Spacing.space8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              NutrientProgressBar._formatAmountRange(
                                contribution.minimumAmount,
                                contribution.amount,
                                contribution.unit,
                              ),
                              style: _captionStyle(V2Colors.fg),
                            ),
                            Text(
                              '$pctOfTotal%',
                              style: _captionStyle(V2Colors.fgMuted),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
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

TextStyle _monoDataStyle(Color color) => TextStyle(
  fontSize: V2Typography.size14,
  fontWeight: FontWeight.w500,
  height: V2Typography.lhSnug,
  color: color,
  fontFeatures: const [FontFeature.tabularFigures()],
);
