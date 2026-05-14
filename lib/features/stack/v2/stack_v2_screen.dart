import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_empty_state.dart';
import 'package:pharmaguide/core/components/pg_eyebrow.dart';
import 'package:pharmaguide/core/components/pg_metric_card.dart';
import 'package:pharmaguide/core/components/pg_pill_button.dart';
import 'package:pharmaguide/core/components/pg_pill_tab_bar.dart';
import 'package:pharmaguide/core/components/pg_score_ring.dart';
import 'package:pharmaguide/core/components/pg_section_header.dart';
import 'package:pharmaguide/core/components/pg_severity_badge.dart';
import 'package:pharmaguide/core/components/pg_stack_item_card.dart';
import 'package:pharmaguide/core/components/pg_type_badge.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_motion.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

/// v2 Stack screen — 3 pill tabs (Stack · Nutrient Analysis · Saved).
///
/// Replaces the legacy 2-tab Material `TabBar` (Stack / Wishlist) with a
/// pill-shape `PGPillTabBar` and pulls Nutrient Analysis out of the
/// Stack tab body into its own dedicated surface — per the user's
/// direction.
///
/// Phase 5 prototype: fixture data so the gallery renders without
/// providers. Real provider wiring happens at the Phase 8 production
/// swap.
class StackV2Screen extends StatefulWidget {
  /// When true, the Stack tab starts empty (for previewing the empty
  /// state crafted with PGEmptyState).
  final bool emptyStack;

  const StackV2Screen({super.key, this.emptyStack = false});

  @override
  State<StackV2Screen> createState() => _StackV2ScreenState();
}

class _StackV2ScreenState extends State<StackV2Screen> {
  int _tab = 0;
  final _expanded = <String>{};

  void _toggleExpand(String id) {
    setState(() {
      if (_expanded.contains(id)) {
        _expanded.remove(id);
      } else {
        _expanded.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: V2Colors.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _TopBar(onAddMedication: () {}),
            const SizedBox(height: V2Spacing.space12),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: V2Spacing.space24,
              ),
              child: PGPillTabBar(
                tabs: const ['Stack', 'Nutrient Analysis', 'Saved'],
                currentIndex: _tab,
                onChanged: (i) => setState(() => _tab = i),
              ),
            ),
            const SizedBox(height: V2Spacing.space16),
            Expanded(
              child: AnimatedSwitcher(
                duration: V2Motion.base,
                switchInCurve: V2Motion.decelerate,
                switchOutCurve: V2Motion.smooth,
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.02),
                      end: Offset.zero,
                    ).animate(anim),
                    child: child,
                  ),
                ),
                child: _bodyForTab(_tab),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bodyForTab(int tab) {
    return KeyedSubtree(
      key: ValueKey('stack-v2-tab-$tab'),
      child: switch (tab) {
        0 => _StackTab(
            emptyStack: widget.emptyStack,
            expanded: _expanded,
            onToggleExpand: _toggleExpand,
          ),
        1 => const _NutrientAnalysisTab(),
        _ => const _SavedTab(),
      },
    );
  }
}

// =============================================================================
// Top bar — title + add medication action
// =============================================================================

