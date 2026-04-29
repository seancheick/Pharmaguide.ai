import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/models/stack_intelligence.dart';
import 'package:pharmaguide/core/widgets/pg_card.dart';
import 'package:pharmaguide/core/widgets/pg_empty_state.dart';
import 'package:pharmaguide/core/widgets/pg_haptics.dart';
import 'package:pharmaguide/core/widgets/pg_section_header.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/interaction_result.dart';
import 'package:pharmaguide/core/models/synergy_result.dart';
import 'package:pharmaguide/core/widgets/pg_score_ring.dart';
import 'package:pharmaguide/core/widgets/pg_severity_banner.dart';
import 'package:pharmaguide/core/widgets/pg_shimmer_box.dart';
import 'package:pharmaguide/services/stack/stack_safety_scorer.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/features/stack/providers/stack_providers.dart';
import 'package:pharmaguide/features/medications/medication_entry_screen.dart';
import 'package:pharmaguide/features/stack/widgets/nutrient_accumulation_panel.dart';
import 'package:pharmaguide/features/stack/widgets/stack_safety_banner.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/stack/widgets/depletion_checker_card.dart';
import 'package:pharmaguide/features/stack/widgets/share_clinician_report_button.dart';
import 'package:pharmaguide/core/widgets/pg_frosted_app_bar.dart';
import 'package:pharmaguide/features/stack/widgets/timing_advice_card.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';
import 'package:pharmaguide/services/stack/stack_intelligence_engine.dart';

/// Look up a single product from the core DB — used by stack item cards
/// to resolve brand name + score from dsldId.
final _stackProductProvider = FutureProvider.family
    .autoDispose<ProductsCoreData?, String>((ref, dsldId) async {
  final coreDb = ref.read(coreDatabaseProvider);
  return coreDb.findById(dsldId);
});

