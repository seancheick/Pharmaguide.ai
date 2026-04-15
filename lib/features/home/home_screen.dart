import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/theme/app_motion.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_card.dart';
import 'package:pharmaguide/core/widgets/pg_citation_strip.dart';
import 'package:pharmaguide/core/widgets/pg_filter_chip.dart';
import 'package:pharmaguide/core/widgets/pg_score_ring.dart';
import 'package:pharmaguide/core/widgets/pg_search_field.dart';
import 'package:pharmaguide/core/widgets/product_image.dart';
import 'package:pharmaguide/core/widgets/pg_section_header.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/interaction_result.dart';
import 'package:pharmaguide/core/models/synergy_result.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';
import 'package:pharmaguide/features/stack/providers/stack_providers.dart';
import 'package:pharmaguide/services/stack/stack_safety_scorer.dart';
import 'package:pharmaguide/services/stack/synergy_result.dart' show SynergyReport;

/// The home screen.
///
/// Editorial-premium composition: hero greeting → scan CTA → search →
/// categories → stack → recent scans → disclaimer. Each section has its own
/// spacing rhythm; nothing is on a uniform 16/16/16 grid.
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
              child: _HeroSection(nickname: profile.nickname),
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
            sliver: SliverToBoxAdapter(child: _ScanCta()),
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
            sliver: SliverToBoxAdapter(child: _HomeSearchLauncher()),
          ),

          // ----------------------------------------------------------------
          // Quick Check CTA — "Safe to Take Together?"
          // ----------------------------------------------------------------
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.space20,
              AppTheme.space12,
              AppTheme.space20,
              0,
            ),
            sliver: SliverToBoxAdapter(
              child: PGCard(
                onTap: () => GoRouter.of(context).push(Routes.quickCheck),
                padding: const EdgeInsets.all(AppTheme.space16),
                child: Semantics(
                  button: true,
                  label: 'Check if two supplements or medications are safe to take together',
                  child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppTheme.severityCaution.withValues(alpha: 0.12),
                        borderRadius:
                            BorderRadius.circular(AppTheme.radiusMedium),
                      ),
                      child: const Icon(
                        Icons.compare_arrows_rounded,
                        color: AppTheme.severityCaution,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: AppTheme.space12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Safe to take together?',
                            style:
                                Theme.of(context).textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Check any two products for interactions',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
                ),
              ),
            ),
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
                child: _ProfileCompletenessCard(
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
          const SliverToBoxAdapter(child: _CategoryRail()),

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
            sliver: SliverToBoxAdapter(child: _StackHealthWidget()),
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
            sliver: SliverToBoxAdapter(child: _RecentScansSection()),
          ),

          // ----------------------------------------------------------------
          // Trust footer — sources, updated date, disclaimer
          // ----------------------------------------------------------------
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.space20,
              AppTheme.space32,
              AppTheme.space20,
              AppTheme.space8,
            ),
            sliver: SliverToBoxAdapter(
              child: _DynamicCitationStrip(),
            ),
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

// ---------------------------------------------------------------------------
// Hero section — editorial greeting
// ---------------------------------------------------------------------------

class _HeroSection extends StatelessWidget {
  final String? nickname;
  const _HeroSection({required this.nickname});

