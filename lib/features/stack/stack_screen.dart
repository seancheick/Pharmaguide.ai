import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_card.dart';
import 'package:pharmaguide/core/widgets/pg_empty_state.dart';
import 'package:pharmaguide/core/widgets/pg_haptics.dart';
import 'package:pharmaguide/core/widgets/pg_section_header.dart';
import 'package:pharmaguide/core/models/interaction_result.dart';
import 'package:pharmaguide/core/widgets/pg_score_ring.dart';
import 'package:pharmaguide/core/widgets/pg_severity_banner.dart';
import 'package:pharmaguide/core/widgets/pg_shimmer_box.dart';
import 'package:pharmaguide/services/stack/stack_safety_scorer.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/stack/providers/stack_providers.dart';
import 'package:pharmaguide/features/medications/medication_entry_screen.dart';
import 'package:pharmaguide/features/stack/widgets/nutrient_accumulation_panel.dart';
import 'package:pharmaguide/features/stack/widgets/stack_safety_banner.dart';

/// My Stack screen — shows all products in the user's supplement stack
/// with Stack Safety Score, M1 nutrient totals, and interaction alerts.
///
/// Sprint 5a wiring: tab layout + real data from [activeStackProvider],
/// premium card-based rendering, swipe-to-remove with undo snackbar.
class StackScreen extends ConsumerWidget {
  const StackScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My stack'),
          bottom: TabBar(
            labelColor: Theme.of(context).colorScheme.primary,
            unselectedLabelColor:
                Theme.of(context).colorScheme.onSurfaceVariant,
            indicatorColor: Theme.of(context).colorScheme.primary,
            indicatorSize: TabBarIndicatorSize.label,
            dividerColor: Colors.transparent,
            labelStyle: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.1,
            ),
            unselectedLabelStyle: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.1,
            ),
            tabs: const [
              Tab(text: 'Stack'),
              Tab(text: 'Wishlist'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _StackTab(),
            _WishlistTab(),
          ],
        ),
      ),
    );
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
    final mq = MediaQuery.of(context);

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
            padding: EdgeInsets.only(bottom: mq.padding.bottom + 96),
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

              // M1 nutrient accumulation panel (UL tracking)
              const Padding(
                padding: EdgeInsets.fromLTRB(
                  AppTheme.space20,
                  AppTheme.space16,
                  AppTheme.space20,
                  0,
                ),
                child: NutrientAccumulationPanel(),
              ),

              const PGSectionHeader(
                title: 'Your supplements',
                subtitle: 'Swipe left to remove',
                padding: EdgeInsets.fromLTRB(
                  AppTheme.space20,
                  AppTheme.space24,
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

    // Aggregate stack health score from safety report.
    final reportAsync = ref.watch(stackSafetyReportProvider);
    final safetyScore = reportAsync.whenOrNull(
      data: (report) {
        final allIssues = <InteractionResult>[
          ...report.medicationPairInteractions,
          ...report.medicationInteractions,
          ...report.stackInteractions,
          ...report.categoryWarnings,
        ];
        return StackSafetyScorer().compute(issues: allIssues);
      },
    );

    return PGCard(
      padding: const EdgeInsets.all(AppTheme.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Stack Health Score ring
              PGScoreRing(
                score: safetyScore?.score.toDouble(),
                size: 56,
                strokeWidth: 4,
                label: 'Safety',
              ),
              const SizedBox(width: AppTheme.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      safetyScore?.riskTier.label ?? 'Analyzing stack\u2026',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _describeLoad(stack.length),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.space12),
          // Issue counts (only shown when score is computed)
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

  String _describeLoad(int total) {
    if (total <= 3) return 'Light — well within recommended ranges';
    if (total <= 6) return 'Moderate — watch for nutrient overlap';
    if (total <= 10) return 'Heavy — review interactions carefully';
    return 'Very heavy — consult a healthcare provider';
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
      child: PGCard(
        onTap: entry.dsldId == null
            ? null
            : () => GoRouter.of(context).push('/product/${entry.dsldId}'),
        padding: const EdgeInsets.all(AppTheme.space12),
        child: Row(
          children: [
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
                    entry.name,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (entry.dosage != null || entry.frequency != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      [entry.dosage, entry.frequency]
                          .whereType<String>()
                          .where((s) => s.isNotEmpty)
                          .join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
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
// Recall alert — checks if any stack product contains a recalled ingredient.
// Hydrates dsldIds from core DB, filters has_recalled_ingredient == 1,
// shows a danger PGSeverityBanner listing affected product names.
// ---------------------------------------------------------------------------

class _RecallAlertSlot extends ConsumerWidget {
  const _RecallAlertSlot({required this.stack});
  final List<UserStacksLocalData> stack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coreDb = ref.watch(coreDatabaseProvider);
    return FutureBuilder<List<String>>(
      future: _findRecalledProducts(coreDb),
      builder: (context, snapshot) {
        final recalled = snapshot.data;
        if (recalled == null || recalled.isEmpty) {
          return const SizedBox.shrink();
        }
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
            body: recalled.length == 1
                ? '${recalled.first} contains a recalled ingredient. '
                    'Consider removing it from your stack.'
                : '${recalled.length} products contain recalled ingredients: '
                    '${recalled.join(", ")}.',
          ),
        );
      },
    );
  }

  Future<List<String>> _findRecalledProducts(CoreDatabase coreDb) async {
    final names = <String>[];
    for (final entry in stack) {
      final id = entry.dsldId;
      if (id == null || id.isEmpty) continue;
      try {
        final product = await coreDb.findById(id);
        if (product != null && product.hasRecalledIngredient == 1) {
          names.add(entry.name);
        }
      } on Exception {
        // Skip broken entries.
      }
    }
    return names;
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
