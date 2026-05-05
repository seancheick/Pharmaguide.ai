import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/fit_score_result.dart';
import 'package:pharmaguide/services/fit_score/fit_display.dart';
import 'package:pharmaguide/core/theme/app_motion.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_card.dart';
import 'package:pharmaguide/core/widgets/pg_circular_icon_button.dart';
import 'package:pharmaguide/core/widgets/pg_empty_state.dart';
import 'package:pharmaguide/core/widgets/pg_frosted_app_bar.dart';
import 'package:pharmaguide/features/product_detail/widgets/score_line.dart';
import 'package:pharmaguide/core/widgets/product_image.dart';
import 'package:pharmaguide/core/widgets/pg_severity_banner.dart';
import 'package:pharmaguide/core/widgets/pg_shimmer_box.dart';
import 'package:pharmaguide/core/widgets/verdict_badge.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/services/sharing/share_service.dart';
import 'package:pharmaguide/features/product_detail/providers/detail_blob_provider.dart';
import 'package:pharmaguide/features/product_detail/providers/hero_verdict_provider.dart';
import 'package:pharmaguide/features/product_detail/providers/personalized_warnings_provider.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';
import 'package:pharmaguide/features/product_detail/dose_safety.dart';
import 'package:pharmaguide/features/product_detail/blend_grouping.dart';
import 'package:pharmaguide/features/product_detail/ingredient_sort.dart';
import 'package:pharmaguide/features/product_detail/widgets/better_alternatives.dart';
import 'package:pharmaguide/features/product_detail/widgets/label_confidence_card.dart';
import 'package:pharmaguide/features/product_detail/providers/fit_score_provider.dart';
import 'package:pharmaguide/features/product_detail/widgets/ingredients_card.dart';
import 'package:pharmaguide/features/product_detail/widgets/ingredient_explain_model.dart';
import 'package:pharmaguide/features/product_detail/widgets/ingredient_explain_sheet.dart';
import 'package:pharmaguide/features/product_detail/widgets/interaction_warnings.dart';
import 'package:pharmaguide/features/product_detail/allergen_match.dart';
import 'package:pharmaguide/features/product_detail/widgets/review_before_use_card.dart';
import 'package:pharmaguide/features/product_detail/widgets/personal_fit_card.dart';
import 'package:pharmaguide/features/product_detail/widgets/populations_section.dart';
import 'package:pharmaguide/features/product_detail/widgets/product_image_viewer.dart';
import 'package:pharmaguide/services/warnings/condition_gate.dart';
import 'package:pharmaguide/features/product_detail/widgets/tradeoffs_section.dart';
import 'package:pharmaguide/features/product_detail/widgets/transparency_footer.dart';
import 'package:pharmaguide/features/product_detail/widgets/excipient_density_card.dart';
import 'package:pharmaguide/features/product_detail/widgets/heavy_metal_warning_card.dart';
import 'package:pharmaguide/features/product_detail/widgets/nutrition_panel.dart';
import 'package:pharmaguide/features/product_detail/widgets/pipeline_detail_sections.dart';
import 'package:pharmaguide/features/product_detail/widgets/pg_stack_action_buttons.dart';
import 'package:pharmaguide/features/product_detail/widgets/score_breakdown_card.dart';
import 'package:url_launcher/url_launcher.dart';

/// Product detail screen.
/// Receives [dsldId] from route params (e.g. `/product/12345`).
///
/// Architecture:
/// - Header data (name, score, verdict) comes from local `products_core` DB —
///   zero network latency, instant render.
/// - Detail blob (ingredients, interactions, evidence) loaded async from
///   Supabase and cached in UserDatabase for 24h.
class ProductDetailScreen extends ConsumerStatefulWidget {
  final String dsldId;

  const ProductDetailScreen({super.key, required this.dsldId});

  @override
  ConsumerState<ProductDetailScreen> createState() =>
      _ProductDetailScreenState();
}

class _ProductDetailScreenState extends ConsumerState<ProductDetailScreen> {
  // Product from CoreDatabase.
  ProductsCoreData? _product;
  bool _productLoading = true;

  /// Anchors the Better Alternatives sliver so the T1.15 sticky-bar
  /// "See safer alternatives" button can scroll the page to it.
  /// Lives on the screen state because the sliver gets rebuilt on
  /// state changes; a stable key keeps the scroll target intact.
  final GlobalKey _alternativesKey = GlobalKey();


  // Personalized interaction warnings live in
  // `personalizedInteractionWarningsProvider` (T1B, sprint:
  // docs/sprints/product_detail_page_sprint.md). The provider watches
  // `activeStackProvider`, so stack mutations from anywhere in the app
  // trigger a rebuild here automatically — no setState needed.

  @override
  void initState() {
    super.initState();
    _loadProduct();
  }

  // T17 (2026-04-30) — `_stackEntry` field + `_loadStackEntry` removed
  // alongside RefillReminderCard. The stack-entry lookup powered the
  // refill card's days-remaining math; with the card deleted, the
  // lookup is dead weight.

  Future<void> _loadProduct() async {
    final coreDb = ref.read(coreDatabaseProvider);
    final product = await coreDb.findById(widget.dsldId);
    if (mounted) {
      setState(() {
        _product = product;
        _productLoading = false;
      });
    }
  }

  bool _isNotScored(ProductsCoreData? product) {
    if (product == null) return false;
    final verdict = product.verdict ?? '';
    final score = product.score100Equivalent;
    final isBlocked = isUnsafeVerdict(verdict);
    return (verdict.trim().toUpperCase() == 'NOT_SCORED' ||
        (score == null && !isBlocked));
  }

  @override
  Widget build(BuildContext context) {
    if (_productLoading) {
      return Scaffold(
        appBar: AppBar(elevation: 0, surfaceTintColor: Colors.transparent),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final productName = _product?.productName ?? 'Product ${widget.dsldId}';
    final brandName = _product?.brandName ?? '';
    final formFactor = _product?.formFactor ?? '';
    final verdict = _product?.verdict ?? '';
    final blockingReason = _product?.blockingReason ?? '';
    final isBlocked = isUnsafeVerdict(verdict);

    final score100 = _product?.score100Equivalent;
    // grade + percentileLabel were rendered in the pre-T1.1 hero. Both
    // move out: grade → T1.4 Section 3 (Product Quality), percentileLabel
    // → T1.4 subtitle. Reads kept commented out so the next session can
    // grab them quickly when wiring T1.4. See INITIATIVE_PRODUCT_TRUST_
    // AND_IA.md change log entry 2026-04-29.
    // Safety rule: NEVER display "safe" when mapped_coverage < 0.3.
    // Default to 0.0 (conservative) when coverage is unknown.
    final mappedCoverage = _product?.mappedCoverage ?? 0.0;
    final interactionHint = _product?.interactionSummaryHint ?? '';

    // Section scores
    final ingredientQuality = _product?.scoreIngredientQuality;
    final safetyPurity = _product?.scoreSafetyPurity;
    final evidenceResearch = _product?.scoreEvidenceResearch;
    final brandTrust = _product?.scoreBrandTrust;

    // Dietary tags
    final dietaryTags = _buildAllTags();

    // Detail blob — fetched & cached by detailBlobProvider. Loading/error
    // state drive the in-place banner; the resolved map feeds every
    // pipeline-detail section below.
    final blobAsync = ref.watch(detailBlobProvider(widget.dsldId));
    final detailBlob = blobAsync.asData?.value;
    final blobLoading = blobAsync.isLoading;
    final blobError = blobAsync.hasError;

    // T16.2e (2026-04-30) — extract ingredient doses ONCE per build so
    // every gate surface (banner conditionIds, §7 condition_summary
    // detail cards) sees the same dose-aware picture. Without this the
    // banner & §7 surfaces fall back to positive-only filtering and
    // sub-clinical aboveDose entries leak through.
    final ingredientDoses = extractIngredientDoses(detailBlob);

    // Detail blob data + personalized interaction warnings from live DB.
    // Personalized warnings (from InteractionDatabase) appear first,
    // followed by generic blob warnings — deduped by (mechanism, severity)
    // to avoid showing the same interaction twice from different sources.
    // T1B (sprint product_detail_page_sprint.md): personalized warnings
    // come from a Riverpod family that watches activeStackProvider, so
    // stack mutations propagate without a screen restart.
    final personalizedWarnings = ref
            .watch(personalizedInteractionWarningsProvider(widget.dsldId))
            .valueOrNull ??
        const <InteractionWarning>[];
    final blobWarnings = _parseWarnings(detailBlob);
    final seenKeys = <String>{
      for (final w in personalizedWarnings)
        '${w.severity.name}:${w.mechanism}',
    };
    final warnings = <InteractionWarning>[
      ...personalizedWarnings,
      ...blobWarnings.where(
        (w) => !seenKeys.contains('${w.severity.name}:${w.mechanism}'),
      ),
    ];
    final profile = ref.watch(profileProvider);
    final guardedWarnings = filterProductDetailWarningsForProfile(
      detailBlob: detailBlob,
      warnings: warnings,
      userConditions: profile.conditions.toSet(),
      userDrugClasses: profile.drugClasses.toSet(),
    );
    // Pipeline nests this under proprietary_blend_detail
    final blendDetail =
        detailBlob?['proprietary_blend_detail'] as Map<String, dynamic>?;
    final hasProprietaryBlends = blendDetail?['has_proprietary_blends'] == true;

    final isNotScored = _isNotScored(_product);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // ----------------------------------------------------------------
          // App bar with back button
          // ----------------------------------------------------------------
          PGFrostedAppBar(
            // Title intentionally empty — the T1.1 hero below carries the
            // product name. Duplicating it here would compete (same trick
            // used by iOS App Store on product pages).
            title: '',
            actions: [
              if (_product != null)
                PGCircularIconButton(
                  icon: Icons.ios_share_rounded,
                  // No haptic — iOS share sheet fires its own present
                  // haptic; firing one here would double-tap the user.
                  haptic: false,
                  onTap: () {
                    ShareService().shareProduct(
                      shareTitle: _product!.shareTitle,
                      shareDescription: _product!.shareDescription,
                      shareHighlights: _product!.shareHighlights,
                    );
                  },
                ),
            ],
          ),

          // ----------------------------------------------------------------
          // Header card — instant from local DB, no network needed
          // ----------------------------------------------------------------
          SliverToBoxAdapter(
            child: _HeaderSection(
              dsldId: widget.dsldId,
              productName: productName,
              brandName: brandName,
              formFactor: formFactor,
              verdict: verdict,
              blockingReason: blockingReason,
              score100: score100,
              dietaryTags: dietaryTags,
              isNotScored: isNotScored,
              topWarnings: _topWarnings(),
              bannedSubstanceDetail:
                  detailBlob?['banned_substance_detail']
                      as Map<String, dynamic>?,
              upc: _product?.upcSku,
              dsldImagePath: _product?.imageThumbnailUrl,
              // T11.1 (2026-04-29 PM) — switched from netContents
              // to servingsPerContainer per Sean's live walkthrough.
              // Net contents produces awkward strings for liquids
              // ("1 Fluid Ounce(s)"); servings × form is cleaner.
              dosingSummary: _product?.dosingSummary,
              servingsPerContainer: _product?.servingsPerContainer,
            ),
          ),

          // ----------------------------------------------------------------
          // Section 2 ("Personal Fit") — T12 (2026-04-29). Replaces
          // the old ForYouSection (context chips + verdict + alerts
          // + Why-this-fits expander) with a much quieter card:
          // shield icon + headline + max 2 causal bullets + edit
          // pencil. The bullet generator prefers the T3 Path A
          // positive-profile bullets ("Magnesium supports your blood
          // pressure goal") and falls back to FitScoreResult.reasons.
          // Alerts list moved to T13 Alert Summary card.
          // ----------------------------------------------------------------
          if (!isBlocked)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.space20,
                  0,
                  AppTheme.space20,
                  AppTheme.space12,
                ),
                child: Consumer(
                  builder: (context, innerRef, _) {
                    final fitAsync = innerRef.watch(
                      fitScoreForProductProvider(widget.dsldId),
                    );
                    final fitResult = fitAsync.asData?.value;
                    final fitDisplay = fitResult != null
                        ? computeFitDisplay(
                            verdict: _maxSeverityOf(guardedWarnings),
                            fitResult: fitResult,
                          )
                        : const FitIncomplete();
                    final ingredientNames =
                        ((detailBlob?['ingredients'] as List?)
                                ?.whereType<Map<String, dynamic>>()
                                .map((e) => e['name']?.toString() ?? '')
                                .where((n) => n.isNotEmpty)
                                .toList(growable: false)) ??
                            const <String>[];
                    return PersonalFitCard(
                      fit: fitDisplay,
                      ingredientNames: ingredientNames,
                      fitReasons: fitResult?.reasons ?? const [],
                      topGoalLabel: _topGoalLabelFromFit(fitResult),
                      onEditProfile: () =>
                          GoRouter.of(context).push(Routes.profileSetup),
                    );
                  },
                ),
              ),
            ),

