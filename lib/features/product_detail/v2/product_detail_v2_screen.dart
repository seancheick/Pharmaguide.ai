import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
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
import 'package:pharmaguide/core/components/pg_tradeoffs_section.dart';
import 'package:pharmaguide/core/components/pg_transparency_footer.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/features/product_detail/widgets/ingredient_explain_model.dart';
import 'package:pharmaguide/features/product_detail/widgets/inactive_color.dart';
import 'package:pharmaguide/services/fit_score/fit_display.dart';

/// v2 Product Detail screen — composes every section adapter into a
/// single scrollable screen. This is the canonical Product Detail
/// surface (the legacy `ProductDetailScreen` was retired in the
/// Phase 11.11 hygiene pass).
///
/// Fixture-driven. Production wiring (Phase 8 later) replaces the
/// fixtures with provider data — the COMPONENTS stay identical, only
/// the data adapters change.
///
/// Scroll order matches production:
///   1. AppBar (back + share)
///   2. PGHeroSection (image + name + brand + chips + ScoreLine)
///   3. PGPersonalFitCard (if !blocked)
///   4. PGReviewBeforeUseCard
///   5. PGScoreBreakdownCard
///   6. PGInteractionWarnings
///   7. PGIngredientsCard (active + inactive)
///   8. PGTradeoffsSection
///   9. PGPopulationsSection
///   10. PGNutritionPanel
///   11. PGCertificationSection
///   12. PGEvidenceSection
///   13. PGHeavyMetalWarning (conditional)
///   14. PGFormulationSection
///   15. PGProbioticSection (conditional)
///   16. PGManufacturerViolationsSection
///   17. PGBetterAlternatives (conditional)
///   18. PGTransparencyFooter
class ProductDetailV2Screen extends StatelessWidget {
  /// Fixture id — currently only 'omega-3' is wired (the canonical demo).
  /// Phase 8.2+ adds more fixtures (longName / contraindicated / missing
  /// data) for stress testing.
  final String fixtureId;

