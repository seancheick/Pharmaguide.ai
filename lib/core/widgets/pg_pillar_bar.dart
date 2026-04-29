import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';

/// A single horizontal pillar bar — `[label] [bar] [percent]` row.
///
/// Used by the product-detail Quality Score card to render each of the four
/// scoring pillars (Ingredient Quality / Safety & Purity / Evidence &
/// Research / Brand Trust) as a tighter, non-expandable companion to
/// `ScoreBreakdownCard`'s expandable section bars.
///
/// The tone color derives from the value/max fraction via the canonical
/// 6-tier ladder defined in `AppTheme.score*`. Null values render an
/// em-dash placeholder + insufficient-data tone.
///
/// ```dart
/// PGPillarBar(
///   label: 'Ingredient Quality',
///   value: product.scoreIngredientQuality,
///   max: 25,
/// )
/// ```
class PGPillarBar extends StatelessWidget {
  /// Pillar label (left-aligned). Single line, ellipsis-truncated.
  final String label;

  /// Current value. Null renders the insufficient-data state.
  final double? value;

  /// Maximum possible value for this pillar (e.g. 25 for ingredient
  /// quality, 30 for safety & purity, 20 for evidence, 5 for brand trust).
  final double max;

  /// Reduced-height variant for dense lists. Default: false (regular
  /// 8pt bar height). Compact = 4pt bar height.
  final bool compact;

  const PGPillarBar({
    super.key,
    required this.label,
    required this.value,
    required this.max,
    this.compact = false,
  });

  /// 0..1 progress. Clamped so a value > max doesn't paint past the bar.
  double get _fraction {
    if (value == null || max <= 0) return 0;
    return (value! / max).clamp(0.0, 1.0);
  }

  /// Percent rendered to the user (e.g. "88%"). Null value → null;
  /// caller decides whether to swap in an em-dash.
  String? get _percentText {
    if (value == null) return null;
    final pct = (_fraction * 100).round();
    return '$pct%';
  }

  /// Maps a 0..1 fraction to the 6-tier tone ladder. Mirrors
  /// `PGScoreRing._colorFor` but takes a fraction instead of a 0..100
  /// score, so PGPillarBar callers can pass per-pillar-max values
  /// without converting to a /100 score first.
  Color _toneFor(double? frac) {
    if (frac == null) return AppTheme.insufficientData;
    if (frac >= 0.85) return AppTheme.scoreExceptional;
    if (frac >= 0.70) return AppTheme.scoreExcellent;
    if (frac >= 0.55) return AppTheme.scoreGood;
    if (frac >= 0.40) return AppTheme.scoreFair;
    if (frac >= 0.25) return AppTheme.scoreBelowAvg;
    return AppTheme.scoreLow;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasValue = value != null;
    final tone = _toneFor(hasValue ? _fraction : null);
    final barHeight = compact ? 4.0 : 8.0;
    final percent = _percentText;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Left: label
        Expanded(
          flex: 5,
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: AppTheme.space12),

        // Middle: bar (track + fill)
        Expanded(
          flex: 6,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(barHeight / 2),
            child: Stack(
              children: [
                // Track
                Container(
                  height: barHeight,
                  color: scheme.surfaceContainerHigh,
                ),
                // Fill — only paints when there's a value.
                if (hasValue)
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: _fraction,
                    child: Container(
                      height: barHeight,
                      color: tone,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: AppTheme.space8),

        // Right: percent text — em-dash for null, tier-tinted for values.
        SizedBox(
          width: 38,
          child: Text(
            percent ?? '—',
            textAlign: TextAlign.right,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: tone,
            ),
          ),
        ),
      ],
    );
  }
}
