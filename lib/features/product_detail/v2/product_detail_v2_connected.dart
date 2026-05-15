// Phase 11.7b — Product Detail V2 Connected screen (orchestration only).
//
// This is the production-wired counterpart of `product_detail_v2_screen.dart`
// (the fixture-only gallery screen at `/dev/v2/product-detail`). The
// Connected version takes a real `dsldId` and mirrors production's
// `ProductDetailScreen` state lifecycle + provider watches + gating logic
// 1:1, so every clinical/safety surface that fires on the production route
// also fires here. Only the visual presentation differs — v2 tokens, v2
// components.
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
import 'package:pharmaguide/core/components/pg_transparency_footer.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/product_detail/providers/detail_blob_provider.dart';
import 'package:pharmaguide/features/product_detail/providers/personalized_warnings_provider.dart';
import 'package:pharmaguide/features/product_detail/v2/gating.dart';
import 'package:pharmaguide/features/product_detail/v2/scroll_anchors.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/hero_section.dart';
import 'package:pharmaguide/features/product_detail/v2/warnings_pipeline.dart';
import 'package:pharmaguide/features/product_detail/widgets/interaction_warnings.dart';
import 'package:pharmaguide/features/product_detail/widgets/pg_stack_action_buttons.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';
import 'package:pharmaguide/services/sharing/share_service.dart';
import 'package:pharmaguide/services/warnings/condition_gate.dart';

/// Production-wired v2 Product Detail screen.
///
/// Receives [dsldId] from route params (`/dev/v2/product/<dsldId>` during
/// the staged rollout; `/product/<dsldId>` once Phase 11.7g ratifies the
/// swap). Accepts the same `?section=` deep link as production so existing
/// links continue working when the route is later swapped.
class ProductDetailV2ConnectedScreen extends ConsumerStatefulWidget {
  final String dsldId;

