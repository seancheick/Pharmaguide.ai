/// Formula comparison is based only on source-provided fingerprints.
enum FormulaSnapshotComparison { unchanged, differs }

class FormulaHistorySnapshot {
  final String snapshotId;
  final String sourceRecordId;
  final String lineageKey;
  final String formulaFingerprint;
  final String? catalogVersion;
  final String? sourceDate;
  final String? sourceUpdatedDate;
  final String? productStatus;
  final String? labelSourceUrl;
  final FormulaSnapshotComparison comparison;
  final List<String> changedRows;
  final bool hasIngredientLevelDetails;

  const FormulaHistorySnapshot({
    required this.snapshotId,
    required this.sourceRecordId,
    required this.lineageKey,
    required this.formulaFingerprint,
    required this.comparison,
    this.catalogVersion,
    this.sourceDate,
    this.sourceUpdatedDate,
    this.productStatus,
    this.labelSourceUrl,
    this.changedRows = const [],
    this.hasIngredientLevelDetails = false,
  });
}

class FormulaHistoryModel {
  final String? currentSourceRecordId;
  final String? currentLineageKey;
  final String? currentFormulaFingerprint;
  final List<FormulaHistorySnapshot> snapshots;

  const FormulaHistoryModel._({
    this.currentSourceRecordId,
    this.currentLineageKey,
    this.currentFormulaFingerprint,
    this.snapshots = const [],
  });

  bool get hasVerifiedHistory => snapshots.isNotEmpty;

  factory FormulaHistoryModel.fromLabelRecord(
    Map<String, dynamic>? labelRecord, {
    List<Map<String, dynamic>>? currentLabelRows,
  }) {
    if (labelRecord == null || labelRecord['history_status'] != 'available') {
      return const FormulaHistoryModel._();
    }

    final sourceRecordId = _nonEmptyString(labelRecord['source_record_id']);
    final lineageKey = _nonEmptyString(labelRecord['lineage_key']);
    final currentFingerprint = _fingerprint(labelRecord['formula_fingerprint']);
    final fieldStatuses = labelRecord['field_statuses'];
    final hasDefensibleCurrentIdentity =
        fieldStatuses is Map &&
        fieldStatuses['source_record_id'] == 'available' &&
        fieldStatuses['lineage_key'] == 'available' &&
        fieldStatuses['formula_fingerprint'] == 'available';
    if (!hasDefensibleCurrentIdentity ||
        sourceRecordId == null ||
        lineageKey == null ||
        currentFingerprint == null) {
      return FormulaHistoryModel._(
        currentSourceRecordId: sourceRecordId,
        currentLineageKey: lineageKey,
        currentFormulaFingerprint: currentFingerprint,
      );
    }

    final history = labelRecord['formula_history'];
    if (history is! List) {
      return FormulaHistoryModel._(
        currentSourceRecordId: sourceRecordId,
        currentLineageKey: lineageKey,
        currentFormulaFingerprint: currentFingerprint,
      );
    }

    final snapshotIdentities = <String>{};
    for (final rawSnapshot in history) {
      if (rawSnapshot is! Map) continue;
      final snapshotId = _nonEmptyString(rawSnapshot['snapshot_id']);
      if (snapshotId != null && !snapshotIdentities.add(snapshotId)) {
        return FormulaHistoryModel._(
          currentSourceRecordId: sourceRecordId,
          currentLineageKey: lineageKey,
          currentFormulaFingerprint: currentFingerprint,
        );
      }
    }

    final currentLedger = _parseLedger(currentLabelRows);
    final snapshots = <FormulaHistorySnapshot>[];
    for (final rawSnapshot in history) {
      if (rawSnapshot is! Map) continue;
      final snapshotId = _nonEmptyString(rawSnapshot['snapshot_id']);
      final snapshotSourceId = _nonEmptyString(rawSnapshot['source_record_id']);
      final snapshotLineage = _nonEmptyString(rawSnapshot['lineage_key']);
      final snapshotFingerprint = _fingerprint(
        rawSnapshot['formula_fingerprint'],
      );
      if (snapshotId == null ||
          snapshotSourceId != sourceRecordId ||
          snapshotLineage != lineageKey ||
          snapshotFingerprint == null) {
        continue;
      }

      final comparison = snapshotFingerprint == currentFingerprint
          ? FormulaSnapshotComparison.unchanged
          : FormulaSnapshotComparison.differs;
      final snapshotLedger = _parseLedger(rawSnapshot['display_ingredients']);
      final hasIngredientLevelDetails =
          comparison == FormulaSnapshotComparison.differs &&
          currentLedger != null &&
          snapshotLedger != null;
      final changedRows = hasIngredientLevelDetails
          ? _summarizeLedgerChanges(snapshotLedger, currentLedger)
          : const <String>[];

      snapshots.add(
        FormulaHistorySnapshot(
          snapshotId: snapshotId,
          sourceRecordId: snapshotSourceId!,
          lineageKey: snapshotLineage!,
          formulaFingerprint: snapshotFingerprint,
          catalogVersion: _nonEmptyString(rawSnapshot['catalog_version']),
          sourceDate: _isoDate(rawSnapshot['source_date']),
          sourceUpdatedDate: _isoDate(rawSnapshot['source_updated_date']),
          productStatus: _nonEmptyString(rawSnapshot['product_status']),
          labelSourceUrl: _httpUrl(rawSnapshot['label_source_url']),
          comparison: comparison,
          changedRows: List.unmodifiable(changedRows),
          hasIngredientLevelDetails: hasIngredientLevelDetails,
        ),
      );
    }

    snapshots.sort(_compareSnapshots);
    return FormulaHistoryModel._(
      currentSourceRecordId: sourceRecordId,
      currentLineageKey: lineageKey,
      currentFormulaFingerprint: currentFingerprint,
      snapshots: List.unmodifiable(snapshots),
    );
  }
}

