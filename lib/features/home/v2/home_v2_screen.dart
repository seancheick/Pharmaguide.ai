import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/components/pg_eyebrow.dart';
import 'package:pharmaguide/core/components/pg_halo_background.dart';
import 'package:pharmaguide/core/components/pg_metric_card.dart';
import 'package:pharmaguide/core/components/pg_pill_button.dart';
import 'package:pharmaguide/core/components/pg_score_line.dart';
import 'package:pharmaguide/core/components/pg_section_header.dart';
import 'package:pharmaguide/core/components/pg_transparency_footer.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_motion.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/core/widgets/pg_frosted_nav_bar.dart';

/// v2 Home — visual mirror of `home_screen.dart`.
///
/// Phase 10.0 — fixture-driven, no provider wiring. Production swap
/// (later phase) keeps the same composition; only the data adapters
/// change. Sliver order mirrors production exactly:
///
///   1. Pinned search row (simplified — full PGFrostedHeader scroll-
///      chrome behavior preserves in production, this is the visual
///      surface)
///   2. Hero greeting (eyebrow + serif greeting + tagline)
///   3. Primary Scan CTA
///   4. Stack health + last fit (PGMetricRow)
///   5. Recent scans (PGSectionHeader + 3 PGScoreLine rows)
///   6. Quick check CTA (secondary pill)
///   7. PGTransparencyFooter
///   8. Spacer for the frosted nav bar
///
/// The shell scaffold uses `extendBody: true` so content flows under
/// the nav bar — same setup as production's _AppShell.
class HomeV2Screen extends StatelessWidget {
  /// Optional handler for nav-destination taps. Gallery preview wires
  /// these to a toast or pop-to-gallery; production wires them to the
  /// real router shell.
  final ValueChanged<int>? onDestinationSelected;
  final int selectedIndex;

  const HomeV2Screen({
    super.key,
    this.selectedIndex = 0,
    this.onDestinationSelected,
  });

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: V2Colors.bg,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: V2Colors.bg,
        // `extendBody` lets the frosted nav blur pick up the scrolling
        // content behind it — mirror of the production shell.
        extendBody: true,
        body: PGHaloBackground(
          // Hero halo: centered slightly above the greeting, very low
          // intensity so it never competes with content readability.
          origin: const Alignment(0, -0.85),
          radius: 1.1,
          intensity: 0.045,
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: [
              // 1. Pinned search row.
              SliverPersistentHeader(
                pinned: true,
                delegate: _SearchHeaderDelegate(topPadding: mq.padding.top),
              ),

              // 2. Hero greeting.
              const SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  V2Spacing.space24,
                  V2Spacing.space16,
                  V2Spacing.space24,
                  0,
                ),
                sliver: SliverToBoxAdapter(child: _HeroGreeting()),
              ),

