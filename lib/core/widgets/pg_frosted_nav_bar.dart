import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';

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

  const PGFrostedNavBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
    this.blurSigma = 22,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final palette = context.v2;
    final surface = palette.surface;
    final outline = palette.outline;
    final indicator = palette.accent.withValues(alpha: isDark ? 0.18 : 0.12);

    // Subtle cool tint — 8% blend of fg into surface gives the bar a
    // neutral-cool hue that contrasts noticeably against the warm cream
    // bg without looking gray.
    final tinted = Color.lerp(surface, palette.fg, isDark ? 0.0 : 0.08)!;
    final decoration = BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          // Top: more transparent so the blur of content behind shows
          // through, selling the "light passes through" feel.
          tinted.withValues(alpha: isDark ? 0.40 : 0.48),
          // Bottom: more solid so labels stay perfectly legible against
          // any content beneath.
          tinted.withValues(alpha: isDark ? 0.70 : 0.78),
        ],
      ),
      border: Border(top: BorderSide(color: outline, width: 0.5)),
    );

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: DecoratedBox(
          decoration: decoration,
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
              // 1px top highlight — the "lit edge" iOS gets when light
              // catches the top surface of glass. Bumped from 0.55 →
              // 0.85 so it actually reads on cream. Sits just under
              // the hairline outline.
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Container(
                    height: 1,
                    color: Colors.white.withValues(alpha: isDark ? 0.08 : 0.85),
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
