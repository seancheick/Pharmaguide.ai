import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/label_mismatch_action.dart';
import 'package:pharmaguide/features/product_detail/widgets/label_mismatch_sheet.dart';
import 'package:pharmaguide/services/product_submission_service.dart';

typedef OpenSourceLabel = Future<void> Function(Uri uri);
typedef OpenLabelMismatchReport =
    Future<void> Function(LabelMismatchProductMetadata product);

const _recordFieldKeys = <String>[
  'source_name',
  'source_record_id',
  'catalog_version',
  'formula_fingerprint',
  'source_date',
  'source_updated_date',
  'product_status',
  'label_source_url',
  'lineage_key',
];

const _productStatuses = <String>{
  'active',
  'discontinued',
  'off_market',
  'reformulated',
  'limited_availability',
  'seasonal',
  'recalled',
};

/// Catalog provenance shown next to the source-label ingredient ledger.
///
/// This section is deliberately informational. It presents source identity
/// and version fields exactly as emitted by the pipeline; it never converts
/// metadata availability into a match, freshness, or authenticity claim.
Widget buildLabelMatchSection({
  required Object? labelRecord,
  String? dsldId,
  String? upc,
  OpenSourceLabel? onOpenSourceLabel,
  OpenLabelMismatchReport? onReportMismatch,
  // When false, the card omits its inline "Doesn't match your bottle?" action —
  // used at the collapsed page-bottom placement where that action is instead
  // rendered contextually next to the ingredient list (LabelMismatchAction).
  bool showMismatchAction = true,
}) {
  final record = _LabelRecord.tryParse(labelRecord);
  if (record == null) return const _UnavailableLabelRecordCard();
  final rawRecord = labelRecord as Map<String, dynamic>;

  return _LabelRecordCard(
    record: record,
    rawRecord: rawRecord,
    dsldId: _nonEmpty(dsldId),
    upc: _nonEmpty(upc),
    onOpenSourceLabel: onOpenSourceLabel,
    onReportMismatch: onReportMismatch,
    showMismatchAction: showMismatchAction,
  );
}

class _LabelRecord {
  final Map<String, String?> fields;
  final String metadataStatus;
  final List<String> metadataIssues;
  final Uri? sourceUri;

  const _LabelRecord({
    required this.fields,
    required this.metadataStatus,
    required this.metadataIssues,
    required this.sourceUri,
  });

  String? operator [](String key) => fields[key];

  static _LabelRecord? tryParse(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;

    final statusesRaw = raw['field_statuses'];
    final issuesRaw = raw['metadata_issues'];
    final metadataStatus = _nonEmpty(raw['metadata_status']);
    if (statusesRaw is! Map<String, dynamic> ||
        issuesRaw is! List ||
        metadataStatus == null) {
      return null;
    }
    if (!const {
      'available',
      'partial',
      'unavailable',
    }.contains(metadataStatus)) {
      return null;
    }

    final fields = <String, String?>{};
    final unavailableIssues = <String>[];
    var availableCount = 0;
    for (final key in _recordFieldKeys) {
      final status = statusesRaw[key];
      final value = raw[key];
      if (status == 'available') {
        final parsed = _nonEmpty(value);
        if (parsed == null) return null;
        fields[key] = parsed;
        availableCount++;
      } else if (status == 'unavailable') {
        if (value != null) return null;
        fields[key] = null;
        unavailableIssues.add('unavailable:$key');
      } else {
        return null;
      }
    }

    if (issuesRaw.any((issue) => issue is! String)) return null;
    final metadataIssues = issuesRaw.cast<String>();
    if (!_sameStringSet(metadataIssues, unavailableIssues)) return null;

    final expectedMetadataStatus = availableCount == _recordFieldKeys.length
        ? 'available'
        : availableCount == 0
        ? 'unavailable'
        : 'partial';
    if (metadataStatus != expectedMetadataStatus) return null;
    final fingerprint = fields['formula_fingerprint'];
    if (fingerprint != null &&
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(fingerprint)) {
      return null;
    }
    for (final dateKey in const ['source_date', 'source_updated_date']) {
      final date = fields[dateKey];
      if (date != null && DateTime.tryParse(date) == null) return null;
    }
    final status = fields['product_status'];
    if (status != null && !_productStatuses.contains(status)) return null;

    Uri? sourceUri;
    final sourceUrl = fields['label_source_url'];
    if (sourceUrl != null) {
      sourceUri = Uri.tryParse(sourceUrl);
      if (sourceUri == null ||
          !const {'http', 'https'}.contains(sourceUri.scheme) ||
          sourceUri.host.isEmpty) {
        return null;
      }
    }

    return _LabelRecord(
      fields: Map.unmodifiable(fields),
      metadataStatus: metadataStatus,
      metadataIssues: List.unmodifiable(metadataIssues),
      sourceUri: sourceUri,
    );
  }
}

