// Recent scans — horizontal carousel of the last 10 scanned products, with a
// loading state, an empty state, and a "scan your first" CTA. Loads from
// user_scan_history joined against core product data.

import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/utils/relative_time.dart';
import 'package:pharmaguide/core/widgets/pg_card.dart';
import 'package:pharmaguide/core/widgets/pg_haptics.dart';
import 'package:pharmaguide/core/widgets/pg_modal.dart';
import 'package:pharmaguide/core/widgets/pg_pressable.dart';
import 'package:pharmaguide/core/widgets/pg_section_header.dart';
import 'package:pharmaguide/core/widgets/pg_shimmer_box.dart';
import 'package:pharmaguide/core/widgets/pg_score_ring.dart';
import 'package:pharmaguide/core/widgets/product_image.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';

/// Threshold above which the "Show all" affordance appears on the Recents
/// header. Below this count the user can see every scan in the carousel
/// itself, so a separate full-list view is unnecessary.
///
/// Previously 10, which created a UX cliff: users with 5–9 scans had no way
/// to open the bottom sheet at all. Five surfaces it once the user has any
/// real history without cluttering the day-one experience.
const int kShowAllRecentsMin = 5;

/// Force-refresh the recents carousel — invalidates both the 10-card
/// (carousel) and 25-card (Show all bottom sheet) variants so they
/// re-fetch on next build. Called by HomeScreen's pull-to-refresh
/// handler. Keeps the underlying provider file-private.
void refreshHomeRecents(WidgetRef ref) {
  ref.invalidate(_recentScansProvider(10));
  ref.invalidate(_recentScansProvider(25));
}

/// Loads recent scan history joined with core product data.
/// Auto-disposes when the home screen is not visible, ensuring fresh data
/// on each visit (fixes stale scans after navigating back from scanner).
final _recentScansProvider = FutureProvider.autoDispose
    .family<List<_RecentScanDisplay>, int>((ref, limit) async {
      final userDb = ref.watch(userDatabaseProvider);
      final coreDb = ref.watch(coreDatabaseProvider);
      final history = await userDb.getRecentScans(limit: limit);
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

class HomeRecentScansSection extends ConsumerWidget {
  const HomeRecentScansSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final scansAsync = ref.watch(_recentScansProvider(10));

    return scansAsync.when(
      loading: () => _buildLoadingState(),
      error: (_, __) => _buildEmptyState(theme, scheme, context),
      data: (scans) {
        if (scans.isEmpty) {
          return _buildEmptyState(theme, scheme, context);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PGSectionHeader(
              title: 'Recent scans',
              subtitle: 'Your last checked products',
              padding: EdgeInsets.zero,
              actionLabel: scans.length >= kShowAllRecentsMin
                  ? 'Show all'
                  : null,
              onActionTap: scans.length >= kShowAllRecentsMin
                  ? () => _showAllRecents(context, ref)
                  : null,
            ),
            const SizedBox(height: AppTheme.space12),
            SizedBox(
              height: 210,
              child: _RecentScansSnapCarousel(scans: scans),
            ),
          ],
        );
      },
    );
  }

  /// Shown while the DB query is in flight — prevents the flash-of-empty-state
  /// that previously showed "Nothing scanned yet" during loading.
  ///
  /// Uses a horizontal ListView of fixed-width (156) shimmer cards that
  /// match the real `_RecentScanCard` silhouette exactly. The previous
  /// `Row + Expanded x3` produced ~124-px-wide shimmers on a 390 iPhone,
  /// causing a visible width-jump when data landed. Shape-preserving
  /// skeletons mean the data crossfade is opacity-only, with zero layout
  /// shift.
  static Widget _buildLoadingState() {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PGSectionHeader(
          title: 'Recent scans',
          subtitle: 'Your last checked products',
          padding: EdgeInsets.zero,
        ),
        SizedBox(height: AppTheme.space12),
        SizedBox(height: 210, child: _RecentScansShimmerRow()),
      ],
    );
  }

  static Widget _buildEmptyState(
    ThemeData theme,
    ColorScheme scheme,
    BuildContext context,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PGSectionHeader(
          title: 'Recent scans',
          subtitle: 'Your last checked products',
          padding: EdgeInsets.zero,
        ),
        const SizedBox(height: AppTheme.space12),
        PGCard(
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
                  border: Border.all(color: scheme.outlineVariant, width: 0.8),
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
              const SizedBox(height: AppTheme.space4),
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
        ),
      ],
    );
  }

  static Future<void> _showAllRecents(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final platform = Theme.of(context).platform;
    final sheetBody = Consumer(
      builder: (context, ref, _) {
        final allScansAsync = ref.watch(_recentScansProvider(25));
        return allScansAsync.when(
          loading: () => const _RecentScansSheetSkeleton(),
          error: (_, __) => const _RecentScansSheetEmpty(),
          data: (scans) => _RecentScansSheet(scans: scans),
        );
      },
    );

    if (platform == TargetPlatform.iOS || platform == TargetPlatform.macOS) {
      await showCupertinoSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (_) => Material(
          color: Theme.of(context).colorScheme.surface,
          child: sheetBody,
        ),
      );
      return;
    }

    await PGModal.bottomSheet<void>(
      context: context,
      builder: (_) => sheetBody,
    );
  }
}

