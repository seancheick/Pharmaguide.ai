import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_haptics.dart';
import 'package:pharmaguide/core/widgets/pg_frosted_header.dart';
import 'package:pharmaguide/core/widgets/pg_frosted_nav_bar.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/home/widgets/home_citation_strip.dart';
import 'package:pharmaguide/features/home/widgets/home_hero_section.dart';
import 'package:pharmaguide/features/home/widgets/home_profile_completeness_card.dart';
import 'package:pharmaguide/features/home/widgets/home_quick_check_cta.dart';
import 'package:pharmaguide/features/home/widgets/home_recent_scans.dart';
import 'package:pharmaguide/features/home/widgets/home_scan_cta.dart';
import 'package:pharmaguide/features/home/widgets/home_search_launcher.dart';
import 'package:pharmaguide/features/home/widgets/home_stack_health.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';
import 'package:pharmaguide/features/stack/providers/stack_providers.dart';

/// True when the user has no scans AND no stack — first-launch state. Drives
/// the collapsed home variant. Re-evaluates whenever [activeStackProvider]
/// emits or is invalidated, so adding the first stack item / first scan
/// flips home into the expanded variant on the next frame.
///
/// Exposed for testing because reactivity is part of the contract: a
/// regression to `ref.read` here would silently leave first-launch users
/// stuck in collapsed mode after their first scan — exactly the moment
/// expanded mode matters most.
@visibleForTesting
final isFirstLaunchHomeProvider = FutureProvider.autoDispose<bool>((ref) async {
  // ref.watch — not ref.read — so this provider re-fires when activeStack
  // is invalidated (which StackActions does on every add/remove).
  final stack = await ref.watch(activeStackProvider.future);
  if (stack.isNotEmpty) return false;
  final userDb = ref.watch(userDatabaseProvider);
  final scans = await userDb.getRecentScans(limit: 1);
  return scans.isEmpty;
});

/// Invalidate the home-specific providers that depend on user activity.
///
/// Used when a new scan lands or when the user explicitly pulls to refresh.
/// This keeps first-launch mode and Recents in sync without waiting for a
/// full route rebuild.
void refreshHomeSurface(WidgetRef ref) {
  ref.invalidate(isFirstLaunchHomeProvider);
  refreshHomeRecents(ref);
}

/// The home screen.
///
/// Editorial-premium composition: hero greeting → scan CTA → search →
/// personal state → recents → utilities → trust. Each section has its own
/// spacing rhythm; nothing is on a uniform 16/16/16 grid.
///
/// Every visual section is a dedicated widget under `widgets/` so the shell
/// below stays a thin layout composition — re-ordering sections or swapping
/// one out is a one-line change here.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final firstLaunchAsync = ref.watch(isFirstLaunchHomeProvider);
    final mq = MediaQuery.of(context);
    final theme = Theme.of(context);
    final isFirstLaunch = firstLaunchAsync.asData?.value == true;
    final showExpandedSections = firstLaunchAsync.asData?.value == false;

    // Status-bar text/icon contrast — dark icons on light theme, light icons
    // on dark theme. Without AnnotatedRegion the system icons can read as
    // illegible against the page background, especially after the user
    // scrolls and the frosted search header changes the visual material
    // beneath the status bar.
    final overlayStyle = theme.brightness == Brightness.dark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;

    final scrollView = CustomScrollView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        // Pull-to-refresh on iOS (CupertinoSliverRefreshControl is iOS-only —
        // sliver lives at the very top so the rubber-band drag reveals it).
        // Android branch wraps the entire scroll view in RefreshIndicator
        // below; the two paths are mutually exclusive.
        if (Platform.isIOS)
          CupertinoSliverRefreshControl(onRefresh: () => _onHomeRefresh(ref)),

        // ----------------------------------------------------------------
        // Search launcher — pinned scroll-aware system surface.
        //
        // First content sliver, with the status-bar inset baked into the
        // delegate so the launcher renders below the notch / Dynamic Island.
        // At scroll offset 0 the surrounding chrome is fully transparent
        // (looks like page material). Once content scrolls past below,
        // PGFrostedHeader inside the delegate fades in a translucent
        // surface + bottom hairline — Settings / Mail / App Store top-
        // chrome pattern.
        // ----------------------------------------------------------------
        SliverPersistentHeader(
          pinned: true,
          delegate: _PinnedSearchHeaderDelegate(topPadding: mq.padding.top),
        ),

        // ----------------------------------------------------------------
        // Hero — date pill, greeting, tagline. Sits below the pinned
        // search and scrolls away naturally on user scroll.
        // ----------------------------------------------------------------
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppTheme.space20,
            AppTheme.space12,
            AppTheme.space20,
            0,
          ),
          sliver: SliverToBoxAdapter(
            child: HomeHeroSection(nickname: profile.nickname),
          ),
        ),

        // ----------------------------------------------------------------
        // Primary CTA — scan. The single most important action on this
        // screen, so it gets the only gradient surface in the whole app.
        // ----------------------------------------------------------------
        const SliverPadding(
          padding: EdgeInsets.fromLTRB(
            AppTheme.space20,
            AppTheme.space20,
            AppTheme.space20,
            0,
          ),
          sliver: SliverToBoxAdapter(child: HomeScanCta()),
        ),

        if (isFirstLaunch)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.space20,
              AppTheme.space16,
              AppTheme.space20,
              0,
            ),
            sliver: SliverToBoxAdapter(
              child: Text(
                'Check supplement quality, safety, and fit in seconds.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ),
          ),

        // ----------------------------------------------------------------
        // Profile completeness (conditional, highlighted card)
        // ----------------------------------------------------------------
        if (showExpandedSections && profile.completeness < 60)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.space20,
              AppTheme.space16,
              AppTheme.space20,
              0,
            ),
            sliver: SliverToBoxAdapter(
              child: HomeProfileCompletenessCard(
                completeness: profile.completeness,
              ),
            ),
          ),

        // Stack health — premium Oura-style card
        // ----------------------------------------------------------------
        if (showExpandedSections) ...[
          const SliverPadding(
            padding: EdgeInsets.fromLTRB(
              AppTheme.space20,
              AppTheme.space32,
              AppTheme.space20,
              0,
            ),
            sliver: SliverToBoxAdapter(child: HomeStackHealthWidget()),
          ),
          const SliverPadding(
            padding: EdgeInsets.fromLTRB(
              AppTheme.space20,
              AppTheme.space24,
              AppTheme.space20,
              0,
            ),
            sliver: SliverToBoxAdapter(child: HomeRecentScansSection()),
          ),
        ],

        // ----------------------------------------------------------------
        // Quick Check CTA — useful, but secondary to scan/search/stack.
        // ----------------------------------------------------------------
        if (showExpandedSections)
          const SliverPadding(
            padding: EdgeInsets.fromLTRB(
              AppTheme.space20,
              AppTheme.space32,
              AppTheme.space20,
              0,
            ),
            sliver: SliverToBoxAdapter(child: HomeQuickCheckCta()),
          ),

        // ----------------------------------------------------------------
        // Trust footer — sources, updated date, disclaimer
        // ----------------------------------------------------------------
        const SliverPadding(
          padding: EdgeInsets.fromLTRB(
            AppTheme.space20,
            AppTheme.space32,
            AppTheme.space20,
            AppTheme.space8,
          ),
          sliver: SliverToBoxAdapter(child: HomeCitationStrip()),
        ),

        // Bottom space for frosted nav bar + safe area
        SliverToBoxAdapter(
          child: SizedBox(
            height: mq.padding.bottom + kPGNavBarHeight + AppTheme.space8,
          ),
        ),
      ],
    );

    // Android: pull-to-refresh comes from a Material RefreshIndicator that
    // wraps the whole scroll view (CupertinoSliverRefreshControl is
    // iOS-only and would render incorrectly on Android).
    final body = Platform.isIOS
        ? scrollView
        : RefreshIndicator(
            onRefresh: () => _onHomeRefresh(ref),
            child: scrollView,
          );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Scaffold(body: body),
    );
  }
}