          // ----------------------------------------------------------------
          // T2A (sprint product_detail_page_sprint.md) — unified
          // "Review before use" card. Replaces AlertSummaryCard +
          // _ConditionAlertBanner with a single severity-toned card
          // that also surfaces personalized allergen rows when the
          // product blob ships structured allergens (Phase 7B/8).
          // ----------------------------------------------------------------
          if (!isBlocked)
            SliverToBoxAdapter(
              child: ReviewBeforeUseCard(
                warnings: guardedWarnings,
                interactionHint: interactionHint,
                interactionSummary:
                    detailBlob?['interaction_summary'] as Map<String, dynamic>?,
                ingredientDoses: ingredientDoses,
                matchedAllergens: matchAllergens(
                  profile.allergens,
                  detailBlob?['allergens'] as List<dynamic>?,
                ),
              ),
            ),

          // ----------------------------------------------------------------
          // T3 (sprint product_detail_page_sprint.md) — unified
          // "Label confidence" card. Replaces ProductStatusChip,
          // UnknownIngredientBanner, BlendWarningBanner, and
          // UnmappedActivesDisclosure (the latter is also unwired
          // from DeepDive). Card hides itself when no signal fires.
          // ----------------------------------------------------------------
          if (!isBlocked &&
              LabelConfidenceCard.hasAnySignal(
                mappedCoverage: mappedCoverage,
                hasProprietaryBlends: hasProprietaryBlends,
                isNotScored: isNotScored,
                productStatus:
                    detailBlob?['product_status'] as Map<String, dynamic>?,
                unmappedActives:
                    detailBlob?['unmapped_actives'] as Map<String, dynamic>?,
              ))
            SliverToBoxAdapter(
              child: LabelConfidenceCard(
                mappedCoverage: mappedCoverage,
                hasProprietaryBlends: hasProprietaryBlends,
                isNotScored: isNotScored,
                productStatus:
                    detailBlob?['product_status'] as Map<String, dynamic>?,
                unmappedActives:
                    detailBlob?['unmapped_actives'] as Map<String, dynamic>?,
              ),
            ),

