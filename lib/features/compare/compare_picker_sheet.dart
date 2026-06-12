// Second-product picker for the Compare flow.
//
// Bottom sheet with two quiet sections — "Your stack" and "Recent
// scans" — sourced from [compareCandidatesProvider] (which already
// excludes the current product). Picking a row pushes the compare
// route.
//
// TODO(compare): scanning-to-compare (scan a barcode as the second
// product) is explicitly out of scope for this iteration.
// TODO(compare): an inline search field was considered and skipped —
// it bloats the sheet; the stack + recent-scans lists cover the real
// "which of mine is better" use case.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/core/widgets/pg_modal.dart';
import 'package:pharmaguide/features/compare/compare_providers.dart';

/// Show the picker. On pick, pops the sheet and pushes
/// `/compare/<currentDsldId>/<picked>`.
///
/// Presented via the shared [PGModal.bottomSheet] (root navigator,
/// safe-area, drag handle, 560pt tablet cap) — same vocabulary as every
/// other sheet in the app.
Future<void> showComparePickerSheet(
  BuildContext context, {
  required String currentDsldId,
}) {
  return PGModal.bottomSheet<void>(
    context: context,
    backgroundColor: V2Colors.surface,
    builder: (_) => ComparePickerSheet(currentDsldId: currentDsldId),
  );
}

class ComparePickerSheet extends ConsumerWidget {
  final String currentDsldId;
  const ComparePickerSheet({super.key, required this.currentDsldId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final candidatesAsync = ref.watch(compareCandidatesProvider(currentDsldId));

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          V2Spacing.space16,
          V2Spacing.space16,
          V2Spacing.space16,
          V2Spacing.space8,
        ),
        child: candidatesAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(V2Spacing.space24),
            child: Center(
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: V2Colors.accent,
              ),
            ),
          ),
          error: (_, __) => Padding(
            padding: const EdgeInsets.all(V2Spacing.space24),
            child: Text(
              'Couldn\'t load your products right now.',
              style: V2Typography.bodySm(color: V2Colors.fgMuted),
            ),
          ),
          data: (candidates) =>
              _PickerList(candidates: candidates, currentDsldId: currentDsldId),
        ),
      ),
    );
  }
}

class _PickerList extends StatelessWidget {
  final CompareCandidates candidates;
  final String currentDsldId;
  const _PickerList({required this.candidates, required this.currentDsldId});

  void _pick(BuildContext context, String dsldId) {
    Navigator.of(context).pop();
    context.push(Routes.comparePath(currentDsldId, dsldId));
  }

  @override
  Widget build(BuildContext context) {
    if (candidates.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(V2Spacing.space24),
        child: Text(
          'Nothing to compare with yet — add products to your stack or '
          'scan a few labels first.',
          style: V2Typography.bodySm(color: V2Colors.fgMuted),
        ),
      );
    }

    return ListView(
      shrinkWrap: true,
      children: [
        Text('Compare with', style: V2Typography.titleSm(color: V2Colors.fg)),
        const SizedBox(height: V2Spacing.space12),
        if (candidates.stack.isNotEmpty) ...[
          Text(
            'Your stack',
            style: V2Typography.caption(color: V2Colors.fgMuted),
          ),
          const SizedBox(height: V2Spacing.space4),
          for (final c in candidates.stack)
            _CandidateRow(candidate: c, onTap: () => _pick(context, c.dsldId)),
        ],
        if (candidates.recentScans.isNotEmpty) ...[
          const SizedBox(height: V2Spacing.space12),
          Text(
            'Recent scans',
            style: V2Typography.caption(color: V2Colors.fgMuted),
          ),
          const SizedBox(height: V2Spacing.space4),
          for (final c in candidates.recentScans)
            _CandidateRow(candidate: c, onTap: () => _pick(context, c.dsldId)),
        ],
      ],
    );
  }
}

class _CandidateRow extends StatelessWidget {
  final CompareCandidate candidate;
  final VoidCallback onTap;
  const _CandidateRow({required this.candidate, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: V2Spacing.space8,
          vertical: V2Spacing.space12,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              candidate.name,
              style: V2Typography.bodyMedium(color: V2Colors.fg),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (candidate.brand.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                candidate.brand,
                style: V2Typography.caption(color: V2Colors.fgMuted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
