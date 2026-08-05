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
import 'package:pharmaguide/core/constants/schema_ids.dart';
import 'package:pharmaguide/core/extensions/json_helpers.dart';
import 'package:pharmaguide/core/scoring/catalog_product_semantics.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/core/utils/product_canonical_ids.dart';
import 'package:pharmaguide/core/widgets/pg_severity_banner.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/data/providers/reference_data_provider.dart';
import 'package:pharmaguide/features/compare/compare_picker_sheet.dart';
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
import 'package:pharmaguide/features/product_detail/v2/sections/formulation_section.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/heavy_metal_section.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/hero_section.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/ingredients_section.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/label_match_section.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/label_mismatch_action.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/manufacturer_violations_section.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/nutrition_section.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/populations_section.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/probiotic_section.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/research_evidence_section.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/review_before_use_section.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/score_breakdown_section.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/synergy_section.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/tradeoffs_section.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/transparency_footer_section.dart';
import 'package:pharmaguide/features/product_detail/v2/warnings_pipeline.dart';
import 'package:pharmaguide/features/product_detail/widgets/pg_favorite_button.dart';
import 'package:pharmaguide/features/product_detail/widgets/pg_stack_action_buttons.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';
import 'package:pharmaguide/features/stack/providers/stack_safety_providers.dart';
import 'package:pharmaguide/services/perf_trace_service.dart';
import 'package:pharmaguide/services/health/rda_reference_contract.dart';
import 'package:pharmaguide/services/sharing/share_service.dart';
import 'package:pharmaguide/services/warnings/interaction_warning.dart';
import 'package:url_launcher/url_launcher.dart';

/// Null-preserving safe map read for detail-blob fields. Uses the shared
/// [SafeJson.safeMap] helper (no raw `as Map<String, dynamic>?` casts —
/// a pipeline shape drift must degrade, not throw) while keeping the
/// null-vs-present distinction section adapters rely on: absent or
/// non-map values return null, never an empty `{}`.
Map<String, dynamic>? _blobMap(Map<String, dynamic>? blob, String key) {
  if (blob == null || blob[key] == null) return null;
  final m = blob.safeMap(key);
  return m.isEmpty ? null : m;
}

/// Section adapters use `SizedBox.shrink()` as their explicit hidden-state
/// contract. Keep the standard gap only when the adapter renders content so
/// a run of hidden deep-dive sections cannot accumulate blank vertical space.
List<Widget> _sectionWithTrailingGap(Widget section) {
  final suppressed =
      section is SizedBox && section.width == 0 && section.height == 0;
  if (suppressed) return const [];
  return [section, const SizedBox(height: V2Spacing.space12)];
}

/// Parsed ingredient collections for the Product Detail label surface.
///
/// [displayIngredients] is null only when the canonical ledger key is absent.
/// Empty means the key was present but empty or malformed, so the UI must fail
/// closed instead of substituting score-oriented rows.
class ProductDetailIngredientSources {
  final List<Map<String, dynamic>> ingredients;
  final List<Map<String, dynamic>>? displayIngredients;
  final List<Map<String, dynamic>> inactiveIngredients;
  final List<Map<String, dynamic>> blends;

  const ProductDetailIngredientSources({
    required this.ingredients,
    required this.displayIngredients,
    required this.inactiveIngredients,
    required this.blends,
  });
}

/// Parse the four ingredient collections without repairing or partially
/// accepting malformed input. Each list is all-or-nothing: one invalid entry
/// invalidates that collection. This keeps source-label identity separate from
/// the legacy scoring input and makes malformed cached blobs non-fatal.
ProductDetailIngredientSources productDetailIngredientSourcesFromBlob(
  Map<String, dynamic>? blob,
) {
  final hasDisplayLedger = blob?.containsKey('display_ingredients') == true;
  final blendDetail = _blobMap(blob, 'proprietary_blend_detail');

  return ProductDetailIngredientSources(
    ingredients: _strictMapList(blob?['ingredients']),
    displayIngredients: hasDisplayLedger
        ? _strictMapList(blob?['display_ingredients'])
        : null,
    inactiveIngredients: _strictMapList(blob?['inactive_ingredients']),
    blends: _strictMapList(blendDetail?['blends']),
  );
}

