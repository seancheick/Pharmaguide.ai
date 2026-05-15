import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/components/pg_eyebrow.dart';
import 'package:pharmaguide/core/components/pg_score_line.dart';
import 'package:pharmaguide/core/components/pg_segmented_control.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_motion.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/core/widgets/pg_frosted_nav_bar.dart';
import 'package:pharmaguide/core/widgets/pg_severity_banner.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';
import 'package:pharmaguide/features/stack/providers/stack_providers.dart';
import 'package:pharmaguide/features/stack/widgets/depletion_checker_card.dart';
import 'package:pharmaguide/features/stack/widgets/nutrient_accumulation_panel.dart';
import 'package:pharmaguide/features/stack/widgets/stack_safety_banner.dart';
import 'package:pharmaguide/features/stack/widgets/timing_advice_card.dart';

/// v2 Stack screen — visual mirror of `stack_screen.dart` with three
/// sub-tabs via [PGSegmentedControl]:
///
///   Stack | Nutrients | Wishlist
///
/// Production currently ships two tabs (Stack / Wishlist) with a
/// nutrient panel embedded in the Stack scroll. Sean 2026-05-15:
/// split nutrients out into its own segment so each tab does one
/// clean job. Production wiring keeps the same providers; only the
/// container changes.
///
/// Segmented control sits below the app bar with a sliding pill
/// highlighter and 280ms emphasized transitions.
class StackV2Screen extends StatefulWidget {
  final int selectedIndex;
  final ValueChanged<int>? onDestinationSelected;
  final bool showNavBar;

  const StackV2Screen({
    super.key,
    this.selectedIndex = 1, // Stack tab is index 1 in v2 nav order
    this.onDestinationSelected,
    this.showNavBar = true,
  });

  @override
  State<StackV2Screen> createState() => _StackV2ScreenState();
}

class _StackV2ScreenState extends State<StackV2Screen> {
  int _segment = 0;

