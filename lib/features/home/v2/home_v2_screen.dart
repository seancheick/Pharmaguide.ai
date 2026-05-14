import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_eyebrow.dart';
import 'package:pharmaguide/core/components/pg_halo_background.dart';
import 'package:pharmaguide/core/components/pg_metric_card.dart';
import 'package:pharmaguide/core/components/pg_pill_button.dart';
import 'package:pharmaguide/core/components/pg_score_chip.dart';
import 'package:pharmaguide/core/components/pg_section_header.dart';
import 'package:pharmaguide/core/components/pg_severity_badge.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/core/widgets/pg_frosted_header.dart';

/// v2 Home screen — editorial composition with calm clinical rhythm.
///
/// Preserves the legacy `_PinnedSearchHeaderDelegate` benchmark
/// (PGFrostedHeader scroll-progress crossfade is the best chrome in the
/// app — keep it). Everything else redesigned to v2:
/// - Serif emotional greeting under a mono caps date eyebrow
/// - Halo radial gradient above the hero (subtle, single focal point)
/// - Editorial scan CTA card (less gradient, more crafted)
/// - PGMetricCard / PGMetricRow for personal-state metrics
/// - Compact recents list using PGSeverityBadge + PGScoreChip
/// - Ghost pill secondary CTA for Quick Check
/// - PGEyebrow trust footer
///
/// Phase 3 prototype: uses fixture data so it renders in the dev gallery
/// without provider plumbing. Real provider wiring lives in
/// HomeV2Screen's eventual production swap (Phase 8).
class HomeV2Screen extends StatelessWidget {
  final String nickname;

  const HomeV2Screen({super.key, this.nickname = 'Sean'});

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Scaffold(
      backgroundColor: V2Colors.bg,
      body: PGHaloBackground(
        // Halo sits above the hero, fading downward. Single focal point.
        origin: const Alignment(0, -0.85),
        radius: 1.2,
        intensity: 0.05,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            SliverPersistentHeader(
              pinned: true,
              delegate: _V2PinnedSearchHeaderDelegate(
                topPadding: mq.padding.top,
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                V2Spacing.space24,
                V2Spacing.space16,
                V2Spacing.space24,
                0,
              ),
              sliver: SliverToBoxAdapter(child: _HeroSection(nickname: nickname)),
            ),
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(
                V2Spacing.space24,
                V2Spacing.space32,
                V2Spacing.space24,
                0,
              ),
              sliver: SliverToBoxAdapter(child: _ScanCtaCard()),
            ),
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(
                V2Spacing.space24,
                V2Spacing.space48,
                V2Spacing.space24,
                0,
              ),
              sliver: SliverToBoxAdapter(child: _StackHealthSection()),
            ),
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(
                V2Spacing.space24,
                V2Spacing.space48,
                V2Spacing.space24,
                0,
              ),
              sliver: SliverToBoxAdapter(child: _RecentScansSection()),
            ),
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(
                V2Spacing.space24,
                V2Spacing.space48,
                V2Spacing.space24,
                0,
              ),
              sliver: SliverToBoxAdapter(child: _QuickCheckCtaSection()),
            ),
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(
                V2Spacing.space24,
                V2Spacing.space48,
                V2Spacing.space24,
                V2Spacing.space24,
              ),
              sliver: SliverToBoxAdapter(child: _TrustFooter()),
            ),
            SliverToBoxAdapter(
              child: SizedBox(height: mq.padding.bottom + V2Spacing.space48),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Hero — date eyebrow + serif greeting + body subline
// =============================================================================

class _HeroSection extends StatelessWidget {
  final String nickname;
  const _HeroSection({required this.nickname});

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 18
            ? 'Good afternoon'
            : 'Good evening';
    final date = _formatDate(DateTime.now());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PGEyebrow(date),
        const SizedBox(height: V2Spacing.space12),
        Text(
          '$greeting,\n$nickname.',
          style: V2Typography.displaySm(color: V2Colors.fg),
        ),
        const SizedBox(height: V2Spacing.space16),
        Text(
          'Scan, search, or pull up your stack.',
          style: V2Typography.bodyXl(color: V2Colors.fgMuted),
        ),
      ],
    );
  }

  String _formatDate(DateTime d) {
    const months = [
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
      'Dec'
    ];
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${weekdays[d.weekday - 1]} · ${months[d.month - 1]} ${d.day}';
  }
}

