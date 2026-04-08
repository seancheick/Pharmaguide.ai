import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/constants/app_colors.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';

/// Shows up to 5 higher-scored products in the same category.
/// Hidden if no alternatives found or product is already top-scored.
class BetterAlternativesSection extends ConsumerWidget {
  final String currentDsldId;
  final String? category;
  final double? currentScore;

  const BetterAlternativesSection({
    super.key,
    required this.currentDsldId,
    this.category,
    this.currentScore,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (category == null || category!.isEmpty || currentScore == null) {
      return const SizedBox.shrink();
    }

    final coreDb = ref.watch(coreDatabaseProvider);

    return FutureBuilder<List<ProductsCoreData>>(
      future: coreDb.findAlternatives(
        category!,
        currentScore!,
        excludeDsldId: currentDsldId,
        limit: 5,
      ),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }

        final alternatives = snapshot.data!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Better Alternatives',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Higher-scored products in this category',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            ...alternatives.map(
              (product) => _AlternativeCard(product: product),
            ),
          ],
        );
      },
    );
  }
}

class _AlternativeCard extends StatelessWidget {
  final ProductsCoreData product;

  const _AlternativeCard({required this.product});

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
    final score = product.score100Equivalent;
    final color = _scoreColor(score);

    return GestureDetector(
      onTap: () => context.push('/product/${product.dsldId}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            // Score badge
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withAlpha(20),
                border: Border.all(color: color.withAlpha(80)),
              ),
              alignment: Alignment.center,
              child: Text(
                score?.toStringAsFixed(0) ?? '--',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Product info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.productName,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (product.brandName != null &&
                      product.brandName!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      product.brandName!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}
