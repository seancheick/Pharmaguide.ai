import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';

/// Canonical nav bar total height used by [PGFrostedNavBar]. Modal bottom
/// sheets should add this to their bottom padding when the app is using
/// `extendBody: true` (the default shell setup) so content isn't hidden
/// behind the frosted bar.
///
/// Value: 68dp content area + ~34dp system home indicator ≈ 96dp total on
/// iPhone, ~76dp on Android. We use 88 as a conservative middle ground —
/// tested on iPhone 15 / Pixel 8.
const double kPGNavBarHeight = 88.0;

/// Frosted glass wrapper around Flutter's `NavigationBar` — produces the
/// Apple-like translucent blur effect that the stock `NavigationBar` can't do
/// on its own (setting `backgroundColor` with alpha just shows the scaffold
/// color through; you need a `BackdropFilter` behind it).
///
/// Use this inside a `Scaffold.bottomNavigationBar` slot, or stacked over
/// scrollable content using a `Stack` + `Positioned` at the bottom.
///
/// ```dart
/// Scaffold(
///   extendBody: true, // let content flow under the nav bar
///   bottomNavigationBar: PGFrostedNavBar(
///     selectedIndex: _index,
///     onDestinationSelected: (i) => setState(() => _index = i),
///     destinations: const [
///       NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
///       NavigationDestination(icon: Icon(Icons.search_rounded), label: 'Search'),
///       NavigationDestination(icon: Icon(Icons.bookmark_outline), label: 'Stack'),
///       NavigationDestination(icon: Icon(Icons.person_outline), label: 'Profile'),
///     ],
///   ),
/// )
/// ```
///
/// Requires `extendBody: true` on the Scaffold for the blur to pick up the
/// content scrolling behind it.
class PGFrostedNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<NavigationDestination> destinations;
  final double blurSigma;

  /// When true, resolves surface / outline / accent through [V2Colors]
  /// directly instead of the active theme's `colorScheme`. Lets v2
  /// preview routes show the v2 nav-bar tone even when the global
  /// theme is still legacy `AppTheme`. Production paths leave this
  /// false so nothing changes for the live app until Phase 8 sign-off
  /// flips `useV2Theme` globally — at which point the theme path
  /// produces the same colors and this flag becomes redundant.
  final bool useV2Tones;

  const PGFrostedNavBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
    this.blurSigma = 22,
    this.useV2Tones = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final Color surface;
    final Color outline;
    final Color indicator;
    if (useV2Tones) {
      surface = isDark ? V2Colors.surfaceDark : V2Colors.surface;
      outline = isDark ? V2Colors.outlineDark : V2Colors.outline;
      indicator = V2Colors.accent.withValues(alpha: isDark ? 0.18 : 0.12);
    } else {
      surface = scheme.surface;
      outline = scheme.outlineVariant;
      indicator = scheme.primary.withValues(alpha: isDark ? 0.18 : 0.12);
    }

    // Surface opacity tuned per useV2Tones — on the cream v2 bg the
    // legacy 0.78 opacity made the bar look like a flat surface
    // (white-on-cream had nothing to refract). 0.62 lets content
    // behind actually show through the blur and reads as real glass.
    // Production tone keeps 0.78 so the legacy app is untouched.
    final surfaceAlpha = useV2Tones
        ? (isDark ? 0.56 : 0.62)
        : (isDark ? 0.72 : 0.78);

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: surface.withValues(alpha: surfaceAlpha),
            border: Border(
              top: BorderSide(color: outline, width: 0.5),
            ),
          ),
          child: Stack(
            children: [
              NavigationBar(
                selectedIndex: selectedIndex,
                onDestinationSelected: onDestinationSelected,
                destinations: destinations,
                backgroundColor: Colors.transparent,
                surfaceTintColor: Colors.transparent,
                shadowColor: Colors.transparent,
                elevation: 0,
                indicatorColor: indicator,
              ),
              // 1px top highlight — sits just below the hairline outline,
              // gives the "lit edge" feel that real glass has when light
              // catches the top surface (iOS pattern). Only rendered for
              // the v2 tone so legacy production paths stay unchanged.
              if (useV2Tones)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Container(
                      height: 1,
                      color: (isDark ? Colors.white : Colors.white)
                          .withValues(alpha: isDark ? 0.04 : 0.55),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
