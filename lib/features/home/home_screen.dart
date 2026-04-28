import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
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
final isFirstLaunchHomeProvider =
    FutureProvider.autoDispose<bool>((ref) async {
  // ref.watch — not ref.read — so this provider re-fires when activeStack
  // is invalidated (which StackActions does on every add/remove).
  final stack = await ref.watch(activeStackProvider.future);
  if (stack.isNotEmpty) return false;
  final userDb = ref.watch(userDatabaseProvider);
  final scans = await userDb.getRecentScans(limit: 1);
  return scans.isEmpty;
});

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
    final isFirstLaunch = firstLaunchAsync.asData?.value == true;
    final showExpandedSections = firstLaunchAsync.asData?.value == false;

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
      ),
    );
  }
}
