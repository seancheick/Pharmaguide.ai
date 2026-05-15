import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/components/pg_hero_section.dart';
import 'package:pharmaguide/core/components/pg_ingredient_data.dart';
import 'package:pharmaguide/core/components/pg_ingredient_tile.dart';
import 'package:pharmaguide/core/components/pg_ingredients_card.dart';
import 'package:pharmaguide/core/components/pg_personal_fit_card.dart';
import 'package:pharmaguide/core/components/pg_review_before_use_card.dart';
import 'package:pharmaguide/core/components/pg_score_line.dart';
import 'package:pharmaguide/core/theme/v2/v2.dart';
import 'package:pharmaguide/features/product_detail/widgets/inactive_color.dart';
import 'package:pharmaguide/features/product_detail/widgets/ingredient_explain_model.dart';
import 'package:pharmaguide/services/fit_score/fit_display.dart';

/// v2 component gallery — debug-only route at `/dev/v2`.
///
/// Phase 8.1.0 cleanup (2026-05-14): retired the Product Detail / Home /
/// Scanner / Stack / floating-shell prototypes that were built on
/// misbuilt primitives. Mirror-based rebuilds in Phase 8.1.1+ will
/// re-register their links here as they land.
class V2Gallery extends StatelessWidget {
  const V2Gallery({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: V2Colors.bg,
      appBar: AppBar(
        title: Text('v2 gallery', style: V2Typography.titleSm()),
        backgroundColor: V2Colors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(V2Spacing.space24),
        children: [
          _Section(
            title: 'Typography',
            children: [
              Text('Display 40pt serif', style: V2Typography.display()),
              const SizedBox(height: V2Spacing.space12),
              Text('Display Sm 32pt serif', style: V2Typography.displaySm()),
              const SizedBox(height: V2Spacing.space12),
              Text('Title 24pt sans 500', style: V2Typography.title()),
              const SizedBox(height: V2Spacing.space8),
              Text('Body 16pt sans 400', style: V2Typography.body()),
              const SizedBox(height: V2Spacing.space8),
              Text(
                'ACTIVE INGREDIENTS',
                style: V2Typography.eyebrow(color: V2Colors.accent),
              ),
              const SizedBox(height: V2Spacing.space4),
              Text(
                'ESTABLISHED',
                style: V2Typography.overline(color: V2Colors.fgMuted),
              ),
            ],
          ),
          const _Section(
            title: 'Color',
            children: [
              _ColorSwatch('bg', V2Colors.bg),
              _ColorSwatch('surface', V2Colors.surface),
              _ColorSwatch('accent', V2Colors.accent),
              _ColorSwatch('accentStrong', V2Colors.accentStrong),
            ],
          ),
          const _Section(
            title: 'Shadows',
            children: [
              _ShadowChip('sm', V2Shadows.sm),
              _ShadowChip('md', V2Shadows.md),
              _ShadowChip('lg', V2Shadows.lg),
            ],
          ),
          _Section(
            title: 'Score line · production parity',
            children: [
              Text(
                'Mirror of lib/features/product_detail/widgets/score_line.dart. '
                'Uses ScoreTier directly — locked colors + labels + descriptions.',
                style: V2Typography.bodySm(color: V2Colors.fgMuted),
              ),
              const SizedBox(height: V2Spacing.space16),
              for (final s in const [95, 84, 75, 65, 55, 30])
                Padding(
                  padding: const EdgeInsets.only(bottom: V2Spacing.space16),
                  child: Container(
                    padding: const EdgeInsets.all(V2Spacing.space16),
                    decoration: BoxDecoration(
                      color: V2Colors.surface,
                      borderRadius:
                          BorderRadius.circular(V2Spacing.radiusCard),
                      border: Border.all(color: V2Colors.outline),
                    ),
                    child: PGScoreLine(score: s),
                  ),
                ),
            ],
          ),
          _Section(
            title: 'Ingredients · production parity',
            children: [
              Text(
                'Mirror of `_IngredientTile` (active) + `_InactiveRow` + '
                '`IngredientsCard`. Same chip semantics, same auto-expand '
                '(≤5), same hairline rhythm.',
                style: V2Typography.bodySm(color: V2Colors.fgMuted),
              ),
              const SizedBox(height: V2Spacing.space16),
              const PGIngredientsCard(
                activeContent: PGActiveIngredientsSection(
                  tiles: [
                    PGActiveIngredientTile(
                      ingredient: PGActiveIngredient(
                        name: 'Magnesium Bisglycinate',
                        dose: '200 mg',
                        formLabel: 'Bisglycinate',
                        formQuality: FormQuality.excellent,
                        doseCallOut: DoseCallOut.withinLimits,
                      ),
                    ),
                    PGActiveIngredientTile(
                      ingredient: PGActiveIngredient(
                        name: 'Vitamin D3 (Cholecalciferol)',
                        dose: '1000 IU',
                        formLabel: 'Cholecalciferol',
                        formQuality: FormQuality.good,
                      ),
                    ),
                    PGActiveIngredientTile(
                      ingredient: PGActiveIngredient(
                        name: 'Magnesium Oxide',
                        dose: '400 mg',
                        formLabel: 'Oxide',
                        formQuality: FormQuality.poor,
                        doseCallOut: DoseCallOut.high,
                      ),
                    ),
                    PGActiveIngredientTile(
                      ingredient: PGActiveIngredient(
                        name: 'Vitamin B12',
                        dose: '500 mcg',
                        formLabel: 'Cyanocobalamin',
                        formQuality: FormQuality.fair,
                        doseCallOut: DoseCallOut.low,
                      ),
                    ),
                    PGActiveIngredientTile(
                      ingredient: PGActiveIngredient(
                        name: 'Proprietary Energy Blend',
                        dose: 'Amount not disclosed',
                        doseCallOut: DoseCallOut.notDisclosed,
                        isInferredFromLabel: true,
                      ),
                    ),
                    PGActiveIngredientTile(
                      ingredient: PGActiveIngredient(
                        name: 'Yohimbine HCl',
                        dose: '20 mg',
                        formLabel: 'Hydrochloride',
                        formQuality: FormQuality.good,
                        doseCallOut: DoseCallOut.high,
                        isSafetyConcern: true,
                      ),
                      showBottomDivider: false,
                    ),
                  ],
                ),
                inactiveIngredients: [
                  PGInactiveIngredient(
                    name: 'Hypromellose',
                    tone: InactiveTone.green,
                    roleHelper: 'Capsule shell',
                  ),
                  PGInactiveIngredient(
                    name: 'Microcrystalline cellulose',
                    tone: InactiveTone.green,
                    roleHelper: 'Bulking agent',
                  ),
                  PGInactiveIngredient(
                    name: 'Magnesium stearate',
                    tone: InactiveTone.yellow,
                    roleHelper: 'Flow agent · low concern',
                  ),
                  PGInactiveIngredient(
                    name: 'Titanium dioxide',
                    tone: InactiveTone.orange,
                    roleHelper: 'Colorant · flagged (EU banned)',
                  ),
                  PGInactiveIngredient(
                    name: 'Red 40 (Allura Red)',
                    tone: InactiveTone.red,
                    roleHelper: 'Synthetic colorant',
                  ),
                  PGInactiveIngredient(
                    name: 'Silicon dioxide',
                    tone: InactiveTone.yellow,
                    roleHelper: 'Anti-caking',
                  ),
                ],
              ),
            ],
          ),
          _Section(
            title: 'Product Detail top sections (Phase 8.1.3)',
            children: [
              Text(
                'Hero + Personal Fit + Review Before Use, stacked in '
                'production scroll order. Same data shape, v2 surface + '
                'typography.',
                style: V2Typography.bodySm(color: V2Colors.fgMuted),
              ),
              const SizedBox(height: V2Spacing.space16),
              // Hero
              const PGHeroSection(
                imageWidget: _DemoProductImage(),
                productName: 'High-Potency Triple-Strength Marine Omega-3',
                brandName: 'Nordic Naturals',
                servingsLabel: '60 Softgels',
                dosingSummary: '2 softgels daily with food',
                trustTags: [
                  PGTrustTag(label: 'IFOS Certified', isCertification: true),
                  PGTrustTag(label: 'Non-GMO', isCertification: false),
                  PGTrustTag(label: 'Gluten Free', isCertification: false),
                ],
                score: 84,
              ),
              const SizedBox(height: V2Spacing.space12),
              // Personal Fit
              PGPersonalFitCard(
                fit: const FitGoodMatch(),
                headline: 'Good match for your heart-health goal',
                bullets: const [
                  'Omega-3 supports your cardiovascular goal',
                  'No conflicts with your current medications',
                ],
                onEditProfile: () {},
              ),
              const SizedBox(height: V2Spacing.space12),
              // Review Before Use — caution example
              PGReviewBeforeUseCard(
                tone: PGReviewTone.caution,
                title: 'Review before use',
                body: '2 things to check with your prescriber.',
                rows: [
                  PGReviewRow(
                    headline: 'May extend bleeding time',
                    caption: 'Caution with warfarin / rivaroxaban',
                    onTap: () {},
                  ),
                  PGReviewRow(
                    headline: 'Contains fish (anchovy, sardine)',
                    caption: 'Allergen · matched from your profile',
                    rowTone: PGReviewTone.danger,
                    onTap: () {},
                  ),
                ],
                startExpanded: true,
              ),
            ],
          ),
          const _Section(
            title: 'First-impression moments',
            children: [
              _PrototypeLink(
                label: 'Splash',
                subtitle: 'Editorial brand-moment entrance',
                routePath: '/dev/v2/splash',
              ),
              _PrototypeLink(
                label: 'Onboarding',
                subtitle: '4-step intro with serif headlines + celebration',
                routePath: '/dev/v2/onboarding',
              ),
            ],
          ),
          const _Section(
            title: 'Settings',
            children: [
              _PrototypeLink(
                label: 'Settings',
                subtitle: 'Avatar hero · hairline groups · calm controls',
                routePath: '/dev/v2/settings',
              ),
              _PrototypeLink(
                label: 'Settings (signed-in)',
                subtitle: 'Signed-in account variant',
                routePath: '/dev/v2/settings?signedIn=1',
              ),
            ],
          ),
          const _Section(
            title: 'In progress — Phase 8.1',
            children: [
              _GalleryNote(
                text:
                    'Product Detail, Home, Scanner, Stack v2 are being '
                    'rebuilt as visual mirrors of production widgets. '
                    'Routes will return here as each lands.',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PrototypeLink extends StatelessWidget {
  final String label;
  final String subtitle;
  final String routePath;

  const _PrototypeLink({
    required this.label,
    required this.subtitle,
    required this.routePath,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: V2Spacing.space8),
      child: Material(
        color: V2Colors.surface,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        child: InkWell(
          onTap: () => context.go(routePath),
          borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
          child: Container(
            padding: const EdgeInsets.all(V2Spacing.space16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
              border: Border.all(color: V2Colors.outline),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label.toUpperCase(),
                        style: V2Typography.eyebrow(color: V2Colors.accent),
                      ),
                      const SizedBox(height: V2Spacing.space4),
                      Text(
                        subtitle,
                        style: V2Typography.body(color: V2Colors.fg),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: V2Colors.fgMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GalleryNote extends StatelessWidget {
  final String text;
  const _GalleryNote({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(V2Spacing.space16),
      decoration: BoxDecoration(
        color: V2Colors.accentTint.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
      ),
      child: Text(text, style: V2Typography.bodySm(color: V2Colors.fg)),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: V2Spacing.space48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: V2Typography.eyebrow(color: V2Colors.accent),
          ),
          const SizedBox(height: V2Spacing.space12),
          ...children,
        ],
      ),
    );
  }
}

/// Placeholder product image for the gallery hero preview — solid
/// accent-tint square with a pill icon. Production passes a real
/// [ProductImage] widget here.
class _DemoProductImage extends StatelessWidget {
  const _DemoProductImage();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: V2Colors.accentTint,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        border: Border.all(color: V2Colors.outline),
      ),
      child: const Icon(
        Icons.medication_outlined,
        size: 40,
        color: V2Colors.accent,
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  final String name;
  final Color color;
  const _ColorSwatch(this.name, this.color);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: V2Spacing.space8),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
              border: Border.all(color: V2Colors.outline),
            ),
          ),
          const SizedBox(width: V2Spacing.space16),
          Text(name, style: V2Typography.body()),
        ],
      ),
    );
  }
}

class _ShadowChip extends StatelessWidget {
  final String label;
  final List<BoxShadow> shadow;
  const _ShadowChip(this.label, this.shadow);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: V2Spacing.space16),
      child: Container(
        padding: const EdgeInsets.all(V2Spacing.space16),
        decoration: BoxDecoration(
          color: V2Colors.surface,
          borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
          boxShadow: shadow,
        ),
        child: Text(label, style: V2Typography.body()),
      ),
    );
  }
}
