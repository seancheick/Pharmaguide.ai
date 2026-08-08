import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:drift/drift.dart' show Value;
import 'package:intl/intl.dart';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/models/stack_intelligence.dart';
import 'package:pharmaguide/core/components/pg_product_thumbnail.dart';
import 'package:pharmaguide/core/components/pg_eyebrow.dart';
import 'package:pharmaguide/core/components/pg_score_line.dart';
import 'package:pharmaguide/core/components/pg_type_badge.dart';
import 'package:pharmaguide/core/utils/stack_intelligence_helpers.dart';
import 'package:pharmaguide/core/components/pg_segmented_control.dart';
import 'package:pharmaguide/core/components/pg_toast.dart';
import 'package:pharmaguide/core/theme/v2/v2_motion.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/core/widgets/pg_frosted_nav_bar.dart';
import 'package:pharmaguide/core/widgets/pg_modal.dart';
import 'package:pharmaguide/core/widgets/pg_severity_banner.dart';
import 'package:pharmaguide/core/widgets/product_image.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';
import 'package:pharmaguide/core/scoring/coverage.dart';
import 'package:pharmaguide/core/scoring/catalog_product_semantics.dart';
import 'package:pharmaguide/core/widgets/pg_haptics.dart';
import 'package:pharmaguide/features/stack/providers/medication_identity_providers.dart';
import 'package:pharmaguide/features/stack/providers/stack_providers.dart';
import 'package:pharmaguide/features/stack/providers/stack_reminder_providers.dart';
import 'package:pharmaguide/features/stack/v2/widgets/medication_details_sheet.dart';
import 'package:pharmaguide/features/stack/v2/widgets/pg_depletion_card.dart';
import 'package:pharmaguide/services/stack/depletion_checker.dart'
    show MedNutrientLoadStatus;
import 'package:pharmaguide/services/stack/depletion_watch.dart'
    show DepletionWatchStatus;
import 'package:pharmaguide/features/stack/v2/widgets/pg_timing_guidance_card.dart';
import 'package:pharmaguide/services/stack/timing_guidance_builder.dart';
import 'package:pharmaguide/features/stack/v2/widgets/stack_safety_details_sheet.dart';
import 'package:pharmaguide/features/stack/providers/coverage_report_provider.dart';
import 'package:pharmaguide/features/stack/widgets/nutrient_accumulation_panel.dart';
import 'package:pharmaguide/features/stack/widgets/stack_coverage_card.dart';
import 'package:pharmaguide/features/stack/widgets/share_clinician_report_button.dart';
import 'package:pharmaguide/features/stack/widgets/stack_safety_banner.dart';
import 'package:pharmaguide/features/stack/widgets/stack_health_fallback_display.dart';
import 'package:pharmaguide/services/auth_state_service.dart';
import 'package:pharmaguide/services/crash_reporting_service.dart';
import 'package:pharmaguide/services/medications/medication_display_name.dart';
import 'package:pharmaguide/services/medications/medication_identity_status.dart';

/// Resolves stack rows back to catalog products so v2 rows render the
/// canonical product name, brand, thumbnail, and score.
final _stackProductProvider = FutureProvider.family
    .autoDispose<ProductsCoreData?, String>((ref, dsldId) async {
      final coreDb = ref.watch(coreDatabaseProvider);
      return coreDb.findById(dsldId);
    });

typedef StackCatalogScoreDisplay = ({
  int score,
  String? qualityTier,
  String? confidence,
});

/// Returns a score only when the current catalog row satisfies the public
/// score contract. Saved stack values are deliberately not accepted here:
/// they can outlive a safety suppression or a failed reassessment.
@visibleForTesting
StackCatalogScoreDisplay? stackCatalogScoreDisplayFor(
  ProductsCoreData? product,
) {
  if (product == null ||
      catalogProductIsBlocked(product) ||
      catalogProductIsNotScored(product) ||
      isLowCoverage(product.mappedCoverage)) {
    return null;
  }
  final score = product.qualityScoreV4100;
  if (score == null) return null;
  return (
    score: score.round(),
    qualityTier: product.qualityTier,
    confidence: product.v4Confidence,
  );
}

/// v2 Stack screen — production stack surface with three sub-tabs
/// via [PGSegmentedControl]:
///
///   Stack | Nutrients | Wishlist
///
/// Sean 2026-05-15: nutrients live in their own segment so each tab
/// does one clean job. Production wiring keeps the same providers;
/// only the container changes.
///
/// Segmented control sits below the app bar with a sliding pill
/// highlighter and 280ms emphasized transitions.
class StackV2Screen extends StatefulWidget {
  final int selectedIndex;
  final ValueChanged<int>? onDestinationSelected;
  final bool showNavBar;
  final bool showPreviewFixtures;

  /// Initial segment: 0 = Stack, 1 = Nutrients, 2 = Wishlist.
  /// Used by deep links (`/stack?tab=wishlist`) after a save toast.
  final int initialSegment;

  const StackV2Screen({
    super.key,
    this.selectedIndex = 1, // Stack tab is index 1 in v2 nav order
    this.onDestinationSelected,
    this.showNavBar = true,
    this.showPreviewFixtures = false,
    this.initialSegment = 0,
  });

  @override
  State<StackV2Screen> createState() => _StackV2ScreenState();
}

class _StackV2ScreenState extends State<StackV2Screen> {
  late int _segment;

  @override
  void initState() {
    super.initState();
    _segment = widget.initialSegment.clamp(0, 2);
  }

  @override
  void didUpdateWidget(covariant StackV2Screen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSegment != widget.initialSegment) {
      _segment = widget.initialSegment.clamp(0, 2);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: v2SystemOverlay(context),
      child: Scaffold(
        extendBody: true,
        appBar: _StackAppBar(
          segment: _segment,
          onSegmentChanged: (i) => setState(() => _segment = i),
        ),
        body: AnimatedSwitcher(
          duration: V2Motion.base,
          switchInCurve: V2Motion.emphasized,
          switchOutCurve: V2Motion.smooth,
          transitionBuilder: (child, animation) {
            // Fade + tiny lift so the panes feel like they slide in,
            // not just hard-cut. Stays within the perf budget — no
            // gradient/blur animation.
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.02),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            );
          },
          child: KeyedSubtree(
            key: ValueKey(_segment),
            child: switch (_segment) {
              0 => _StackTab(showPreviewFixtures: widget.showPreviewFixtures),
              1 => _NutrientsTab(
                showPreviewFixtures: widget.showPreviewFixtures,
              ),
              _ => const _WishlistTab(),
            },
          ),
        ),
        bottomNavigationBar: widget.showNavBar
            ? PGFrostedNavBar(
                selectedIndex: widget.selectedIndex,
                onDestinationSelected: widget.onDestinationSelected ?? (_) {},
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
              )
            : null,
      ),
    );
  }
}

// =============================================================================
// App bar — "My stack" title + add-medication + share-clinician trailing.
// Segmented control sits in the bar's bottom slot.
// =============================================================================

class _StackAppBar extends StatelessWidget implements PreferredSizeWidget {
  final int segment;
  final ValueChanged<int> onSegmentChanged;

  const _StackAppBar({required this.segment, required this.onSegmentChanged});

  @override
  // 56pt AppBar default + 16 gap + 44 segmented control + 16 gap = 132
  Size get preferredSize => const Size.fromHeight(132);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      automaticallyImplyLeading: false,
      titleSpacing: V2Spacing.space24,
      title: Text('My stack', style: V2Typography.title(color: context.v2.fg)),
      actions: [
        IconButton(
          icon: Icon(Icons.add_rounded, color: context.v2.fg),
          tooltip: 'Add to stack',
          onPressed: () => unawaited(_showAddToStackSheet(context)),
        ),
        // Reuse production `ShareClinicianReportButton` — wraps the full
        // profile/stack/safety snapshot + share_plus flow. IconTheme
        // override matches the v2 app-bar foreground (context.v2.fg).
        IconTheme(
          data: IconThemeData(color: context.v2.fg),
          child: const ShareClinicianReportButton(),
        ),
        const SizedBox(width: V2Spacing.space8),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(76),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            V2Spacing.space24,
            V2Spacing.space16,
            V2Spacing.space24,
            V2Spacing.space16,
          ),
          child: PGSegmentedControl(
            segments: const ['Stack', 'Nutrients', 'Wishlist'],
            selectedIndex: segment,
            onChanged: onSegmentChanged,
          ),
        ),
      ),
    );
  }
}

