// NutrientProgressBar — single-row visualization for one nutrient's
// stack-wide total against RDA and UL benchmarks.
//
// Now expandable: tap to see which supplements contribute and how much.

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';

class NutrientProgressBar extends StatefulWidget {
  const NutrientProgressBar({
    super.key,
    required this.status,
  });

  final NutrientStatus status;

  static Color tierColorFor(NutrientTier tier) {
    switch (tier) {
      case NutrientTier.exceedsUl:
        return AppTheme.severityContraindicated;
      case NutrientTier.approachingUl:
        return AppTheme.severityAvoid;
      case NutrientTier.aboveTypical:
        return AppTheme.severityCaution;
      case NutrientTier.abundant:
        return AppTheme.scoreGood;
      case NutrientTier.adequate:
        return AppTheme.severitySafe;
      case NutrientTier.underFifty:
      case NutrientTier.noRda:
        return AppTheme.insufficientData;
    }
  }

  @override
  State<NutrientProgressBar> createState() => _NutrientProgressBarState();
}

class _NutrientProgressBarState extends State<NutrientProgressBar> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final total = widget.status.total;
    final tierColor = NutrientProgressBar.tierColorFor(widget.status.tier);
    final fillPct = _fillPercent(widget.status);
    final hasContributions = total.contributions.length > 1;

    return GestureDetector(
      onTap: hasContributions
          ? () => setState(() => _expanded = !_expanded)
          : null,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.space16,
          vertical: AppTheme.space12,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Text(
                        total.displayName,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (hasContributions) ...[
                        const SizedBox(width: 4),
                        AnimatedRotation(
                          turns: _expanded ? 0.5 : 0.0,
                          duration: const Duration(milliseconds: 200),
                          child: Icon(
                            Icons.expand_more,
                            size: 16,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Text(
                  _formatAmount(total.totalAmount, total.unit),
                  style: AppTheme.numeric(
                    theme.textTheme.bodyMedium!.copyWith(
                      fontWeight: FontWeight.w700,
                      color: tierColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.radiusFull),
              child: LinearProgressIndicator(
                value: fillPct.clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: scheme.surfaceContainerHigh,
                valueColor: AlwaysStoppedAnimation<Color>(tierColor),
              ),
            ),
            const SizedBox(height: 4),
            _buildSubtitleRow(theme, scheme),
            if (widget.status.warning != null) ...[
              const SizedBox(height: 6),
              _WarningChip(
                text: widget.status.warning!,
                color: tierColor,
              ),
            ],
            if (total.hasUnitConflict) ...[
              const SizedBox(height: 4),
              Text(
                'Note: excludes products reported in a different unit.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                  fontSize: 11,
                ),
              ),
            ],

            // Expandable per-supplement breakdown
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 200),
              crossFadeState: _expanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              firstChild: const SizedBox.shrink(),
              secondChild: _buildContributions(theme, scheme),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubtitleRow(ThemeData theme, ColorScheme scheme) {
    final rda = widget.status.pctOfRda;
    final ul = widget.status.pctOfUl;
    final parts = <String>[];

    if (rda != null) {
      parts.add(_formatRdaPercent(rda));
    }
    if (ul != null) {
      parts.add('${ul.round()}% UL');
    }

    final text = parts.isEmpty ? 'No RDA data' : parts.join('  ·  ');

    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        color: scheme.onSurfaceVariant,
        fontSize: 12,
      ),
    );
  }

  /// Format RDA percentage in a human-friendly way.
  /// Instead of "25000% RDA" show "250x RDA" for extreme values.
  static String _formatRdaPercent(double pct) {
    if (pct > 1000) {
      final multiplier = (pct / 100).round();
      return '${multiplier}x RDA';
    }
    return '${pct.round()}% RDA';
  }

  Widget _buildContributions(ThemeData theme, ColorScheme scheme) {
    final contributions = widget.status.total.contributions;
    if (contributions.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.all(AppTheme.space8),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'From your stack',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 4),
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
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        c.productName,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      _formatAmount(c.amount, c.unit),
                      style: AppTheme.numeric(
                        theme.textTheme.bodySmall!.copyWith(
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 36,
                      child: Text(
                        '$pctOfTotal%',
                        textAlign: TextAlign.end,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
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
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.warning_amber_rounded, size: 14, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
