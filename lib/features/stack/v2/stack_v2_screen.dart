import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/components/pg_eyebrow.dart';
import 'package:pharmaguide/core/components/pg_score_line.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/core/widgets/pg_frosted_nav_bar.dart';

/// v2 Stack screen — faithful visual mirror of `stack_screen.dart`.
///
/// Production composition preserved:
///   - Two pinned tabs: Stack | Wishlist
///   - Stack tab: Stack Health summary card (status tier, NO numeric
///     score per production rule 2026-05-05) → "Your supplements"
///     section header (subtitle: "Swipe left to remove") → list of
///     supplement / medication cards (Dismissible end-to-start →
///     delete with Undo snackbar)
///   - Wishlist tab: empty-state card with a soft "Save for later" CTA
///
/// Production-only slots not mirrored at the visual level (Phase-8
/// wiring brings them back):
///   - _RecallAlertSlot / _StackSafetyBannerSlot — conditional;
///     stay hidden in the all-clear fixture
///   - _ProfileNudgeSlot / _TimingAdviceSlot / _DepletionSlot — same
///   - NutrientAccumulationPanel — same
class StackV2Screen extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: V2Colors.bg,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          backgroundColor: V2Colors.bg,
          extendBody: true,
          appBar: const _StackAppBar(),
          body: const TabBarView(
            children: [_StackTab(), _WishlistTab()],
          ),
          bottomNavigationBar: showNavBar
              ? PGFrostedNavBar(
                  useV2Tones: true,
                  selectedIndex: selectedIndex,
                  onDestinationSelected: onDestinationSelected ?? (_) {},
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
      ),
    );
  }
}

// =============================================================================
// App bar — "My stack" title + add-medication + share-clinician trailing.
// Pinned TabBar lives under the bar.
// =============================================================================

class _StackAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _StackAppBar();

  @override
  Size get preferredSize => const Size.fromHeight(108); // bar + tab strip

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
        preferredSize: const Size.fromHeight(48),
        child: Container(
          color: V2Colors.bg,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: V2Spacing.space16),
          child: TabBar(
            labelColor: V2Colors.accent,
            unselectedLabelColor: V2Colors.fgMuted,
            indicatorColor: V2Colors.accent,
            indicatorSize: TabBarIndicatorSize.label,
            dividerColor: Colors.transparent,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelStyle: V2Typography.titleSm(color: V2Colors.accent),
            unselectedLabelStyle:
                V2Typography.bodyMedium(color: V2Colors.fgMuted),
            tabs: const [
              Tab(text: 'Stack'),
              Tab(text: 'Wishlist'),
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

class _StackTab extends StatelessWidget {
  const _StackTab();

  static const _items = <_StackEntry>[
    _StackEntry(
      name: 'Ultimate Omega 2X with Vitamin D3 + K2',
      brand: 'Nordic Naturals',
      score: 84,
      dosage: '2 softgels',
      frequency: 'with food',
    ),
    _StackEntry(
      name: 'Basic Nutrients 2/Day',
      brand: 'Thorne',
      score: 91,
      dosage: '2 capsules',
      frequency: 'morning',
    ),
    _StackEntry(
      name: 'L-Theanine 200mg',
      brand: 'NOW Foods',
      score: 72,
      dosage: '1 capsule',
      frequency: 'as needed',
    ),
    _StackEntry(
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
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: EdgeInsets.only(
        top: V2Spacing.space16,
        bottom: MediaQuery.of(context).padding.bottom +
            kPGNavBarHeight +
            V2Spacing.space24,
      ),
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: V2Spacing.space24),
          child: _StackSummaryCard(),
        ),
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
        ..._items.map(
          (e) => Padding(
            padding: const EdgeInsets.fromLTRB(
              V2Spacing.space24,
              0,
              V2Spacing.space24,
              V2Spacing.space12,
            ),
            child: _StackItemRow(entry: e),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Stack Summary card — Stack Health title + status pill, optional
// issue-count line, supplement / medication count chips. Numeric
// 0-100 score removed per production rule 2026-05-05.
// =============================================================================

class _StackSummaryCard extends StatelessWidget {
  const _StackSummaryCard();

  @override
  Widget build(BuildContext context) {
    // Fixture: Optimal stack (3 supplements + 1 medication, 0 issues).
    // Production reads from stackSafetyReportProvider + intelligence
    // engine; same all-clear tier.
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
          const Row(
            children: [
              _CountChip(
                icon: Icons.medication_outlined,
                label: 'Supplements',
                count: 3,
              ),
              SizedBox(width: V2Spacing.space8),
              _CountChip(
                icon: Icons.local_pharmacy_outlined,
                label: 'Medications',
                count: 1,
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
// Stack item — Dismissible row card. Supplements show a compact
// PGScoreLine; medications show a pharmacy glyph.
// =============================================================================

class _StackEntry {
  final String name;
  final String? brand;
  final int? score;
  final String? dosage;
  final String? frequency;
  final bool isMedication;

  const _StackEntry({
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
  const _StackItemRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey('stack_${entry.name}'),
      direction: DismissDirection.endToStart,
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
      onDismissed: (_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Removed ${entry.name}'),
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(label: 'Undo', onPressed: () {}),
          ),
        );
      },
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
// Wishlist tab — calm empty state. Production currently ships an
// empty-state stub here; mirror the same intent.
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