enum _StackAddChoice { supplement, medication }

Future<void> _showAddToStackSheet(BuildContext context) async {
  final choice = await PGModal.bottomSheet<_StackAddChoice>(
    context: context,
    builder: (_) => const _AddToStackSheet(),
  );
  if (!context.mounted || choice == null) return;

  switch (choice) {
    case _StackAddChoice.supplement:
      unawaited(GoRouter.of(context).push(Routes.search));
      return;
    case _StackAddChoice.medication:
      unawaited(GoRouter.of(context).push(Routes.medicationEntry));
      return;
  }
}

class _AddToStackSheet extends StatelessWidget {
  const _AddToStackSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          V2Spacing.space24,
          V2Spacing.space8,
          V2Spacing.space24,
          V2Spacing.space24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PGEyebrow('Add to stack'),
            const SizedBox(height: V2Spacing.space8),
            Text(
              'What are you adding?',
              style: V2Typography.titleSm(color: context.v2.fg),
            ),
            const SizedBox(height: V2Spacing.space16),
            _StackAddOption(
              icon: Icons.spa_outlined,
              title: 'Supplement',
              subtitle: 'Search products and add from the product page.',
              onTap: () {
                HapticFeedback.selectionClick();
                Navigator.of(context).pop(_StackAddChoice.supplement);
              },
            ),
            const SizedBox(height: V2Spacing.space12),
            _StackAddOption(
              icon: Icons.medication_outlined,
              title: 'Medication',
              subtitle: 'Add a medication for interaction checks.',
              onTap: () {
                HapticFeedback.selectionClick();
                Navigator.of(context).pop(_StackAddChoice.medication);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _StackAddOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _StackAddOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(V2Spacing.space16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
            border: Border.all(color: context.v2.outline),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: context.v2.accentTint,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: context.v2.accent, size: 22),
              ),
              const SizedBox(width: V2Spacing.space16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: V2Typography.bodyMedium(color: context.v2.fg),
                    ),
                    const SizedBox(height: V2Spacing.space4),
                    Text(
                      subtitle,
                      style: V2Typography.caption(color: context.v2.fgMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: V2Spacing.space12),
              Icon(Icons.chevron_right_rounded, color: context.v2.fgSubtle),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Stack tab — summary card + supplements list.
// =============================================================================

class _StackTab extends ConsumerStatefulWidget {
  final bool showPreviewFixtures;

  const _StackTab({required this.showPreviewFixtures});

  @override
  ConsumerState<_StackTab> createState() => _StackTabState();
}

class _StackTabState extends ConsumerState<_StackTab> {
  /// Sentry PHARMAGUIDE-10 ("A dismissed Dismissible widget is still part
  /// of the tree"): removal is async (DB + provider stream), so for a frame
  /// the dismissed row was still in the rebuilt list. Hide dismissed ids
  /// synchronously; unhide on failure so the row reappears with the error.
  final Set<String> _dismissedIds = <String>{};

  /// Fixture used only when no real stack rows have loaded (cold cache
  /// + zero-state during the first frame). Production rows replace
  /// these once activeStackProvider resolves.
  static const _fixtureItems = <_StackEntry>[
    _StackEntry(
      id: 'fixture-1',
      name: 'Ultimate Omega 2X with Vitamin D3 + K2',
      brand: 'Nordic Naturals',
      score: 84,
      dosage: '2 softgels',
      frequency: 'with food',
    ),
    _StackEntry(
      id: 'fixture-2',
      name: 'Basic Nutrients 2/Day',
      brand: 'Thorne',
      score: 91,
      dosage: '2 capsules',
      frequency: 'morning',
    ),
    _StackEntry(
      id: 'fixture-3',
      name: 'L-Theanine 200mg',
      brand: 'NOW Foods',
      score: 72,
      dosage: '1 capsule',
      frequency: 'as needed',
    ),
    _StackEntry(
      id: 'fixture-4',
      name: 'Atorvastatin 20mg',
      brand: null,
      score: null,
      dosage: '20 mg',
      frequency: 'evening',
      isMedication: true,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final showPreviewFixtures = widget.showPreviewFixtures;
    ref.watch(medicationIdentityHydrationProvider);
    final stackAsync = ref.watch(activeStackProvider);
    final identityAssessments = ref
        .watch(medicationIdentityAssessmentsProvider)
        .asData
        ?.value;
    final realItems = stackAsync.asData?.value
        .map(
          (row) => _StackEntry(
            id: row.id,
            name: row.name,
            brand: null, // production resolves brand via core DB
            score: null, // ditto for score
            dosage: row.dosage,
            frequency: row.frequency,
            startedAt: row.startedAt,
            reminderMinutes: row.reminderMinutes,
            isMedication: row.type == 'medication',
            medicationIdentity: row.type == 'medication'
                ? MedicationIdentitySnapshot.fromStackRow(row)
                : null,
            medicationIdentityAssessment: row.type == 'medication'
                ? (identityAssessments == null
                      ? null
                      : identityAssessments[row.id])
                : null,
            // Phase 11.7j.5 — Sean 2026-05-16: thread dsldId so the
            // row tap can navigate to /product/<dsldId>. Null for
            // medications.
            dsldId: row.dsldId,
          ),
        )
        .toList();

    // Only show fixture rows during the initial-load phase
    // (`!hasValue`). Once the provider has emitted any value —
    // including an empty list after the user clears their stack —
    // render the real items or the empty-state widget below.
    final bool hasLoadedOnce = stackAsync.hasValue;
    // Drop optimistically-dismissed rows; ids the provider no longer
    // emits are pruned so the set can't grow stale.
    _dismissedIds.retainAll(
      (realItems ?? const <_StackEntry>[]).map((e) => e.id).toSet(),
    );
    final visibleItems = realItems
        ?.where((e) => !_dismissedIds.contains(e.id))
        .toList();
    final List<_StackEntry> items;
    if (hasLoadedOnce) {
      items = visibleItems ?? const <_StackEntry>[];
    } else if (showPreviewFixtures) {
      items = _fixtureItems;
    } else {
      items = const <_StackEntry>[];
    }
    final isShowingFixture = !hasLoadedOnce && showPreviewFixtures;
    final isLoading = !hasLoadedOnce && !showPreviewFixtures;
    final bool isEmpty = hasLoadedOnce && items.isEmpty;
    final medications = items.where((item) => item.isMedication).toList();
    final supplements = items.where((item) => !item.isMedication).toList();

    Future<void> removeEntry(_StackEntry entry) async {
      // Hide the row in the same frame the Dismissible completes. The DB
      // update is async, so leaving it visible causes Flutter to rebuild a
      // dismissed widget with the same key.
      setState(() => _dismissedIds.add(entry.id));
      final actions = ref.read(stackActionsProvider);
      try {
        await actions.remove(entry.id);
      } on Exception {
        if (!context.mounted) return;
        setState(() => _dismissedIds.remove(entry.id));
        PGToast.show(
          context,
          'Could not remove.',
          variant: PGToastVariant.error,
        );
        return;
      }
      if (!context.mounted) return;
      final removedName = entry.isMedication
          ? medicationDisplayName(entry.name)
          : entry.name;
      PGToast.show(
        context,
        'Removed $removedName',
        variant: PGToastVariant.info,
        duration: const Duration(seconds: 4),
        actionLabel: 'Undo',
        onAction: () async {
          try {
            await actions.restore(entry.id);
          } on Exception {
            // silent
          }
        },
      );
    }

    Widget stackRow(_StackEntry entry) => Padding(
      padding: const EdgeInsets.fromLTRB(
        V2Spacing.space24,
        0,
        V2Spacing.space24,
        V2Spacing.space12,
      ),
      child: _StackItemRow(
        entry: entry,
        onRemoved: isShowingFixture ? null : () => removeEntry(entry),
      ),
    );

    List<Widget> stackSection(String title, List<_StackEntry> entries) {
      if (entries.isEmpty) return const <Widget>[];
      return [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: V2Spacing.space24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: V2Typography.titleSm(color: context.v2.fg)),
              const SizedBox(height: 2),
              Text(
                'Swipe left to remove',
                style: V2Typography.bodySm(color: context.v2.fgMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: V2Spacing.space12),
        ...entries.map(stackRow),
      ];
    }

    // RefreshIndicator wraps the list so pull-to-refresh re-fires
    // activeStackProvider.
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(activeStackProvider);
        await ref.read(activeStackProvider.future);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: EdgeInsets.only(
          top: V2Spacing.space8,
          bottom:
              MediaQuery.of(context).padding.bottom +
              kPGNavBarHeight +
              V2Spacing.space24,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: V2Spacing.space24),
            child: _StackSummaryCard(showPreviewFixtures: showPreviewFixtures),
          ),
          // Production safety + intelligence surfaces — each collapses
          // to SizedBox.shrink when there's nothing to surface, so
          // these silently disappear on a clean stack.
          const _RecallAlertSlot(),
          const _StackSafetyBannerSlot(),
          const _ProfileNudgeSlot(),
          const SizedBox(height: V2Spacing.space24),
          // Empty state — Sean 2026-05-16: replaces the post-clear
          // fixture flash with a calm "your stack is empty" prompt
          // pointing back to /scan.
          if (isLoading)
            const _V2StackEmptyPanel(
              icon: Icons.hourglass_empty_rounded,
              eyebrow: 'Loading',
              headline: 'Checking your stack',
              body:
                  'Loading your supplements and medications from this device.',
            )
          else if (isEmpty)
            _V2StackEmptyPanel(
              icon: Icons.layers_outlined,
              eyebrow: 'Stack',
              headline: 'Your stack is empty',
              body:
                  'Add the supplements you take regularly to see nutrient '
                  'totals, UL warnings, and interactions in one place.',
              actionLabel: 'Scan a supplement',
              onAction: () => GoRouter.of(context).go(Routes.scan),
            ),
          if (!isLoading && !isEmpty) ...[
            ...stackSection('Your medications', medications),
            if (medications.isNotEmpty && supplements.isNotEmpty)
              const SizedBox(height: V2Spacing.space12),
            ...stackSection('Your supplements', supplements),
          ],
          // Timing + medication/nutrient guidance, then goal support
          // at the bottom. Each slot collapses when nothing applies.
          const _TimingGuidanceSlot(),
          const _DepletionSlot(),
          const _GoalSupportSlot(),
        ],
      ),
    );
  }
}

