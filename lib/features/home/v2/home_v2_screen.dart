import 'dart:io' show Platform;

import 'package:flutter/cupertino.dart';
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
              // 0. iOS pull-to-refresh sliver.
              if (Platform.isIOS)
                const CupertinoSliverRefreshControl(),

              // 1. Search row — non-pinned for the visual mirror. The
              // production scroll-chrome-fading behavior (where
              // PGFrostedHeader fades in once content scrolls past)
              // re-wires in the Phase-8 sweep; the custom delegate
              // here was throwing SliverGeometry layout errors on
              // certain heights, so we dropped it for stability. The
              // search row scrolls away naturally with the content
              // instead of pinning.
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(
                    top: mq.padding.top + V2Spacing.space12,
                    left: V2Spacing.space24,
                    right: V2Spacing.space24,
                    bottom: V2Spacing.space12,
                  ),
                  child: const _SearchLauncher(),
                ),
              ),

              // 1.5. Quick-filter category chips. Horizontal scrollable
              // row that scrolls away naturally with the page (not
              // pinned) — keeps the search header lean while still
              // giving instant triage entry to the top categories.
              const SliverToBoxAdapter(child: _CategoryChipsRow()),

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

              // 5. Suggested next — a single recommendation card based
              // on the user's stack + goals. Driven by the production
              // recommender in a later wiring pass; fixture surfaces
              // it here so reviewers can see the slot.
              const SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  V2Spacing.space24,
                  V2Spacing.space32,
                  V2Spacing.space24,
                  0,
                ),
                sliver: SliverToBoxAdapter(child: _SuggestedNextCard()),
              ),

              // 6. Recent scans section.
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
          // v2 order: Home / Stack / Scan / Chat / Profile.
          // Scan sits at the centerpoint (index 2 of 5) — visual anchor
          // for the primary action since we no longer ship a floating
          // scan pill. Production AppShell keeps its legacy order
          // until the Phase-8 wiring sweep flips it globally.
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.layers_outlined),
              selectedIcon: Icon(Icons.layers_rounded),
              label: 'Stack',
            ),
            NavigationDestination(
              icon: Icon(Icons.qr_code_scanner_outlined),
              selectedIcon: Icon(Icons.qr_code_scanner_rounded),
              label: 'Scan',
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
// Search launcher row. Non-pinned in the visual mirror — the
// production scroll-chrome-fading rewires in the Phase-8 sweep.
// =============================================================================

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
        // Top row: date eyebrow + profile avatar chip on the right.
        // Avatar opens the profile tab — quick affordance for editing
        // goals / nickname / health context without diving through
        // settings.
        Row(
          children: [
            const Expanded(child: PGEyebrow('Thursday · May 15')),
            _ProfileAvatar(initials: 'S', onTap: () {}),
          ],
        ),
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
        const SizedBox(height: V2Spacing.space12),
        // Engagement stat capsule — small, factual. Production wiring
        // pulls the streak/count from user_data.db; here we surface
        // fixture values to show the slot exists. Mono caps keep it
        // squarely in the metadata register, not promotional.
        const _StatCapsule(
          icon: Icons.local_fire_department_outlined,
          label: 'DAY 7 SCAN STREAK',
        ),
      ],
    );
  }
}

/// Small circular avatar chip — initials on accent-tint, hairline
/// outline. Tappable for quick profile entry.
class _ProfileAvatar extends StatelessWidget {
  final String initials;
  final VoidCallback onTap;

  const _ProfileAvatar({required this.initials, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: V2Colors.accentTint,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: V2Colors.accent.withValues(alpha: 0.25),
              width: 0.7,
            ),
          ),
          child: Text(
            initials,
            style: V2Typography.label(color: V2Colors.accent),
          ),
        ),
      ),
    );
  }
}

/// Mono-caps capsule used for the hero stat callout (scan streak,
/// goal progress, etc.). Outline-only — never tinted heavily, never
/// promotional.
class _StatCapsule extends StatelessWidget {
  final IconData icon;
  final String label;

