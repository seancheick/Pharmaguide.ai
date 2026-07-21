import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/features/product_detail/widgets/label_mismatch_sheet.dart';
import 'package:pharmaguide/services/label_mismatch_report_service.dart';

/// Build the report metadata for a "Doesn't match your bottle?" action from a
/// raw `label_record` blob map. Returns null when there is no identifier to
/// report against. Single source of truth for this metadata so the standalone
/// action (near the ingredient list) and any future caller stay consistent.
LabelMismatchProductMetadata? labelMismatchMetadataFrom(
  Object? labelRecord, {
  String? dsldId,
  String? upc,
}) {
  final record = labelRecord is Map ? labelRecord : const <dynamic, dynamic>{};
  final sourceRecordId = record['source_record_id']?.toString();
  final reportId = dsldId ?? sourceRecordId;
  if (reportId == null || reportId.trim().isEmpty) return null;
  try {
    return LabelMismatchProductMetadata(
      dsldId: reportId,
      upc: upc,
      sourceRecordId: sourceRecordId,
      catalogSourceVersion: record['catalog_version']?.toString(),
      formulaFingerprint: record['formula_fingerprint']?.toString(),
    );
  } on LabelMismatchValidationException {
    // Malformed provenance (e.g. a non-sha256 fingerprint) must never crash the
    // product page during build — the mismatch action simply does not render.
    return null;
  }
}

/// Standalone "Doesn't match your bottle?" affordance. Rendered next to the
/// ingredient list — where a user comparing the app to the bottle actually
/// looks — separate from the collapsed catalog-record card at the page bottom.
class LabelMismatchAction extends StatelessWidget {
  const LabelMismatchAction({
    super.key,
    required this.product,
    this.onReportMismatch,
  });

  final LabelMismatchProductMetadata product;
  final Future<void> Function(LabelMismatchProductMetadata product)?
  onReportMismatch;

  Future<void> _open(BuildContext context) async {
    final callback = onReportMismatch;
    if (callback != null) {
      await callback(product);
      return;
    }
    await showLabelMismatchSheet(context, product: product);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          label: 'Doesn’t match your bottle? Report a catalog mismatch',
          onTap: () => _open(context),
          excludeSemantics: true,
          child: TextButton.icon(
            key: const Key('label-mismatch-action'),
            onPressed: () => _open(context),
            icon: const Icon(Icons.report_outlined, size: 18),
            label: const Text('Doesn’t match your bottle?'),
          ),
        ),
        Text(
          'Send a structured report for review. Reports never change the '
          'catalog automatically.',
          style: V2Typography.caption(color: V2Colors.fgMuted),
        ),
      ],
    );
  }
}
