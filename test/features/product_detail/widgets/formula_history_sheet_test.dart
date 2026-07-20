import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/product_detail/formula_history_model.dart';
import 'package:pharmaguide/features/product_detail/widgets/formula_history_sheet.dart';

String _fingerprint(String character) => List.filled(64, character).join();

Map<String, dynamic> _labelRecord({
  String? sourceRecordId = '999',
  String? lineageKey = 'dsld:999',
  String? formulaFingerprint,
  String historyStatus = 'available',
  List<Map<String, dynamic>> history = const [],
  Map<String, dynamic>? fieldStatuses,
}) {
  return {
    'source_record_id': sourceRecordId,
    'lineage_key': lineageKey,
    'formula_fingerprint': formulaFingerprint ?? _fingerprint('a'),
    'history_status': historyStatus,
    'field_statuses':
        fieldStatuses ??
        {
          'source_record_id': 'available',
          'lineage_key': 'available',
          'formula_fingerprint': 'available',
        },
    'formula_history': history,
  };
}

Map<String, dynamic> _snapshot({
  required String snapshotId,
  String sourceRecordId = '999',
  String lineageKey = 'dsld:999',
  String? fingerprint,
  String? catalogVersion,
  String? sourceDate,
  String? sourceUpdatedDate,
  String? productStatus,
  List<Map<String, dynamic>>? displayIngredients,
}) {
  return {
    'snapshot_id': snapshotId,
    'source_record_id': sourceRecordId,
    'lineage_key': lineageKey,
    'formula_fingerprint': fingerprint ?? _fingerprint('b'),
    if (catalogVersion != null) 'catalog_version': catalogVersion,
    if (sourceDate != null) 'source_date': sourceDate,
    if (sourceUpdatedDate != null) 'source_updated_date': sourceUpdatedDate,
    if (productStatus != null) 'product_status': productStatus,
    if (displayIngredients != null) 'display_ingredients': displayIngredients,
  };
}

Widget _harness(FormulaHistoryModel model) {
  return MaterialApp(
    home: Scaffold(body: FormulaHistorySheet(model: model)),
  );
}

