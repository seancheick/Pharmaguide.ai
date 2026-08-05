import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_score_line.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
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
  final String? scoreConfidence;

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
    this.scoreConfidence,
    this.imageWidget,
    this.onTap,
  });
}

/// v2 better-alternatives section.
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
    this.title = 'Better alternatives',
    this.body,
  });

  @override
  Widget build(BuildContext context) {
    if (alternatives.isEmpty) return const SizedBox.shrink();
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
          if (body != null) ...[
            const SizedBox(height: V2Spacing.space4),
            Text(body!, style: V2Typography.bodySm(color: context.v2.fgMuted)),
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
    // Compact card: 48pt thumbnail, sans 14pt product name, compact
    // PGScoreLine (14pt score, no tier description). Tighter than the
    // production "Worth considering" cards — Sean's call: alternatives
    // are scannable list items, not full product previews.
    final card = Container(
      padding: const EdgeInsets.all(V2Spacing.space12),
      decoration: BoxDecoration(
        color: context.v2.bg,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        border: Border.all(color: context.v2.outline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: alt.imageWidget ?? _AlternativePlaceholder(),
          ),
          const SizedBox(width: V2Spacing.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  alt.brand,
                  style: V2Typography.caption(color: context.v2.fgMuted),
                ),
                const SizedBox(height: 2),
                Text(
                  alt.name,
                  style: V2Typography.bodySm(
                    color: context.v2.fg,
                  ).copyWith(fontWeight: FontWeight.w500),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: V2Spacing.space4),
                PGScoreLine(
                  score: alt.score,
                  compact: true,
                  confidence: alt.scoreConfidence,
                ),
              ],
            ),
          ),
          if (alt.onTap != null) ...[
            const SizedBox(width: V2Spacing.space8),
            Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: context.v2.fgMuted,
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
        color: context.v2.accentTint,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
      ),
      child: Icon(
        Icons.medication_outlined,
        size: 24,
        color: context.v2.accent,
      ),
    );
  }
}

/// Phase 11.7L.F follow-up — cream skeleton shown while
/// `BetterAlternativesRanker` resolves. Mirrors the section's
/// vertical rhythm (title bar + 2 row placeholders) so the sticky
/// CTA's scroll anchor lands on a real surface, not an empty slot.
class PGBetterAlternativesSkeleton extends StatelessWidget {
  const PGBetterAlternativesSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title placeholder
        Container(
          width: 240,
          height: 20,
          decoration: BoxDecoration(
            color: context.v2.outline,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(height: V2Spacing.space16),
        for (var i = 0; i < 2; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: V2Spacing.space8),
            child: Container(
              padding: const EdgeInsets.all(V2Spacing.space12),
              decoration: BoxDecoration(
                color: context.v2.surface,
                borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
                border: Border.all(color: context.v2.outline),
                boxShadow: V2Shadows.sm,
              ),
              child: Row(
                children: [
                  // Score badge placeholder
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: context.v2.outline,
                      borderRadius: BorderRadius.circular(V2Spacing.space8),
                    ),
                  ),
                  const SizedBox(width: V2Spacing.space16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 200,
                          height: 14,
                          decoration: BoxDecoration(
                            color: context.v2.outline,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(height: V2Spacing.space8),
                        Container(
                          width: 120,
                          height: 12,
                          decoration: BoxDecoration(
                            color: context.v2.outline,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
