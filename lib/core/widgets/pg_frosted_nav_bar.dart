import 'dart:ui';

import 'package:flutter/material.dart';

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
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: isDark ? 0.72 : 0.78),
            border: Border(
              top: BorderSide(color: scheme.outlineVariant, width: 0.5),
            ),
          ),
          child: NavigationBar(
            selectedIndex: selectedIndex,
            onDestinationSelected: onDestinationSelected,
            destinations: destinations,
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            shadowColor: Colors.transparent,
            elevation: 0,
            indicatorColor: scheme.primary.withValues(
              alpha: isDark ? 0.18 : 0.12,
            ),
          ),
        ),
      ),
    );
  }
}
