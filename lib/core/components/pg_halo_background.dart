import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';

/// Halo background — soft radial gradient accent.
///
/// Per the v2 plan, halos belong on hero sections ONLY. Never behind
/// dense medical content (it competes with readability). One halo per
/// viewport section.
///
/// Default behavior: 4% accent at the [origin] fading to fully
/// transparent. Static — never animate the gradient itself (perf
/// guardrail).
class PGHaloBackground extends StatelessWidget {
  /// Where the halo center sits, in fractional coordinates of the
  /// painted box. Defaults to the top center.
  final Alignment origin;

  /// Halo radius as a fraction of the box's shorter side. Default 0.7
  /// fills most of the box but leaves a calm edge.
  final double radius;

  /// Maximum accent opacity at the halo center. Default 0.04 (very low).
  final double intensity;

  /// Optional accent override.
  final Color? color;

  final Widget? child;

  const PGHaloBackground({
    super.key,
    this.origin = const Alignment(0, -0.6),
    this.radius = 0.85,
    this.intensity = 0.04,
    this.color,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final tint = (color ?? V2Colors.accent).withValues(alpha: intensity);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: origin,
          radius: radius,
          colors: [tint, tint.withValues(alpha: 0.0)],
          stops: const [0.0, 1.0],
        ),
      ),
      child: child,
    );
  }
}
