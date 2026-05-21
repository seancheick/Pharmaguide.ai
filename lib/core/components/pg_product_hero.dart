import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_eyebrow.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_motion.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

/// Hero product card — image + structured metadata.
///
/// Defined frame, never floats. Image box ratio defaults to 1:1 (square)
/// which works for bottle fronts AND for fullscreen tap-to-zoom label
/// viewing. Override to 4:5 if the layout prefers a more portrait crop.
///
/// Long-name handling: title wraps to up to 3 lines (Geist Sans, never
/// serif — the audit's "clinical content stays sans" rule applies here
/// because product names ARE clinical context). No ellipsis on important
/// names. If still too long, degrades **one size tier** (title → titleSm)
/// before constraining lines.
class PGProductHero extends StatelessWidget {
  final String productName;
  final String brand;
  final String? form;
  final String? servingSize;
  final String? imageUrl;
  final double imageAspectRatio;

  /// Tap handler for the image — wire to fullscreen viewer.
  final VoidCallback? onImageTap;

  const PGProductHero({
    super.key,
    required this.productName,
    required this.brand,
    this.form,
    this.servingSize,
    this.imageUrl,
    this.imageAspectRatio = 1,
    this.onImageTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasMetaRow = form != null || servingSize != null;
    final longName = productName.length > 40;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Image card — defined frame, soft shadow, never floats.
        _HeroImageFrame(
          imageUrl: imageUrl,
          aspectRatio: imageAspectRatio,
          onTap: onImageTap,
        ),
        const SizedBox(height: V2Spacing.space16),
        // Brand eyebrow.
        PGEyebrow(brand),
        const SizedBox(height: V2Spacing.space8),
        // Product name — Geist Sans, graceful degradation for long names.
        Text(
          productName,
          style: (longName
                  ? V2Typography.titleSm(color: V2Colors.fg)
                  : V2Typography.title(color: V2Colors.fg))
              .copyWith(height: 1.2),
          maxLines: 3,
          softWrap: true,
        ),
        if (hasMetaRow) ...[
          const SizedBox(height: V2Spacing.space12),
          Wrap(
            spacing: V2Spacing.space16,
            runSpacing: V2Spacing.space4,
            children: [
              if (form != null)
                _MetaPair(label: 'Form', value: form!),
              if (servingSize != null)
                _MetaPair(label: 'Serving', value: servingSize!),
            ],
          ),
        ],
      ],
    );
  }
}

class _MetaPair extends StatelessWidget {
  final String label;
  final String value;
  const _MetaPair({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PGEyebrow(label, color: V2Colors.fgMuted),
        const SizedBox(height: V2Spacing.space4),
        Text(value, style: V2Typography.body(color: V2Colors.fg)),
      ],
    );
  }
}

class _HeroImageFrame extends StatelessWidget {
  final String? imageUrl;
  final double aspectRatio;
  final VoidCallback? onTap;

  const _HeroImageFrame({
    required this.imageUrl,
    required this.aspectRatio,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final missing = imageUrl == null || imageUrl!.isEmpty;
    final frame = RepaintBoundary(
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: Container(
          decoration: BoxDecoration(
            color: V2Colors.surface,
            borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
            border: Border.all(color: V2Colors.outline),
            boxShadow: V2Shadows.sm,
          ),
          clipBehavior: Clip.antiAlias,
          child: missing
              ? const _MissingProductPlaceholder()
              : Image.network(
                  imageUrl!,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, progress) =>
                      progress == null ? child : const _ShimmerFill(),
                  errorBuilder: (_, __, ___) =>
                      const _MissingProductPlaceholder(),
                ),
        ),
      ),
    );

    if (onTap == null || missing) return frame;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        child: frame,
      ),
    );
  }
}

class _MissingProductPlaceholder extends StatelessWidget {
  const _MissingProductPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: V2Colors.surface,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(V2Spacing.space24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.medication_outlined,
            size: 40,
            color: V2Colors.fgMuted.withValues(alpha: 0.5),
          ),
          const SizedBox(height: V2Spacing.space12),
          const PGEyebrow(
            'Image not yet available',
            color: V2Colors.fgMuted,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ShimmerFill extends StatefulWidget {
  const _ShimmerFill();

  @override
  State<_ShimmerFill> createState() => _ShimmerFillState();
}

class _ShimmerFillState extends State<_ShimmerFill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: V2Motion.slower,
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final alpha = (0.04 + _controller.value * 0.04).clamp(0.0, 1.0);
        return Container(color: V2Colors.fg.withValues(alpha: alpha));
      },
    );
  }
}