  const ProductDetailV2Screen({super.key, this.fixtureId = 'omega-3'});

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: V2Colors.bg,
        body: CustomScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            // App bar
            SliverAppBar(
              backgroundColor: V2Colors.bg,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              pinned: false,
              floating: true,
              snap: true,
              leading: IconButton(
                icon: const Icon(
                  Icons.arrow_back_rounded,
                  color: V2Colors.fg,
                ),
                // **Sentry fix — 21× `GoError: There is nothing to pop`.**
                // Dev gallery deep links land here without a stack;
                // fall back to home instead of throwing.
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go(Routes.home);
                  }
                },
              ),
              actions: [
                IconButton(
                  icon: const Icon(
                    Icons.ios_share_rounded,
                    color: V2Colors.fg,
                  ),
                  onPressed: () {},
                ),
              ],
            ),

            // Body — each section gets 12pt bottom padding for the
            // editorial rhythm Sean approved on the gallery preview.
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                V2Spacing.space16,
                0,
                V2Spacing.space16,
                mq.padding.bottom + V2Spacing.space24,
              ),
              sliver: SliverList.list(
                children: const [
                  // 1. Hero
                  PGHeroSection(
                    imageWidget: _DemoHeroImage(),
                    productName:
                        'Ultimate Omega 2X with Vitamin D3 + K2',
                    brandName: 'Nordic Naturals',
                    servingsLabel: '60 Softgels',
                    dosingSummary: '2 softgels daily with food',
                    trustTags: [
                      PGTrustTag(
                        label: 'IFOS Certified',
                        isCertification: true,
                      ),
                      PGTrustTag(
                        label: 'Non-GMO',
                        isCertification: false,
                      ),
                      PGTrustTag(
                        label: 'Gluten Free',
                        isCertification: false,
                      ),
                    ],
                    score: 84,
                  ),
                  SizedBox(height: V2Spacing.space12),

                  // 2. Personal Fit
                  _DemoPersonalFit(),
                  SizedBox(height: V2Spacing.space12),

                  // 3. Review Before Use
                  _DemoReviewBeforeUse(),
                  SizedBox(height: V2Spacing.space12),

                  // 4. Score Breakdown
                  _DemoScoreBreakdown(),
                  SizedBox(height: V2Spacing.space12),

                  // 5. Interaction Warnings
                  _DemoInteractionWarnings(),
                  SizedBox(height: V2Spacing.space12),

                  // 6. Label Confidence (calm caveat block — only
                  // renders when there's coverage to flag; here we
                  // surface partial coverage for design preview)
                  _DemoLabelConfidence(),
                  SizedBox(height: V2Spacing.space12),

                  // 7. Ingredients
                  _DemoIngredients(),
                  SizedBox(height: V2Spacing.space12),

                  // 7. Tradeoffs
                  _DemoTradeoffs(),
                  SizedBox(height: V2Spacing.space12),

                  // 8. Populations
                  _DemoPopulations(),
                  SizedBox(height: V2Spacing.space12),

                  // 9. Nutrition
                  _DemoNutrition(),
                  SizedBox(height: V2Spacing.space12),

                  // 10. Certifications
                  _DemoCertifications(),
                  SizedBox(height: V2Spacing.space12),

                  // 11. Evidence
                  _DemoEvidence(),
                  SizedBox(height: V2Spacing.space12),

                  // 12. Heavy metal warning
                  _DemoHeavyMetal(),
                  SizedBox(height: V2Spacing.space12),

                  // 13. Formulation
                  _DemoFormulation(),
                  SizedBox(height: V2Spacing.space12),

                  // 14. Probiotic (conditional — this product has no
                  // probiotics; rendering for design preview only.
                  // Production: hide when no strains/CFU data)
                  _DemoProbiotic(),
                  SizedBox(height: V2Spacing.space12),

                  // 15. Manufacturer violations
                  _DemoViolations(),
                  SizedBox(height: V2Spacing.space12),

                  // 16. Better alternatives
                  _DemoBetterAlternatives(),
                  SizedBox(height: V2Spacing.space12),

                  // 17. Transparency footer
                  PGTransparencyFooter(
                    freshnessLabel: 'Catalog updated 3 days ago',
                  ),
                ],
              ),
            ),

            // Bottom safe-area extender so the sticky action bar
            // (when wired in Phase 8.x) doesn't overlap the footer.
            const SliverToBoxAdapter(
              child: SizedBox(height: V2Spacing.space24),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Section fixtures — each wraps one of the 17 v2 components with realistic
// Omega-3 data. Phase 8.2+ refactors these into a typed fixture model
// (so multiple products can render through the same screen).
// =============================================================================

class _DemoHeroImage extends StatelessWidget {
  const _DemoHeroImage();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: V2Colors.accentTint,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
      ),
      alignment: Alignment.center,
      child: const Icon(
        Icons.medication_outlined,
        size: 44,
        color: V2Colors.accent,
      ),
    );
  }
}

class _DemoPersonalFit extends StatelessWidget {
  const _DemoPersonalFit();

  @override
  Widget build(BuildContext context) {
    return PGPersonalFitCard(
      fit: const FitGoodMatch(),
      headline: 'Good match for your heart-health goal',
      bullets: const [
        'Omega-3 supports your cardiovascular goal',
        'No conflicts with your current medications',
      ],
      onEditProfile: () {},
    );
  }
}

class _DemoReviewBeforeUse extends StatelessWidget {
  const _DemoReviewBeforeUse();

  @override
  Widget build(BuildContext context) {
    return PGReviewBeforeUseCard(
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
    );
  }
}

class _DemoScoreBreakdown extends StatelessWidget {
  const _DemoScoreBreakdown();