  const _StatCapsule({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: V2Spacing.space12,
        vertical: V2Spacing.space4,
      ),
      decoration: BoxDecoration(
        color: V2Colors.surface,
        borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
        border: Border.all(color: V2Colors.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: V2Colors.accent),
          const SizedBox(width: V2Spacing.space8),
          Text(
            label,
            style: V2Typography.overline(color: V2Colors.fgMuted),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Primary Scan CTA — the one gradient surface on the screen.
// Accent-strong → accent diagonal, scan-rounded icon, pill button vibe
// but full-width tile so it feels like the singular action.
// =============================================================================

// =============================================================================
// Category quick-filter chips. Horizontal scrollable row of accent-
// tinted pills that route to the search screen pre-filtered by
// category. Scrolls naturally with the page (not pinned).
// =============================================================================

class _CategoryChipsRow extends StatelessWidget {
  const _CategoryChipsRow();

  static const _categories = <(IconData, String)>[
    (Icons.spa_outlined, 'Multivitamin'),
    (Icons.water_drop_outlined, 'Omega'),
    (Icons.bedtime_outlined, 'Sleep'),
    (Icons.fitness_center_outlined, 'Energy'),
    (Icons.shield_outlined, 'Immune'),
    (Icons.psychology_outlined, 'Focus'),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(
          V2Spacing.space24,
          V2Spacing.space12,
          V2Spacing.space24,
          V2Spacing.space4,
        ),
        itemCount: _categories.length,
        separatorBuilder: (_, __) =>
            const SizedBox(width: V2Spacing.space8),
        itemBuilder: (context, i) {
          final (icon, label) = _categories[i];
          return _CategoryChip(icon: icon, label: label, onTap: () {});
        },
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: V2Colors.surface,
      borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: V2Spacing.space16,
            vertical: V2Spacing.space8,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
            border: Border.all(color: V2Colors.outline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: V2Colors.accent),
              const SizedBox(width: V2Spacing.space8),
              Text(
                label,
                style: V2Typography.label(color: V2Colors.fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Suggested next — a single "based on your stack + goals" card that
// drives discovery without feeling promotional. Production will wire
// the actual recommender; fixture surfaces the slot.
// =============================================================================

class _SuggestedNextCard extends StatelessWidget {
  const _SuggestedNextCard();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PGEyebrow('Suggested next'),
        const SizedBox(height: V2Spacing.space12),
        Material(
          color: V2Colors.surface,
          borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
          child: InkWell(
            onTap: () {},
            borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
            child: Container(
              padding: const EdgeInsets.all(V2Spacing.space16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
                border: Border.all(color: V2Colors.outline),
                boxShadow: V2Shadows.sm,
              ),
              child: Row(
                children: [
                  // Thumbnail placeholder (production: ProductImage).
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: V2Colors.accentTint,
                      borderRadius:
                          BorderRadius.circular(V2Spacing.radiusCard),
                    ),
                    child: const Icon(
                      Icons.medication_outlined,
                      color: V2Colors.accent,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: V2Spacing.space16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Thorne',
                          style:
                              V2Typography.caption(color: V2Colors.fgMuted),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Magnesium Bisglycinate',
                          style: V2Typography.bodySm(color: V2Colors.fg)
                              .copyWith(fontWeight: FontWeight.w500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: V2Spacing.space4),
                        Text(
                          'Pairs with your sleep goal · scored 91',
                          style:
                              V2Typography.bodySm(color: V2Colors.fgMuted),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
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
          ),
        ),
      ],
    );
  }
}

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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top row: "last scan" pill — gives the CTA a tiny data
              // detail signal ("you came back 2h after your last scan")
              // without competing with the primary action below.
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: V2Spacing.space8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius:
                          BorderRadius.circular(V2Spacing.radiusPill),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.access_time_rounded,
                          size: 12,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'LAST SCAN · 2H AGO',
                          style: V2Typography.overline(
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: V2Spacing.space16),
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius:
                          BorderRadius.circular(V2Spacing.radiusCard),
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
                timestamp: 'Today, 2:14 PM',
              ),
              _RecentScanRow(
                brand: 'Thorne',
                name: 'Basic Nutrients 2/Day',
                score: 91,
                timestamp: 'Yesterday',
              ),
              _RecentScanRow(
                brand: 'NOW Foods',
                name: 'L-Theanine 200mg',
                score: 72,
                timestamp: 'Mon',
              ),
              _RecentScanRow(
                brand: 'Pure Encapsulations',
                name: 'Magnesium Glycinate',
                score: 88,
                timestamp: 'Sun',
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
  final String timestamp;
  final bool isLast;

  const _RecentScanRow({
    required this.brand,
    required this.name,
    required this.score,
    required this.timestamp,
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
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          brand,
                          style:
                              V2Typography.caption(color: V2Colors.fgMuted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: V2Spacing.space8),
                      Text(
                        timestamp,
                        style:
                            V2Typography.caption(color: V2Colors.fgSubtle),
                      ),
                    ],
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
            'Cross-check two things you\'re taking — without scanning '
            'either one.',
            style: V2Typography.body(color: V2Colors.fg),
          ),
          const SizedBox(height: V2Spacing.space12),
          // Example chip — anchors the action with a concrete pairing
          // so users see what "quick check" actually does at a glance.
          // Tap routes to the quick-check screen pre-filled.
          Wrap(
            spacing: V2Spacing.space8,
            runSpacing: V2Spacing.space8,
            children: [
              _ExamplePairChip(
                label: 'Omega-3 · Warfarin',
                onTap: () {},
              ),
              _ExamplePairChip(
                label: 'Vitamin K · Blood thinner',
                onTap: () {},
              ),
            ],
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

class _ExamplePairChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _ExamplePairChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: V2Colors.accentTint,
      borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: V2Spacing.space12,
            vertical: V2Spacing.space4,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
            border: Border.all(
              color: V2Colors.accent.withValues(alpha: 0.22),
              width: 0.7,
            ),
          ),
          child: Text(
            label,
            style: V2Typography.caption(color: V2Colors.accent).copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
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
    // Order matches HomeV2Screen.destinations — Scan sits at index 2.
    final destination = const [
      'Home',
      'Stack',
      'Scan',
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
