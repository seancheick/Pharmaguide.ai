import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/models/interaction_result.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_empty_state.dart';
import 'package:pharmaguide/core/widgets/pg_fitscore_badge.dart';
import 'package:pharmaguide/core/widgets/pg_score_ring.dart';
import 'package:pharmaguide/core/widgets/product_image.dart';
import 'package:pharmaguide/core/widgets/pg_severity_banner.dart';
import 'package:pharmaguide/core/widgets/pg_shimmer_box.dart';
import 'package:pharmaguide/core/widgets/verdict_badge.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/services/sharing/share_service.dart';
import 'package:pharmaguide/services/stack/stack_interaction_checker.dart';
import 'package:pharmaguide/features/product_detail/providers/detail_blob_provider.dart';
import 'package:pharmaguide/features/product_detail/providers/fit_score_provider.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';
import 'package:pharmaguide/features/product_detail/widgets/better_alternatives.dart';
import 'package:pharmaguide/features/product_detail/widgets/blend_warning_banner.dart';
import 'package:pharmaguide/features/product_detail/widgets/fit_score_sheet.dart';
import 'package:pharmaguide/features/product_detail/widgets/interaction_warnings.dart';
import 'package:pharmaguide/features/product_detail/widgets/excipient_density_card.dart';
import 'package:pharmaguide/features/product_detail/widgets/form_absorption_section.dart';
import 'package:pharmaguide/features/product_detail/widgets/heavy_metal_warning_card.dart';
import 'package:pharmaguide/features/product_detail/widgets/pairs_well_section.dart';
import 'package:pharmaguide/features/product_detail/widgets/nutrition_panel.dart';
import 'package:pharmaguide/features/product_detail/widgets/pipeline_detail_sections.dart';
import 'package:pharmaguide/features/product_detail/widgets/pg_stack_action_buttons.dart';
import 'package:pharmaguide/features/product_detail/widgets/refill_reminder_card.dart';
import 'package:pharmaguide/features/product_detail/widgets/score_breakdown_card.dart';
import 'package:pharmaguide/features/product_detail/widgets/unmapped_actives_disclosure.dart';
import 'package:pharmaguide/features/product_detail/widgets/unknown_ingredient_banner.dart';
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

  // User stack entry for this product (null = not in stack). Powers the
  // refill-reminder card; we need addedAt for the days-remaining math.
  UserStacksLocalData? _stackEntry;

  // Personalized interaction warnings from live DB lookup against user's
  // stack. These supplement the static blob-parsed warnings with
  // "Because you're taking X" context. Spec §9.2.
  List<InteractionWarning> _personalizedWarnings = const [];

  @override
  void initState() {
    super.initState();
    _loadProduct();
    _loadStackEntry();
    _loadPersonalizedInteractions();
  }

  /// Look up whether the user has this product in their stack — needed
  /// for the refill-reminder card's days-remaining computation. Silent
  /// failure: if the lookup throws, the card just won't render.
  Future<void> _loadStackEntry() async {
    try {
      final userDb = ref.read(userDatabaseProvider);
      final entry = await userDb.findStackEntryByDsldId(widget.dsldId);
      if (mounted) {
        setState(() {
          _stackEntry = entry;
        });
      }
    } on Exception {
      // Stack lookup failure is non-fatal — leave _stackEntry null,
      // the refill card will simply not render.
    }
  }

  /// Query the bundled InteractionDatabase for interactions between this
  /// product's ingredients and the user's current stack. Maps results to
  /// [InteractionWarning] with "Because you're taking [X]" context.
  Future<void> _loadPersonalizedInteractions() async {
    try {
      final interactionDb = ref.read(interactionDatabaseProvider);
      final userDb = ref.read(userDatabaseProvider);
      final coreDb = ref.read(coreDatabaseProvider);

      final product = await coreDb.findById(widget.dsldId);
      if (product == null || !mounted) return;

      final stack = await userDb.getActiveStack();
      if (stack.isEmpty || !mounted) return;

      // Extract canonical IDs from this product's key_ingredient_tags
      // (primary) and herbs from fingerprint (secondary).
      final canonicalIds = _extractCanonicalIds(
        product.keyIngredientTags,
        product.ingredientFingerprint,
      );
      if (canonicalIds.isEmpty) return;

      final checker = StackInteractionChecker();
      final warnings = <InteractionWarning>[];
      final seenIds = <String>{};

      // Check against stack supplements.
      final supplements =
          stack.where((e) => e.type == 'supplement').toList(growable: false);
      if (supplements.isNotEmpty) {
        final hits = await checker.checkSupplementPairInteractions(
          newProductCanonicalIds: canonicalIds,
          stackSupplements: supplements,
          db: interactionDb,
          newProductName: product.productName,
        );
        for (final hit in hits) {
          if (seenIds.add(hit.id)) {
            warnings.add(_interactionResultToWarning(hit));
          }
        }
      }

      // Check against stack medications.
      final medications =
          stack.where((e) => e.type == 'medication').toList(growable: false);
      if (medications.isNotEmpty) {
        final hits = await checker.checkMedicationInteractions(
          newProductCanonicalIds: canonicalIds,
          stackMedications: medications,
          db: interactionDb,
          newProductName: product.productName,
        );
        for (final hit in hits) {
          if (seenIds.add(hit.id)) {
            warnings.add(_interactionResultToWarning(hit));
          }
        }
      }

      if (mounted && warnings.isNotEmpty) {
        setState(() => _personalizedWarnings = warnings);
      }
    } on UnimplementedError {
      // Provider stub not overridden (test environment) — fall back to
      // blob-only warnings. This is the only Error we intentionally catch.
    } on Exception {
      // Non-fatal — personalized warnings are a bonus on top of blob
      // warnings. If the interaction DB is missing or corrupt, we
      // silently fall back to blob-only.
    }
  }

  /// Extract canonical ingredient IDs for interaction matching.
  ///
  /// Primary source: [tagsJson] from `key_ingredient_tags` column — a JSON
  /// array like `["iron", "calcium", "vitamin_d"]`.
  ///
  /// Secondary source: `herbs` list inside [fingerprintJson] for herbal
  /// products whose canonical IDs live in the fingerprint's herbs array.
  ///
  /// Previous implementation read fingerprint top-level map keys which
  /// always returned structural keys (`nutrients`, `herbs`, etc.), not
  /// actual ingredient IDs. Fixed 2026-04-14.
  static List<String> _extractCanonicalIds(
    String? tagsJson,
    String? fingerprintJson,
  ) {
    final ids = <String>{};

    // Primary: key_ingredient_tags.
    if (tagsJson != null && tagsJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(tagsJson);
        if (decoded is List) {
          for (final tag in decoded) {
            final s = tag.toString().toLowerCase().trim();
            if (s.isNotEmpty) ids.add(s);
          }
        }
      } on FormatException {
        // Fall through.
      }
    }

    // Secondary: herbs from ingredient_fingerprint.
    if (fingerprintJson != null && fingerprintJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(fingerprintJson);
        if (decoded is Map) {
          final herbs = decoded['herbs'];
          if (herbs is List) {
            for (final h in herbs) {
              final s = h.toString().toLowerCase().trim();
              if (s.isNotEmpty) ids.add(s);
            }
          }
        }
      } on FormatException {
        // Best-effort.
      }
    }

    return ids.toList(growable: false);
  }

  /// Maps an [InteractionResult] from the curated DB to an
  /// [InteractionWarning] that the existing [InteractionWarningsList]
  /// widget can render. Adds "Because you're taking [X]" context.
  static InteractionWarning _interactionResultToWarning(
      InteractionResult result) {
    return InteractionWarning(
      severity: result.severity,
      evidenceLevel: result.evidenceLevel,
      title: 'Because you\'re taking ${result.agent2Name}',
      mechanism: result.mechanism,
      management: result.management,
      sourceUrls: result.sourceUrls,
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

  bool _isNotScored(ProductsCoreData? product) {
    if (product == null) return false;
    final verdict = product.verdict ?? '';
    final score = product.score100Equivalent;
    final isBlocked =
        verdict == 'BLOCKED' || verdict == 'UNSAFE';
    return (verdict == 'NOT_SCORED' ||
            (score == null && !isBlocked));
  }

  @override
  Widget build(BuildContext context) {
    if (_productLoading) {
      return Scaffold(
        appBar: AppBar(
          elevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final productName = _product?.productName ?? 'Product ${widget.dsldId}';
    final brandName = _product?.brandName ?? '';
    final formFactor = _product?.formFactor ?? '';
    final verdict = _product?.verdict ?? '';
    final blockingReason = _product?.blockingReason ?? '';
    final score100 = _product?.score100Equivalent;
    final grade = _product?.grade ?? '';
    // Safety rule: NEVER display "safe" when mapped_coverage < 0.3.
    // Default to 0.0 (conservative) when coverage is unknown.
    final mappedCoverage = _product?.mappedCoverage ?? 0.0;
    final percentileLabel = _product?.percentileLabel ?? '';
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

    // Detail blob data + personalized interaction warnings from live DB.
    // Personalized warnings (from InteractionDatabase) appear first,
    // followed by generic blob warnings — deduped by (mechanism, severity)
    // to avoid showing the same interaction twice from different sources.
    final blobWarnings = _parseWarnings(detailBlob);
    final seenKeys = <String>{
      for (final w in _personalizedWarnings)
        '${w.severity.name}:${w.mechanism}',
    };
    final warnings = <InteractionWarning>[
      ..._personalizedWarnings,
      ...blobWarnings.where(
          (w) => !seenKeys.contains('${w.severity.name}:${w.mechanism}')),
    ];
    // Pipeline nests this under proprietary_blend_detail
    final blendDetail = detailBlob?['proprietary_blend_detail'] as Map<String, dynamic>?;
    final hasProprietaryBlends = blendDetail?['has_proprietary_blends'] == true;

    final isBlocked =
        verdict == 'BLOCKED' || verdict == 'UNSAFE';
    final isNotScored = _isNotScored(_product);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // ----------------------------------------------------------------
          // App bar with back button
          // ----------------------------------------------------------------
          SliverAppBar(
            pinned: true,
            elevation: 0,
            surfaceTintColor: Colors.transparent,
            title: Text(
              productName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.share_outlined),
                tooltip: 'Share',
                onPressed: _product == null
                    ? null
                    : () {
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
              grade: grade,
              percentileLabel: percentileLabel,
              dietaryTags: dietaryTags,
              isBlocked: isBlocked,
              isNotScored: isNotScored,
              topWarnings: _topWarnings(),
              onScoreInfoTap: () => _showScoreEducation(context),
              imageUrl: _product?.imageUrl,
              upc: _product?.upcSku,
              // Score explainer data — rendered inline in header
              ingredientQuality: ingredientQuality,
              safetyPurity: safetyPurity,
              evidenceResearch: evidenceResearch,
              brandTrust: brandTrust,
              mappedCoverage: mappedCoverage,
              decisionHighlights: _product?.decisionHighlights,
            ),
          ),

          // ----------------------------------------------------------------
          // Condition alert banner (interaction summary hint)
          // ----------------------------------------------------------------
          if (interactionHint.isNotEmpty)
            SliverToBoxAdapter(
              child: _ConditionAlertBanner(hint: interactionHint),
            ),

          // ----------------------------------------------------------------
          // Coverage / blend banners — full-bleed feel, tighter spacing
          // ----------------------------------------------------------------
          if (!isBlocked) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.space20, 0, AppTheme.space20, AppTheme.space8),
                child: UnknownIngredientBanner(mappedCoverage: mappedCoverage),
              ),
            ),
            if (hasProprietaryBlends)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    AppTheme.space20, 0, AppTheme.space20, AppTheme.space8),
                  child: BlendWarningBanner(),
                ),
              ),
          ],

          // ----------------------------------------------------------------
          // Score breakdown — generous breathing room
          // ----------------------------------------------------------------
          if (!isBlocked && !isNotScored)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.space20, AppTheme.space8,
                  AppTheme.space20, AppTheme.space20),
                child: ScoreBreakdownCard(
                  ingredientQuality: ingredientQuality,
                  safetyPurity: safetyPurity,
                  evidenceResearch: evidenceResearch,
                  brandTrust: brandTrust,
                  sectionBreakdown: detailBlob?['section_breakdown']
                      as Map<String, dynamic>?,
                  hasThirdPartyTesting:
                      _product?.hasThirdPartyTesting == 1,
                  isTrustedManufacturer:
                      _product?.isTrustedManufacturer == 1,
                ),
              ),
            ),

          // ----------------------------------------------------------------
          // Detail section (ingredients, pros/cons, warnings) — key content
          // ----------------------------------------------------------------
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.space20, 0, AppTheme.space20, AppTheme.space20),
              child: blobLoading
                  ? const _DetailShimmer()
                  : blobError
                      ? _DetailErrorBanner(
                          onRetry: () => ref.invalidate(
                              detailBlobProvider(widget.dsldId)),
                        )
                      : _DetailSection(
                          detailBlob: detailBlob,
                          warnings: warnings,
                        ),
            ),
          ),

          // ----------------------------------------------------------------
          // Allergen summary banner
          // ----------------------------------------------------------------
          if (!isBlocked && _product?.allergenSummary != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.space20, 0, AppTheme.space20, AppTheme.space8),
                child: AllergenSummaryBanner(
                    allergenSummary: _product?.allergenSummary),
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
                  AppTheme.space20, AppTheme.space4,
                  AppTheme.space20, AppTheme.space8),
                child: _DeepDiveSection(
                  dsldId: widget.dsldId,
                  activeIngredients: (detailBlob?['ingredients'] as List?)
                          ?.whereType<Map<String, dynamic>>()
                          .toList() ??
                      [],
                  inactiveIngredients:
                      (detailBlob?['inactive_ingredients'] as List?)
                              ?.whereType<Map<String, dynamic>>()
                              .toList() ??
                          [],
                  certificationDetail:
                      detailBlob?['certification_detail'] as Map<String, dynamic>?,
                  evidenceData:
                      detailBlob?['evidence_data'] as Map<String, dynamic>?,
                  formulationDetail:
                      detailBlob?['formulation_detail'] as Map<String, dynamic>?,
                  probioticDetail:
                      detailBlob?['probiotic_detail'] as Map<String, dynamic>?,
                  synergyDetail:
                      detailBlob?['synergy_detail'] as Map<String, dynamic>?,
                  manufacturerDetail:
                      detailBlob?['manufacturer_detail'] as Map<String, dynamic>?,
                  caloriesPerServing: _product?.caloriesPerServing,
                  nutritionDetail:
                      detailBlob?['nutrition_detail'] as Map<String, dynamic>?,
                  unmappedActives:
                      detailBlob?['unmapped_actives'] as Map<String, dynamic>?,
                  heavyMetalDetail:
                      detailBlob?['heavy_metal_detail'] as Map<String, dynamic>?,
                ),
              ),
            ),

          // ----------------------------------------------------------------
          // Refill reminder
          // ----------------------------------------------------------------
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.space20, 0, AppTheme.space20, AppTheme.space12),
              child: RefillReminderCard(
                servingsPerContainer: _product?.servingsPerContainer,
                netContentsQuantity: _product?.netContentsQuantity,
                netContentsUnit: _product?.netContentsUnit,
                dosingSummary: _product?.dosingSummary,
                addedAt: _stackEntry?.addedAt,
              ),
            ),
          ),

          // ----------------------------------------------------------------
          // Better Alternatives — generous bottom spacing
          // ----------------------------------------------------------------
          if (!isBlocked)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.space20, 0, AppTheme.space20, AppTheme.space24),
                child: BetterAlternativesSection(
                  currentDsldId: widget.dsldId,
                  category: _product?.primaryCategory,
                  currentScore: score100,
                ),
              ),
            ),

          // Bottom padding for sticky action bar clearance
          SliverToBoxAdapter(
            child: SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
          ),
        ],
      ),
      // Sticky action bar — always reachable
      bottomNavigationBar: Container(
        padding: EdgeInsets.fromLTRB(
          AppTheme.space20,
          AppTheme.space12,
          AppTheme.space20,
          MediaQuery.of(context).padding.bottom + AppTheme.space12,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(
            top: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
              width: 0.5,
            ),
          ),
        ),
        child: PGStackActionButtons(dsldId: widget.dsldId),
      ),
    );
  }

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
    // Pipeline emits 'warnings' (not 'interaction_warnings')
    final raw = blob['warnings'];
    if (raw is! List) return [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(InteractionWarning.fromJson)
        .toList();
  }

  void _showScoreEducation(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _ScoreEducationSheet(),
    );
  }
}