  @override
  Widget build(BuildContext context) {
    return PGScoreBreakdownCard(
      heroScore: 84,
      mappedCoverage: 0.78,
      pillars: [
        PGPillar(
          label: 'Ingredient Quality',
          microExplanation: 'Form, dosage, and bioavailability',
          score: 22,
          max: 25,
          onTap: () {},
        ),
        PGPillar(
          label: 'Safety & Purity',
          microExplanation:
              'Free from harmful ingredients and contaminants',
          score: 26,
          max: 30,
          badges: const [
            PGPillarBadge(
              icon: Icons.verified_outlined,
              label: 'Third-party tested',
              color: AppTheme.severitySafe,
            ),
          ],
          onTap: () {},
        ),
        PGPillar(
          label: 'Evidence & Research',
          microExplanation: 'Clinical support behind ingredients',
          score: 14,
          max: 20,
          onTap: () {},
        ),
        PGPillar(
          label: 'Transparency & Verification',
          microExplanation: 'Label clarity and independent testing',
          score: 4,
          max: 5,
          badges: const [
            PGPillarBadge(
              icon: Icons.factory_outlined,
              label: 'Trusted manufacturer',
              color: AppTheme.severitySafe,
            ),
          ],
          onTap: () {},
        ),
      ],
    );
  }
}

class _DemoInteractionWarnings extends StatelessWidget {
  const _DemoInteractionWarnings();

  @override
  Widget build(BuildContext context) {
    return PGInteractionWarnings(
      personalized: [
        PGWarning(
          severity: PGWarningSeverity.danger,
          evidence: PGEvidenceLevel.established,
          title: 'Major interaction with your blood thinner',
          mechanism:
              'Omega-3 fatty acids inhibit platelet aggregation and '
              'can extend bleeding time. Combined with warfarin or '
              'rivaroxaban, this raises the risk of bleeding events — '
              'especially at doses above 3g EPA + DHA per day.',
          management:
              'Discuss with your prescriber before adding. They may '
              'want to monitor INR more frequently or adjust your '
              'warfarin dose.',
          sourceCount: 7,
          onShowSources: () {},
        ),
      ],
      generic: [
        PGWarning(
          severity: PGWarningSeverity.safe,
          evidence: PGEvidenceLevel.theoretical,
          title: 'May reduce iron absorption when taken together',
          mechanism: 'Some studies suggest omega-3 may slightly reduce '
              'non-heme iron absorption.',
          management: 'Take iron supplements 2 hours apart.',
          sourceCount: 2,
          onShowSources: () {},
        ),
      ],
    );
  }
}

class _DemoLabelConfidence extends StatelessWidget {
  const _DemoLabelConfidence();

  @override
  Widget build(BuildContext context) {
    return PGLabelConfidenceCard(
      header: 'Limited data — partial coverage',
      items: [
        PGLabelConfidenceItem(
          icon: Icons.layers_outlined,
          title: 'Contains a proprietary blend',
          body:
              "Per-ingredient amounts inside the blend aren't disclosed "
              "by the manufacturer. The blend's total is shown above.",
          onTap: () {},
        ),
        const PGLabelConfidenceItem(
          icon: Icons.help_outline_rounded,
          title: "2 active ingredients aren't in our database",
          body:
              'Those ingredients could not be scored. The PG Score '
              'above is based on the 5 that we recognize.',
          detail: 'astaxanthin (1.2 mg) · sea-buckthorn oil (50 mg)',
        ),
      ],
    );
  }
}

class _DemoIngredients extends StatelessWidget {
  const _DemoIngredients();

