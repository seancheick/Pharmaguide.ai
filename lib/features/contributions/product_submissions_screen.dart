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
import 'package:pharmaguide/features/contributions/product_submission_resolution_copy.dart';
import 'package:pharmaguide/features/contributions/add_missing_product_sheet.dart';
import 'package:pharmaguide/features/product_detail/widgets/label_mismatch_sheet.dart';
import 'package:pharmaguide/features/scanner/missing_product_submission_sheet.dart';
import 'package:pharmaguide/services/product_submission_draft_store.dart';
import 'package:pharmaguide/services/product_submission_service.dart';

typedef ResubmitProductSubmission =
    Future<void> Function(ProductSubmissionSummary status);
typedef HideProductSubmission =
    Future<void> Function(ProductSubmissionSummary status);

/// Full-page catalog-contribution surface: impact stats, every submission
/// with its verdict and guidance, and how the pipeline works. Replaces the
/// old bottom sheet — a sheet stops working at fifty submissions, and the
/// impact header is the contributor's "my work mattered" moment.
class ProductSubmissionsScreen extends ConsumerStatefulWidget {
  const ProductSubmissionsScreen({
    super.key,
    this.onResubmit,
    this.onHide,
    this.onRetake,
  });

  /// Injected so the status surface stays independent of the capture route.
  /// The production lineage-aware handler is wired with Task 4.
  final ResubmitProductSubmission? onResubmit;
  final HideProductSubmission? onHide;

