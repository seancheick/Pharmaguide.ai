import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_eyebrow.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_motion.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

/// Supplement Facts label image — a first-class trust surface.
///
/// Per UX research cited in the v2 plan: supplement shoppers expect
/// visible Supplement Facts imagery; burying it makes users assume the
/// info is missing. Treat label image with the same care as the hero
/// bottle photo.
///
/// States:
/// - [imageUrl] present → cached network image, tap to view fullscreen
/// - [imageUrl] null → designed placeholder ("Label not yet available")
///
/// **Never** show a broken-image icon or blank box.
class PGLabelImage extends StatelessWidget {
  final String? imageUrl;

  /// Aspect ratio of the label image card. Default 4:5 (portrait-leaning),
  /// matching how supplement labels usually photograph.
  final double aspectRatio;

  /// Tap handler. Wire to a fullscreen viewer route.
  final VoidCallback? onTap;

  const PGLabelImage({
    super.key,
    this.imageUrl,
    this.aspectRatio = 4 / 5,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final missing = imageUrl == null || imageUrl!.isEmpty;
    final card = AspectRatio(
      aspectRatio: aspectRatio,
      child: Container(
        decoration: BoxDecoration(
          color: V2Colors.surface,
          borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
          border: Border.all(color: V2Colors.outline),
        ),
        clipBehavior: Clip.antiAlias,
        child: missing
            ? const _MissingLabelPlaceholder()
            : Image.network(
                imageUrl!,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return const _LoadingShimmer();
                },
                errorBuilder: (_, __, ___) => const _MissingLabelPlaceholder(),
              ),
      ),
    );

    if (onTap == null || missing) return card;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        child: card,
      ),
    );
  }
}

class _MissingLabelPlaceholder extends StatelessWidget {
  const _MissingLabelPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: V2Colors.surface,
      padding: const EdgeInsets.all(V2Spacing.space16),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.description_outlined,
            size: 32,
            color: V2Colors.fgMuted.withValues(alpha: 0.5),
          ),
          const SizedBox(height: V2Spacing.space12),
          const PGEyebrow(
            'Label not yet available',
            color: V2Colors.fgMuted,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: V2Spacing.space4),
          Text(
            'We add Supplement Facts photos as manufacturers publish them.',
            style: V2Typography.bodySm(color: V2Colors.fgMuted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _LoadingShimmer extends StatefulWidget {
  const _LoadingShimmer();

  @override
  State<_LoadingShimmer> createState() => _LoadingShimmerState();
}

class _LoadingShimmerState extends State<_LoadingShimmer>
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
        final alpha = (0.05 + (_controller.value * 0.05)).clamp(0.0, 1.0);
        return Container(color: V2Colors.fg.withValues(alpha: alpha));
      },
    );
  }
}