  @override
  Widget build(BuildContext context) {
    return const PGIngredientsCard(
      activeContent: PGActiveIngredientsSection(
        tiles: [
          PGActiveIngredientTile(
            ingredient: PGActiveIngredient(
              name: 'EPA (eicosapentaenoic acid)',
              dose: '650 mg',
              formLabel: 'Triglyceride',
              formQuality: FormQuality.excellent,
              doseCallOut: DoseCallOut.withinLimits,
            ),
          ),
          PGActiveIngredientTile(
            ingredient: PGActiveIngredient(
              name: 'DHA (docosahexaenoic acid)',
              dose: '450 mg',
              formLabel: 'Triglyceride',
              formQuality: FormQuality.excellent,
              doseCallOut: DoseCallOut.withinLimits,
            ),
          ),
          PGActiveIngredientTile(
            ingredient: PGActiveIngredient(
              name: 'Vitamin D3 (cholecalciferol)',
              dose: '1000 IU',
              formLabel: 'Cholecalciferol',
              formQuality: FormQuality.good,
              doseCallOut: DoseCallOut.withinLimits,
            ),
            showBottomDivider: false,
          ),
        ],
      ),
      inactiveIngredients: [
        PGInactiveIngredient(
          name: 'Gelatin',
          tone: InactiveTone.green,
          roleHelper: 'Capsule shell',
        ),
        PGInactiveIngredient(
          name: 'Glycerin',
          tone: InactiveTone.green,
          roleHelper: 'Plasticizer',
        ),
        PGInactiveIngredient(
          name: 'Soy lecithin',
          tone: InactiveTone.yellow,
          roleHelper: 'Emulsifier · common allergen',
        ),
        PGInactiveIngredient(
          name: 'Mixed tocopherols',
          tone: InactiveTone.green,
          roleHelper: 'Antioxidant',
        ),
      ],
    );
  }
}

class _DemoTradeoffs extends StatelessWidget {
  const _DemoTradeoffs();

  @override
  Widget build(BuildContext context) {
    return const PGTradeoffsSection(
      pros: [
        PGTradeoff(
          headline: 'IFOS-certified purity',
          caption: 'Tested for 200+ contaminants',
        ),
        PGTradeoff(
          headline: 'Triglyceride form',
          caption: 'Better absorption than ethyl ester',
        ),
        PGTradeoff(
          headline: 'Vitamin K2 added for cardio synergy',
          caption: 'Moderate evidence',
        ),
      ],
      considerations: [
        PGTradeoff(
          headline: 'Contains soy lecithin',
          caption: 'Common allergen',
        ),
        PGTradeoff(
          headline: 'Higher dose than RDA',
          caption: 'Monitor with prescriber',
        ),
      ],
    );
  }
}

class _DemoPopulations extends StatelessWidget {
  const _DemoPopulations();

  @override
  Widget build(BuildContext context) {
    return PGPopulationsSection(
      callouts: [
        PGPopulationCallout(
          icon: Icons.pregnant_woman_rounded,
          label: 'Pregnancy & lactation',
          body:
              'High-dose vitamin D may need adjustment. Coordinate with '
              'your OB.',
          onTap: () {},
        ),
        PGPopulationCallout(
          icon: Icons.bloodtype_outlined,
          label: 'On blood thinners',
          body: 'Omega-3 extends bleeding time — see the warning above.',
          onTap: () {},
        ),
      ],
    );
  }
}

class _DemoNutrition extends StatelessWidget {
  const _DemoNutrition();

  @override
  Widget build(BuildContext context) {
    return const PGNutritionPanel(
      caloriesPerServing: 10,
      servingSize: '2 softgels',
      facts: [
        PGNutritionFact(
          label: 'Total Fat',
          value: '1 g',
          dailyValue: '1%',
          isHeadline: true,
        ),
        PGNutritionFact(label: 'EPA', value: '650 mg', dailyValue: '—'),
        PGNutritionFact(label: 'DHA', value: '450 mg', dailyValue: '—'),
        PGNutritionFact(
          label: 'Vitamin D3',
          value: '1000 IU',
          dailyValue: '125%',
        ),
        PGNutritionFact(
          label: 'Vitamin K2 (MK-7)',
          value: '45 mcg',
          dailyValue: '38%',
        ),
      ],
    );
  }
}