  /// Answers a reviewer's request for new photos on the same submission.
  final ResubmitProductSubmission? onRetake;

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
    ref.invalidate(pendingProductSubmissionDraftsProvider);
    await ref.read(productSubmissionsProvider.future);
  }

  Future<void> _addFromPhotos() async {
    final upc = await showAddMissingProductIdentitySheet(context);
    if (!mounted || upc == null) return;
    await showMissingProductSubmissionSheet(
      context,
      upc: upc,
      preferLibrary: true,
      service: ref.read(productSubmissionServiceProvider),
    );
    if (!mounted) return;
    ref.invalidate(productSubmissionsProvider);
    ref.invalidate(pendingProductSubmissionDraftsProvider);
  }

  /// Reopen capture for a barcode this device still holds photos for. The
  /// sheet recognises the saved capture and offers to finish it.
  Future<void> _finishPending(PendingProductSubmission pending) async {
    await showMissingProductSubmissionSheet(
      context,
      upc: pending.upc,
      service: ref.read(productSubmissionServiceProvider),
      resubmissionOf: pending.resubmissionOf,
    );
    if (!mounted) return;
    ref.invalidate(productSubmissionsProvider);
    ref.invalidate(pendingProductSubmissionDraftsProvider);
  }

  Future<void> _resubmit(ProductSubmissionSummary status) async {
    final service = ref.read(productSubmissionServiceProvider);
    switch (status.kind) {
      case ProductSubmissionKind.missingProduct:
        final upc = status.upc;
        if (upc == null) return;
        await showMissingProductSubmissionSheet(
          context,
          upc: upc,
          service: service,
          resubmissionOf: status.submissionId,
        );
      case ProductSubmissionKind.labelMismatch:
        final product = status.mismatchProduct;
        if (product == null) return;
        await showLabelMismatchSheet(
          context,
          product: product,
          isAuthenticated: true,
          reportService: service,
          resubmissionOf: status.submissionId,
        );
      case null:
        return;
    }
    if (mounted) ref.invalidate(productSubmissionsProvider);
  }

  /// Same submission, same review: only the photos the reviewer asked about
  /// are retaken. An unfinished retake resumes with the photos saved on this
  /// phone.
  Future<void> _retake(ProductSubmissionSummary status) async {
    final service = ref.read(productSubmissionServiceProvider);
    final upc = status.upc;
    if (upc == null) return;
    final ProductSubmissionRetake plan;
    try {
      plan = await service.prepareRetake(status);
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Couldn’t open this request. Try again in a moment.'),
        ),
      );
      return;
    }
    if (!mounted) return;
    await showMissingProductSubmissionSheet(
      context,
      upc: upc,
      service: service,
      retake: plan,
    );
    if (mounted) ref.invalidate(productSubmissionsProvider);
  }

  Future<void> _hide(ProductSubmissionSummary status) async {
    final confirmed = await PGModal.bottomSheet<bool>(
      context: context,
      builder: (_) => const _HideSubmissionSheet(),
    );
    if (confirmed != true || !mounted) return;

    try {
      final handler =
          widget.onHide ??
          (status) => ref
              .read(productSubmissionServiceProvider)
              .hideFromHistory(status.submissionId);
      await handler(status);
      if (!mounted) return;
      ref.invalidate(productSubmissionsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Removed from your contribution history.'),
        ),
      );
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Couldn’t hide this submission. Please try again.'),
        ),
      );
    }
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
        actions: [
          Semantics(
            button: true,
            label: 'Add a missing product',
            child: IconButton.filledTonal(
              key: const Key('contributions-add-product'),
              tooltip: 'Add a missing product',
              onPressed: _addFromPhotos,
              iconSize: 26,
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              icon: const Icon(Icons.add_rounded),
            ),
          ),
        ],
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
                _ImpactGrid(
                  statuses: statuses,
                  // Null while loading or unreadable: shown as a dash, since
                  // zero would tell the user they have earned nothing.
                  points: ref.watch(contributionPointsProvider).value,
                ),
                const SizedBox(height: V2Spacing.space24),
                _UnfinishedCaptures(onFinish: _finishPending),
                Text(
                  'Your submissions',
                  style: V2Typography.titleSm(color: context.v2.fg),
                ),
                const SizedBox(height: V2Spacing.space12),
                if (statuses.isEmpty)
                  _EmptyState()
                else
                  for (final status in statuses) ...[
                    _SubmissionCard(
                      status: status,
                      onResubmit: widget.onResubmit ?? _resubmit,
                      onRetake: widget.onRetake ?? _retake,
                      onHide: _hide,
                    ),
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
                    'Each product added to the catalog earns 10 points. '
                    'We plan to offer discounts and other rewards in the '
                    'future; details may change as the program develops.',
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

/// Photos this device saved that never reached the server.
///
/// Shown above the server-backed history because it is the one thing here the
/// user can still act on offline, and because the alternative route back to an
/// interrupted capture is rescanning the same barcode.
class _UnfinishedCaptures extends ConsumerWidget {
  const _UnfinishedCaptures({required this.onFinish});

  final Future<void> Function(PendingProductSubmission pending) onFinish;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingProductSubmissionDraftsProvider);
    final drafts = pending.value ?? const <PendingProductSubmission>[];
    if (drafts.isEmpty) return const SizedBox.shrink();
    return Column(
      key: const Key('unfinished-captures'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Not sent yet', style: V2Typography.titleSm(color: context.v2.fg)),
        const SizedBox(height: V2Spacing.space8),
        Text(
          'These photos are still on this phone. Nobody has seen them yet.',
          style: V2Typography.bodySm(color: context.v2.fgMuted),
        ),
        const SizedBox(height: V2Spacing.space12),
        for (final draft in drafts) ...[
          Card(
            margin: const EdgeInsets.only(bottom: V2Spacing.space8),
            child: ListTile(
              key: Key('unfinished-${draft.submissionId}'),
              title: Text(
                '${draft.photoCount} '
                '${draft.photoCount == 1 ? 'photo' : 'photos'} ready to send',
                style: V2Typography.bodySm(color: context.v2.fg),
              ),
              subtitle: Text(
                'Barcode ${draft.upc}',
                style: V2Typography.monoData(color: context.v2.fgMuted),
              ),
              trailing: FilledButton(
                onPressed: () => onFinish(draft),
                child: const Text('Finish sending'),
              ),
            ),
          ),
        ],
        const SizedBox(height: V2Spacing.space24),
      ],
    );
  }
}