final RegExp _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');

String? _nonEmptyString(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String? _fingerprint(Object? value) {
  final fingerprint = _nonEmptyString(value)?.toLowerCase();
  return fingerprint != null && _sha256Pattern.hasMatch(fingerprint)
      ? fingerprint
      : null;
}

String? _isoDate(Object? value) {
  final raw = _nonEmptyString(value);
  return raw != null && DateTime.tryParse(raw) != null ? raw : null;
}

String? _httpUrl(Object? value) {
  final raw = _nonEmptyString(value);
  if (raw == null) return null;
  final uri = Uri.tryParse(raw);
  return uri != null &&
          (uri.scheme == 'http' || uri.scheme == 'https') &&
          uri.host.isNotEmpty
      ? raw
      : null;
}

int _compareSnapshots(
  FormulaHistorySnapshot left,
  FormulaHistorySnapshot right,
) {
  final leftDate = left.sourceUpdatedDate ?? left.sourceDate;
  final rightDate = right.sourceUpdatedDate ?? right.sourceDate;
  if (leftDate == null && rightDate != null) return 1;
  if (leftDate != null && rightDate == null) return -1;
  if (leftDate != null && rightDate != null) {
    final dateOrder = _comparisonInstant(
      leftDate,
    ).compareTo(_comparisonInstant(rightDate));
    if (dateOrder != 0) return dateOrder;
  }
  return left.snapshotId.compareTo(right.snapshotId);
}

DateTime _comparisonInstant(String raw) {
  final parsed = DateTime.parse(raw);
  if (parsed.isUtc || RegExp(r'(?:Z|[+-]\d\d(?::?\d\d)?)$').hasMatch(raw)) {
    return parsed.toUtc();
  }
  // Offset-free source dates are calendar values, not the device timezone.
  // Compare their components in UTC so ordering is identical across devices.
  return DateTime.utc(
    parsed.year,
    parsed.month,
    parsed.day,
    parsed.hour,
    parsed.minute,
    parsed.second,
    parsed.millisecond,
    parsed.microsecond,
  );
}

class _LabelRow {
  final int order;
  final int nestedDepth;
  final String name;
  final String? form;
  final String? dose;
  final String? parentheticalDose;
  final String? parentLabel;
  final String? sourceSection;
  final String foldedComponentsSignature;

  const _LabelRow({
    required this.order,
    required this.nestedDepth,
    required this.name,
    required this.foldedComponentsSignature,
    this.form,
    this.dose,
    this.parentheticalDose,
    this.parentLabel,
    this.sourceSection,
  });

  String get displayText {
    final parts = <String>[name];
    if (form != null) parts[0] = '$name ($form)';
    if (dose != null) parts.add(dose!);
    if (parentheticalDose != null) parts.add('($parentheticalDose)');
    return parts.join(' · ');
  }

  String get signature => [
    nestedDepth,
    name,
    form,
    dose,
    parentheticalDose,
    parentLabel,
    sourceSection,
    foldedComponentsSignature,
  ].join('\u001f');
}

List<_LabelRow>? _parseLedger(Object? rawLedger) {
  if (rawLedger is! List || rawLedger.isEmpty) return null;
  final rows = <_LabelRow>[];
  final seenOrders = <int>{};
  for (final rawRow in rawLedger) {
    if (rawRow is! Map) return null;
    final rawOrder = rawRow['label_order'];
    final order = rawOrder is int
        ? rawOrder
        : rawOrder is num && rawOrder == rawOrder.toInt()
        ? rawOrder.toInt()
        : null;
    final rawDepth = rawRow['nested_depth'] ?? 0;
    final nestedDepth = rawDepth is int
        ? rawDepth
        : rawDepth is num && rawDepth == rawDepth.toInt()
        ? rawDepth.toInt()
        : null;
    final name = _nonEmptyString(rawRow['label_display_name']);
    final foldedComponentsSignature = _foldedComponentsSignature(
      rawRow['folded_label_components'],
    );
    if (order == null ||
        order < 0 ||
        !seenOrders.add(order) ||
        nestedDepth == null ||
        nestedDepth < 0 ||
        name == null ||
        foldedComponentsSignature == null) {
      return null;
    }
    rows.add(
      _LabelRow(
        order: order,
        nestedDepth: nestedDepth,
        name: name,
        form: _nonEmptyString(rawRow['label_display_form']),
        dose: _nonEmptyString(rawRow['exact_dose_text']),
        parentheticalDose: _nonEmptyString(rawRow['parenthetical_dose_text']),
        parentLabel: _nonEmptyString(rawRow['parent_label']),
        sourceSection: _nonEmptyString(rawRow['source_section']),
        foldedComponentsSignature: foldedComponentsSignature,
      ),
    );
  }
  rows.sort((left, right) => left.order.compareTo(right.order));
  return rows;
}

String? _foldedComponentsSignature(Object? rawComponents) {
  if (rawComponents == null) return '';
  if (rawComponents is! List) return null;
  final signatures = <String>[];
  for (final rawComponent in rawComponents) {
    if (rawComponent is! Map) return null;
    final name = _nonEmptyString(rawComponent['label_display_name']);
    if (name == null) return null;
    signatures.add(
      [
        name,
        _nonEmptyString(rawComponent['label_display_form']),
        _nonEmptyString(rawComponent['exact_dose_text']),
        _nonEmptyString(rawComponent['parent_label']),
      ].join('\u001f'),
    );
  }
  return signatures.join('\u001e');
}

List<String> _summarizeLedgerChanges(
  List<_LabelRow> previous,
  List<_LabelRow> current,
) {
  final previousByOrder = {for (final row in previous) row.order: row};
  final currentByOrder = {for (final row in current) row.order: row};
  final orders = {...previousByOrder.keys, ...currentByOrder.keys}.toList()
    ..sort();
  final summaries = <String>[];
  for (final order in orders) {
    final before = previousByOrder[order];
    final after = currentByOrder[order];
    final rowNumber = order + 1;
    if (before == null && after != null) {
      summaries.add('Row $rowNumber added: ${after.displayText}');
    } else if (before != null && after == null) {
      summaries.add('Row $rowNumber removed: ${before.displayText}');
    } else if (before != null &&
        after != null &&
        before.signature != after.signature) {
      if (before.displayText != after.displayText) {
        summaries.add(
          'Row $rowNumber: ${before.displayText} → ${after.displayText}',
        );
      } else {
        summaries.add(
          'Row $rowNumber: ${after.displayText} · label structure changed',
        );
      }
    }
  }
  return summaries;
}
