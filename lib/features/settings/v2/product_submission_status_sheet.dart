import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/components/pg_eyebrow.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/core/widgets/pg_modal.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/contributions/providers/product_submission_providers.dart';
import 'package:pharmaguide/services/product_submission_service.dart';

/// Opens the status surface. Used by Settings and by `submission_update`
/// push tap-through.
Future<void> showProductSubmissionStatusSheet(BuildContext context) {
  return PGModal.bottomSheet<void>(
    context: context,
    builder: (_) => const ProductSubmissionStatusSheet(),
  );
}

class ProductSubmissionStatusSheet extends ConsumerStatefulWidget {
  const ProductSubmissionStatusSheet({super.key});

  @override
  ConsumerState<ProductSubmissionStatusSheet> createState() =>
      _ProductSubmissionStatusSheetState();
}

class _ProductSubmissionStatusSheetState
    extends ConsumerState<ProductSubmissionStatusSheet>
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
    return SafeArea(
      top: false,
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
            const PGEyebrow('Catalog contributions'),
            const SizedBox(height: V2Spacing.space8),
            Text(
              'Product submissions',
              style: V2Typography.title(color: context.v2.fg),
            ),
            const SizedBox(height: V2Spacing.space8),
            Text(
              'Only products you submitted appear here. A reviewer must '
              'approve label evidence before it can enter the catalog.',
              style: V2Typography.bodySm(color: context.v2.fgMuted),
            ),
            const SizedBox(height: V2Spacing.space16),
            Flexible(
              child: submissions.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (_, _) => _StatusError(
                  onRetry: () => ref.invalidate(productSubmissionsProvider),
                ),
                data: (statuses) {
                  if (statuses.isEmpty) {
                    return Text(
                      'No product submissions yet.',
                      style: V2Typography.body(color: context.v2.fgMuted),
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: _refresh,
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: statuses.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: V2Spacing.space24),
                      itemBuilder: (_, index) =>
                          _SubmissionStatusRow(status: statuses[index]),
                    ),
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

class _SubmissionStatusRow extends ConsumerWidget {
  const _SubmissionStatusRow({required this.status});

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
    return Semantics(
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
                Text(identity, style: V2Typography.body(color: context.v2.fg)),
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
            onPressed: () =>
                context.push(Routes.productDetail(resolvedDsldId)),
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
    return _StatusDisplay(
      'Added to catalog',
      Icons.task_alt_rounded,
      p.safe,
    );
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