class _ImpactGrid extends StatelessWidget {
  const _ImpactGrid({required this.statuses, required this.points});

  final List<ProductSubmissionSummary> statuses;
  final int? points;

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
    final approved = statuses.where((s) => s.isComplete).length;
    final submitted = statuses.where((s) => s.uploadReady).length;
    final notAdded = statuses
        .where(
          (s) =>
              s.uploadReady &&
              (s.reviewStatus == ProductSubmissionReviewStatus.rejected ||
                  s.reviewStatus == ProductSubmissionReviewStatus.duplicate),
        )
        .length;
    final awaitingRelease = statuses
        .where(
          (s) =>
              s.uploadReady &&
              s.reviewStatus == ProductSubmissionReviewStatus.approved &&
              !s.isComplete,
        )
        .length;
    Widget card({
      required Key key,
      required IconData icon,
      required Color accent,
      required String value,
      required String label,
      VoidCallback? onTap,
      String? tapHint,
    }) => Semantics(
      button: onTap != null,
      hint: tapHint,
      child: Material(
        key: key,
        color: context.v2.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
          side: BorderSide(color: context.v2.outline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The old design's colored edge, as an inner bar: a mixed
                // border color cannot legally carry a borderRadius.
                Container(width: 3, color: accent),
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
                              value,
                              style: V2Typography.title(color: context.v2.fg),
                            ),
                          ],
                        ),
                        const SizedBox(height: V2Spacing.space8),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                label,
                                style: V2Typography.bodySm(
                                  color: context.v2.fgMuted,
                                ),
                              ),
                            ),
                            if (onTap != null) ...[
                              const SizedBox(width: V2Spacing.space4),
                              Icon(
                                Icons.info_outline_rounded,
                                color: context.v2.fgMuted,
                                size: 15,
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
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
                value: '$pending',
                label: 'Pending review',
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: card(
                key: const Key('contributions-stat-approved'),
                icon: Icons.verified_outlined,
                accent: context.v2.safe,
                value: '$approved',
                label: 'Catalog additions',
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: card(
                key: const Key('contributions-stat-total'),
                icon: Icons.upload_outlined,
                accent: context.v2.accent,
                value: '$submitted',
                label: 'Total submissions',
                tapHint: 'Shows the submission outcome breakdown',
                onTap: () => _showSubmissionBreakdown(
                  context,
                  pending: pending,
                  awaitingRelease: awaitingRelease,
                  added: approved,
                  notAdded: notAdded,
                  total: submitted,
                ),
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: card(
                key: const Key('contributions-stat-points'),
                icon: Icons.star_outline_rounded,
                accent: context.v2.accentStrong,
                value: points == null ? '—' : '$points',
                label: 'Points earned',
                tapHint: 'Explains how contribution points are earned',
                onTap: () => _showPointsExplanation(context),
              ),
            ),
          ],
        );
      },
    );
  }
}

void _showPointsExplanation(BuildContext context) {
  PGModal.bottomSheet<void>(
    context: context,
    builder: (context) => const _ContributionInfoSheet(
      title: 'How points work',
      children: [
        Text(
          'Earn 10 points when a product you submit is approved and added '
          'to PharmaGuide. Pending, rejected, duplicate, and incomplete '
          'submissions do not earn points.',
        ),
        SizedBox(height: V2Spacing.space12),
        Text(
          'A successful resubmission earns once. We plan to make points '
          'redeemable for discounts and other rewards in the future. '
          'Reward details may change while the program is being developed.',
        ),
      ],
    ),
  );
}

