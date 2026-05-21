import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_motion.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';

/// v2 progress dots — pill-extends-on-current pattern.
///
/// The active step renders as a longer pill in accent color; inactive
/// steps are thin track-colored dots. Width animates smoothly when the
/// step changes (280ms smooth curve) so the indicator feels like a
/// continuous element, not a row of separate dots.
///
/// Use for onboarding, scan flow, or any short linear sequence.
///
/// Per the v2 design plan, "animated dot progress (scale + accent fill)"
/// is one of the few moments where motion is encouraged — this lives in
/// the "delight is allowed" bucket.
class PGProgressDots extends StatelessWidget {
  final int total;
  final int current;

  /// Height of every dot/pill (also informs the radius).
  final double dotHeight;

  /// Width of an inactive dot.
  final double inactiveWidth;

  /// Width of the active pill.
  final double activeWidth;

  /// Gap between adjacent dots.
  final double spacing;

  const PGProgressDots({
    super.key,
    required this.total,
    required this.current,
    this.dotHeight = 6,
    this.inactiveWidth = 6,
    this.activeWidth = 28,
    this.spacing = V2Spacing.space8,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(total, (i) {
        final isCurrent = i == current;
        final isPast = i < current;
        return Padding(
          padding: EdgeInsetsDirectional.only(
            end: i == total - 1 ? 0 : spacing,
          ),
          child: AnimatedContainer(
            duration: V2Motion.base,
            curve: V2Motion.smooth,
            width: isCurrent ? activeWidth : inactiveWidth,
            height: dotHeight,
            decoration: BoxDecoration(
              color: isCurrent
                  ? V2Colors.accent
                  : (isPast
                      ? V2Colors.accent.withValues(alpha: 0.35)
                      : V2Colors.outline),
              borderRadius: BorderRadius.circular(dotHeight / 2),
            ),
          ),
        );
      }),
    );
  }
}
