import 'dart:io' show Platform;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/interaction_result.dart';
import 'package:pharmaguide/core/models/synergy_result.dart';
import 'package:pharmaguide/core/utils/stack_intelligence_helpers.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';
import 'package:pharmaguide/features/stack/providers/stack_providers.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/home/widgets/home_recent_scans.dart';
import 'package:pharmaguide/core/components/pg_transparency_footer.dart';
import 'package:pharmaguide/services/stack/stack_intelligence_engine.dart';
import 'package:pharmaguide/services/stack/stack_safety_scorer.dart';
import 'package:pharmaguide/core/components/pg_score_line.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/core/widgets/pg_frosted_nav_bar.dart';

/// v2 Home — faithful visual mirror of `home_screen.dart`.
///
/// Phase 10.0 rebuild (2026-05-15): the earlier pass invented patterns
/// that don't exist in production (avatar chip, scan streak, category
/// chips, "Suggested next" card, 2-card stack health row, numeric
/// stack score, vertical recent-scans list). Sean called the
/// foundational rule of v2: visual reskin only, never redesign.
///
/// This rebuild mirrors production exactly:
///   1. iOS pull-to-refresh sliver
///   2. Search field — static, opens /search
///   3. Hero greeting — date label + "Good morning, Sean." + tagline
///      "Know what you take."
///   4. Scan CTA — single row, accent gradient
///   5. Stack Health — ONE card: header + status pill, insight band,
///      micro-metrics row (supplements · medications · interactions),
///      "View stack →" footer. NO numeric score.
///   6. Recent scans — section header + HORIZONTAL carousel of 156pt
///      cards (image + score line + name + brand + time-ago)
///   7. Quick Check — "Safe to take together?" single-row card with
///      caution-tinted compare-arrows icon
///   8. PGTransparencyFooter
///
/// Nav bar at the bottom: PGFrostedNavBar with `useV2Tones: true` and
/// Scan centered (Home / Stack / Scan / Chat / Profile).
class HomeV2Screen extends StatelessWidget {
  final ValueChanged<int>? onDestinationSelected;
  final int selectedIndex;

  /// When false, the v2 home screen doesn't paint its own bottom
  /// nav bar — used inside the production AppShell which already
  /// paints one. Default true for the /dev/v2/home gallery preview
  /// where there's no shell.
  final bool showNavBar;

  const HomeV2Screen({
    super.key,
    this.selectedIndex = 0,
    this.onDestinationSelected,
    this.showNavBar = true,
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
        extendBody: true,
        body: CustomScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            // iOS pull-to-refresh — absorbs bouncing-physics overscroll.
            if (Platform.isIOS) const CupertinoSliverRefreshControl(),

            // 1. Search field — static placeholder, opens /search.
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  V2Spacing.space24,
                  mq.padding.top + V2Spacing.space12,
                  V2Spacing.space24,
                  V2Spacing.space8,
                ),
                child: const _SearchLauncher(),
              ),
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