void main() {
  test('keeps only explicit snapshots matching current source and lineage', () {
    final model = FormulaHistoryModel.fromLabelRecord(
      _labelRecord(
        history: [
          _snapshot(snapshotId: 'undated'),
          _snapshot(
            snapshotId: 'dated',
            sourceDate: '2024-01-02',
            catalogVersion: '5',
          ),
          _snapshot(snapshotId: 'wrong-source', sourceRecordId: '998'),
          _snapshot(snapshotId: 'wrong-lineage', lineageKey: 'dsld:998'),
          {
            'snapshot_id': 'missing-fingerprint',
            'source_record_id': '999',
            'lineage_key': 'dsld:999',
          },
        ],
      ),
    );

    expect(model.hasVerifiedHistory, isTrue);
    expect(model.snapshots.map((snapshot) => snapshot.snapshotId), [
      'dated',
      'undated',
    ]);
    expect(model.snapshots.first.sourceDate, '2024-01-02');
    expect(model.snapshots.last.sourceDate, isNull);
  });

  test('suppresses history when current lineage is missing or uncertain', () {
    final snapshot = _snapshot(snapshotId: 'real-snapshot');

    final missingLineage = FormulaHistoryModel.fromLabelRecord(
      _labelRecord(lineageKey: null, history: [snapshot]),
    );
    final uncertainLineage = FormulaHistoryModel.fromLabelRecord(
      _labelRecord(
        history: [snapshot],
        fieldStatuses: const {
          'source_record_id': 'available',
          'lineage_key': 'unavailable',
          'formula_fingerprint': 'available',
        },
      ),
    );

    expect(missingLineage.snapshots, isEmpty);
    expect(uncertainLineage.snapshots, isEmpty);
  });

  test(
    'suppresses history when current source or fingerprint is uncertain',
    () {
      final snapshot = _snapshot(snapshotId: 'real-snapshot');
      final sourceUnavailable = FormulaHistoryModel.fromLabelRecord(
        _labelRecord(
          history: [snapshot],
          fieldStatuses: const {
            'source_record_id': 'unavailable',
            'lineage_key': 'available',
            'formula_fingerprint': 'available',
          },
        ),
      );
      final fingerprintUnavailable = FormulaHistoryModel.fromLabelRecord(
        _labelRecord(
          history: [snapshot],
          fieldStatuses: const {
            'source_record_id': 'available',
            'lineage_key': 'available',
            'formula_fingerprint': 'unavailable',
          },
        ),
      );
      final invalidFingerprint = FormulaHistoryModel.fromLabelRecord(
        _labelRecord(formulaFingerprint: 'not-a-sha256', history: [snapshot]),
      );

      expect(sourceUnavailable.snapshots, isEmpty);
      expect(fingerprintUnavailable.snapshots, isEmpty);
      expect(invalidFingerprint.snapshots, isEmpty);
    },
  );

  test('duplicate snapshot identities suppress ambiguous history', () {
    final model = FormulaHistoryModel.fromLabelRecord(
      _labelRecord(
        history: [
          _snapshot(snapshotId: 'duplicate', sourceDate: '2024-01-01'),
          _snapshot(snapshotId: 'duplicate', sourceDate: '2025-01-01'),
        ],
      ),
    );

    expect(model.snapshots, isEmpty);
  });

  test(
    'sorts by explicit date then snapshot ID with undated snapshots last',
    () {
      final model = FormulaHistoryModel.fromLabelRecord(
        _labelRecord(
          history: [
            _snapshot(snapshotId: 'undated'),
            _snapshot(snapshotId: 'same-b', sourceDate: '2024-01-01'),
            _snapshot(
              snapshotId: 'later',
              sourceUpdatedDate: '2025-01-01T00:00:00Z',
            ),
            _snapshot(snapshotId: 'same-a', sourceDate: '2024-01-01'),
          ],
        ),
      );

      expect(model.snapshots.map((snapshot) => snapshot.snapshotId), [
        'same-a',
        'same-b',
        'later',
        'undated',
      ]);
    },
  );

  test('mixed offset and calendar dates have a deterministic UTC ordering', () {
    final model = FormulaHistoryModel.fromLabelRecord(
      _labelRecord(
        history: [
          _snapshot(
            snapshotId: 'offset',
            sourceUpdatedDate: '2024-01-01T00:30:00+01:00',
          ),
          _snapshot(
            snapshotId: 'calendar',
            sourceUpdatedDate: '2024-01-01T00:00:00',
          ),
        ],
      ),
    );

    expect(model.snapshots.map((snapshot) => snapshot.snapshotId), [
      'offset',
      'calendar',
    ]);
  });

  test(
    'distinct real snapshots with the current fingerprint are unchanged',
    () {
      final currentFingerprint = _fingerprint('a');
      final model = FormulaHistoryModel.fromLabelRecord(
        _labelRecord(
          formulaFingerprint: currentFingerprint,
          history: [
            _snapshot(
              snapshotId: 'snapshot-one',
              fingerprint: currentFingerprint,
            ),
            _snapshot(
              snapshotId: 'snapshot-two',
              fingerprint: currentFingerprint,
            ),
          ],
        ),
      );

      expect(model.snapshots, hasLength(2));
      expect(
        model.snapshots.map((snapshot) => snapshot.comparison),
        everyElement(FormulaSnapshotComparison.unchanged),
      );
    },
  );

  test('does not invent changed ingredients from fingerprint-only history', () {
    final model = FormulaHistoryModel.fromLabelRecord(
      _labelRecord(history: [_snapshot(snapshotId: 'older')]),
    );

    expect(
      model.snapshots.single.comparison,
      FormulaSnapshotComparison.differs,
    );
    expect(model.snapshots.single.changedRows, isEmpty);
    expect(model.snapshots.single.hasIngredientLevelDetails, isFalse);
  });

  test(
    'summarizes real ledger row changes deterministically by label order',
    () {
      final currentRows = [
        {
          'label_order': 1,
          'label_display_name': 'DHA',
          'exact_dose_text': '240 mg',
        },
        {
          'label_order': 0,
          'label_display_name': 'EPA',
          'exact_dose_text': '360 mg',
        },
      ];
      final olderRows = [
        {
          'label_order': 1,
          'label_display_name': 'DHA',
          'exact_dose_text': '200 mg',
        },
        {
          'label_order': 0,
          'label_display_name': 'EPA',
          'exact_dose_text': '300 mg',
        },
      ];
      final model = FormulaHistoryModel.fromLabelRecord(
        _labelRecord(
          history: [
            _snapshot(snapshotId: 'older', displayIngredients: olderRows),
          ],
        ),
        currentLabelRows: currentRows,
      );

      expect(model.snapshots.single.hasIngredientLevelDetails, isTrue);
      expect(model.snapshots.single.changedRows, [
        'Row 1: EPA · 300 mg → EPA · 360 mg',
        'Row 2: DHA · 200 mg → DHA · 240 mg',
      ]);
    },
  );

  test('folded component map key order cannot create a false row change', () {
    final currentRows = [
      {
        'label_order': 0,
        'label_display_name': 'Folate',
        'exact_dose_text': '665 mcg DFE',
        'folded_label_components': [
          {'label_display_name': 'Folic acid', 'exact_dose_text': '400 mcg'},
        ],
      },
    ];
    final olderRows = [
      {
        'label_order': 0,
        'label_display_name': 'Folate',
        'exact_dose_text': '665 mcg DFE',
        'folded_label_components': [
          {'exact_dose_text': '400 mcg', 'label_display_name': 'Folic acid'},
        ],
      },
    ];
    final model = FormulaHistoryModel.fromLabelRecord(
      _labelRecord(
        history: [
          _snapshot(snapshotId: 'older', displayIngredients: olderRows),
        ],
      ),
      currentLabelRows: currentRows,
    );

    expect(model.snapshots.single.hasIngredientLevelDetails, isTrue);
    expect(model.snapshots.single.changedRows, isEmpty);
  });

  testWidgets('shows truthful no-history copy with an accessible heading', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final model = FormulaHistoryModel.fromLabelRecord(
      _labelRecord(lineageKey: null),
    );

    await tester.pumpWidget(_harness(model));

    expect(find.text('Formula history'), findsOneWidget);
    expect(
      find.text('No verified formula history is available for this product.'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Formula history'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets(
    'renders only real snapshot metadata and fingerprint comparison',
    (tester) async {
      final model = FormulaHistoryModel.fromLabelRecord(
        _labelRecord(
          history: [
            _snapshot(
              snapshotId: 'dsld-999-v5',
              catalogVersion: '5',
              sourceUpdatedDate: '2024-03-04T10:11:12Z',
            ),
            _snapshot(snapshotId: 'undated'),
          ],
        ),
      );

      await tester.pumpWidget(_harness(model));

      expect(find.text('Snapshot dsld-999-v5'), findsOneWidget);
      expect(find.text('Catalog version 5'), findsOneWidget);
      expect(find.text('Source updated 2024-03-04T10:11:12Z'), findsOneWidget);
      expect(find.text('Formula differs from current label'), findsNWidgets(2));
      expect(
        find.text(
          'Ingredient-level changes were not provided with this snapshot.',
        ),
        findsNWidgets(2),
      );
      expect(find.textContaining('Reformulated'), findsNothing);
      expect(find.textContaining('Source date unavailable'), findsNothing);
    },
  );

  testWidgets('labels identical fingerprints unchanged, never reformulated', (
    tester,
  ) async {
    final currentFingerprint = _fingerprint('c');
    final model = FormulaHistoryModel.fromLabelRecord(
      _labelRecord(
        formulaFingerprint: currentFingerprint,
        history: [
          _snapshot(
            snapshotId: 'same-formula',
            fingerprint: currentFingerprint,
            productStatus: 'reformulated',
          ),
        ],
      ),
    );

    await tester.pumpWidget(_harness(model));

    expect(find.text('Formula unchanged'), findsOneWidget);
    expect(find.text('Reformulated'), findsNothing);
  });
}
