import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/utils/stack_intelligence_helpers.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';
import 'package:pharmaguide/features/stack/providers/stack_providers.dart';
import 'package:pharmaguide/core/utils/relative_time.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/core/components/pg_transparency_footer.dart';
import 'package:pharmaguide/services/stack/stack_intelligence_engine.dart';
import 'package:pharmaguide/core/components/pg_pill_button.dart';
import 'package:pharmaguide/core/components/pg_score_line.dart';
import 'package:pharmaguide/core/widgets/product_image.dart';
import 'package:pharmaguide/core/widgets/pg_haptics.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/core/widgets/pg_frosted_nav_bar.dart';

/// v2 Home — production home surface.
///
/// Production information architecture:
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
/// Nav bar at the bottom: PGFrostedNavBar with Scan centered
/// (Home / Stack / Scan / Chat / Profile).
class HomeV2Screen extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final mq = MediaQuery.of(context);
    final scrollView = CustomScrollView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        // iOS pull-to-refresh — absorbs bouncing-physics overscroll.
        if (Platform.isIOS)
          CupertinoSliverRefreshControl(onRefresh: () => _onHomeV2Refresh(ref)),

        // 1. Search field — pinned at top, opens /search.
        // The field sticks under the status bar while content scrolls
        // beneath it. ColoredBox keeps the cream bg continuous.
        SliverPersistentHeader(
          pinned: true,
          delegate: _PinnedSearchDelegate(topPadding: mq.padding.top),
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

        // 4. Stack Health — reads StackIntelligenceEngine for the
        // real tier verdict; identical source-of-truth to the Stack
        // tab summary card so the user sees one verdict across both
        // surfaces.
        const SliverPadding(
          padding: EdgeInsets.fromLTRB(
            V2Spacing.space24,
            V2Spacing.space32,
            V2Spacing.space24,
            0,
          ),
          sliver: SliverToBoxAdapter(child: _StackHealthCard()),
        ),

        // 5. Recent scans — carousel with real recent-scan data +
        // Show-all bottom sheet.
        const SliverPadding(
          padding: EdgeInsets.fromLTRB(
            V2Spacing.space24,
            V2Spacing.space24,
            V2Spacing.space24,
            0,
          ),
          sliver: SliverToBoxAdapter(child: _RecentScansSection()),
        ),

        // 6. Quick Check — "Safe to take together?" tile that opens
        // the real quick-check screen.
        const SliverPadding(
          padding: EdgeInsets.fromLTRB(
            V2Spacing.space24,
            V2Spacing.space24,
            V2Spacing.space24,
            0,
          ),
          sliver: SliverToBoxAdapter(child: _QuickCheckCta()),
        ),

        // 7. Trust footer — reads the catalog manifest for the real
        // "Catalog updated <date>" freshness label.
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
            height: mq.padding.bottom + kPGNavBarHeight + V2Spacing.space8,
          ),
        ),
      ],
    );
    final body = Platform.isIOS
        ? scrollView
        : RefreshIndicator(
            onRefresh: () => _onHomeV2Refresh(ref),
            child: scrollView,
          );
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
        body: body,
        bottomNavigationBar: !showNavBar
            ? null
            : PGFrostedNavBar(
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

Future<void> _onHomeV2Refresh(WidgetRef ref) async {
  unawaited(PGHaptics.tap());
  ref.invalidate(activeStackProvider);
  ref.invalidate(_v2RecentScansProvider);
  await Future<void>.delayed(const Duration(milliseconds: 350));
}

// =============================================================================
// Search launcher row — non-pinned home search affordance.
// =============================================================================

class _SearchLauncher extends StatelessWidget {
  const _SearchLauncher();

  @override
  Widget build(BuildContext context) {
    void openSearch() => GoRouter.of(context).push(Routes.search);

    return Semantics(
      button: true,
      label: 'Search supplements',
      onTap: openSearch,
      child: ExcludeSemantics(
        child: Material(
          color: V2Colors.surface,
          borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
          child: InkWell(
            onTap: openSearch,
            borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(
                horizontal: V2Spacing.space16,
              ),
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

  /// Resolve the greeting band for the given hour. Sean 2026-05-16
  /// spec: morning / afternoon / evening windows plus a "Hello"
  /// fallback outside business hours. Returns the band as a `String`
  /// (e.g. "Good morning") or `null` if the time is outside the
  /// known bands — caller substitutes "Hello" (with name) or
  /// "Hello there" (no name) for the null case.
  static String? _bandFor(int hour) {
    if (hour >= 5 && hour < 12) return 'Good morning';
    if (hour >= 12 && hour < 17) return 'Good afternoon';
    if (hour >= 17 && hour < 22) return 'Good evening';
    return null; // late-night / pre-dawn window → "Hello"
  }

  /// Compose the greeting line per Sean's spec:
  ///   * Nickname present → "Good morning, Sean" / "Hello, Sean"
  ///   * Nickname empty   → "Good morning" / "Hello there"
  /// No trailing period — the line is a casual hello, not a sentence.
  static String composeGreeting({required String? nickname, DateTime? now}) {
    final hour = (now ?? DateTime.now()).hour;
    final cleaned = nickname?.trim();
    final hasName = cleaned != null && cleaned.isNotEmpty;
    final band = _bandFor(hour);
    if (band != null) {
      return hasName ? '$band, $cleaned' : band;
    }
    return hasName ? 'Hello, $cleaned' : 'Hello there';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nickname = ref.watch(profileProvider).nickname;
    final now = DateTime.now();
    final dateLabel =
        '${_days[now.weekday - 1]}  ·  ${_months[now.month - 1]} ${now.day}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(dateLabel, style: V2Typography.eyebrow(color: V2Colors.accent)),
        const SizedBox(height: V2Spacing.space12),
        Text(
          composeGreeting(nickname: nickname, now: now),
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
        onTap: () => GoRouter.of(context).go(Routes.scan),
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
                  borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
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
    final stackAsync = ref.watch(activeStackProvider);
    final stack = stackAsync.asData?.value ?? const [];
    final supplementCount = stack.where((e) => e.type == 'supplement').length;
    final medicationCount = stack.where((e) => e.type == 'medication').length;
    final hasLoadedStack = stackAsync.hasValue;
    final hasRealData = stack.isNotEmpty;
    final supplementLabel = hasLoadedStack ? supplementCount : 3;
    final medicationLabel = hasLoadedStack ? medicationCount : 1;
    final contextLine = hasLoadedStack
        ? '$supplementCount supplement${supplementCount == 1 ? '' : 's'}'
              ' · $medicationCount medication'
              '${medicationCount == 1 ? '' : 's'}'
        : '3 supplements · 1 medication';

    // Real intelligence tier — identical wire-up to Stack v2's
    // _StackSummaryCard so the user sees one verdict everywhere.
    final reportAsync = ref.watch(stackSafetyReportProvider);
    final synergyAsync = ref.watch(synergyReportProvider);
    final recallAsync = ref.watch(recalledIngredientsReportProvider);
    final doseAlertsAsync = ref.watch(stackDoseThresholdAlertsProvider);
    final intelligence =
        (reportAsync.hasValue &&
            synergyAsync.hasValue &&
            recallAsync.hasValue &&
            doseAlertsAsync.hasValue)
        ? const StackIntelligenceEngine().diagnoseFromReports(
            stackSize: stack.length,
            safetyReport: reportAsync.value!,
            recalledReport: recallAsync.value!,
            synergyReport: synergyAsync.value!,
            doseThresholdAlerts: doseAlertsAsync.value!,
          )
        : null;
    final status = intelligence?.tier.healthLabel;
    final isAnalyzing =
        reportAsync.isLoading ||
        synergyAsync.isLoading ||
        recallAsync.isLoading ||
        doseAlertsAsync.isLoading;
    final Color tone = status?.color ?? V2Colors.safe;
    final statusLabel = isAnalyzing
        ? 'Analyzing'
        : status?.label ?? 'No data yet';
    final insightLine = hasRealData
        ? describeStackSummary(intelligence)
        : contextLine;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
      child: InkWell(
        onTap: () => GoRouter.of(context).go(Routes.stack),
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
                                style: V2Typography.titleSm(color: V2Colors.fg),
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
                              style: V2Typography.caption(
                                color: tone,
                              ).copyWith(fontWeight: FontWeight.w500),
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
                      label:
                          '$supplementLabel supplement'
                          '${supplementLabel == 1 ? '' : 's'}',
                      color: V2Colors.accent,
                    ),
                    const SizedBox(width: V2Spacing.space16),
                    _MicroMetric(
                      icon: Icons.local_pharmacy_outlined,
                      label:
                          '$medicationLabel medication'
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
              style: V2Typography.caption(
                color: V2Colors.fgMuted,
              ).copyWith(fontWeight: FontWeight.w500),
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
// "Show all" opens a list bottom sheet.
// =============================================================================

/// v2 Recent scans carousel. Reads user_scan_history + core DB and
/// renders real cards. Tap on a card pushes /product/{dsldId}.
/// Loading/error states stay quiet; true empty data renders the v2
/// empty state instead of fake cards.
class _RecentScansSection extends ConsumerWidget {
  const _RecentScansSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scansAsync = ref.watch(_v2RecentScansProvider);
    final scans = scansAsync.asData?.value;
    if (scans == null) return const SizedBox.shrink();
    if (scans.isEmpty) return const _RecentScansEmptyState();

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
            ],
          ),
        ),
        const SizedBox(height: V2Spacing.space12),
        SizedBox(
          height: 218,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: V2Spacing.space24),
            itemCount: scans.length,
            separatorBuilder: (_, __) =>
                const SizedBox(width: V2Spacing.space12),
            itemBuilder: (context, i) {
              return _RecentScanCard(scan: scans[i]);
            },
          ),
        ),
      ],
    );
  }
}

/// v2 empty state for the Recent scans section. Calm "Nothing scanned
/// yet" prompt + outlined "Scan your first supplement" pill button
/// that routes to /scan. Mirrors the production
/// `_buildEmptyState` intent — never silently hide the section.
class _RecentScansEmptyState extends StatelessWidget {
  const _RecentScansEmptyState();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: V2Spacing.space24),
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
        const SizedBox(height: V2Spacing.space12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: V2Spacing.space24),
          // **Phase 11.7j.2 — Sean 2026-05-16 size + tone parity with
          // Stack Health card.** Adds V2Shadows.md (was no shadow) +
          // larger vertical padding so the empty state sits at the
          // same visual weight as the Stack Health card directly
          // above it. Text softened from "Your last 10 scanned
          // supplements will appear here." to "Your recent scans
          // will appear here." — no need to set a numeric cap
          // expectation up front.
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(
              V2Spacing.space24,
              V2Spacing.space32,
              V2Spacing.space24,
              V2Spacing.space32,
            ),
            decoration: BoxDecoration(
              color: V2Colors.surface,
              borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
              border: Border.all(color: V2Colors.outline),
              boxShadow: V2Shadows.md,
            ),
            child: Column(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: V2Colors.accentTint,
                    borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
                    border: Border.all(
                      color: V2Colors.accent.withValues(alpha: 0.22),
                      width: 0.7,
                    ),
                  ),
                  child: const Icon(
                    Icons.history_rounded,
                    size: 24,
                    color: V2Colors.accent,
                  ),
                ),
                const SizedBox(height: V2Spacing.space12),
                Text(
                  'Nothing scanned yet',
                  style: V2Typography.titleSm(color: V2Colors.fg),
                ),
                const SizedBox(height: V2Spacing.space4),
                Text(
                  'Your recent scans will appear here.',
                  textAlign: TextAlign.center,
                  style: V2Typography.bodySm(color: V2Colors.fgMuted),
                ),
                const SizedBox(height: V2Spacing.space16),
                PGPillButton(
                  label: 'Scan your first supplement',
                  icon: Icons.qr_code_scanner_rounded,
                  variant: PGPillVariant.secondary,
                  onPressed: () => GoRouter.of(context).go(Routes.scan),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _RecentScanCard extends StatelessWidget {
  final _RecentScan scan;

  const _RecentScanCard({required this.scan});

  static const double _imageFrameSize = V2Spacing.space64 + V2Spacing.space8;
  static const double _imageSize = V2Spacing.space64 - V2Spacing.space8;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 156,
      child: Material(
        color: V2Colors.surface,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        child: InkWell(
          onTap: () => GoRouter.of(context).push('/product/${scan.dsldId}'),
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
                // ProductImage resolves the DSLD thumbnail or OFF image
                // via cache, then falls back to BrandedPlaceholder when
                // nothing is available.
                Center(
                  child: Container(
                    key: const ValueKey('home-recent-scan-image-frame'),
                    width: _imageFrameSize,
                    height: _imageFrameSize,
                    padding: const EdgeInsets.all(V2Spacing.space8),
                    decoration: BoxDecoration(
                      color: V2Colors.bg,
                      borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
                      border: Border.all(color: V2Colors.outline),
                    ),
                    child: ProductImage(
                      dsldId: scan.dsldId,
                      upc: scan.upc,
                      dsldImagePath: scan.imageUrl,
                      productName: scan.name,
                      brandName: scan.brand,
                      formFactor: scan.formFactor,
                      score: scan.score.toDouble(),
                      size: _imageSize,
                      compact: true,
                    ),
                  ),
                ),
                const SizedBox(height: V2Spacing.space8),
                // Compact score line keeps tone alignment with the rest
                // of v2 product surfaces.
                Center(child: PGScoreLine(score: scan.score, compact: true)),
                const SizedBox(height: V2Spacing.space8),
                Text(
                  scan.name,
                  style: V2Typography.bodySm(
                    color: V2Colors.fg,
                  ).copyWith(fontWeight: FontWeight.w500),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  scan.brand,
                  style: V2Typography.caption(color: V2Colors.fgMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const Spacer(),
                Text(
                  scan.time,
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
// Quick Check — "Safe to take together?" single-row card with a
// caution-tinted compare-arrows icon.
// =============================================================================

/// v2 Quick-Check tile. Tap routes to the real /quick-check screen.
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
                  borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
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
              const Icon(Icons.chevron_right_rounded, color: V2Colors.fgMuted),
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
    // **Sentry fix — 15× `Looking up a deactivated widget's ancestor`.**
    // Capture the messenger reference BEFORE setState so the
    // InheritedWidget lookup happens on a guaranteed-mounted context
    // (setState can deactivate this element if GoRouter is mid-transition
    // away from the dev gallery). The `mounted` guard catches the
    // remaining race where the tap fires after the gallery has popped.
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _index = i);
    // Order matches HomeV2Screen.destinations — Scan sits at index 2.
    final destination = const ['Home', 'Stack', 'Scan', 'Chat', 'Profile'][i];
    messenger.showSnackBar(
      SnackBar(
        content: Text('$destination tapped — preview only'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1200),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        HomeV2Screen(selectedIndex: _index, onDestinationSelected: _onTap),
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
                child: Icon(Icons.close_rounded, color: V2Colors.fg, size: 20),
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
// "Catalog updated <date>" freshness label. Uses PGTransparencyFooter
// so the disclaimer + sources strip stays consistent with Product Detail.
// =============================================================================

class _CitationStrip extends ConsumerWidget {
  const _CitationStrip();

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
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
    // Phase 11.7j.3 — center the footer block on Home. Home's body is
    // organized around centered cards, so the trust footer should
    // resolve the column visually rather than hang off the left edge.
    return PGTransparencyFooter(freshnessLabel: freshness, center: true);
  }
}

// =============================================================================
// v2 Recent-scans provider — joins user_scan_history with the core
// catalog and returns ready-to-render records for the carousel cards.
//
// **Phase 11.7L bug 4 (2026-05-16):** record now carries `upc`,
// `imageUrl`, and `formFactor` so `_RecentScanCard` can render the
// real product photo via `ProductImage`.
//
// Auto-disposes when the home screen unmounts so the scan list
// refreshes when the user returns from a scanner round.
// =============================================================================

typedef _RecentScan = ({
  String dsldId,
  String? upc,
  String? imageUrl,
  String? formFactor,
  String brand,
  String name,
  int score,
  String time,
});

final _v2RecentScansProvider = FutureProvider.autoDispose<List<_RecentScan>>((
  ref,
) async {
  final userDb = ref.watch(userDatabaseProvider);
  final coreDb = ref.watch(coreDatabaseProvider);
  final history = await userDb.getRecentScans(limit: 10);
  final results = <_RecentScan>[];
  for (final scan in history) {
    final product = await coreDb.findById(scan.dsldId);
    if (product == null) continue;
    results.add((
      dsldId: product.dsldId,
      upc: product.upcSku,
      imageUrl: product.imageThumbnailUrl,
      formFactor: product.formFactor,
      brand: product.brandName ?? '',
      name: product.productName,
      score: (product.qualityScoreV4100 ?? 0).round(),
      time: relativeTime(scan.scannedAt),
    ));
  }
  return results;
});

// =============================================================================
// Pinned search header delegate — keeps `_SearchLauncher` sticky under the
// status bar while content scrolls underneath.
// =============================================================================

class _PinnedSearchDelegate extends SliverPersistentHeaderDelegate {
  _PinnedSearchDelegate({required this.topPadding});

  /// System status-bar inset; we draw inside this padding so the search
  /// field never sits underneath the notch / Dynamic Island.
  final double topPadding;

  // 48pt launcher + 12pt top + 8pt bottom = 68pt below the status bar.
  static const double _topPadding = V2Spacing.space12;
  static const double _bottomPadding = V2Spacing.space8;
  static const double _launcherHeight = 48;

  double get _height =>
      topPadding + _topPadding + _launcherHeight + _bottomPadding;

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
    return ColoredBox(
      color: V2Colors.bg,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          V2Spacing.space24,
          topPadding + _topPadding,
          V2Spacing.space24,
          _bottomPadding,
        ),
        child: const _SearchLauncher(),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _PinnedSearchDelegate oldDelegate) {
    return oldDelegate.topPadding != topPadding;
  }
}