// ---------------------------------------------------------------------------
// Score education overlay
// ---------------------------------------------------------------------------

class _ScoreEducationSheet extends StatelessWidget {
  const _ScoreEducationSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.85,
      expand: false,
      builder: (context, scrollController) {
        return SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'What does this score mean?',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),

              // How We Score
              Text(
                'How We Score',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Each product is scored 0–100 from our reference catalog. '
                'This explains the core product score, not your personalized '
                'FitScore.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),

              // The 4 Pillars — visual bars
              Text(
                'The 4 Pillars',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              _pillarBar(theme, scheme, 'Ingredient Quality', 25,
                  Icons.science_outlined),
              const SizedBox(height: 8),
              _pillarBar(theme, scheme, 'Safety & Purity', 30,
                  Icons.shield_outlined),
              const SizedBox(height: 8),
              _pillarBar(theme, scheme, 'Evidence & Research', 20,
                  Icons.menu_book_outlined),
              const SizedBox(height: 8),
              _pillarBar(theme, scheme, 'Brand Trust', 5,
                  Icons.verified_outlined),
              const SizedBox(height: 20),

              // Verdict Meanings
              Text(
                'Verdict Meanings',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              _verdictRow(theme, scheme, 'RECOMMENDED', '85-100',
                  AppTheme.scoreExceptional),
              _verdictRow(theme, scheme, 'GOOD', '70-84',
                  AppTheme.scoreExcellent),
              _verdictRow(theme, scheme, 'MODERATE', '55-69',
                  AppTheme.scoreGood),
              _verdictRow(theme, scheme, 'REVIEW', '40-54',
                  AppTheme.scoreFair),
              _verdictRow(theme, scheme, 'BLOCKED / UNSAFE', 'N/A',
                  AppTheme.severityContraindicated),
            ],
          ),
        );
      },
    );
  }

  /// Visual progress bar for a score pillar — shows icon, name, max points,
  /// and a proportional bar (fraction of the total 80-point scale).
  static Widget _pillarBar(
    ThemeData theme,
    ColorScheme scheme,
    String name,
    int maxPoints,
    IconData icon,
  ) {
    final fraction = maxPoints / 80.0; // 80 is the total across all 4 pillars
    return Row(
      children: [
        Icon(icon, size: 16, color: scheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Text(
                    '$maxPoints pts',
                    style: AppTheme.numeric(
                      theme.textTheme.labelSmall!.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                child: LinearProgressIndicator(
                  value: fraction,
                  minHeight: 4,
                  backgroundColor: scheme.surfaceContainerHigh,
                  valueColor: AlwaysStoppedAnimation(scheme.primary),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static Widget _verdictRow(
    ThemeData theme,
    ColorScheme scheme,
    String label,
    String range,
    Color color,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              border: Border.all(color: color, width: 1.5),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          const Spacer(),
          Text(
            range,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Condition alert banner
// ---------------------------------------------------------------------------

/// Parses the pipeline's `interaction_summary_hint` JSON blob and renders
/// a banner **only when relevant to this user**.
///
/// The hint field stores a JSON dict like:
/// ```json
/// {"has_any": true, "highest_severity": "avoid",
///  "condition_ids": ["hypertension", "surgery_scheduled"],
///  "drug_class_ids": ["anticoagulants", "statins"]}
/// ```
///
/// Rendering rules:
///   - `has_any == false` → nothing (no banner at all)
///   - User has matching conditions/drug classes → specific warning with
///     only the matched items, tone matches `highest_severity`
///   - User has profile data but no matches → nothing (no personal risk)
///   - User has NO profile data → generic "has interactions, complete
///     your profile" nudge in neutral tone
class _ConditionAlertBanner extends ConsumerWidget {
  final String hint;

  const _ConditionAlertBanner({required this.hint});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final parsed = _parseHint(hint);
    if (parsed == null || parsed.hasAny != true) {
      return const SizedBox.shrink();
    }

    final profile = ref.watch(profileProvider);
    final hasProfile =
        profile.conditions.isNotEmpty || profile.drugClasses.isNotEmpty;

    final matchedConditions = parsed.conditionIds
        .where(profile.conditions.contains)
        .toList(growable: false);
    final matchedDrugClasses = parsed.drugClassIds
        .where(profile.drugClasses.contains)
        .toList(growable: false);

    final hasMatches =
        matchedConditions.isNotEmpty || matchedDrugClasses.isNotEmpty;

    // Profile is populated but nothing overlaps — this product has known
    // interactions but none apply to this user. Show nothing.
    if (hasProfile && !hasMatches) {
      return const SizedBox.shrink();
    }

    // No profile at all — show generic nudge so the user knows personalization
    // is available.
    if (!hasProfile) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          AppTheme.space20,
          AppTheme.space8,
          AppTheme.space20,
          AppTheme.space12,
        ),
        child: PGSeverityBanner(
          tone: PGBannerTone.neutral,
          title: 'This product has known interactions',
          body: 'Add your health conditions and medications to get '
              'warnings personalized to your profile.',
          actionLabel: 'Complete profile',
          onAction: () => GoRouter.of(context).push(Routes.profileSetup),
        ),
      );
    }

    // Profile populated AND matches found — show specific warning.
    final tone = _toneFor(parsed.highestSeverity);
    final title = _titleFor(parsed.highestSeverity);
    final body = _buildMatchBody(
      matchedConditions: matchedConditions,
      matchedDrugClasses: matchedDrugClasses,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.space20,
        AppTheme.space8,
        AppTheme.space20,
        AppTheme.space12,
      ),
      child: PGSeverityBanner(
        tone: tone,
        title: title,
        body: body,
      ),
    );
  }

  static _InteractionHint? _parseHint(String raw) {
    if (raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      return _InteractionHint(
        hasAny: map['has_any'] == true,
        highestSeverity:
            (map['highest_severity'] as String?)?.toLowerCase() ?? '',
        conditionIds: _listOfStrings(map['condition_ids']),
        drugClassIds: _listOfStrings(map['drug_class_ids']),
      );
    } on FormatException {
      return null;
    }
  }

  static List<String> _listOfStrings(Object? raw) {
    if (raw is List) {
      return raw.map((e) => e.toString()).toList(growable: false);
    }
    return const [];
  }

  static PGBannerTone _toneFor(String severity) {
    switch (severity) {
      case 'contraindicated':
      case 'avoid':
        return PGBannerTone.danger;
      case 'caution':
        return PGBannerTone.caution;
      case 'monitor':
        return PGBannerTone.info;
      default:
        return PGBannerTone.caution;
    }
  }

  static String _titleFor(String severity) {
    switch (severity) {
      case 'contraindicated':
        return 'Do not use — contraindicated for your profile';
      case 'avoid':
        return 'Avoid — conflicts with your profile';
      case 'caution':
        return 'Use with caution — relevant to your profile';
      case 'monitor':
        return 'Worth monitoring — relevant to your profile';
      default:
        return 'Relevant to your profile';
    }
  }

  static String _buildMatchBody({
    required List<String> matchedConditions,
    required List<String> matchedDrugClasses,
  }) {
    final parts = <String>[];
    if (matchedConditions.isNotEmpty) {
      final labels = matchedConditions.map(_humanLabel).join(', ');
      parts.add('Your conditions: $labels');
    }
    if (matchedDrugClasses.isNotEmpty) {
      final labels = matchedDrugClasses.map(_humanLabel).join(', ');
      parts.add('Your medications: $labels');
    }
    parts.add('Scroll down for details on which ingredients are affected.');
    return parts.join('\n');
  }

  /// snake_case → Title Case with known medical-term overrides so the
  /// generic transform doesn't produce "Ttc" or "Nsaids".
  static String _humanLabel(String id) {
    const overrides = {
      'ttc': 'Trying to conceive',
      'nsaids': 'NSAIDs',
      'ssris': 'SSRIs',
      'snris': 'SNRIs',
      'maois': 'MAOIs',
      'gi_disorders': 'GI disorders',
      'gerd': 'GERD',
      'ibs': 'IBS',
      'ibd': 'IBD',
      'copd': 'COPD',
      'pcos': 'PCOS',
      'adhd': 'ADHD',
      'hiv_aids': 'HIV/AIDS',
    };
    final lower = id.toLowerCase();
    if (overrides.containsKey(lower)) return overrides[lower]!;
    return lower
        .split('_')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }
}

/// Lightweight value type for the parsed interaction hint.
class _InteractionHint {
  final bool hasAny;
  final String highestSeverity;
  final List<String> conditionIds;
  final List<String> drugClassIds;

  const _InteractionHint({
    required this.hasAny,
    required this.highestSeverity,
    required this.conditionIds,
    required this.drugClassIds,
  });
}

// ---------------------------------------------------------------------------
// Header section
// ---------------------------------------------------------------------------

class _HeaderSection extends ConsumerWidget {
  final String dsldId;
  final String productName;
  final String brandName;
  final String formFactor;
  final String verdict;
  final String blockingReason;
  final double? score100;
  final String grade;
  final String percentileLabel;
  final List<({String label, bool isCertification})> dietaryTags;
  final bool isBlocked;
  final bool isNotScored;
  final List<Map<String, dynamic>> topWarnings;
  final VoidCallback onScoreInfoTap;
  final String? imageUrl;
  final String? upc;
  final double? ingredientQuality;
  final double? safetyPurity;
  final double? evidenceResearch;
  final double? brandTrust;
  final double mappedCoverage;
  final String? decisionHighlights;

  const _HeaderSection({
    required this.dsldId,
    required this.productName,
    required this.brandName,
    required this.formFactor,
    required this.verdict,
    required this.blockingReason,
    required this.score100,
    required this.grade,
    required this.percentileLabel,
    required this.dietaryTags,
    required this.isBlocked,
    required this.isNotScored,
    required this.topWarnings,
    required this.onScoreInfoTap,
    this.imageUrl,
    this.upc,
    this.ingredientQuality,
    this.safetyPurity,
    this.evidenceResearch,
    this.brandTrust,
    this.mappedCoverage = 0.0,
    this.decisionHighlights,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // FitScore integration — async, shows a "personalized for you" pill
    // next to the score ring. Null while loading or when the product has
    // no base score; the badge handles that by rendering nothing.
    final fitScoreAsync = ref.watch(fitScoreForProductProvider(dsldId));

    return Container(
      color: scheme.surface,
      padding: const EdgeInsets.fromLTRB(
        AppTheme.space24,
        AppTheme.space16,
        AppTheme.space24,
        AppTheme.space24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Product image + name + brand
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProductImage(
                dsldId: dsldId,
                upc: upc,
                productName: productName,
                brandName: brandName,
                formFactor: formFactor,
                score: score100,
                size: 52,
              ),
              const SizedBox(width: AppTheme.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      productName,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                        height: 1.22,
                      ),
                    ),
                    if (brandName.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        brandName,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (formFactor.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        formFactor,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.space20),

          // BLOCKED / UNSAFE banner — replaces score circle
          if (isBlocked)
            _BlockedBanner(
              verdict: verdict,
              blockingReason: blockingReason,
              topWarnings: topWarnings,
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Score ring + grade label + glow
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: (score100 != null && !isNotScored)
                        ? [
                            BoxShadow(
                              color: _glowColor(score100!)
                                  .withValues(alpha: 0.18),
                              blurRadius: 28,
                              spreadRadius: 2,
                            ),
                          ]
                        : null,
                  ),
                  child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    PGScoreRing(
                      score: isNotScored ? null : score100,
                      size: 88,
                      strokeWidth: 6,
                    ),
                    // Info button as floating action
                    Positioned(
                      top: -2,
                      right: -2,
                      child: GestureDetector(
                        onTap: onScoreInfoTap,
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: scheme.surface,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: scheme.outlineVariant,
                              width: 0.8,
                            ),
                          ),
                          child: Icon(
                            Icons.info_outline_rounded,
                            size: 13,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                ),
                // Grade label below ring
                if (!isNotScored && grade.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    grade,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: VerdictBadge.colorFor(verdict),
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
                  ],
                ),
                const SizedBox(width: AppTheme.space16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      VerdictBadge(verdict: verdict),
                      if (isNotScored) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Not enough data to score this product',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ] else if (percentileLabel.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          percentileLabel,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      // FitScore badge — Sprint 4 personalization layer
                      if (!isNotScored) ...[
                        const SizedBox(height: AppTheme.space8),
                        PGFitScoreBadge(
                          result: fitScoreAsync.asData?.value,
                          onTap: fitScoreAsync.asData?.value == null
                              ? null
                              : () => showFitScoreSheet(
                                    context,
                                    fitScoreAsync.asData!.value!,
                                  ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),

          // Inline score explainer — "why this score?" in one line
          if (!isBlocked && !isNotScored && score100 != null && mappedCoverage >= 0.3) ...[
            const SizedBox(height: 12),
            _InlineExplainer(
              score100: score100!,
              ingredientQuality: ingredientQuality,
              safetyPurity: safetyPurity,
              evidenceResearch: evidenceResearch,
              brandTrust: brandTrust,
            ),
          ],

          // Decision highlights — pipeline pre-computed hero insights
          if (decisionHighlights != null && decisionHighlights!.isNotEmpty) ...[
            const SizedBox(height: 10),
            _DecisionHighlights(raw: decisionHighlights!),
          ],

          // Certification + dietary tags
          if (dietaryTags.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: dietaryTags.map((tag) {
                final isCert = tag.isCertification;
                final color = isCert
                    ? AppTheme.severitySafe
                    : AppTheme.scoreExcellent;
                return Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withAlpha(isCert ? 18 : 20),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: color.withAlpha(60)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isCert) ...[
                        Icon(Icons.verified_outlined,
                            size: 12, color: color),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        tag.label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],

          // View Label button (when product has an image/label URL)
          if (imageUrl != null && imageUrl!.isNotEmpty) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.description_outlined, size: 16),
                label: const Text('View Supplement Label'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  side: BorderSide(color: scheme.outlineVariant),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                  ),
                ),
                onPressed: () {
                  final uri = Uri.tryParse(imageUrl!);
                  if (uri != null) {
                    launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
              ),
            ),
          ],
        ],
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

  const _BlockedBanner({
    required this.verdict,
    required this.blockingReason,
    required this.topWarnings,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reasonText = blockingReason.isNotEmpty
        ? blockingReason
        : 'No scoring available for this product.';
    final fdaLinks = _extractFdaLinks(topWarnings);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PGSeverityBanner(
          tone: PGBannerTone.danger,
          title: verdict.toUpperCase(),
          body: reasonText,
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
                ...fdaLinks.map((url) => InkWell(
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
                    )),
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

class _DetailSection extends ConsumerWidget {
  final Map<String, dynamic>? detailBlob;
  final List<InteractionWarning> warnings;

  const _DetailSection({
    required this.detailBlob,
    required this.warnings,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

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

    final blob = detailBlob!;

    // Parse structured data from blob
    final ingredients = (blob['ingredients'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .toList() ??
        [];
    final inactiveIngredients = (blob['inactive_ingredients'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .toList() ??
        [];
    final bonuses = (blob['score_bonuses'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .toList() ??
        [];
    final penalties = (blob['score_penalties'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .toList() ??
        [];
    final ingredientsSummary =
        blob['ingredients_summary']?.toString() ?? '';

    // Interaction summary with condition details
    final interactionSummary =
        blob['interaction_summary'] as Map<String, dynamic>?;

    // Profile-gated warning filter (schema v5.2+ contract).
    //
    // Every pipeline warning carries a `display_mode_default` derived
    // from its severity and ban_context:
    //   - "critical"      → always show (substance hazard, contraindicated rule)
    //   - "informational" → show as neutral note regardless of profile
    //   - "suppress"      → hide unless user profile matches the rule's
    //                        trigger tags (condition_id / drug_class_id)
    //
    // Prior behavior: generic warnings (both tags null) always rendered
    // via `return true`, which surfaced scary-looking rules to users
    // who had no matching profile. The fix reads the pipeline's
    // `display_mode_default` and only falls through to "show it" when
    // the rule is intrinsically worth showing (critical / informational)
    // OR the user's declared profile matches.
    final filteredWarnings = warnings.where((w) {
      // Rule 1 — profile match always shows (promotes to "alert" in UI).
      if (w.matchesProfile(
        userConditions: userConditions,
        userDrugClasses: userDrugClasses,
      )) {
        return true;
      }
      // Rule 2 — pipeline told us how to handle the no-match case.
      final mode = w.displayModeDefault;
      if (mode == 'critical' || mode == 'informational') {
        return true;
      }
      if (mode == 'suppress') {
        return false;
      }
      // Rule 3 — legacy blobs predating v5.2 have no display_mode.
      // Fall back to the old logic ONLY for warnings that carry a
      // condition_id or drug_class_id — those are profile-gated by
      // construction. Generic no-tag legacy warnings default to
      // "informational" (render) — backward-compatible but will no
      // longer trigger the scary fallback once the pipeline reprocesses
      // products under v5.2.
      if (w.conditionId != null && w.conditionId!.isNotEmpty) return false;
      if (w.drugClassId != null && w.drugClassId!.isNotEmpty) return false;
      return true;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ---- Active Ingredients (collapsible — long for multivitamins) ----
        if (ingredients.isNotEmpty) ...[
          _CollapsibleIngredients(ingredients: ingredients),
          const SizedBox(height: 20),
        ] else if (ingredientsSummary.isNotEmpty) ...[
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

        // ---- Form & Absorption (bioavailability comparison) ----
        if (ingredients.length >= 2) ...[
          FormAbsorptionSection(ingredients: ingredients),
          const SizedBox(height: 20),
        ],

        // ---- Inactive Ingredients ----
        if (inactiveIngredients.isNotEmpty) ...[
          _sectionTitle(theme, 'Other Ingredients', inactiveIngredients.length),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: inactiveIngredients.map((ing) {
              final name = ing['name']?.toString() ?? ing['raw_source_text']?.toString() ?? '';
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                ),
                child: Text(
                  name,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
        ],

        // ---- Pros (score bonuses) ----
        if (bonuses.isNotEmpty) ...[
          _sectionTitle(theme, 'Strengths', bonuses.length,
              icon: Icons.thumb_up_outlined, color: AppTheme.severitySafe),
          const SizedBox(height: 8),
          ...bonuses.map((b) => _ProConTile(
                label: b['label']?.toString() ?? b['reason']?.toString() ?? '',
                detail: b['detail']?.toString() ?? b['description']?.toString() ?? '',
                isPositive: true,
              )),
          const SizedBox(height: 20),
        ],

        // ---- Cons (score penalties) ----
        if (penalties.isNotEmpty) ...[
          _sectionTitle(theme, 'Concerns', penalties.length,
              icon: Icons.thumb_down_outlined, color: AppTheme.severityAvoid),
          const SizedBox(height: 8),
          ...penalties.map((p) => _ProConTile(
                label: p['label']?.toString() ?? p['reason']?.toString() ?? '',
                detail: p['detail']?.toString() ?? p['description']?.toString() ?? '',
                isPositive: false,
              )),
          const SizedBox(height: 20),
        ],

        // ---- Condition-specific interaction details (filtered by profile) ----
        if (interactionSummary != null) ...[
          _InteractionConditionDetails(
            summary: interactionSummary,
            userConditions: userConditions,
            userDrugClasses: userDrugClasses,
          ),
          const SizedBox(height: 20),
        ],

        // Interaction warnings (filtered by profile).
        InteractionWarningsList(warnings: filteredWarnings),
      ],
    );
  }

  Widget _sectionTitle(ThemeData theme, String title, int count,
      {IconData? icon, Color? color}) {
    final scheme = theme.colorScheme;
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 18, color: color ?? scheme.primary),
          const SizedBox(width: 6),
        ],
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
            color: color,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(AppTheme.radiusFull),
          ),
          child: Text(
            '$count',
            style: AppTheme.numeric(TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            )),
          ),
        ),
      ],
    );
  }
}

/// Collapsible wrapper for the Active Ingredients list.
///
/// Multivitamins can have 20+ actives which makes the product page
/// unreadably long. Tap the row (which shows "N Active Ingredients") to
/// toggle the full list open or closed. Collapsed by default for lists
/// longer than 5 ingredients; short lists stay expanded.
class _CollapsibleIngredients extends StatefulWidget {
  final List<Map<String, dynamic>> ingredients;
  const _CollapsibleIngredients({required this.ingredients});

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
                      horizontal: 7, vertical: 2),
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
                    children: widget.ingredients
                        .map((ing) => _IngredientTile(ingredient: ing))
                        .toList(),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

/// A single active ingredient row showing name, dose, form, and category.
class _IngredientTile extends StatelessWidget {
  final Map<String, dynamic> ingredient;
  const _IngredientTile({required this.ingredient});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final name = ingredient['standard_name']?.toString() ??
        ingredient['name']?.toString() ??
        ingredient['raw_source_text']?.toString() ??
        '';
    final quantity = ingredient['quantity'];
    final unit = ingredient['unit']?.toString() ?? '';
    final form = ingredient['form']?.toString() ?? '';
    final category = ingredient['category']?.toString() ?? '';
    final bioScore = ingredient['bio_score'];

    final doseLabel = quantity != null ? '$quantity $unit'.trim() : '';

    // Compact row — no card border, bottom divider only (premium density)
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppTheme.space8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Bioavailability indicator dot
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  color: bioScore != null
                      ? _bioColor(bioScore)
                      : scheme.outlineVariant,
                  shape: BoxShape.circle,
                ),
              ),
              // Name + dose on one line
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        _SafetyTag(bioScore: bioScore, ingredient: ingredient),
                        if (form.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Text(
                            form,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontSize: 10,
                            ),
                          ),
                        ],
                        if (category.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer
                                  .withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(
                                AppTheme.radiusFull),
                            ),
                            child: Text(
                              category,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onPrimaryContainer,
                                fontSize: 9,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Divider(height: 0.5, thickness: 0.5, color: scheme.outlineVariant),
      ],
    );
  }

  Color _bioColor(dynamic score) {
    final s = (score is num) ? score.toDouble() : 0.0;
    if (s >= 12) return AppTheme.severitySafe;
    if (s >= 8) return AppTheme.scoreGood;
    if (s >= 4) return AppTheme.severityCaution;
    return AppTheme.severityAvoid;
  }
}

/// Compact safety tag chip for ingredients — "Safe", "Caution", or "Risky".
class _SafetyTag extends StatelessWidget {
  final dynamic bioScore;
  final Map<String, dynamic> ingredient;

  const _SafetyTag({required this.bioScore, required this.ingredient});

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = _resolve();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
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
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  (String, Color, IconData) _resolve() {
    // Check for explicit flags first
    final hasWarning = ingredient['has_interaction'] == true ||
        ingredient['has_warning'] == true;
    if (hasWarning) {
      return ('Caution', AppTheme.severityCaution, Icons.warning_amber_rounded);
    }

    // Fall back to bioavailability score
    final s = (bioScore is num) ? (bioScore as num).toDouble() : -1.0;
    if (s < 0) {
      return ('Unknown', AppTheme.insufficientData, Icons.help_outline_rounded);
    }
    if (s >= 10) {
      return ('Well dosed', AppTheme.severitySafe, Icons.check_circle_outline);
    }
    if (s >= 6) {
      return ('Adequate', AppTheme.scoreGood, Icons.check_circle_outline);
    }
    if (s >= 3) {
      return ('Low form', AppTheme.severityCaution, Icons.info_outline);
    }
    return ('Poor form', AppTheme.severityAvoid, Icons.warning_amber_rounded);
  }
}

/// A pro or con item with icon and label.
class _ProConTile extends StatelessWidget {
  final String label;
  final String detail;
  final bool isPositive;

  const _ProConTile({
    required this.label,
    required this.detail,
    required this.isPositive,
  });

  @override
  Widget build(BuildContext context) {
    if (label.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = isPositive ? AppTheme.severitySafe : AppTheme.severityAvoid;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              isPositive ? Icons.add_circle_outline : Icons.remove_circle_outline,
              size: 16,
              color: color,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (detail.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(
                    detail,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows which specific conditions and drug classes are affected and why.
///
/// Filters by the user's actual profile — only conditions the user has
/// selected and drug classes the user takes are shown. Without this
/// filter a multivitamin would list every possible condition interaction
/// regardless of relevance.
class _InteractionConditionDetails extends StatelessWidget {
  final Map<String, dynamic> summary;
  final Set<String> userConditions;
  final Set<String> userDrugClasses;

  const _InteractionConditionDetails({
    required this.summary,
    required this.userConditions,
    required this.userDrugClasses,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final conditionSummary =
        summary['condition_summary'] as Map<String, dynamic>? ?? {};
    final drugClassSummary =
        summary['drug_class_summary'] as Map<String, dynamic>? ?? {};

    // Filter to only conditions/drug classes in the user's profile.
    final relevantConditions = conditionSummary.entries
        .where((e) => userConditions.contains(e.key))
        .toList();
    final relevantDrugClasses = drugClassSummary.entries
        .where((e) => userDrugClasses.contains(e.key))
        .toList();

    if (relevantConditions.isEmpty && relevantDrugClasses.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Why this may affect you',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 10),

        // Condition details (filtered to user's profile)
        ...relevantConditions.map((e) {
          final data = e.value as Map<String, dynamic>? ?? {};
          final label = data['label']?.toString() ?? e.key;
          final severity = data['highest_severity']?.toString() ?? '';
          final ingredients = (data['ingredients'] as List?)
                  ?.map((i) => i.toString())
                  .toList() ??
              [];
          final actions = (data['actions'] as List?)
                  ?.map((a) => a.toString())
                  .toList() ??
              [];
          return _ConditionCard(
            icon: Icons.medical_information_outlined,
            label: label,
            severity: severity,
            ingredients: ingredients,
            actions: actions,
          );
        }),

        // Drug class details (filtered to user's medications)
        ...relevantDrugClasses.map((e) {
          final data = e.value as Map<String, dynamic>? ?? {};
          final label = data['label']?.toString() ?? e.key;
          final severity = data['highest_severity']?.toString() ?? '';
          final ingredients = (data['ingredients'] as List?)
                  ?.map((i) => i.toString())
                  .toList() ??
              [];
          final actions = (data['actions'] as List?)
                  ?.map((a) => a.toString())
                  .toList() ??
              [];
          return _ConditionCard(
            icon: Icons.medication_outlined,
            label: label,
            severity: severity,
            ingredients: ingredients,
            actions: actions,
          );
        }),
      ],
    );
  }
}

/// A card explaining one condition or drug class interaction.
class _ConditionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String severity;
  final List<String> ingredients;
  final List<String> actions;

  const _ConditionCard({
    required this.icon,
    required this.label,
    required this.severity,
    required this.ingredients,
    required this.actions,
  });

  Color _severityColor() {
    switch (severity.toLowerCase()) {
      case 'contraindicated':
      case 'avoid':
        return AppTheme.severityContraindicated;
      case 'caution':
        return AppTheme.severityCaution;
      case 'monitor':
        return AppTheme.severityMonitor;
      default:
        return AppTheme.severityCaution;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = _severityColor();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(AppTheme.space12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          border: Border.all(color: color.withValues(alpha: 0.2), width: 0.8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    severity.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: color,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
            if (ingredients.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Affected by: ${ingredients.join(", ")}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 4),
              ...actions.map((a) => Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('  \u2022 ', style: TextStyle(fontSize: 12)),
                        Expanded(
                          child: Text(
                            a,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )),
            ],
          ],
        ),
      ),
    );
  }
}

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
      description:
          'Pull to refresh, or try again once you have connectivity.',
      actionLabel: 'Retry',
      onAction: onRetry,
      variant: PGEmptyStateVariant.offline,
    );
  }
}

// Old _ActionButtons removed — replaced by [PGStackActionButtons] which
// handles safety check, add/remove, and undo snackbar.

// ---------------------------------------------------------------------------
// "Why this score?" — compact explainer card
// ---------------------------------------------------------------------------

/// Score-tier color for the glow behind the ring on the header.
Color _glowColor(double score) {
  if (score >= 85) return AppTheme.scoreExceptional;
  if (score >= 70) return AppTheme.scoreExcellent;
  if (score >= 55) return AppTheme.scoreGood;
  if (score >= 40) return AppTheme.scoreFair;
  return AppTheme.scoreBelowAvg;
}

/// Compact inline explainer — renders inside the header, right under the
/// verdict badge. One line: icon + "why this score" summary.
class _InlineExplainer extends StatelessWidget {
  final double score100;
  final double? ingredientQuality;
  final double? safetyPurity;
  final double? evidenceResearch;
  final double? brandTrust;

  const _InlineExplainer({
    required this.score100,
    this.ingredientQuality,
    this.safetyPurity,
    this.evidenceResearch,
    this.brandTrust,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = _buildSummary();
    final color = _scoreColor();

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.space12,
        vertical: AppTheme.space8,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      ),
      child: Row(
        children: [
          Icon(_scoreIcon(), size: 15, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              summary,
              style: theme.textTheme.bodySmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  String _buildSummary() {
    final scores = <String, double>{
      if (ingredientQuality != null) 'Ingredient quality': ingredientQuality!,
      if (safetyPurity != null) 'Safety & purity': safetyPurity!,
      if (evidenceResearch != null) 'Evidence': evidenceResearch!,
      if (brandTrust != null) 'Brand trust': brandTrust!,
    };

    if (scores.isEmpty) return 'Score based on available data.';

    if (score100 >= 80) {
      final best = scores.entries.reduce(
        (a, b) => a.value >= b.value ? a : b,
      );
      return 'Strong overall quality \u2022 ${best.key} rated highest';
    }

    if (score100 >= 50) {
      final weakest = scores.entries.reduce(
        (a, b) => a.value <= b.value ? a : b,
      );
      return 'Moderate quality \u2022 ${weakest.key} could be stronger';
    }

    final weakest = scores.entries.reduce(
      (a, b) => a.value <= b.value ? a : b,
    );
    return 'Quality concerns \u2022 Low ${weakest.key.toLowerCase()} score';
  }

  Color _scoreColor() {
    if (score100 >= 80) return AppTheme.severitySafe;
    if (score100 >= 50) return AppTheme.severityCaution;
    return AppTheme.severityAvoid;
  }

  IconData _scoreIcon() {
    if (score100 >= 80) return Icons.check_circle_outline;
    if (score100 >= 50) return Icons.info_outline;
    return Icons.warning_amber_rounded;
  }
}

/// Renders pipeline decision_highlights — compact positive/caution/trust lines.
class _DecisionHighlights extends StatelessWidget {
  final String raw;
  const _DecisionHighlights({required this.raw});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Map<String, dynamic> parsed;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const SizedBox.shrink();
      parsed = Map<String, dynamic>.from(decoded);
    } on FormatException {
      return const SizedBox.shrink();
    }

    final positive = parsed['positive']?.toString() ?? '';
    final caution = parsed['caution']?.toString() ?? '';
    final trust = parsed['trust']?.toString() ?? '';

    if (positive.isEmpty && caution.isEmpty && trust.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (positive.isNotEmpty) _highlight(
          theme, Icons.thumb_up_outlined, AppTheme.severitySafe, positive),
        if (caution.isNotEmpty) _highlight(
          theme, Icons.info_outline, AppTheme.severityCaution, caution),
        if (trust.isNotEmpty) _highlight(
          theme, Icons.verified_outlined, AppTheme.evidenceStrong, trust),
      ],
    );
  }

  Widget _highlight(ThemeData theme, IconData icon, Color color, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 13, color: color),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.3,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Deep dive — collapsible wrapper for detailed analysis sections.
// Keeps the product detail scroll depth manageable while making all data
// accessible on demand. Initially collapsed; user taps to expand.
// ---------------------------------------------------------------------------

class _DeepDiveSection extends StatefulWidget {
  final String dsldId;
  final Map<String, dynamic>? certificationDetail;
  final Map<String, dynamic>? evidenceData;
  final Map<String, dynamic>? formulationDetail;
  final Map<String, dynamic>? probioticDetail;
  final Map<String, dynamic>? synergyDetail;
  final Map<String, dynamic>? manufacturerDetail;
  final double? caloriesPerServing;
  final Map<String, dynamic>? nutritionDetail;
  final Map<String, dynamic>? unmappedActives;
  final List<Map<String, dynamic>> activeIngredients;
  final List<Map<String, dynamic>> inactiveIngredients;
  final Map<String, dynamic>? heavyMetalDetail;

  const _DeepDiveSection({
    required this.dsldId,
    required this.activeIngredients,
    required this.inactiveIngredients,
    this.heavyMetalDetail,
    this.certificationDetail,
    this.evidenceData,
    this.formulationDetail,
    this.probioticDetail,
    this.synergyDetail,
    this.manufacturerDetail,
    this.caloriesPerServing,
    this.nutritionDetail,
    this.unmappedActives,
  });

  @override
  State<_DeepDiveSection> createState() => _DeepDiveSectionState();
}

class _DeepDiveSectionState extends State<_DeepDiveSection>
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
                EvidenceDetailSection(
                  evidenceData: widget.evidenceData,
                ),
                const SizedBox(height: AppTheme.space8),
                HeavyMetalWarningCard(
                    heavyMetalDetail: widget.heavyMetalDetail),
                const SizedBox(height: AppTheme.space8),
                ExcipientDensityCard(
                  activeIngredients: widget.activeIngredients,
                  inactiveIngredients: widget.inactiveIngredients,
                ),
                const SizedBox(height: AppTheme.space8),
                FormulationDetailSection(
                  formulationDetail: widget.formulationDetail,
                ),
                const SizedBox(height: AppTheme.space8),
                ProbioticDetailSection(
                  probioticDetail: widget.probioticDetail,
                ),
                const SizedBox(height: AppTheme.space8),
                PairsWellSection(dsldId: widget.dsldId),
                const SizedBox(height: AppTheme.space8),
                SynergyDetailSection(
                  synergyDetail: widget.synergyDetail,
                ),
                const SizedBox(height: AppTheme.space8),
                ManufacturerViolationsSection(
                  manufacturerDetail: widget.manufacturerDetail,
                ),
                const SizedBox(height: AppTheme.space8),
                NutritionPanel(
                  caloriesPerServing: widget.caloriesPerServing,
                  nutritionDetail: widget.nutritionDetail,
                ),
                const SizedBox(height: AppTheme.space8),
                UnmappedActivesDisclosure(
                  unmappedActives: widget.unmappedActives,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
