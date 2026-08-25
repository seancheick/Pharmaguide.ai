import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/components/pg_eyebrow.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/contributions/providers/product_submission_providers.dart';
import 'package:pharmaguide/services/product_submission_service.dart';

/// Full-page catalog-contribution surface: impact stats, every submission
/// with its verdict and guidance, and how the pipeline works. Replaces the
/// old bottom sheet — a sheet stops working at fifty submissions, and the
/// impact header is the contributor's "my work mattered" moment.
class ProductSubmissionsScreen extends ConsumerStatefulWidget {
  const ProductSubmissionsScreen({super.key});

  @override
  ConsumerState<ProductSubmissionsScreen> createState() =>
      _ProductSubmissionsScreenState();
}

class _ProductSubmissionsScreenState
    extends ConsumerState<ProductSubmissionsScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A review can land while the app is backgrounded; refresh on return.
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(productSubmissionsProvider);
    }
  }

  Future<void> _refresh() async {
    ref.invalidate(productSubmissionsProvider);
    await ref.read(productSubmissionsProvider.future);
  }

  @override
  Widget build(BuildContext context) {
    final submissions = ref.watch(productSubmissionsProvider);
    return Scaffold(
      backgroundColor: context.v2.bg,
      appBar: AppBar(
        backgroundColor: context.v2.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: context.v2.fg),
        title: Text(
          'Your contributions',
          style: V2Typography.titleSm(color: context.v2.fg),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        top: false,
        child: submissions.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(
            child: _StatusError(
              onRetry: () => ref.invalidate(productSubmissionsProvider),
            ),
          ),
          data: (statuses) => RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                V2Spacing.space24,
                V2Spacing.space8,
                V2Spacing.space24,
                V2Spacing.space24,
              ),
              children: [
                const PGEyebrow('Catalog contributions'),
                const SizedBox(height: V2Spacing.space8),
                Text(
                  'Every product you add makes PharmaGuide more accurate '
                  'for everyone.',
                  style: V2Typography.bodySm(color: context.v2.fgMuted),
                ),
                const SizedBox(height: V2Spacing.space16),
                _ImpactGrid(statuses: statuses),
                const SizedBox(height: V2Spacing.space24),
                Text(
                  'Your submissions',
                  style: V2Typography.titleSm(color: context.v2.fg),
                ),
                const SizedBox(height: V2Spacing.space12),
                if (statuses.isEmpty)
                  _EmptyState()
                else
                  for (final status in statuses) ...[
                    _SubmissionCard(status: status),
                    const SizedBox(height: V2Spacing.space12),
                  ],
                const SizedBox(height: V2Spacing.space16),
                Text(
                  'How it works',
                  style: V2Typography.titleSm(color: context.v2.fg),
                ),
                const SizedBox(height: V2Spacing.space12),
                const _HowItWorksStep(
                  index: 1,
                  title: 'Submit',
                  body:
                      'Scan a product we don’t have and photograph its '
                      'label.',
                ),
                const _HowItWorksStep(
                  index: 2,
                  title: 'Human review',
                  body:
                      'A reviewer verifies every label — nothing enters '
                      'the catalog unchecked.',
                ),
                const _HowItWorksStep(
                  index: 3,
                  title: 'Released to everyone',
                  body:
                      'Approved products ship in the next catalog update, '
                      'on every device.',
                ),
                const SizedBox(height: V2Spacing.space16),
                Container(
                  padding: const EdgeInsets.all(V2Spacing.space16),
                  decoration: BoxDecoration(
                    color: context.v2.accentTint,
                    borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
                  ),
                  child: Text(
                    'Points track your impact. We’re building perks to '
                    'redeem them for — approved contributions already '
                    'count.',
                    style: V2Typography.bodySm(color: context.v2.fg),
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

class _ImpactGrid extends StatelessWidget {
  const _ImpactGrid({required this.statuses});

  final List<ProductSubmissionSummary> statuses;

  @override
  Widget build(BuildContext context) {
    final pending = statuses
        .where(
          (s) =>
              s.uploadReady &&
              (s.reviewStatus == ProductSubmissionReviewStatus.submitted ||
                  s.reviewStatus == ProductSubmissionReviewStatus.underReview),
        )
        .length;
    final approved = statuses
        .where((s) => s.reviewStatus == ProductSubmissionReviewStatus.approved)
        .length;
    final points = contributionPoints(statuses);
    Widget card({
      required Key key,
      required IconData icon,
      required Color accent,
      required int value,
      required String label,
    }) => Container(
      key: key,
      decoration: BoxDecoration(
        color: context.v2.surface,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        border: Border.all(color: context.v2.outline),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The old design's colored edge, as an inner bar: a mixed
            // border color cannot legally carry a borderRadius.
            Container(
              width: 3,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(V2Spacing.radiusCard),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(V2Spacing.space16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Icon(icon, color: accent, size: 20),
                        Text(
                          '$value',
                          style: V2Typography.title(color: context.v2.fg),
                        ),
                      ],
                    ),
                    const SizedBox(height: V2Spacing.space8),
                    Text(
                      label,
                      style: V2Typography.bodySm(color: context.v2.fgMuted),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final oneColumn =
            constraints.maxWidth < 300 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.3;
        final cardWidth = oneColumn
            ? constraints.maxWidth
            : (constraints.maxWidth - V2Spacing.space12) / 2;
        return Wrap(
          spacing: V2Spacing.space12,
          runSpacing: V2Spacing.space12,
          children: [
            SizedBox(
              width: cardWidth,
              child: card(
                key: const Key('contributions-stat-pending'),
                icon: Icons.schedule_rounded,
                accent: context.v2.caution,
                value: pending,
                label: 'Pending review',
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: card(
                key: const Key('contributions-stat-approved'),
                icon: Icons.verified_outlined,
                accent: context.v2.safe,
                value: approved,
                label: 'Approved',
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: card(
                key: const Key('contributions-stat-total'),
                icon: Icons.upload_outlined,
                accent: context.v2.accent,
                value: statuses.length,
                label: 'Total submissions',
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: card(
                key: const Key('contributions-stat-points'),
                icon: Icons.star_outline_rounded,
                accent: context.v2.accentStrong,
                value: points,
                label: 'Points earned',
              ),
            ),
          ],
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(V2Spacing.space16),
      decoration: BoxDecoration(
        border: Border.all(color: context.v2.outline),
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
      ),
      child: Text(
        'No submissions yet. Scan a product we don’t have and it will '
        'appear here.',
        style: V2Typography.body(color: context.v2.fgMuted),
      ),
    );
  }
}

class _HowItWorksStep extends StatelessWidget {
  const _HowItWorksStep({
    required this.index,
    required this.title,
    required this.body,
  });

  final int index;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: V2Spacing.space12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: context.v2.accent,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$index',
              style: V2Typography.bodySm(color: context.v2.bg),
            ),
          ),
          const SizedBox(width: V2Spacing.space12),
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
                  body,
                  style: V2Typography.bodySm(color: context.v2.fgMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SubmissionCard extends ConsumerWidget {
  const _SubmissionCard({required this.status});

  final ProductSubmissionSummary status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final display = _statusDisplay(context.v2, status);
    final identity = switch (status.kind) {
      ProductSubmissionKind.labelMismatch => 'Catalog correction',
      ProductSubmissionKind.missingProduct =>
        'UPC ${status.upc ?? 'unavailable'}',
      null => 'Submission details unavailable',
    };
    final guidance = _resolutionGuidance(status);
    return Container(
      padding: const EdgeInsets.all(V2Spacing.space16),
      decoration: BoxDecoration(
        color: context.v2.surface,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        border: Border.all(color: context.v2.outline),
      ),
      child: Semantics(
        container: true,
        label: '$identity. ${display.label}.',
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(display.icon, color: display.color, size: 24),
            const SizedBox(width: V2Spacing.space12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    identity,
                    style: V2Typography.body(color: context.v2.fg),
                  ),
                  const SizedBox(height: V2Spacing.space4),
                  Text(
                    display.label,
                    style: V2Typography.bodySm(color: display.color),
                  ),
                  if (guidance != null) ...[
                    const SizedBox(height: V2Spacing.space4),
                    Text(
                      guidance,
                      style: V2Typography.bodySm(color: context.v2.fgMuted),
                    ),
                  ],
                  if (status.promotedCatalogVersion case final version?) ...[
                    const SizedBox(height: V2Spacing.space4),
                    Text(
                      'Catalog version $version',
                      style: V2Typography.caption(color: context.v2.fgMuted),
                    ),
                  ],
                  if (status.resolvedDsldId case final resolvedId?)
                    _GatedProductLink(resolvedDsldId: resolvedId),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "View product" renders only after the id is confirmed present in the
/// INSTALLED local catalog — a promoted product only becomes openable once
/// a catalog update carrying it reaches this device.
class _GatedProductLink extends ConsumerWidget {
  const _GatedProductLink({required this.resolvedDsldId});

  final String resolvedDsldId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder(
      future: ref.read(coreDatabaseProvider).findById(resolvedDsldId),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }
        if (snapshot.data == null) {
          return Padding(
            padding: const EdgeInsets.only(top: V2Spacing.space4),
            child: Text(
              'Available after your next catalog update.',
              style: V2Typography.caption(color: context.v2.fgMuted),
            ),
          );
        }
        return Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: Key('submission-view-product-$resolvedDsldId'),
            onPressed: () => context.push(Routes.productDetail(resolvedDsldId)),
            child: const Text('View product'),
          ),
        );
      },
    );
  }
}

class _StatusDisplay {
  const _StatusDisplay(this.label, this.icon, this.color);

  final String label;
  final IconData icon;
  final Color color;
}

/// User-facing translation of the closed resolution vocabulary. Returns
/// null when there is nothing actionable to add to the status label.
String? _resolutionGuidance(ProductSubmissionSummary status) {
  if (status.reviewStatus == ProductSubmissionReviewStatus.rejected ||
      status.reviewStatus == ProductSubmissionReviewStatus.duplicate) {
    return switch (status.resolutionCode) {
      ProductSubmissionResolutionCode.photoQuality =>
        'The photos were too blurry or dark to read. Try again with more '
            'light and steadier hands.',
      ProductSubmissionResolutionCode.missingPanel =>
        'We couldn’t see the full Supplement Facts panel. Try again and '
            'capture the whole panel.',
      ProductSubmissionResolutionCode.labelUnreadable =>
        'The label wasn’t readable enough to verify. A retake with the '
            'label flat and in focus usually fixes this.',
      ProductSubmissionResolutionCode.notASupplement =>
        'This product isn’t a dietary supplement, so it doesn’t belong in '
            'the PharmaGuide catalog.',
      ProductSubmissionResolutionCode.alreadyInCatalog =>
        'Good news — this product is already in the catalog.',
      ProductSubmissionResolutionCode.duplicateSubmission =>
        'Someone beat you to it — this product is already on its way into '
            'the catalog.',
      ProductSubmissionResolutionCode.other => status.resolutionDetail,
      null => null,
    };
  }
  return null;
}

_StatusDisplay _statusDisplay(V2Palette p, ProductSubmissionSummary status) {
  if (!status.hasKnownState) {
    return _StatusDisplay(
      'Status unavailable',
      Icons.help_outline_rounded,
      p.fgMuted,
    );
  }
  if (status.isComplete) {
    return _StatusDisplay('Added to catalog', Icons.task_alt_rounded, p.safe);
  }
  if (status.uploadState != ProductSubmissionUploadState.ready) {
    return _StatusDisplay(
      'Upload incomplete — start a new submission to try again',
      Icons.cloud_off_outlined,
      p.caution,
    );
  }
  return switch (status.reviewStatus) {
    ProductSubmissionReviewStatus.submitted => _StatusDisplay(
      'Waiting for review',
      Icons.schedule_rounded,
      p.fgMuted,
    ),
    ProductSubmissionReviewStatus.underReview => _StatusDisplay(
      'Under review',
      Icons.fact_check_outlined,
      p.accent,
    ),
    ProductSubmissionReviewStatus.approved => _StatusDisplay(
      'Approved — waiting for a catalog release',
      Icons.verified_outlined,
      p.safe,
    ),
    ProductSubmissionReviewStatus.rejected => _StatusDisplay(
      'Not added',
      Icons.block_outlined,
      p.fgMuted,
    ),
    ProductSubmissionReviewStatus.duplicate => _StatusDisplay(
      'Already under review',
      Icons.content_copy_outlined,
      p.fgMuted,
    ),
    ProductSubmissionReviewStatus.unknown => throw StateError(
      'Unknown review state must be handled before display.',
    ),
  };
}

class _StatusError extends StatelessWidget {
  const _StatusError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Submission status is unavailable right now.',
          style: V2Typography.body(color: context.v2.fgMuted),
        ),
        const SizedBox(height: V2Spacing.space12),
        TextButton(onPressed: onRetry, child: const Text('Try again')),
      ],
    );
  }
}
