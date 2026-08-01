import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pharmaguide/core/components/pg_better_alternatives.dart';
import 'package:pharmaguide/core/components/pg_certification_section.dart';
import 'package:pharmaguide/core/components/pg_evidence_section.dart';
import 'package:pharmaguide/core/components/pg_formulation_section.dart';
import 'package:pharmaguide/core/components/pg_heavy_metal_warning.dart';
import 'package:pharmaguide/core/components/pg_hero_section.dart';
import 'package:pharmaguide/core/components/pg_ingredient_data.dart';
import 'package:pharmaguide/core/components/pg_ingredient_tile.dart';
import 'package:pharmaguide/core/components/pg_ingredients_card.dart';
import 'package:pharmaguide/core/components/pg_interaction_warnings.dart';
import 'package:pharmaguide/core/components/pg_label_confidence_card.dart';
import 'package:pharmaguide/core/components/pg_manufacturer_violations_section.dart';
import 'package:pharmaguide/core/components/pg_nutrition_panel.dart';
import 'package:pharmaguide/core/components/pg_personal_fit_card.dart';
import 'package:pharmaguide/core/components/pg_populations_section.dart';
import 'package:pharmaguide/core/components/pg_probiotic_section.dart';
import 'package:pharmaguide/core/components/pg_review_before_use_card.dart';
import 'package:pharmaguide/core/components/pg_score_breakdown_card.dart';
import 'package:pharmaguide/core/components/pg_score_line.dart';
import 'package:pharmaguide/core/components/pg_toast.dart';
import 'package:pharmaguide/core/components/pg_tradeoffs_section.dart';
import 'package:pharmaguide/core/components/pg_transparency_footer.dart';
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
      appBar: AppBar(
        title: Text('v2 gallery', style: V2Typography.titleSm()),
        backgroundColor: context.v2.bg,
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
                style: V2Typography.eyebrow(color: context.v2.accent),
              ),
              const SizedBox(height: V2Spacing.space4),
              Text(
                'ESTABLISHED',
                style: V2Typography.overline(color: context.v2.fgMuted),
              ),
            ],
          ),
          _Section(
            title: 'Color',
            children: [
              _ColorSwatch('bg', context.v2.bg),
              _ColorSwatch('surface', context.v2.surface),
              _ColorSwatch('accent', context.v2.accent),
              _ColorSwatch('accentStrong', context.v2.accentStrong),
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
                'Uses ScoreTier directly — locked colors + labels + descriptions.',
                style: V2Typography.bodySm(color: context.v2.fgMuted),
              ),
              const SizedBox(height: V2Spacing.space16),
              for (final s in const [95, 84, 75, 65, 55, 30])
                Padding(
                  padding: const EdgeInsets.only(bottom: V2Spacing.space16),
                  child: Container(
                    padding: const EdgeInsets.all(V2Spacing.space16),
                    decoration: BoxDecoration(
                      color: context.v2.surface,
                      borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
                      border: Border.all(color: context.v2.outline),
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
                'Canonical ingredients card — active tile, inactive row, '
                'auto-expand (≤5), hairline rhythm.',
                style: V2Typography.bodySm(color: context.v2.fgMuted),
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
                style: V2Typography.bodySm(color: context.v2.fgMuted),
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
              // Review Before Use — auto-expanded because one row is
              // danger-tier (the fish allergen match). Banner tone stays
              // caution; the row inside still renders danger-tinted —
              // mirrors production "allergen match always bumps row to
              // danger even inside a calmer card" rule.
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
              ),
              const SizedBox(height: V2Spacing.space12),
              // Review Before Use — clean state. No danger rows, so the
              // card auto-collapses to banner-only; tap the chevron to
              // reveal the rows. Mirrors production's "calm by default,
              // expand on demand" behavior for non-danger findings.
              PGReviewBeforeUseCard(
                tone: PGReviewTone.safe,
                title: 'Looks safe for you',
                body: 'No conflicts with your medications or conditions.',
                rows: [
                  PGReviewRow(
                    headline: 'Gluten-free claim verified',
                    caption: 'Matches your dietary preference',
                    rowTone: PGReviewTone.safe,
                    onTap: () {},
                  ),
                  PGReviewRow(
                    headline: 'No interactions with your stack',
                    caption: 'Cross-checked against 6 supplements',
                    rowTone: PGReviewTone.safe,
                    onTap: () {},
                  ),
                ],
              ),
            ],
          ),
          _Section(
            title: 'Product Detail mid sections (Phase 8.1.4)',
            children: [
              Text(
                'Score Breakdown · Interaction Warnings · Label '
                'Confidence — the next 3 sliver positions on production '
                'scroll. Same data shape, v2 surface + typography.',
                style: V2Typography.bodySm(color: context.v2.fgMuted),
              ),
              const SizedBox(height: V2Spacing.space16),
              // 1. Score Breakdown — v4 six-pillar native scale
              PGScoreBreakdownCard(
                heroScore: 87.3,
                pillars: [
                  PGPillar(
                    label: 'Formulation',
                    microExplanation: 'Form, dosage, and bioavailability',
                    score: 17.6,
                    max: 20,
                    onTap: () {},
                  ),
                  PGPillar(
                    label: 'Dose',
                    microExplanation: 'Serving strength and studied ranges',
                    score: 16,
                    max: 20,
                    onTap: () {},
                  ),
                  PGPillar(
                    label: 'Evidence',
                    microExplanation: 'Clinical support behind ingredients',
                    score: 18.9,
                    max: 20,
                    onTap: () {},
                  ),
                  PGPillar(
                    label: 'Transparency',
                    microExplanation: 'Label clarity and disclosure',
                    score: 12.5,
                    max: 15,
                    onTap: () {},
                  ),
                  PGPillar(
                    label: 'Testing & Brand',
                    microExplanation: 'Independent testing and brand checks',
                    score: 13,
                    max: 15,
                    badges: [
                      PGPillarBadge(
                        icon: Icons.verified_outlined,
                        label: 'Third-party tested',
                        color: context.v2.safe,
                      ),
                      PGPillarBadge(
                        icon: Icons.factory_outlined,
                        label: 'Trusted manufacturer',
                        color: context.v2.safe,
                      ),
                    ],
                    onTap: () {},
                  ),
                  PGPillar(
                    label: 'Safety Hygiene',
                    microExplanation: 'Clean-label and contaminant risk checks',
                    score: 9.3,
                    max: 10,
                    onTap: () {},
                  ),
                ],
              ),
              const SizedBox(height: V2Spacing.space12),
              // 2. Interaction Warnings — personalized + generic
              PGInteractionWarnings(
                personalized: [
                  PGWarning(
                    severity: PGWarningSeverity.danger,
                    evidence: PGEvidenceLevel.established,
                    title: 'Major interaction with your blood thinner',
                    mechanism:
                        'Omega-3 fatty acids inhibit platelet aggregation '
                        'and can extend bleeding time. Combined with '
                        'warfarin or rivaroxaban, this raises the risk of '
                        'bleeding events — especially at doses above 3g '
                        'EPA + DHA per day.',
                    management:
                        'Discuss with your prescriber before adding. They '
                        'may want to monitor INR more frequently or adjust '
                        'your warfarin dose.',
                    sourceCount: 7,
                    onShowSources: () {},
                  ),
                  PGWarning(
                    severity: PGWarningSeverity.caution,
                    evidence: PGEvidenceLevel.moderate,
                    title: 'High-dose vitamin D + your kidney condition',
                    mechanism:
                        'High vitamin D intake increases calcium '
                        'absorption, which can stress kidneys in patients '
                        'with reduced glomerular filtration.',
                    management:
                        'Stay under 2000 IU/day. Monitor serum '
                        'calcium with your nephrologist.',
                    sourceCount: 4,
                    onShowSources: () {},
                  ),
                ],
                generic: [
                  PGWarning(
                    severity: PGWarningSeverity.safe,
                    evidence: PGEvidenceLevel.theoretical,
                    title: 'May reduce iron absorption when taken together',
                    mechanism:
                        'Some studies suggest omega-3 may slightly reduce '
                        'non-heme iron absorption.',
                    management: 'Take iron supplements 2 hours apart.',
                    sourceCount: 2,
                    onShowSources: () {},
                  ),
                ],
              ),
              const SizedBox(height: V2Spacing.space12),
              // 3. Label Confidence — calm caveat block
              PGLabelConfidenceCard(
                header: 'Limited data — partial coverage',
                items: [
                  PGLabelConfidenceItem(
                    icon: Icons.layers_outlined,
                    title: 'Contains a proprietary blend',
                    body:
                        'Per-ingredient amounts inside the blend aren\'t '
                        'disclosed by the manufacturer. The blend\'s total '
                        'is shown above.',
                    onTap: () {},
                  ),
                  const PGLabelConfidenceItem(
                    icon: Icons.help_outline_rounded,
                    title: '2 active ingredients aren\'t in our database',
                    body:
                        'Those ingredients couldn\'t be scored. The PG '
                        'Score above is based on the 5 that we recognize.',
                    detail: 'astaxanthin (1.2 mg) · sea-buckthorn oil (50 mg)',
                  ),
                ],
              ),
            ],
          ),
          _Section(
            title: 'Product Detail bottom sections (Phase 8.1.5)',
            children: [
              Text(
                'The remaining 11 sliver positions — same data shape '
                'as production, v2 surface + typography.',
                style: V2Typography.bodySm(color: context.v2.fgMuted),
              ),
              const SizedBox(height: V2Spacing.space16),
              // 1. Tradeoffs (Pros / What to consider)
              const PGTradeoffsSection(
                pros: [
                  PGTradeoff(
                    headline: 'IFOS-certified omega-3',
                    caption: 'Tested for purity',
                    points: 4,
                  ),
                  PGTradeoff(
                    headline: 'Vitamin K2 added for cardio synergy',
                    caption: 'Moderate evidence',
                    points: 2,
                  ),
                ],
                considerations: [
                  PGTradeoff(
                    headline: 'Higher dose than RDA',
                    caption: 'Monitor with prescriber',
                    points: -2,
                  ),
                  PGTradeoff(
                    headline: 'Contains soy lecithin',
                    caption: 'Common allergen',
                  ),
                ],
              ),
              const SizedBox(height: V2Spacing.space12),
              // 2. Populations to watch
              PGPopulationsSection(
                callouts: [
                  PGPopulationCallout(
                    icon: Icons.pregnant_woman_rounded,
                    label: 'Pregnancy & lactation',
                    body:
                        'Vitamin A retinyl form can be teratogenic at '
                        'high doses. Choose beta-carotene during these '
                        'life stages.',
                    onTap: () {},
                  ),
                  PGPopulationCallout(
                    icon: Icons.bloodtype_outlined,
                    label: 'Kidney disease',
                    body:
                        'High vitamin D increases calcium load on '
                        'kidneys with reduced GFR.',
                    onTap: () {},
                  ),
                ],
              ),
              const SizedBox(height: V2Spacing.space12),
              // 3. Nutrition Panel
              const PGNutritionPanel(
                caloriesPerServing: 10,
                servingSize: '2 softgels',
                facts: [
                  PGNutritionFact(
                    label: 'Total Fat',
                    value: '1 g',
                    dailyValue: '1%',
                    isHeadline: true,
                  ),
                  PGNutritionFact(
                    label: 'EPA',
                    value: '650 mg',
                    dailyValue: '—',
                  ),
                  PGNutritionFact(
                    label: 'DHA',
                    value: '450 mg',
                    dailyValue: '—',
                  ),
                  PGNutritionFact(
                    label: 'Vitamin D3',
                    value: '1000 IU',
                    dailyValue: '125%',
                  ),
                ],
              ),
              const SizedBox(height: V2Spacing.space12),
              // 4. Certifications
              const PGCertificationSection(
                certifications: [
                  PGCertification(
                    label: 'IFOS — 5-star purity',
                    verified: true,
                    caption: 'Tested for 200+ contaminants',
                  ),
                  PGCertification(
                    label: 'Non-GMO Project Verified',
                    verified: true,
                  ),
                  PGCertification(
                    label: 'USP Verified',
                    verified: false,
                    caption: 'Not enrolled in this program',
                  ),
                ],
              ),
              const SizedBox(height: V2Spacing.space12),
              // 5. Clinical evidence
              PGEvidenceSection(
                tier: PGEvidenceTier.strong,
                totalStudies: 12,
                hasMetaAnalysis: true,
                citations: [
                  PGCitation(
                    pmid: '34567890',
                    title:
                        'Omega-3 supplementation and cardiovascular '
                        'outcomes: a 2023 meta-analysis',
                    year: '2023',
                    onTap: () {},
                  ),
                  PGCitation(
                    pmid: '32123456',
                    title:
                        'EPA + DHA effects on triglycerides in adults '
                        'with metabolic syndrome',
                    year: '2021',
                    onTap: () {},
                  ),
                ],
              ),
              const SizedBox(height: V2Spacing.space12),
              // 6. Heavy metal risk
              PGHeavyMetalWarning(
                metals: const ['Mercury (trace)', 'Lead (trace)'],
                note:
                    'Within FDA action limits. Concentrations '
                    'detected during IFOS testing.',
                onTap: () {},
              ),
              const SizedBox(height: V2Spacing.space12),
              // 7. Formulation
              const PGFormulationSection(
                form: 'Triglyceride softgel',
                formTierLabel: 'Premium',
                absorptionEnhancers: [
                  'Phospholipid carrier',
                  'Vitamin E (antioxidant)',
                ],
                botanicals: ['Rosemary extract'],
              ),
              const SizedBox(height: V2Spacing.space12),
              // 8. Probiotic detail (typically conditional — this
              // product would not normally show this, but rendering
              // here so reviewers can see the section design)
              const PGProbioticSection(
                totalCfuLabel: '12 billion CFU',
                totalStrainCount: 5,
                hasSurvivabilityCoating: true,
                survivabilityReason: 'Delayed-release capsule',
                prebioticPresent: true,
                prebioticName: 'Inulin',
                strains: [
                  PGStrain(
                    name: 'L. acidophilus LA-5',
                    cfuLabel: '5 billion CFU',
                    supportLevel: 'high',
                    indication: 'Digestive support',
                    researchStatus: PGProbioticResearchStatus.exactStrain,
                    sourceUrls: ['https://pubmed.ncbi.nlm.nih.gov/'],
                  ),
                  PGStrain(
                    name: 'B. lactis BB-12',
                    cfuLabel: '4 billion CFU',
                    supportLevel: 'moderate',
                    indication: 'Regularity',
                    researchStatus: PGProbioticResearchStatus.formulaOnly,
                  ),
                  PGStrain(
                    name: 'S. thermophilus',
                    cfuLabel: '3 billion CFU',
                    researchStatus: PGProbioticResearchStatus.none,
                  ),
                ],
              ),
              const SizedBox(height: V2Spacing.space12),
              // 9. Manufacturer violations
              PGManufacturerViolationsSection(
                violations: [
                  PGViolation(
                    severity: PGReviewTone.danger,
                    type: 'GMP non-compliance',
                    date: 'Mar 2023',
                    trustSummary:
                        'FDA cited the facility for failing 5 of 9 '
                        'core GMP requirements during a routine '
                        'inspection. Most concerns centered on '
                        'documentation gaps.',
                    onTap: () {},
                  ),
                  PGViolation(
                    severity: PGReviewTone.caution,
                    type: 'Label inaccuracy',
                    date: 'Aug 2021',
                    trustSummary:
                        'Tested EPA content was 18% below label claim.',
                    onTap: () {},
                  ),
                ],
              ),
              const SizedBox(height: V2Spacing.space12),
              // 10. Better alternatives
              PGBetterAlternatives(
                body:
                    'Higher-scoring options in this category with '
                    'better fit for your profile.',
                alternatives: [
                  PGAlternative(
                    dsldId: 'alt-1',
                    brand: 'Carlson Labs',
                    name: 'Norwegian Omega-3 Fish Oil',
                    score: 92,
                    onTap: () {},
                  ),
                  PGAlternative(
                    dsldId: 'alt-2',
                    brand: 'NOW Foods',
                    name: 'Ultra Omega-3 with Vitamin D',
                    score: 87,
                    onTap: () {},
                  ),
                ],
              ),
              const SizedBox(height: V2Spacing.space12),
              // 11. Transparency footer
              const PGTransparencyFooter(
                freshnessLabel: 'Catalog updated 3 days ago',
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
              _PrototypeLink(
                label: 'Auth invitation',
                subtitle:
                    'Sign-in handoff after onboarding · magic link · '
                    'Apple · Google · skip',
                routePath: '/dev/v2/auth',
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
              _PrototypeLink(
                label: 'Profile setup (dashboard)',
                subtitle:
                    'Editable health profile · cream tile rows · '
                    'bottom-sheet selectors · greeting-ready nickname',
                routePath: '/dev/v2/profile-setup',
              ),
              _PrototypeLink(
                label: 'Profile wizard (first-time)',
                subtitle:
                    '3-step guided setup · nickname → basics '
                    '→ health context · runs once per install',
                routePath: '/dev/v2/profile-wizard',
              ),
              _PrototypeLink(
                label: 'Medication entry',
                subtitle:
                    'Search RxNorm · select medication · '
                    'class fallback sheet · dose + schedule',
                routePath: '/dev/v2/medication-entry',
              ),
              _PrototypeLink(
                label: 'Search',
                subtitle:
                    'Catalog search · on-market first · off-market '
                    'tail · quality + category chips · grid toggle',
                routePath: '/dev/v2/search',
              ),
              _PrototypeLink(
                label: 'Quick check',
                subtitle:
                    "Safe to take together? · pair lookup · "
                    'severity verdict · why + what to do',
                routePath: '/dev/v2/quick-check',
              ),
            ],
          ),
          const _Section(
            title: 'Flagship screens',
            children: [
              _PrototypeLink(
                label: 'Home',
                subtitle:
                    'Greeting · scan CTA · stack health · recent scans · '
                    'retinted nav bar',
                routePath: '/dev/v2/home',
              ),
              _PrototypeLink(
                label: 'Scanner',
                subtitle:
                    'Camera frame · 2-tone verdict flash · not-found '
                    'amber overlay (tap frame to cycle)',
                routePath: '/dev/v2/scan',
              ),
              _PrototypeLink(
                label: 'Camera permission',
                subtitle: 'Pre-prompt — benefit-first ask before the OS dialog',
                routePath: '/dev/v2/scan/permission',
              ),
              _PrototypeLink(
                label: 'Camera permission (denied)',
                subtitle: 'Denied state — Settings + manual fallback',
                routePath: '/dev/v2/scan/permission?denied=1',
              ),
              _PrototypeLink(
                label: 'Stack',
                subtitle:
                    'My stack · Wishlist tabs · summary card with status '
                    'tier · swipe-to-remove items',
                routePath: '/dev/v2/stack',
              ),
            ],
          ),
          const _Section(title: 'Auth tools', children: [_SignOutButton()]),
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

  // (See _SignOutButton at the bottom of this file for the gallery's
  // auth-testing affordance.)

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: V2Spacing.space8),
      child: Material(
        color: context.v2.surface,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        child: InkWell(
          onTap: () => context.go(routePath),
          borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
          child: Container(
            padding: const EdgeInsets.all(V2Spacing.space16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
              border: Border.all(color: context.v2.outline),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label.toUpperCase(),
                        style: V2Typography.eyebrow(color: context.v2.accent),
                      ),
                      const SizedBox(height: V2Spacing.space4),
                      Text(
                        subtitle,
                        style: V2Typography.body(color: context.v2.fg),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: context.v2.fgMuted),
              ],
            ),
          ),
        ),
      ),
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
            style: V2Typography.eyebrow(color: context.v2.accent),
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
        color: context.v2.accentTint,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        border: Border.all(color: context.v2.outline),
      ),
      child: Icon(
        Icons.medication_outlined,
        size: 40,
        color: context.v2.accent,
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
              border: Border.all(color: context.v2.outline),
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
          color: context.v2.surface,
          borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
          boxShadow: shadow,
        ),
        child: Text(label, style: V2Typography.body()),
      ),
    );
  }
}