class _TopBar extends StatelessWidget {
  final VoidCallback onAddMedication;
  const _TopBar({required this.onAddMedication});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        V2Spacing.space24,
        V2Spacing.space12,
        V2Spacing.space24,
        0,
      ),
      child: Row(
        children: [
          Text(
            'My stack',
            style: V2Typography.title(color: V2Colors.fg),
          ),
          const Spacer(),
          PGPillButton(
            label: 'Add',
            icon: Icons.add_rounded,
            variant: PGPillVariant.ghost,
            onPressed: onAddMedication,
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Tab 1 — Stack list
// =============================================================================

class _StackTab extends StatelessWidget {
  final bool emptyStack;
  final Set<String> expanded;
  final ValueChanged<String> onToggleExpand;

  const _StackTab({
    required this.emptyStack,
    required this.expanded,
    required this.onToggleExpand,
  });

  static const _fixtures = <_StackFixture>[
    _StackFixture(
      id: 'mag',
      brand: 'Thorne',
      name: 'Magnesium Glycinate',
      doseLine: '200 mg · 2 capsules nightly',
      imageUrl: null,
      type: PGItemType.supplement,
      score: 88,
    ),
    _StackFixture(
      id: 'omega',
      brand: 'Nordic Naturals',
      name: 'Ultimate Omega + D3 + K2',
      doseLine: '2 softgels with food',
      imageUrl: null,
      type: PGItemType.supplement,
      score: 74,
      flagSeverity: PGSeverity.monitor,
      flagLabel: 'Bleeding risk · check with prescriber',
    ),
    _StackFixture(
      id: 'multi',
      brand: 'Pure Encapsulations',
      name: 'Daily Multivitamin Complex',
      doseLine: '6 capsules daily',
      imageUrl: null,
      type: PGItemType.supplement,
      score: 81,
    ),
    _StackFixture(
      id: 'warfarin',
      brand: 'Bristol-Myers Squibb',
      name: 'Coumadin (Warfarin)',
      doseLine: '2.5 mg · once daily',
      imageUrl: null,
      type: PGItemType.medication,
    ),
    _StackFixture(
      id: 'sertraline',
      brand: 'Pfizer',
      name: 'Zoloft (Sertraline)',
      doseLine: '50 mg · once daily',
      imageUrl: null,
      type: PGItemType.medication,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    if (emptyStack) {
      return _EmptyStack();
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        V2Spacing.space24,
        0,
        V2Spacing.space24,
        V2Spacing.space48,
      ),
      children: [
        const _StackHealthHeader(),
        const SizedBox(height: V2Spacing.space24),
        const PGSectionHeader(
          eyebrow: 'Active',
          title: '5 items in your stack',
        ),
        const SizedBox(height: V2Spacing.space16),
        for (final f in _fixtures)
          Padding(
            padding: const EdgeInsets.only(bottom: V2Spacing.space12),
            child: PGStackItemCard(
              name: f.name,
              brand: f.brand,
              doseLine: f.doseLine,
              imageUrl: f.imageUrl,
              type: f.type,
              score: f.score,
              flagSeverity: f.flagSeverity,
              flagLabel: f.flagLabel,
              expanded: expanded.contains(f.id),
              onTap: () => onToggleExpand(f.id),
              expandedDetails: _ExpandedDetails(fixture: f),
            ),
          ),
      ],
    );
  }
}

class _StackFixture {
  final String id;
  final String brand;
  final String name;
  final String doseLine;
  final String? imageUrl;
  final PGItemType type;
  final double? score;
  final PGSeverity? flagSeverity;
  final String? flagLabel;

  const _StackFixture({
    required this.id,
    required this.brand,
    required this.name,
    required this.doseLine,
    required this.imageUrl,
    required this.type,
    this.score,
    this.flagSeverity,
    this.flagLabel,
  });
}

class _StackHealthHeader extends StatelessWidget {
  const _StackHealthHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(V2Spacing.space24),
      decoration: BoxDecoration(
        color: V2Colors.surface,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        border: Border.all(color: V2Colors.outline),
        boxShadow: V2Shadows.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const PGScoreRing(score: 82, size: 76, caption: 'Stack health'),
          const SizedBox(width: V2Spacing.space24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const PGEyebrow('This week'),
                const SizedBox(height: V2Spacing.space8),
                Text(
                  'Mostly clear.',
                  style: V2Typography.titleSm(color: V2Colors.fg),
                ),
                const SizedBox(height: V2Spacing.space4),
                Text(
                  '1 item to monitor with your prescriber.',
                  style: V2Typography.bodySm(color: V2Colors.fgMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpandedDetails extends StatelessWidget {
  final _StackFixture fixture;
  const _ExpandedDetails({required this.fixture});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PGEyebrow('Why it’s in your stack'),
        const SizedBox(height: V2Spacing.space8),
        Text(
          fixture.type == PGItemType.medication
              ? 'Prescribed medication — included so we can check supplement '
                  'interactions against it.'
              : 'Tracking dose, timing, and overlap with the rest of your stack.',
          style: V2Typography.body(color: V2Colors.fgMuted),
        ),
        const SizedBox(height: V2Spacing.space12),
        Row(
          children: [
            PGPillButton(
              label: 'Edit',
              variant: PGPillVariant.ghost,
              icon: Icons.edit_outlined,
              onPressed: () {},
            ),
            const SizedBox(width: V2Spacing.space8),
            PGPillButton(
              label: 'Remove',
              variant: PGPillVariant.ghost,
              icon: Icons.delete_outline_rounded,
              onPressed: () {},
            ),
          ],
        ),
      ],
    );
  }
}

class _EmptyStack extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: PGEmptyState(
        eyebrow: 'Your stack',
        icon: Icons.layers_outlined,
        headline: 'Build your stack.',
        body:
            'Scan a supplement or add a medication to start checking interactions, '
            'overlaps, and personal fit.',
        primaryLabel: 'Scan a supplement',
        primaryIcon: Icons.qr_code_scanner_rounded,
        onPrimaryTap: () {},
        secondaryLabel: 'Add medication',
        onSecondaryTap: () {},
      ),
    );
  }
}

// =============================================================================
// Tab 2 — Nutrient analysis
// =============================================================================

class _NutrientAnalysisTab extends StatelessWidget {
  const _NutrientAnalysisTab();

  static const _nutrients = <_Nutrient>[
    _Nutrient(label: 'Vitamin D', value: '4,000 IU', pct: 1.00,
        caption: 'At upper limit', trend: PGMetricTrend.flat),
    _Nutrient(label: 'Magnesium', value: '420 mg', pct: 1.00,
        caption: '100% of UL', trend: PGMetricTrend.flat),
    _Nutrient(label: 'Zinc', value: '25 mg', pct: 0.63, caption: 'within range'),
    _Nutrient(label: 'Vitamin B6', value: '50 mg', pct: 0.50, caption: 'within range'),
    _Nutrient(label: 'Folate', value: '600 mcg', pct: 0.85,
        caption: 'approaching UL', trend: PGMetricTrend.down),
    _Nutrient(label: 'Calcium', value: '200 mg', pct: 0.08, caption: 'low'),
  ];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        V2Spacing.space24,
        0,
        V2Spacing.space24,
        V2Spacing.space48,
      ),
      children: [
        const PGSectionHeader(
          eyebrow: 'Today',
          title: 'Cumulative nutrient intake',
          subtitle: 'From everything in your stack, totaled per day.',
        ),
        const SizedBox(height: V2Spacing.space24),
        const PGMetricRow(
          cards: [
            PGMetricCard(
              label: 'At limit',
              value: '2',
              caption: 'nutrients',
              delta: 'monitor',
              trend: PGMetricTrend.down,
            ),
            PGMetricCard(
              label: 'Within range',
              value: '8',
              caption: 'safe daily',
            ),
          ],
        ),
        const SizedBox(height: V2Spacing.space32),
        const PGSectionHeader(
          eyebrow: 'Breakdown',
          title: 'By nutrient',
        ),
        const SizedBox(height: V2Spacing.space16),
        for (final n in _nutrients)
          Padding(
            padding: const EdgeInsets.only(bottom: V2Spacing.space12),
            child: _NutrientRow(nutrient: n),
          ),
      ],
    );
  }
}

