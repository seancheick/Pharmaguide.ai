import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_section_header.dart';
import 'package:pharmaguide/features/home/widgets/home_category_rail.dart';
import 'package:pharmaguide/features/home/widgets/home_citation_strip.dart';
import 'package:pharmaguide/features/home/widgets/home_hero_section.dart';
import 'package:pharmaguide/features/home/widgets/home_profile_completeness_card.dart';
import 'package:pharmaguide/features/home/widgets/home_quick_check_cta.dart';
import 'package:pharmaguide/features/home/widgets/home_recent_scans.dart';
import 'package:pharmaguide/features/home/widgets/home_scan_cta.dart';
import 'package:pharmaguide/features/home/widgets/home_search_launcher.dart';
import 'package:pharmaguide/features/home/widgets/home_stack_health.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';

/// The home screen.
///
/// Editorial-premium composition: hero greeting → scan CTA → search →
/// categories → stack → recent scans → disclaimer. Each section has its own
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
    final mq = MediaQuery.of(context);

    return Scaffold(
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          // Top safe area (no app bar — home uses free-floating hero)
          SliverToBoxAdapter(
            child: SizedBox(height: mq.padding.top + AppTheme.space12),
          ),

          // ----------------------------------------------------------------
          // Hero — date pill, greeting, tagline
          // ----------------------------------------------------------------
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.space20,
              AppTheme.space8,
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

          // ----------------------------------------------------------------
          // Search launcher (tap → opens full search screen)
          // ----------------------------------------------------------------
          const SliverPadding(
            padding: EdgeInsets.fromLTRB(
              AppTheme.space20,
              AppTheme.space12,
              AppTheme.space20,
              0,
            ),
            sliver: SliverToBoxAdapter(child: HomeSearchLauncher()),
          ),

          // ----------------------------------------------------------------
          // Quick Check CTA — "Safe to Take Together?"
          // ----------------------------------------------------------------
          const SliverPadding(
            padding: EdgeInsets.fromLTRB(
              AppTheme.space20,
              AppTheme.space12,
              AppTheme.space20,
              0,
            ),
            sliver: SliverToBoxAdapter(child: HomeQuickCheckCta()),
          ),

          // ----------------------------------------------------------------
          // Profile completeness (conditional, highlighted card)
          // ----------------------------------------------------------------
          if (profile.completeness < 60)
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

          // ----------------------------------------------------------------
          // Categories
          // ----------------------------------------------------------------
          const SliverToBoxAdapter(
            child: PGSectionHeader(
              title: 'Browse categories',
              subtitle: 'Popular supplement types',
              padding: EdgeInsets.fromLTRB(
                AppTheme.space20,
                AppTheme.space32,
                AppTheme.space20,
                AppTheme.space12,
              ),
            ),
          ),
          const SliverToBoxAdapter(child: HomeCategoryRail()),

          // ----------------------------------------------------------------
          // Stack health — premium Oura-style card
          // ----------------------------------------------------------------
          const SliverPadding(
            padding: EdgeInsets.fromLTRB(
              AppTheme.space20,
              AppTheme.space24,
              AppTheme.space20,
              0,
            ),
            sliver: SliverToBoxAdapter(child: HomeStackHealthWidget()),
          ),

          // ----------------------------------------------------------------
          // Recent scans
          // ----------------------------------------------------------------
          const SliverToBoxAdapter(
            child: PGSectionHeader(
              title: 'Recent scans',
              subtitle: 'Your last checked products',
              padding: EdgeInsets.fromLTRB(
                AppTheme.space20,
                AppTheme.space24,
                AppTheme.space20,
                AppTheme.space12,
              ),
            ),
          ),
          const SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: AppTheme.space20),
            sliver: SliverToBoxAdapter(child: HomeRecentScansSection()),
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
            child: SizedBox(height: mq.padding.bottom + 96),
          ),
        ],
      ),
    );
  }
}