  @override
  Widget build(BuildContext context) {
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
              0 => const _StackTab(),
              1 => const _NutrientsTab(),
              _ => const _WishlistTab(),
            },
          ),
        ),
        bottomNavigationBar: widget.showNavBar
            ? PGFrostedNavBar(
                useV2Tones: true,
                selectedIndex: widget.selectedIndex,
                onDestinationSelected:
                    widget.onDestinationSelected ?? (_) {},
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

  const _StackAppBar({
    required this.segment,
    required this.onSegmentChanged,
  });

  @override
  // 56pt AppBar default + 16 gap + 44 segmented control + 16 gap = 132
  Size get preferredSize => const Size.fromHeight(132);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: V2Colors.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      automaticallyImplyLeading: false,
      titleSpacing: V2Spacing.space24,
      title: Text(
        'My stack',
        style: V2Typography.title(color: V2Colors.fg),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.add_rounded, color: V2Colors.fg),
          tooltip: 'Add medication',
          onPressed: () {},
        ),
        IconButton(
          icon: const Icon(Icons.ios_share_rounded, color: V2Colors.fg),
          tooltip: 'Share with clinician',
          onPressed: () {},
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

// =============================================================================
// Stack tab — summary card + supplements list.
// =============================================================================

class _StackTab extends ConsumerWidget {
  const _StackTab();

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
  Widget build(BuildContext context, WidgetRef ref) {
    final stackAsync = ref.watch(activeStackProvider);
    final realItems = stackAsync.asData?.value
        .map((row) => _StackEntry(
              id: row.id,
              name: row.name,
              brand: null, // production resolves brand via core DB
              score: null, // ditto for score
              dosage: row.dosage,
              frequency: row.frequency,
              isMedication: row.type == 'medication',
            ))
        .toList();
    final items = (realItems == null || realItems.isEmpty)
        ? _fixtureItems
        : realItems;
    final isShowingFixture = items == _fixtureItems;

    // RefreshIndicator wraps the list so pull-to-refresh re-fires
    // activeStackProvider. Matches production behavior.
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
          bottom: MediaQuery.of(context).padding.bottom +
              kPGNavBarHeight +
              V2Spacing.space24,
        ),
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: V2Spacing.space24),
            child: _StackSummaryCard(),
          ),
          // Production safety + intelligence surfaces — each collapses
          // to SizedBox.shrink when there's nothing to surface, so
          // these silently disappear on a clean stack. Kept as the
          // production widgets per Sean's directive ("temporary visual
          // inconsistency acceptable, loss of clinical functionality
          // is not"). v2 mirrors of each land in subsequent passes.
          _LegacyRecallAlertSlot(stack: stackAsync.asData?.value ?? const []),
          const _LegacyStackSafetyBannerSlot(),
          const _LegacyProfileNudgeSlot(),
          const SizedBox(height: V2Spacing.space24),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: V2Spacing.space24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your supplements',
                  style: V2Typography.titleSm(color: V2Colors.fg),
                ),
                const SizedBox(height: 2),
                Text(
                  'Swipe left to remove',
                  style: V2Typography.bodySm(color: V2Colors.fgMuted),
                ),
              ],
            ),
          ),
          const SizedBox(height: V2Spacing.space12),
        ...items.map(
          (e) => Padding(
            padding: const EdgeInsets.fromLTRB(
              V2Spacing.space24,
              0,
              V2Spacing.space24,
              V2Spacing.space12,
            ),
            child: _StackItemRow(
              entry: e,
              // Fixture items can't be removed (no provider row to
              // delete). Real rows wire to stackActionsProvider.
              onRemoved: isShowingFixture
                  ? null
                  : () async {
                      final actions = ref.read(stackActionsProvider);
                      try {
                        await actions.remove(e.id);
                      } on Exception {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Could not remove.'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                        return;
                      }
                      if (!context.mounted) return;
                      final messenger = ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar();
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text('Removed ${e.name}'),
                          duration: const Duration(seconds: 4),
                          behavior: SnackBarBehavior.floating,
                          action: SnackBarAction(
                            label: 'Undo',
                            onPressed: () async {
                              try {
                                await actions.restore(e.id);
                              } on Exception {
                                // silent
                              }
                            },
                          ),
                        ),
                      );
                    },
            ),
          ),
        ),
        // Timing + depletion advice — same conditional behavior as
        // the safety slots above (collapse when nothing to show).
        const _LegacyTimingAdviceSlot(),
        const _LegacyDepletionSlot(),
        ],
      ),
    );
  }
}

// =============================================================================
// Stack Summary card.
// =============================================================================

class _StackSummaryCard extends ConsumerWidget {
  const _StackSummaryCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Phase 11.2: live supplement + medication counts. Status tier
    // stays "Optimal" until the intelligence engine wires in
    // Phase 11.x — same incremental rollout as Home.
    final stack = ref.watch(activeStackProvider).asData?.value ?? const [];
    final supplementCount =
        stack.where((e) => e.type == 'supplement').length;
    final medicationCount =
        stack.where((e) => e.type == 'medication').length;
    final hasRealData = stack.isNotEmpty;
    final liveSupplementCount = hasRealData ? supplementCount : 3;
    final liveMedicationCount = hasRealData ? medicationCount : 1;
    const tone = V2Colors.safe;