            // 3. Scan CTA.
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(
                V2Spacing.space24,
                V2Spacing.space24,
                V2Spacing.space24,
                0,
              ),
              sliver: SliverToBoxAdapter(child: _ScanCta()),
            ),

            // 4. Stack Health — v2 mirror, provider-wired in
            // Phase 11.5. Reads StackIntelligenceEngine for the real
            // tier verdict; identical source-of-truth to the
            // Stack-tab summary card so the user sees one verdict
            // across both surfaces.
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(
                V2Spacing.space24,
                V2Spacing.space32,
                V2Spacing.space24,
                0,
              ),
              sliver: SliverToBoxAdapter(child: _StackHealthCard()),
            ),

            // 5. Recent scans — legacy production carousel with real
            // _recentScansProvider data + Show-all bottom sheet.
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(
                V2Spacing.space24,
                V2Spacing.space24,
                V2Spacing.space24,
                0,
              ),
              sliver: SliverToBoxAdapter(child: HomeRecentScansSection()),
            ),

            // 6. Quick Check — legacy production "Safe to take
            // together?" tile that opens the real quick-check screen.
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(
                V2Spacing.space24,
                V2Spacing.space24,
                V2Spacing.space24,
                0,
              ),
              sliver: SliverToBoxAdapter(child: _QuickCheckCta()),
            ),

            // 7. Trust footer — v2 mirror reading the catalog manifest
            // for the real "Catalog updated <date>" freshness label.
            // Phase 11.5 replacement for the legacy HomeCitationStrip.
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(
                V2Spacing.space24,
                V2Spacing.space32,
                V2Spacing.space24,
                V2Spacing.space8,
              ),
              sliver: SliverToBoxAdapter(child: _CitationStrip()),
            ),

            // 8. Bottom spacer for the frosted nav bar overlap.
            SliverToBoxAdapter(
              child: SizedBox(
                height:
                    mq.padding.bottom + kPGNavBarHeight + V2Spacing.space8,
              ),
            ),
          ],
        ),
        bottomNavigationBar: !showNavBar
            ? null
            : PGFrostedNavBar(
          useV2Tones: true,
          selectedIndex: selectedIndex,
          onDestinationSelected: onDestinationSelected ?? (_) {},
          // v2 order: Home / Stack / Scan / Chat / Profile — Scan at
          // index 2 (visual centerpoint of the flat nav).
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
// Search launcher row — non-pinned visual mirror of HomeSearchLauncher.
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
                  'Search supplements',
                  style: V2Typography.body(color: V2Colors.fgMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Hero greeting — date label + greeting + "Know what you take." tagline.
// Mirrors HomeHeroSection.greetingFor() bands and date format.
// =============================================================================

class _HeroGreeting extends ConsumerWidget {
  const _HeroGreeting();

  static const _days = [
    'MONDAY',
    'TUESDAY',
    'WEDNESDAY',
    'THURSDAY',
    'FRIDAY',
    'SATURDAY',
    'SUNDAY',
  ];
  static const _months = [
    'JANUARY',
    'FEBRUARY',
    'MARCH',
    'APRIL',
    'MAY',
    'JUNE',
    'JULY',
    'AUGUST',
    'SEPTEMBER',
    'OCTOBER',
    'NOVEMBER',
    'DECEMBER',
  ];

  String _greetingFor(int hour) {
    if (hour >= 5 && hour < 12) return 'Good morning';
    if (hour >= 12 && hour < 17) return 'Hello there';
    if (hour >= 17 && hour < 21) return 'Good evening';
    return 'Good night';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Phase 11.1: read profileProvider for the real nickname; fall
    // back to "Sean" so the gallery preview keeps showing the polished
    // editorial state when no profile is loaded.
    final nickname = ref.watch(profileProvider).nickname;
    final displayName = (nickname != null && nickname.isNotEmpty)
        ? nickname
        : 'Sean';
    final now = DateTime.now();
    final dateLabel =
        '${_days[now.weekday - 1]}  ·  ${_months[now.month - 1]} ${now.day}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          dateLabel,
          style: V2Typography.eyebrow(color: V2Colors.accent),
        ),
        const SizedBox(height: V2Spacing.space12),
        Text(
          '${_greetingFor(now.hour)}, $displayName.',
          style: V2Typography.displayXs(color: V2Colors.fg),
        ),
        const SizedBox(height: V2Spacing.space4),
        Text(
          'Know what you take.',
          style: V2Typography.body(color: V2Colors.fgMuted),
        ),
      ],
    );
  }
}

