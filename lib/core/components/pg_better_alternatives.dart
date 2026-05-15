import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_score_line.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

/// One alternative product surfaced when the current product is
/// blocked / low-scoring / fit-limited.
class PGAlternative {
  final String dsldId;
  final String name;
  final String brand;
  final int score;

  /// Optional 96pt product image widget (caller provides — production
  /// composes ProductImage with Hero tag).
  final Widget? imageWidget;

  /// Tap → navigate to that product's detail page.
  final VoidCallback? onTap;

  const PGAlternative({
    required this.dsldId,
    required this.name,
    required this.brand,
    required this.score,
    this.imageWidget,
    this.onTap,
  });
}

/// v2 mirror of `BetterAlternativesSection`
/// (lib/features/product_detail/widgets/better_alternatives.dart).
///
/// Conditional render — caller decides when to show (production rule:
/// product is blocked OR score < 60 OR fit is Limited/NotRecommended).
/// Max 3 alternatives. Each row is a tappable card with thumbnail +
/// name + brand + score line.
class PGBetterAlternatives extends StatelessWidget {
  final List<PGAlternative> alternatives;
  final String title;
  final String? body;

  const PGBetterAlternatives({
    super.key,
    required this.alternatives,
    this.title = 'Worth considering',
    this.body,
  });

  @override
  Widget build(BuildContext context) {
    if (alternatives.isEmpty) return const SizedBox.shrink();
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
          if (body != null) ...[
            const SizedBox(height: V2Spacing.space4),
            Text(
              body!,
              style: V2Typography.bodySm(color: V2Colors.fgMuted),
            ),
          ],
          const SizedBox(height: V2Spacing.space12),
          for (var i = 0; i < alternatives.length; i++) ...[
            if (i > 0) const SizedBox(height: V2Spacing.space8),
            _AlternativeCard(alt: alternatives[i]),
          ],
        ],
      ),
    );
  }
}

class _AlternativeCard extends StatelessWidget {
  final PGAlternative alt;
  const _AlternativeCard({required this.alt});

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: const EdgeInsets.all(V2Spacing.space12),
      decoration: BoxDecoration(
        color: V2Colors.bg,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        border: Border.all(color: V2Colors.outline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 56pt image slot — falls back to a soft accent-tint tile.
          SizedBox(
            width: 56,
            height: 56,
            child: alt.imageWidget ?? _AlternativePlaceholder(),
          ),
          const SizedBox(width: V2Spacing.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alt.brand,
                  style: V2Typography.caption(color: V2Colors.fgMuted),
                ),
                const SizedBox(height: 2),
                Text(
                  alt.name,
                  style: V2Typography.bodyMedium(color: V2Colors.fg),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: V2Spacing.space8),
                PGScoreLine(score: alt.score),
              ],
            ),
          ),
          if (alt.onTap != null) ...[
            const SizedBox(width: V2Spacing.space8),
            const Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: V2Colors.fgMuted,
            ),
          ],
        ],
      ),
    );

    if (alt.onTap == null) return card;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
      child: InkWell(
        onTap: alt.onTap,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        child: card,
      ),
    );
  }
}

class _AlternativePlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: V2Colors.accentTint,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
      ),
      child: const Icon(
        Icons.medication_outlined,
        size: 24,
        color: V2Colors.accent,
      ),
    );
  }
}
