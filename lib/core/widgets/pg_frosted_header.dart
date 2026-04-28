import 'dart:ui';

import 'package:flutter/material.dart';

/// Frosted-glass header surface that sits above scrollable content.
///
/// Visually quiet at [scrollProgress] 0 (transparent, no hairline) and
/// turns frosted with a bottom hairline once content has scrolled
/// underneath. The host widget computes the progress from a
/// `ScrollController` and passes it in — typically:
///
/// ```dart
/// scrollProgress = (offset / heroFadeOutDistance).clamp(0.0, 1.0)
/// ```
///
/// where `heroFadeOutDistance` is the height of the hero zone that the
/// search should remain transparent over.
///
/// Mounts inside a `Stack > Positioned(top: 0)` over the page content,
/// or inside a `SliverPersistentHeader` for sliver-mounted layouts.
///
/// Companion to [`PGFrostedNavBar`] — same blur recipe (BackdropFilter +
/// translucent surface fill), same dark/light alpha curves. Together
/// they produce the iOS top-and-bottom translucent chrome that App
/// Store, Settings, and Mail use.
class PGFrostedHeader extends StatelessWidget {
  /// The contents of the header — typically a search field or app-bar
  /// row sitting inside a [SafeArea].
  final Widget child;

  /// Progress from 0..1. 0 = no scroll yet (transparent passthrough), 1
  /// = content scrolled past the hero (full frosted surface + hairline).
  /// Values outside the range are clamped.
  final double scrollProgress;

  /// Gaussian blur sigma applied to the content underneath the header.
  /// 30 is the iOS-equivalent intensity. PGFrostedNavBar uses 22 (a hair
  /// lighter for the bottom chrome which sits below thumb-glance area).
  final double blurSigma;

  const PGFrostedHeader({
    super.key,
    required this.child,
    required this.scrollProgress,
    this.blurSigma = 30,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final p = scrollProgress.clamp(0.0, 1.0);

    // Surface fill alpha — peak 0.78 (light) / 0.72 (dark), matching the
    // PGFrostedNavBar curve. At progress 0 the fill is transparent so
    // the header is visually invisible; at progress 1 the fill reaches
    // peak opacity and reads as a clear frosted surface.
    final fillAlpha = (isDark ? 0.72 : 0.78) * p;

    // Hairline alpha — fades in alongside the fill so the bottom edge
    // appears only once content is actually underneath the header.
    final hairlineAlpha = 0.6 * p;

    return ClipRect(
      child: BackdropFilter(
        // Blur scales smoothly from 0 to full intensity. ImageFilter.blur
        // with sigma 0 is a no-op (passthrough), so this is fine to mount
        // even when the header should be visually inert.
        filter: ImageFilter.blur(
          sigmaX: blurSigma * p,
          sigmaY: blurSigma * p,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: fillAlpha),
            border: Border(
              bottom: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: hairlineAlpha),
                width: 0.5,
              ),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
