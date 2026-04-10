import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/core/constants/app_colors.dart';
import 'package:pharmaguide/core/constants/score_colors.dart';
import 'package:pharmaguide/core/widgets/verdict_badge.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/data/supabase/detail_blob_service.dart';
import 'package:pharmaguide/features/product_detail/widgets/better_alternatives.dart';
import 'package:pharmaguide/features/product_detail/widgets/blend_warning_banner.dart';
import 'package:pharmaguide/features/product_detail/widgets/interaction_warnings.dart';
import 'package:pharmaguide/features/product_detail/widgets/score_breakdown_card.dart';
import 'package:pharmaguide/features/product_detail/widgets/unknown_ingredient_banner.dart';
import 'package:shimmer/shimmer.dart';
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

class _ProductDetailScreenState extends ConsumerState<ProductDetailScreen>
    with SingleTickerProviderStateMixin {
  final _blobService = DetailBlobService();

  // Product from CoreDatabase.
  ProductsCoreData? _product;
  bool _productLoading = true;

  // Cached detail blob.
  Map<String, dynamic>? _detailBlob;
  bool _blobLoading = true;
  bool _blobError = false;

  // Score ring animation.
  late AnimationController _scoreAnimController;
  late Animation<double> _scoreAnimation;

  /// 24-hour cache TTL for detail blobs.
  static const _cacheTtl = Duration(hours: 24);

  @override
  void initState() {
    super.initState();
    _scoreAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _scoreAnimation = Tween<double>(begin: 0, end: 0).animate(
      CurvedAnimation(
        parent: _scoreAnimController,
        curve: Curves.easeOutCubic,
      ),
    );
    _loadProduct();
    _loadDetailBlob();
  }

  @override
  void dispose() {
    _scoreAnimController.dispose();
    super.dispose();
  }

  Future<void> _loadProduct() async {
    final coreDb = ref.read(coreDatabaseProvider);
    final product = await coreDb.findById(widget.dsldId);
    if (mounted) {
      setState(() {
        _product = product;
        _productLoading = false;
      });
      // Start score animation if we have a score.
      final score = product?.score100Equivalent;
      if (score != null && !_isNotScored(product)) {
        _scoreAnimation = Tween<double>(begin: 0, end: score).animate(
          CurvedAnimation(
            parent: _scoreAnimController,
            curve: Curves.easeOutCubic,
          ),
        );
        unawaited(_scoreAnimController.forward());
      }
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

    // Detail blob data
    final warnings = _parseWarnings();
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
              scoreAnimation: _scoreAnimation,
              onScoreInfoTap: () => _showScoreEducation(context),
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
          // Action buttons
          // ----------------------------------------------------------------
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              child: _ActionButtons(dsldId: widget.dsldId),
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
    } catch (_) {
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

class _ConditionAlertBanner extends StatelessWidget {
  final String hint;

  const _ConditionAlertBanner({required this.hint});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.orange.withAlpha(15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.orange.withAlpha(80)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: AppColors.orange,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                hint,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textPrimary,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header section
// ---------------------------------------------------------------------------

class _HeaderSection extends StatelessWidget {
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
  final Animation<double> scoreAnimation;
  final VoidCallback onScoreInfoTap;

  const _HeaderSection({
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
    required this.scoreAnimation,
    required this.onScoreInfoTap,
  });

  Color _scoreColor(double? score) => scoreColor(score);

  @override
  Widget build(BuildContext context) {
    final scoreColor = isBlocked ? AppColors.red : _scoreColor(score100);

    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Product name + brand
          Text(
            productName,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          if (brandName.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              brandName,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          if (formFactor.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              formFactor,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 16),

          // BLOCKED / UNSAFE banner — replaces score circle
          if (isBlocked)
            _BlockedBanner(
              verdict: verdict,
              blockingReason: blockingReason,
              topWarnings: topWarnings,
            )
          else if (isNotScored)
            // NOT_SCORED — grey circle with N/A
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const _NotScoredCircle(),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      VerdictBadge(verdict: verdict),
                      const SizedBox(height: 6),
                      const Text(
                        'Not enough data to score this product',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Animated score circle with info button
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    _AnimatedScoreCircle(
                      animation: scoreAnimation,
                      targetScore: score100,
                      grade: grade,
                      color: scoreColor,
                    ),
                    Positioned(
                      top: -4,
                      right: -4,
                      child: GestureDetector(
                        onTap: onScoreInfoTap,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: AppColors.border, width: 1),
                          ),
                          child: const Icon(
                            Icons.info_outline,
                            size: 14,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Verdict badge
                      VerdictBadge(verdict: verdict),
                      if (percentileLabel.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          percentileLabel,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
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
// Animated score circle widget
// ---------------------------------------------------------------------------

class _AnimatedScoreCircle extends AnimatedWidget {
  final Animation<double> animation;
  final double? targetScore;
  final String grade;
  final Color color;

  const _AnimatedScoreCircle({
    required this.animation,
    required this.targetScore,
    required this.grade,
    required this.color,
  }) : super(listenable: animation);

  @override
  Widget build(BuildContext context) {
    final animValue = animation.value;
    final displayScore = targetScore != null
        ? animValue.toStringAsFixed(0)
        : '--';
    final progress = targetScore != null
        ? (animValue / 100).clamp(0.0, 1.0)
        : 0.0;

    return SizedBox(
      width: 72,
      height: 72,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: progress,
            strokeWidth: 6,
            backgroundColor: AppColors.border,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                displayScore,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              if (grade.isNotEmpty)
                Text(
                  grade,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// NOT_SCORED grey circle
// ---------------------------------------------------------------------------

class _NotScoredCircle extends StatelessWidget {
  const _NotScoredCircle();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 72,
      height: 72,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: 0,
            strokeWidth: 6,
            backgroundColor: AppColors.border,
            valueColor:
                AlwaysStoppedAnimation<Color>(AppColors.textSecondary),
          ),
          Text(
            'N/A',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Blocked / Unsafe full-width banner
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
    final reasonText = blockingReason.isNotEmpty
        ? blockingReason
        : 'No scoring available for this product.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.red.withAlpha(15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.red.withAlpha(80)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.block, color: AppColors.red, size: 18),
              const SizedBox(width: 8),
              Text(
                verdict.toUpperCase(),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.red,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'This product cannot be scored due to:',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.red.withAlpha(180),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            reasonText,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.red,
            ),
          ),
          // FDA source links from top_warnings
          ..._fdaLinks(topWarnings),
        ],
      ),
    );
  }

  List<Widget> _fdaLinks(List<Map<String, dynamic>> warnings) {
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
    if (links.isEmpty) return [];
    return [
      const SizedBox(height: 10),
      const Text(
        'FDA Links:',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.red,
        ),
      ),
      ...links.map(
        (url) => GestureDetector(
          onTap: () async {
            final uri = Uri.tryParse(url);
            if (uri != null) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          },
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              url,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.red,
                decoration: TextDecoration.underline,
                overflow: TextOverflow.ellipsis,
              ),
              maxLines: 1,
            ),
          ),
        ),
      ),
    ];
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
    return Shimmer.fromColors(
      baseColor: AppColors.border,
      highlightColor: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _shimmerBox(height: 20, width: 120),
          const SizedBox(height: 10),
          _shimmerBox(height: 14),
          const SizedBox(height: 6),
          _shimmerBox(height: 14),
          const SizedBox(height: 6),
          _shimmerBox(height: 14, width: 240),
          const SizedBox(height: 20),
          _shimmerBox(height: 20, width: 160),
          const SizedBox(height: 10),
          _shimmerBox(height: 80),
          const SizedBox(height: 12),
          _shimmerBox(height: 80),
        ],
      ),
    );
  }

  Widget _shimmerBox({double height = 16, double? width}) {
    return Container(
      width: width ?? double.infinity,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.border,
        borderRadius: BorderRadius.circular(6),
      ),
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.border.withAlpha(60),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_outlined,
              color: AppColors.textSecondary, size: 20),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Could not load product details.',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Action buttons
// ---------------------------------------------------------------------------

class _ActionButtons extends StatelessWidget {
  final String dsldId;

  const _ActionButtons({required this.dsldId});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: () {
            // TODO: add product to user stack via StackProvider
          },
          icon: const Icon(Icons.add),
          label: const Text('Add to Stack'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  // TODO: trigger share_plus with product share data
                },
                icon: const Icon(Icons.share_outlined),
                label: const Text('Share'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  // TODO: save to favorites via FavoritesProvider
                },
                icon: const Icon(Icons.bookmark_border_outlined),
                label: const Text('Save'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