void _showSubmissionBreakdown(
  BuildContext context, {
  required int pending,
  required int awaitingRelease,
  required int added,
  required int notAdded,
  required int total,
}) {
  PGModal.bottomSheet<void>(
    context: context,
    builder: (context) => _ContributionInfoSheet(
      title: 'Submission breakdown',
      children: [
        _BreakdownRow(label: 'Pending review', value: pending),
        if (awaitingRelease > 0)
          _BreakdownRow(
            label: 'Approved, awaiting release',
            value: awaitingRelease,
          ),
        _BreakdownRow(label: 'Added to catalog', value: added),
        _BreakdownRow(label: 'Not added', value: notAdded),
        const Divider(height: V2Spacing.space24),
        _BreakdownRow(
          key: const Key('submission-breakdown-total'),
          label: 'Finalized submissions',
          value: total,
          emphasized: true,
        ),
        const SizedBox(height: V2Spacing.space12),
        Text(
          'Interrupted uploads are excluded until their photos are '
          'successfully submitted.',
          style: V2Typography.bodySm(color: context.v2.fgMuted),
        ),
      ],
    ),
  );
}

class _ContributionInfoSheet extends StatelessWidget {
  const _ContributionInfoSheet({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        V2Spacing.space24,
        V2Spacing.space8,
        V2Spacing.space24,
        V2Spacing.space32,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: V2Typography.titleSm(color: context.v2.fg)),
          const SizedBox(height: V2Spacing.space12),
          DefaultTextStyle(
            style: V2Typography.body(color: context.v2.fg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({
    super.key,
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final int value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final style = emphasized
        ? V2Typography.bodyMedium(color: context.v2.fg)
        : V2Typography.body(color: context.v2.fg);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: V2Spacing.space4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text('$value', style: style),
        ],
      ),
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
        'No submissions yet. Scan a product we don’t have, or add one from '
        'photos and a UPC from the package or store listing.',
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
  const _SubmissionCard({
    required this.status,
    this.onResubmit,
    this.onRetake,
    this.onHide,
  });

  final ProductSubmissionSummary status;
  final ResubmitProductSubmission? onResubmit;
  final ResubmitProductSubmission? onRetake;
  final HideProductSubmission? onHide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final display = _statusDisplay(context.v2, status);
    final guidance = _resolutionGuidance(status);
    final canHide =
        status.uploadReady &&
        (status.reviewStatus == ProductSubmissionReviewStatus.rejected ||
            status.reviewStatus == ProductSubmissionReviewStatus.duplicate);
    return Container(
      padding: const EdgeInsets.all(V2Spacing.space16),
      decoration: BoxDecoration(
        color: context.v2.surface,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        border: Border.all(color: context.v2.outline),
      ),
      child: Semantics(
        container: true,
        label:
            'Submission${status.upc == null ? '' : ' for UPC ${status.upc}'}. '
            '${display.label}.',
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(display.icon, color: display.color, size: 24),
            const SizedBox(width: V2Spacing.space12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SubmissionIdentity(status: status),
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
                  if (status.reviewStatus ==
                          ProductSubmissionReviewStatus.rejected &&
                      status.resolutionCode?.resubmittable == true &&
                      status.hasResubmissionTarget &&
                      onResubmit != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        key: Key('submission-resubmit-${status.submissionId}'),
                        onPressed: () => onResubmit!(status),
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('Try again with new photos'),
                      ),
                    ),
                  if ((status.needsNewPhotos || status.retakeUnfinished) &&
                      onRetake != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        key: Key('submission-retake-${status.submissionId}'),
                        onPressed: () => onRetake!(status),
                        icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                        label: Text(
                          status.retakeUnfinished
                              ? 'Finish sending new photos'
                              : 'Retake photos',
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (canHide && onHide != null)
              IconButton(
                key: Key('submission-hide-${status.submissionId}'),
                tooltip: 'Hide from history',
                onPressed: () => onHide!(status),
                icon: const Icon(Icons.close_rounded, size: 18),
                color: context.v2.fgMuted,
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
      ),
    );
  }
}

class _HideSubmissionSheet extends StatelessWidget {
  const _HideSubmissionSheet();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        V2Spacing.space24,
        V2Spacing.space8,
        V2Spacing.space24,
        V2Spacing.space32,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Hide this submission?',
            style: V2Typography.titleSm(color: context.v2.fg),
          ),
          const SizedBox(height: V2Spacing.space8),
          Text(
            'It will disappear from Your Contributions. The private review '
            'record stays securely stored, and hiding it does not change '
            'your points or the catalog.',
            style: V2Typography.body(color: context.v2.fgMuted),
          ),
          const SizedBox(height: V2Spacing.space24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Hide from history'),
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep it'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SubmissionIdentity extends ConsumerWidget {
  const _SubmissionIdentity({required this.status});

  final ProductSubmissionSummary status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogId = status.resolvedDsldId ?? status.mismatchProduct?.dsldId;
    if (catalogId == null) {
      return _SubmissionIdentityText(
        name: _fallbackSubmissionName(status),
        upc: status.upc,
      );
    }
    return FutureBuilder(
      future: ref.read(coreDatabaseProvider).findById(catalogId),
      builder: (context, snapshot) => _SubmissionIdentityText(
        name: snapshot.data?.productName ?? _fallbackSubmissionName(status),
        upc: status.upc,
      ),
    );
  }
}

class _SubmissionIdentityText extends StatelessWidget {
  const _SubmissionIdentityText({required this.name, required this.upc});

  final String name;
  final String? upc;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: V2Typography.bodyMedium(color: context.v2.fg),
        ),
        if (upc != null) ...[
          const SizedBox(height: V2Spacing.space4),
          Text(
            'UPC $upc',
            style: V2Typography.caption(color: context.v2.fgMuted),
          ),
        ],
      ],
    );
  }
}