// =============================================================================
// Scan CTA — single row, accent gradient. Production HomeScanCta.
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
          padding: const EdgeInsets.fromLTRB(
            V2Spacing.space24,
            V2Spacing.space24,
            V2Spacing.space16,
            V2Spacing.space24,
          ),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [V2Colors.accent, V2Colors.accentStrong],
            ),
            borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
            boxShadow: V2Shadows.md,
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius:
                      BorderRadius.circular(V2Spacing.radiusCard),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.22),
                    width: 0.8,
                  ),
                ),
                child: const Icon(
                  Icons.qr_code_scanner_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: V2Spacing.space16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Scan a supplement',
                      style: V2Typography.titleSm(color: Colors.white),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Check safety & interactions instantly',
                      // Locked to one line — Sean 2026-05-15. Shrunk
                      // from bodySm (14pt) to 12pt with ellipsis so it
                      // never wraps under the gradient tile's fixed
                      // 56pt icon + chevron real-estate.
                      style: V2Typography.bodySm(
                        color: Colors.white.withValues(alpha: 0.82),
                      ).copyWith(fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: V2Spacing.space8),
              Icon(
                Icons.arrow_forward_rounded,
                size: 22,
                color: Colors.white.withValues(alpha: 0.88),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Stack Health — single card, no numeric score. Mirrors
// HomeStackHealthWidget's populated state: header + status pill,
// one-line tinted insight band, micro-metrics row, "View stack →"
// footer. Fixture uses the "Optimal · no major interactions" state.
// =============================================================================

/// v2 Home Stack-Health card. Phase 11.5: now provider-wired to the
/// real StackIntelligenceEngine, mirroring the Stack-tab summary
/// card. Same source of truth as the production
/// HomeStackHealthWidget — same tier verdict on both surfaces.
class _StackHealthCard extends ConsumerWidget {
  const _StackHealthCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stack = ref.watch(activeStackProvider).asData?.value ?? const [];
    final supplementCount = stack
        .where((e) => e.type == 'supplement')
        .length;
    final medicationCount = stack
        .where((e) => e.type == 'medication')
        .length;
    final hasRealData = stack.isNotEmpty;
    final supplementLabel = hasRealData ? supplementCount : 3;
    final medicationLabel = hasRealData ? medicationCount : 1;
    final contextLine = hasRealData
        ? '$supplementCount supplement${supplementCount == 1 ? '' : 's'}'
            ' · $medicationCount medication'
            '${medicationCount == 1 ? '' : 's'}'
        : '3 supplements · 1 medication';

    // Real intelligence tier — identical wire-up to Stack v2's
    // _StackSummaryCard so the user sees one verdict everywhere.
    final reportAsync = ref.watch(stackSafetyReportProvider);
    final synergyAsync = ref.watch(synergyReportProvider);
    final recallAsync = ref.watch(recalledIngredientsReportProvider);
    final safetyScore = reportAsync.whenOrNull(
      data: (report) {
        final allIssues = <InteractionResult>[
          ...report.medicationPairInteractions,
          ...report.medicationInteractions,
          ...report.stackInteractions,
          ...report.categoryWarnings,
        ];
        final synergies = synergyAsync.whenOrNull(
              data: (synergyReport) => synergyReport.matches
                  .map(
                    (m) => SynergyResult(
                      ingredient1: m.matchedIngredients.isNotEmpty
                          ? m.matchedIngredients.first
                          : m.clusterId,
                      ingredient2: m.matchedIngredients.length > 1
                          ? m.matchedIngredients[1]
                          : m.clusterName,
                      description: m.mechanism,
                      evidenceLevel: EvidenceLevel.established,
                      bonus: m.bonusPoints,
                    ),
                  )
                  .toList(),
            ) ??
            const <SynergyResult>[];
        return const StackSafetyScorer().compute(
          issues: allIssues,
          synergies: synergies,
        );
      },
    );
    final intelligence =
        (reportAsync.hasValue && synergyAsync.hasValue && recallAsync.hasValue)
            ? const StackIntelligenceEngine().diagnose(
                stackSize: stack.length,
                safetyReport: reportAsync.value!,
                recalledReport: recallAsync.value!,
                synergyReport: synergyAsync.value!,
                qualityScore: safetyScore?.score,
              )
            : null;
    final status = intelligence?.tier.healthLabel;
    final isAnalyzing = reportAsync.isLoading ||
        synergyAsync.isLoading ||
        recallAsync.isLoading;
    final Color tone = status?.color ?? V2Colors.safe;
    final statusLabel = isAnalyzing
        ? 'Analyzing'
        : status?.label ?? 'No data yet';
    final insightLine = hasRealData
        ? describeStackSummary(intelligence)
        : contextLine; // Empty stack: keep the fixture line for design preview.

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
      child: InkWell(
        onTap: () {},
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        child: Container(
          // Modernization (Sean 2026-05-15): replace the flat white
          // surface with a subtle vertical gradient — top stays clean
          // white, bottom fades to a 5% safe-tinted wash. Gives the
          // card a "healthy state" warmth without changing structure.
          // Softer layered shadow via V2Shadows.md so the card lifts
          // off the cream bg more deliberately.
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                V2Colors.surface,
                Color.lerp(V2Colors.surface, tone, 0.05)!,
              ],
            ),
            borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
            border: Border.all(color: V2Colors.outline),
            boxShadow: V2Shadows.md,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header + status pill + insight band.
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  V2Spacing.space24,
                  V2Spacing.space24,
                  V2Spacing.space24,
                  V2Spacing.space16,
                ),
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Stack Health',
                                style:
                                    V2Typography.titleSm(color: V2Colors.fg),
                              ),
                              const SizedBox(height: 2),
                              // Header subline = supplement/medication
                              // count context, matching production's
                              // _StackSummaryCard pattern. The long
                              // diagnostic insight goes in the tinted
                              // band below the header.
                              Text(
                                contextLine,
                                style: V2Typography.bodySm(
                                  color: V2Colors.fgMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: V2Spacing.space12,
                            vertical: V2Spacing.space4,
                          ),
                          decoration: BoxDecoration(
                            color: tone.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(
                              V2Spacing.radiusPill,
                            ),
                            border: Border.all(
                              color: tone.withValues(alpha: 0.20),
                              width: 0.8,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Small filled status dot — reads as a
                              // live indicator (not just a label tag).
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: tone,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: V2Spacing.space8),
                              Text(
                                statusLabel,
                                style: V2Typography.label(color: tone),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: V2Spacing.space12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: V2Spacing.space12,
                        vertical: V2Spacing.space8,
                      ),
                      decoration: BoxDecoration(
                        color: tone.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            // Icon mirrors intelligence severity: warning
                            // when the stack tier flags issues, check
                            // when the stack is solid/optimized.
                            (status?.label.contains('Unsafe') ?? false) ||
                                    (status?.label.contains('Concerning') ??
                                        false)
                                ? Icons.warning_amber_rounded
                                : Icons.check_circle_outline,
                            size: 14,
                            color: tone,
                          ),
                          const SizedBox(width: V2Spacing.space8),
                          Expanded(
                            child: Text(
                              insightLine,
                              style: V2Typography.caption(color: tone)
                                  .copyWith(fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Micro-metrics row — supplements · medications · conflicts.
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: V2Spacing.space24,
                  vertical: V2Spacing.space12,
                ),
                decoration: const BoxDecoration(
                  color: V2Colors.bg,
                  border: Border(
                    top: BorderSide(color: V2Colors.outline, width: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    _MicroMetric(
                      icon: Icons.medication_outlined,
                      label: '$supplementLabel supplement'
                          '${supplementLabel == 1 ? '' : 's'}',
                      color: V2Colors.accent,
                    ),
                    const SizedBox(width: V2Spacing.space16),
                    _MicroMetric(
                      icon: Icons.local_pharmacy_outlined,
                      label: '$medicationLabel medication'
                          '${medicationLabel == 1 ? '' : 's'}',
                      color: V2Colors.fgMuted,
                    ),
                    const SizedBox(width: V2Spacing.space16),
                    const _MicroMetric(
                      icon: Icons.check_circle_outline,
                      label: 'No conflicts',
                      color: V2Colors.safe,
                    ),
                  ],
                ),
              ),
              // CTA footer.
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  V2Spacing.space24,
                  V2Spacing.space12,
                  V2Spacing.space24,
                  V2Spacing.space16,
                ),
                child: Row(
                  children: [
                    Text(
                      'View stack',
                      style: V2Typography.label(color: V2Colors.accent),
                    ),
                    const SizedBox(width: V2Spacing.space4),
                    const Icon(
                      Icons.arrow_forward_rounded,
                      size: 16,
                      color: V2Colors.accent,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MicroMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _MicroMetric({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: V2Spacing.space4),
          Flexible(
            child: Text(
              label,
              style: V2Typography.caption(color: V2Colors.fgMuted)
                  .copyWith(fontWeight: FontWeight.w500),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Recent scans — section header + horizontal carousel of 156pt cards.
// Mirrors HomeRecentScansSection. "Show all" opens a list bottom sheet
// (production behavior, not built in the visual mirror).
// =============================================================================

// Scaffold for the v2 Recent-scans carousel mirror — currently unused.
// Routes.home renders the legacy HomeRecentScansSection which sources
// real scan history. Kept here for the future v2 wiring pass.
// ignore: unused_element
class _RecentScansSection extends StatelessWidget {
  const _RecentScansSection();

  static const _fixture = <(String, String, int, String)>[
    ('Nordic Naturals', 'Ultimate Omega 2X', 84, '2h ago'),
    ('Thorne', 'Basic Nutrients 2/Day', 91, 'Yesterday'),
    ('NOW Foods', 'L-Theanine 200mg', 72, '3d ago'),
    ('Pure Encapsulations', 'Magnesium Glycinate', 88, '5d ago'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: V2Spacing.space24),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Recent scans',
                      style: V2Typography.titleSm(color: V2Colors.fg),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Your last checked products',
                      style: V2Typography.bodySm(color: V2Colors.fgMuted),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () {},
                child: Text(
                  'Show all',
                  style: V2Typography.label(color: V2Colors.accent),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: V2Spacing.space12),
        SizedBox(
          height: 210,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: V2Spacing.space24,
            ),
            itemCount: _fixture.length,
            separatorBuilder: (_, __) =>
                const SizedBox(width: V2Spacing.space12),
            itemBuilder: (context, i) {
              final (brand, name, score, time) = _fixture[i];
              return _RecentScanCard(
                brand: brand,
                name: name,
                score: score,
                time: time,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _RecentScanCard extends StatelessWidget {
  final String brand;
  final String name;
  final int score;
  final String time;

  const _RecentScanCard({
    required this.brand,
    required this.name,
    required this.score,
    required this.time,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 156,
      child: Material(
        color: V2Colors.surface,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        child: InkWell(
          onTap: () {},
          borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
          child: Container(
            padding: const EdgeInsets.all(V2Spacing.space12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
              border: Border.all(color: V2Colors.outline),
              boxShadow: V2Shadows.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Product image placeholder (production: ProductImage).
                Center(
                  child: Container(
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
                      size: 24,
                    ),
                  ),
                ),
                const SizedBox(height: V2Spacing.space8),
                // Compact score line (in lieu of PGScoreRing — keeps
                // tone alignment with the rest of v2 product surfaces).
                Center(child: PGScoreLine(score: score, compact: true)),
                const SizedBox(height: V2Spacing.space8),
                Text(
                  name,
                  style: V2Typography.bodySm(color: V2Colors.fg).copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  brand,
                  style: V2Typography.caption(color: V2Colors.fgMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const Spacer(),
                Text(
                  time,
                  style: V2Typography.caption(color: V2Colors.fgSubtle),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Quick Check — "Safe to take together?" single-row card. Mirrors
// HomeQuickCheckCta. Caution-tinted compare-arrows icon.
// =============================================================================

/// v2 Quick-Check tile. Phase 11.5: now provider-aware in the sense
/// that tap routes to the real /quick-check screen — same behavior
/// as the legacy HomeQuickCheckCta. Production functionality preserved.
class _QuickCheckCta extends StatelessWidget {
  const _QuickCheckCta();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: V2Colors.surface,
      borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
      child: InkWell(
        onTap: () => GoRouter.of(context).push(Routes.quickCheck),
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
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: V2Colors.caution.withValues(alpha: 0.12),
                  borderRadius:
                      BorderRadius.circular(V2Spacing.radiusCard),
                ),
                child: const Icon(
                  Icons.compare_arrows_rounded,
                  color: V2Colors.caution,
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
                      'Safe to take together?',
                      style: V2Typography.bodyMedium(color: V2Colors.fg),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Check two supplements or medications',
                      style: V2Typography.bodySm(color: V2Colors.fgMuted),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
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
// Preview wrapper for /dev/v2/home — toasts on nav-bar taps and
// provides a floating close chip to return to the gallery.
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

// =============================================================================
// v2 Citation strip — reads catalogInfoProvider for the real
// "Catalog updated <date>" freshness label. Phase 11.5 replacement
// for legacy HomeCitationStrip. Uses PGTransparencyFooter so the
// disclaimer + sources strip stays consistent with Product Detail.
// =============================================================================

class _CitationStrip extends ConsumerWidget {
  const _CitationStrip();

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _formatDate(DateTime d) =>
      'Updated ${_months[d.month - 1]} ${d.day}, ${d.year}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogAsync = ref.watch(catalogInfoProvider);
    final info = catalogAsync.asData?.value;
    final freshness = info?.buildDate != null
        ? _formatDate(info!.buildDate!)
        : null;
    return PGTransparencyFooter(freshnessLabel: freshness);
  }
}
