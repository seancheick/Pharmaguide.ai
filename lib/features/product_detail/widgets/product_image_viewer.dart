// Fullscreen product-image viewer.
//
// Spec: INITIATIVE_PRODUCT_DETAIL_CLEANUP.md, Sprint S2.1, T1.
//
// Tap-to-zoom modal launched from the product detail header. Uses the
// same `product-$dsldId` Hero tag as the carousel→detail flight, so
// the image lifts smoothly from the 96pt thumbnail into the fullscreen
// viewer. InteractiveViewer handles pinch-zoom + pan once the flight
// completes. Black backdrop + X close button match the App Store /
// Apple Photos image-viewer convention.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class ProductImageViewer extends StatelessWidget {
  /// The resolved image URL — must be non-null. Callers should only
  /// open this viewer once a real image has resolved (placeholder taps
  /// are inert by design — see [ProductImage.onTap]).
  final String imageUrl;

  /// Hero tag to match against the source thumbnail. Convention is
  /// `product-$dsldId` to share with the carousel→detail flight.
  final String heroTag;

  /// Used as the close button's accessibility label so VoiceOver
  /// announces "Close, [product name]" rather than a bare "Close".
  final String productName;

  const ProductImageViewer({
    super.key,
    required this.imageUrl,
    required this.heroTag,
    required this.productName,
  });

  /// Push the viewer onto the navigator with a fade transition so the
  /// Hero flight (handled by Flutter) stays visually clean — a default
  /// slide-up would compete with the lift animation.
  static Future<void> show(
    BuildContext context, {
    required String imageUrl,
    required String heroTag,
    required String productName,
  }) {
    return Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 250),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (_, __, ___) => ProductImageViewer(
          imageUrl: imageUrl,
          heroTag: heroTag,
          productName: productName,
        ),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaPad = MediaQuery.of(context).padding;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Center the image in the available area; InteractiveViewer
          // owns the gesture surface for pinch + pan. minScale: 1.0 so
          // the image can't shrink below its natural fit; maxScale: 4.0
          // is enough to inspect a typical supplement label without
          // running into bitmap-resolution limits.
          Positioned.fill(
            child: InteractiveViewer(
              minScale: 1.0,
              maxScale: 4.0,
              child: Center(
                child: Hero(
                  tag: heroTag,
                  child: CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.contain,
                    errorWidget: (_, __, ___) => const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white54,
                      size: 64,
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Close button — top-right, inside safe area. Black scrim
          // around the icon keeps it readable on white-label products.
          Positioned(
            top: mediaPad.top + 8,
            right: 8,
            child: Material(
              color: Colors.black54,
              shape: const CircleBorder(),
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 24),
                onPressed: () => Navigator.of(context).maybePop(),
                tooltip: 'Close $productName image',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