// =============================================================================
// Scan CTA — editorial card with serif label + primary pill
// =============================================================================

class _ScanCtaCard extends StatelessWidget {
  const _ScanCtaCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(V2Spacing.space24),
      decoration: BoxDecoration(
        color: V2Colors.surface,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        border: Border.all(color: V2Colors.outline),
        boxShadow: V2Shadows.md,
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: V2Colors.accentTint,
              borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
            ),
            child: const Icon(
              Icons.qr_code_scanner_rounded,
              size: 28,
              color: V2Colors.accent,
            ),
          ),
          const SizedBox(width: V2Spacing.space16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const PGEyebrow('Primary'),
                const SizedBox(height: V2Spacing.space4),
                Text(
                  'Scan a supplement',
                  style: V2Typography.titleSm(color: V2Colors.fg),
                ),
                const SizedBox(height: V2Spacing.space4),
                Text(
                  'PG Score in seconds.',
                  style: V2Typography.bodySm(color: V2Colors.fgMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: V2Spacing.space12),
          PGPillButton(
            label: 'Scan',
            variant: PGPillVariant.primary,
            onPressed: () {},
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Stack Health — 3 metric cards in a row
// =============================================================================

class _StackHealthSection extends StatelessWidget {
  const _StackHealthSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PGSectionHeader(
          eyebrow: 'Your stack',
          title: 'Stack health',
          subtitle: 'A quick read on what you’re currently taking.',
        ),
        const SizedBox(height: V2Spacing.space24),
        PGMetricRow(
          cards: [
            PGMetricCard(
              label: 'Health',
              value: '82',
              caption: 'of 100',
              delta: '+4 this week',
              trend: PGMetricTrend.up,
              onTap: () {},
            ),
            const PGMetricCard(
              label: 'Items',
              value: '6',
              caption: 'in stack',
            ),
            const PGMetricCard(
              label: 'Alerts',
              value: '2',
              caption: 'monitor',
              trailing: _SeverityDot(color: V2Colors.caution),
            ),
          ],
        ),
      ],
    );
  }
}

class _SeverityDot extends StatelessWidget {
  final Color color;
  const _SeverityDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

// =============================================================================
// Recent Scans — compact list using v2 components
// =============================================================================

class _RecentScansSection extends StatelessWidget {
  const _RecentScansSection();

  static const _items = <_RecentItem>[
    _RecentItem(
      brand: 'Thorne',
      name: 'Magnesium Glycinate',
      score: 88,
      severity: PGSeverity.safe,
    ),
    _RecentItem(
      brand: 'Pure Encapsulations',
      name: 'Daily Multivitamin',
      score: 81,
      severity: PGSeverity.safe,
    ),
    _RecentItem(
      brand: 'Nordic Naturals',
      name: 'Omega-3 + D3 + K2',
      score: 74,
      severity: PGSeverity.monitor,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PGSectionHeader(
          eyebrow: 'Recent',
          title: 'Last 3 scans',
          trailing: PGPillButton(
            label: 'View all',
            variant: PGPillVariant.ghost,
            onPressed: () {},
          ),
        ),
        const SizedBox(height: V2Spacing.space16),
        for (final item in _items)
          Padding(
            padding: const EdgeInsets.only(bottom: V2Spacing.space12),
            child: _RecentScanRow(item: item),
          ),
      ],
    );
  }
}