class _LabelRecordCard extends StatelessWidget {
  final _LabelRecord record;
  final Map<String, dynamic> rawRecord;
  final String? dsldId;
  final String? upc;
  final OpenSourceLabel? onOpenSourceLabel;
  final OpenLabelMismatchReport? onReportMismatch;
  final bool showMismatchAction;

  const _LabelRecordCard({
    required this.record,
    required this.rawRecord,
    required this.dsldId,
    required this.upc,
    required this.onOpenSourceLabel,
    required this.onReportMismatch,
    this.showMismatchAction = true,
  });

  @override
  Widget build(BuildContext context) {
    final sourceAction = record.sourceUri == null
        ? null
        : _sourceActionLabel(record.sourceUri!);
    Future<void> openSourceLabel() async {
      await onOpenSourceLabel!(record.sourceUri!);
    }

    final reportProduct = labelMismatchMetadataFrom(
      rawRecord,
      dsldId: dsldId,
      upc: upc,
    );
    Future<void> openMismatchReport() async {
      final product = reportProduct!;
      final callback = onReportMismatch;
      if (callback != null) {
        await callback(product);
        return;
      }
      await showLabelMismatchSheet(context, product: product);
    }

    final issueSet = record.metadataIssues.toSet();
    final unavailableLabels = <String>[
      for (final field in const [
        'source_name',
        'source_record_id',
        'upc',
        'catalog_version',
        'formula_fingerprint',
        'source_date',
        'source_updated_date',
        'product_status',
        'label_source_url',
        'lineage_key',
      ])
        if ((field == 'upc' && upc == null) ||
            issueSet.contains('unavailable:$field'))
          _fieldLabel(field),
    ];

    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Container(
        padding: const EdgeInsets.all(V2Spacing.space16),
        decoration: BoxDecoration(
          color: context.v2.surface,
          borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
          border: Border.all(color: context.v2.outline),
          boxShadow: V2Shadows.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.inventory_2_outlined,
                  size: 20,
                  color: context.v2.accent,
                ),
                const SizedBox(width: V2Spacing.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          'Catalog record details',
                          style: V2Typography.titleSm(color: context.v2.fg),
                        ),
                      ),
                      const SizedBox(height: V2Spacing.space4),
                      Text(
                        'Compare these catalog details with the package in '
                        'your hand.',
                        style: V2Typography.bodySm(color: context.v2.fgMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: V2Spacing.space16),
            _MetadataStatus(status: record.metadataStatus),
            const SizedBox(height: V2Spacing.space12),
            _DetailRow(label: 'Source', value: record['source_name']),
            _DetailRow(
              label: 'Source record ID',
              value: record['source_record_id'],
              mono: true,
            ),
            _DetailRow(label: 'UPC', value: upc, mono: true),
            _DetailRow(
              label: 'Product status',
              value: _productStatusLabel(record['product_status']),
            ),
            _DetailRow(
              label: 'Catalog version',
              value: record['catalog_version'],
              mono: true,
            ),
            _DetailRow(
              label: 'Formula fingerprint',
              value: record['formula_fingerprint'],
              mono: true,
              selectable: true,
            ),
            _DetailRow(label: 'Source date', value: record['source_date']),
            _DetailRow(
              label: 'Source updated',
              value: record['source_updated_date'],
            ),
            if (unavailableLabels.isNotEmpty) ...[
              const SizedBox(height: V2Spacing.space8),
              Text(
                'Unavailable in catalog: ${unavailableLabels.join(', ')}.',
                style: V2Typography.caption(color: context.v2.fgMuted),
              ),
            ],
            const SizedBox(height: V2Spacing.space8),
            Text(
              'The formula fingerprint identifies the stored label formula; '
              'it does not prove package authenticity.',
              style: V2Typography.caption(color: context.v2.fgMuted),
            ),
            if (sourceAction != null && onOpenSourceLabel != null) ...[
              const SizedBox(height: V2Spacing.space8),
              Semantics(
                button: true,
                label: '$sourceAction, opens external source',
                onTap: openSourceLabel,
                excludeSemantics: true,
                child: TextButton.icon(
                  key: const Key('source-label-action'),
                  onPressed: openSourceLabel,
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: Text(sourceAction),
                ),
              ),
            ],
            if (showMismatchAction && reportProduct != null) ...[
              const SizedBox(height: V2Spacing.space8),
              const Divider(height: V2Spacing.space16),
              Semantics(
                button: true,
                label: 'Doesn’t match your bottle? Report a catalog mismatch',
                onTap: openMismatchReport,
                excludeSemantics: true,
                child: TextButton.icon(
                  key: const Key('label-mismatch-action'),
                  onPressed: openMismatchReport,
                  icon: const Icon(Icons.report_outlined, size: 18),
                  label: const Text('Doesn’t match your bottle?'),
                ),
              ),
              Text(
                'Send a structured report for review. Reports never change '
                'the catalog automatically.',
                style: V2Typography.caption(color: context.v2.fgMuted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetadataStatus extends StatelessWidget {
  final String status;

  const _MetadataStatus({required this.status});

  @override
  Widget build(BuildContext context) {
    final label = switch (status) {
      'available' => 'Source metadata available',
      'partial' => 'Partial source metadata',
      _ => 'Source metadata unavailable',
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: V2Spacing.space8,
        vertical: V2Spacing.space4,
      ),
      decoration: BoxDecoration(
        color: context.v2.accentTint,
        borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
      ),
      child: Text(label, style: V2Typography.caption(color: context.v2.accent)),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String? value;
  final bool mono;
  final bool selectable;

  const _DetailRow({
    required this.label,
    required this.value,
    this.mono = false,
    this.selectable = false,
  });

  @override
  Widget build(BuildContext context) {
    final displayValue = value ?? 'Unavailable';
    final style = mono
        ? V2Typography.monoData(color: context.v2.fg)
        : V2Typography.bodySm(color: context.v2.fg);
    final valueWidget = selectable && value != null
        ? SelectableText(displayValue, style: style, textAlign: TextAlign.end)
        : Text(displayValue, style: style, textAlign: TextAlign.end);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: V2Spacing.space4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 128,
            child: Text(
              label,
              style: V2Typography.bodySm(color: context.v2.fgMuted),
            ),
          ),
          const SizedBox(width: V2Spacing.space8),
          Expanded(child: valueWidget),
        ],
      ),
    );
  }
}

class _UnavailableLabelRecordCard extends StatelessWidget {
  const _UnavailableLabelRecordCard();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Container(
        padding: const EdgeInsets.all(V2Spacing.space16),
        decoration: BoxDecoration(
          color: context.v2.surface,
          borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
          border: Border.all(color: context.v2.outline),
          boxShadow: V2Shadows.sm,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline_rounded,
              size: 20,
              color: context.v2.fgMuted,
            ),
            const SizedBox(width: V2Spacing.space12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      'Catalog record details unavailable',
                      style: V2Typography.bodyMedium(color: context.v2.fg),
                    ),
                  ),
                  const SizedBox(height: V2Spacing.space4),
                  Text(
                    'This catalog record could not be read. Compare the '
                    'ingredient list with the package before use.',
                    style: V2Typography.bodySm(color: context.v2.fgMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String? _nonEmpty(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

bool _sameStringSet(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  return left.toSet().containsAll(right) && right.toSet().containsAll(left);
}

String? _productStatusLabel(String? status) => switch (status) {
  'active' => 'Active',
  'discontinued' => 'Discontinued',
  'off_market' => 'Off market',
  'reformulated' => 'Reformulated',
  'limited_availability' => 'Limited availability',
  'seasonal' => 'Seasonal',
  'recalled' => 'Recalled',
  _ => null,
};

String _sourceActionLabel(Uri uri) {
  final path = uri.path.toLowerCase();
  if (RegExp(r'\.(png|jpe?g|webp|gif|heic|heif|avif)$').hasMatch(path)) {
    return 'View source label image';
  }
  if (path.endsWith('.pdf')) return 'View source label PDF';
  return 'View source label';
}

String _fieldLabel(String field) {
  return switch (field) {
    'source_name' => 'Source',
    'source_record_id' => 'Source record ID',
    'upc' => 'UPC',
    'catalog_version' => 'Catalog version',
    'formula_fingerprint' => 'Formula fingerprint',
    'source_date' => 'Source date',
    'source_updated_date' => 'Source updated',
    'product_status' => 'Product status',
    'label_source_url' => 'Source label',
    'lineage_key' => 'Formula lineage',
    _ => field,
  };
}