  static const _days = [
    'MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY',
    'FRIDAY', 'SATURDAY', 'SUNDAY',
  ];
  static const _months = [
    'JANUARY', 'FEBRUARY', 'MARCH', 'APRIL', 'MAY', 'JUNE',
    'JULY', 'AUGUST', 'SEPTEMBER', 'OCTOBER', 'NOVEMBER', 'DECEMBER',
  ];

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final now = DateTime.now();
    final dateLabel = '${_days[now.weekday - 1]}  ·  '
        '${_months[now.month - 1]} ${now.day}';
    final name =
        (nickname != null && nickname!.isNotEmpty) ? ', $nickname' : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Date label — small, uppercase, teal
        Text(
          dateLabel,
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
            color: scheme.primary,
          ),
        ),
        const SizedBox(height: AppTheme.space12),
        // Greeting — large, tight letter-spacing
        Text(
          '${_greeting()}$name.',
          style: theme.textTheme.headlineLarge?.copyWith(
            fontSize: 30,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.6,
            height: 1.12,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Know what you take.',
          style: theme.textTheme.titleMedium?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w400,
            letterSpacing: -0.1,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Scan CTA — gradient pill card. The single most distinctive thing on the
// home screen; everything else is restrained.
// ---------------------------------------------------------------------------

class _ScanCta extends StatelessWidget {
  const _ScanCta();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final darkerBrand = Color.lerp(scheme.primary, scheme.scrim, 0.25)!;
    // Dynamic Type clamp — the gradient card has a fixed icon well and
    // right chevron, so unbounded text scaling breaks the layout. Cap
    // the text scaler at 1.3x on this single hero surface; long body
    // content on this screen still honors full Dynamic Type.
    final clampedScaler = MediaQuery.textScalerOf(context)
        .clamp(minScaleFactor: 1.0, maxScaleFactor: 1.3);

    return Semantics(
      button: true,
      label: 'Scan a supplement barcode to check its quality and safety',
      child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppTheme.radiusXLarge),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => GoRouter.of(context).go(Routes.scan),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [scheme.primary, darkerBrand],
            ),
            borderRadius: BorderRadius.circular(AppTheme.radiusXLarge),
            boxShadow: [
              BoxShadow(
                color: scheme.primary.withValues(alpha: 0.25),
                blurRadius: 24,
                offset: const Offset(0, 10),
                spreadRadius: -6,
              ),
            ],
          ),
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: clampedScaler),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.space20,
                AppTheme.space20,
                AppTheme.space16,
                AppTheme.space20,
              ),
              child: Row(
                children: [
                  // Icon well
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: scheme.onPrimary.withValues(alpha: 0.18),
                      borderRadius:
                          BorderRadius.circular(AppTheme.radiusLarge),
                      border: Border.all(
                        color: scheme.onPrimary.withValues(alpha: 0.22),
                        width: 0.8,
                      ),
                    ),
                    child: Icon(
                      Icons.qr_code_scanner_rounded,
                      color: scheme.onPrimary,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: AppTheme.space16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Scan a supplement',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: scheme.onPrimary,
                            letterSpacing: -0.25,
                            height: 1.22,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Check safety & interactions instantly',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                            color: scheme.onPrimary.withValues(alpha: 0.82),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppTheme.space8),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 22,
                    color: scheme.onPrimary.withValues(alpha: 0.88),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
    );
  }
}

// ---------------------------------------------------------------------------
// Search launcher — read-only PGSearchField that opens /search on tap
// ---------------------------------------------------------------------------

class _HomeSearchLauncher extends ConsumerWidget {
  const _HomeSearchLauncher();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(catalogInfoProvider).asData?.value.productCount;
    final label = count != null ? 'Search $count+ supplements…'
        : 'Search supplements…';
    return PGSearchField(
      readOnly: true,
      hintText: label,
      onTap: () => GoRouter.of(context).push(Routes.search),
    );
  }
}

// ---------------------------------------------------------------------------
// Category rail — horizontal scrolling PGFilterChip row
// ---------------------------------------------------------------------------

class _CategoryRail extends StatelessWidget {
  const _CategoryRail();