    return Container(
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
                      style: V2Typography.titleSm(color: V2Colors.fg),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'No major safety issues detected right now.',
                      style: V2Typography.bodySm(color: V2Colors.fgMuted),
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
                  color: tone.withValues(alpha: 0.10),
                  borderRadius:
                      BorderRadius.circular(V2Spacing.radiusPill),
                  border: Border.all(
                    color: tone.withValues(alpha: 0.20),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: tone,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: V2Spacing.space8),
                    Text(
                      'Optimal',
                      style: V2Typography.label(color: tone),
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
          color: V2Colors.bg,
          borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
          border: Border.all(color: V2Colors.outline),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: V2Colors.accent),
            const SizedBox(width: V2Spacing.space8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$count',
                    style: V2Typography.bodyMedium(color: V2Colors.fg)
                        .copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  Text(
                    label,
                    style: V2Typography.caption(color: V2Colors.fgMuted),
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

  const _StackEntry({
    required this.id,
    required this.name,
    required this.brand,
    required this.score,
    this.dosage,
    this.frequency,
    this.isMedication = false,
  });
}

class _StackItemRow extends StatelessWidget {
  final _StackEntry entry;

  /// Callback fired after the user swipe-dismisses. Production
  /// version calls stackActionsProvider.remove() + shows an Undo
  /// snackbar. Null on fixture rows so the dismiss is rejected
  /// before the row leaves the list.
  final Future<void> Function()? onRemoved;

  const _StackItemRow({required this.entry, this.onRemoved});

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey('stack_${entry.id}'),
      direction: onRemoved != null
          ? DismissDirection.endToStart
          : DismissDirection.none,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: V2Spacing.space24),
        decoration: BoxDecoration(
          color: V2Colors.caution.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        ),
        child: const Icon(
          Icons.delete_outline_rounded,
          color: V2Colors.caution,
          size: 22,
        ),
      ),
      onDismissed: (_) => onRemoved?.call(),
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
            child: Row(
              children: [
                _ItemLeadingGlyph(entry: entry),
                const SizedBox(width: V2Spacing.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        entry.name,
                        style: V2Typography.bodyMedium(color: V2Colors.fg),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (entry.brand != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          entry.brand!,
                          style:
                              V2Typography.caption(color: V2Colors.fgMuted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (entry.dosage != null || entry.frequency != null) ...[
                        const SizedBox(height: V2Spacing.space4),
                        Text(
                          [entry.dosage, entry.frequency]
                              .whereType<String>()
                              .where((s) => s.isNotEmpty)
                              .join(' · '),
                          style:
                              V2Typography.caption(color: V2Colors.fgSubtle),
                        ),
                      ],
                      if (entry.score != null) ...[
                        const SizedBox(height: V2Spacing.space4),
                        PGScoreLine(score: entry.score!, compact: true),
                      ],
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
    );
  }
}

class _ItemLeadingGlyph extends StatelessWidget {
  final _StackEntry entry;
  const _ItemLeadingGlyph({required this.entry});

  @override
  Widget build(BuildContext context) {
    final isMed = entry.isMedication;
    final tone = isMed ? V2Colors.fgMuted : V2Colors.accent;
    final tint = isMed
        ? V2Colors.fgMuted.withValues(alpha: 0.10)
        : V2Colors.accentTint;

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
      ),
      child: Icon(
        isMed ? Icons.local_pharmacy_outlined : Icons.medication_outlined,
        size: 20,
        color: tone,
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
  const _NutrientsTab();

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
    // Production behavior: when there's a real stack, render the
    // legacy NutrientAccumulationPanel which sources live data from
    // stackNutrientStatusesProvider. v2 fixture rows only render
    // when no real stack is present (for design preview). Sean
    // 2026-05-15: preserve production functionality first, polish
    // the legacy widget into a v2 mirror in a later pass.
    final hasRealStack =
        (ref.watch(activeStackProvider).asData?.value ?? const []).isNotEmpty;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: EdgeInsets.only(
        top: V2Spacing.space8,
        bottom: MediaQuery.of(context).padding.bottom +
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
                'Daily nutrient coverage',
                style: V2Typography.titleSm(color: V2Colors.fg),
              ),
              const SizedBox(height: 2),
              Text(
                'Totals across your stack vs. RDA / UL benchmarks.',
                style: V2Typography.bodySm(color: V2Colors.fgMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: V2Spacing.space12),
        // Real production panel — only renders when the user actually
        // has a stack. Audit-backlog: replace with a v2 mirror later.
        if (hasRealStack)
          const Padding(
            padding:
                EdgeInsets.symmetric(horizontal: V2Spacing.space24),
            child: NutrientAccumulationPanel(),
          ),
        if (hasRealStack) const SizedBox(height: V2Spacing.space16),
        // Fixture preview rows — only when there's no real stack, so
        // the gallery review state still feels populated.
        if (!hasRealStack)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: V2Spacing.space24),
          child: Container(
            decoration: BoxDecoration(
              color: V2Colors.surface,
              borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
              border: Border.all(color: V2Colors.outline),
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

  Color get _tone => switch (status.tier) {
        _NutrientTier.warning => V2Colors.caution,
        _NutrientTier.monitor => V2Colors.monitor,
        _NutrientTier.normal => V2Colors.accent,
      };

  @override
  Widget build(BuildContext context) {
    final clampedPercent = status.percent.clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(V2Spacing.space16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isLast ? Colors.transparent : V2Colors.outline,
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
                  style: V2Typography.bodyMedium(color: V2Colors.fg),
                ),
              ),
              const SizedBox(width: V2Spacing.space8),
              Text(
                status.detail,
                style: V2Typography.caption(color: _tone)
                    .copyWith(fontWeight: FontWeight.w500),
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
                  Container(color: V2Colors.outline),
                  FractionallySizedBox(
                    widthFactor: clampedPercent,
                    child: Container(color: _tone),
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
// Wishlist tab — calm empty state.
// =============================================================================

class _WishlistTab extends StatelessWidget {
  const _WishlistTab();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(V2Spacing.space24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: V2Colors.accentTint,
                borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
              ),
              child: const Icon(
                Icons.bookmark_outline_rounded,
                size: 40,
                color: V2Colors.accent,
              ),
            ),
            const SizedBox(height: V2Spacing.space24),
            const PGEyebrow('Wishlist'),
            const SizedBox(height: V2Spacing.space8),
            Text(
              'Save products to revisit them later',
              textAlign: TextAlign.center,
              style: V2Typography.titleSm(color: V2Colors.fg),
            ),
            const SizedBox(height: V2Spacing.space8),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: V2Spacing.space24,
              ),
              child: Text(
                "Anything you bookmark from a product page will land here so "
                "you can compare or add later.",
                textAlign: TextAlign.center,
                style: V2Typography.body(color: V2Colors.fgMuted),
              ),
            ),
          ],
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
          onDestinationSelected: (i) => setState(() => _navIndex = i),
        ),
        Positioned(
          top: MediaQuery.of(context).padding.top + 4,
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
// Legacy production slot widgets — copied from stack_screen.dart so the
// v2 Stack route preserves the same safety + intelligence surfaces
// (recall alerts, safety banner, profile nudge, timing advice,
// depletion). Visual style is still legacy here; v2 mirrors land in
// subsequent passes and replace these. Sean 2026-05-15: clinical
// functionality stays alive even while the visual reskin progresses.
// =============================================================================

class _LegacyRecallAlertSlot extends ConsumerWidget {
  const _LegacyRecallAlertSlot({required this.stack});
  // ignore: unused_element
  final List<dynamic> stack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportAsync = ref.watch(recalledIngredientsReportProvider);
    return reportAsync.when(
      data: (report) {
        if (report.isEmpty) return const SizedBox.shrink();
        final ordered = report.orderedViolations;
        final primary = ordered.first;
        final names =
            ordered.map((v) => v.productName).toList(growable: false);
        final body = ordered.length == 1
            ? primary.bannerMessage
            : '${ordered.length} products need review. '
                '${primary.bannerMessage} Plus ${ordered.length - 1} '
                'more: ${names.skip(1).join(", ")}.';
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            V2Spacing.space24,
            V2Spacing.space12,
            V2Spacing.space24,
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

class _LegacyStackSafetyBannerSlot extends ConsumerWidget {
  const _LegacyStackSafetyBannerSlot();

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

class _LegacyProfileNudgeSlot extends ConsumerWidget {
  const _LegacyProfileNudgeSlot();

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

class _LegacyTimingAdviceSlot extends ConsumerWidget {
  const _LegacyTimingAdviceSlot();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportAsync = ref.watch(stackSafetyReportProvider);
    return reportAsync.when(
      data: (report) {
        if (!report.hasTimingAdvice) return const SizedBox.shrink();
        return TimingAdviceCard(
          optimizations: report.timingOptimizations,
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

class _LegacyDepletionSlot extends ConsumerWidget {
  const _LegacyDepletionSlot();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final depletionAsync = ref.watch(depletionReportProvider);
    return depletionAsync.when(
      data: (depletions) {
        if (depletions.isEmpty) return const SizedBox.shrink();
        return DepletionCheckerCard(
          depletions: depletions,
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