              // 3. Primary Scan CTA.
              const SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  V2Spacing.space24,
                  V2Spacing.space24,
                  V2Spacing.space24,
                  0,
                ),
                sliver: SliverToBoxAdapter(child: _ScanCta()),
              ),

              // 4. Stack health row (2-up metric cards).
              const SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  V2Spacing.space24,
                  V2Spacing.space32,
                  V2Spacing.space24,
                  0,
                ),
                sliver: SliverToBoxAdapter(child: _StackHealthRow()),
              ),

              // 5. Recent scans section.
              const SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  V2Spacing.space24,
                  V2Spacing.space32,
                  V2Spacing.space24,
                  0,
                ),
                sliver: SliverToBoxAdapter(child: _RecentScansSection()),
              ),

              // 6. Quick check CTA — secondary action.
              const SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  V2Spacing.space24,
                  V2Spacing.space24,
                  V2Spacing.space24,
                  0,
                ),
                sliver: SliverToBoxAdapter(child: _QuickCheckCta()),
              ),

              // 7. Trust footer.
              const SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  V2Spacing.space24,
                  V2Spacing.space32,
                  V2Spacing.space24,
                  V2Spacing.space8,
                ),
                sliver: SliverToBoxAdapter(
                  child: PGTransparencyFooter(
                    freshnessLabel: 'Catalog updated 3 days ago',
                  ),
                ),
              ),

              // 8. Spacer for the frosted nav bar overlap.
              SliverToBoxAdapter(
                child: SizedBox(
                  height: mq.padding.bottom + kPGNavBarHeight + V2Spacing.space8,
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: PGFrostedNavBar(
          // useV2Tones makes the bar resolve through V2Colors directly
          // — the v2 retint Sean asked for in 10.0. Production keeps
          // this false until the global theme flips.
          useV2Tones: true,
          selectedIndex: selectedIndex,
          onDestinationSelected:
              onDestinationSelected ?? (_) {},
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.qr_code_scanner_outlined),
              selectedIcon: Icon(Icons.qr_code_scanner_rounded),
              label: 'Scan',
            ),
            NavigationDestination(
              icon: Icon(Icons.layers_outlined),
              selectedIcon: Icon(Icons.layers_rounded),
              label: 'Stack',
            ),
            NavigationDestination(
              icon: Icon(Icons.auto_awesome_outlined),
              selectedIcon: Icon(Icons.auto_awesome_rounded),
              label: 'Chat',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Pinned search header — visual mirror of production's
// _PinnedSearchHeaderDelegate. Full scroll-progress chrome fading
// preserves in production; here we render the static end state.
// =============================================================================

class _SearchHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double topPadding;

  static const double _verticalPadding = 12;
  static const double _launcherHeight = 52;

  _SearchHeaderDelegate({required this.topPadding});

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
    // Simple binary: at scroll 0, transparent surface (just hairline at
    // bottom). Once scrolled, cream surface @ 95% opacity + hairline.
    // No BackdropFilter at this preview level — keeps the perf
    // guardrail count to one blur surface per viewport (the nav bar).
    final scrolled = overlapsContent;
    return AnimatedContainer(
      duration: V2Motion.base,
      curve: V2Motion.smooth,
      decoration: BoxDecoration(
        color: scrolled
            ? V2Colors.bg.withValues(alpha: 0.95)
            : Colors.transparent,
        border: Border(
          bottom: BorderSide(
            color: scrolled ? V2Colors.outline : Colors.transparent,
            width: 0.5,
          ),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.only(
          top: topPadding + _verticalPadding,
          left: V2Spacing.space24,
          right: V2Spacing.space24,
          bottom: _verticalPadding,
        ),
        child: const _SearchLauncher(),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _SearchHeaderDelegate oldDelegate) {
    return oldDelegate.topPadding != topPadding;
  }
}

class _SearchLauncher extends StatelessWidget {
  const _SearchLauncher();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: V2Colors.surface,
      borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
      child: InkWell(
        onTap: () {},
        borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: V2Spacing.space16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
            border: Border.all(color: V2Colors.outline),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.search_rounded,
                size: 20,
                color: V2Colors.fgMuted,
              ),
              const SizedBox(width: V2Spacing.space12),
              Expanded(
                child: Text(
                  'Search a supplement or medication',
                  style: V2Typography.body(color: V2Colors.fgMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(
                Icons.tune_rounded,
                size: 20,
                color: V2Colors.fgMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Hero greeting — eyebrow + serif greeting + body tagline. Fixture
// uses "Sean" — production reads `profile.nickname`.
// =============================================================================

class _HeroGreeting extends StatelessWidget {
  const _HeroGreeting();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PGEyebrow('Thursday · May 15'),
        const SizedBox(height: V2Spacing.space8),
        Text(
          'Good morning, Sean.',
          style: V2Typography.displayXs(color: V2Colors.fg),
        ),
        const SizedBox(height: V2Spacing.space8),
        Text(
          'Three scans in your stack this week. One worth a closer look.',
          style: V2Typography.body(color: V2Colors.fgMuted),
        ),
      ],
    );
  }
}

// =============================================================================
// Primary Scan CTA — the one gradient surface on the screen.
// Accent-strong → accent diagonal, scan-rounded icon, pill button vibe
// but full-width tile so it feels like the singular action.
// =============================================================================

class _ScanCta extends StatelessWidget {
  const _ScanCta();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
      child: InkWell(
        onTap: () {},
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        child: Container(
          padding: const EdgeInsets.all(V2Spacing.space24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [V2Colors.accentStrong, V2Colors.accent],
            ),
            borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
            boxShadow: V2Shadows.md,
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
                ),
                child: const Icon(
                  Icons.qr_code_scanner_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(width: V2Spacing.space16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Scan a supplement',
                      style: V2Typography.titleSm(color: Colors.white),
                    ),
                    const SizedBox(height: V2Spacing.space4),
                    Text(
                      'Get an instant PG Score + safety read',
                      style: V2Typography.bodySm(
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_rounded,
                color: Colors.white,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Stack health row — two PGMetricCards side by side.
// =============================================================================

class _StackHealthRow extends StatelessWidget {
  const _StackHealthRow();

  @override
  Widget build(BuildContext context) {
    return PGMetricRow(
      cards: [
        PGMetricCard(
          label: 'Stack health',
          value: '86',
          caption: 'out of 100',
          delta: '+4 this week',
          trend: PGMetricTrend.up,
          onTap: () {},
        ),
        PGMetricCard(
          label: 'Last fit score',
          value: '82',
          caption: 'Omega-3 · today',
          delta: 'Good match',
          onTap: () {},
        ),
      ],
    );
  }
}

// =============================================================================
// Recent scans section — section header + 3 score-line rows.
// =============================================================================

class _RecentScansSection extends StatelessWidget {
  const _RecentScansSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PGSectionHeader(
          eyebrow: 'Recent activity',
          title: 'Your last scans',
          trailing: GestureDetector(
            onTap: () {},
            child: Text(
              'View all',
              style: V2Typography.label(color: V2Colors.accent),
            ),
          ),
        ),
        const SizedBox(height: V2Spacing.space16),
        Container(
          decoration: BoxDecoration(
            color: V2Colors.surface,
            borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
            border: Border.all(color: V2Colors.outline),
            boxShadow: V2Shadows.sm,
          ),
          clipBehavior: Clip.antiAlias,
          child: const Column(
            children: [
              _RecentScanRow(
                brand: 'Nordic Naturals',
                name: 'Ultimate Omega 2X',
                score: 84,
              ),
              _RecentScanRow(
                brand: 'Thorne',
                name: 'Basic Nutrients 2/Day',
                score: 91,
              ),
              _RecentScanRow(
                brand: 'NOW Foods',
                name: 'L-Theanine 200mg',
                score: 72,
                isLast: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RecentScanRow extends StatelessWidget {
  final String brand;
  final String name;
  final int score;
  final bool isLast;

  const _RecentScanRow({
    required this.brand,
    required this.name,
    required this.score,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {},
      child: Container(
        padding: const EdgeInsets.all(V2Spacing.space16),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isLast ? Colors.transparent : V2Colors.outline,
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: V2Colors.accentTint,
                borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
              ),
              child: const Icon(
                Icons.medication_outlined,
                color: V2Colors.accent,
                size: 20,
              ),
            ),
            const SizedBox(width: V2Spacing.space12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    brand,
                    style: V2Typography.caption(color: V2Colors.fgMuted),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    name,
                    style: V2Typography.bodySm(color: V2Colors.fg).copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: V2Spacing.space4),
                  PGScoreLine(score: score, compact: true),
                ],
              ),
            ),
            const SizedBox(width: V2Spacing.space8),
            const Icon(
              Icons.chevron_right_rounded,
              color: V2Colors.fgMuted,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Quick Check CTA — secondary action. Pill button + body explanation
// in a calm bordered tile.
// =============================================================================

class _QuickCheckCta extends StatelessWidget {
  const _QuickCheckCta();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(V2Spacing.space24),
      decoration: BoxDecoration(
        color: V2Colors.surface,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        border: Border.all(color: V2Colors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PGEyebrow('Quick check'),
          const SizedBox(height: V2Spacing.space8),
          Text(
            'Type a supplement + medication to see if they conflict.',
            style: V2Typography.body(color: V2Colors.fg),
          ),
          const SizedBox(height: V2Spacing.space16),
          PGPillButton(
            label: 'Start a quick check',
            icon: Icons.bolt_outlined,
            variant: PGPillVariant.secondary,
            onPressed: () {},
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Preview wrapper for /dev/v2/home — wires nav-bar destination taps to
// toasts so reviewers can verify tap targets without leaving the
// gallery preview.
// =============================================================================

class HomeV2Preview extends StatefulWidget {
  const HomeV2Preview({super.key});

  @override
  State<HomeV2Preview> createState() => _HomeV2PreviewState();
}

class _HomeV2PreviewState extends State<HomeV2Preview> {
  int _index = 0;

  void _onTap(int i) {
    setState(() => _index = i);
    final destination = const [
      'Home',
      'Scan',
      'Stack',
      'Chat',
      'Profile',
    ][i];
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$destination tapped — preview only (Phase 10.0)'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1200),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        HomeV2Screen(
          selectedIndex: _index,
          onDestinationSelected: _onTap,
        ),
        // Floating back chip — gallery preview only.
        Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          right: 8,
          child: Material(
            color: V2Colors.surface,
            shape: const CircleBorder(),
            elevation: 0,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => context.go('/dev/v2'),
              child: const Padding(
                padding: EdgeInsets.all(V2Spacing.space8),
                child: Icon(
                  Icons.close_rounded,
                  color: V2Colors.fg,
                  size: 20,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