// =============================================================================
// Stack Summary card.
// =============================================================================

class _StackSummaryCard extends ConsumerWidget {
  final bool showPreviewFixtures;

  const _StackSummaryCard({required this.showPreviewFixtures});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Live supplement + medication counts AND real
    // StackIntelligenceEngine tier verdict. Same source of truth as
    // Home Stack Health so the user sees ONE verdict across both
    // surfaces (no drift). Sean's safety rule: real clinical surfaces
    // here, never a hardcoded "Optimal".
    final stackAsync = ref.watch(activeStackProvider);
    final stack = stackAsync.asData?.value ?? const [];
    final supplementCount = stack.where((e) => e.type == 'supplement').length;
    final medicationCount = stack.where((e) => e.type == 'medication').length;
    final hasLoadedStack = stackAsync.hasValue;
    final liveSupplementCount = hasLoadedStack
        ? supplementCount
        : showPreviewFixtures
        ? 3
        : 0;
    final liveMedicationCount = hasLoadedStack
        ? medicationCount
        : showPreviewFixtures
        ? 1
        : 0;

    final healthSnapshotAsync = ref.watch(stackHealthSnapshotProvider);
    final healthSnapshot = healthSnapshotAsync.asData?.value;
    final intelligence = healthSnapshot?.intelligence;
    final status = intelligence?.tier.healthLabel;
    final isAnalyzing = healthSnapshotAsync.isLoading;
    // A safety subsystem that ERRORED must never fall through to the
    // reassuring green "No data yet" — an unknown result is not a clear
    // one. When any provider errors and none is still loading, the
    // fallback hedges with a neutral (non-green) tone + label.
    final hasError = healthSnapshotAsync.hasError;
    final needsMoreInfo =
        stack.isNotEmpty && intelligence?.tier == StackTier.incomplete;
    // Tone/label: real status color when the intelligence engine produced a
    // verdict; otherwise a pure fallback (green while analyzing / empty,
    // neutral hedge on error).
    final fallback = stackHealthFallbackDisplay(
      palette: context.v2,
      isAnalyzing: isAnalyzing,
      hasError: hasError,
      needsMoreInfo: needsMoreInfo,
    );
    final Color tone = status?.color ?? fallback.tone;
    final statusTone = context.v2.tintedLabel(tone);
    final statusLabel = status?.label ?? fallback.label;
    final reviewSignals = healthSnapshot?.reviewSignals ?? const [];
    final canReviewSignals = reviewSignals.isNotEmpty;
    final insightLine = canReviewSignals
        ? describeSafetySignalReview(reviewSignals.length)
        : intelligence == null
        ? stackHealthFallbackSummary(
            isAnalyzing: isAnalyzing,
            hasError: hasError,
          )
        : describeStackSummary(intelligence);

