import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

/// Typographic score chip — pure number + tier eyebrow, no arc.
///
/// Alternative to [PGScoreRing] for surfaces that want a more restrained,
/// "clinical report" feel rather than a data-viz ring. The chip leads with
/// the number (Geist Sans, tabular figures); the tier name and "PG SCORE"
/// label sit underneath in mono caps.
///
/// **When to use:**
/// - In list items, summary cards, or anywhere the score is one of many
///   data points (Stack screen, search results, Recents).
/// - On the Product Detail Key Takeaway, when the design wants the
///   verdict label to anchor the card visually, not the score itself.
///
/// **When NOT to use:**
/// - When the score IS the moment (e.g. post-scan reveal). Use the ring
///   there with a parent fade-in for the celebratory feel.
class PGScoreChip extends StatelessWidget {
  final double score;

  /// Tier name shown below the number, e.g. "EXCELLENT" / "MODERATE" /
  /// "POOR". When null, the chip computes a default from the score bands.
  final String? tierLabel;

  /// Whether to render the "PG SCORE" caption above the number.
  final bool showCaption;

  const PGScoreChip({
    super.key,
    required this.score,
    this.tierLabel,
    this.showCaption = true,
  });

  Color _bandColor(double s) {
    if (s >= 80) return V2Colors.safe;
    if (s >= 60) return V2Colors.monitor;
    if (s >= 40) return V2Colors.caution;
    return V2Colors.avoid;
  }

  String _defaultTier(double s) {
    if (s >= 80) return 'Excellent';
    if (s >= 60) return 'Moderate';
    if (s >= 40) return 'Poor';
    return 'Avoid';
  }

  @override
  Widget build(BuildContext context) {
    final color = _bandColor(score);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showCaption)
          Text(
            'PG SCORE',
            style: V2Typography.overline(color: V2Colors.fgMuted),
          ),
        if (showCaption) const SizedBox(height: V2Spacing.space4),
        Text(
          score.round().toString(),
          style: V2Typography.title(color: V2Colors.fg).copyWith(
            fontSize: 36,
            height: 1.0,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: V2Spacing.space4),
        Text(
          (tierLabel ?? _defaultTier(score)).toUpperCase(),
          style: V2Typography.overline(color: color),
        ),
      ],
    );
  }
}