class _DemoCertifications extends StatelessWidget {
  const _DemoCertifications();

  @override
  Widget build(BuildContext context) {
    return const PGCertificationSection(
      certifications: [
        PGCertification(
          label: 'IFOS — 5-star purity',
          verified: true,
          caption: 'Tested for 200+ contaminants',
        ),
        PGCertification(label: 'Non-GMO Project Verified', verified: true),
        PGCertification(
          label: 'USP Verified',
          verified: false,
          caption: 'Not enrolled in this program',
        ),
      ],
    );
  }
}

class _DemoEvidence extends StatelessWidget {
  const _DemoEvidence();

  @override
  Widget build(BuildContext context) {
    return PGEvidenceSection(
      tier: PGEvidenceTier.strong,
      totalStudies: 12,
      hasMetaAnalysis: true,
      citations: [
        PGCitation(
          pmid: '34567890',
          title:
              'Omega-3 supplementation and cardiovascular outcomes: a '
              '2023 meta-analysis',
          year: '2023',
          onTap: () {},
        ),
        PGCitation(
          pmid: '32123456',
          title:
              'EPA + DHA effects on triglycerides in adults with '
              'metabolic syndrome',
          year: '2021',
          onTap: () {},
        ),
      ],
    );
  }
}

class _DemoHeavyMetal extends StatelessWidget {
  const _DemoHeavyMetal();

  @override
  Widget build(BuildContext context) {
    return PGHeavyMetalWarning(
      metals: const ['Mercury (trace)', 'Lead (trace)'],
      note: 'Within FDA action limits. Detected during IFOS testing.',
      onTap: () {},
    );
  }
}

class _DemoFormulation extends StatelessWidget {
  const _DemoFormulation();

  @override
  Widget build(BuildContext context) {
    return const PGFormulationSection(
      form: 'Triglyceride softgel',
      formTierLabel: 'Premium',
      absorptionEnhancers: [
        'Phospholipid carrier',
        'Vitamin E (antioxidant)',
      ],
      botanicals: ['Rosemary extract'],
    );
  }
}

class _DemoProbiotic extends StatelessWidget {
  const _DemoProbiotic();

  @override
  Widget build(BuildContext context) {
    // This product doesn't have probiotics in reality; renders this
    // section for the design preview so reviewers can see the layout.
    // Production hides it when no CFU data is present.
    return const PGProbioticSection(
      totalCfuLabel: '12 billion CFU',
      totalStrainCount: 3,
      hasSurvivabilityCoating: true,
      survivabilityReason: 'Delayed-release capsule',
      strains: [
        PGStrain(
          name: 'L. acidophilus LA-5',
          cfuLabel: '5 billion CFU',
          evidence: 'ESTABLISHED',
          isClinical: true,
        ),
        PGStrain(
          name: 'B. lactis BB-12',
          cfuLabel: '4 billion CFU',
          evidence: 'MODERATE',
          isClinical: true,
        ),
        PGStrain(
          name: 'S. thermophilus',
          cfuLabel: '3 billion CFU',
          evidence: 'LIMITED',
        ),
      ],
    );
  }
}

class _DemoViolations extends StatelessWidget {
  const _DemoViolations();

  @override
  Widget build(BuildContext context) {
    return PGManufacturerViolationsSection(
      violations: [
        PGViolation(
          severity: PGReviewTone.caution,
          type: 'Label inaccuracy',
          date: 'Aug 2021',
          trustSummary:
              'Tested EPA content was 18% below label claim during '
              'a 2021 audit. Brand has since updated their analytical '
              'protocol.',
          onTap: () {},
        ),
      ],
    );
  }
}

class _DemoBetterAlternatives extends StatelessWidget {
  const _DemoBetterAlternatives();

  @override
  Widget build(BuildContext context) {
    return PGBetterAlternatives(
      body:
          'Higher-scoring options in this category with better fit '
          'for your profile.',
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
    );
  }
}
