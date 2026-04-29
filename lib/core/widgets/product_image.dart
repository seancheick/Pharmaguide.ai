import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/branded_placeholder.dart';
import 'package:pharmaguide/services/product_image_resolver.dart';

/// Orchestrating widget that displays a real product photo when available
/// (via Open Food Facts) or falls back to a [BrandedPlaceholder].
///
/// Never blocks on loading — shows the placeholder immediately while the
/// OFF lookup runs in the background, then swaps in the real image.
class ProductImage extends ConsumerWidget {
  final String dsldId;
  final String? upc;
  final String productName;
  final String brandName;
  final String? formFactor;
  final double? score;
  final double size;

  /// When true, force the placeholder's compact (single colored square
  /// with initial) layout regardless of [size]. Pass-through to
  /// [BrandedPlaceholder.compact] — see that widget for the rationale.
  /// Use this in hero contexts at 96pt+ where the default multi-row
  /// "full card" placeholder layout overflows the 1:1 box.
  final bool compact;

  const ProductImage({
    super.key,
    required this.dsldId,
    this.upc,
    required this.productName,
    required this.brandName,
    this.formFactor,
    this.score,
    this.size = 52,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final imageAsync = ref.watch(
      _productImageProvider((dsldId: dsldId, upc: upc)),
    );

    // Build placeholder once per frame — avoids allocating on every
    // .when() branch and CachedNetworkImage callback.
    final placeholder = BrandedPlaceholder(
      productName: productName,
      brand: brandName,
      formFactor: formFactor,
      score: score,
      size: size,
      compact: compact,
    );

    return imageAsync.when(
      loading: () => placeholder,
      error: (_, __) => placeholder,
      data: (imageUrl) {
        if (imageUrl == null) return placeholder;
        return ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          child: CachedNetworkImage(
            imageUrl: imageUrl,
            width: size,
            height: size,
            fit: BoxFit.cover,
            placeholder: (_, __) => placeholder,
            errorWidget: (_, __, ___) => placeholder,
          ),
        );
      },
    );
  }
}

/// Parameter record for the family provider.
typedef _ImageParams = ({String dsldId, String? upc});

/// Resolves product image URL via cache → OFF API → null.
final _productImageProvider = FutureProvider.family
    .autoDispose<String?, _ImageParams>((ref, params) async {
      final resolver = ref.read(productImageResolverProvider);
      return resolver.resolve(params.dsldId, params.upc);
    });
