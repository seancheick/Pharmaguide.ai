import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_eyebrow.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

/// Direction of a metric's delta indicator.
enum PGMetricTrend {
  /// Neutral — no caret rendered.
  flat,

  /// Positive (e.g. health score improved).
  up,

  /// Negative (e.g. interactions detected).
  down,
}

/// A single metric tile — value + label + optional delta + optional trailing.
///
/// Designed for personal state surfaces: stack health, fit score, daily
/// nutrient totals. Composable into rows / grids — see [PGMetricRow].
///
/// **Visual:**
/// - Surface bg + hairline outline + tier-1 shadow
/// - Mono caps eyebrow label up top
/// - Large value in Geist Sans 500 with tabular figures (no jitter when
///   counting changes)
/// - Optional caption beneath the value (e.g. "of 8 daily")
/// - Optional trailing widget on the right (e.g. small severity dot)
/// - Optional delta pill below — colored by [PGMetricTrend], muted by
///   default. Never the dominant element.
class PGMetricCard extends StatelessWidget {
  /// Mono caps label for the metric ("STACK HEALTH", "DAILY VITAMINS").
  final String label;

  /// Primary value, already formatted (e.g. "86", "3 / 8", "2 alerts").
  final String value;

  /// Body caption shown beneath the value.
  final String? caption;

  /// Optional delta string (e.g. "+12 this week", "−1 since Tuesday").
  /// Renders as a pill colored by [trend].
  final String? delta;
  final PGMetricTrend trend;

  /// Trailing widget anchored top-right inside the card. Use for a small
  /// severity dot or icon.
  final Widget? trailing;

  /// Optional tap handler — opens a deeper view (Stack screen, FitScore
  /// detail). When null, the card is informational only.
  final VoidCallback? onTap;

  /// Override the default value text size — useful when the value is
  /// extra-large ("3 / 8") and the layout wants more weight.
  final double? valueSize;

  const PGMetricCard({
    super.key,
    required this.label,
    required this.value,
    this.caption,
    this.delta,
    this.trend = PGMetricTrend.flat,
    this.trailing,
    this.onTap,
    this.valueSize,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: const EdgeInsets.all(V2Spacing.space16),
      decoration: BoxDecoration(
        color: context.v2.surface,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        border: Border.all(color: context.v2.outline),
        boxShadow: V2Shadows.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(child: PGEyebrow(label, color: context.v2.fgMuted)),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: V2Spacing.space12),
          Text(
            value,
            style: V2Typography.title(color: context.v2.fg).copyWith(
              fontSize: valueSize ?? 28,
              height: 1.05,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (caption != null) ...[
            const SizedBox(height: V2Spacing.space4),
            Text(
              caption!,
              style: V2Typography.bodySm(color: context.v2.fgMuted),
            ),
          ],
          if (delta != null) ...[
            const SizedBox(height: V2Spacing.space12),
            _DeltaPill(text: delta!, trend: trend),
          ],
        ],
      ),
    );

    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        child: card,
      ),
    );
  }
}

class _DeltaPill extends StatelessWidget {
  final String text;
  final PGMetricTrend trend;

  const _DeltaPill({required this.text, required this.trend});

  @override
  Widget build(BuildContext context) {
    final tint = switch (trend) {
      PGMetricTrend.up => context.v2.safeTint,
      PGMetricTrend.down => context.v2.cautionTint,
      PGMetricTrend.flat => context.v2.outline,
    };
    final foreground = context.v2.fg;
    final caret = switch (trend) {
      PGMetricTrend.up => '↑',
      PGMetricTrend.down => '↓',
      PGMetricTrend.flat => null,
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: V2Spacing.space12,
        vertical: V2Spacing.space4,
      ),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (caret != null) ...[
            Text(caret, style: V2Typography.label(color: foreground)),
            const SizedBox(width: V2Spacing.space4),
          ],
          Text(text, style: V2Typography.caption(color: foreground)),
        ],
      ),
    );
  }
}

/// Convenience wrapper to render a row of [PGMetricCard]s. Each card
/// gets equal width via [Expanded]; pass between 2 and 3 children for
/// best legibility (4 cards on a 390pt phone gets cramped).
class PGMetricRow extends StatelessWidget {
  final List<PGMetricCard> cards;

  const PGMetricRow({super.key, required this.cards});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < cards.length; i++) ...[
          if (i > 0) const SizedBox(width: V2Spacing.space12),
          Expanded(child: cards[i]),
        ],
      ],
    );
  }
}