String _fallbackSubmissionName(ProductSubmissionSummary status) {
  if (status.kind == null) return 'Submission details unavailable';
  if (status.kind == ProductSubmissionKind.labelMismatch) {
    return 'Catalog correction';
  }
  if (status.reviewStatus == ProductSubmissionReviewStatus.rejected) {
    return 'Product name unavailable';
  }
  return 'Product submission';
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
  if (status.needsNewPhotos || status.retakeUnfinished) {
    return productSubmissionRetakeRequest(
      status.evidenceRequestReason,
      status.evidenceRequestPanels,
    );
  }
  if (status.reviewStatus == ProductSubmissionReviewStatus.rejected ||
      status.reviewStatus == ProductSubmissionReviewStatus.duplicate) {
    return productSubmissionResolutionGuidance(
      status.resolutionCode,
      detail: status.resolutionDetail,
    );
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
  if (status.retakeUnfinished) {
    return _StatusDisplay(
      'New photos not sent yet',
      Icons.cloud_upload_outlined,
      p.caution,
    );
  }
  if (status.needsNewPhotos) {
    return _StatusDisplay(
      'New photos needed',
      Icons.add_a_photo_outlined,
      p.caution,
    );
  }
  if (status.uploadState != ProductSubmissionUploadState.ready) {
    return _StatusDisplay(
      'Upload incomplete — start a new submission to try again',
      Icons.cloud_off_outlined,
      p.caution,
    );
  }
  final resolutionHeadline = switch (status.resolutionCode) {
    ProductSubmissionResolutionCode.alreadyInCatalog =>
      'Already in the catalog',
    ProductSubmissionResolutionCode.duplicateSubmission => 'Already on its way',
    _ => null,
  };
  if (resolutionHeadline != null &&
      (status.reviewStatus == ProductSubmissionReviewStatus.rejected ||
          status.reviewStatus == ProductSubmissionReviewStatus.duplicate)) {
    return _StatusDisplay(
      resolutionHeadline,
      Icons.content_copy_outlined,
      p.fgMuted,
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
