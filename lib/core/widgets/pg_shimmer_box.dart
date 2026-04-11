import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';

/// Skeleton loader — a rounded rectangle that shimmers while content loads.
///
/// Use this instead of raw `shimmer` package calls so all loading states
/// share the same base/highlight tones and radius. Light and dark mode
/// handled automatically.
///
/// ```dart
/// PGShimmerBox(height: 18, width: 120)  // headline placeholder
/// PGShimmerBox(height: 80)              // card placeholder
/// PGShimmerBox(height: 44, radius: 22)  // pill placeholder
/// ```
class PGShimmerBox extends StatelessWidget {
  final double height;
  final double? width;
  final double radius;
  final EdgeInsetsGeometry margin;

  const PGShimmerBox({
    super.key,
    this.height = 16,
    this.width,
    this.radius = 8,
    this.margin = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Shimmer.fromColors(
      baseColor: scheme.surfaceContainerHigh,
      highlightColor: scheme.surfaceContainerLowest,
      period: const Duration(milliseconds: 1400),
      child: Container(
        height: height,
        width: width ?? double.infinity,
        margin: margin,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}

/// Pre-composed shimmer skeleton for a product list row.
class PGShimmerListRow extends StatelessWidget {
  const PGShimmerListRow({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(
        horizontal: AppTheme.space16,
        vertical: AppTheme.space12,
      ),
      child: Row(
        children: [
          PGShimmerBox(height: 52, width: 52, radius: 26),
          SizedBox(width: AppTheme.space16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PGShimmerBox(height: 14, width: 180),
                SizedBox(height: 6),
                PGShimmerBox(height: 12, width: 120),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Pre-composed shimmer skeleton for a card-like content block.
class PGShimmerCard extends StatelessWidget {
  final double height;

  const PGShimmerCard({super.key, this.height = 120});

  @override
  Widget build(BuildContext context) {
    return PGShimmerBox(
      height: height,
      radius: AppTheme.radiusLarge,
    );
  }
}