/// Gallery-only affordance to flip back to the signed-out state for
/// testing the auth round-trip. Only enabled when there's a current
/// session — otherwise the tile shows "Not signed in" and stays
/// muted. Tapping it fires supabase.auth.signOut() which trips the
/// global _AuthEventListener → "Signed out" snackbar.
class _SignOutButton extends StatefulWidget {
  const _SignOutButton();

  @override
  State<_SignOutButton> createState() => _SignOutButtonState();
}

class _SignOutButtonState extends State<_SignOutButton> {
  StreamSubscription<dynamic>? _sub;
  String? _currentEmail;

  @override
  void initState() {
    super.initState();
    try {
      _currentEmail = Supabase.instance.client.auth.currentUser?.email;
      _sub = Supabase.instance.client.auth.onAuthStateChange.listen((_) {
        if (!mounted) return;
        setState(() {
          _currentEmail = Supabase.instance.client.auth.currentUser?.email;
        });
      });
    } on Object catch (_) {
      // Placeholder build — no auth available.
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _signOut() async {
    try {
      await Supabase.instance.client.auth.signOut();
    } on Object catch (_) {
      // _AuthEventListener doesn't fire on local-only sign-out
      // failures; surface inline so the tester knows.
      if (!mounted) return;
      PGToast.show(
        context,
        'Could not sign out — try again.',
        variant: PGToastVariant.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = _currentEmail != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: V2Spacing.space8),
      child: Material(
        color: context.v2.surface,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        child: InkWell(
          onTap: signedIn ? _signOut : null,
          borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
          child: Container(
            padding: const EdgeInsets.all(V2Spacing.space16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
              border: Border.all(color: context.v2.outline),
            ),
            child: Row(
              children: [
                Icon(
                  signedIn
                      ? Icons.logout_rounded
                      : Icons.person_outline_rounded,
                  color: signedIn ? context.v2.accent : context.v2.fgMuted,
                  size: 20,
                ),
                const SizedBox(width: V2Spacing.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        signedIn ? 'SIGN OUT' : 'NOT SIGNED IN',
                        style: V2Typography.eyebrow(
                          color: signedIn
                              ? context.v2.accent
                              : context.v2.fgMuted,
                        ),
                      ),
                      const SizedBox(height: V2Spacing.space4),
                      Text(
                        signedIn
                            ? _currentEmail!
                            : 'Sign in via the Auth invitation screen.',
                        style: V2Typography.body(color: context.v2.fg),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (signedIn)
                  Icon(Icons.chevron_right, color: context.v2.fgMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
