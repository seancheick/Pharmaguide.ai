import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/core/widgets/pg_modal.dart';
import 'package:pharmaguide/data/database/core_database.dart';

enum KnownProductAction { view, report, compare }

/// A catalog match is a choice to inspect or report, never a new submission.
/// A null product means bottle comparison ended without a confirmed target.
Future<KnownProductAction?> showKnownProductSubmissionSheet(
  BuildContext context, {
  ProductsCoreData? product,
  bool canCompare = false,
  bool canReport = true,
}) => PGModal.bottomSheet<KnownProductAction>(
  context: context,
  builder: (context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(
      V2Spacing.space24,
      V2Spacing.space8,
      V2Spacing.space24,
      V2Spacing.space24,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          product == null
              ? 'No bottle selected'
              : 'This barcode is in your catalog',
          style: V2Typography.titleSm(color: context.v2.fg),
        ),
        const SizedBox(height: V2Spacing.space12),
        if (product != null) ...[
          if (product.brandName?.trim().isNotEmpty ?? false)
            Text(
              product.brandName!,
              style: V2Typography.bodySm(color: context.v2.fgMuted),
            ),
          Text(
            product.productName,
            style: V2Typography.titleSm(color: context.v2.fg),
          ),
          const SizedBox(height: V2Spacing.space12),
        ],
        Text(
          'The catalog installed on this phone may lag behind a newer label. '
          '${product == null ? 'Compare the catalog labels and choose the record you want to view or report.' : 'View this product or report an incorrect label for review.'} '
          'Any saved photos and submissions stay as they are.',
          style: V2Typography.bodySm(color: context.v2.fgMuted),
        ),
        const SizedBox(height: V2Spacing.space16),
        if (product != null) ...[
          FilledButton(
            onPressed: () => Navigator.of(context).pop(KnownProductAction.view),
            child: const Text('View product'),
          ),
          OutlinedButton(
            onPressed: canReport
                ? () => Navigator.of(context).pop(KnownProductAction.report)
                : null,
            child: const Text('Report incorrect label'),
          ),
          if (!canReport)
            Text(
              'Reporting isn’t available for this catalog record yet. You can still view the product.',
              style: V2Typography.bodySm(color: context.v2.fgMuted),
            ),
        ],
        if (canCompare)
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(KnownProductAction.compare),
            child: const Text('Compare labels'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  ),
);