/// Object-like snap carousel for the populated Recents state.
///
/// Uses a PageView with `viewportFraction: 0.42` so each card occupies a
/// ~164-pt slot — close to the 156-pt visible card width with a 12-pt
/// gutter. `PageScrollPhysics` produces the iOS snap behavior — App Store
/// "Up Next" / Apple TV row pattern. On every page change a selection
/// haptic fires (iOS-feel signature: Apple Music's mini-player, Photos
/// year/month/day toggle, Wallet card swipe).
///
/// Stateful because we own a PageController and dispose it on unmount.
class _RecentScansSnapCarousel extends StatefulWidget {
  final List<_RecentScanDisplay> scans;

  const _RecentScansSnapCarousel({required this.scans});

  @override
  State<_RecentScansSnapCarousel> createState() =>
      _RecentScansSnapCarouselState();
}

class _RecentScansSnapCarouselState extends State<_RecentScansSnapCarousel> {
  late final PageController _controller;

  @override
  void initState() {
    super.initState();
    _controller = PageController(viewportFraction: 0.42);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      controller: _controller,
      // padEnds:false keeps the first card flush with the leading edge —
      // otherwise PageView centers the first/last item, which puts a
      // huge gap before card 1 that breaks the chrome rhythm.
      padEnds: false,
      physics: const PageScrollPhysics(),
      itemCount: widget.scans.length,
      onPageChanged: (_) {
        // Light selection haptic on each card-snap event. Decorative, so
        // suppressed under reduce-motion via PGHaptics.tap.
        unawaited(PGHaptics.tap(context));
      },
      itemBuilder: (context, index) {
        final scan = widget.scans[index];
        // The visual gutter between cards comes from viewportFraction's
        // natural slack: a 0.42 slot on a 390-pt phone is ~164pt, the
        // card is 156pt fixed, the trailing ~8pt reads as the gutter.
        // On smaller phones the gutter compresses but never overflows
        // because the card has a hard SizedBox at 156pt.
        return Padding(
          padding: const EdgeInsets.only(left: 4),
          child: _RecentScanCard(
            product: scan.product,
            scannedAt: scan.scannedAt,
          ),
        );
      },
    );
  }
}

/// Horizontal shimmer row that matches the data-state slot geometry
/// (156-px-wide cards, 12-px gaps, 4-px outer padding). Top-level widget so
/// the parent's `_buildLoadingState` stays `const`.
class _RecentScansShimmerRow extends StatelessWidget {
  const _RecentScansShimmerRow();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 3,
      separatorBuilder: (_, __) => const SizedBox(width: AppTheme.space12),
      itemBuilder: (_, __) =>
          const SizedBox(width: 156, child: PGShimmerCard(height: 210)),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final score = product.score100Equivalent;