/// My Stack screen — shows all products in the user's supplement stack
/// with Stack Safety Score, M1 nutrient totals, and interaction alerts.
///
/// Sprint 5a wiring: tab layout + real data from [activeStackProvider],
/// premium card-based rendering, swipe-to-remove with undo snackbar.
class StackScreen extends ConsumerWidget {
  const StackScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        body: NestedScrollView(
          // Float-down bar so the frosted treatment fades away when the
          // user scrolls a tab body up; reappears on scroll-down. Matches
          // iOS Settings / Mail.
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            const PGFrostedAppBar(
              title: 'My stack',
              automaticallyImplyLeading: false, // tab root
              actions: [ShareClinicianReportButton()],
            ),
            // Pinned TabBar directly under the frosted bar — same iOS
            // Settings/Wallet pattern.
            SliverPersistentHeader(
              pinned: true,
              delegate: _StackTabBarDelegate(
                tabBar: TabBar(
                  labelColor: scheme.primary,
                  unselectedLabelColor: scheme.onSurfaceVariant,
                  indicatorColor: scheme.primary,
                  indicatorSize: TabBarIndicatorSize.label,
                  dividerColor: Colors.transparent,
                  labelStyle: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.1,
                  ),
                  unselectedLabelStyle: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.1,
                  ),
                  tabs: const [
                    Tab(text: 'Stack'),
                    Tab(text: 'Wishlist'),
                  ],
                ),
                background: scheme.surface,
              ),
            ),
          ],
          body: const TabBarView(
            children: [
              _StackTab(),
              _WishlistTab(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pins the stack-tab TabBar directly under [PGFrostedAppBar] so the
/// tab strip stays visible while either tab body scrolls. Background
/// color matches the page material so the strip blends with the bar
/// when the frosted treatment fades in on scroll.
class _StackTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  final Color background;

  const _StackTabBarDelegate({
    required this.tabBar,
    required this.background,
  });

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Material(
      color: background,
      elevation: 0,
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(covariant _StackTabBarDelegate oldDelegate) {
    return oldDelegate.tabBar != tabBar || oldDelegate.background != background;
  }
}

// ---------------------------------------------------------------------------
// Stack tab — nutrient panel + product list
// ---------------------------------------------------------------------------

class _StackTab extends ConsumerWidget {
  const _StackTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stackAsync = ref.watch(activeStackProvider);
    final mq = MediaQuery.paddingOf(context);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(activeStackProvider);
        await ref.read(activeStackProvider.future);
      },
      child: stackAsync.when(
        loading: () => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(AppTheme.space20),
          children: const [
            PGShimmerCard(height: 96),
            SizedBox(height: AppTheme.space12),
            PGShimmerCard(height: 72),
            SizedBox(height: AppTheme.space12),
            PGShimmerCard(height: 72),
          ],
        ),
        error: (error, _) => _StackErrorView(
          onRetry: () => ref.invalidate(activeStackProvider),
        ),
        data: (stack) {
          if (stack.isEmpty) {
            return const _StackEmptyView();
          }
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: EdgeInsets.only(bottom: mq.bottom + 96),
            children: [
              // Summary card — total count, quick stats
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.space20,
                  AppTheme.space16,
                  AppTheme.space20,
                  0,
                ),
                child: _StackSummaryCard(stack: stack),
              ),

              // Recall alert — danger banner if any stack product
              // contains a recalled ingredient.
              _RecallAlertSlot(stack: stack),

              // M4 aggregated safety banner — consumes the
              // stackSafetyReportProvider and renders itself as
              // SizedBox.shrink when the report is clean, so a
              // no-warning stack never eats vertical space.
              const _StackSafetyBannerSlot(),

              // Gentle nudge if the user hasn't filled in their profile —
              // without conditions / medications we can't personalize
              // warnings, so let them know what they're missing.
              const _ProfileNudgeSlot(),

              // Your supplements list — first, so user sees what's in their stack
              const PGSectionHeader(
                title: 'Your supplements',
                subtitle: 'Swipe left to remove',
                padding: EdgeInsets.fromLTRB(
                  AppTheme.space20,
                  AppTheme.space16,
                  AppTheme.space20,
                  AppTheme.space12,
                ),
              ),

              // Product list
              ...stack.map((entry) => Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppTheme.space20,
                      0,
                      AppTheme.space20,
                      AppTheme.space12,
                    ),
                    child: _StackItemCard(entry: entry),
                  )),

              // Timing optimization advice
              const _TimingAdviceSlot(),

              // Depletion checker — nutrients depleted by medications
              const _DepletionSlot(),

              // Nutrient accumulation panel (UL tracking)
              const Padding(
                padding: EdgeInsets.fromLTRB(
                  AppTheme.space20,
                  AppTheme.space16,
                  AppTheme.space20,
                  0,
                ),
                child: NutrientAccumulationPanel(),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Summary card — shows total count and daily supplement load
// ---------------------------------------------------------------------------

class _StackSummaryCard extends ConsumerWidget {
  final List<UserStacksLocalData> stack;
  const _StackSummaryCard({required this.stack});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final supplementCount =
        stack.where((e) => e.type == 'supplement').length;
    final medicationCount =
        stack.where((e) => e.type == 'medication').length;

    // Shared stack-health computation — same source of truth used by the home
    // card so both screens stay aligned on the user's current stack status.
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
              .map((m) => SynergyResult(
                    ingredient1: m.matchedIngredients.isNotEmpty
                        ? m.matchedIngredients.first : m.clusterId,
                    ingredient2: m.matchedIngredients.length > 1
                        ? m.matchedIngredients[1] : m.clusterName,
                    description: m.mechanism,
                    evidenceLevel: EvidenceLevel.established,
                    bonus: m.bonusPoints,
                  ))
              .toList(),
        ) ?? const <SynergyResult>[];
        return const StackSafetyScorer().compute(
          issues: allIssues,
          synergies: synergies,
        );
      },
    );

    // Keep the ring here for the fuller Stack view; Home uses the status label
    // more prominently. If still loading, show a shimmering ring with
    // "Analyzing stack…".
    final score = safetyScore?.score.toDouble();
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
    final isAnalyzing =
        reportAsync.isLoading || synergyAsync.isLoading || recallAsync.isLoading;

    return PGCard(
      padding: const EdgeInsets.all(AppTheme.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Stack health score (safety score) — mirrors homepage.
              PGScoreRing(
                score: score,
                size: 56,
                strokeWidth: 4,
              ),
              const SizedBox(width: AppTheme.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isAnalyzing
                          ? 'Analyzing stack\u2026'
                          : status != null
                              ? status.label
                              : 'No data yet',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _describeSummary(intelligence),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    // (Status label intentionally not repeated here — the
                    // healthLabel.label already renders as the card title
                    // above. Repeating it as 'Status: ...' was visible
                    // duplication.)
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.space12),
          // Issue counts
          if (safetyScore != null &&
              (safetyScore.seriousCount > 0 ||
                  safetyScore.moderateCount > 0)) ...[
            Text(
              '${safetyScore.seriousCount} serious \u00B7 '
              '${safetyScore.moderateCount} cautions \u00B7 '
              '${safetyScore.monitorCount} monitor',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppTheme.space12),
          ],
          Row(
            children: [
              _CountChip(
                icon: Icons.medication_outlined,
                label: 'Supplements',
                count: supplementCount,
              ),
              const SizedBox(width: AppTheme.space8),
              _CountChip(
                icon: Icons.local_pharmacy_outlined,
                label: 'Medications',
                count: medicationCount,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _describeSummary(StackIntelligence? intelligence) {
    if (intelligence == null) {
      return 'Reviewing interactions, recall alerts, and nutrient overlap.';
    }

    switch (intelligence.tier) {
      case StackTier.unsafe:
        if (intelligence.hasBannedIngredient) {
          return 'Banned ingredient found — review immediately.';
        }
        if (intelligence.hasRecalledIngredient) {
          return 'Recalled ingredient found — review immediately.';
        }
        if (intelligence.hasContraindicatedInteraction) {
          return 'Contraindicated interaction found — review immediately.';
        }
        return 'High-risk issue found — review immediately.';
      case StackTier.concerning:
        if (intelligence.interactionCount > 0 &&
            intelligence.nutrientWarningCount > 0) {
          return '${intelligence.interactionCount} interaction'
              '${intelligence.interactionCount == 1 ? '' : 's'} and '
              '${intelligence.nutrientWarningCount} nutrient warning'
              '${intelligence.nutrientWarningCount == 1 ? '' : 's'} need review.';
        }
        if (intelligence.interactionCount > 0) {
          return '${intelligence.interactionCount} interaction'
              '${intelligence.interactionCount == 1 ? '' : 's'} need review.';
        }
        if (intelligence.nutrientWarningCount > 0) {
          return '${intelligence.nutrientWarningCount} nutrient warning'
              '${intelligence.nutrientWarningCount == 1 ? '' : 's'} need review.';
        }
        return 'Important issues found — review this stack.';
      case StackTier.decent:
        if (intelligence.interactionCount > 0) {
          return '${intelligence.interactionCount} interaction'
              '${intelligence.interactionCount == 1 ? '' : 's'} worth reviewing.';
        }
        if (intelligence.nutrientWarningCount > 0) {
          return '${intelligence.nutrientWarningCount} nutrient warning'
              '${intelligence.nutrientWarningCount == 1 ? '' : 's'} worth reviewing.';
        }
        return 'Some concerns are worth reviewing.';
      case StackTier.solid:
      case StackTier.optimized:
        return 'No major safety issues detected right now.';
      case StackTier.incomplete:
        return 'Add more information to diagnose this stack.';
    }
  }
}

class _CountChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;

  const _CountChip({
    required this.icon,
    required this.label,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.space12,
          vertical: AppTheme.space12,
        ),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          border: Border.all(color: scheme.outlineVariant, width: 0.8),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: scheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontSize: 12,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              '$count',
              style: AppTheme.numeric(
                theme.textTheme.titleMedium!.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Stack item card — dismissible with undo
// ---------------------------------------------------------------------------

class _StackItemCard extends ConsumerWidget {
  final UserStacksLocalData entry;
  const _StackItemCard({required this.entry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isMedication = entry.type == 'medication';

    return Dismissible(
      key: ValueKey('stack_${entry.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppTheme.space20),
        decoration: BoxDecoration(
          color: scheme.error.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        ),
        child: Icon(
          Icons.delete_outline_rounded,
          color: scheme.error,
          size: 24,
        ),
      ),
      onDismissed: (_) async {
        await PGHaptics.press();
        final actions = ref.read(stackActionsProvider);
        try {
          await actions.remove(entry.id);
        } on Exception {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not remove.')),
          );
          return;
        }
        if (!context.mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        messenger.clearSnackBars();
        messenger.showSnackBar(
          SnackBar(
            content: Text('Removed ${entry.name}'),
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () async {
                try {
                  await actions.restore(entry.id);
                } on Exception {
                  // Silent.
                }
              },
            ),
          ),
        );
      },
      child: _StackItemCardContent(
        entry: entry,
        isMedication: isMedication,
      ),
    );
  }
}

/// Inner content of a stack item — resolves product name + brand from
/// the core DB when a dsldId is present, so "Multivitamin" becomes
/// "ONE Multivitamin · Pure Encapsulations".
class _StackItemCardContent extends ConsumerWidget {
  final UserStacksLocalData entry;
  final bool isMedication;
  const _StackItemCardContent({
    required this.entry,
    required this.isMedication,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // Resolve product details from core DB for richer display.
    String displayName = entry.name;
    String? brandName;
    double? score;

    if (entry.dsldId != null) {
      final productAsync = ref.watch(
        _stackProductProvider(entry.dsldId!),
      );
      final product = productAsync.asData?.value;
      if (product != null) {
        displayName = product.productName;
        brandName = product.brandName;
        score = product.score100Equivalent;
      }
    }

    return PGCard(
        onTap: entry.dsldId == null
            ? null
            : () => GoRouter.of(context).push('/product/${entry.dsldId}'),
        padding: const EdgeInsets.all(AppTheme.space12),
        child: Row(
          children: [
            // Score ring for supplements, icon for medications
            if (!isMedication && score != null)
              PGScoreRing(
                score: score,
                size: 44,
                strokeWidth: 3.5,
              )
            else
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isMedication
                      ? AppTheme.info.withValues(alpha: 0.12)
                      : scheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                ),
                child: Icon(
                  isMedication
                      ? Icons.local_pharmacy_outlined
                      : Icons.medication_outlined,
                  size: 20,
                  color: isMedication ? AppTheme.info : scheme.primary,
                ),
              ),
            const SizedBox(width: AppTheme.space12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    displayName,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (brandName != null && brandName.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      brandName,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (entry.dosage != null || entry.frequency != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      [entry.dosage, entry.frequency]
                          .whereType<String>()
                          .where((s) => s.isNotEmpty)
                          .join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (entry.dsldId != null)
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: scheme.onSurfaceVariant,
              ),
          ],
        ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state — big call to action
// ---------------------------------------------------------------------------

class _StackEmptyView extends StatelessWidget {
  const _StackEmptyView();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppTheme.space20,
        AppTheme.space48,
        AppTheme.space20,
        AppTheme.space48,
      ),
      children: [
        PGEmptyState(
          icon: Icons.layers_outlined,
          title: 'Your stack is empty',
          description:
              'Add the supplements you take regularly to see nutrient totals, '
              'UL warnings, and interactions in one place.',
          actionLabel: 'Scan a supplement',
          onAction: () => GoRouter.of(context).go(Routes.scan),
          padding: const EdgeInsets.fromLTRB(
            AppTheme.space20,
            AppTheme.space32,
            AppTheme.space20,
            AppTheme.space24,
          ),
        ),
        const SizedBox(height: AppTheme.space8),
        Center(
          child: TextButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const MedicationEntryScreen(),
              ),
            ),
            icon: const Icon(Icons.medication_outlined, size: 18),
            label: const Text('Add medications manually'),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Error state
// ---------------------------------------------------------------------------

class _StackErrorView extends StatelessWidget {
  final VoidCallback onRetry;
  const _StackErrorView({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppTheme.space20),
      children: [
        PGEmptyState(
          icon: Icons.cloud_off_outlined,
          title: 'Could not load your stack',
          description:
              'Pull to refresh, or try again once you have connectivity.',
          actionLabel: 'Retry',
          onAction: onRetry,
          variant: PGEmptyStateVariant.error,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Recall alert — watches recalledIngredientsReportProvider (canonical provider)
// instead of duplicating DB lookups via FutureBuilder. Shows a danger banner
// when any stack product contains a recalled ingredient.
// ---------------------------------------------------------------------------

class _RecallAlertSlot extends ConsumerWidget {
  const _RecallAlertSlot({required this.stack});
  final List<UserStacksLocalData> stack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportAsync = ref.watch(recalledIngredientsReportProvider);
    return reportAsync.when(
      data: (report) {
        if (report.isEmpty) return const SizedBox.shrink();
        final ordered = report.orderedViolations;
        final primary = ordered.first;
        final names = ordered.map((v) => v.productName).toList(growable: false);
        final body = ordered.length == 1
            ? primary.bannerMessage
            : '${ordered.length} products need review. ${primary.bannerMessage} '
                'Plus ${ordered.length - 1} more: ${names.skip(1).join(", ")}.';
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTheme.space20,
            AppTheme.space12,
            AppTheme.space20,
            0,
          ),
          child: PGSeverityBanner(
            tone: PGBannerTone.danger,
            title: 'Recall Alert',
            body: body,
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

// ---------------------------------------------------------------------------
// Safety banner slot — watches stackSafetyReportProvider in its own
// ConsumerWidget so the surrounding _StackTab doesn't rebuild on every
// safety-report change. Collapses to SizedBox.shrink during loading,
// error, or when the report is clean (no warnings).
// ---------------------------------------------------------------------------

class _StackSafetyBannerSlot extends ConsumerWidget {
  const _StackSafetyBannerSlot();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportAsync = ref.watch(stackSafetyReportProvider);
    return reportAsync.when(
      data: (report) {
        if (report.isEmpty) return const SizedBox.shrink();
        return StackSafetyBanner(
          report: report,
          margin: kStackSafetyBannerMargin,
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

// ---------------------------------------------------------------------------
// Profile nudge — shown when the user has no conditions / medications
// in their profile. Without those we can't personalize interaction
// warnings, so a gentle prompt to finish onboarding is more useful
// than a loud pile of generic alerts. Hides itself once the profile
// has any condition or drug class populated.
// ---------------------------------------------------------------------------

class _ProfileNudgeSlot extends ConsumerWidget {
  const _ProfileNudgeSlot();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final hasProfile =
        profile.conditions.isNotEmpty || profile.drugClasses.isNotEmpty;
    if (hasProfile) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.space20,
        AppTheme.space12,
        AppTheme.space20,
        0,
      ),
      child: PGSeverityBanner(
        tone: PGBannerTone.neutral,
        title: 'Personalize your stack',
        body: 'Add your health conditions and medications to see '
            'warnings that actually apply to you.',
        actionLabel: 'Complete profile',
        onAction: () => GoRouter.of(context).push(Routes.profileSetup),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Timing advice slot — watches stackSafetyReportProvider for timing
// optimizations. Collapses to SizedBox.shrink when there are none.
// ---------------------------------------------------------------------------

class _TimingAdviceSlot extends ConsumerWidget {
  const _TimingAdviceSlot();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportAsync = ref.watch(stackSafetyReportProvider);
    return reportAsync.when(
      data: (report) {
        if (!report.hasTimingAdvice) return const SizedBox.shrink();
        return TimingAdviceCard(
          optimizations: report.timingOptimizations,
          margin: const EdgeInsets.fromLTRB(
            AppTheme.space20,
            AppTheme.space12,
            AppTheme.space20,
            0,
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

// ---------------------------------------------------------------------------
// Depletion slot — watches depletionReportProvider for medication-induced
// nutrient depletions. Collapses when user has no medications.
// ---------------------------------------------------------------------------

class _DepletionSlot extends ConsumerWidget {
  const _DepletionSlot();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final depletionAsync = ref.watch(depletionReportProvider);
    return depletionAsync.when(
      data: (depletions) {
        if (depletions.isEmpty) return const SizedBox.shrink();
        return DepletionCheckerCard(
          depletions: depletions,
          margin: const EdgeInsets.fromLTRB(
            AppTheme.space20,
            AppTheme.space12,
            AppTheme.space20,
            0,
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

// ---------------------------------------------------------------------------
// Wishlist tab — placeholder until Sprint 5a wishlist wiring
// ---------------------------------------------------------------------------

class _WishlistTab extends StatelessWidget {
  const _WishlistTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.space20,
        AppTheme.space48,
        AppTheme.space20,
        AppTheme.space48,
      ),
      children: [
        PGEmptyState(
          icon: Icons.bookmark_border_rounded,
          title: 'No saved products',
          description:
              'Save products from search results or scan details to compare '
              'them later.',
          actionLabel: 'Browse supplements',
          onAction: () => GoRouter.of(context).push(Routes.search),
        ),
      ],
    );
  }
}