class _Nutrient {
  final String label;
  final String value;

  /// Fraction of upper-limit (0.0 → 1.0+). Used to color the bar.
  final double pct;
  final String caption;
  final PGMetricTrend trend;

  const _Nutrient({
    required this.label,
    required this.value,
    required this.pct,
    required this.caption,
    this.trend = PGMetricTrend.flat,
  });
}

class _NutrientRow extends StatelessWidget {
  final _Nutrient nutrient;
  const _NutrientRow({required this.nutrient});

  Color _barColor(double pct) {
    if (pct >= 1.0) return V2Colors.caution;
    if (pct >= 0.8) return V2Colors.monitor;
    return V2Colors.safe;
  }

  @override
  Widget build(BuildContext context) {
    final clamped = nutrient.pct.clamp(0.0, 1.0);
    final color = _barColor(nutrient.pct);

    return Container(
      padding: const EdgeInsets.all(V2Spacing.space16),
      decoration: BoxDecoration(
        color: V2Colors.surface,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        border: Border.all(color: V2Colors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  nutrient.label,
                  style: V2Typography.bodyMedium(color: V2Colors.fg),
                ),
              ),
              Text(
                nutrient.value,
                style: V2Typography.monoData(color: V2Colors.fg),
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
                    widthFactor: clamped,
                    child: Container(color: color),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: V2Spacing.space8),
          Text(
            nutrient.caption,
            style: V2Typography.caption(color: V2Colors.fgMuted),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Tab 3 — Saved / bookmarks
// =============================================================================

class _SavedTab extends StatelessWidget {
  const _SavedTab();

  static const _items = <_StackFixture>[
    _StackFixture(
      id: 'lions-mane',
      brand: 'Real Mushrooms',
      name: 'Lion’s Mane Extract',
      doseLine: 'Saved for review',
      imageUrl: null,
      type: PGItemType.bookmark,
      score: 79,
    ),
    _StackFixture(
      id: 'creatine',
      brand: 'Thorne',
      name: 'Creatine Monohydrate',
      doseLine: 'Saved for review',
      imageUrl: null,
      type: PGItemType.bookmark,
      score: 91,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) {
      return const Center(
        child: PGEmptyState(
          eyebrow: 'Saved',
          icon: Icons.bookmark_outline_rounded,
          headline: 'Nothing saved yet.',
          body:
              'Bookmark supplements you’re researching. They’ll wait here until '
              'you’re ready to add them to your stack.',
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        V2Spacing.space24,
        0,
        V2Spacing.space24,
        V2Spacing.space48,
      ),
      children: [
        const PGSectionHeader(
          eyebrow: 'Bookmarked',
          title: 'Saved for review',
          subtitle:
              'Not in your stack yet. We’ll check fit against your profile '
              'when you’re ready.',
        ),
        const SizedBox(height: V2Spacing.space16),
        for (final f in _items)
          Padding(
            padding: const EdgeInsets.only(bottom: V2Spacing.space12),
            child: PGStackItemCard(
              name: f.name,
              brand: f.brand,
              doseLine: f.doseLine,
              imageUrl: f.imageUrl,
              type: f.type,
              score: f.score,
            ),
          ),
      ],
    );
  }
}