    final card = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            context.v2.surface,
            Color.lerp(context.v2.surface, tone, 0.05)!,
          ],
        ),
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        border: Border.all(color: context.v2.outline),
        boxShadow: V2Shadows.md,
      ),
      padding: const EdgeInsets.all(V2Spacing.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                      style: V2Typography.titleSm(color: context.v2.fg),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      insightLine,
                      style: V2Typography.bodySm(color: context.v2.fgMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: V2Spacing.space12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: V2Spacing.space12,
                  vertical: V2Spacing.space4,
                ),
                decoration: BoxDecoration(
                  color: statusTone.fill,
                  borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
                  border: Border.all(color: statusTone.border, width: 0.8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
                      style: V2Typography.label(color: statusTone.foreground),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: V2Spacing.space16),
          Row(
            children: [
              _CountChip(
                icon: Icons.medication_outlined,
                label: 'Supplements',
                count: liveSupplementCount,
              ),
              const SizedBox(width: V2Spacing.space8),
              _CountChip(
                icon: Icons.local_pharmacy_outlined,
                label: 'Medications',
                count: liveMedicationCount,
              ),
            ],
          ),
        ],
      ),
    );
    if (!canReviewSignals) return card;
    return Semantics(
      button: true,
      label:
          '${describeSafetySignalReview(reviewSignals.length)}. View details',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => showStackSafetyDetailsSheet(context, healthSnapshot!),
          borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
          child: card,
        ),
      ),
    );
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
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: V2Spacing.space12,
          vertical: V2Spacing.space8,
        ),
        decoration: BoxDecoration(
          color: context.v2.bg,
          borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
          border: Border.all(color: context.v2.outline),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: context.v2.accent),
            const SizedBox(width: V2Spacing.space8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$count',
                    style: V2Typography.bodyMedium(color: context.v2.fg)
                        .copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                  ),
                  Text(
                    label,
                    style: V2Typography.caption(color: context.v2.fgMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Stack item row.
// =============================================================================

class _StackEntry {
  /// Stable id used as the Dismissible key AND as the
  /// stackActionsProvider remove/restore handle. Fixture rows pass
  /// synthetic ids like "fixture-1" — the parent suppresses dismiss
  /// for those.
  final String id;
  final String name;
  final String? brand;
  final int? score;
  final String? dosage;
  final String? frequency;
  final bool isMedication;
  final MedicationIdentitySnapshot? medicationIdentity;
  final MedicationIdentityAssessment? medicationIdentityAssessment;

  /// Phase 11.7j.5 — DSLD id when the row is a catalog product.
  /// Null for medications (RxNorm-based) and fixture rows.
  /// Drives the tap-to-open-product-detail navigation in
  /// `_StackItemRow.onTap`.
  final String? dsldId;

  /// User-reported start date and per-item reminder. Both device-only; see
  /// user_stacks_table.dart.
  final DateTime? startedAt;
  final int? reminderMinutes;

  const _StackEntry({
    required this.id,
    required this.name,
    required this.brand,
    required this.score,
    this.dosage,
    this.frequency,
    this.isMedication = false,
    this.medicationIdentity,
    this.medicationIdentityAssessment,
    this.dsldId,
    this.startedAt,
    this.reminderMinutes,
  });

  bool get hasReminder => reminderMinutes != null;
}

class _StackItemRow extends ConsumerWidget {
  final _StackEntry entry;

  /// Callback fired after the user swipe-dismisses. Production
  /// version calls stackActionsProvider.remove() + shows an Undo
  /// snackbar. Null on fixture rows so the dismiss is rejected
  /// before the row leaves the list.
  final Future<void> Function()? onRemoved;

  const _StackItemRow({required this.entry, this.onRemoved});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final product = entry.dsldId == null
        ? null
        : ref.watch(_stackProductProvider(entry.dsldId!)).asData?.value;
    final productName = product?.productName.trim();
    final brandName = product?.brandName?.trim();
    final fallbackName = entry.isMedication
        ? medicationDisplayName(entry.name)
        : entry.name;
    final displayName = productName == null || productName.isEmpty
        ? fallbackName
        : productName;
    final displayBrand = brandName == null || brandName.isEmpty
        ? entry.brand
        : brandName;
    final scoreDisplay = entry.isMedication
        ? null
        : stackCatalogScoreDisplayFor(product);
    final itemType = entry.isMedication
        ? PGItemType.medication
        : PGItemType.supplement;
    // The saved reminder survives a permission denial by design, but the row
    // must not announce a notification the device was never allowed to
    // schedule.
    final remindersDeliverable = ref.watch(stackRemindersDeliverableProvider);
    final reminderLabel = entry.reminderMinutes == null
        ? null
        : remindersDeliverable
        ? 'Daily reminder at ${TimeOfDay(hour: entry.reminderMinutes! ~/ 60, minute: entry.reminderMinutes! % 60).format(context)}'
        : 'Reminder saved — notifications are off for PharmaGuide';
    final trackingDetails = [
      if (entry.isMedication) entry.dosage,
      if (entry.isMedication) entry.frequency,
      reminderLabel,
    ].whereType<String>().where((value) => value.isNotEmpty).toList();

    return Dismissible(
      key: ValueKey('stack_${entry.id}'),
      direction: onRemoved != null
          ? DismissDirection.endToStart
          : DismissDirection.none,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: V2Spacing.space24),
        decoration: BoxDecoration(
          color: context.v2.caution.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        ),
        child: Icon(
          Icons.delete_outline_rounded,
          color: context.v2.caution,
          size: 22,
        ),
      ),
      onDismissed: (_) => onRemoved?.call(),
      child: Material(
        color: context.v2.surface,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        child: InkWell(
          // Supplement rows open catalog details when possible. Medication
          // rows use a local information sheet; health data never leaves the
          // device just to explain what the entry is used for.
          onTap: () {
            if (entry.isMedication) {
              unawaited(
                showMedicationDetailsSheet(
                  context,
                  name: displayName,
                  dosage: entry.dosage,
                  frequency: entry.frequency,
                  reminderLabel: reminderLabel,
                  identity: entry.medicationIdentity,
                  assessment: entry.medicationIdentityAssessment,
                  onEditTracking: () => _showEditStackTrackingSheet(
                    context,
                    ref,
                    entry: entry,
                    displayName: displayName,
                  ),
                ),
              );
              return;
            }
            final id = entry.dsldId;
            if (id != null && id.isNotEmpty) {
              context.push(Routes.productDetail(id));
              return;
            }
            PGToast.show(
              context,
              'No product details available for this entry. '
              'Re-add via scan to enable the detail page.',
              variant: PGToastVariant.info,
              duration: const Duration(seconds: 3),
            );
          },
          borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
          child: Container(
            padding: const EdgeInsets.all(V2Spacing.space12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
              border: Border.all(color: context.v2.outline),
              boxShadow: V2Shadows.sm,
            ),
            child: Row(
              children: [
                // Supplements: resolve via ProductImage (catalog path +
                // OFF fallback + branded placeholder) — raw imageUrl
                // alone is often empty in core rows. Medications keep
                // the bottle silhouette (no catalog photo).
                if (entry.isMedication || entry.dsldId == null)
                  PGProductThumbnail(
                    imageUrl: null,
                    type: itemType,
                    size: 48,
                    showTypeBadge: false,
                  )
                else
                  ProductImage(
                    dsldId: entry.dsldId!,
                    upc: product?.upcSku,
                    dsldImagePath:
                        product?.imageThumbnailUrl ?? product?.imageUrl,
                    productName: displayName,
                    brandName: displayBrand ?? '',
                    formFactor: product?.formFactor,
                    score: scoreDisplay?.score.toDouble(),
                    size: 48,
                    compact: true,
                  ),
                const SizedBox(width: V2Spacing.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        displayName,
                        style: V2Typography.bodyMedium(color: context.v2.fg),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (displayBrand != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          displayBrand,
                          style: V2Typography.caption(
                            color: context.v2.fgMuted,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (trackingDetails.isNotEmpty) ...[
                        const SizedBox(height: V2Spacing.space4),
                        Semantics(
                          label: trackingDetails.join(', '),
                          excludeSemantics: true,
                          child: Row(
                            children: [
                              if (entry.hasReminder) ...[
                                Icon(
                                  Icons.notifications_active_outlined,
                                  size: 12,
                                  color: context.v2.accent,
                                ),
                                const SizedBox(width: 4),
                              ],
                              Flexible(
                                child: Text(
                                  trackingDetails.join(' · '),
                                  style: V2Typography.caption(
                                    color: context.v2.fgSubtle,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (scoreDisplay != null) ...[
                        const SizedBox(height: V2Spacing.space4),
                        PGScoreLine(
                          score: scoreDisplay.score,
                          qualityTier: scoreDisplay.qualityTier,
                          compact: true,
                          confidence: scoreDisplay.confidence,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: V2Spacing.space8),
                IconButton(
                  tooltip: entry.isMedication
                      ? 'Edit dose and tracking for $displayName'
                      : 'Edit tracking for $displayName',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    Icons.edit_outlined,
                    color: context.v2.fgMuted,
                    size: 18,
                  ),
                  onPressed: () => _showEditStackTrackingSheet(
                    context,
                    ref,
                    entry: entry,
                    displayName: displayName,
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: context.v2.fgMuted,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _showEditStackTrackingSheet(
  BuildContext context,
  WidgetRef ref, {
  required _StackEntry entry,
  required String displayName,
}) async {
  final saved = await PGModal.bottomSheet<bool>(
    context: context,
    builder: (_) => _EditStackTrackingSheet(
      displayName: displayName,
      isMedication: entry.isMedication,
      dosage: entry.isMedication ? entry.dosage : null,
      startedAt: entry.startedAt,
      reminderMinutes: entry.reminderMinutes,
      onSave: ({dosage, startedAt, reminderMinutes}) => ref
          .read(stackActionsProvider)
          .updateTracking(
            entryId: entry.id,
            dosage: dosage ?? const Value.absent(),
            startedAt: startedAt ?? const Value.absent(),
            reminderMinutes: reminderMinutes ?? const Value.absent(),
          ),
    ),
  );
  if (saved == true && context.mounted) {
    PGToast.show(
      context,
      'Saved tracking details.',
      variant: PGToastVariant.success,
    );
  }
}

typedef _SaveStackTracking =
    Future<bool> Function({
      Value<String?>? dosage,
      Value<DateTime?>? startedAt,
      Value<int?>? reminderMinutes,
    });

class _EditStackTrackingSheet extends StatefulWidget {
  const _EditStackTrackingSheet({
    required this.displayName,
    required this.isMedication,
    required this.dosage,
    required this.startedAt,
    required this.reminderMinutes,
    required this.onSave,
  });

  final String displayName;
  final bool isMedication;
  final String? dosage;
  final DateTime? startedAt;
  final int? reminderMinutes;
  final _SaveStackTracking onSave;

  @override
  State<_EditStackTrackingSheet> createState() =>
      _EditStackTrackingSheetState();
}

class _EditStackTrackingSheetState extends State<_EditStackTrackingSheet> {
  late final TextEditingController _dosageController;
  DateTime? _startedAt;
  int? _reminderMinutes;
  var _saving = false;
  var _discardApproved = false;
  var _confirmingDiscard = false;

  @override
  void initState() {
    super.initState();
    _dosageController = TextEditingController(text: widget.dosage);
    _dosageController.addListener(_onDosageChanged);
    _startedAt = widget.startedAt;
    _reminderMinutes = widget.reminderMinutes;
  }

  void _onDosageChanged() {
    // PopScope receives canPop during build, so controller edits must rebuild
    // the guard rather than only changing the controller's internal state.
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _dosageController.removeListener(_onDosageChanged);
    _dosageController.dispose();
    super.dispose();
  }

  String _formatStart(DateTime value) =>
      DateFormat.yMMMd().format(value.toLocal());

  String _formatReminder(int minutes) {
    final time = TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
    return time.format(context);
  }

  Future<void> _pickStartDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _startedAt ?? now,
      firstDate: DateTime(now.year - 40),
      // A start date cannot be in the future; "I will start next month" is a
      // different fact than "I started".
      lastDate: now,
      helpText: 'When did you start taking this?',
    );
    if (picked != null) setState(() => _startedAt = picked);
  }

  Future<void> _pickReminderTime() async {
    final current = _reminderMinutes ?? 8 * 60;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
      helpText: 'Daily reminder time',
    );
    if (picked != null) {
      setState(() => _reminderMinutes = picked.hour * 60 + picked.minute);
    }
  }

  /// True when the sheet holds edits that would be lost on dismissal.
  bool get _isDirty =>
      (widget.isMedication &&
          _dosageController.text.trim() != (widget.dosage ?? '').trim()) ||
      _startedAt != widget.startedAt ||
      _reminderMinutes != widget.reminderMinutes;

  Future<bool> _confirmDiscard() async {
    if (!_isDirty) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('Your edits to this item have not been saved yet.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Swiping the sheet away is the easiest gesture to hit by accident, and
      // a discarded start date is silently wrong data rather than a visible
      // failure. Confirm before losing it.
      canPop: _discardApproved || !_isDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _confirmingDiscard) return;
        _confirmingDiscard = true;
        final approved = await _confirmDiscard();
        if (!mounted) return;
        _confirmingDiscard = false;
        if (!approved) return;

        // PopScope must rebuild with canPop=true before the second pop attempt;
        // otherwise the same guard intercepts the programmatic dismissal.
        setState(() => _discardApproved = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).pop();
        });
      },
      child: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        V2Spacing.space24,
        V2Spacing.space8,
        V2Spacing.space24,
        MediaQuery.viewInsetsOf(context).bottom + V2Spacing.space24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PGEyebrow(
            widget.isMedication ? 'Dose & tracking' : 'Tracking details',
            color: context.v2.fgMuted,
          ),
          const SizedBox(height: V2Spacing.space8),
          Text(
            widget.displayName,
            style: V2Typography.titleSm(color: context.v2.fg),
          ),
          const SizedBox(height: V2Spacing.space8),
          Text(
            widget.isMedication
                ? 'Save the dose as prescribed, plus an optional start date '
                      'or daily reminder. PharmaGuide does not change your '
                      'prescription.'
                : 'Supplement amounts come from the verified product label. '
                      'Add an optional start date or daily reminder here.',
            style: V2Typography.bodySm(color: context.v2.fgMuted),
          ),
          if (widget.isMedication) ...[
            const SizedBox(height: V2Spacing.space24),
            TextField(
              controller: _dosageController,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Dose (optional)',
                hintText: 'For example, 500 mg',
              ),
            ),
          ],
          const SizedBox(height: V2Spacing.space24),

          // --- Start date -------------------------------------------------
          PGEyebrow('Since when', color: context.v2.fgMuted),
          const SizedBox(height: V2Spacing.space4),
          Text(
            'If you started before adding this to PharmaGuide, saying so makes '
            'long-term monitoring notes accurate.',
            style: V2Typography.caption(color: context.v2.fgMuted),
          ),
          const SizedBox(height: V2Spacing.space8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : _pickStartDate,
                  icon: const Icon(Icons.event_outlined, size: 18),
                  // Wraps rather than truncates: at large accessibility text
                  // sizes an ellipsis would hide the date, which is the only
                  // thing the control is reporting.
                  label: Text(
                    _startedAt == null
                        ? 'Set start date'
                        : 'Started ${_formatStart(_startedAt!)}',
                    softWrap: true,
                    textAlign: TextAlign.start,
                  ),
                ),
              ),
              if (_startedAt != null)
                IconButton(
                  tooltip: 'Clear start date',
                  onPressed: _saving
                      ? null
                      : () => setState(() => _startedAt = null),
                  icon: const Icon(Icons.close_rounded),
                ),
            ],
          ),
          const SizedBox(height: V2Spacing.space24),

          // --- Reminder ---------------------------------------------------
          PGEyebrow('Reminder', color: context.v2.fgMuted),
          const SizedBox(height: V2Spacing.space4),
          Text(
            'Optional notification only. Timing guidance stays in your '
            'reviewed Daily Plan.',
            style: V2Typography.caption(color: context.v2.fgMuted),
          ),
          const SizedBox(height: V2Spacing.space8),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _reminderMinutes != null,
            onChanged: _saving
                ? null
                : (on) async {
                    if (!on) {
                      setState(() => _reminderMinutes = null);
                      return;
                    }
                    await _pickReminderTime();
                  },
            title: Text(
              _reminderMinutes == null
                  ? 'No reminder'
                  : 'Every day at ${_formatReminder(_reminderMinutes!)}',
              style: V2Typography.bodySm(color: context.v2.fg),
            ),
          ),
          if (_reminderMinutes != null)
            TextButton.icon(
              onPressed: _saving ? null : _pickReminderTime,
              icon: const Icon(Icons.schedule_rounded, size: 18),
              label: const Text('Change time'),
            ),
          const SizedBox(height: V2Spacing.space24),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.check_rounded),
              label: Text(_saving ? 'Saving…' : 'Save'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final changed = await widget.onSave(
        dosage: widget.isMedication
            ? Value(_dosageController.text)
            : const Value.absent(),
        startedAt: Value(_startedAt),
        reminderMinutes: Value(_reminderMinutes),
      );
      if (mounted) Navigator.of(context).pop(changed);
    } on StackReminderLimitException catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      PGToast.show(
        context,
        'You can keep up to ${error.maxReminders} daily reminders. '
        'Turn one off before adding another.',
        variant: PGToastVariant.error,
      );
    } on Object {
      if (!mounted) return;
      setState(() => _saving = false);
      PGToast.show(
        context,
        'Could not save tracking details. Try again.',
        variant: PGToastVariant.error,
      );
    }
  }
}

class _V2StackEmptyPanel extends StatelessWidget {
  final IconData icon;
  final String eyebrow;
  final String headline;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _V2StackEmptyPanel({
    required this.icon,
    required this.eyebrow,
    required this.headline,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    // Visual rule (Sean 2026-05-17): empty states sit on the cream
    // page bg with outline only — no shadow, no surface fill — so
    // they read as quieter than the active gradient-tinted summary
    // card above. Avoids the "flat white tile against cream gradient"
    // mismatch Sean called out in the post-walkthrough review.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: V2Spacing.space24),
      child: Material(
        color: context.v2.bg,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(V2Spacing.space24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
            border: Border.all(color: context.v2.outline),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: context.v2.accentTint,
                  borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
                ),
                child: Icon(icon, color: context.v2.accent, size: 28),
              ),
              const SizedBox(height: V2Spacing.space16),
              PGEyebrow(eyebrow),
              const SizedBox(height: V2Spacing.space8),
              Text(
                headline,
                textAlign: TextAlign.center,
                style: V2Typography.titleSm(color: context.v2.fg),
              ),
              const SizedBox(height: V2Spacing.space8),
              Text(
                body,
                textAlign: TextAlign.center,
                style: V2Typography.bodySm(color: context.v2.fgMuted),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: V2Spacing.space16),
                InkWell(
                  onTap: onAction,
                  borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: V2Spacing.space16,
                      vertical: V2Spacing.space8,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
                      border: Border.all(
                        color: context.v2.accent.withValues(alpha: 0.32),
                      ),
                    ),
                    child: Text(
                      actionLabel!,
                      style: V2Typography.label(color: context.v2.accent),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Nutrients tab — list of nutrient rows showing % RDA / UL coverage.
// Mirror of the production NutrientAccumulationPanel intent: most
// clinically relevant first (UL warnings before RDA tracking).
// =============================================================================

class _NutrientsTab extends ConsumerWidget {
  final bool showPreviewFixtures;

  const _NutrientsTab({required this.showPreviewFixtures});

  // Fixture ordered by clinical priority: UL-flagged first, then RDA-
  // tracked descending by %. Used when the user has no real stack
  // so the design preview state still renders.
  static const _rows = <_NutrientStatus>[
    _NutrientStatus(
      name: 'Vitamin A',
      detail: '120% of UL',
      percent: 1.20,
      tier: _NutrientTier.warning,
    ),
    _NutrientStatus(
      name: 'Iron',
      detail: '85% of UL',
      percent: 0.85,
      tier: _NutrientTier.monitor,
    ),
    _NutrientStatus(
      name: 'Magnesium',
      detail: '94% of RDA',
      percent: 0.94,
      tier: _NutrientTier.normal,
    ),
    _NutrientStatus(
      name: 'Vitamin D',
      detail: '78% of RDA',
      percent: 0.78,
      tier: _NutrientTier.normal,
    ),
    _NutrientStatus(
      name: 'Omega-3 (EPA + DHA)',
      detail: '65% of AI',
      percent: 0.65,
      tier: _NutrientTier.normal,
    ),
    _NutrientStatus(
      name: 'Vitamin B12',
      detail: '320% of RDA',
      percent: 1.0,
      tier: _NutrientTier.normal,
    ),
    _NutrientStatus(
      name: 'Zinc',
      detail: '48% of RDA',
      percent: 0.48,
      tier: _NutrientTier.normal,
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Production behavior: only render real nutrient totals once a
    // real stack exists. Fixture nutrient rows are reserved for the
    // dev preview so the production tab never claims nutrient
    // coverage while the Stack tab is empty.
    final stackAsync = ref.watch(activeStackProvider);
    final stack = stackAsync.asData?.value ?? const [];
    final isLoading = !stackAsync.hasValue && !showPreviewFixtures;
    final hasRealStack = stack.isNotEmpty;
    final shouldShowFixtures = showPreviewFixtures && !hasRealStack;

    // Nutrients tab pull-to-refresh parity (Sean 2026-05-17): Stack
    // tab already supports pull-to-refresh; this tab needs the same
    // gesture so a user adding a product elsewhere can refresh
    // nutrient totals without bouncing through the Stack tab first.
    return RefreshIndicator(
      color: context.v2.accent,
      backgroundColor: context.v2.surface,
      onRefresh: () async {
        ref.invalidate(activeStackProvider);
        await ref.read(activeStackProvider.future);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: EdgeInsets.only(
          top: V2Spacing.space8,
          bottom:
              MediaQuery.of(context).padding.bottom +
              kPGNavBarHeight +
              V2Spacing.space24,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: V2Spacing.space24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Supplement nutrient totals',
                  style: V2Typography.titleSm(color: context.v2.fg),
                ),
                const SizedBox(height: 2),
                Text(
                  'From your supplements only · compared with RDA/AI and '
                  'upper limits',
                  style: V2Typography.bodySm(color: context.v2.fgMuted),
                ),
              ],
            ),
          ),
          const SizedBox(height: V2Spacing.space12),
          // Production nutrient panel — only renders when the user
          // actually has a stack.
          if (isLoading)
            const _V2StackEmptyPanel(
              icon: Icons.hourglass_empty_rounded,
              eyebrow: 'Nutrients',
              headline: 'Checking nutrient totals',
              body: 'Loading your stack before calculating coverage.',
            ),
          if (hasRealStack)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: V2Spacing.space24),
              child: NutrientAccumulationPanel(),
            ),
          if (hasRealStack) const SizedBox(height: V2Spacing.space16),
          if (!isLoading && !hasRealStack && !shouldShowFixtures)
            const _V2StackEmptyPanel(
              icon: Icons.ssid_chart_rounded,
              eyebrow: 'Nutrients',
              headline: 'No nutrient totals yet',
              body:
                  'Add supplements to your stack and PharmaGuide will calculate '
                  'daily coverage and upper-limit warnings here.',
            ),
          // Fixture preview rows — dev preview only.
          if (shouldShowFixtures)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: V2Spacing.space24,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: context.v2.surface,
                  borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
                  border: Border.all(color: context.v2.outline),
                  boxShadow: V2Shadows.sm,
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (var i = 0; i < _rows.length; i++)
                      _NutrientRow(
                        status: _rows[i],
                        isLast: i == _rows.length - 1,
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

enum _NutrientTier { normal, monitor, warning }

class _NutrientStatus {
  final String name;
  final String detail;

  /// Visual progress 0..1 (1.0 = filled). Display percent shown in detail.
  final double percent;
  final _NutrientTier tier;

  const _NutrientStatus({
    required this.name,
    required this.detail,
    required this.percent,
    required this.tier,
  });
}

class _NutrientRow extends StatelessWidget {
  final _NutrientStatus status;
  final bool isLast;

  const _NutrientRow({required this.status, this.isLast = false});

  // Mirror the production NutrientProgressBar color story: exceeding a UL is
  // red, approaching one (80-99%) is amber, everything else is calm.
  Color _tone(V2Palette palette) => switch (status.tier) {
    _NutrientTier.warning => palette.contraindicated,
    _NutrientTier.monitor => palette.caution,
    _NutrientTier.normal => palette.accent,
  };

  @override
  Widget build(BuildContext context) {
    final clampedPercent = status.percent.clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(V2Spacing.space16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isLast ? Colors.transparent : context.v2.outline,
            width: 0.5,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  status.name,
                  style: V2Typography.bodyMedium(color: context.v2.fg),
                ),
              ),
              const SizedBox(width: V2Spacing.space8),
              Text(
                status.detail,
                style: V2Typography.caption(
                  color: _tone(context.v2),
                ).copyWith(fontWeight: FontWeight.w500),
              ),
            ],
          ),
          const SizedBox(height: V2Spacing.space8),
          ClipRRect(
            borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
            child: SizedBox(
              height: 6,
              child: Stack(
                children: [
                  Container(color: context.v2.outline),
                  FractionallySizedBox(
                    widthFactor: clampedPercent,
                    child: Container(color: _tone(context.v2)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Wishlist tab — signed-in favorites list; guests prompted to sign in.
// =============================================================================

class _WishlistTab extends ConsumerWidget {
  const _WishlistTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isGuest = ref.watch(authStateProvider) == AuthMode.guest;
    final favoritesAsync = ref.watch(favoritesProvider);

    if (isGuest) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: EdgeInsets.only(
          top: V2Spacing.space24,
          bottom:
              MediaQuery.of(context).padding.bottom +
              kPGNavBarHeight +
              V2Spacing.space24,
        ),
        children: [
          _V2StackEmptyPanel(
            icon: Icons.favorite_border_rounded,
            eyebrow: 'Wishlist',
            headline: 'Sign in to save products',
            body:
                'Wishlist is available on a free early-access account so your '
                'saved products stay on this device when you come back.',
            actionLabel: 'Sign in',
            onAction: () => context.push(Routes.authInvitation),
          ),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(favoritesProvider);
        await ref.read(favoritesProvider.future);
      },
      child: favoritesAsync.when(
        loading: () => ListView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: EdgeInsets.only(
            top: V2Spacing.space24,
            bottom:
                MediaQuery.of(context).padding.bottom +
                kPGNavBarHeight +
                V2Spacing.space24,
          ),
          children: const [
            _V2StackEmptyPanel(
              icon: Icons.hourglass_empty_rounded,
              eyebrow: 'Loading',
              headline: 'Loading your wishlist',
              body: 'Pulling saved products from this device.',
            ),
          ],
        ),
        error: (_, __) => ListView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: EdgeInsets.only(
            top: V2Spacing.space24,
            bottom:
                MediaQuery.of(context).padding.bottom +
                kPGNavBarHeight +
                V2Spacing.space24,
          ),
          children: [
            _V2StackEmptyPanel(
              icon: Icons.cloud_off_rounded,
              eyebrow: 'Wishlist',
              headline: 'Couldn’t load wishlist',
              body: 'Try again in a moment.',
              actionLabel: 'Retry',
              onAction: () => ref.invalidate(favoritesProvider),
            ),
          ],
        ),
        data: (favorites) {
          if (favorites.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: EdgeInsets.only(
                top: V2Spacing.space24,
                bottom:
                    MediaQuery.of(context).padding.bottom +
                    kPGNavBarHeight +
                    V2Spacing.space24,
              ),
              children: [
                _V2StackEmptyPanel(
                  icon: Icons.favorite_border_rounded,
                  eyebrow: 'Wishlist',
                  headline: 'No saved products yet',
                  body:
                      'Tap the heart on any product page to save it here for '
                      'later — compare or add to your stack when you’re ready.',
                  actionLabel: 'Scan a product',
                  onAction: () => GoRouter.of(context).go(Routes.scan),
                ),
              ],
            );
          }

          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: EdgeInsets.fromLTRB(
              V2Spacing.space24,
              V2Spacing.space8,
              V2Spacing.space24,
              MediaQuery.of(context).padding.bottom +
                  kPGNavBarHeight +
                  V2Spacing.space24,
            ),
            itemCount: favorites.length + 1,
            separatorBuilder: (_, __) =>
                const SizedBox(height: V2Spacing.space12),
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: V2Spacing.space8),
                  child: Text(
                    '${favorites.length} saved',
                    style: V2Typography.eyebrow(color: context.v2.fgMuted),
                  ),
                );
              }
              final fav = favorites[index - 1];
              return _WishlistItemRow(
                key: ValueKey('wishlist_${fav.dsldId}'),
                dsldId: fav.dsldId,
              );
            },
          );
        },
      ),
    );
  }
}

class _WishlistItemRow extends ConsumerWidget {
  final String dsldId;

  const _WishlistItemRow({super.key, required this.dsldId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final product = ref.watch(_stackProductProvider(dsldId)).asData?.value;
    final displayName = (product?.productName.trim().isNotEmpty ?? false)
        ? product!.productName.trim()
        : 'Saved product';
    final displayBrand = product?.brandName?.trim();
    final scoreDisplay = stackCatalogScoreDisplayFor(product);

    return Dismissible(
      key: ValueKey('wishlist_dismiss_$dsldId'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: V2Spacing.space24),
        decoration: BoxDecoration(
          color: context.v2.accentTint,
          borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        ),
        child: Icon(
          Icons.favorite_border_rounded,
          color: context.v2.accent,
          size: 22,
        ),
      ),
      confirmDismiss: (_) async {
        try {
          await ref.read(favoritesActionsProvider).remove(dsldId);
          return true;
        } on StackRequiresSignInException {
          if (context.mounted) {
            await context.push(Routes.authInvitation);
          }
          return false;
        } on Exception catch (e, st) {
          CrashReportingService().recordError(
            e,
            st,
            hint: 'wishlist:swipe_remove',
          );
          if (context.mounted) {
            PGToast.show(
              context,
              'Could not remove from Wishlist.',
              variant: PGToastVariant.error,
            );
          }
          return false;
        }
      },
      child: Material(
        color: context.v2.surface,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        child: InkWell(
          onTap: () => context.push(Routes.productDetail(dsldId)),
          borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
          child: Container(
            padding: const EdgeInsets.all(V2Spacing.space12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
              border: Border.all(color: context.v2.outline),
              boxShadow: V2Shadows.sm,
            ),
            child: Row(
              children: [
                ProductImage(
                  dsldId: dsldId,
                  upc: product?.upcSku,
                  dsldImagePath:
                      product?.imageThumbnailUrl ?? product?.imageUrl,
                  productName: displayName,
                  brandName: displayBrand ?? '',
                  formFactor: product?.formFactor,
                  score: scoreDisplay?.score.toDouble(),
                  size: 48,
                  compact: true,
                ),
                const SizedBox(width: V2Spacing.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        displayName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: V2Typography.label(color: context.v2.fg),
                      ),
                      if (displayBrand != null && displayBrand.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          displayBrand,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: V2Typography.bodySm(color: context.v2.fgMuted),
                        ),
                      ],
                      if (scoreDisplay != null) ...[
                        const SizedBox(height: V2Spacing.space4),
                        PGScoreLine(
                          score: scoreDisplay.score,
                          qualityTier: scoreDisplay.qualityTier,
                          compact: true,
                          confidence: scoreDisplay.confidence,
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Remove from Wishlist',
                  icon: Icon(
                    Icons.favorite_rounded,
                    color: context.v2.accent,
                    size: 22,
                  ),
                  onPressed: () async {
                    unawaited(PGHaptics.press());
                    try {
                      await ref.read(favoritesActionsProvider).remove(dsldId);
                      if (context.mounted) {
                        PGToast.show(
                          context,
                          'Removed from Wishlist',
                          variant: PGToastVariant.info,
                          duration: const Duration(seconds: 2),
                        );
                      }
                    } on StackRequiresSignInException {
                      if (context.mounted) {
                        await context.push(Routes.authInvitation);
                      }
                    } on Exception catch (e, st) {
                      CrashReportingService().recordError(
                        e,
                        st,
                        hint: 'wishlist:heart_remove',
                      );
                      if (context.mounted) {
                        PGToast.show(
                          context,
                          'Could not remove from Wishlist.',
                          variant: PGToastVariant.error,
                        );
                      }
                    }
                  },
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
// Preview wrapper.
// =============================================================================

class StackV2Preview extends StatefulWidget {
  const StackV2Preview({super.key});

  @override
  State<StackV2Preview> createState() => _StackV2PreviewState();
}

class _StackV2PreviewState extends State<StackV2Preview> {
  int _navIndex = 1;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        StackV2Screen(
          selectedIndex: _navIndex,
          showPreviewFixtures: true,
          onDestinationSelected: (i) => setState(() => _navIndex = i),
        ),
        Positioned(
          top: MediaQuery.of(context).padding.top + 4,
          right: 8,
          child: Material(
            color: context.v2.surface,
            shape: const CircleBorder(),
            elevation: 0,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => context.go('/dev/v2'),
              child: Padding(
                padding: const EdgeInsets.all(V2Spacing.space8),
                child: Icon(
                  Icons.close_rounded,
                  color: context.v2.fg,
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
// Production safety slot widgets. These preserve the same recall,
// interaction, nutrient-warning, profile-nudge, timing, and depletion
// behavior as the previous stack route while rendering through v2
// surfaces/tokens.
// =============================================================================

/// Neutral, non-green hedge shown when a safety surface could not be
/// evaluated — a provider error or an incomplete check. Under-warning is
/// the dangerous failure here: an unknown safety result must never render
/// as green/all-clear, so these slots surface this hedge instead of
/// silently collapsing to `SizedBox.shrink`.
class _SafetyUnavailableBanner extends StatelessWidget {
  const _SafetyUnavailableBanner({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return PGSeverityBanner(
      tone: PGBannerTone.neutral,
      title: title,
      body: body,
      margin: const EdgeInsets.fromLTRB(
        V2Spacing.space24,
        V2Spacing.space12,
        V2Spacing.space24,
        0,
      ),
    );
  }
}

class _RecallAlertSlot extends ConsumerWidget {
  // The report carries both findings and the incomplete hedge. Every surface
  // consumes this same object so an unavailable scan cannot appear clean on
  // Home while showing a warning here.
  const _RecallAlertSlot();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportAsync = ref.watch(recalledIngredientsReportProvider);
    return reportAsync.when(
      data: (report) {
        if (report.isEmpty) {
          // Empty report + incomplete check means the recall data could not
          // be loaded — hedge rather than imply the stack is recall-free, or
          // an FDA-recalled product goes silently un-flagged. A genuinely
          // clean stack (loaded, no hits) still shows nothing.
          if (report.incomplete) {
            return const _SafetyUnavailableBanner(
              title: "Couldn't check for recalls",
              body:
                  'Recall data is unavailable right now, so we could not '
                  'check your stack against FDA recalls. Check back in a '
                  'moment.',
            );
          }
          return const SizedBox.shrink();
        }
        final ordered = report.orderedViolations;
        final title = ordered.every((violation) => violation.isBannedSubstance)
            ? 'Banned Substance Alert'
            : ordered.every((violation) => violation.isRecalledProduct)
            ? 'Recall Alert'
            : 'Product Safety Alert';
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            V2Spacing.space24,
            V2Spacing.space12,
            V2Spacing.space24,
            0,
          ),
          child: PGSeverityBanner(
            tone: PGBannerTone.danger,
            title: title,
            body: report.bannerMessage,
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      // Never vanish silently on error — hedge so a failed recall check does
      // not read as "no recalls".
      error: (_, __) => const _SafetyUnavailableBanner(
        title: "Couldn't check for recalls",
        body:
            'Recall data is unavailable right now, so we could not check '
            'your stack against FDA recalls. Check back in a moment.',
      ),
    );
  }
}

class _StackSafetyBannerSlot extends ConsumerWidget {
  const _StackSafetyBannerSlot();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshotAsync = ref.watch(stackHealthSnapshotProvider);
    return snapshotAsync.when(
      data: (snapshot) {
        if (snapshot.reviewSignals.isEmpty &&
            !snapshot.intelligence.analysisIncomplete) {
          return const SizedBox.shrink();
        }
        return StackSafetyBanner(
          snapshot: snapshot,
          onTap: snapshot.reviewSignals.isEmpty
              ? null
              : () => showStackSafetyDetailsSheet(context, snapshot),
          margin: const EdgeInsets.fromLTRB(
            V2Spacing.space24,
            V2Spacing.space12,
            V2Spacing.space24,
            0,
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      // Never vanish silently on error — hedge (neutral) so a failed safety
      // pass does not read as "no interactions".
      error: (_, __) => const _SafetyUnavailableBanner(
        title: "Couldn't check your stack",
        body:
            'Safety data is unavailable right now, so we could not check '
            'your stack for interactions or timing guidance. Check back '
            'in a moment.',
      ),
    );
  }
}

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
        V2Spacing.space24,
        V2Spacing.space12,
        V2Spacing.space24,
        0,
      ),
      child: PGSeverityBanner(
        tone: PGBannerTone.neutral,
        title: 'Personalize your stack',
        body:
            'Add your health conditions and medications to see warnings '
            'that actually apply to you.',
        actionLabel: 'Complete profile',
        onAction: () => GoRouter.of(context).push(Routes.profileSetup),
      ),
    );
  }
}

/// One product-level timing surface built from the reviewed rules.
///
/// Ingredient rules may explain why a constraint exists, but a person only
/// handles the physical bottle in their stack. The builder therefore groups by
/// stable stack-row identity, never renders an ingredient as if it were a
/// bottle, and never states when a prescribed medication is taken.
class _TimingGuidanceSlot extends ConsumerWidget {
  const _TimingGuidanceSlot();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportAsync = ref.watch(stackSafetyReportProvider);
    return reportAsync.when(
      data: (report) {
        final guidance = const TimingGuidanceBuilder().build(
          report.timingOptimizations,
        );
        // A failed timing check must never read as "nothing found". The card
        // itself stays silent unless it can honestly assert one or the other.
        if (report.checksIncomplete && guidance.products.isEmpty) {
          return const SizedBox.shrink();
        }
        return PGTimingGuidanceCard(
          guidance: guidance,
          margin: const EdgeInsets.fromLTRB(
            V2Spacing.space24,
            V2Spacing.space12,
            V2Spacing.space24,
            0,
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

/// Goal-support slot shown after the user's concrete stack items and timing.
/// Hidden while loading or when the stack is empty; errors render an explicit
/// unavailable state. The no-goals invitation links to profile setup.
class _GoalSupportSlot extends ConsumerWidget {
  const _GoalSupportSlot();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportAsync = ref.watch(coverageReportProvider);
    return reportAsync.when(
      data: (report) {
        if (report.isEmpty) return const SizedBox.shrink();
        return StackGoalSupportCard(
          report: report,
          onAddGoals: () => GoRouter.of(context).push(Routes.profileSetup),
          margin: const EdgeInsets.fromLTRB(
            V2Spacing.space24,
            V2Spacing.space12,
            V2Spacing.space24,
            0,
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const _SafetyUnavailableBanner(
        title: "Couldn't check goal support",
        body: 'Goal-support data is unavailable right now. Try again shortly.',
      ),
    );
  }
}

/// Phase 11.7L.C — depletion-checker slot wired to the v2 mirror card.
class _DepletionSlot extends ConsumerWidget {
  const _DepletionSlot();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final depletionAsync = ref.watch(depletionReportProvider);
    const margin = EdgeInsets.fromLTRB(
      V2Spacing.space24,
      V2Spacing.space12,
      V2Spacing.space24,
      0,
    );
    return depletionAsync.when(
      data: (report) {
        // UNAVAILABLE is not a clean state — show it explicitly, never hide it
        // as if there were no medication–nutrient considerations (B1.2 App-1).
        if (report.status == MedNutrientLoadStatus.unavailable) {
          return const PGDepletionUnavailableCard(margin: margin);
        }
        if (report.matches.isEmpty) return const SizedBox.shrink();
        // The watch only annotates rows the checker already produced, so a
        // pending/failed watch degrades to today's card rather than delaying
        // or suppressing it.
        final watchStatuses =
            ref.watch(depletionWatchProvider).asData?.value ??
            const <String, DepletionWatchStatus>{};
        return PGDepletionCard(
          depletions: report.matches,
          margin: margin,
          watchStatuses: watchStatuses,
        );
      },
      loading: () => const SizedBox.shrink(),
      // An exception is NOT a clean state — a load/parse failure must never
      // render as "no medication–nutrient considerations" (B1.2 App-1:
      // unavailable is never clean). Surface it like the unavailable status.
      error: (_, __) => const PGDepletionUnavailableCard(margin: margin),
    );
  }
}
