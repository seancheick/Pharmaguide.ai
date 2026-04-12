import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/constants/app_colors.dart';
import 'package:pharmaguide/core/models/interaction_result.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_empty_state.dart';
import 'package:pharmaguide/core/widgets/pg_fitscore_badge.dart';
import 'package:pharmaguide/core/widgets/pg_score_ring.dart';
import 'package:pharmaguide/core/widgets/pg_severity_banner.dart';
import 'package:pharmaguide/core/widgets/pg_shimmer_box.dart';
import 'package:pharmaguide/core/widgets/verdict_badge.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/data/supabase/detail_blob_service.dart';
import 'package:pharmaguide/services/stack/stack_interaction_checker.dart';
import 'package:pharmaguide/features/product_detail/providers/fit_score_provider.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';
import 'package:pharmaguide/features/product_detail/widgets/better_alternatives.dart';
import 'package:pharmaguide/features/product_detail/widgets/blend_warning_banner.dart';
import 'package:pharmaguide/features/product_detail/widgets/fit_score_sheet.dart';
import 'package:pharmaguide/features/product_detail/widgets/interaction_warnings.dart';
import 'package:pharmaguide/features/product_detail/widgets/nutrition_panel.dart';
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
  final _blobService = DetailBlobService();

  // Product from CoreDatabase.
  ProductsCoreData? _product;
  bool _productLoading = true;

  // Cached detail blob.
  Map<String, dynamic>? _detailBlob;
  bool _blobLoading = true;
  bool _blobError = false;

  // User stack entry for this product (null = not in stack). Powers the
  // refill-reminder card; we need addedAt for the days-remaining math.
  UserStacksLocalData? _stackEntry;

  // Personalized interaction warnings from live DB lookup against user's
  // stack. These supplement the static blob-parsed warnings with
  // "Because you're taking X" context. Spec §9.2.
  List<InteractionWarning> _personalizedWarnings = const [];

  /// 24-hour cache TTL for detail blobs.
  static const _cacheTtl = Duration(hours: 24);

  @override
  void initState() {
    super.initState();
    _loadProduct();
    _loadDetailBlob();
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

      // Extract canonical IDs from this product's ingredient fingerprint.
      final canonicalIds = _extractCanonicalIds(product.ingredientFingerprint);
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
    } on Object {
      // Non-fatal — personalized warnings are a bonus on top of blob
      // warnings. If the interaction DB is missing/corrupt or the
      // provider isn't overridden (tests), we silently fall back to
      // blob-only. Catches both Exception and Error (UnimplementedError
      // from the provider stub).
    }
  }

  /// Extract canonical ingredient IDs from a product's ingredient_fingerprint
  /// JSON. Returns an empty list on null/malformed input.
  static List<String> _extractCanonicalIds(String? fingerprintJson) {
    if (fingerprintJson == null || fingerprintJson.isEmpty) {
      return const <String>[];
    }
    try {
      final decoded = jsonDecode(fingerprintJson);
      if (decoded is Map) {
        return decoded.keys.map((k) => k.toString().toLowerCase()).toList();
      }
      if (decoded is List) {
        return decoded
            .where((e) => e != null)
            .map((e) => e.toString().toLowerCase())
            .toList();
      }
    } on FormatException {
      // Malformed JSON — return empty.
    }
    return const <String>[];
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

  Future<void> _loadDetailBlob() async {
    setState(() {
      _blobLoading = true;
      _blobError = false;
    });

    try {
      final userDb = ref.read(userDatabaseProvider);

      // Check local cache first.
      final cached = await userDb.getCachedDetail(widget.dsldId);
      if (cached != null) {
        final age = DateTime.now().difference(cached.cachedAt);
        if (age < _cacheTtl) {
          if (mounted) {
            setState(() {
              _detailBlob = jsonDecode(cached.blobJson) as Map<String, dynamic>;
              _blobLoading = false;
            });
          }
          return;
        }
      }

      // Cache miss or stale — fetch from network.
      final blob = await _blobService.fetchDetailBlob(widget.dsldId);
      if (mounted) {
        if (blob != null) {
          // Store in cache.
          final blobJson = jsonEncode(blob);
          await userDb.cacheDetail(widget.dsldId, blobJson, null);
        }
        setState(() {
          _detailBlob = blob;
          _blobLoading = false;
        });
      }
    } on Exception {
      if (mounted) {
        setState(() {
          _blobLoading = false;
          _blobError = true;
        });
      }
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
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textPrimary,
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
    final mappedCoverage = _product?.mappedCoverage ?? 1.0;
    final percentileLabel = _product?.percentileLabel ?? '';
    final interactionHint = _product?.interactionSummaryHint ?? '';

    // Section scores
    final ingredientQuality = _product?.scoreIngredientQuality;
    final safetyPurity = _product?.scoreSafetyPurity;
    final evidenceResearch = _product?.scoreEvidenceResearch;
    final brandTrust = _product?.scoreBrandTrust;

    // Dietary tags
    final dietaryTags = _buildDietaryTags();

    // Detail blob data + personalized interaction warnings from live DB.
    // Personalized warnings (from InteractionDatabase) appear first,
    // followed by generic blob warnings — deduped by title to avoid
    // showing the same mechanism twice.
    final blobWarnings = _parseWarnings();
    final seenTitles = <String>{
      for (final w in _personalizedWarnings) w.title,
    };
    final warnings = <InteractionWarning>[
      ..._personalizedWarnings,
      ...blobWarnings.where((w) => !seenTitles.contains(w.title)),
    ];
    final hasProprietaryBlends = _detailBlob?['has_proprietary_blends'] == true;

    final isBlocked =
        verdict == 'BLOCKED' || verdict == 'UNSAFE';
    final isNotScored = _isNotScored(_product);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          // ----------------------------------------------------------------
          // App bar with back button
          // ----------------------------------------------------------------
          SliverAppBar(
            pinned: true,
            backgroundColor: AppColors.surface,
            foregroundColor: AppColors.textPrimary,
            elevation: 0,
            surfaceTintColor: Colors.transparent,
            title: Text(
              productName,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.share_outlined),
                tooltip: 'Share',
                onPressed: () {
                  // TODO: trigger share_plus with share_title / share_description
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
            ),
          ),

          // ----------------------------------------------------------------
          // "Why this score?" — compact 1-liner above the fold
          // ----------------------------------------------------------------
          if (!isBlocked && !isNotScored && score100 != null)
            SliverToBoxAdapter(
              child: _ScoreExplainerCard(
                score100: score100,
                ingredientQuality: ingredientQuality,
                safetyPurity: safetyPurity,
                evidenceResearch: evidenceResearch,
                brandTrust: brandTrust,
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
          // Coverage / blend banners
          // ----------------------------------------------------------------
          if (!isBlocked) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: UnknownIngredientBanner(mappedCoverage: mappedCoverage),
              ),
            ),
            if (hasProprietaryBlends)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: BlendWarningBanner(),
                ),
              ),
          ],

          // ----------------------------------------------------------------
          // Score breakdown (hidden for BLOCKED / UNSAFE / NOT_SCORED)
          // ----------------------------------------------------------------
          if (!isBlocked && !isNotScored)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: ScoreBreakdownCard(
                  ingredientQuality: ingredientQuality,
                  safetyPurity: safetyPurity,
                  evidenceResearch: evidenceResearch,
                  brandTrust: brandTrust,
                ),
              ),
            ),

          // ----------------------------------------------------------------
          // Detail section — shimmer while loading, real data after fetch
          // ----------------------------------------------------------------
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _blobLoading
                  ? const _DetailShimmer()
                  : _blobError
                      ? _DetailErrorBanner(onRetry: _loadDetailBlob)
                      : _DetailSection(
                          detailBlob: _detailBlob,
                          warnings: warnings,
                        ),
            ),
          ),

          // ----------------------------------------------------------------
          // v1.3.2 Nutrition Facts (calories column + nutrition_detail blob)
          // Auto-hides when the product has no nutrition data.
          // ----------------------------------------------------------------
          if (!_blobLoading && !_blobError)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: NutritionPanel(
                  caloriesPerServing: _product?.caloriesPerServing,
                  nutritionDetail: _detailBlob?['nutrition_detail']
                      as Map<String, dynamic>?,
                ),
              ),
            ),

          // ----------------------------------------------------------------
          // v1.3.1 Refill reminder — only shown when the product is in
          // the user's stack AND we have net contents data. Auto-hides
          // otherwise. The card uses servings_per_container + dosing
          // frequency parsed from dosing_summary + the stack entry's
          // addedAt to estimate days remaining and color-code urgency.
          // ----------------------------------------------------------------
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
          // v1.3.2 Unmapped actives transparency — only shown when the
          // pipeline left at least one ingredient unmapped (long-tail
          // exotic extracts, typos, etc.). Auto-hides for the 99.5%+ of
          // products with full coverage.
          // ----------------------------------------------------------------
          if (!_blobLoading && !_blobError)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: UnmappedActivesDisclosure(
                  unmappedActives: _detailBlob?['unmapped_actives']
                      as Map<String, dynamic>?,
                ),
              ),
            ),

          // ----------------------------------------------------------------
          // Better Alternatives
          // ----------------------------------------------------------------
          if (!isBlocked)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: BetterAlternativesSection(
                  currentDsldId: widget.dsldId,
                  category: _product?.primaryCategory,
                  currentScore: score100,
                ),
              ),
            ),

          // ----------------------------------------------------------------
          // Action buttons (Add to Stack with safety check, Share, Save)
          // ----------------------------------------------------------------
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.space20,
                0,
                AppTheme.space20,
                AppTheme.space32,
              ),
              child: PGStackActionButtons(dsldId: widget.dsldId),
            ),
          ),
        ],
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

  List<String> _buildDietaryTags() {
    final tags = <String>[];
    if (_product?.isVegan == 1) tags.add('Vegan');
    if (_product?.isGlutenFree == 1) tags.add('Gluten-Free');
    if (_product?.isDairyFree == 1) tags.add('Dairy-Free');
    if (_product?.isSoyFree == 1) tags.add('Soy-Free');
    if (_product?.isOrganic == 1) tags.add('Organic');
    if (_product?.isNonGmo == 1) tags.add('Non-GMO');
    return tags;
  }

  List<InteractionWarning> _parseWarnings() {
    final blob = _detailBlob;
    if (blob == null) return [];
    final raw = blob['interaction_warnings'];
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
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
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
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'What does this score mean?',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),

              // How We Score
              const Text(
                'How We Score',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Every product receives a FitScore from 0 to 100 based on '
                'the core product data in our reference catalog. This screen '
                'currently explains the core product score, not your '
                'personalized FitScore. Personalized adjustments should be '
                'shown as a separate layer so product evidence and personal '
                'fit are not conflated.',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),

              // The 4 Pillars
              const Text(
                'The 4 Pillars',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              _pillarRow('Ingredient Quality', 'Up to 25 pts',
                  'Dosage accuracy, bioavailability, form quality'),
              _pillarRow('Safety & Purity', 'Up to 30 pts',
                  'Third-party testing, contaminant risk, interactions'),
              _pillarRow('Evidence & Research', 'Up to 20 pts',
                  'Clinical studies, evidence strength, claim support'),
              _pillarRow('Brand Trust', 'Up to 5 pts',
                  'Manufacturing standards, transparency, track record'),
              const SizedBox(height: 20),

              // Verdict Meanings
              const Text(
                'Verdict Meanings',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              _verdictRow('RECOMMENDED', '85-100',
                  AppColors.scoreExceptional),
              _verdictRow('GOOD', '70-84', AppColors.scoreExcellent),
              _verdictRow('MODERATE', '55-69', AppColors.scoreGood),
              _verdictRow('REVIEW', '40-54', AppColors.scoreFair),
              _verdictRow('BLOCKED / UNSAFE', 'N/A', AppColors.red),
            ],
          ),
        );
      },
    );
  }

  static Widget _pillarRow(
      String name, String points, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(top: 6, right: 10),
            decoration: const BoxDecoration(
              color: AppColors.scoreExcellent,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      TextSpan(
                        text: '  $points',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Widget _verdictRow(String label, String range, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color.withAlpha(30),
              border: Border.all(color: color, width: 1.5),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          const Spacer(),
          Text(
            range,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
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
      parts.add('Conditions: $labels');
    }
    if (matchedDrugClasses.isNotEmpty) {
      final labels = matchedDrugClasses.map(_humanLabel).join(', ');
      parts.add('Medications: $labels');
    }
    return parts.join('  •  ');
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
  final List<String> dietaryTags;
  final bool isBlocked;
  final bool isNotScored;
  final List<Map<String, dynamic>> topWarnings;
  final VoidCallback onScoreInfoTap;

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
        AppTheme.space20,
        AppTheme.space16,
        AppTheme.space20,
        AppTheme.space20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Product name + brand
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
          const SizedBox(height: AppTheme.space16),

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
                // Score ring — animated, tabular figure, "–" for NOT_SCORED
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    PGScoreRing(
                      score: isNotScored ? null : score100,
                      size: 76,
                      strokeWidth: 5,
                      label: isNotScored ? null : grade,
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

          // Dietary tags
          if (dietaryTags.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: dietaryTags
                  .map(
                    (tag) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.scoreExcellent.withAlpha(20),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: AppColors.scoreExcellent.withAlpha(60)),
                      ),
                      child: Text(
                        tag,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: AppColors.scoreExceptional,
                        ),
                      ),
                    ),
                  )
                  .toList(),
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

class _DetailSection extends StatelessWidget {
  final Map<String, dynamic>? detailBlob;
  final List<InteractionWarning> warnings;

  const _DetailSection({
    required this.detailBlob,
    required this.warnings,
  });

  @override
  Widget build(BuildContext context) {
    if (detailBlob == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text(
          'No additional details available.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
      );
    }

    final ingredientsSummary =
        detailBlob!['ingredients_summary']?.toString() ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Ingredients
        if (ingredientsSummary.isNotEmpty) ...[
          Text(
            'Ingredients',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            ingredientsSummary,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
        ],

        // Interaction warnings
        InteractionWarningsList(warnings: warnings),
      ],
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

class _ScoreExplainerCard extends StatelessWidget {
  final double score100;
  final double? ingredientQuality;
  final double? safetyPurity;
  final double? evidenceResearch;
  final double? brandTrust;

  const _ScoreExplainerCard({
    required this.score100,
    this.ingredientQuality,
    this.safetyPurity,
    this.evidenceResearch,
    this.brandTrust,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final summary = _buildSummary();
    final color = _scoreColor();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Container(
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
            Icon(
              _scoreIcon(),
              size: 16,
              color: color,
            ),
            const SizedBox(width: AppTheme.space8),
            Expanded(
              child: Text(
                summary,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
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