  /// Optional anchor for `?section=` deep links. Accepts `'interactions'`,
  /// `'ingredients'`, or `'alternatives'`. Unknown values fall through.
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
    _anchors.scheduleInitialScroll(
      initialSection: widget.initialSection,
      isMounted: () => mounted,
    );
  }

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
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    // -------------------------------------------------------------
    // Header derivations (local product row)
    // -------------------------------------------------------------
    final productName = _product?.productName ?? 'Product ${widget.dsldId}';
    final brandName = _product?.brandName ?? '';
    final formFactor = _product?.formFactor ?? '';
    final score100 = _product?.score100Equivalent;
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
    final blendDetail =
        detailBlob?['proprietary_blend_detail'] as Map<String, dynamic>?;
    final hasProprietaryBlends = blendDetail?['has_proprietary_blends'] == true;

    // -------------------------------------------------------------
    // Gate booleans (see gating.dart)
    // -------------------------------------------------------------
    final showPersonalFit = shouldShowPersonalFit(isBlocked: isBlocked);
    final showReviewBeforeUse =
        shouldShowReviewBeforeUse(isBlocked: isBlocked);
    final showScoreBreakdown = shouldShowScoreBreakdown(
      isBlocked: isBlocked,
      isNotScored: isNotScored,
    );
    final showDeepDive = shouldShowDeepDive(
      isBlocked: isBlocked,
      blobLoading: blobLoading,
      blobError: blobError,
    );

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
                    dsldId: widget.dsldId,
                    product: _product,
                    productName: productName,
                    brandName: brandName,
                    formFactor: formFactor,
                    score100: score100,
                    isBlocked: isBlocked,
                    isNotScored: isNotScored,
                    trustTags: trustTags,
                    // bottomBanner: 11.7c slots BlockedBanner here.
                  ),
                  const SizedBox(height: V2Spacing.space12),

                  // ---- 2. PersonalFit (PLACEHOLDER, 11.7c) ---------
                  if (showPersonalFit) ...[
                    const _SectionPlaceholder(
                      label: 'PersonalFit',
                      detail:
                          'fitScoreForProductProvider → PGPersonalFitCard',
                    ),
                    const SizedBox(height: V2Spacing.space12),
                  ],

                  // ---- 3. ReviewBeforeUse (PLACEHOLDER, 11.7c) -----
                  if (showReviewBeforeUse) ...[
                    _SectionPlaceholder(
                      key: _anchors.interactionsKey,
                      label: 'ReviewBeforeUse',
                      detail:
                          'guardedWarnings: ${guardedWarnings.length} · '
                          'worst=${worstSeverityOf(guardedWarnings).label}',
                    ),
                    const SizedBox(height: V2Spacing.space12),
                  ],

                  // ---- 4. LabelConfidence (PLACEHOLDER, 11.7c) -----
                  // PRODUCTION ORDER: LabelConfidence sits BEFORE
                  // ScoreBreakdown so the low-coverage caveat sets
                  // expectation before the score it caveats.
                  if (!isBlocked) ...[
                    _SectionPlaceholder(
                      label: 'LabelConfidence',
                      detail:
                          'coverage=${(mappedCoverage * 100).toStringAsFixed(0)}% · '
                          'propBlends=$hasProprietaryBlends · '
                          'notScored=$isNotScored',
                    ),
                    const SizedBox(height: V2Spacing.space12),
                  ],

                  // ---- 5. ScoreBreakdown (PLACEHOLDER, 11.7d) ------
                  if (showScoreBreakdown) ...[
                    _SectionPlaceholder(
                      label: 'ScoreBreakdown',
                      detail:
                          'hero=$score100 · ingredient='
                          '${_product?.scoreIngredientQuality ?? "—"} · '
                          'safety=${_product?.scoreSafetyPurity ?? "—"} · '
                          'evidence=${_product?.scoreEvidenceResearch ?? "—"} · '
                          'brand=${_product?.scoreBrandTrust ?? "—"}',
                    ),
                    const SizedBox(height: V2Spacing.space12),
                  ],

                  // ---- 6. Ingredients (PLACEHOLDER, 11.7d) ---------
                  if (showDeepDive) ...[
                    _SectionPlaceholder(
                      key: _anchors.ingredientsKey,
                      label: 'Ingredients',
                      detail: _shellIngredientsSummary(
                        detailBlob,
                        ingredientDoses,
                      ),
                    ),
                    const SizedBox(height: V2Spacing.space12),
                  ],

                  // ---- 7. Tradeoffs (PLACEHOLDER, 11.7d) -----------
                  if (showDeepDive) ...[
                    const _SectionPlaceholder(
                      label: 'Tradeoffs',
                      detail: 'tradeoffs_section blob',
                    ),
                    const SizedBox(height: V2Spacing.space12),
                  ],

                  // ---- 8. Populations (PLACEHOLDER, 11.7d) ---------
                  if (showDeepDive) ...[
                    const _SectionPlaceholder(
                      label: 'Populations',
                      detail: 'condition_summary + drug_classes',
                    ),
                    const SizedBox(height: V2Spacing.space12),
                  ],

                  // ---- 9. Nutrition (PLACEHOLDER, 11.7d) -----------
                  if (showDeepDive) ...[
                    _SectionPlaceholder(
                      label: 'Nutrition',
                      detail:
                          'cal/serving=${_product?.caloriesPerServing ?? "—"}',
                    ),
                    const SizedBox(height: V2Spacing.space12),
                  ],

                  // ---- 10. Certifications (PLACEHOLDER, 11.7e) -----
                  if (showDeepDive) ...[
                    const _SectionPlaceholder(
                      label: 'Certifications',
                      detail: 'certification_detail blob',
                    ),
                    const SizedBox(height: V2Spacing.space12),
                  ],

                  // ---- 11. Evidence (PLACEHOLDER, 11.7e) -----------
                  if (showDeepDive) ...[
                    const _SectionPlaceholder(
                      label: 'Evidence',
                      detail: 'evidence_data blob',
                    ),
                    const SizedBox(height: V2Spacing.space12),
                  ],

                  // ---- 12. HeavyMetal (PLACEHOLDER, 11.7e) ---------
                  if (showDeepDive) ...[
                    _SectionPlaceholder(
                      label: 'HeavyMetal',
                      detail: (detailBlob?['heavy_metal_detail'] != null)
                          ? 'present'
                          : 'absent — section hides in 11.7e',
                    ),
                    const SizedBox(height: V2Spacing.space12),
                  ],

                  // ---- 13. Formulation (PLACEHOLDER, 11.7e) --------
                  if (showDeepDive) ...[
                    const _SectionPlaceholder(
                      label: 'Formulation',
                      detail: 'formulation_detail blob',
                    ),
                    const SizedBox(height: V2Spacing.space12),
                  ],

                  // ---- 14. Probiotic (PLACEHOLDER, 11.7e) ----------
                  if (showDeepDive) ...[
                    _SectionPlaceholder(
                      label: 'Probiotic',
                      detail: (detailBlob?['probiotic_detail'] != null)
                          ? 'present'
                          : 'absent — section hides in 11.7e',
                    ),
                    const SizedBox(height: V2Spacing.space12),
                  ],

                  // ---- 15. ManufacturerViolations (PLACEHOLDER) ----
                  if (showDeepDive) ...[
                    const _SectionPlaceholder(
                      label: 'ManufacturerViolations',
                      detail: 'manufacturer_detail blob',
                    ),
                    const SizedBox(height: V2Spacing.space12),
                  ],

                  // ---- 16. BetterAlternatives (PLACEHOLDER, 11.7e) -
                  // Shell renders the anchor unconditionally so the
                  // _alternativesKey is layoutable for the sticky CTA's
                  // ensureVisible call. The real gate
                  // (shouldShowBetterAlternatives) wires in 11.7e.
                  _SectionPlaceholder(
                    key: _anchors.alternativesKey,
                    label: 'BetterAlternatives',
                    detail:
                        'gate: isBlocked=$isBlocked · score=$score100 · '
                        'fit=pending',
                  ),
                  const SizedBox(height: V2Spacing.space12),

                  // ---- 17. TransparencyFooter (WIRED) --------------
                  const PGTransparencyFooter(),
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
        onPressed: () => context.pop(),
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

  /// Shell-only diagnostic — one-line summary of ingredient counts so
  /// the placeholder shows real data while waiting on the 11.7d adapter.
  /// Deleted along with the Ingredients placeholder when that section
  /// wires.
  String _shellIngredientsSummary(
    Map<String, dynamic>? blob,
    Map<String, IngredientDose> ingredientDoses,
  ) {
    if (blob == null) return 'blob pending';
    final active =
        (blob['ingredients'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .length ??
        0;
    final inactive =
        (blob['inactive_ingredients'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .length ??
        0;
    return '$active active · $inactive inactive · '
        '${ingredientDoses.length} doses extracted';
  }
}

// =====================================================================
// _SectionPlaceholder — transient cards used by every unwired section
// in the 11.7b shell. Each placeholder shows the section name + a
// one-line diagnostic of the data its adapter WILL render in 11.7c–
// 11.7e. Deleted along with this comment block once every section
// adapter is wired.
// =====================================================================

class _SectionPlaceholder extends StatelessWidget {
  final String label;
  final String? detail;

  const _SectionPlaceholder({super.key, required this.label, this.detail});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        V2Spacing.space16,
        V2Spacing.space12,
        V2Spacing.space16,
        V2Spacing.space12,
      ),
      decoration: BoxDecoration(
        color: V2Colors.surface,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        border: Border.all(color: V2Colors.outline, width: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: V2Spacing.space8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: V2Colors.accentTint,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'WIRING',
                  style: V2Typography.eyebrow(color: V2Colors.accent),
                ),
              ),
              const SizedBox(width: V2Spacing.space8),
              Text(label, style: V2Typography.titleSm(color: V2Colors.fg)),
            ],
          ),
          if (detail != null) ...[
            const SizedBox(height: V2Spacing.space4),
            Text(
              detail!,
              style: V2Typography.bodySm(color: V2Colors.fgMuted),
            ),
          ],
        ],
      ),
    );
  }
}