          // ----------------------------------------------------------------
          // Score breakdown — generous breathing room
          // ----------------------------------------------------------------
          if (!isBlocked && !isNotScored)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.space20,
                  AppTheme.space8,
                  AppTheme.space20,
                  AppTheme.space20,
                ),
                child: ScoreBreakdownCard(
                  ingredientQuality: ingredientQuality,
                  safetyPurity: safetyPurity,
                  evidenceResearch: evidenceResearch,
                  brandTrust: brandTrust,
                  sectionBreakdown:
                      detailBlob?['section_breakdown'] as Map<String, dynamic>?,
                  hasThirdPartyTesting: _product?.hasThirdPartyTesting == 1,
                  isTrustedManufacturer: _product?.isTrustedManufacturer == 1,
                  // T1.4 — hero continuity label + coverage line.
                  // heroScore links Section 3 back to the Quality Score
                  // ring in the hero (T1.1). mappedCoverage drives the
                  // tier-tinted coverage line below the pillars.
                  heroScore: score100,
                  mappedCoverage: mappedCoverage,
                ),
              ),
            ),

          // ----------------------------------------------------------------
          // Detail section (ingredients, pros/cons, warnings) — key content
          // ----------------------------------------------------------------
          // T16.2g (2026-04-30) — `_alertsKey` removed. The
          // AlertSummaryCard now expands inline as an accordion (Sean's
          // "drop down and we see everything there, one source"), so
          // we no longer need a scroll-target anchor for it.
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.space20,
                0,
                AppTheme.space20,
                AppTheme.space20,
              ),
              child: blobLoading
                  ? const _DetailShimmer()
                  : blobError
                  ? _DetailErrorBanner(
                      onRetry: () =>
                          ref.invalidate(detailBlobProvider(widget.dsldId)),
                    )
                  : DetailSection(
                      detailBlob: detailBlob,
                      warnings: warnings,
                      // T1.7 inputs — trust signals for the
                      // "What we don't know" section. Read off the
                      // product directly here so DetailSection
                      // stays decoupled from the screen-state.
                      isTrustedManufacturer:
                          _product?.isTrustedManufacturer == 1,
                      hasThirdPartyTesting: _product?.hasThirdPartyTesting == 1,
                      mappedCoverage: _product?.mappedCoverage,
                      scoreEvidenceResearch: _product?.scoreEvidenceResearch,
                      scoreEvidenceResearchMax:
                          _product?.scoreEvidenceResearchMax,
                      // T1.11 inputs — collapsed Product Details panel.
                      dosingSummary: _product?.dosingSummary,
                      servingsPerContainer: _product?.servingsPerContainer,
                      netContentsQuantity: _product?.netContentsQuantity,
                      netContentsUnit: _product?.netContentsUnit,
                      formFactor: _product?.formFactor,
                    ),
            ),
          ),

          // ----------------------------------------------------------------
          // Allergen summary banner — legacy free-text fallback for
          // products that don't yet have structured `detailBlob['allergens']`.
          // T2A: suppressed when ReviewBeforeUseCard rendered personalized
          // allergen rows from the structured list.
          // ----------------------------------------------------------------
          if (!isBlocked &&
              _product?.allergenSummary != null &&
              matchAllergens(
                profile.allergens,
                detailBlob?['allergens'] as List<dynamic>?,
              ).isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.space20,
                  0,
                  AppTheme.space20,
                  AppTheme.space8,
                ),
                child: AllergenSummaryBanner(
                  allergenSummary: _product?.allergenSummary,
                ),
              ),
            ),

          // ----------------------------------------------------------------
          // Deep dive — collapsible section for detailed analysis.
          // Keeps the scroll depth manageable while making all data
          // accessible on demand (Oura-style progressive disclosure).
          // ----------------------------------------------------------------
          if (!blobLoading && !blobError)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.space20,
                  AppTheme.space4,
                  AppTheme.space20,
                  AppTheme.space8,
                ),
                child: DeepDiveSection(
                  dsldId: widget.dsldId,
                  activeIngredients:
                      (detailBlob?['ingredients'] as List?)
                          ?.whereType<Map<String, dynamic>>()
                          .toList() ??
                      [],
                  inactiveIngredients:
                      (detailBlob?['inactive_ingredients'] as List?)
                          ?.whereType<Map<String, dynamic>>()
                          .toList() ??
                      [],
                  certificationDetail:
                      detailBlob?['certification_detail']
                          as Map<String, dynamic>?,
                  evidenceData:
                      detailBlob?['evidence_data'] as Map<String, dynamic>?,
                  formulationDetail:
                      detailBlob?['formulation_detail']
                          as Map<String, dynamic>?,
                  ingredientQualityData:
                      detailBlob?['ingredient_quality_data']
                          as Map<String, dynamic>?,
                  probioticDetail:
                      detailBlob?['probiotic_detail'] as Map<String, dynamic>?,
                  synergyDetail:
                      detailBlob?['synergy_detail'] as Map<String, dynamic>?,
                  manufacturerDetail:
                      detailBlob?['manufacturer_detail']
                          as Map<String, dynamic>?,
                  caloriesPerServing: _product?.caloriesPerServing,
                  nutritionDetail:
                      detailBlob?['nutrition_detail'] as Map<String, dynamic>?,
                  unmappedActives:
                      detailBlob?['unmapped_actives'] as Map<String, dynamic>?,
                  heavyMetalDetail:
                      detailBlob?['heavy_metal_detail']
                          as Map<String, dynamic>?,
                ),
              ),
            ),

          // T17 (2026-04-30) — Refill reminder card deleted per spec
          // (60-day battery estimate). Lives only when the user has
          // stack data anyway, and the value didn't justify the
          // hero-area real-estate. Spec line 81 of
          // INITIATIVE_PRODUCT_DETAIL_CLEANUP.md.

          // ----------------------------------------------------------------
          // T1.12 Section 11 — Better Alternatives, V1 non-personalized.
          // Render gate fires on isBlocked OR score100 < 60 OR fit is
          // FitLimitedFit/FitNotRecommended. The gate lives inside a
          // Consumer so it has access to the same fit-score provider
          // ForYouSection uses — keeping the two sections in sync as the
          // fit math evolves.
          // ----------------------------------------------------------------
          SliverToBoxAdapter(
            key: _alternativesKey,
            child: Consumer(
              builder: (context, innerRef, _) {
                final fitAsync = innerRef.watch(
                  fitScoreForProductProvider(widget.dsldId),
                );
                final fitResult = fitAsync.asData?.value;
                final maxSeverity = _maxSeverityOf(guardedWarnings);
                final fitDisplay = fitResult == null
                    ? null
                    : computeFitDisplay(
                        verdict: maxSeverity,
                        fitResult: fitResult,
                      );
                if (!shouldShowBetterAlternatives(
                  isBlocked: isBlocked,
                  isNotScored: isNotScored,
                  score100: score100,
                  fitDisplay: fitDisplay,
                )) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppTheme.space20,
                    0,
                    AppTheme.space20,
                    AppTheme.space24,
                  ),
                  child: BetterAlternativesSection(
                    currentDsldId: widget.dsldId,
                    category: _product?.primaryCategory,
                    currentScore: score100 ?? 0,
                  ),
                );
              },
            ),
          ),

          // T1.14 Section 13 — Transparency footer. Always rendered.
          // No personalization (it's site-wide trust language). Sits
          // above the bottom action-bar clearance padding.
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                AppTheme.space20,
                AppTheme.space8,
                AppTheme.space20,
                AppTheme.space8,
              ),
              child: TransparencyFooter(),
            ),
          ),

          // Bottom padding for sticky action bar clearance
          SliverToBoxAdapter(
            child: SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
          ),
        ],
      ),
      // T1.15 Section 14 — sticky action bar. Always rendered (used to
      // be `isBlocked ? null : …` which left blocked products with no
      // bottom affordance). Now blocked/unsafe products get a "See safer
      // alternatives" primary that scrolls to the Better Alternatives
      // section via [_alternativesKey].
      //
      // 2026-04-30 — chrome (padding, surface bg, top border, safe area)
      // moved INSIDE [PGStackActionButtons] so the whole bar can
      // cross-fade to height 0 once the in-stack confirmation window
      // expires. Pre-fix the Container wrapper here would persist as a
      // padded styled strip even after the inner pill collapsed.
      bottomNavigationBar: PGStackActionButtons(
        dsldId: widget.dsldId,
        isUnsafe: isBlocked,
        onSeeAlternatives: _handleSeeAlternatives,
      ),
    );
  }

  // T1.12 — `_shouldShowAlternatives` was removed in favor of the
  // public `shouldShowBetterAlternatives(...)` pure helper exported
  // from `better_alternatives.dart`. The new helper is fit-aware
  // (FitLimitedFit / FitNotRecommended also fire the section) and
  // the threshold tightened from 55 → 60 per T1.12 spec.

  /// T1.15 — primary tap target for the unsafe-verdict sticky bar.
  /// Scrolls the screen to the Better Alternatives sliver. No-op
  /// when the sliver hasn't been laid out yet (off-screen or
  /// shouldShowBetterAlternatives returned false).
  ///
  /// Wrapped in try/catch so platform-edge failures (no Scrollable
  /// ancestor in some tree configurations, render object not yet
  /// laid out, etc.) don't surface as new Sentry error classes —
  /// the worst case is the user gets no scroll, not a crash.
  void _handleSeeAlternatives() {
    final ctx = _alternativesKey.currentContext;
    if (ctx == null) return;
    try {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        alignment: 0.1,
      );
    } on Exception {
      // No-op — the user is no worse off than the deferred-key case.
    }
  }

  // T8 (2026-04-29) — removed `_handleLogDose` placeholder method.
  // The Log Dose secondary action is gone from the product page; it
  // belongs on the stack screen. See `INITIATIVE_PRODUCT_DETAIL_
  // CLEANUP.md` S2.1 / T8.

  /// Worst-applicable severity across the personalized + blob warnings —
  /// drives T1.3's risk-gate inside the For You section. Empty list →
  /// `Severity.safe` (the no-issues baseline).
  static Severity _maxSeverityOf(List<InteractionWarning> warnings) {
    Severity worst = Severity.safe;
    for (final w in warnings) {
      if (w.severity.weight > worst.weight) worst = w.severity;
    }
    return worst;
  }

  /// Inside-state proxy for [topGoalLabelFromFit] so the screen's
  /// build flow can call it as a member. The actual implementation
  /// is the top-level function (testable without pumping the whole
  /// screen widget).
  static String? _topGoalLabelFromFit(FitScoreResult? result) =>
      topGoalLabelFromFit(result);

  List<Map<String, dynamic>> _topWarnings() {
    final raw = _product?.topWarnings;
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.whereType<Map<String, dynamic>>().toList();
      }
      return [];
    } on FormatException {
      return [];
    }
  }

  List<({String label, bool isCertification})> _buildAllTags() {
    final tags = <({String label, bool isCertification})>[];
    // Certifications first — these are trust signals
    if (_product?.hasThirdPartyTesting == 1) {
      tags.add((label: 'Third-Party Tested', isCertification: true));
    }
    if (_product?.isTrustedManufacturer == 1) {
      tags.add((label: 'Trusted Manufacturer', isCertification: true));
    }
    // Dietary tags
    if (_product?.isVegan == 1) {
      tags.add((label: 'Vegan', isCertification: false));
    }
    if (_product?.isGlutenFree == 1) {
      tags.add((label: 'Gluten-Free', isCertification: false));
    }
    if (_product?.isDairyFree == 1) {
      tags.add((label: 'Dairy-Free', isCertification: false));
    }
    if (_product?.isSoyFree == 1) {
      tags.add((label: 'Soy-Free', isCertification: false));
    }
    if (_product?.isOrganic == 1) {
      tags.add((label: 'Organic', isCertification: true));
    }
    if (_product?.isNonGmo == 1) {
      tags.add((label: 'Non-GMO', isCertification: false));
    }
    return tags;
  }

  List<InteractionWarning> _parseWarnings(Map<String, dynamic>? blob) {
    if (blob == null) return [];
    // Pipeline emits two separate warning lists:
    //   `warnings`                — always-visible safety alerts (banned,
    //                                recalled, harmful additives, allergens,
    //                                drug/condition interactions).
    //   `warnings_profile_gated`  — conditionally surfaced alerts that carry
    //                                condition_ids / drug_class_ids tags and
    //                                are filtered downstream by the active
    //                                user profile (e.g. Titanium Dioxide
    //                                EU-ban high-risk alert for pregnancy).
    // Both share the InteractionWarning schema, so we concatenate them
    // here and let the `InteractionWarningsList.filteredWarnings` pass
    // handle profile-based suppression. Not emitting the gated list would
    // silently lose high-risk alerts the pipeline has already curated.
    final result = <InteractionWarning>[];
    final hasStructuredProductStatus = blob['product_status'] is Map;
    for (final key in const ['warnings', 'warnings_profile_gated']) {
      final raw = blob[key];
      if (raw is! List) continue;
      result.addAll(
        raw
            .whereType<Map<String, dynamic>>()
            .where(
              (warning) => !_isLegacyProductStatusWarning(
                warning,
                hasStructuredProductStatus: hasStructuredProductStatus,
              ),
            )
            .map(InteractionWarning.fromJson),
      );
    }
    // FLTR-12 — real blobs contain duplicates in two shapes:
    //   (a) same semantic entry in both `warnings` and
    //       `warnings_profile_gated`
    //   (b) pipeline emits the same entry twice inside one list
    //       (e.g., "Vitamin A / pregnancy" 2× on dsld 15640).
    // Collapse both via composite dedup key (conditions + drug classes
    // + normalized headline + normalized body) with severity-normalize-
    // before-dedup — the highest severity wins when collisions carry
    // mixed labels ("monitor" + "caution" → keep caution).
    return InteractionWarning.dedupe(result);
  }

  bool _isLegacyProductStatusWarning(
    Map<String, dynamic> warning, {
    required bool hasStructuredProductStatus,
  }) {
    if (!hasStructuredProductStatus) return false;
    final tokens = [
      warning['type'],
      warning['source'],
      warning['category'],
      warning['warning_type'],
    ].map((value) => value?.toString().trim().toLowerCase() ?? '');
    return tokens.contains('status') || tokens.contains('product_status');
  }

  // T11 (2026-04-29) — `_showScoreEducation` + `_ScoreEducationSheet`
  // removed. The score-ring tap-to-explain flow no longer fires
  // (`ScoreLine` doesn't carry an info affordance in V1). Future
  // sprint can reintroduce a tap-to-explain via a new help icon next
  // to the tier label if user testing surfaces a need.
}

/// Best-effort top goal label for the For You section's verdict
/// headline copy (e.g. `"Sleep Quality"`,
/// `"Cardiovascular/Heart Health"`). Pulled from the FitScore result's
/// `reasons` list, which the engine orders by relevance (see
/// `FitScoreService._goalReasons` → "Supports your <label> goal.").
///
/// Returns null when no goal-shaped reason surfaces — the For You
/// section then falls back to the generic "your profile" headline.
///
/// Pattern note: `(.+?)` is non-greedy and matches ANY character
/// (including `/`, `&`, `,`) so labels like "Reduce Stress/Anxiety",
/// "Focus & Mental Clarity", and "Skin, Hair, & Nails" all extract
/// cleanly. Anchoring on `\s+goal\b` ensures the boundary is the
/// literal word "goal", not a substring of e.g. "goalkeeper".
///
/// Top-level so it can be unit-tested directly without pumping the
/// whole product detail screen widget. Both `_ProductDetailScreenState`
/// (via `_topGoalLabelFromFit`) and the test suite call this.
String? topGoalLabelFromFit(FitScoreResult? result) {
  if (result == null) return null;
  final pattern = RegExp(r'your\s+(.+?)\s+goal\b', caseSensitive: false);
  for (final reason in result.reasons) {
    final m = pattern.firstMatch(reason);
    if (m != null) {
      final label = m.group(1)?.trim();
      if (label != null && label.isNotEmpty) return label;
    }
  }
  return null;
}

/// Product-detail warning gate shared by the top "For You" card and the
/// deeper warning stack. Profile-tagged rules only render when the
/// active profile matches; global critical/informational warnings still
/// render without a profile match. Product-level UL exceedance warnings
/// are synthesized here because they live under `rda_ul_data`, not the
/// top-level warning lists.
List<InteractionWarning> filterProductDetailWarningsForProfile({
  required Map<String, dynamic>? detailBlob,
  required List<InteractionWarning> warnings,
  required Set<String> userConditions,
  required Set<String> userDrugClasses,
}) {
  final combinedWarnings = [..._synthesizeUlWarnings(detailBlob), ...warnings];

  // T4 (2026-04-29) — apply (condition, ingredient, dose) threshold
  // gating BEFORE the profile-visibility filter. Drops false-positive
  // condition monitor warnings the pipeline emits without dose
  // awareness (Vit D + TTC, Mg + diabetes, etc.). UL warnings carry
  // no conditionIds so they pass through untouched. Spec:
  // INITIATIVE_PRODUCT_DETAIL_CLEANUP.md S2.1 / T3 + T4.
  final ingredientDoses = extractIngredientDoses(detailBlob);
  final gatedWarnings = applyConditionThresholdGate(
    warnings: combinedWarnings,
    ingredientDoses: ingredientDoses,
  );

  return gatedWarnings
      .where((w) {
        if (w.matchesProfile(
          userConditions: userConditions,
          userDrugClasses: userDrugClasses,
        )) {
          return true;
        }

        // Profile-tagged rules are never promoted to global alerts when the
        // current user does not match them. This prevents pregnancy, kidney,
        // and medication warnings from reading as personal guidance for the
        // wrong profile even if an older blob marked them critical.
        if (w.conditionIds.isNotEmpty || w.drugClassIds.isNotEmpty) {
          return false;
        }

        final mode = w.displayModeDefault;
        if (mode == 'critical' || mode == 'informational') return true;
        if (mode == 'suppress') return false;

        // Legacy blobs predating display_mode_default had no explicit gate.
        // Untagged legacy warnings remain visible for backward compatibility.
        return true;
      })
      .toList(growable: false);
}

