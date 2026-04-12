import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/theme/app_motion.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_card.dart';
import 'package:pharmaguide/core/widgets/pg_citation_strip.dart';
import 'package:pharmaguide/core/widgets/pg_filter_chip.dart';
import 'package:pharmaguide/core/widgets/pg_search_field.dart';
import 'package:pharmaguide/core/widgets/pg_section_header.dart';
import 'package:pharmaguide/core/widgets/product_list_item.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';

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
          // Stack health
          // ----------------------------------------------------------------
          const SliverToBoxAdapter(
            child: PGSectionHeader(
              title: 'Your stack',
              subtitle: 'Supplements you take regularly',
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
            sliver: SliverToBoxAdapter(child: _StackHealthCard()),
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
              child: PGCitationStrip(
                sourceCount: 5231,
                updatedAt: DateTime(2026, 4, 11),
                disclaimer:
                    'PharmaGuide is not medical advice. Always consult your '
                    'healthcare provider before starting or stopping a supplement.',
              ),
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
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 11,
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
    final scheme = Theme.of(context).colorScheme;
    final darkerBrand = Color.lerp(scheme.primary, Colors.black, 0.25)!;
    // Dynamic Type clamp — the gradient card has a fixed icon well and
    // right chevron, so unbounded text scaling breaks the layout. Cap
    // the text scaler at 1.3x on this single hero surface; long body
    // content on this screen still honors full Dynamic Type.
    final clampedScaler = MediaQuery.textScalerOf(context)
        .clamp(minScaleFactor: 1.0, maxScaleFactor: 1.3);

    return Material(
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
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius:
                          BorderRadius.circular(AppTheme.radiusLarge),
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
                  const SizedBox(width: AppTheme.space16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Scan a supplement',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: -0.25,
                            height: 1.22,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Check safety & interactions instantly',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                            color: Colors.white.withValues(alpha: 0.82),
                            letterSpacing: 0,
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
                    color: Colors.white.withValues(alpha: 0.88),
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

// ---------------------------------------------------------------------------
// Search launcher — read-only PGSearchField that opens /search on tap
// ---------------------------------------------------------------------------

class _HomeSearchLauncher extends StatelessWidget {
  const _HomeSearchLauncher();

  @override
  Widget build(BuildContext context) {
    return PGSearchField(
      readOnly: true,
      hintText: 'Search 5,000+ supplements…',
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

class _StackHealthCard extends StatelessWidget {
  const _StackHealthCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return PGCard(
      onTap: () => GoRouter.of(context).go(Routes.stack),
      padding: const EdgeInsets.all(AppTheme.space16),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
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
                  'Track supplements you take daily to see interactions & dosing.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.space8),
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

// ---------------------------------------------------------------------------
// Recent scans — loads from user_scan_history, falls back to empty state
// ---------------------------------------------------------------------------

class _RecentScansSection extends ConsumerStatefulWidget {
  const _RecentScansSection();

  @override
  ConsumerState<_RecentScansSection> createState() =>
      _RecentScansSectionState();
}

class _RecentScansSectionState extends ConsumerState<_RecentScansSection> {
  List<_RecentScanDisplay>? _scans;

  @override
  void initState() {
    super.initState();
    _loadScans();
  }

  Future<void> _loadScans() async {
    final userDb = ref.read(userDatabaseProvider);
    final coreDb = ref.read(coreDatabaseProvider);
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
    if (mounted) setState(() => _scans = results);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (_scans == null || _scans!.isEmpty) {
      return _buildEmptyState(theme, scheme, context);
    }
    return Column(
      children: [
        for (final scan in _scans!)
          ProductListItem(product: scan.product),
      ],
    );
  }

  Widget _buildEmptyState(ThemeData theme, ColorScheme scheme, BuildContext context) {
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
                  style: TextStyle(
                    fontFamily: 'Inter',
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