    return SizedBox(
      width: 156,
      child: PGPressable(
        onTap: () => GoRouter.of(context).push('/product/${product.dsldId}'),
        child: PGCard(
          padding: const EdgeInsets.all(AppTheme.space12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Product image (OFF photo or branded placeholder).
              // G.2 — Hero wrap gives the image a shared-element flight
              // when the user taps through to the product detail screen
              // (which has the matching Hero on its identity-row image).
              // flightShuttleBuilder uses the source widget verbatim so
              // the default Material elevation overlay doesn't add a
              // tinted halo during transit (heavy-feeling on a small
              // 48pt thumbnail flying to a 96pt destination).
              Center(
                child: Hero(
                  tag: 'product-${product.dsldId}',
                  flightShuttleBuilder: (_, __, ___, ____, _____) => ProductImage(
                    dsldId: product.dsldId,
                    upc: product.upcSku,
                    productName: product.productName,
                    brandName: product.brandName ?? '',
                    formFactor: product.formFactor,
                    score: score,
                    size: 48,
                  ),
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
              ),
              const SizedBox(height: AppTheme.space6),
              // Score ring centered
              Center(
                child: PGScoreRing(score: score, size: 40, strokeWidth: 3.5),
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
              const SizedBox(height: AppTheme.space2),
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
                relativeTime(scannedAt),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontSize: 10,
                ),
              ),
            ],
          ),
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

    // PGPressable replaces Material+InkWell so the empty-state CTA gets
    // the same tactile feel as the rest of home — scale 0.96 + spring +
    // light haptic. The pill shape (radiusFull) is preserved.
    return PGPressable(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(AppTheme.radiusFull),
          border: Border.all(color: scheme.outlineVariant, width: 0.8),
        ),
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
              const SizedBox(width: AppTheme.space6),
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
    );
  }
}

class _RecentScansSheet extends StatelessWidget {
  final List<_RecentScanDisplay> scans;

  const _RecentScansSheet({required this.scans});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppTheme.space20,
          0,
          AppTheme.space20,
          AppTheme.space24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Recent scans',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: AppTheme.space4),
            Text(
              'Your last ${scans.length} scanned products',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppTheme.space16),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: scans.length,
                separatorBuilder: (_, __) => const SizedBox(height: AppTheme.space12),
                itemBuilder: (context, index) {
                  final scan = scans[index];
                  return _RecentScanListTile(
                    product: scan.product,
                    scannedAt: scan.scannedAt,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentScansSheetSkeleton extends StatelessWidget {
  const _RecentScansSheetSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppTheme.space20,
          0,
          AppTheme.space20,
          AppTheme.space24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PGShimmerBox(height: 28, width: 160, radius: 10),
            SizedBox(height: AppTheme.space8),
            PGShimmerBox(height: 16, width: 220, radius: 8),
            SizedBox(height: AppTheme.space16),
            PGShimmerCard(height: 84),
            SizedBox(height: AppTheme.space12),
            PGShimmerCard(height: 84),
            SizedBox(height: AppTheme.space12),
            PGShimmerCard(height: 84),
          ],
        ),
      ),
    );
  }
}

class _RecentScansSheetEmpty extends StatelessWidget {
  const _RecentScansSheetEmpty();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppTheme.space20,
          0,
          AppTheme.space20,
          AppTheme.space24,
        ),
        child: Text(
          'No recent scans yet.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}

class _RecentScanListTile extends StatelessWidget {
  final ProductsCoreData product;
  final DateTime scannedAt;

  const _RecentScanListTile({required this.product, required this.scannedAt});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return PGPressable(
      onTap: () => GoRouter.of(context).push('/product/${product.dsldId}'),
      child: PGCard(
        padding: const EdgeInsets.all(AppTheme.space12),
        child: Row(
          children: [
            // G.2 — Hero wrap (same tag as the carousel card and the
            // product-detail hero). Source surface is the Show-all
            // sheet; destination is the product detail.
            Hero(
              tag: 'product-${product.dsldId}',
              flightShuttleBuilder: (_, __, ___, ____, _____) => ProductImage(
                dsldId: product.dsldId,
                upc: product.upcSku,
                productName: product.productName,
                brandName: product.brandName ?? '',
                formFactor: product.formFactor,
                score: product.score100Equivalent,
                size: 48,
              ),
              child: ProductImage(
                dsldId: product.dsldId,
                upc: product.upcSku,
                productName: product.productName,
                brandName: product.brandName ?? '',
                formFactor: product.formFactor,
                score: product.score100Equivalent,
                size: 48,
              ),
            ),
            const SizedBox(width: AppTheme.space12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.productName,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.1,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (product.brandName != null &&
                      product.brandName!.isNotEmpty) ...[
                    const SizedBox(height: AppTheme.space2),
                    Text(
                      product.brandName!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: AppTheme.space6),
                  Text(
                    relativeTime(scannedAt),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppTheme.space12),
            PGScoreRing(
              score: product.score100Equivalent,
              size: 40,
              strokeWidth: 3.5,
            ),
          ],
        ),
      ),
    );
  }
}
