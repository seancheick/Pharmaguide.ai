import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_card.dart';
import 'package:pharmaguide/core/widgets/pg_score_ring.dart';
import 'package:pharmaguide/core/widgets/product_image.dart';
import 'package:pharmaguide/core/widgets/verdict_badge.dart';
import 'package:pharmaguide/data/database/core_database.dart';

/// Reusable product list item used in search results, category browsing, etc.
///
/// Uses [PGScoreRing] for the score visualization and [VerdictBadge] for the
/// verdict pill. Tap routes to the product detail screen via go_router.
class ProductListItem extends StatelessWidget {
  final ProductsCoreData product;
  final EdgeInsetsGeometry padding;

  const ProductListItem({
    super.key,
    required this.product,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppTheme.space16,
      vertical: AppTheme.space12,
    ),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final score = product.score100Equivalent;

    final scoreLabel = score != null ? ', score ${score.round()} out of 100' : '';
    final brandLabel = product.brandName != null ? ' by ${product.brandName}' : '';

    return Semantics(
      button: true,
      label: '${product.productName}$brandLabel$scoreLabel. Tap to view details.',
      child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.push('/product/${product.dsldId}'),
        splashColor: scheme.primary.withValues(alpha: 0.08),
        highlightColor: scheme.primary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        child: Padding(
          padding: padding,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Product image (OFF photo or branded placeholder)
              ProductImage(
                dsldId: product.dsldId,
                upc: product.upcSku,
                productName: product.productName,
                brandName: product.brandName ?? '',
                formFactor: product.formFactor,
                score: score,
                size: 48,
              ),
              const SizedBox(width: AppTheme.space12),
              // Animated score ring
              PGScoreRing(
                score: score,
                size: 52,
                strokeWidth: 4,
              ),
              const SizedBox(width: AppTheme.space16),
              // Text column
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      product.productName,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.1,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (product.brandName != null &&
                        product.brandName!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        product.brandName!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (product.verdict != null &&
                        product.verdict!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          VerdictBadge(verdict: product.verdict!),
                          if (product.primaryCategory != null &&
                              product.primaryCategory!.isNotEmpty) ...[
                            const SizedBox(width: AppTheme.space8),
                            Flexible(
                              child: Text(
                                product.primaryCategory!,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  letterSpacing: 0.1,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppTheme.space8),
              Icon(
                Icons.chevron_right_rounded,
                color: scheme.onSurfaceVariant,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }
}

/// Grid-view version of a product card. Uses [PGCard] for the surface and
/// [PGScoreRing] for the score.
class ProductGridItem extends StatelessWidget {
  final ProductsCoreData product;

  const ProductGridItem({super.key, required this.product});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final score = product.score100Equivalent;

    final gridScoreLabel = score != null ? ', score ${score.round()} out of 100' : '';
    final gridBrandLabel = product.brandName != null ? ' by ${product.brandName}' : '';

    return Semantics(
      button: true,
      label: '${product.productName}$gridBrandLabel$gridScoreLabel. Tap to view details.',
      child: PGCard(
      onTap: () => context.push('/product/${product.dsldId}'),
      padding: const EdgeInsets.all(AppTheme.space12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row — image + score ring + verdict badge
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProductImage(
                dsldId: product.dsldId,
                upc: product.upcSku,
                productName: product.productName,
                brandName: product.brandName ?? '',
                formFactor: product.formFactor,
                score: score,
                size: 40,
              ),
              const SizedBox(width: AppTheme.space8),
              PGScoreRing(
                score: score,
                size: 44,
                strokeWidth: 3.5,
              ),
              const Spacer(),
              if (product.verdict != null && product.verdict!.isNotEmpty)
                VerdictBadge(verdict: product.verdict!),
            ],
          ),
          const Spacer(),
          // Product name
          Text(
            product.productName,
            style: theme.textTheme.titleSmall?.copyWith(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.1,
              height: 1.3,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (product.brandName != null && product.brandName!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              product.brandName!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    ),
    );
  }
}
