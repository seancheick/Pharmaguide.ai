import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/constants/app_colors.dart';
import 'package:pharmaguide/data/database/core_database.dart';

/// Reusable product list item used in search results, category browsing, etc.
class ProductListItem extends StatelessWidget {
  final ProductsCoreData product;

  const ProductListItem({super.key, required this.product});

  Color _scoreColor(double? score) {
    if (score == null) return AppColors.textSecondary;
    if (score >= 85) return AppColors.scoreExceptional;
    if (score >= 70) return AppColors.scoreExcellent;
    if (score >= 55) return AppColors.scoreGood;
    if (score >= 40) return AppColors.scoreFair;
    if (score >= 25) return AppColors.scoreBelowAvg;
    return AppColors.scoreLow;
  }

  Color _verdictColor(String? verdict) {
    switch (verdict?.toUpperCase()) {
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
    final score = product.score100Equivalent;
    final color = _scoreColor(score);
    final verdictColor = _verdictColor(product.verdict);

    return InkWell(
      onTap: () => context.push('/product/${product.dsldId}'),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            // Score circle
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withAlpha(20),
                border: Border.all(color: color.withAlpha(80), width: 2),
              ),
              alignment: Alignment.center,
              child: Text(
                score?.toStringAsFixed(0) ?? '--',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ),
            const SizedBox(width: 14),
            // Product info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.productName,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  if (product.brandName != null &&
                      product.brandName!.isNotEmpty)
                    Text(
                      product.brandName!,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 4),
                  // Verdict + category
                  Row(
                    children: [
                      if (product.verdict != null &&
                          product.verdict!.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: verdictColor.withAlpha(20),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            product.verdict!.toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: verdictColor,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      if (product.primaryCategory != null &&
                          product.primaryCategory!.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text(
                          product.primaryCategory!,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                color: AppColors.textSecondary, size: 20),
          ],
        ),
      ),
    );
  }
}

/// Grid-view version of a product card.
class ProductGridItem extends StatelessWidget {
  final ProductsCoreData product;

  const ProductGridItem({super.key, required this.product});

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
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Score badge
            Align(
              alignment: Alignment.topRight,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withAlpha(20),
                  border: Border.all(color: color.withAlpha(80)),
                ),
                alignment: Alignment.center,
                child: Text(
                  score?.toStringAsFixed(0) ?? '--',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
            ),
            const Spacer(),
            // Product name
            Text(
              product.productName,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            if (product.brandName != null && product.brandName!.isNotEmpty)
              Text(
                product.brandName!,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
    );
  }
}
