// Phase 11.7b — Product Detail V2 Connected screen (orchestration only).
//
// Production-wired Product Detail v2. Takes a real `dsldId` and owns the
// provider watches + gating logic for every clinical/safety surface that
// fires on the production route.
//
// File responsibilities (Sean's directive — no second-gen monolith):
//   • Own state lifecycle: load product, hold scroll anchors, mount/unmount.
//   • Watch providers and assemble the inputs the section adapters need.
//   • Compose the screen's structure: app bar, sliver list, sticky CTA.
//   • Delegate gating to `gating.dart`, scroll behavior to
//     `scroll_anchors.dart`, warning compose to `warnings_pipeline.dart`,
//     section composition to `sections/<name>_section.dart`.
//
// What this file does NOT do:
//   • Inline gate logic (lives in `gating.dart`).
//   • Inline warning merge/filter (lives in `warnings_pipeline.dart`).
//   • Inline scroll anchor bookkeeping (lives in `scroll_anchors.dart`).
//   • Per-section model → prop mapping (lives in `sections/<name>.dart`).
//
// Ship sequence:
//   • 11.7b (THIS COMMIT) — orchestration + Hero + TransparencyFooter +
//     sticky CTA live. 14 mid-page sections are labeled placeholders.
//   • 11.7c–11.7f — each placeholder swaps for its real adapter, one
//     section adapter file at a time. The connected file gets shorter
//     as section adapter files multiply.
//   • 11.7g — production /product/:dsldId route flips over once
//     stakeholder review passes.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/components/pg_empty_state.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/core/utils/product_canonical_ids.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/product_detail/product_detail_helpers.dart'
    show topGoalLabelFromFit;
import 'package:pharmaguide/features/product_detail/providers/detail_blob_provider.dart';
import 'package:pharmaguide/features/product_detail/providers/fit_score_provider.dart';
import 'package:pharmaguide/features/product_detail/providers/personalized_warnings_provider.dart';
import 'package:pharmaguide/features/product_detail/v2/gating.dart';
import 'package:pharmaguide/features/product_detail/v2/scroll_anchors.dart';
import 'package:pharmaguide/features/product_detail/allergen_match.dart';
import 'package:pharmaguide/features/product_detail/free_from_match.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/allergen_summary_banner_section.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/better_alternatives_section.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/blocked_banner_helpers.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/blocked_banner_section.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/certifications_section.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/evidence_section.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/excipient_density_section.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/formulation_section.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/heavy_metal_section.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/hero_section.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/ingredients_section.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/label_confidence_section.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/manufacturer_violations_section.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/nutrition_section.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/personal_fit_section.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/populations_section.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/probiotic_section.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/research_evidence_section.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/review_before_use_section.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/score_breakdown_section.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/synergy_section.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/tradeoffs_section.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/transparency_footer_section.dart';
import 'package:pharmaguide/features/product_detail/v2/warnings_pipeline.dart';
import 'package:pharmaguide/features/product_detail/widgets/pg_stack_action_buttons.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';
import 'package:pharmaguide/services/fit_score/fit_display.dart';
import 'package:pharmaguide/services/sharing/share_service.dart';
import 'package:pharmaguide/services/warnings/condition_gate.dart';
import 'package:pharmaguide/services/warnings/interaction_warning.dart';

/// Production-wired v2 Product Detail screen.
///
/// Receives [dsldId] from route params (`/dev/v2/product/<dsldId>` during
/// the staged rollout; `/product/<dsldId>` once Phase 11.7g ratifies the
/// swap). Accepts the same `?section=` deep link as production so existing
/// links continue working when the route is later swapped.
class ProductDetailV2ConnectedScreen extends ConsumerStatefulWidget {
  final String dsldId;

  /// Optional anchor for `?section=` deep links. Accepts `'interactions'`,
  /// `'research'`, `'ingredients'`, or `'alternatives'`. Unknown values
  /// fall through.
  final String? initialSection;

  const ProductDetailV2ConnectedScreen({
    super.key,
    required this.dsldId,
    this.initialSection,
  });

