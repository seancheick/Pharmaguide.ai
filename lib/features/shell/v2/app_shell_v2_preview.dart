import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_floating_nav_bar.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/features/home/v2/home_v2_screen.dart';
import 'package:pharmaguide/features/scanner/v2/scanner_v2_preview_screen.dart';
import 'package:pharmaguide/features/settings/v2/settings_v2_screen.dart';
import 'package:pharmaguide/features/stack/v2/stack_v2_screen.dart';

/// Interactive preview of the v2 app shell with the floating pill nav.
///
/// Switches between Home / Scan / Stack / Saved / Profile as the user
/// taps the bar — so reviewers can feel the new chrome end-to-end
/// without booting the production routes.
///
/// Production swap (Phase 8): the existing `_AppShell` in `lib/app.dart`
/// will adopt this nav bar by replacing `PGFrostedNavBar` with
/// `PGFloatingNavBar`, keeping the same 5 destinations + GoRouter wiring.
class AppShellV2Preview extends StatefulWidget {
  const AppShellV2Preview({super.key});

  @override
  State<AppShellV2Preview> createState() => _AppShellV2PreviewState();
}

class _AppShellV2PreviewState extends State<AppShellV2Preview> {
  int _index = 0;

  static const _destinations = <PGNavDestination>[
    PGNavDestination(
      icon: Icons.home_outlined,
      selectedIcon: Icons.home_rounded,
      label: 'Home',
    ),
    PGNavDestination(
      icon: Icons.qr_code_scanner_rounded,
      label: 'Scan',
      raised: true,
    ),
    PGNavDestination(
      icon: Icons.layers_outlined,
      selectedIcon: Icons.layers_rounded,
      label: 'Stack',
    ),
    PGNavDestination(
      icon: Icons.bookmark_outline_rounded,
      selectedIcon: Icons.bookmark_rounded,
      label: 'Saved',
    ),
    PGNavDestination(
      icon: Icons.person_outline_rounded,
      selectedIcon: Icons.person_rounded,
      label: 'Profile',
    ),
  ];

  Widget _bodyForIndex(int i) {
    return KeyedSubtree(
      key: ValueKey('shell-tab-$i'),
      child: switch (i) {
        0 => const HomeV2Screen(),
        1 => const ScannerV2PreviewScreen(),
        2 => const StackV2Screen(),
        3 => const StackV2Screen(emptyStack: false),
        _ => const SettingsV2Screen(),
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // `extendBody: true` lets content flow under the floating pill so
      // the BackdropFilter has pixels to blur. Each screen body adds its
      // own bottom padding equal to the bar's footprint so content
      // doesn't sit underneath.
      extendBody: true,
      backgroundColor: V2Colors.bg,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: child,
        ),
        child: _bodyForIndex(_index),
      ),
      bottomNavigationBar: PGFloatingNavBar(
        currentIndex: _index,
        destinations: _destinations,
        onChanged: (i) => setState(() => _index = i),
      ),
    );
  }
}