List<InteractionWarning> _synthesizeUlWarnings(Map<String, dynamic>? blob) {
  final ulAnalysis =
      ((blob?['rda_ul_data'] as Map<String, dynamic>?)?['analyzed_ingredients']
              as List?)
          ?.whereType<Map<String, dynamic>>()
          .toList();
  final ulExceedances = extractUlExceedances(ulAnalysis);
  return ulExceedances
      .map(
        (e) => InteractionWarning(
          severity: Severity.avoid,
          evidenceLevel: EvidenceLevel.established,
          title: 'Exceeds upper limit: ${e.standardName}',
          mechanism: e.warning,
          management: 'Reduce dose or consult a healthcare provider.',
          displayModeDefault: 'critical',
        ),
      )
      .toList(growable: false);
}



/// Strip noisy numeric or "Tier N" detail strings emitted by the
/// pipeline (e.g. `score_bonuses[i].detail == "3"` for the delivery
/// tier). The user can't interpret a bare number under a label like
/// "Advanced delivery system" — it reads as a bug.
///
/// Pipeline-side fix to emit prose detail directly is tracked as T3.4
/// in `INITIATIVE_PRODUCT_TRUST_AND_IA.md`. This is the Flutter-side
/// safety net.
///
/// Returns an empty string when the input is null, blank, a bare
/// integer, or "Tier N" (case-insensitive). Otherwise returns the
/// trimmed input unchanged.
final RegExp _whyDetailNoise = RegExp(
  r'^(?:\d+|tier\s+\d+)$',
  caseSensitive: false,
);
String sanitizeWhyDetail(String? raw) {
  if (raw == null) return '';
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';
  if (_whyDetailNoise.hasMatch(trimmed)) return '';
  return trimmed;
}

List<({String label, String detail, bool isPositive})> _extractWhyItems(
  Map<String, dynamic>? blob,
) {
  if (blob == null) return const [];
  final bonuses =
      (blob['score_bonuses'] as List?)
          ?.whereType<Map<String, dynamic>>()
          .toList() ??
      [];
  final penalties =
      (blob['score_penalties'] as List?)
          ?.whereType<Map<String, dynamic>>()
          .toList() ??
      [];

  return <({String label, String detail, bool isPositive})>[
    ...bonuses.map(
      (b) => (
        label: b['label']?.toString() ?? b['reason']?.toString() ?? '',
        detail: sanitizeWhyDetail(
          b['detail']?.toString() ?? b['description']?.toString(),
        ),
        isPositive: true,
      ),
    ),
    ...penalties.map(
      (p) => (
        label: p['label']?.toString() ?? p['reason']?.toString() ?? '',
        detail: sanitizeWhyDetail(
          p['detail']?.toString() ?? p['description']?.toString(),
        ),
        isPositive: false,
      ),
    ),
  ].where((item) => item.label.trim().isNotEmpty).toList();
  // T15 (2026-04-29 PM) — removed `.take(3)` total-items cap. Per-side
  // cap (4 bonuses, 4 penalties) lives in `TradeoffsSection.build`,
  // which also computes the "and N more" overflow footer. Pre-T15 the
  // global cap meant a product with 5 bonuses + 0 penalties showed 3
  // bonuses; with T15's per-side cap it shows all 4 (or 4 + "and 1
  // more").
}

// _pickHeroScoreReason was removed in T1.1 (2026-04-29) — the hero no
// longer renders an inline score-reason line. The reasoning rows live
// in T1.6 Tradeoffs (Section 5) instead. _extractWhyItems is still
// used by the deep-dive sections so it stays.

// ---------------------------------------------------------------------------
// Hero subtitle helpers (G.3, 2026-04-29)
// ---------------------------------------------------------------------------

/// True when at least one subtitle segment has content. Skip rendering
/// the subtitle row entirely when all three are empty (avoids an empty
/// `Text.rich` painting a zero-height layout artifact).
bool _hasAnyHeroSubtitle(String brand, String form, String? dose) =>
    brand.isNotEmpty || form.isNotEmpty || (dose != null && dose.isNotEmpty);

/// Known clean form-noun keywords. Used by [_extractFormNoun] to pick a
/// premium-looking word out of a messy pipeline `form_factor` value
/// (e.g., `"30 round yello tablet"` → `"Tablet"`).
const Set<String> _knownFormNouns = {
  'capsule',
  'capsules',
  'softgel',
  'softgels',
  'tablet',
  'tablets',
  'caplet',
  'caplets',
  'gummy',
  'gummies',
  'liquid',
  'powder',
  'tincture',
  'drops',
  'lozenge',
  'lozenges',
  'spray',
  'cream',
  'patch',
  'patches',
};

/// Pull a single clean form-noun out of a free-form `form_factor`
/// string. The pipeline ships values that range from clean
/// (`"Capsules"`) to noisy (`"30 round yello tablet"`); the hero
/// subtitle should display only the form word, not the embedded count
/// or descriptive prefix. Returns null when no recognizable noun
/// surfaces — caller drops the segment cleanly.
///
/// T11.1 (2026-04-29 PM, post live walkthrough fix): Sean caught
/// products rendering as "Vitamin D · GNC · 30 round yello tablet"
/// when the pipeline form_factor was the full descriptor.
String? _extractFormNoun(String raw) {
  if (raw.trim().isEmpty) return null;
  final words = raw.toLowerCase().split(RegExp(r'\s+'));
  for (final w in words) {
    if (_knownFormNouns.contains(w)) {
      return '${w[0].toUpperCase()}${w.substring(1)}';
    }
  }
  return null;
}

/// Mass-noun form factors that don't take a count modifier in
/// English ("600 Liquids" reads as a typo). When the form is one of
/// these, [_formatServingsForm] drops the count and renders just the
/// form word — the dosing-summary segment ("Take 2 drops three times
/// daily") already conveys quantity for liquids/powders.
const Set<String> _massNounForms = {'Liquid', 'Powder', 'Tincture'};

/// Build the middle subtitle segment from servings-per-container +
/// form factor. Combines them with proper singular/plural agreement:
/// `60 Capsules` / `1 Capsule` / `30 Tablets`. Mass nouns
/// (Liquid/Powder/Tincture) drop the count. Falls back gracefully:
///   - servings + countable form → `"60 Capsules"`
///   - servings + mass-noun form → `"Liquid"` (count dropped)
///   - servings only             → `"60"` (better than nothing)
///   - form only                 → `"Capsules"`
///   - neither                   → null
///
/// T11.1 — replaces the prior call to `formatNetContents(...)` which
/// produced awkward strings like "1 Fluid Ounce(s)" for liquid
/// products. T12.1 (2026-04-29 PM live walkthrough) added the mass-
/// noun handling — Sean caught "600 Liquids · Take 2 drops three
/// times daily" rendering after T11.1.
String? _formatServingsForm(int? servings, String rawForm) {
  final form = _extractFormNoun(rawForm);
  if (servings == null || servings <= 0) {
    return form; // form-only or null
  }
  if (form == null) {
    return '$servings'; // servings-only
  }
  // Mass nouns: count is meaningless ("600 Liquids" = grammatically
  // odd). Render form alone; dosing summary segment carries quantity.
  if (_massNounForms.contains(form)) {
    return form;
  }
  // Naive singular agreement: drop trailing 's' when count == 1 and
  // the form is plural.
  if (servings == 1 && form.endsWith('s')) {
    return '$servings ${form.substring(0, form.length - 1)}';
  }
  // Pluralize singular forms when count > 1 (e.g., "Capsule" → "Capsules").
  if (servings > 1 && !form.endsWith('s')) {
    // Form-specific plural: "Gummy" → "Gummies" not "Gummys".
    if (form == 'Gummy') return '$servings Gummies';
    return '$servings ${form}s';
  }
  return '$servings $form';
}

/// Capitalize the first character of [s] iff it isn't already
/// uppercase. T11.1 hygiene — pipeline data ranges from clean
/// ("Thorne") to inconsistent ("thorne", "take 1 tablet daily"); this
/// keeps the hero subtitle reading like a premium label without
/// over-titlecasing already-uppercased input ("GNC" stays "GNC").
String _capFirst(String s) {
  if (s.isEmpty) return s;
  final first = s[0];
  if (first.toUpperCase() == first) return s;
  return '${first.toUpperCase()}${s.substring(1)}';
}

/// Builds the dot-separated hero subtitle: `Brand  ·  Form  ·  Dose`.
/// Drops orphan dots — if `brand` is empty but `form` is present, the
/// result starts with `form`, not ` · form`. App Store / Apple Health
/// inline-subtitle pattern: more compact than the prior stacked
/// `[brand]\n[form]` Text widgets and matches the premium-feel reference.
TextSpan _buildHeroSubtitleSpan({
  required BuildContext context,
  required String brand,
  required String form,
  String? dose,
}) {
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;
  final segments = <String>[
    if (brand.isNotEmpty) _capFirst(brand),
    if (form.isNotEmpty) _capFirst(form),
    if (dose != null && dose.isNotEmpty) _capFirst(dose),
  ];
  return TextSpan(
    // T16.1 (2026-04-30) — tighten subtitle. Pre-T16.1: 14pt, two
    // spaces around dots ('  ·  '). For long brands like "Pure
    // encapsulations" + "Take 2 capsules daily" the segments wrapped
    // mid-text and looked unpremium. App Store / Apple Health
    // convention: tighter density on a single line, soft-wrap to a
    // second line gracefully when content is genuinely too long.
    text: segments.join(' · '),
    style: theme.textTheme.bodyMedium?.copyWith(
      fontSize: 13,
      color: scheme.onSurfaceVariant,
      fontWeight: FontWeight.w500,
      letterSpacing: -0.05,
    ),
  );
}

// ---------------------------------------------------------------------------
// Header section
// ---------------------------------------------------------------------------

/// Score-led product detail hero.
///
/// **T11 rebuild (2026-04-29)** — replaces the score-ring altar with a
/// compact text-based [ScoreLine]. New layout:
///   1. Identity row — 96pt image + title + dot-separated subtitle
///      (Brand · Net contents · Dosing summary)
///   2. Dietary / certification chips — one row, small outlined
///   3. Score line — `● 90/100 Exceptional` + tier description
///   4. Safety verdict banner — only when blocked/avoid (rendered last
///      so the score is read first; the banner expands beneath when
///      it fires)
///
/// `PGScoreRing` is still used elsewhere (search-list rows) but no
/// longer appears in the hero. The 96pt ring + "PG SCORE" label freed
/// ~120pt of vertical real estate.
///
/// Notable T11 carryovers from prior cleanups:
///   * Image is tap-to-fullscreen (T1)
///   * Subtitle is dot-separated inline (App Store / Apple Health
///     pattern, G.3 cleanup 2026-04-29)
///
/// Spec: INITIATIVE_PRODUCT_DETAIL_CLEANUP.md, Sprint S2.2, T11.
class _HeaderSection extends ConsumerWidget {
  final String dsldId;
  final String productName;
  final String brandName;
  final String formFactor;
  final String verdict;
  final String blockingReason;
  final double? score100;
  final List<({String label, bool isCertification})> dietaryTags;
  final bool isNotScored;
  final List<Map<String, dynamic>> topWarnings;
  final Map<String, dynamic>? bannedSubstanceDetail;
  final String? upc;
  final String? dsldImagePath;

