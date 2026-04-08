import 'package:flutter/material.dart';
import 'package:pharmaguide/core/constants/app_colors.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/supabase/detail_blob_service.dart';
import 'package:pharmaguide/features/product_detail/widgets/blend_warning_banner.dart';
import 'package:pharmaguide/features/product_detail/widgets/interaction_warnings.dart';
import 'package:pharmaguide/features/product_detail/widgets/score_breakdown_card.dart';
import 'package:pharmaguide/features/product_detail/widgets/unknown_ingredient_banner.dart';
import 'package:shimmer/shimmer.dart';

/// Product detail screen.
/// Receives [dsldId] from route params (e.g. `/product/12345`).
///
/// Architecture:
/// - Header data (name, score, verdict) comes from local `products_core` DB —
///   zero network latency, instant render.
/// - Detail blob (ingredients, interactions, evidence) loaded async from
///   Supabase and cached in memory for the session.
///
/// TODO: Replace [_mockProduct] with a real CoreDatabase provider lookup.
/// TODO: Replace [_detailBlobService] with a Riverpod-managed singleton.
class ProductDetailScreen extends StatefulWidget {
  final String dsldId;

  const ProductDetailScreen({super.key, required this.dsldId});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  // TODO: Replace with Riverpod provider injection once CoreDatabase is wired.
  final _blobService = DetailBlobService();

  // Cached detail blob for this session.
  Map<String, dynamic>? _detailBlob;
  bool _blobLoading = true;
  bool _blobError = false;

  // TODO: Replace with `ref.watch(coreDatabaseProvider).findById(widget.dsldId)`
  // when the CoreDatabase Riverpod provider is set up.
  ProductsCoreData? get _product => null; // placeholder

  @override
  void initState() {
    super.initState();
    _loadDetailBlob();
  }

  Future<void> _loadDetailBlob() async {
    setState(() {
      _blobLoading = true;
      _blobError = false;
    });
    try {
      final blob = await _blobService.fetchDetailBlob(widget.dsldId);
      if (mounted) {
        setState(() {
          _detailBlob = blob;
          _blobLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _blobLoading = false;
          _blobError = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // TODO: Replace with real product data from CoreDatabase provider.
    // For now we use a mock product to allow the screen to render while
    // the provider integration is pending.
    final productName = _product?.productName ?? 'Product ${widget.dsldId}';
    final brandName = _product?.brandName ?? '';
    final formFactor = _product?.formFactor ?? '';
    final verdict = _product?.verdict ?? '';
    final blockingReason = _product?.blockingReason ?? '';
    final score100 = _product?.score100Equivalent;
    final grade = _product?.grade ?? '';
    final mappedCoverage = _product?.mappedCoverage ?? 1.0;
    final percentileLabel = _product?.percentileLabel ?? '';

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
              topWarnings: _topWarnings(),
            ),
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
          // Score breakdown (hidden for BLOCKED / UNSAFE)
          // ----------------------------------------------------------------
          if (!isBlocked)
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
      // topWarnings is stored as JSON text in the DB
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
  final List<Map<String, dynamic>> topWarnings;

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
    required this.topWarnings,
  });

  Color _scoreColor(double? score) {
    if (score == null) return AppColors.textSecondary;
    if (score >= 85) return AppColors.scoreExceptional;
    if (score >= 70) return AppColors.scoreExcellent;
    if (score >= 55) return AppColors.scoreGood;
    if (score >= 40) return AppColors.scoreFair;
    if (score >= 25) return AppColors.scoreBelowAvg;
    return AppColors.scoreLow;
  }

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
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Score circle
                _ScoreCircle(
                  score: score100,
                  grade: grade,
                  color: scoreColor,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Verdict badge
                      _VerdictBadge(verdict: verdict),
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
// Score circle widget
// ---------------------------------------------------------------------------

class _ScoreCircle extends StatelessWidget {
  final double? score;
  final String grade;
  final Color color;

  const _ScoreCircle({
    required this.score,
    required this.grade,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final displayScore =
        score != null ? score!.toStringAsFixed(0) : '--';

    return SizedBox(
      width: 72,
      height: 72,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: score != null ? (score! / 100).clamp(0.0, 1.0) : 0,
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
// Verdict badge
// ---------------------------------------------------------------------------

class _VerdictBadge extends StatelessWidget {
  final String verdict;

  const _VerdictBadge({required this.verdict});

  Color _colorFor(String v) {
    switch (v.toUpperCase()) {
      case 'RECOMMENDED':
        return AppColors.scoreExceptional;
      case 'GOOD':
        return AppColors.scoreExcellent;
      case 'REVIEW':
        return AppColors.scoreFair;
      case 'MODERATE':
        return AppColors.scoreBelowAvg;
      case 'UNSAFE':
      case 'BLOCKED':
        return AppColors.red;
      default:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (verdict.isEmpty) return const SizedBox.shrink();
    final color = _colorFor(verdict);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Text(
        verdict.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.5,
        ),
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
          onTap: () {
            // TODO: launch url via url_launcher when wired up
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
