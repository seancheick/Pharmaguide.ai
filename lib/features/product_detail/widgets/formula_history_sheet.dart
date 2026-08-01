import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/core/widgets/pg_modal.dart';
import 'package:pharmaguide/features/product_detail/formula_history_model.dart';

/// Opens a read-only source history surface.
Future<void> showFormulaHistorySheet(
  BuildContext context, {
  required Map<String, dynamic>? labelRecord,
  List<Map<String, dynamic>>? currentLabelRows,
}) {
  final model = FormulaHistoryModel.fromLabelRecord(
    labelRecord,
    currentLabelRows: currentLabelRows,
  );
  return PGModal.bottomSheet<void>(
    context: context,
    backgroundColor: context.v2.surface,
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.68,
      minChildSize: 0.42,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, scrollController) =>
          FormulaHistorySheet(model: model, scrollController: scrollController),
    ),
  );
}

class FormulaHistorySheet extends StatelessWidget {
  final FormulaHistoryModel model;
  final ScrollController? scrollController;

  const FormulaHistorySheet({
    super.key,
    required this.model,
    this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(
        V2Spacing.space24,
        V2Spacing.space8,
        V2Spacing.space24,
        V2Spacing.space32,
      ),
      children: [
        Semantics(
          header: true,
          label: 'Formula history',
          child: ExcludeSemantics(
            child: Text(
              'Formula history',
              style: V2Typography.titleSm(color: context.v2.fg),
            ),
          ),
        ),
        const SizedBox(height: V2Spacing.space8),
        Text(
          'Only source-linked snapshots are shown. Dates appear only when '
          'the source provides them.',
          style: V2Typography.bodySm(color: context.v2.fgMuted),
        ),
        const SizedBox(height: V2Spacing.space24),
        if (!model.hasVerifiedHistory)
          const _NoHistoryState()
        else
          for (var index = 0; index < model.snapshots.length; index++) ...[
            _SnapshotCard(snapshot: model.snapshots[index]),
            if (index != model.snapshots.length - 1)
              const SizedBox(height: V2Spacing.space12),
          ],
      ],
    );
  }
}

class _NoHistoryState extends StatelessWidget {
  const _NoHistoryState();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'No verified formula history is available for this product.',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.all(V2Spacing.space16),
          decoration: BoxDecoration(
            color: context.v2.accentTint,
            borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
            border: Border.all(color: context.v2.outline),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.history_rounded,
                size: 20,
                color: context.v2.fgMuted,
              ),
              const SizedBox(width: V2Spacing.space12),
              Expanded(
                child: Text(
                  'No verified formula history is available for this product.',
                  style: V2Typography.bodySm(color: context.v2.fg),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SnapshotCard extends StatelessWidget {
  final FormulaHistorySnapshot snapshot;

  const _SnapshotCard({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final isUnchanged =
        snapshot.comparison == FormulaSnapshotComparison.unchanged;
    final comparisonLabel = isUnchanged
        ? 'Formula unchanged'
        : 'Formula differs from current label';
    final accent = isUnchanged ? context.v2.safe : context.v2.caution;
    final tint = isUnchanged ? context.v2.safeTint : context.v2.cautionTint;

    return Semantics(
      container: true,
      label: _snapshotSemanticsLabel(snapshot, comparisonLabel),
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.all(V2Spacing.space16),
          decoration: BoxDecoration(
            color: context.v2.surface,
            borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
            border: Border.all(color: context.v2.outline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Snapshot ${snapshot.snapshotId}',
                style: V2Typography.label(color: context.v2.fg),
              ),
              const SizedBox(height: V2Spacing.space8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: V2Spacing.space8,
                  vertical: V2Spacing.space4,
                ),
                decoration: BoxDecoration(
                  color: tint,
                  borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
                ),
                child: Text(
                  comparisonLabel,
                  style: V2Typography.caption(color: accent),
                ),
              ),
              const SizedBox(height: V2Spacing.space12),
              if (snapshot.catalogVersion != null)
                _MetadataLine(
                  text: 'Catalog version ${snapshot.catalogVersion}',
                ),
              if (snapshot.sourceDate != null)
                _MetadataLine(text: 'Source date ${snapshot.sourceDate}'),
              if (snapshot.sourceUpdatedDate != null)
                _MetadataLine(
                  text: 'Source updated ${snapshot.sourceUpdatedDate}',
                ),
              _MetadataLine(text: 'Source record ${snapshot.sourceRecordId}'),
              _MetadataLine(text: 'Lineage ${snapshot.lineageKey}'),
              _MetadataLine(
                text:
                    'Formula ID ${_shortFingerprint(snapshot.formulaFingerprint)}',
              ),
              const SizedBox(height: V2Spacing.space12),
              if (isUnchanged)
                Text(
                  'This snapshot has the same formula fingerprint as the '
                  'current label.',
                  style: V2Typography.bodySm(color: context.v2.fgMuted),
                )
              else if (!snapshot.hasIngredientLevelDetails)
                Text(
                  'Ingredient-level changes were not provided with this '
                  'snapshot.',
                  style: V2Typography.bodySm(color: context.v2.fgMuted),
                )
              else if (snapshot.changedRows.isNotEmpty) ...[
                Text(
                  'Label changes',
                  style: V2Typography.label(color: context.v2.fg),
                ),
                const SizedBox(height: V2Spacing.space8),
                for (final summary in snapshot.changedRows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: V2Spacing.space4),
                    child: Text(
                      '• $summary',
                      style: V2Typography.bodySm(color: context.v2.fg),
                    ),
                  ),
              ] else
                Text(
                  'The source supplied row details, but no row-level '
                  'difference was identifiable.',
                  style: V2Typography.bodySm(color: context.v2.fgMuted),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetadataLine extends StatelessWidget {
  final String text;

  const _MetadataLine({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: V2Spacing.space4),
      child: Text(text, style: V2Typography.caption(color: context.v2.fgMuted)),
    );
  }
}

String _shortFingerprint(String fingerprint) {
  return fingerprint.length <= 12 ? fingerprint : fingerprint.substring(0, 12);
}

String _snapshotSemanticsLabel(
  FormulaHistorySnapshot snapshot,
  String comparisonLabel,
) {
  final facts = <String>[
    'Snapshot ${snapshot.snapshotId}',
    comparisonLabel,
    if (snapshot.catalogVersion != null)
      'Catalog version ${snapshot.catalogVersion}',
    if (snapshot.sourceDate != null) 'Source date ${snapshot.sourceDate}',
    if (snapshot.sourceUpdatedDate != null)
      'Source updated ${snapshot.sourceUpdatedDate}',
    'Source record ${snapshot.sourceRecordId}',
    'Lineage ${snapshot.lineageKey}',
    'Formula fingerprint ${snapshot.formulaFingerprint}',
    if (snapshot.comparison == FormulaSnapshotComparison.differs &&
        !snapshot.hasIngredientLevelDetails)
      'Ingredient-level changes were not provided with this snapshot',
    ...snapshot.changedRows,
  ];
  return '${facts.join('. ')}.';
}