  /// User-facing dosing summary (e.g., `"1 capsule daily"`,
  /// `"1-2 caps daily"`). Pulled from `_product.dosingSummary`. Null
  /// when the pipeline didn't ship a dosing string for this product;
  /// the subtitle drops the segment cleanly.
  final String? dosingSummary;

  /// Container size in servings — `60` for "60 Capsules". Pulled
  /// from `_product.servingsPerContainer`. Combines with [formFactor]
  /// via `_formatServingsForm` to produce the subtitle's middle
  /// segment with proper singular/plural agreement.
  final int? servingsPerContainer;

  const _HeaderSection({
    required this.dsldId,
    required this.productName,
    required this.brandName,
    required this.formFactor,
    required this.verdict,
    required this.blockingReason,
    required this.score100,
    required this.dietaryTags,
    required this.isNotScored,
    required this.topWarnings,
    this.bannedSubstanceDetail,
    this.upc,
    this.dsldImagePath,
    this.dosingSummary,
    this.servingsPerContainer,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    // T1.1: compute the gated verdict. Banner renders only when severity
    // ≥ Avoid; lower-tier verdicts (Caution / Monitor / Safe / Recommended /
    // etc.) flow through to Section 2 ("For You").
    final heroVerdict = computeHeroVerdict(
      productVerdict: verdict,
      blockingReason: blockingReason,
      topWarnings: topWarnings,
      bannedSubstanceDetail: bannedSubstanceDetail,
    );

    // T11.1 (2026-04-29 PM) — middle subtitle segment is now
    // servings × form (e.g., "60 Capsules") instead of net contents
    // (which produced awkward strings like "1 Fluid Ounce(s)" for
    // liquids). The helper strips noise out of the pipeline
    // form_factor — products shipping as "30 round yello tablet"
    // now render as "30 Tablets". Falls back to a clean form noun
    // when servings is missing.
    final servingsLabel =
        _formatServingsForm(servingsPerContainer, formFactor) ?? '';

    // Single elevated surface for the hero — replaces the previous
    // nested Container + DecoratedBox. PGCard.elevated handles
    // surface fill, outline, soft shadow, and dark-mode-aware tint
    // in one place per the design system.
    final disableAnimations =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    return Padding(
      // The outer Container's `color: scheme.surface` + symmetrical
      // padding becomes a Padding here. The screen's CustomScrollView
      // background already paints surface color.
      padding: const EdgeInsets.fromLTRB(
        AppTheme.space20,
        AppTheme.space12,
        AppTheme.space20,
        AppTheme.space16,
      ),
      child: TweenAnimationBuilder<double>(
        // Hero entrance: fade + translate-up over 240ms. Reduce-motion
        // jumps to the final value instantly via `disableAnimations`.
        duration: disableAnimations ? Duration.zero : AppMotion.medium,
        curve: AppMotion.standard,
        tween: Tween<double>(begin: 0.0, end: 1.0),
        builder: (context, t, child) {
          return Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(0, (1 - t) * 8),
              child: child,
            ),
          );
        },
        child: PGCard(
          variant: PGCardVariant.elevated,
          padding: const EdgeInsets.all(AppTheme.space16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Identity row — 96pt image + name / brand / form column.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 96pt thumbnail — the hero's identity anchor. compact:true
                  // forces BrandedPlaceholder's clean colored-square layout
                  // even at this size (the default multi-row "full card"
                  // layout above 56pt is sized for list items and overflows
                  // when stretched to hero proportions).
                  //
                  // G.2 — Hero wrap with tag matching the source thumbnails
                  // in home_recent_scans (carousel card + Show-all sheet).
                  // The user sees the image fly from a 48pt source to this
                  // 96pt destination — App Store / Apple Health signature
                  // shared-element transition. flightShuttleBuilder uses the
                  // destination at full 96pt, compact:true so the in-flight
                  // frame is the larger crop (cleaner mid-flight than
                  // bilinear-scaling a 48pt source up).
                  Hero(
                    tag: 'product-$dsldId',
                    flightShuttleBuilder: (_, __, ___, ____, _____) =>
                        ProductImage(
                          dsldId: dsldId,
                          upc: upc,
                          dsldImagePath: dsldImagePath,
                          productName: productName,
                          brandName: brandName,
                          formFactor: formFactor,
                          score: score100,
                          size: 96,
                          compact: true,
                        ),
                    child: ProductImage(
                      dsldId: dsldId,
                      upc: upc,
                      dsldImagePath: dsldImagePath,
                      productName: productName,
                      brandName: brandName,
                      formFactor: formFactor,
                      score: score100,
                      size: 96,
                      compact: true,
                      // T1 — tap-to-fullscreen. Reuses the same Hero
                      // tag so the image lifts smoothly from 96pt
                      // into the viewer; placeholder taps are inert.
                      onTap: (imageUrl) => ProductImageViewer.show(
                        context,
                        imageUrl: imageUrl,
                        heroTag: 'product-$dsldId',
                        productName: productName,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppTheme.space16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          productName,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            height: 1.16,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        // T11.1 (2026-04-29 PM) — subtitle: Brand ·
                        // Servings × Form · Dosing summary. Drops
                        // segments cleanly when missing (no orphan
                        // dots).
                        if (_hasAnyHeroSubtitle(
                          brandName,
                          servingsLabel,
                          dosingSummary,
                        )) ...[
                          const SizedBox(height: 4),
                          Text.rich(
                            _buildHeroSubtitleSpan(
                              context: context,
                              brand: brandName,
                              form: servingsLabel,
                              dose: dosingSummary,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        // T11.1 — chips moved INTO the right column
                        // (under subtitle, next to image). The image
                        // now visually owns the left side full-height
                        // for a more premium tile-like feel,
                        // matching Sean's reference sample.
                        if (dietaryTags.isNotEmpty) ...[
                          const SizedBox(height: AppTheme.space8),
                          _HeroTrustChips(tags: dietaryTags),
                        ],
                      ],
                    ),
                  ),
                ],
              ),

              // T11 — text-based score line replaces the 96pt score
              // ring + "PG SCORE" label altar. ~120pt of vertical real
              // estate freed; tier label + description make the score
              // immediately interpretable. Suppressed when the
              // product is BLOCKED — a "DO NOT USE" + "82/100" UI
              // sends mixed signals; the BlockedBanner replaces it.
              if (heroVerdict is! HeroVerdictBlocked && !isNotScored) ...[
                const SizedBox(height: AppTheme.space16),
                ScoreLine(score: (score100 ?? 0).round()),
              ] else if (isNotScored) ...[
                const SizedBox(height: AppTheme.space12),
                Text(
                  'Not enough verified data to score.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],

              // Verdict banner — only renders for Blocked / Avoid /
              // Contraindicated. Lower severities (Caution / Monitor /
              // Safe / Recommended) live in Section 2 ("For You").
              if (heroVerdict is HeroVerdictBlocked) ...[
                const SizedBox(height: AppTheme.space16),
                _BlockedBanner(
                  verdict: heroVerdict.verdict,
                  blockingReason: heroVerdict.blockingReason,
                  topWarnings: heroVerdict.topWarnings,
                  bannedSubstanceDetail: heroVerdict.bannedSubstanceDetail,
                ),
              ] else if (heroVerdict is HeroVerdictAvoid) ...[
                const SizedBox(height: AppTheme.space16),
                PGSeverityBanner(
                  tone: PGBannerTone.danger,
                  title: heroVerdict.headline.toUpperCase(),
                  body:
                      'Interacts with medications in your stack — '
                      'review the details before adding to your stack.',
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// _HeroScoreReason removed in T1.1 — see comment above _pickHeroScoreReason.
// Reasoning lives in T1.6 Tradeoffs section; "Why this score" rows there
// will reuse this DNA once T1.4 / T1.6 are wired.

// T11 (2026-04-29) — `_ScoreRingButton` removed. The 96pt score ring
// + tier-tinted glow + tap-to-explain affordance is replaced by the
// compact text-based `ScoreLine` in the rebuilt header. `PGScoreRing`
// itself is still used in `product_list_item.dart` for the small
// 52pt ring on each search-result row.

class _HeroTrustChips extends StatelessWidget {
  final List<({String label, bool isCertification})> tags;

  const _HeroTrustChips({required this.tags});

  @override
  Widget build(BuildContext context) {
    final visible = tags.take(4).toList(growable: false);
    final overflow = tags.length - visible.length;

    return Wrap(
      // T16.1 (2026-04-30) — tighter inter-chip spacing 8→6 to pair
      // with the smaller chip body, helping "Trusted Manufacturer" +
      // "Gluten Free" fit on one line.
      spacing: 6,
      runSpacing: 6,
      children: [
        ...visible.map(
          (tag) => _HeroTrustChipOutline(
            label: tag.label,
            isCertification: tag.isCertification,
          ),
        ),
        if (overflow > 0)
          _HeroTrustChipOutline(
            label: '+$overflow more',
            isCertification: false,
          ),
      ],
    );
  }
}

/// Outline-only trust chip — Apple iOS chip style.
///
/// No fill, no icon — just a clean text pill with a primary-tinted border.
/// Replaces the filled `_HeroMetaPill` for hero trust signals where the
/// premium iOS feel matters more than the visual loudness of a tinted pill.
///
/// Certifications use `colorScheme.primary` for the border tone (the
/// "this is verified by a real authority" signal); dietary tags use
/// `AppTheme.scoreExcellent` (success green — louder than primary, but
/// still calmer than a filled chip).
class _HeroTrustChipOutline extends StatelessWidget {
  final String label;
  final bool isCertification;

  const _HeroTrustChipOutline({
    required this.label,
    required this.isCertification,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tone = isCertification ? scheme.primary : AppTheme.scoreExcellent;
    // T16.1 (2026-04-30) — second shrink pass. Pre-T16.1: 10×4 / 11pt
    // / 0.8 border. "Trusted Manufacturer" + "Gluten Free" still
    // overflowed the right column on iPhone SE width and ran to a
    // second row. Tightened to 8×3 / 10pt / 0.7 border (10pt is the
    // iOS HIG floor for readable secondary text). Saves ~35pt
    // horizontal, fits both common chip pairs on a single line.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        border: Border.all(color: tone.withValues(alpha: 0.55), width: 0.7),
        borderRadius: BorderRadius.circular(AppTheme.radiusFull),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: tone,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.05,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Blocked / Unsafe full-width banner — uses PGSeverityBanner for the base
// surface and adds FDA source links inline.
// ---------------------------------------------------------------------------

class _BlockedBanner extends StatelessWidget {
  final String verdict;
  final String blockingReason;
  final List<Map<String, dynamic>> topWarnings;
  final Map<String, dynamic>? bannedSubstanceDetail;

  const _BlockedBanner({
    required this.verdict,
    required this.blockingReason,
    required this.topWarnings,
    this.bannedSubstanceDetail,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final substanceName = bannedSubstanceDetail?['substance_name']
        ?.toString()
        .trim();
    final oneLiner = bannedSubstanceDetail?['safety_warning_one_liner']
        ?.toString()
        .trim();
    final safetyWarning = bannedSubstanceDetail?['safety_warning']
        ?.toString()
        .trim();
    final reasonText = oneLiner != null && oneLiner.isNotEmpty
        ? oneLiner
        : blockingReason.isNotEmpty
        ? blockingReason
        : 'This product is flagged as unsafe.';
    final fdaLinks = _extractFdaLinks(topWarnings);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PGSeverityBanner(
          tone: PGBannerTone.danger,
          title: verdict.toUpperCase(),
          body: reasonText,
        ),
        if (substanceName != null && substanceName.isNotEmpty) ...[
          const SizedBox(height: AppTheme.space12),
          Text(
            'Banned ingredient detected: $substanceName',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
        ],
        if (safetyWarning != null && safetyWarning.isNotEmpty) ...[
          const SizedBox(height: AppTheme.space8),
          Text(
            safetyWarning,
            style: theme.textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
        ],
        const SizedBox(height: AppTheme.space12),
        Container(
          padding: const EdgeInsets.all(AppTheme.space12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.do_not_disturb_on_outlined,
                color: AppTheme.severityContraindicated,
                size: 18,
              ),
              const SizedBox(width: AppTheme.space8),
              Expanded(
                child: Text(
                  'Do not use this product',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (fdaLinks.isNotEmpty) ...[
          const SizedBox(height: AppTheme.space8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.space4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'FDA sources',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.severityContraindicated,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 4),
                ...fdaLinks.map(
                  (url) => InkWell(
                    onTap: () async {
                      final uri = Uri.tryParse(url);
                      if (uri != null) {
                        await launchUrl(
                          uri,
                          mode: LaunchMode.externalApplication,
                        );
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.open_in_new_rounded,
                            size: 11,
                            color: AppTheme.severityContraindicated,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              url,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: AppTheme.severityContraindicated,
                                decoration: TextDecoration.underline,
                                overflow: TextOverflow.ellipsis,
                              ),
                              maxLines: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  List<String> _extractFdaLinks(List<Map<String, dynamic>> warnings) {
    final links = <String>[];
    for (final w in warnings) {
      final urls = w['source_urls'];
      if (urls is List) {
        for (final u in urls) {
          final str = u.toString();
          if (str.contains('fda.gov') || str.contains('recall')) {
            links.add(str);
          }
        }
      }
    }
    return links;
  }
}

// ---------------------------------------------------------------------------
// Detail section (loaded from blob)
// ---------------------------------------------------------------------------

class DetailSection extends ConsumerWidget {
  final Map<String, dynamic>? detailBlob;
  final List<InteractionWarning> warnings;

  // T1.7 — trust signals consumed by `UnknownsSection`. Passed in
  // from the parent screen so this widget stays decoupled from the
  // screen state's `_product` reference.
  final bool isTrustedManufacturer;
  final bool hasThirdPartyTesting;
  final double? mappedCoverage;
  final double? scoreEvidenceResearch;
  final double? scoreEvidenceResearchMax;

  // T1.11 — Product Details (Section 10). Same decoupling pattern as
  // the T1.7 trust signals: parent reads off `_product`, we just
  // render. Manufacturer name + country still come from
  // `detailBlob.manufacturer_info` already in scope here.
  final String? dosingSummary;
  final int? servingsPerContainer;
  final double? netContentsQuantity;
  final String? netContentsUnit;
  final String? formFactor;

  const DetailSection({
    super.key,
    required this.detailBlob,
    required this.warnings,
    this.isTrustedManufacturer = false,
    this.hasThirdPartyTesting = false,
    this.mappedCoverage,
    this.scoreEvidenceResearch,
    this.scoreEvidenceResearchMax,
    this.dosingSummary,
    this.servingsPerContainer,
    this.netContentsQuantity,
    this.netContentsUnit,
    this.formFactor,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Local aliases so null-promotion works downstream (fields don't
    // promote across reads — locals do).
    final detailBlob = this.detailBlob;
    final warnings = this.warnings;

    // User's active conditions and drug classes for personalized filtering.
    // A multivitamin interacts with dozens of conditions in general — but
    // we only want to show ones the user has flagged on their profile.
    final profile = ref.watch(profileProvider);
    final userConditions = profile.conditions.toSet();
    final userDrugClasses = profile.drugClasses.toSet();

    if (detailBlob == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          'No additional details available.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final blob = detailBlob;

    // Parse structured data from blob
    final ingredients =
        (blob['ingredients'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .toList() ??
        [];
    // FLTR-6 — dedupe by normalized name at the parse boundary.
    // Real blobs repeat excipients (e.g., "cellulose" twice on
    // GlutenAssure Multivitamin, "ethyl vanillin" twice on Enhanced
    // Krill Plus). Dedupe once; downstream renderers see a clean
    // list.
    final inactiveIngredients = dedupeInactivesForDisplay(
      (blob['inactive_ingredients'] as List?)
              ?.whereType<Map<String, dynamic>>() ??
          const <Map<String, dynamic>>[],
    );

    // FLTR-11 — per-ingredient UL evaluation lives under the top-level
    // rda_ul_data block. Pulled out here so _CollapsibleIngredients
    // can match each ingredient row to its UL entry once, and so the
    // _SafetyTag can render a dose-safety badge that honors the
    // pipeline's skip_ul_check signal.
    final ulAnalysis =
        ((blob['rda_ul_data'] as Map<String, dynamic>?)?['analyzed_ingredients']
                as List?)
            ?.whereType<Map<String, dynamic>>()
            .toList();

    final ingredientsSummary = blob['ingredients_summary']?.toString() ?? '';
    final whyItems = _extractWhyItems(blob);

    // T2A/2B (sprint product_detail_page_sprint.md) — `interactionSummary`
    // and `ingredientDoses` were previously consumed here for the
    // `_InteractionConditionDetails` ("Relevant to your health") section,
    // which has been removed. ReviewBeforeUseCard at the top of the page
    // already gates these against profile via `gateInteractionSummary`.

    // T16.2f (2026-04-30) — proprietary-blend metadata for label-style
    // grouping in the active list. The pipeline emits this whenever a
    // product has a named blend (Eye Health Blend, Energy Complex, etc).
    // Null/empty when the product has no blends — renderer falls
    // through to flat layout in that case.
    final propBlends =
        ((blob['proprietary_blend_detail'] as Map<String, dynamic>?)?['blends']
                as List?)
            ?.whereType<Map<String, dynamic>>()
            .toList(growable: false);

    // FLTR-11a RETIRED (2026-04-24) — pipeline E1.11 now emits
    // dose-aware severity at source, so no Flutter-side downgrade
    // pass is needed. Pass profile-filtered warnings through directly.
    final guardedWarnings = filterProductDetailWarningsForProfile(
      detailBlob: blob,
      warnings: warnings,
      userConditions: userConditions,
      userDrugClasses: userDrugClasses,
    );
    // T16 — `visibleInactives` / `hiddenInactivesCount` removed.
    // The 8-chip cap + "+N more" pill logic now lives inside
    // `IngredientsCard` which also drives the new color-dotted
    // expanded list.

    // Section ordering matches the IA spec exactly — see
    // INITIATIVE_PRODUCT_TRUST_AND_IA.md "IA structure":
    //   §4 Ingredients (active + inactive)
    //   §5 Tradeoffs
    //   §6 What we don't know
    //   §7 Interactions  (7.1 With your stack + 7.2 legacy generic)
    //   §8 Populations
    //   §10 Product Details (collapsed)
    //
    // Section 9 (Evidence), §11 (Better Alternatives), §12 (Deep Dive),
    // §13 (Transparency Footer) and §14 (Sticky Action Bar) live on
    // the outer screen, not inside this Column.
    //
    // Pre-2026-04-29-review ordering rendered Tradeoffs BEFORE
    // ingredients and stranded `_InteractionConditionDetails` between
    // §4 and §6. Both bugs caught by Sean's dev review and fixed
    // here. See T1.16 close-out notes for context.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ---- §4 Ingredients (T16 merged card) ----
        // T16 (2026-04-30) — was two separate sections (active list +
        // inactive chip wrap). Now a single elevated `IngredientsCard`
        // with an internal divider. Active rendering still flows
        // through `_CollapsibleIngredients` (passed as `activeContent`);
        // inactive sub-section gets a "See all N ⌄" toggle that
        // reveals the FULL list with `inactiveColorRank` color dots.
        if (ingredients.isNotEmpty || inactiveIngredients.isNotEmpty) ...[
          IngredientsCard(
            activeContent: ingredients.isNotEmpty
                ? _CollapsibleIngredients(
                    ingredients: ingredients,
                    ulAnalysis: ulAnalysis,
                    blends: propBlends,
                  )
                : null,
            // Pass full pipeline rows — `severity_level` drives the
            // color dot, `functional_roles[]` drives the tap modal.
            // Filter out rows without a usable name (defensive).
            inactiveIngredients: inactiveIngredients
                .where(
                  (ing) =>
                      ((ing['name']?.toString() ?? '').isNotEmpty) ||
                      ((ing['raw_source_text']?.toString() ?? '').isNotEmpty),
                )
                .toList(growable: false),
          ),
          const SizedBox(height: 20),
        ] else if (ingredientsSummary.isNotEmpty) ...[
          // Legacy fallback path — when the pipeline ships only a
          // free-text `ingredients_summary` blob (no structured
          // active list and no inactives), render the summary alone.
          // Rare; pre-T16 behavior preserved here.
          Text(
            'Ingredients',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            ingredientsSummary,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
        ],

        // FLTR-20 — the standalone "Form & Absorption" card was
        // removed; form-quality tiers now render inline on each
        // active ingredient row via [_SafetyTag]. The underlying
        // `FormAbsorptionSection` widget stays in the repo for
        // potential reuse (e.g. a dedicated explainer) — it's no
        // longer wired into the scroll.

        // ---- §5 Tradeoffs ----
        if (whyItems.isNotEmpty) ...[
          // T1.6 — replaces the pre-Sprint-1 single-column Highlights
          // with a two-column "What's good / What to consider" split.
          // Same upstream `whyItems` record list (already sanitized
          // via T0.2's `sanitizeWhyDetail` inside `_extractWhyItems`),
          // routed through the new `TradeoffsSection` which splits +
          // renders + handles the empty-side and SE-class
          // single-column fallback.
          TradeoffsSection(
            items: whyItems,
            inactiveIngredients: inactiveIngredients,
          ),
          const SizedBox(height: 20),
        ],

        // ---- §6 What we don't know — REMOVED 2026-04-30 ----
        // Sean's call: redundant with the trust signals already
        // surfaced in §5 Tradeoffs ("Third-party tested" / "no recent
        // COAs") and the §10 Footer's coverage / sources lines. The
        // standalone gap-list was noise.
        //
        // §7.1 / §7.2 — WithYourStackSection + _InteractionConditionDetails
        // REMOVED 2026-05-05 (Phase 2B / sprint product_detail_page_sprint).
        // Both were re-rendering the same profile-matched interaction
        // data ReviewBeforeUseCard already shows at the top of the page.
        // Useful bits — evidence chip, citation count chip,
        // tap-to-open citations sheet — were lifted into _AlertRow
        // inside ReviewBeforeUseCard so users still have one tap to
        // sources. The "✓ No known interaction" positive trust beat
        // is dropped per Sean: silence in ReviewBeforeUseCard is
        // sufficient — no need for a row that says nothing fired.

        // ---- §7.2 Other precautions — REMOVED 2026-04-30 ----
        // Sean's call: post-T16.2g the AlertSummaryCard accordion at
        // the top of the page already shows every warning inline (no
        // scroll, no extra surface needed). The legacy generic-
        // precautions bucket here was duplicative chrome.

        // ---- §8 Synergy Cluster (T22 — promoted out of Deep Dive) ----
        // T20/T22 (2026-04-30) — `SynergyDetailSection` was previously
        // wrapped inside Deep Dive (collapsed by default), so genuine
        // tier-1 "Proven synergy" qualifications were hidden from the
        // primary IA. Spec line 36 lists Synergy as §8 — a top-level
        // section that surfaces conditionally when high-confidence
        // matches exist. The widget itself self-hides when the T22
        // filter (tier ≤ 2, match_count ≥ 2, all_adequate) yields zero
        // results, so unconditional placement here is safe.
        SynergyDetailSection(
          synergyDetail: detailBlob['synergy_detail'] as Map<String, dynamic>?,
        ),

        // ---- §9 Populations ----
        // T1.9 — at-risk populations dedupe. Aggregates
        // populationWarnings across all warnings, dedupes by string,
        // filters out entries that match the user's profile (those
        // are already surfaced in Section 7's WithYourStackSection),
        // and renders the remainder as "Extra caution for: A, B, C"
        // with an optional "(already covered for X, Y)" line naming
        // the user signals that DID match — so the user knows we
        // considered them, didn't ignore them. Hides entirely when
        // no populations to show OR when dedupe leaves the list
        // empty.
        PopulationsSection(
          warnings: guardedWarnings,
          userConditions: userConditions,
          userDrugClasses: userDrugClasses,
          ageBracket: ref.watch(profileProvider).ageBracket,
        ),

        // T17 (2026-04-30) — Bottom Product Details block deleted per
        // spec (line 83: "merged into header"). Brand + dosing already
        // surface in the hero `_HeaderSection`; manufacturer / net
        // contents / form factor moved to Deep Dive's manufacturer
        // section. Pre-T17 the bottom panel was redundant chrome that
        // pushed real content (Interactions, Populations) further down.
      ],
    );
  }

  // T16 (2026-04-30) — `_sectionTitle` private helper removed. Was
  // only used by the old standalone "Other Ingredients" section
  // header; that section now lives inside `IngredientsCard` with its
  // own integrated title.
}

// _WhyThisProductSection + _ProConTile removed in T1.6 (2026-04-29).
// The single-column "Highlights" card was superseded by `TradeoffsSection`
// (lib/features/product_detail/widgets/tradeoffs_section.dart), which
// splits the same `_extractWhyItems` record list into a two-column
// 👍 What's good / ⚖️ What to consider layout with SE-class fallback.

/// Collapsible wrapper for the Active Ingredients list.
///
/// Multivitamins can have 20+ actives which makes the product page
/// unreadably long. Tap the row (which shows "N Active Ingredients") to
/// toggle the full list open or closed. Collapsed by default for lists
/// longer than 5 ingredients; short lists stay expanded.
class _CollapsibleIngredients extends StatefulWidget {
  final List<Map<String, dynamic>> ingredients;

  /// Pipeline's per-ingredient UL analysis from
  /// `blob.rda_ul_data.analyzed_ingredients`. Null when the blob
  /// lacks the block; each tile will simply not render a UL-based
  /// badge in that case.
  final List<Map<String, dynamic>>? ulAnalysis;

  /// T16.2f (2026-04-30) — pipeline's
  /// `proprietary_blend_detail.blends[]`. When non-empty, ingredients
  /// matching `child_ingredients[].name` render under a label-style
  /// blend header (name + total dose) with indented child rows.
  /// Optional for back-compat with non-blend products.
  final List<Map<String, dynamic>>? blends;

  const _CollapsibleIngredients({
    required this.ingredients,
    this.ulAnalysis,
    this.blends,
  });

  @override
  State<_CollapsibleIngredients> createState() =>
      _CollapsibleIngredientsState();
}

class _CollapsibleIngredientsState extends State<_CollapsibleIngredients> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    // Auto-expand if list is short (<= 5). Long lists start collapsed.
    _expanded = widget.ingredients.length <= 5;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final count = widget.ingredients.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Tappable header row — tap anywhere to toggle.
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Text(
                  'Active Ingredients',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                  ),
                  child: Text(
                    '$count',
                    style: AppTheme.numeric(
                      theme.textTheme.labelSmall!.copyWith(
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(
                    Icons.expand_more_rounded,
                    size: 22,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        // Animated expand/collapse of the list body.
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: _expanded
              ? Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _buildExpandedRows(),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  /// T16.2f (2026-04-30) — build the active-ingredient body, grouping
  /// matched blend members under a label-style header with indented
  /// child rows. Falls through to the pre-T16.2f flat layout when the
  /// product has no proprietary blends OR when no ingredients matched
  /// any blend's children.
  ///
  /// Render order:
  ///   1. Loose disclosed-dose actives (FLTR-9 sort)
  ///   2. Per-blend bucket: header row + indented children (pipeline order)
  ///   3. Loose undisclosed-dose actives (FLTR-9 sort)
  ///
  /// This isolates blend ingredients from loose ones so the user can
  /// tell at a glance which "amount not disclosed" entries are inside a
  /// blend (and therefore have a known parent total) vs. genuinely
  /// non-quantified standalone ingredients.
  List<Widget> _buildExpandedRows() {
    final grouped = groupActivesByBlend(
      ingredients: widget.ingredients,
      blendsRaw: widget.blends,
    );

    if (!grouped.hasBlends) {
      // No blends matched — preserve pre-T16.2f flat behavior.
      return sortActivesForDisplay(widget.ingredients)
          .map(
            (ing) => _IngredientTile(
              ingredient: ing,
              ulEntry: matchUlEntry(ing, widget.ulAnalysis),
            ),
          )
          .toList(growable: false);
    }

    final rows = <Widget>[];
    for (final ing in grouped.looseDisclosed) {
      rows.add(
        _IngredientTile(
          ingredient: ing,
          ulEntry: matchUlEntry(ing, widget.ulAnalysis),
        ),
      );
    }
    for (final blend in grouped.blends) {
      rows.add(_BlendHeaderTile(blend: blend));
      for (final child in blend.children) {
        rows.add(
          Padding(
            padding: const EdgeInsets.only(left: AppTheme.space20),
            child: _IngredientTile(
              ingredient: child,
              ulEntry: matchUlEntry(child, widget.ulAnalysis),
            ),
          ),
        );
      }
    }
    for (final ing in grouped.looseUndisclosed) {
      rows.add(
        _IngredientTile(
          ingredient: ing,
          ulEntry: matchUlEntry(ing, widget.ulAnalysis),
        ),
      );
    }
    return rows;
  }
}

/// T16.2f — proprietary-blend header row matching the supplement-facts
/// label format: bold blend name on the left, total dose on the right.
/// Children render indented below this tile via the renderer.
class _BlendHeaderTile extends StatelessWidget {
  final BlendGroup blend;

  const _BlendHeaderTile({required this.blend});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasTotal = blend.totalAmount != null && blend.unit.isNotEmpty;
    final totalLabel = hasTotal
        ? '${blend.totalAmount} ${blend.unit}'
        : 'Amount not disclosed';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.space8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            Icons.layers_outlined,
            size: 14,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              blend.name,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.1,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            totalLabel,
            style: AppTheme.numeric(
              theme.textTheme.labelSmall!.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A single active ingredient row.
///
/// T4A/T4B (sprint product_detail_page_sprint.md) — Material 3 layout:
///
///   ┌────────────────────────────────────────────┐
///   │ Magnesium                          200 mg  │
///   │ bisglycinate                               │   ← 12sp gray helper
///   │ [Excellent]  [High dose]                   │   ← M3 chips
///   └────────────────────────────────────────────┘
///
/// Whole row is an InkWell that opens [showIngredientExplainSheet].
/// The chips also tap into the same sheet — dual targets, single
/// surface so future-data additions land in one place.
class _IngredientTile extends StatelessWidget {
  final Map<String, dynamic> ingredient;

  /// The UL-analysis entry matched for this ingredient (if any).
  /// Pre-matched by [_CollapsibleIngredients] so we don't re-scan the
  /// list per tile.
  final Map<String, dynamic>? ulEntry;

  const _IngredientTile({required this.ingredient, this.ulEntry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // v1.5.0 canonical contract — pipeline emits explicit display +
    // routing fields so Flutter renders them directly without local
    // inference. See scripts/FINAL_EXPORT_SCHEMA_V1.md for the contract
    // definitions.
    //   display_form_label  user-visible form, null when truly unknown
    //   form_status         'known' | 'unknown'
    //   display_dose_label  pre-formatted dose string
    //   dose_status         'disclosed' | 'not_disclosed_blend' | 'missing'
    //   is_safety_concern   true only for moderate/high/critical hazards
    // Legacy `form` field is read as a fallback for blobs built before
    // the v1.5.0 refactor; it will be removed once all consumers migrate.
    final formStatus = ingredient['form_status']?.toString();
    final displayFormLabel = ingredient['display_form_label']?.toString().trim();
    final legacyForm = ingredient['form']?.toString().trim() ?? '';
    final formLabel = (displayFormLabel != null && displayFormLabel.isNotEmpty)
        ? displayFormLabel
        : legacyForm;
    final hasKnownForm = formStatus != null
        ? formStatus == 'known'
        : formLabel.isNotEmpty;

    final displayLabel = ingredient['display_label']?.toString().trim();
    final cleanName = ingredient['standard_name']?.toString().trim() ??
        ingredient['name']?.toString().trim() ??
        ingredient['raw_source_text']?.toString().trim() ??
        '';
    final name = (hasKnownForm && cleanName.isNotEmpty)
        ? cleanName
        : ((displayLabel != null && displayLabel.isNotEmpty)
            ? displayLabel
            : cleanName);
    final isInferredFromName =
        ingredient['display_type'] == 'inferred_from_name' ||
        ingredient['provenance'] == 'product_name_fallback';

    // Dose: trust display_dose_label (pipeline pre-formats per the
    // three-class rule "X mg" / "Amount not disclosed" / "—"). The legacy
    // quantity+unit fallback is retained ONLY for pre-v1.5.0 blobs.
    final displayDoseLabel = ingredient['display_dose_label']?.toString().trim();
    final doseStatus = ingredient['dose_status']?.toString();
    String doseLabel;
    if (displayDoseLabel != null && displayDoseLabel.isNotEmpty) {
      doseLabel = displayDoseLabel;
    } else if (doseStatus == 'missing' || doseStatus == 'not_disclosed_blend') {
      doseLabel = '';
    } else {
      // Legacy fallback for stale blobs.
      final quantity = ingredient['quantity'];
      final unit = ingredient['unit']?.toString() ?? '';
      doseLabel = quantity != null ? '$quantity $unit'.trim() : '';
    }

    final formQuality = resolveFormQuality(ingredient['bio_score']);
    final doseCallOut = resolveDoseCallOut(
      ingredient: ingredient,
      ulEntry: ulEntry,
    );

    void openSheet() {
      showIngredientExplainSheet(
        context,
        ingredient: ingredient,
        ulEntry: ulEntry,
      );
    }

    return Column(
      children: [
        InkWell(
          onTap: openSheet,
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: AppTheme.space8,
              horizontal: 4,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name + dose row.
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (doseLabel.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(
                          doseLabel,
                          style: AppTheme.numeric(
                            theme.textTheme.labelSmall!.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                // Form helper line (12sp gray) — only when form known.
                if (hasKnownForm && formLabel.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    formLabel.toLowerCase(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
                // Chips row — Form chip + Dose chip (when applicable).
                if (formQuality != FormQuality.unknown ||
                    doseCallOut != DoseCallOut.withinLimits ||
                    isInferredFromName) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (formQuality != FormQuality.unknown)
                        _FormChip(quality: formQuality, onTap: openSheet),
                      if (doseCallOut != DoseCallOut.withinLimits)
                        _DoseChip(callOut: doseCallOut, onTap: openSheet),
                      if (isInferredFromName)
                        const _IngredientMiniChip(
                          label: 'Inferred from label',
                          icon: Icons.manage_search_rounded,
                          color: AppTheme.insufficientData,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        Divider(height: 0.5, thickness: 0.5, color: scheme.outlineVariant),
      ],
    );
  }
}

/// Form-quality chip — short label per the vocabulary contract.
/// Bottom tier ("Poor") uses amber, not red — bioavailability is
/// form quality, not safety.
class _FormChip extends StatelessWidget {
  final FormQuality quality;
  final VoidCallback onTap;

  const _FormChip({required this.quality, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = _color(quality);
    final label = formChipLabel(quality);
    return _PillChip(label: label, color: color, onTap: onTap);
  }

  static Color _color(FormQuality q) {
    switch (q) {
      case FormQuality.excellent:
        return AppTheme.severitySafe;
      case FormQuality.good:
        return AppTheme.scoreGood;
      case FormQuality.fair:
        return AppTheme.severityCaution;
      case FormQuality.poor:
        // Sean: bottom tier is amber, not red — bioavailability is a
        // form-quality signal, not a safety signal.
        return AppTheme.severityCaution;
      case FormQuality.unknown:
        return AppTheme.insufficientData;
    }
  }
}

/// Dose chip — surfaces UL exceedance, sub-clinical dose, or
/// non-disclosed dose. Red only for `High dose` (real safety signal).
class _DoseChip extends StatelessWidget {
  final DoseCallOut callOut;
  final VoidCallback onTap;

  const _DoseChip({required this.callOut, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _PillChip(
      label: doseChipLabel(callOut),
      color: _color(callOut),
      onTap: onTap,
    );
  }

  static Color _color(DoseCallOut d) {
    switch (d) {
      case DoseCallOut.high:
        return AppTheme.severityAvoid; // Red — actual safety signal.
      case DoseCallOut.low:
        return AppTheme.severityCaution;
      case DoseCallOut.notDisclosed:
        return AppTheme.insufficientData;
      case DoseCallOut.withinLimits:
        return AppTheme.severitySafe;
    }
  }
}

/// Compact M3-style pill used by both chips. Tappable; same sheet
/// target as the parent row.
class _PillChip extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _PillChip({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: color,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}

class _IngredientMiniChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const _IngredientMiniChip({
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}


// _ProConTile removed in T1.6 (2026-04-29) along with its only call
// site (_WhyThisProductSection). The colored-bullet equivalent now
// lives as `TradeoffRow` inside `tradeoffs_section.dart`.


// ---------------------------------------------------------------------------
// Shimmer placeholder while detail blob loads
// ---------------------------------------------------------------------------

class _DetailShimmer extends StatelessWidget {
  const _DetailShimmer();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PGShimmerBox(height: 18, width: 120),
        SizedBox(height: AppTheme.space12),
        PGShimmerBox(height: 14),
        SizedBox(height: 6),
        PGShimmerBox(height: 14),
        SizedBox(height: 6),
        PGShimmerBox(height: 14, width: 240),
        SizedBox(height: AppTheme.space24),
        PGShimmerBox(height: 18, width: 160),
        SizedBox(height: AppTheme.space12),
        PGShimmerCard(height: 96),
        SizedBox(height: AppTheme.space12),
        PGShimmerCard(height: 96),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Error state with retry
// ---------------------------------------------------------------------------

class _DetailErrorBanner extends StatelessWidget {
  final VoidCallback onRetry;

  const _DetailErrorBanner({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return PGEmptyState(
      icon: Icons.cloud_off_outlined,
      title: 'Could not load details',
      description: 'Pull to refresh, or try again once you have connectivity.',
      actionLabel: 'Retry',
      onAction: onRetry,
      variant: PGEmptyStateVariant.offline,
    );
  }
}

// Old _ActionButtons removed — replaced by [PGStackActionButtons] which
// handles safety check, add/remove, and undo snackbar.

// T11 (2026-04-29) — `_glowColor` removed. Was the score-tier glow
// hue for the score ring's drop shadow; the ring is gone, so the
// helper is orphaned. The new `ScoreLine` uses `ScoreTier.color`
// directly.

// ---------------------------------------------------------------------------
// Deep dive — collapsible wrapper for detailed analysis sections.
// Keeps the product detail scroll depth manageable while making all data
// accessible on demand. Initially collapsed; user taps to expand.
// ---------------------------------------------------------------------------

class DeepDiveSection extends StatefulWidget {
  final String dsldId;
  final Map<String, dynamic>? certificationDetail;
  final Map<String, dynamic>? evidenceData;
  final Map<String, dynamic>? formulationDetail;
  final Map<String, dynamic>? ingredientQualityData;
  final Map<String, dynamic>? probioticDetail;
  final Map<String, dynamic>? synergyDetail;
  final Map<String, dynamic>? manufacturerDetail;
  final double? caloriesPerServing;
  final Map<String, dynamic>? nutritionDetail;
  final Map<String, dynamic>? unmappedActives;
  final List<Map<String, dynamic>> activeIngredients;
  final List<Map<String, dynamic>> inactiveIngredients;
  final Map<String, dynamic>? heavyMetalDetail;

  const DeepDiveSection({
    super.key,
    required this.dsldId,
    required this.activeIngredients,
    required this.inactiveIngredients,
    this.heavyMetalDetail,
    this.certificationDetail,
    this.evidenceData,
    this.formulationDetail,
    this.ingredientQualityData,
    this.probioticDetail,
    this.synergyDetail,
    this.manufacturerDetail,
    this.caloriesPerServing,
    this.nutritionDetail,
    this.unmappedActives,
  });

  @override
  State<DeepDiveSection> createState() => _DeepDiveSectionState();
}

class _DeepDiveSectionState extends State<DeepDiveSection>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late final AnimationController _ctrl;
  late final Animation<double> _heightFactor;
  late final Animation<double> _iconTurns;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 280),
      vsync: this,
    );
    _heightFactor = _ctrl.drive(CurveTween(curve: Curves.easeOutCubic));
    _iconTurns = _ctrl.drive(
      Tween(begin: 0.0, end: 0.5).chain(CurveTween(curve: Curves.easeOutCubic)),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _expanded = !_expanded;
      if (_expanded) {
        _ctrl.forward();
      } else {
        _ctrl.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Toggle header
        Material(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _toggle,
            splashColor: scheme.primary.withValues(alpha: 0.08),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.space16,
                vertical: AppTheme.space12,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.analytics_outlined,
                    size: 18,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Deep dive',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    _expanded ? 'Hide' : 'Show details',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  RotationTransition(
                    turns: _iconTurns,
                    child: Icon(
                      Icons.expand_more_rounded,
                      size: 20,
                      color: scheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Collapsible content
        ClipRect(
          child: AnimatedBuilder(
            animation: _heightFactor,
            builder: (context, child) => Align(
              heightFactor: _heightFactor.value,
              alignment: Alignment.topCenter,
              child: child,
            ),
            child: Column(
              children: [
                const SizedBox(height: AppTheme.space12),
                CertificationDetailSection(
                  certificationDetail: widget.certificationDetail,
                ),
                const SizedBox(height: AppTheme.space8),
                EvidenceDetailSection(evidenceData: widget.evidenceData),
                const SizedBox(height: AppTheme.space8),
                HeavyMetalWarningCard(
                  heavyMetalDetail: widget.heavyMetalDetail,
                ),
                const SizedBox(height: AppTheme.space8),
                ExcipientDensityCard(
                  activeIngredients: widget.activeIngredients,
                  inactiveIngredients: widget.inactiveIngredients,
                  dosageForm: widget.formulationDetail?['delivery_form']
                      ?.toString(),
                ),
                const SizedBox(height: AppTheme.space8),
                FormulationDetailSection(
                  formulationDetail: widget.formulationDetail,
                  ingredientQualityData: widget.ingredientQualityData,
                ),
                const SizedBox(height: AppTheme.space8),
                ProbioticDetailSection(probioticDetail: widget.probioticDetail),
                const SizedBox(height: AppTheme.space8),
                // T17 (2026-04-30) — `PairsWellSection` deleted per
                // spec (replaced by tightened Synergy Cluster).
                // T20/T22 (2026-04-30) — `SynergyDetailSection`
                // promoted out of Deep Dive to top-level §8 (in the
                // main DetailSection column). See call site there.
                ManufacturerViolationsSection(
                  manufacturerDetail: widget.manufacturerDetail,
                ),
                const SizedBox(height: AppTheme.space8),
                // T18 (2026-04-30) — collapsed full Nutrition Facts
                // panel into a "View supplement facts" link that opens
                // a bottom sheet. Same hide rule applies (no nutrition
                // data → link auto-hides).
                NutritionFactsLink(
                  caloriesPerServing: widget.caloriesPerServing,
                  nutritionDetail: widget.nutritionDetail,
                ),
                // T3 (sprint product_detail_page_sprint.md) —
                // UnmappedActivesDisclosure moved into LabelConfidenceCard.
              ],
            ),
          ),
        ),
      ],
    );
  }
}