/// Refresh handler — fires a light haptic, invalidates the home-relevant
/// providers, and waits a short beat so the indicator animation feels
/// purposeful rather than a flicker. Shared by the iOS sliver-refresh
/// control and the Android Material refresh indicator.
Future<void> _onHomeRefresh(WidgetRef ref) async {
  unawaited(PGHaptics.tap());
  ref.invalidate(activeStackProvider);
  refreshHomeSurface(ref);
  await Future<void>.delayed(const Duration(milliseconds: 350));
}

/// Pinned-search header delegate.
///
/// Renders [HomeSearchLauncher] inside a [PGFrostedHeader] whose
/// scroll-progress is driven by `overlapsContent`: 0 while the search is
/// floating in its natural inline position, 1 once the user has scrolled
/// past it and content is now sliding underneath. PGFrostedHeader
/// internally crossfades over ~220ms so the binary flip reads as a smooth
/// material transition (App Store / Settings pattern).
///
/// [maxExtent] equals [minExtent] — no shrink-on-pin behavior. The search
/// stays its natural height, only the surrounding chrome fades.
class _PinnedSearchHeaderDelegate extends SliverPersistentHeaderDelegate {
  /// System status-bar inset; we draw inside this padding so the search
  /// field never sits underneath the notch / Dynamic Island.
  final double topPadding;

  /// Fixed total height of the header zone: status-bar inset + vertical
  /// padding above and below the launcher + the launcher itself
  /// (≈ 52pt). Tuned to match the prior inline rhythm.
  static const double _verticalPadding = 12;
  static const double _launcherHeight = 52;

  _PinnedSearchHeaderDelegate({required this.topPadding});

  double get _height => topPadding + _verticalPadding * 2 + _launcherHeight;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return PGFrostedHeader(
      // Binary signal — TweenAnimationBuilder inside PGFrostedHeader
      // smooths the flip into a 220ms crossfade.
      scrollProgress: overlapsContent ? 1.0 : 0.0,
      child: Padding(
        padding: EdgeInsets.only(
          top: topPadding + _verticalPadding,
          left: AppTheme.space20,
          right: AppTheme.space20,
          bottom: _verticalPadding,
        ),
        child: const HomeSearchLauncher(),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _PinnedSearchHeaderDelegate oldDelegate) {
    return oldDelegate.topPadding != topPadding;
  }
}