class _RecentItem {
  final String brand;
  final String name;
  final double score;
  final PGSeverity severity;

  const _RecentItem({
    required this.brand,
    required this.name,
    required this.score,
    required this.severity,
  });
}

class _RecentScanRow extends StatelessWidget {
  final _RecentItem item;
  const _RecentScanRow({required this.item});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
      child: InkWell(
        onTap: () {},
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        child: Container(
          padding: const EdgeInsets.all(V2Spacing.space16),
          decoration: BoxDecoration(
            color: V2Colors.surface,
            borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
            border: Border.all(color: V2Colors.outline),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PGEyebrow(item.brand, color: V2Colors.fgMuted),
                    const SizedBox(height: V2Spacing.space4),
                    Text(
                      item.name,
                      style: V2Typography.bodyMedium(color: V2Colors.fg),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: V2Spacing.space8),
                    PGSeverityBadge(severity: item.severity),
                  ],
                ),
              ),
              const SizedBox(width: V2Spacing.space16),
              PGScoreChip(score: item.score, showCaption: false),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Quick Check CTA — secondary action
// =============================================================================

class _QuickCheckCtaSection extends StatelessWidget {
  const _QuickCheckCtaSection();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(V2Spacing.space24),
      decoration: BoxDecoration(
        color: V2Colors.surface,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        border: Border.all(color: V2Colors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PGEyebrow('Off-catalog'),
          const SizedBox(height: V2Spacing.space8),
          Text(
            'Type an ingredient or brand',
            style: V2Typography.titleSm(color: V2Colors.fg),
          ),
          const SizedBox(height: V2Spacing.space8),
          Text(
            'Quick-check supplements we don’t have a scan match for.',
            style: V2Typography.body(color: V2Colors.fgMuted),
          ),
          const SizedBox(height: V2Spacing.space16),
          PGPillButton(
            label: 'Quick check',
            variant: PGPillVariant.secondary,
            icon: Icons.search_rounded,
            onPressed: () {},
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Trust Footer — sources eyebrow, plain trust line, updated date
// =============================================================================

class _TrustFooter extends StatelessWidget {
  const _TrustFooter();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PGEyebrow('Sources', color: V2Colors.fgMuted),
        const SizedBox(height: V2Spacing.space8),
        Text(
          'NIH ODS · PubMed · FDA · Clinician-reviewed.',
          style: V2Typography.bodySm(color: V2Colors.fgMuted),
        ),
        const SizedBox(height: V2Spacing.space4),
        Text(
          'Catalog updated weekly. Pull to refresh.',
          style: V2Typography.caption(color: V2Colors.fgSubtle),
        ),
      ],
    );
  }
}

// =============================================================================
// Pinned search header — v2 styling, preserves PGFrostedHeader benchmark
// =============================================================================

class _V2PinnedSearchHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double topPadding;

  static const double _verticalPadding = 12;
  static const double _launcherHeight = 52;

  _V2PinnedSearchHeaderDelegate({required this.topPadding});

  double get _height => topPadding + _verticalPadding * 2 + _launcherHeight;

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
    return PGFrostedHeader(
      scrollProgress: overlapsContent ? 1.0 : 0.0,
      child: Padding(
        padding: EdgeInsets.only(
          top: topPadding + _verticalPadding,
          left: V2Spacing.space24,
          right: V2Spacing.space24,
          bottom: _verticalPadding,
        ),
        child: const _V2SearchLauncher(),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _V2PinnedSearchHeaderDelegate old) =>
      old.topPadding != topPadding;
}

class _V2SearchLauncher extends StatelessWidget {
  const _V2SearchLauncher();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: V2Spacing.space16),
        decoration: BoxDecoration(
          color: V2Colors.surface,
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
            Text(
              'Search products or ingredients',
              style: V2Typography.body(color: V2Colors.fgMuted),
            ),
          ],
        ),
      ),
    );
  }
}