  static const _categories = <(String, String, IconData)>[
    ('Omega-3', 'omega_3', Icons.water_drop_outlined),
    ('Probiotics', 'probiotic', Icons.biotech_outlined),
    ('Multivitamin', 'multivitamin', Icons.medication_outlined),
    ('Magnesium', 'magnesium', Icons.bolt_outlined),
    ('Collagen', 'collagen', Icons.spa_outlined),
    ('Adaptogens', 'adaptogen', Icons.eco_outlined),
    ('Nootropics', 'nootropic', Icons.psychology_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppTheme.space20),
        itemCount: _categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppTheme.space8),
        itemBuilder: (context, index) {
          final (label, slug, icon) = _categories[index];
          return PGFilterChip(
            label: label,
            icon: icon,
            selected: false,
            onTap: () =>
                GoRouter.of(context).push('${Routes.search}?category=$slug'),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Profile completeness card — highlighted variant with progress
// ---------------------------------------------------------------------------

class _ProfileCompletenessCard extends StatelessWidget {
  final int completeness;
  const _ProfileCompletenessCard({required this.completeness});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return PGCard(
      variant: PGCardVariant.highlighted,
      onTap: () => GoRouter.of(context).push(Routes.profileSetup),
      padding: const EdgeInsets.all(AppTheme.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                ),
                child: Icon(
                  Icons.person_add_alt_1_rounded,
                  color: scheme.primary,
                  size: 18,
                ),
              ),
              const SizedBox(width: AppTheme.space12),
              Expanded(
                child: Text(
                  'Complete your health profile',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '$completeness%',
                style: AppTheme.numeric(
                  theme.textTheme.titleMedium!.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.space12),
          // Progress bar — rounded, 6pt tall
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusFull),
            child: LinearProgressIndicator(
              value: completeness / 100,
              minHeight: 6,
              backgroundColor: scheme.primary.withValues(alpha: 0.14),
              valueColor: AlwaysStoppedAnimation(scheme.primary),
            ),
          ),
          const SizedBox(height: AppTheme.space12),
          Text(
            'Add your meds, conditions, and allergies for personalized safety scores.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Stack health card — empty state today, will show real stack summary soon
// ---------------------------------------------------------------------------

/// Premium stack health widget — Oura-style card with animated score,
/// one-line insight, micro metrics, top issue callout, and action CTA.
/// Watches stack + safety providers reactively.
class _StackHealthWidget extends ConsumerWidget {
  const _StackHealthWidget();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final stackAsync = ref.watch(activeStackProvider);

    return stackAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (stack) {
        if (stack.isEmpty) return _buildEmptyState(context, theme, scheme);
        return _StackHealthCard(stack: stack);
      },
    );
  }

  Widget _buildEmptyState(
    BuildContext context,
    ThemeData theme,
    ColorScheme scheme,
  ) {
    return PGCard(
      onTap: () => GoRouter.of(context).go(Routes.scan),
      variant: PGCardVariant.elevated,
      padding: const EdgeInsets.all(AppTheme.space20),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            ),
            child: Icon(
              Icons.layers_outlined,
              size: 24,
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: AppTheme.space16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Build your stack',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Add supplements to see safety scores & interactions.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            size: 22,
            color: scheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

/// The actual populated stack health card — only rendered when stack is non-empty.
class _StackHealthCard extends ConsumerWidget {
  final List<UserStacksLocalData> stack;
  const _StackHealthCard({required this.stack});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final reportAsync = ref.watch(stackSafetyReportProvider);
    final synergyAsync = ref.watch(synergyReportProvider);

    // Compute safety score from report
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
              .map((m) => SynergyResult(
                    ingredient1: m.matchedIngredients.isNotEmpty
                        ? m.matchedIngredients.first
                        : m.clusterId,
                    ingredient2: m.matchedIngredients.length > 1
                        ? m.matchedIngredients[1]
                        : m.clusterName,
                    description: m.mechanism,
                    evidenceLevel: EvidenceLevel.established,
                    bonus: m.bonusPoints,
                  ))
              .toList(),
        ) ??
            const <SynergyResult>[];
        return const StackSafetyScorer().compute(
          issues: allIssues,
          synergies: synergies,
        );
      },
    );

    final score = safetyScore?.score;
    final riskTier = safetyScore?.riskTier;
    final serious = safetyScore?.seriousCount ?? 0;
    final moderate = safetyScore?.moderateCount ?? 0;
    final supplementCount =
        stack.where((e) => e.type == 'supplement').length;
    final medicationCount =
        stack.where((e) => e.type == 'medication').length;
    final interactionCount = serious + moderate;

    // Top issue — most severe interaction
    final topIssue = reportAsync.whenOrNull(
      data: (report) {
        final ordered = report.orderedWarnings;
        if (ordered.isEmpty) return null;
        final first = ordered.first;
        if (first is InteractionResult) return first.mechanism;
        return null;
      },
    );

    // Dynamic subtitle
    final subtitle = _subtitle(serious, moderate, interactionCount);
    // One-line insight
    final insight = _insight(serious, moderate, interactionCount);
    // Score glow color
    final glowColor = _glowColor(score);

    return PGCard(
      variant: PGCardVariant.elevated,
      onTap: () => GoRouter.of(context).go(Routes.stack),
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          // ---- Header + Score + Insight ----
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.space20,
              AppTheme.space20,
              AppTheme.space20,
              AppTheme.space16,
            ),
            child: Column(
              children: [
                // Title row
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Stack Health',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: glowColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Animated score ring with glow
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: score != null
                            ? [
                                BoxShadow(
                                  color: glowColor.withValues(alpha: 0.22),
                                  blurRadius: 20,
                                  spreadRadius: 2,
                                ),
                              ]
                            : null,
                      ),
                      child: PGScoreRing(
                        score: score?.toDouble(),
                        size: 64,
                        strokeWidth: 5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppTheme.space12),
                // One-line insight
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.space12,
                    vertical: AppTheme.space8,
                  ),
                  decoration: BoxDecoration(
                    color: glowColor.withValues(alpha: 0.08),
                    borderRadius:
                        BorderRadius.circular(AppTheme.radiusSmall),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _insightIcon(serious),
                        size: 14,
                        color: glowColor,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          insight,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: glowColor,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ---- Micro metrics row ----
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.space20,
              vertical: AppTheme.space12,
            ),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              border: Border(
                top: BorderSide(
                  color: scheme.outlineVariant,
                  width: 0.5,
                ),
              ),
            ),
            child: Row(
              children: [
                _MicroMetric(
                  icon: Icons.medication_outlined,
                  label: '$supplementCount supplements',
                  color: scheme.primary,
                ),
                const SizedBox(width: AppTheme.space16),
                _MicroMetric(
                  icon: Icons.local_pharmacy_outlined,
                  label: '$medicationCount medications',
                  color: AppTheme.info,
                ),
                const SizedBox(width: AppTheme.space16),
                _MicroMetric(
                  icon: interactionCount > 0
                      ? Icons.warning_amber_rounded
                      : Icons.check_circle_outline,
                  label: interactionCount > 0
                      ? '$interactionCount interaction${interactionCount == 1 ? '' : 's'}'
                      : 'No conflicts',
                  color: interactionCount > 0
                      ? AppTheme.severityCaution
                      : AppTheme.severitySafe,
                ),
              ],
            ),
          ),

          // ---- Top issue callout (conditional) ----
          if (topIssue != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(
                AppTheme.space20,
                AppTheme.space12,
                AppTheme.space20,
                AppTheme.space12,
              ),
              decoration: BoxDecoration(
                color: (serious > 0
                        ? AppTheme.severityContraindicated
                        : AppTheme.severityCaution)
                    .withValues(alpha: 0.06),
                border: Border(
                  top: BorderSide(
                    color: scheme.outlineVariant,
                    width: 0.5,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 14,
                    color: serious > 0
                        ? AppTheme.severityContraindicated
                        : AppTheme.severityCaution,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      topIssue,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

          // ---- CTA footer ----
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.space20,
              AppTheme.space12,
              AppTheme.space20,
              AppTheme.space16,
            ),
            child: Row(
              children: [
                Text(
                  interactionCount > 0 ? 'Review stack' : 'View stack',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 16,
                  color: scheme.primary,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _subtitle(int serious, int moderate, int total) {
    if (serious > 0) return 'Your stack needs attention';
    if (moderate > 0) return 'Minor optimizations available';
    return 'Your stack is well optimized';
  }

  String _insight(int serious, int moderate, int total) {
    if (serious > 0) {
      return '$serious high-risk interaction${serious == 1 ? '' : 's'} needs attention';
    }
    if (moderate > 0) {
      return '$moderate potential conflict${moderate == 1 ? '' : 's'} to review';
    }
    return 'No major interactions detected';
  }

  Color _glowColor(int? score) {
    if (score == null) return AppTheme.insufficientData;
    if (score >= 85) return AppTheme.scoreExceptional;
    if (score >= 70) return AppTheme.scoreExcellent;
    if (score >= 55) return AppTheme.scoreFair;
    return AppTheme.severityContraindicated;
  }

  IconData _insightIcon(int serious) {
    if (serious > 0) return Icons.error_outline_rounded;
    return Icons.check_circle_outline;
  }
}

/// Compact icon + label metric for the micro metrics row.
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
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                    fontSize: 10.5,
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Recent scans — loads from user_scan_history, falls back to empty state
// ---------------------------------------------------------------------------

/// Loads recent scan history joined with core product data.
/// Auto-disposes when the home screen is not visible, ensuring fresh data
/// on each visit (fixes stale scans after navigating back from scanner).
final _recentScansProvider =
    FutureProvider.autoDispose<List<_RecentScanDisplay>>((ref) async {
  final userDb = ref.watch(userDatabaseProvider);
  final coreDb = ref.watch(coreDatabaseProvider);
  final history = await userDb.getRecentScans(limit: 10);
  final results = <_RecentScanDisplay>[];
  for (final scan in history) {
    final product = await coreDb.findById(scan.dsldId);
    if (product != null) {
      results.add(
        _RecentScanDisplay(product: product, scannedAt: scan.scannedAt),
      );
    }
  }
  return results;
});

class _RecentScansSection extends ConsumerWidget {
  const _RecentScansSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final scansAsync = ref.watch(_recentScansProvider);

    return scansAsync.when(
      loading: () => _buildLoadingState(scheme),
      error: (_, __) => _buildEmptyState(theme, scheme, context),
      data: (scans) {
        if (scans.isEmpty) {
          return _buildEmptyState(theme, scheme, context);
        }
        return SizedBox(
          height: 210,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            itemCount: scans.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final scan = scans[index];
              return _RecentScanCard(
                product: scan.product,
                scannedAt: scan.scannedAt,
              );
            },
          ),
        );
      },
    );
  }

  /// Shown while the DB query is in flight — prevents the flash-of-empty-state
  /// that previously showed "Nothing scanned yet" during loading.
  static Widget _buildLoadingState(ColorScheme scheme) {
    return SizedBox(
      height: 120,
      child: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  static Widget _buildEmptyState(
    ThemeData theme,
    ColorScheme scheme,
    BuildContext context,
  ) {
    return PGCard(
      variant: PGCardVariant.recessed,
      padding: const EdgeInsets.fromLTRB(
        AppTheme.space16,
        AppTheme.space24,
        AppTheme.space16,
        AppTheme.space20,
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: scheme.surfaceContainer,
              borderRadius: BorderRadius.circular(AppTheme.radiusFull),
              border: Border.all(
                color: scheme.outlineVariant,
                width: 0.8,
              ),
            ),
            child: Icon(
              Icons.history_rounded,
              size: 26,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppTheme.space12),
          Text(
            'Nothing scanned yet',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Your last 10 scanned supplements will appear here.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppTheme.space16),
          _OutlineScanButton(
            onTap: () => GoRouter.of(context).go(Routes.scan),
          ),
        ],
      ),
    );
  }
}

/// Pairs a resolved product with its scan timestamp for display.
class _RecentScanDisplay {
  final ProductsCoreData product;
  final DateTime scannedAt;
  const _RecentScanDisplay({required this.product, required this.scannedAt});
}

/// A card-style recent scan item for the horizontal carousel.
class _RecentScanCard extends StatelessWidget {
  final ProductsCoreData product;
  final DateTime scannedAt;

  const _RecentScanCard({required this.product, required this.scannedAt});

  String _timeAgo() {
    final diff = DateTime.now().difference(scannedAt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final score = product.score100Equivalent;

    return SizedBox(
      width: 156,
      child: PGCard(
        onTap: () => GoRouter.of(context).push('/product/${product.dsldId}'),
        padding: const EdgeInsets.all(AppTheme.space12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product image (OFF photo or branded placeholder)
            Center(
              child: ProductImage(
                dsldId: product.dsldId,
                upc: product.upcSku,
                productName: product.productName,
                brandName: product.brandName ?? '',
                formFactor: product.formFactor,
                score: score,
                size: 48,
              ),
            ),
            const SizedBox(height: AppTheme.space6),
            // Score ring centered
            Center(
              child: PGScoreRing(
                score: score,
                size: 40,
                strokeWidth: 3.5,
              ),
            ),
            const SizedBox(height: AppTheme.space6),
            // Product name
            Text(
              product.productName,
              style: theme.textTheme.titleSmall?.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.1,
                height: 1.25,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            // Brand
            if (product.brandName != null && product.brandName!.isNotEmpty)
              Text(
                product.brandName!,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            const Spacer(),
            // Time ago
            Text(
              _timeAgo(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OutlineScanButton extends StatelessWidget {
  final VoidCallback onTap;
  const _OutlineScanButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AnimatedContainer(
      duration: AppMotion.fast,
      curve: AppMotion.standard,
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(AppTheme.radiusFull),
        border: Border.all(color: scheme.outlineVariant, width: 0.8),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppTheme.radiusFull),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.space16,
              vertical: AppTheme.space8,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.qr_code_scanner_rounded,
                  size: 16,
                  color: scheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  'Scan your first supplement',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: scheme.primary,
                    letterSpacing: -0.05,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dynamic citation strip — reads product count & build date from DB manifest
// ---------------------------------------------------------------------------

class _DynamicCitationStrip extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogAsync = ref.watch(catalogInfoProvider);

    final info = catalogAsync.asData?.value;
    if (info == null) return const SizedBox.shrink(); // Still loading
    final sourceCount = info.productCount;
    final buildDate = info.buildDate ?? DateTime.now();

    return PGCitationStrip(
      sourceCount: sourceCount,
      updatedAt: buildDate,
      disclaimer:
          'PharmaGuide is not medical advice. Always consult your '
          'healthcare provider before starting or stopping a supplement.',
    );
  }
}
