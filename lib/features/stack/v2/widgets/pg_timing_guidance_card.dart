// PGTimingGuidanceCard — per-bottle timing guidance.
//
// Replaces PGDailyPlanCard, which drew a generated daily schedule. Three things
// this card deliberately does NOT do:
//
//   * It never shows a clock time or a daypart. There is no "with breakfast" or
//     "before bed", because the app does not know when the user wakes, eats,
//     fasts, or sleeps. Event-relative guidance ("30-60 minutes before intended
//     sleep") is rendered only when a rule authored it structurally.
//   * It never states when a prescribed medication is taken. Guidance attaches
//     to the supplement, scoped so the prescription is left alone.
//   * It never renders an ingredient as if it were a bottle, and it never
//     writes filler. A product with no applicable verified rule shows nothing.

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_eyebrow.dart';
import 'package:pharmaguide/core/models/timing_optimization.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/services/stack/timing_guidance_builder.dart';

class PGTimingGuidanceCard extends StatelessWidget {
  const PGTimingGuidanceCard({
    super.key,
    required this.guidance,
    this.margin = EdgeInsets.zero,
  });

  final TimingGuidance guidance;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final hasProducts = guidance.products.isNotEmpty;
    final canSayNothingFound = guidance.canAssertNoFindings;

    // Silence over filler. Nothing to show and nothing we can honestly assert
    // means no card at all.
    if (!hasProducts && !canSayNothingFound) return const SizedBox.shrink();

    final palette = context.v2;

    return Padding(
      padding: margin,
      child: Container(
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
          border: Border.all(color: palette.outline),
          boxShadow: V2Shadows.sm,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Padding(
                padding: const EdgeInsets.all(V2Spacing.space16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.schedule_rounded,
                          size: 16,
                          color: palette.accent,
                        ),
                        const SizedBox(width: V2Spacing.space8),
                        PGEyebrow('Timing guidance', color: palette.accent),
                      ],
                    ),
                    const SizedBox(height: V2Spacing.space12),
                    if (!hasProducts)
                      // One stack-level statement, never one per product: a
                      // per-bottle "nothing found" would imply per-bottle
                      // comprehensive coverage the app cannot claim.
                      Text(
                        'No important timing findings identified for the '
                        'products successfully assessed.',
                        style: V2Typography.bodySm(color: palette.fgMuted),
                      ),
                    for (var i = 0; i < guidance.products.length; i++) ...[
                      if (i > 0) const SizedBox(height: V2Spacing.space16),
                      _ProductGuidance(product: guidance.products[i]),
                    ],
                  ],
                ),
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 4,
              child: ColoredBox(color: palette.accent),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductGuidance extends StatelessWidget {
  const _ProductGuidance({required this.product});

  final ProductTimingGuidance product;

  @override
  Widget build(BuildContext context) {
    final palette = context.v2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            product.productName,
            style: V2Typography.titleSm(color: palette.fg),
          ),
        ),
        if (product.importantSeparation.isNotEmpty)
          _Section(
            label: 'Important',
            items: product.importantSeparation,
            emphasised: true,
          ),
        if (product.howToTake.isNotEmpty)
          _Section(label: 'How to take it', items: product.howToTake),
        if (product.optional.isNotEmpty)
          _Section(label: 'Optional', items: product.optional),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.label,
    required this.items,
    this.emphasised = false,
  });

  final String label;
  final List<TimingOptimization> items;
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    final palette = context.v2;
    return Padding(
      padding: const EdgeInsets.only(top: V2Spacing.space8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: V2Typography.label(
              color: emphasised ? palette.fg : palette.fgMuted,
            ),
          ),
          const SizedBox(height: V2Spacing.space4),
          for (final item in items) ...[
            // The pipeline's own words. The app never rewrites reviewed advice.
            Text(item.advice, style: V2Typography.bodySm(color: palette.fg)),
            if (item.involvesMedication) ...[
              const SizedBox(height: 2),
              Text(
                'Continue taking your medication exactly as prescribed.',
                style: V2Typography.caption(color: palette.fgMuted),
              ),
            ],
            const SizedBox(height: V2Spacing.space8),
          ],
        ],
      ),
    );
  }
}