  @override
  ConsumerState<ProductDetailV2ConnectedScreen> createState() =>
      _ProductDetailV2ConnectedState();
}

class _ProductDetailV2ConnectedState
    extends ConsumerState<ProductDetailV2ConnectedScreen> {
  /// Product from CoreDatabase (instant local lookup, no network).
  ProductsCoreData? _product;
  bool _productLoading = true;

  /// Scroll anchor bookkeeping — owns the 3 GlobalKeys + the
  /// `?section=` retry loop + the unsafe-CTA jump. See
  /// `scroll_anchors.dart`.
  final ProductDetailScrollAnchors _anchors = ProductDetailScrollAnchors();

  @override
  void initState() {
    super.initState();
    _loadProduct();
    _scheduleInitialSectionScroll();
  }

  @override
  void didUpdateWidget(covariant ProductDetailV2ConnectedScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final routeChanged =
        oldWidget.dsldId != widget.dsldId ||
        oldWidget.initialSection != widget.initialSection;
    if (!routeChanged) return;

    _anchors.resetInitialScroll();
    if (oldWidget.dsldId != widget.dsldId) {
      setState(() {
        _product = null;
        _productLoading = true;
      });
      _loadProduct();
    }
    _scheduleInitialSectionScroll();
  }

  Future<void> _loadProduct() async {
    final requestedDsldId = widget.dsldId;
    final coreDb = ref.read(coreDatabaseProvider);
    final product = await coreDb.findById(requestedDsldId);
    if (mounted && widget.dsldId == requestedDsldId) {
      setState(() {
        _product = product;
        _productLoading = false;
      });
    }
  }

  void _scheduleInitialSectionScroll() {
    _anchors.scheduleInitialScroll(
      initialSection: widget.initialSection,
      isMounted: () => mounted,
    );
  }

  @override
  void dispose() {
    _anchors.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_productLoading) {
      return Scaffold(
        backgroundColor: V2Colors.bg,
        appBar: AppBar(
          backgroundColor: V2Colors.bg,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
        ),
        body: const _ProductDetailLoadingState(),
      );
    }

    if (_product == null) {
      return Scaffold(
        backgroundColor: V2Colors.bg,
        appBar: AppBar(
          backgroundColor: V2Colors.bg,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: V2Colors.fg),
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go(Routes.home);
              }
            },
          ),
        ),
        body: SafeArea(
          child: Center(
            child: PGEmptyState(
              icon: Icons.inventory_2_outlined,
              eyebrow: 'Catalog',
              headline: 'Product unavailable',
              body:
                  'This shared or scanned product is not in the verified '
                  'catalog on this device.',
              primaryLabel: 'Search catalog',
              primaryIcon: Icons.search_rounded,
              onPrimaryTap: () => context.go(Routes.search),
              secondaryLabel: 'Go home',
              onSecondaryTap: () => context.go(Routes.home),
            ),
          ),
        ),
      );
    }

    // -------------------------------------------------------------
    // Header derivations (local product row)
    // -------------------------------------------------------------
    final productName = _product?.productName ?? 'Product ${widget.dsldId}';
    final brandName = _product?.brandName ?? '';
    final formFactor = _product?.formFactor ?? '';
    final score100 = _product?.qualityScoreV4100;
    final mappedCoverage = _product?.mappedCoverage ?? 0.0;
    final trustTags = buildHeroTrustTags(_product);
    final isBlocked = productIsBlocked(_product);
    final isNotScored = productIsNotScored(_product);

    // -------------------------------------------------------------
    // Async detail blob (same provider production uses)
    // -------------------------------------------------------------
    final blobAsync = ref.watch(detailBlobProvider(widget.dsldId));
    final detailBlob = blobAsync.asData?.value;
    final blobLoading = blobAsync.isLoading;
    final blobError = blobAsync.hasError;

    // -------------------------------------------------------------
    // Warning compose pipeline (see warnings_pipeline.dart)
    // -------------------------------------------------------------
    final personalizedWarnings =
        ref
            .watch(personalizedInteractionWarningsProvider(widget.dsldId))
            .value ??
        const <InteractionWarning>[];
    final profile = ref.watch(profileProvider);
    final guardedWarnings = composeGuardedWarnings(
      detailBlob: detailBlob,
      personalizedWarnings: personalizedWarnings,
      userConditions: profile.conditions.toSet(),
      userDrugClasses: profile.drugClasses.toSet(),
      userProfileFlags: profile.evaluatorProfileFlags,
    );

    // -------------------------------------------------------------
    // Blob-derived flags + ingredient doses (used by adapters in 11.7c+)
    // -------------------------------------------------------------
    final ingredientDoses = extractIngredientDoses(detailBlob);
    final canonicalIds = _product == null
        ? const <String>[]
        : canonicalIdsForProduct(_product!, detailBlob: detailBlob);
    final blendDetail =
        detailBlob?['proprietary_blend_detail'] as Map<String, dynamic>?;
    final hasProprietaryBlends = blendDetail?['has_proprietary_blends'] == true;

    // -------------------------------------------------------------
    // LabelConfidence signal probe — checked here so we can gate the
    // section sliver the same way production does (line 403).
    // -------------------------------------------------------------
    final labelConfidenceHasSignal = labelConfidenceHasAnySignal(
      mappedCoverage: mappedCoverage,
      hasProprietaryBlends: hasProprietaryBlends,
      isNotScored: isNotScored,
      productStatus: detailBlob?['product_status'] as Map<String, dynamic>?,
      unmappedActives: detailBlob?['unmapped_actives'] as Map<String, dynamic>?,
    );

    // -------------------------------------------------------------
    // Gate booleans (see gating.dart)
    // -------------------------------------------------------------
    final showPersonalFit = shouldShowPersonalFit(isBlocked: isBlocked);
    final showReviewBeforeUse = shouldShowReviewBeforeUse(isBlocked: isBlocked);
    final showLabelConfidence = shouldShowLabelConfidence(
      isBlocked: isBlocked,
      hasAnySignal: labelConfidenceHasSignal,
    );
    final showScoreBreakdown = shouldShowScoreBreakdown(
      isBlocked: isBlocked,
      isNotScored: isNotScored,
    );
    final showDeepDive = shouldShowDeepDive(
      isBlocked: isBlocked,
      blobLoading: blobLoading,
      blobError: blobError,
    );

    // -------------------------------------------------------------
    // Allergen + free-from match (used by ReviewBeforeUse adapter).
    // Computed unconditionally so the no-structured-allergens check
    // is reusable by the free-text allergen summary fallback.
    // -------------------------------------------------------------
    final matchedAllergens = matchAllergens(
      profile.allergens,
      detailBlob?['allergens'] as List<dynamic>?,
    );
    final userAllergenSet = profile.allergens.toSet();
    final freeFromClaims = matchFreeFromClaims(
      userAllergenIds: userAllergenSet,
      isGlutenFree: _product?.isGlutenFree,
      isDairyFree: _product?.isDairyFree,
      isSoyFree: _product?.isSoyFree,
    );
    final containsAllergenIds = matchedAllergens
        .where((m) => m.presenceType == 'contains')
        .map((m) => m.id)
        .toSet();
    final freeFromConflicts = findFreeFromConflicts(
      matchedContainsAllergenIds: containsAllergenIds,
      isGlutenFree: _product?.isGlutenFree,
      isDairyFree: _product?.isDairyFree,
      isSoyFree: _product?.isSoyFree,
    );
    final interactionHint = _product?.interactionSummaryHint ?? '';

    // -------------------------------------------------------------
    // Hero `bottomBanner` slot — blocked-product banner (11.7c.1).
    // Null when the product is not blocked; the Hero collapses the
    // slot to zero height in that case. When blocked, this slot
    // replaces the production header's standalone BlockedBanner
    // sliver, keeping the banner visually anchored to the hero card.
    // -------------------------------------------------------------
    final heroBottomBanner = isBlocked
        ? buildBlockedBannerSection(
            verdict: _product?.verdict ?? '',
            blockingReason: _product?.blockingReason ?? '',
            topWarnings: parseTopWarnings(_product),
            bannedSubstanceDetail:
                detailBlob?['banned_substance_detail'] as Map<String, dynamic>?,
          )
        : null;

    final mq = MediaQuery.of(context);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: V2Colors.bg,
        body: CustomScrollView(
          controller: _anchors.scrollController,
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            _buildAppBar(),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                V2Spacing.space16,
                0,
                V2Spacing.space16,
                mq.padding.bottom + V2Spacing.space24,
              ),
              sliver: SliverList.list(
                children: [
                  // ---- 1. Hero (WIRED) -----------------------------
                  buildHeroSection(
                    context: context,
                    dsldId: widget.dsldId,
                    product: _product,
                    productName: productName,
                    brandName: brandName,
                    formFactor: formFactor,
                    score100: score100,
                    isBlocked: isBlocked,
                    isNotScored: isNotScored,
                    trustTags: trustTags,
                    bottomBanner: heroBottomBanner,
                  ),
                  const SizedBox(height: V2Spacing.space12),

                  // ---- 2. PersonalFit (WIRED, 11.7c.2) -------------
                  // Lazy-watch via Consumer so fitScoreForProductProvider
                  // only fires when the section actually renders (mirrors
                  // production line 311's inner Consumer pattern).
                  if (showPersonalFit) ...[
                    Consumer(
                      builder: (context, innerRef, _) {
                        final fitAsync = innerRef.watch(
                          fitScoreForProductProvider(widget.dsldId),
                        );
                        final fitResult = fitAsync.asData?.value;
                        final fitDisplay = fitResult != null
                            ? computeFitDisplay(
                                verdict: worstSeverityOf(guardedWarnings),
                                fitResult: fitResult,
                              )
                            : const FitIncomplete();
                        return buildPersonalFitSection(
                          fit: fitDisplay,
                          topGoalLabel: topGoalLabelFromFit(fitResult),
                          fitReasons: fitResult?.reasons ?? const [],
                          ingredientNames: ingredientNamesFromBlob(detailBlob),
                          userConditions: profile.conditions.toList(
                            growable: false,
                          ),
                          contextChips: contextChipsFromProfile(
                            goals: profile.goals,
                            conditions: profile.conditions,
                            drugClasses: profile.drugClasses,
                          ),
                          onEditProfile: () =>
                              context.push(Routes.profileSetup),
                        );
                      },
                    ),
                    const SizedBox(height: V2Spacing.space12),
                  ],

                  // ---- 3. ReviewBeforeUse (WIRED, 11.7c.3) ---------
                  if (showReviewBeforeUse) ...[
                    KeyedSubtree(
                      key: _anchors.interactionsKey,
                      child: ReviewBeforeUseSection(
                        warnings: guardedWarnings,
                        interactionHint: interactionHint,
                        interactionSummary:
                            detailBlob?['interaction_summary']
                                as Map<String, dynamic>?,
                        ingredientDoses: ingredientDoses,
                        matchedAllergens: matchedAllergens,
                        freeFromClaims: freeFromClaims,
                        freeFromConflicts: freeFromConflicts,
                      ),
                    ),
                    const SizedBox(height: V2Spacing.space12),
                  ],

                  // ---- 4. LabelConfidence (WIRED, 11.7c.4) ---------
                  // PRODUCTION ORDER: LabelConfidence sits BEFORE
                  // ScoreBreakdown so the low-coverage caveat sets
                  // expectation before the score it caveats.
                  if (showLabelConfidence) ...[
                    buildLabelConfidenceSection(
                      context: context,
                      mappedCoverage: mappedCoverage,
                      hasProprietaryBlends: hasProprietaryBlends,
                      isNotScored: isNotScored,
                      productStatus:
                          detailBlob?['product_status']
                              as Map<String, dynamic>?,
                      unmappedActives:
                          detailBlob?['unmapped_actives']
                              as Map<String, dynamic>?,
                    ),
                    const SizedBox(height: V2Spacing.space12),
                  ],

                  // ---- 4.5 Allergen summary fallback ---------------
                  // Renders ONLY when the product has free-text
                  // allergenSummary AND the blob has no structured
                  // allergens (which would have already populated
                  // ReviewBeforeUse rows). Suppressed on blocked.
                  if (shouldShowAllergenSummaryBanner(
                    isBlocked: isBlocked,
                    allergenSummary: _product?.allergenSummary,
                    noStructuredAllergens: matchedAllergens.isEmpty,
                  )) ...[
                    buildAllergenSummaryBannerSection(
                      allergenSummary: _product?.allergenSummary,
                    ),
                    const SizedBox(height: V2Spacing.space12),
                  ],

                  // ---- 5. ScoreBreakdown (WIRED, 11.7d.1) ----------
                  if (showScoreBreakdown) ...[
                    buildScoreBreakdownSection(
                      ingredientQuality: _product?.scoreIngredientQuality,
                      safetyPurity: _product?.scoreSafetyPurity,
                      evidenceResearch: _product?.scoreEvidenceResearch,
                      brandTrust: _product?.scoreBrandTrust,
                      hasThirdPartyTesting: _product?.hasThirdPartyTesting == 1,
                      isTrustedManufacturer:
                          _product?.isTrustedManufacturer == 1,
                      heroScore: score100,
                      mappedCoverage: mappedCoverage,
                      sectionBreakdown:
                          detailBlob?['section_breakdown']
                              as Map<String, dynamic>?,
                      // v4: prefer the six-pillar breakdown from the blob.
                      // When absent (legacy bundle / pre-v4 blob) the adapter
                      // falls back to the v3 four-section pillars above.
                      qualityPillarsV4:
                          detailBlob?['quality_pillars_v4']
                              as Map<String, dynamic>?,
                    ),
                    const SizedBox(height: V2Spacing.space12),
                  ],

                  // ---- 6. Ingredients (WIRED, 11.7d.2) -------------
                  if (showDeepDive) ...[
                    KeyedSubtree(
                      key: _anchors.ingredientsKey,
                      child: buildIngredientsSection(
                        context: context,
                        ingredients:
                            ((detailBlob?['ingredients'] as List?) ?? const [])
                                .whereType<Map<String, dynamic>>()
                                .toList(growable: false),
                        inactiveIngredients:
                            ((detailBlob?['inactive_ingredients'] as List?) ??
                                    const [])
                                .whereType<Map<String, dynamic>>()
                                .toList(growable: false),
                        ulAnalysis:
                            ((detailBlob?['rda_ul_data']
                                        as Map<
                                          String,
                                          dynamic
                                        >?)?['analyzed_ingredients']
                                    as List?)
                                ?.whereType<Map<String, dynamic>>()
                                .toList(growable: false),
                        blends: (blendDetail?['blends'] as List?)
                            ?.whereType<Map<String, dynamic>>()
                            .toList(growable: false),
                      ),
                    ),
                    const SizedBox(height: V2Spacing.space12),
                  ],

                  // ---- 6.5 Excipient density (WIRED, 11.11) --------
                  // Quality signal: ratio of actives to inactive fillers.
                  // Whitelist-aware suppression handled inside the card.
                  if (showDeepDive) ...[
                    buildExcipientDensitySection(
                      activeIngredients:
                          ((detailBlob?['ingredients'] as List?) ?? const [])
                              .whereType<Map<String, dynamic>>()
                              .toList(growable: false),
                      inactiveIngredients:
                          ((detailBlob?['inactive_ingredients'] as List?) ??
                                  const [])
                              .whereType<Map<String, dynamic>>()
                              .toList(growable: false),
                      dosageForm: _product?.formFactor,
                    ),
                    const SizedBox(height: V2Spacing.space12),
                  ],

                  // ---- 7. Tradeoffs (WIRED, 11.7d.3) ---------------
                  if (showDeepDive) ...[
                    buildTradeoffsSection(detailBlob: detailBlob),
                    const SizedBox(height: V2Spacing.space12),
                  ],

                  // ---- 8. Populations (WIRED, 11.7d.4) -------------
                  if (showDeepDive) ...[
                    buildPopulationsSection(
                      warnings: guardedWarnings,
                      userConditions: profile.conditions.toSet(),
                      userDrugClasses: profile.drugClasses.toSet(),
                      ageBracket: profile.ageBracket,
                    ),
                    const SizedBox(height: V2Spacing.space12),
                  ],

                  // ---- 9. Nutrition (WIRED, 11.7d.5) ---------------
                  if (showDeepDive) ...[
                    buildNutritionSection(
                      caloriesPerServing: _product?.caloriesPerServing,
                      nutritionDetail:
                          detailBlob?['nutrition_detail']
                              as Map<String, dynamic>?,
                    ),
                    const SizedBox(height: V2Spacing.space12),
                  ],

                  // ---- 10. Certifications (WIRED, 11.7e) -----------
                  if (showDeepDive) ...[
                    buildCertificationsSection(
                      certificationDetail:
                          detailBlob?['certification_detail']
                              as Map<String, dynamic>?,
                    ),
                    const SizedBox(height: V2Spacing.space12),
                  ],

                  // ---- 11. Evidence (WIRED, 11.7e) -----------------
                  if (showDeepDive) ...[
                    buildEvidenceSection(
                      evidenceData:
                          detailBlob?['evidence_data'] as Map<String, dynamic>?,
                    ),
                    const SizedBox(height: V2Spacing.space12),
                  ],

                  // ---- 11.1 Tier 2 research evidence (Sprint 28) ---
                  // Neutral literature co-occurrence surface. These rows
                  // never become warnings or score penalties.
                  if (showDeepDive && canonicalIds.isNotEmpty) ...[
                    KeyedSubtree(
                      key: _anchors.researchKey,
                      child: ResearchEvidenceSection(
                        canonicalIds: canonicalIds,
                      ),
                    ),
                    const SizedBox(height: V2Spacing.space12),
                  ],

                  // ---- 11.5 Synergy (WIRED, 11.11) -----------------
                  // "Works well with" — T22 high-confidence clusters
                  // (Sprint 21 54-cluster data). Hidden when no
                  // tier ≤ 2 clusters pass — never renders as empty.
                  if (showDeepDive) ...[
                    buildSynergySection(detailBlob: detailBlob),
                    const SizedBox(height: V2Spacing.space12),
                  ],

                  // ---- 12. HeavyMetal (WIRED, 11.7e) ---------------
                  if (showDeepDive) ...[
                    buildHeavyMetalSection(
                      heavyMetalDetail:
                          detailBlob?['heavy_metal_detail']
                              as Map<String, dynamic>?,
                    ),
                    const SizedBox(height: V2Spacing.space12),
                  ],

                  // ---- 13. Formulation (WIRED, 11.7e) --------------
                  if (showDeepDive) ...[
                    buildFormulationSection(
                      formulationDetail:
                          detailBlob?['formulation_detail']
                              as Map<String, dynamic>?,
                      ingredientQualityData:
                          detailBlob?['ingredient_quality_data']
                              as Map<String, dynamic>?,
                    ),
                    const SizedBox(height: V2Spacing.space12),
                  ],

                  // ---- 14. Probiotic (WIRED, 11.7e) ----------------
                  if (showDeepDive) ...[
                    buildProbioticSection(
                      probioticDetail:
                          detailBlob?['probiotic_detail']
                              as Map<String, dynamic>?,
                    ),
                    const SizedBox(height: V2Spacing.space12),
                  ],

                  // ---- 15. ManufacturerViolations (WIRED, 11.7e) ---
                  if (showDeepDive) ...[
                    buildManufacturerViolationsSection(
                      manufacturerDetail:
                          detailBlob?['manufacturer_detail']
                              as Map<String, dynamic>?,
                    ),
                    const SizedBox(height: V2Spacing.space12),
                  ],

                  // ---- 16. BetterAlternatives (WIRED, 11.7e) -------
                  // Anchor wraps the section so the sticky CTA's
                  // ensureVisible call still lands on layoutable content
                  // when the section hides (SizedBox.shrink keeps the
                  // GlobalKey attached).
                  KeyedSubtree(
                    key: _anchors.alternativesKey,
                    child: BetterAlternativesSection(
                      currentDsldId: widget.dsldId,
                      isBlocked: isBlocked,
                      isNotScored: isNotScored,
                      score100: score100,
                      category: _product?.primaryCategory,
                      guardedWarnings: guardedWarnings,
                    ),
                  ),
                  const SizedBox(height: V2Spacing.space12),

                  // ---- "No additional details available." fallback -
                  // Mirrors production DetailSection.build() line 1935:
                  // when blob resolved but is null, surface a quiet
                  // honest line so users understand the data state
                  // (rather than wondering whether content failed to
                  // load). Renders for blocked + non-blocked alike.
                  if (!blobLoading && !blobError && detailBlob == null) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: V2Spacing.space16,
                      ),
                      child: Text(
                        'No additional details available.',
                        style: V2Typography.bodySm(color: V2Colors.fgMuted),
                      ),
                    ),
                    const SizedBox(height: V2Spacing.space12),
                  ],

                  // ---- 17. TransparencyFooter (WIRED, 11.7f) -------
                  // Reads catalogInfoProvider for the real freshness
                  // label — "Updated <Mon DD, YYYY>" — same source the
                  // v2 home screen's citation strip uses.
                  const TransparencyFooterSection(),
                ],
              ),
            ),
          ],
        ),
        // Sticky action bar — production widget reused as-is. Already
        // provider-aware (reads stackEntryForDsldIdProvider), so the
        // "Add to my stack" / "See safer alternatives" flow works
        // from day 1.
        bottomNavigationBar: PGStackActionButtons(
          dsldId: widget.dsldId,
          isUnsafe: isBlocked,
          onSeeAlternatives: _anchors.scrollToAlternatives,
        ),
      ),
    );
  }

  // -----------------------------------------------------------------
  // Sliver helpers (local — small enough to live in screen)
  // -----------------------------------------------------------------

  Widget _buildAppBar() {
    return SliverAppBar(
      backgroundColor: V2Colors.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      pinned: false,
      floating: true,
      snap: true,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded, color: V2Colors.fg),
        // **Sentry fix — 21× `GoError: There is nothing to pop`.**
        // Deep links / scan-flow / push notifications can land users
        // here without anything on the navigation stack. Fall back to
        // the home shell instead of letting GoRouter throw.
        onPressed: () {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go(Routes.home);
          }
        },
      ),
      actions: [
        if (_product != null)
          IconButton(
            icon: const Icon(Icons.ios_share_rounded, color: V2Colors.fg),
            // No haptic — iOS share sheet fires its own present haptic.
            onPressed: () {
              ShareService().shareProduct(
                shareTitle: _product!.shareTitle,
                shareDescription: _product!.shareDescription,
                shareHighlights: _product!.shareHighlights,
              );
            },
          ),
      ],
    );
  }
}

class _ProductDetailLoadingState extends StatelessWidget {
  const _ProductDetailLoadingState();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(V2Spacing.space24),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: V2Colors.surface,
              borderRadius: BorderRadius.circular(V2Spacing.radiusSheet),
              border: Border.all(color: V2Colors.outline),
              boxShadow: V2Shadows.sm,
            ),
            child: Padding(
              padding: const EdgeInsets.all(V2Spacing.space24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: V2Colors.accent,
                    ),
                  ),
                  const SizedBox(height: V2Spacing.space16),
                  Text(
                    'Opening product',
                    style: V2Typography.titleSm(color: V2Colors.fg),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: V2Spacing.space8),
                  Text(
                    'Loading the verified catalog record on this device.',
                    style: V2Typography.bodySm(color: V2Colors.fgMuted),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// All sections wired (Phase 11.7e completed). The _SectionPlaceholder
// shell-helper has been deleted — its job (rendering "WIRING <name>"
// diagnostic cards) is done. Future placeholder cards should live in
// their own section file as a deferred-state widget, not a global helper.