List<Map<String, dynamic>> _strictMapList(Object? raw) {
  if (raw is! List) return const [];
  final rows = <Map<String, dynamic>>[];
  for (final row in raw) {
    if (row is! Map<String, dynamic>) return const [];
    rows.add(row);
  }
  return List.unmodifiable(rows);
}

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

  /// Anchors for the score-breakdown pillar deep-links. Ingredients
  /// reuses `_anchors.ingredientsKey`; these cover the sections that
  /// have no pre-existing anchor. The evidence key is attached by
  /// WRAPPING the section's builder call site (KeyedSubtree) — the
  /// section file itself is owned by another change in flight.
  final GlobalKey _evidenceSectionKey = GlobalKey();
  final GlobalKey _certificationsSectionKey = GlobalKey();

  /// One-shot guard: finish the scan→verdict perf trace exactly once per
  /// screen, on the first frame where the hero verdict is visible.
  /// Products opened from search/stack (no active transaction) no-op
  /// inside PerfTraceService.
  bool _verdictTraceFinished = false;
  bool _isSharing = false;

  @override
  void initState() {
    super.initState();
    _loadProduct();
    _scheduleInitialSectionScroll();
  }

  Future<void> _shareProduct() async {
    final product = _product;
    if (product == null || _isSharing) return;
    setState(() => _isSharing = true);
    try {
      final canShareScore =
          !catalogProductIsBlocked(product) &&
          !catalogProductIsNotScored(product);
      await ShareService().shareProduct(
        productName: product.productName,
        brandName: product.brandName,
        qualityScore: canShareScore ? product.qualityScoreV4100 : null,
        qualityTier: canShareScore ? product.qualityTier : null,
        scoreConfidence: canShareScore ? product.v4Confidence : null,
        qualityHighlights: buildHeroTrustTags(
          product,
        ).map((tag) => tag.label).toList(growable: false),
      );
    } on Exception {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Couldn’t open the share sheet. Try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  @override
  void didUpdateWidget(covariant ProductDetailV2ConnectedScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final routeChanged =
        oldWidget.dsldId != widget.dsldId ||
        oldWidget.initialSection != widget.initialSection;
    if (!routeChanged) return;

    _anchors.resetInitialScroll();
    if (mounted && oldWidget.dsldId != widget.dsldId) {
      // New product on the same screen instance — re-arm the one-shot
      // perf-trace finish for the fresh hero render.
      _verdictTraceFinished = false;
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

  /// Smooth-scroll to a pillar's detail section via the shared
  /// prime-and-retry mechanism (`scroll_anchors.dart`). The lazy
  /// SliverList doesn't build below-the-fold sections, so the key's
  /// context is null until the viewport is primed near [primeFraction]
  /// — a plain ensureVisible would silently drop every deep link to a
  /// far section.
  void _scrollToSection(GlobalKey key, {required double primeFraction}) {
    _anchors.scrollToKey(
      key,
      isMounted: () => mounted,
      primeFraction: primeFraction,
    );
  }

  @override
  void dispose() {
    // Backing out before the hero verdict ever rendered would leave the
    // scan→verdict transaction dangling (the NEXT scan would finish it
    // as 'cancelled' with a junk duration). Abort it now instead.
    if (!_verdictTraceFinished) {
      PerfTraceService().abandonScanToVerdict();
    }
    _anchors.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_productLoading) {
      return Scaffold(
        appBar: AppBar(surfaceTintColor: Colors.transparent, elevation: 0),
        body: const _ProductDetailLoadingState(),
      );
    }

    if (_product == null) {
      return Scaffold(
        appBar: AppBar(
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_rounded, color: context.v2.fg),
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
    final ingredientSources = productDetailIngredientSourcesFromBlob(
      detailBlob,
    );
    final labelNutritionRows = labelNutritionRowsForDisplayLedger(
      ingredientSources.displayIngredients,
    );
    final blobLoading = blobAsync.isLoading;
    final blobError = blobAsync.hasError;
    final appRdaReferenceData = ref.watch(rdaOptimalUlsProvider).asData?.value;
    final productRdaUlData = _blobMap(detailBlob, 'rda_ul_data');
    final canUseProductUlData = hasCurrentRdaReference(
      appReferenceData: appRdaReferenceData,
      productRdaUlData: productRdaUlData,
    );
    final productUlAnalysis = canUseProductUlData
        ? (productRdaUlData?['analyzed_ingredients'] as List?)
        : null;

    // -------------------------------------------------------------
    // Warning compose pipeline (see warnings_pipeline.dart)
    // -------------------------------------------------------------
    final personalizedWarningsAsync = ref.watch(
      personalizedInteractionWarningsProvider(widget.dsldId),
    );
    final personalizedWarnings =
        personalizedWarningsAsync.value ?? const <InteractionWarning>[];
    // When the personalized lookup errored, the warning list above is
    // empty for the wrong reason — surface a hedge instead of letting
    // the page imply "no interactions found".
    final personalizedWarningsFailed = personalizedWarningsAsync.hasError;
    final profile = ref.watch(profileProvider);
    final userConditionsSet = profile.conditionsForEvaluator.toSet();
    final userProfileFlagsAsync = ref.watch(evaluatorProfileFlagsProvider);
    // Union the profile picker drug-class chips with the classes of the
    // meds the user actually ADDED to their stack — the same already-
    // resolved source stack safety uses (no re-mapping) — so pipeline
    // drug-gated warnings fire whether the user ticked the chip OR added
    // the medication.
    final stackMedicationClassIds =
        ref.watch(currentStackMedicationClassIdsProvider).value ??
        const <String>{};
    final userDrugClassesSet = <String>{
      ...profile.drugClassesForEvaluator,
      ...stackMedicationClassIds,
    };
    final userProfileFlagsSet =
        userProfileFlagsAsync.asData?.value ?? const <String>{};
    final guardedWarnings = composeGuardedWarnings(
      detailBlob: detailBlob,
      personalizedWarnings: personalizedWarnings,
      userConditions: userConditionsSet,
      userDrugClasses: userDrugClassesSet,
      userProfileFlags: userProfileFlagsSet,
    );
    final profileBenefitWarnings = InteractionWarning.dedupe([
      ...personalizedWarnings,
      ...parseBlobWarnings(detailBlob),
    ]).where((w) => w.direction == 'beneficial').toList(growable: false);
    final profileBenefitNotes = profileBenefitWarnings
        .where(
          (warning) => warning.matchesProfile(
            userConditions: userConditionsSet,
            userDrugClasses: userDrugClassesSet,
            userProfileFlags: userProfileFlagsSet,
          ),
        )
        .toList(growable: false);
    // Split profile-matched/safety warnings (the card) from global
    // educational notes (a separate collapsed "Good to know" section) so the
    // profile card's count reflects only what's relevant to this user.
    final partitionedWarnings = partitionProfileWarnings(
      warnings: guardedWarnings,
      userConditions: userConditionsSet,
      userDrugClasses: userDrugClassesSet,
      userProfileFlags: userProfileFlagsSet,
    );
    final fitAsync = ref.watch(fitScoreForProductProvider(widget.dsldId));
    final fitResult = fitAsync.asData?.value;
    final personalizedChecksFailed =
        personalizedWarningsFailed ||
        fitAsync.hasError ||
        userProfileFlagsAsync.asData == null;

    // -------------------------------------------------------------
    // Blob-derived flags used by downstream sections.
    // -------------------------------------------------------------
    // Research evidence routes through delivered markers too (e.g. turmeric ->
    // curcumin), unlike the interaction/safety path which stays source-only.
    final researchCanonicalIds = _product == null
        ? const <String>[]
        : researchCanonicalIdsForProduct(_product!, detailBlob: detailBlob);
    final labelRecordPresent = detailBlob?.containsKey('label_record') == true;
    // Report metadata for the standalone "Doesn't match your bottle?" feedback
    // action rendered at the page bottom after catalog provenance.
    final labelMismatchMeta = labelMismatchMetadataFrom(
      detailBlob?['label_record'],
      dsldId: widget.dsldId,
      upc: _product?.upcSku,
    );

    // -------------------------------------------------------------
    // Gate booleans (see gating.dart)
    // -------------------------------------------------------------
    final showProfileRelevance = shouldShowProfileRelevance(
      isBlocked: isBlocked,
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
    final evidenceData = _blobMap(detailBlob, 'evidence_data');
    final showClinicalEvidence =
        showDeepDive && hasRenderableClinicalEvidence(evidenceData);
    final certificationDetail = _blobMap(detailBlob, 'certification_detail');
    final showCertifications =
        showDeepDive && hasRenderableCertifications(certificationDetail);

    // -------------------------------------------------------------
    // Scan→verdict perf trace — finish once, after the first frame in
    // which the hero verdict/score is on screen. Search/stack opens
    // (no active transaction) no-op inside PerfTraceService.
    // -------------------------------------------------------------
    if (!_verdictTraceFinished) {
      _verdictTraceFinished = true;
      // Duration only — the former `from_cache` tag was recorded before
      // the blob resolved (effectively always false) and was dropped.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        PerfTraceService().finishScanToVerdict();
      });
    }

    // -------------------------------------------------------------
    // Score-breakdown pillar named actions (v4 only). Only destinations that
    // add supporting information and actually render on this page
    // get a destination callback — others render no action (no dead links).
    //   evidence            → clinical Evidence section
    //   verification        → Certifications (third-party) section
    // Transparency already has the visible label ledger; Formulation, Dose,
    // and Formula & quality checks are explained in place. None need another
    // link.
    // -------------------------------------------------------------
    // Prime fractions approximate each target's position in the page so
    // the lazy SliverList builds it before the keyed ensureVisible lands
    // (same approach as scroll_anchors' `?section=` fractions).
    final onPillarTap = <String, VoidCallback>{
      if (showClinicalEvidence)
        'evidence': () =>
            _scrollToSection(_evidenceSectionKey, primeFraction: 0.65),
      if (showCertifications) ...{
        'verification': () =>
            _scrollToSection(_certificationsSectionKey, primeFraction: 0.60),
      },
    };

    // -------------------------------------------------------------
    // Profile-relevant allergen + free-from match.
    // Computed unconditionally so the no-structured-allergens check
    // is reusable by the free-text allergen summary fallback.
    // -------------------------------------------------------------
    final blobAllergensRaw = detailBlob?['allergens'];
    final blobAllergens = blobAllergensRaw is List ? blobAllergensRaw : null;
    final matchedAllergens = matchAllergens(profile.allergens, blobAllergens);
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
    final profileRelevanceSummary = buildProfileRelevanceSummary(
      fitResult: fitResult,
      topGoalLabel: topGoalLabelFromFit(fitResult),
      warnings: partitionedWarnings.profile,
      interactionHint: interactionHint,
      matchedAllergens: matchedAllergens,
      freeFromConflicts: freeFromConflicts,
      hasInteractionProfile:
          profile.conditionsForEvaluator.isNotEmpty ||
          profile.drugClassesForEvaluator.isNotEmpty,
      hasProfileInformation:
          profile.ageBracket != null ||
          profile.sex != null ||
          profile.conditions.isNotEmpty ||
          profile.drugClasses.isNotEmpty ||
          profile.allergens.isNotEmpty ||
          profile.profileFlags.isNotEmpty,
      selectedGoalLabels: profile.goalsForEvaluator
          .map((goal) => SchemaIds.goalLabels[goal] ?? goal)
          .toList(growable: false),
      // A pipeline-flagged substance hazard (moderate additive / high-risk
      // ingredient) sits in the calm general bucket; it must still stop the
      // verdict from rendering a green "safe" all-clear.
      hasCriticalGlobalNote: partitionedWarnings.general.any(
        (warning) => isCriticalDisplayMode(warning.displayModeDefault),
      ),
      onTapCitations: (urls) =>
          showProfileRelevanceCitationsSheet(context, urls),
    );

    // Independent allergen alert for blocked products. A blocked verdict
    // hides the ProfileRelevance card, but an allergen match must still
    // surface as its own signal. Null when not blocked (ProfileRelevance
    // renders the allergen rows) or when there is no allergen match.
    final blockedAllergenAlert = isBlocked
        ? buildBlockedAllergenAlertSummary(matchedAllergens)
        : null;

    // -------------------------------------------------------------
    // Hero `bottomBanner` slot — blocked-product banner (11.7c.1).
    // Null when the product is not blocked; the Hero collapses the
    // slot to zero height in that case. When blocked, this slot
    // replaces the production header's standalone BlockedBanner
    // sliver, keeping the banner visually anchored to the hero card.
    // -------------------------------------------------------------
    final heroBottomBanner = isBlocked
        ? buildBlockedBannerSection(
            context: context,
            verdict: catalogProductSafetyStatusId(
              catalogProductSafetyStatus(_product!),
            ),
            blockingReason: _product?.blockingReason ?? '',
            topWarnings: parseTopWarnings(_product),
            bannedSubstanceDetail:
                switch (detailBlob?['banned_substance_detail']) {
                  final Map<dynamic, dynamic> m => Map<String, dynamic>.from(m),
                  _ => null,
                },
          )
        : null;

    final mq = MediaQuery.of(context);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
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
                    scoreConfidenceDetail: _blobMap(
                      detailBlob,
                      'v4_confidence_detail',
                    ),
                    bottomBanner: heroBottomBanner,
                  ),
                  const SizedBox(height: V2Spacing.space12),

                  // ---- 2. ProfileRelevance (personalized) ----------
                  if (personalizedChecksFailed) ...[
                    const PGSeverityBanner(
                      key: Key('personalized-checks-error-banner'),
                      tone: PGBannerTone.caution,
                      title: 'Personalized checks are incomplete',
                      body:
                          'We couldn\'t complete every interaction and profile '
                          'check for this product. This is not an all-clear; '
                          'try again before relying on these results.',
                    ),
                    const SizedBox(height: V2Spacing.space12),
                  ],

                  // ---- 2b. Blocked allergen alert ------------------
                  // A blocked verdict hides ProfileRelevance, but an
                  // allergen match is an independent safety signal that
                  // must still surface (a "contains" match matters
                  // regardless of why the product is blocked).
                  if (blockedAllergenAlert != null) ...[
                    ProfileRelevanceSection(
                      summary: blockedAllergenAlert,
                      onCompleteProfile: () =>
                          context.push(Routes.profileSetup),
                    ),
                    const SizedBox(height: V2Spacing.space12),
                  ],

                  if (showProfileRelevance) ...[
                    if (profileRelevanceSummary.shouldRender) ...[
                      KeyedSubtree(
                        key: _anchors.interactionsKey,
                        child: ProfileRelevanceSection(
                          summary: profileRelevanceSummary,
                          onCompleteProfile: () =>
                              context.push(Routes.profileSetup),
                        ),
                      ),
                      const SizedBox(height: V2Spacing.space12),
                    ],
                    if (buildGeneralNotesSection(
                          warnings: [
                            ...partitionedWarnings.general,
                            ...profileBenefitNotes,
                          ],
                          freeFromClaims: freeFromClaims
                              .where(
                                (claim) =>
                                    !freeFromConflicts.contains(claim.concern),
                              )
                              .toList(growable: false),
                          onTapCitations: (urls) =>
                              showProfileRelevanceCitationsSheet(context, urls),
                        )
                        case final generalNotes?) ...[
                      generalNotes,
                      const SizedBox(height: V2Spacing.space12),
                    ],
                  ],

                  // ---- 4.5 Allergen summary fallback ---------------
                  // Renders ONLY when the product has free-text
                  // allergenSummary AND the blob has no structured
                  // allergens (which would have already populated
                  // ReviewBeforeUse rows). Suppressed on blocked.
                  // Gated on the blob actually lacking structured
                  // allergen data — NOT on matchedAllergens.isEmpty,
                  // which is also true when the user simply has no
                  // allergens in their profile.
                  if (shouldShowAllergenSummaryBanner(
                    isBlocked: isBlocked,
                    allergenSummary: _product?.allergenSummary,
                    noStructuredAllergens:
                        blobAllergens == null || blobAllergens.isEmpty,
                  )) ...[
                    buildAllergenSummaryBannerSection(
                      context: context,
                      allergenSummary: _product?.allergenSummary,
                    ),
                    const SizedBox(height: V2Spacing.space12),
                  ],

                  // ---- 4.6 Allergen data unavailable hedge --------
                  // unknown != safe: a user with declared allergens must
                  // not read "no allergen data" as a silent clean bill.
                  if (shouldShowAllergenDataUnavailableHedge(
                    isBlocked: isBlocked,
                    userHasAllergens: profile.allergensForEvaluator.isNotEmpty,
                    noStructuredAllergens:
                        blobAllergens == null || blobAllergens.isEmpty,
                    allergenSummary: _product?.allergenSummary,
                  )) ...[
                    buildAllergenDataUnavailableHedge(context),
                    const SizedBox(height: V2Spacing.space12),
                  ],

                  // Catalog label record moved to the collapsed
                  // "Product data & sources" section at the page bottom; the
                  // "Doesn't match your bottle?" action stays next to the
                  // ingredient list below.

                  // ---- 6. Ingredients (WIRED, 11.7d.2) -------------
                  if (showDeepDive) ...[
                    KeyedSubtree(
                      key: _anchors.ingredientsKey,
                      child: buildIngredientsSection(
                        key: ValueKey('ingredient-ledger-${widget.dsldId}'),
                        context: context,
                        ingredients: ingredientSources.ingredients,
                        displayIngredients:
                            ingredientSources.displayIngredients,
                        inactiveIngredients:
                            ingredientSources.inactiveIngredients,
                        ulAnalysis: productUlAnalysis
                            ?.whereType<Map<String, dynamic>>()
                            .toList(growable: false),
                        blends: ingredientSources.blends,
                        nutritionContent: buildNutritionSection(
                          caloriesPerServing: _product?.caloriesPerServing,
                          nutritionDetail: _blobMap(
                            detailBlob,
                            'nutrition_detail',
                          ),
                          labelRows: labelNutritionRows,
                          embedded: true,
                        ),
                      ),
                    ),
                    const SizedBox(height: V2Spacing.space12),
                  ],

                  // ---- 6.1 Probiotic label + research ------------
                  // Keep label-specific context beside the ingredient
                  // ledger it explains. Research matching is informational
                  // and remains independent from the scoring core.
                  if (showDeepDive) ...[
                    buildProbioticSection(
                      probioticDetail: _blobMap(detailBlob, 'probiotic_detail'),
                      onTapSources: (urls) =>
                          showProfileRelevanceCitationsSheet(context, urls),
                    ),
                    const SizedBox(height: V2Spacing.space12),
                  ],

                  // ---- Quality breakdown --------------------------
                  // The label identity comes first; scoring explains the
                  // already-visible product rather than interrupting it.
                  if (showScoreBreakdown) ...[
                    buildScoreBreakdownSection(
                      ingredientQuality: _product?.scoreIngredientQuality,
                      safetyPurity: _product?.scoreSafetyPurity,
                      evidenceResearch: _product?.scoreEvidenceResearch,
                      brandTrust: _product?.scoreBrandTrust,
                      heroScore: score100,
                      mappedCoverage: mappedCoverage,
                      sectionBreakdown: _blobMap(
                        detailBlob,
                        'section_breakdown',
                      ),
                      qualityPillarsV4: _blobMap(
                        detailBlob,
                        'quality_pillars_v4',
                      ),
                      qualityScoreCapV4: _blobMap(
                        detailBlob,
                        'quality_score_cap_v4',
                      ),
                      onPillarTap: onPillarTap,
                    ),
                    const SizedBox(height: V2Spacing.space12),
                  ],

                  // ---- 7. Tradeoffs (WIRED, 11.7d.3) ---------------
                  if (showDeepDive) ...[
                    buildTradeoffsSection(
                      detailBlob: detailBlob,
                      appReferenceData: appRdaReferenceData,
                    ),
                    const SizedBox(height: V2Spacing.space12),
                  ],

                  // ---- 8. Populations (WIRED, 11.7d.4) -------------
                  if (showDeepDive) ...[
                    buildPopulationsSection(
                      warnings: guardedWarnings,
                      userConditions: profile.conditionsForEvaluator.toSet(),
                      userDrugClasses: profile.drugClassesForEvaluator.toSet(),
                      ageBracket: profile.ageBracket,
                    ),
                    const SizedBox(height: V2Spacing.space12),
                  ],

                  // Nutrition moved up beside the ingredient list (bottle data
                  // belongs together); still conditional via buildNutritionSection.

                  // ---- 10. Certifications (WIRED, 11.7e) -----------
                  if (showDeepDive) ...[
                    KeyedSubtree(
                      key: _certificationsSectionKey,
                      child: buildCertificationsSection(
                        certificationDetail: certificationDetail,
                      ),
                    ),
                    const SizedBox(height: V2Spacing.space12),
                  ],

                  // ---- 11. Research support (evidence + literature) ----
                  // ONE surface (T10): the compact clinical-evidence card
                  // whose studies sheet also carries related ingredient
                  // research, or — when there is no clinical evidence — a
                  // research-only card. Both scroll anchors resolve here.
                  // Render when either half would have shown; the widget
                  // itself picks the state (and hides if research resolves
                  // empty), matching the old per-block gating.
                  if (showClinicalEvidence ||
                      (showDeepDive && researchCanonicalIds.isNotEmpty)) ...[
                    KeyedSubtree(
                      key: _evidenceSectionKey,
                      child: KeyedSubtree(
                        key: _anchors.researchKey,
                        child: ResearchSupportSection(
                          evidenceData: evidenceData,
                          canonicalIds: researchCanonicalIds,
                        ),
                      ),
                    ),
                    const SizedBox(height: V2Spacing.space12),
                  ],

                  // ---- 11.5 Synergy (WIRED, 11.11) -----------------
                  // "Works well with" — T22 high-confidence clusters
                  // (Sprint 21 54-cluster data). Hidden when no
                  // tier ≤ 2 clusters pass — never renders as empty.
                  if (showDeepDive) ...[
                    ..._sectionWithTrailingGap(
                      buildSynergySection(detailBlob: detailBlob),
                    ),
                  ],

                  // ---- 12. HeavyMetal (WIRED, 11.7e) ---------------
                  if (showDeepDive) ...[
                    ..._sectionWithTrailingGap(
                      buildHeavyMetalSection(
                        heavyMetalDetail: _blobMap(
                          detailBlob,
                          'heavy_metal_detail',
                        ),
                      ),
                    ),
                  ],

                  // ---- 13. Formulation (WIRED, 11.7e) --------------
                  if (showDeepDive) ...[
                    ..._sectionWithTrailingGap(
                      buildFormulationSection(
                        context: context,
                        formulationDetail: _blobMap(
                          detailBlob,
                          'formulation_detail',
                        ),
                        ingredientQualityData: _blobMap(
                          detailBlob,
                          'ingredient_quality_data',
                        ),
                      ),
                    ),
                  ],

                  // ---- 15. ManufacturerViolations (WIRED, 11.7e) ---
                  if (showDeepDive) ...[
                    ..._sectionWithTrailingGap(
                      buildManufacturerViolationsSection(
                        manufacturerDetail: _blobMap(
                          detailBlob,
                          'manufacturer_detail',
                        ),
                      ),
                    ),
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
                      profileIncomplete:
                          profileRelevanceSummary.profileIncomplete,
                    ),
                  ),
                  const SizedBox(height: V2Spacing.space12),

                  // ---- Product data & sources (collapsed) ---------
                  // Catalog provenance (record IDs, versions, fingerprint,
                  // source dates) is debugging/provenance detail — collapsed
                  // by default at the page bottom, out of the primary scroll.
                  if (showDeepDive && labelRecordPresent) ...[
                    Container(
                      key: const Key('product-data-sources-card'),
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: context.v2.surface,
                        borderRadius: BorderRadius.circular(
                          V2Spacing.radiusCard,
                        ),
                        border: Border.all(color: context.v2.outline),
                        boxShadow: V2Shadows.sm,
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: Theme(
                          data: Theme.of(
                            context,
                          ).copyWith(dividerColor: Colors.transparent),
                          child: ExpansionTile(
                            tilePadding: const EdgeInsets.symmetric(
                              horizontal: V2Spacing.space16,
                            ),
                            childrenPadding: const EdgeInsets.fromLTRB(
                              V2Spacing.space12,
                              0,
                              V2Spacing.space12,
                              V2Spacing.space12,
                            ),
                            title: Text(
                              'Product data & sources',
                              style: V2Typography.titleSm(color: context.v2.fg),
                            ),
                            children: [
                              buildLabelMatchSection(
                                labelRecord: detailBlob?['label_record'],
                                upc: _product?.upcSku,
                                currentLabelRows:
                                    ingredientSources.displayIngredients,
                                onOpenSourceLabel: (uri) async {
                                  await launchUrl(
                                    uri,
                                    mode: LaunchMode.externalApplication,
                                  );
                                },
                                showMismatchAction: false,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: V2Spacing.space12),
                  ],

                  // Feedback belongs after the product content and provenance,
                  // not inside the primary decision flow.
                  if (showDeepDive &&
                      labelRecordPresent &&
                      labelMismatchMeta != null) ...[
                    LabelMismatchAction(product: labelMismatchMeta),
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
        // "Add to my stack" / "See higher-quality options" flow works
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
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      pinned: false,
      floating: true,
      snap: true,
      leading: IconButton(
        icon: Icon(Icons.arrow_back_rounded, color: context.v2.fg),
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
        // Wishlist heart — signed-in only; guests are sent to auth.
        // Sits left of Compare/Share so save-for-later is one tap away
        // without competing with the sticky "Add to stack" CTA.
        if (_product != null) PGFavoriteButton(dsldId: widget.dsldId),
        // Quiet Compare entry — opens the second-product picker sheet
        // (stack + recent scans; the current product is excluded).
        // Scanning-to-compare is out of scope: TODO(compare).
        if (_product != null)
          IconButton(
            tooltip: 'Compare',
            icon: Icon(Icons.compare_arrows_rounded, color: context.v2.fg),
            onPressed: () =>
                showComparePickerSheet(context, currentDsldId: widget.dsldId),
          ),
        if (_product != null)
          IconButton(
            tooltip: 'Share product',
            icon: _isSharing
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(Icons.ios_share_rounded, color: context.v2.fg),
            // No haptic — iOS share sheet fires its own present haptic.
            onPressed: _isSharing ? null : _shareProduct,
          ),
      ],
    );
  }
}

/// Hero-shaped skeleton — matches the product-detail first screenful so
/// load feels like structure arriving, not a spinner interstitial.
class _ProductDetailLoadingState extends StatelessWidget {
  const _ProductDetailLoadingState();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          V2Spacing.space16,
          V2Spacing.space8,
          V2Spacing.space16,
          V2Spacing.space24,
        ),
        children: [
          // Hero card skeleton (image 80 + title/brand/score).
          Container(
            padding: const EdgeInsets.all(V2Spacing.space12),
            decoration: BoxDecoration(
              color: context.v2.surface,
              borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
              border: Border.all(color: context.v2.outline),
              boxShadow: V2Shadows.sm,
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SkeletonBlock(width: 80, height: 80, radius: 12),
                    SizedBox(width: V2Spacing.space12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _SkeletonBlock(width: double.infinity, height: 16),
                          SizedBox(height: V2Spacing.space8),
                          _SkeletonBlock(width: 140, height: 12),
                          SizedBox(height: V2Spacing.space8),
                          _SkeletonBlock(width: 96, height: 12),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: V2Spacing.space12),
                _SkeletonBlock(width: 88, height: 10),
                SizedBox(height: V2Spacing.space8),
                _SkeletonBlock(width: 160, height: 18),
              ],
            ),
          ),
          const SizedBox(height: V2Spacing.space12),
          // Profile-relevance / score card placeholders.
          const _SkeletonCard(height: 88),
          const SizedBox(height: V2Spacing.space12),
          const _SkeletonCard(height: 120),
          const SizedBox(height: V2Spacing.space12),
          const _SkeletonCard(height: 160),
        ],
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  final double height;
  const _SkeletonCard({required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(minHeight: height),
      decoration: BoxDecoration(
        color: context.v2.surface,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        border: Border.all(color: context.v2.outline),
      ),
      padding: const EdgeInsets.all(V2Spacing.space16),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SkeletonBlock(width: 120, height: 12),
          SizedBox(height: V2Spacing.space12),
          _SkeletonBlock(width: double.infinity, height: 12),
          SizedBox(height: V2Spacing.space8),
          _SkeletonBlock(width: 200, height: 12),
        ],
      ),
    );
  }
}

class _SkeletonBlock extends StatelessWidget {
  final double width;
  final double height;
  final double radius;

  const _SkeletonBlock({
    required this.width,
    required this.height,
    this.radius = 4,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width == double.infinity ? null : width,
      height: height,
      constraints: width == double.infinity
          ? const BoxConstraints(minWidth: double.infinity)
          : null,
      decoration: BoxDecoration(
        color: context.v2.outline.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

// All sections wired (Phase 11.7e completed). The _SectionPlaceholder
// shell-helper has been deleted — its job (rendering "WIRING <name>"
// diagnostic cards) is done. Future placeholder cards should live in
// their own section file as a deferred-state widget, not a global helper.
