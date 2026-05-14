import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_eyebrow.dart';
import 'package:pharmaguide/core/components/pg_ingredient_stack.dart';
import 'package:pharmaguide/core/components/pg_label_image.dart';
import 'package:pharmaguide/core/components/pg_pill_button.dart';
import 'package:pharmaguide/core/components/pg_product_hero.dart';
import 'package:pharmaguide/core/components/pg_score_ring.dart';
import 'package:pharmaguide/core/components/pg_section_header.dart';
import 'package:pharmaguide/core/components/pg_severity_badge.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_motion.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/features/product_detail/v2/product_detail_v2_fixtures.dart';

/// v2 Product Detail prototype screen.
///
/// Loads a [ProductDetailFixture] (mock data — no provider coupling in
/// Phase 1). See `product_detail_v2_spec.dart` for the full design contract.
///
/// Section order (each section has ONE job):
/// 1. Hero (image + name + brand + meta)
/// 2. Key Takeaway (severity badge + verdict + score ring + explain + CTA)
/// 3. Your Fit
/// 4. Active Ingredients
/// 5. Inactive Ingredients
/// 6. Label & Source Data
class ProductDetailV2Screen extends StatelessWidget {
  final String fixtureId;

  const ProductDetailV2Screen({super.key, this.fixtureId = 'normal'});

  @override
  Widget build(BuildContext context) {
    final fixture = ProductDetailFixtures.byId(fixtureId);

    return Scaffold(
      backgroundColor: V2Colors.bg,
      appBar: AppBar(
        backgroundColor: V2Colors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: const BackButton(color: V2Colors.fg),
        title: PGEyebrow(fixtureId, color: V2Colors.fgMuted),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          V2Spacing.space24,
          V2Spacing.space8,
          V2Spacing.space24,
          V2Spacing.space48,
        ),
        children: [
          PGProductHero(
            productName: fixture.productName,
            brand: fixture.brand,
            form: fixture.form,
            servingSize: fixture.servingSize,
            imageUrl: fixture.imageUrl,
          ),
          const SizedBox(height: V2Spacing.space32),
          _KeyTakeawayCard(fixture: fixture),
          const SizedBox(height: V2Spacing.space32),
          _YourFitCard(fixture: fixture),
          const SizedBox(height: V2Spacing.space32),
          PGIngredientStack(
            eyebrow: 'Active Ingredients',
            ingredients: fixture.activeIngredients,
          ),
          const SizedBox(height: V2Spacing.space32),
          PGIngredientStack(
            eyebrow: 'Inactive Ingredients',
            ingredients: fixture.inactiveIngredients,
          ),
          const SizedBox(height: V2Spacing.space32),
          const PGSectionHeader(
            eyebrow: 'Label & Source',
            title: 'Supplement Facts',
          ),
          const SizedBox(height: V2Spacing.space16),
          PGLabelImage(imageUrl: fixture.labelImageUrl),
        ],
      ),
    );
  }
}

/// Sticky-hero "Key Takeaway" card — severity badge, verdict, explainer,
/// score ring, primary CTA.
///
/// **Layout decisions:**
/// - Score ring on the right (visual anchor)
/// - Severity badge top-left (immediate scan-ability)
/// - Verdict label below badge — Geist Sans 18pt (`bodyXl`)
/// - Explanation in body 16pt
/// - Primary CTA stretches at the bottom (`expand: true`)
/// - Shadow: sm (subtle lift, not floating)
class _KeyTakeawayCard extends StatelessWidget {
  final ProductDetailFixture fixture;
  const _KeyTakeawayCard({required this.fixture});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        padding: const EdgeInsets.all(V2Spacing.space24),
        decoration: BoxDecoration(
          color: V2Colors.surface,
          borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
          border: Border.all(color: V2Colors.outline),
          boxShadow: V2Shadows.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PGEyebrow('Key Takeaway'),
            const SizedBox(height: V2Spacing.space12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      PGSeverityBadge(
                        severity: fixture.topSeverity,
                        evidence: fixture.evidenceLabel,
                      ),
                      const SizedBox(height: V2Spacing.space16),
                      Text(
                        fixture.topVerdictLabel,
                        style: V2Typography.bodyXl(color: V2Colors.fg),
                        maxLines: 3,
                        softWrap: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: V2Spacing.space16),
                PGScoreRing(
                  score: fixture.pgScore,
                  size: 88,
                  caption: 'PG Score',
                ),
              ],
            ),
            const SizedBox(height: V2Spacing.space16),
            Text(
              fixture.topVerdictExplain,
              style: V2Typography.body(color: V2Colors.fgMuted),
            ),
            const SizedBox(height: V2Spacing.space24),
            PGPillButton(
              label: 'Add to Stack',
              icon: Icons.add_rounded,
              onPressed: () {},
              expand: true,
            ),
          ],
        ),
      ),
    );
  }
}

/// "Your Fit" card — personalized fit state (mock for Phase 1).
///
/// In production this binds to fit_score_provider. The prototype renders
/// a simple PGSectionHeader + body line.
class _YourFitCard extends StatelessWidget {
  final ProductDetailFixture fixture;
  const _YourFitCard({required this.fixture});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: V2Motion.fast,
      padding: const EdgeInsets.all(V2Spacing.space24),
      decoration: BoxDecoration(
        color: V2Colors.surface,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        border: Border.all(color: V2Colors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PGEyebrow('Your Fit'),
          const SizedBox(height: V2Spacing.space12),
          Text(
            fixture.fitState,
            style: V2Typography.bodyXl(color: V2Colors.fg),
          ),
        ],
      ),
    );
  }
}
