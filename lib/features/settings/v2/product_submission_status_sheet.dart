import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_eyebrow.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/services/product_submission_service.dart';

class ProductSubmissionStatusSheet extends StatefulWidget {
  const ProductSubmissionStatusSheet({super.key, required this.service});

  final ProductSubmissionService service;

  @override
  State<ProductSubmissionStatusSheet> createState() =>
      _ProductSubmissionStatusSheetState();
}

class _ProductSubmissionStatusSheetState
    extends State<ProductSubmissionStatusSheet> {
  late Future<List<ProductSubmissionSummary>> _statuses;

  @override
  void initState() {
    super.initState();
    _statuses = widget.service.listOwnSubmissions();
  }

  void _retry() {
    setState(() {
      _statuses = widget.service.listOwnSubmissions();
    });
  }

  @override
  Widget build(BuildContext context) {
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
              style: V2Typography.title(color: V2Colors.fg),
            ),
            const SizedBox(height: V2Spacing.space8),
            Text(
              'Only products you submitted appear here. A reviewer must '
              'approve label evidence before it can enter the catalog.',
              style: V2Typography.bodySm(color: V2Colors.fgMuted),
            ),
            const SizedBox(height: V2Spacing.space16),
            Flexible(
              child: FutureBuilder<List<ProductSubmissionSummary>>(
                future: _statuses,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return _StatusError(onRetry: _retry);
                  }
                  final statuses = snapshot.data ?? const [];
                  if (statuses.isEmpty) {
                    return Text(
                      'No product submissions yet.',
                      style: V2Typography.body(color: V2Colors.fgMuted),
                    );
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    itemCount: statuses.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: V2Spacing.space24),
                    itemBuilder: (_, index) =>
                        _SubmissionStatusRow(status: statuses[index]),
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

class _SubmissionStatusRow extends StatelessWidget {
  const _SubmissionStatusRow({required this.status});

  final ProductSubmissionSummary status;

  @override
  Widget build(BuildContext context) {
    final display = _statusDisplay(status);
    final identity = status.kind == ProductSubmissionKind.labelMismatch
        ? 'Catalog correction'
        : 'UPC ${status.upc ?? 'unavailable'}';
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
                Text(identity, style: V2Typography.body(color: V2Colors.fg)),
                const SizedBox(height: V2Spacing.space4),
                Text(
                  display.label,
                  style: V2Typography.bodySm(color: display.color),
                ),
                if (status.promotedCatalogVersion case final version?) ...[
                  const SizedBox(height: V2Spacing.space4),
                  Text(
                    'Catalog version $version',
                    style: V2Typography.caption(color: V2Colors.fgMuted),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusDisplay {
  const _StatusDisplay(this.label, this.icon, this.color);

  final String label;
  final IconData icon;
  final Color color;
}

_StatusDisplay _statusDisplay(ProductSubmissionSummary status) {
  if (status.isComplete) {
    return const _StatusDisplay(
      'Added to catalog',
      Icons.task_alt_rounded,
      V2Colors.safe,
    );
  }
  if (!status.uploadReady) {
    return const _StatusDisplay(
      'Upload incomplete — start a new submission to try again',
      Icons.cloud_off_outlined,
      V2Colors.caution,
    );
  }
  return switch (status.reviewStatus) {
    ProductSubmissionReviewStatus.submitted => const _StatusDisplay(
      'Waiting for review',
      Icons.schedule_rounded,
      V2Colors.fgMuted,
    ),
    ProductSubmissionReviewStatus.underReview => const _StatusDisplay(
      'Under review',
      Icons.fact_check_outlined,
      V2Colors.accent,
    ),
    ProductSubmissionReviewStatus.approved => const _StatusDisplay(
      'Approved — waiting for a catalog release',
      Icons.verified_outlined,
      V2Colors.safe,
    ),
    ProductSubmissionReviewStatus.rejected => const _StatusDisplay(
      'Not added',
      Icons.block_outlined,
      V2Colors.fgMuted,
    ),
    ProductSubmissionReviewStatus.duplicate => const _StatusDisplay(
      'Already under review',
      Icons.content_copy_outlined,
      V2Colors.fgMuted,
    ),
    ProductSubmissionReviewStatus.unknown => const _StatusDisplay(
      'Status unavailable',
      Icons.help_outline_rounded,
      V2Colors.fgMuted,
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
          style: V2Typography.body(color: V2Colors.fgMuted),
        ),
        const SizedBox(height: V2Spacing.space12),
        TextButton(onPressed: onRetry, child: const Text('Try again')),
      ],
    );
  }
}
