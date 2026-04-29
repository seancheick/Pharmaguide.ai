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
    final platform = theme.platform;
    final useGlass =
        platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;

    final target = scrollProgress.clamp(0.0, 1.0);

    // Smooth the progress so a binary scrollProgress flip (e.g. driven by
    // SliverPersistentHeader's overlapsContent) crossfades over ~200ms
    // instead of snapping. If the host already passes a smooth value, this
    // tween simply tracks it tightly; if the host passes 0/1, we get the
    // crossfade for free.
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: target),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      builder: (context, p, _) {
        // iOS/macOS use true glass. Android gets a tonal elevated surface
        // with the same rhythm but no transplanted iPhone blur treatment.
        final fillAlpha = useGlass
            ? (isDark ? 0.72 : 0.78) * p
            : (isDark ? 0.88 : 0.92) * p;
        // Hairline alpha — fades in alongside the fill.
        final hairlineAlpha = 0.6 * p;
        // Dark-mode-only top glint — a faint white inner-edge that
        // simulates light catching the top of frosted glass. iOS
        // Settings / Wallet / Music all do this in dark mode and the
        // surface looks flat without it. 4% white is enough to read as
        // refractive without crossing into "decorative". Fades with
        // scrollProgress so the edge only appears once the surface is
        // actually frosted.
        final glintAlpha = useGlass && isDark ? 0.04 * p : 0.0;

        final decorated = DecoratedBox(
          decoration: BoxDecoration(
            color: (useGlass ? scheme.surface : scheme.surfaceContainerHigh)
                .withValues(alpha: fillAlpha),
            border: Border(
              top: glintAlpha > 0
                  ? BorderSide(
                      color: Colors.white.withValues(alpha: glintAlpha),
                      width: 0.5,
                    )
                  : BorderSide.none,
              bottom: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: hairlineAlpha),
                width: 0.5,
              ),
            ),
          ),
          child: child,
        );

        if (!useGlass) {
          return decorated;
        }

        return ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: blurSigma * p,
              sigmaY: blurSigma * p,
            ),
            child: decorated,
          ),
        );
      },
    );
  }
}
