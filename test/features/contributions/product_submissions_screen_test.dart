import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/contributions/providers/product_submission_providers.dart';
import 'package:pharmaguide/features/contributions/product_submissions_screen.dart';
import 'package:pharmaguide/features/product_detail/widgets/label_mismatch_sheet.dart';
import 'package:pharmaguide/services/product_submission_service.dart';

Widget _harness(
  List<Map<String, Object?>> rows, {
  CoreDatabase? db,
  Future<void> Function(ProductSubmissionSummary status)? onResubmit,
  Future<void> Function(ProductSubmissionSummary status)? onHide,
}) {
  final database = db ?? CoreDatabase.memory();
  if (db == null) addTearDown(database.close);
  return ProviderScope(
    overrides: [
      productSubmissionServiceProvider.overrideWithValue(
        ProductSubmissionService(backend: _Backend(rows)),
      ),
      coreDatabaseProvider.overrideWithValue(database),
    ],
    child: MaterialApp(
      home: ProductSubmissionsScreen(onResubmit: onResubmit, onHide: onHide),
    ),
  );
}

void main() {
  testWidgets('shows review and shipped states without exposing other users', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness([
        _row(
          id: '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a11',
          reviewStatus: 'under_review',
        ),
        _row(
          id: '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a12',
          reviewStatus: 'approved',
          catalogVersion: '2026.07.30.1',
        ),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Your contributions'), findsOneWidget);
    expect(find.text('Under review'), findsOneWidget);
    expect(find.text('Added to catalog'), findsOneWidget);
    expect(find.textContaining('2026.07.30.1'), findsOneWidget);
    expect(find.textContaining('050428381397'), findsNWidgets(2));
  });

  testWidgets('unknown status is unavailable, never a false completion', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness([
        _row(
          id: '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a11',
          reviewStatus: 'future_state',
        ),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Status unavailable'), findsOneWidget);
    expect(find.text('Added to catalog'), findsNothing);
  });

  testWidgets(
    'unknown upload or kind is unavailable, not an incomplete upload',
    (tester) async {
      await tester.pumpWidget(
        _harness([
          {
            ..._row(
              id: '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a11',
              reviewStatus: 'submitted',
            ),
            'upload_state': 'future_state',
          },
          {
            ..._row(
              id: '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a12',
              reviewStatus: 'submitted',
            ),
            'kind': 'future_kind',
          },
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('Status unavailable'), findsNWidgets(2));
      expect(find.textContaining('start a new submission'), findsNothing);
      expect(find.text('Waiting for review'), findsNothing);
      expect(find.text('Submission details unavailable'), findsOneWidget);
    },
  );

  testWidgets('does not promise an unavailable upload-resume action', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness([
        {
          ..._row(
            id: '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a11',
            reviewStatus: 'submitted',
          ),
          'upload_state': 'pending',
        },
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('start a new submission'), findsOneWidget);
    expect(find.textContaining('reopen the submission'), findsNothing);
  });

  testWidgets('rejection guidance translates the resolution code', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness([
        {
          ..._row(
            id: '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a11',
            reviewStatus: 'rejected',
          ),
          'resolution_code': 'photo_quality',
        },
        {
          ..._row(
            id: '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a12',
            reviewStatus: 'rejected',
          ),
          'resolution_code': 'other',
          'resolution_detail': 'The lot number sticker covered the panel.',
        },
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('too blurry or dark'), findsOneWidget);
    expect(
      find.text('The lot number sticker covered the panel.'),
      findsOneWidget,
    );
  });

  testWidgets('duplicate outcomes use distinct truthful headlines', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness([
        {
          ..._row(
            id: '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a11',
            reviewStatus: 'duplicate',
          ),
          'resolution_code': 'already_in_catalog',
        },
        {
          ..._row(
            id: '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a12',
            reviewStatus: 'duplicate',
          ),
          'resolution_code': 'duplicate_submission',
        },
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Already in the catalog'), findsOneWidget);
    expect(find.text('Already on its way'), findsOneWidget);
    expect(find.text('Already under review'), findsNothing);
  });

  testWidgets('offers resubmission only for evidence users can correct', (
    tester,
  ) async {
    ProductSubmissionSummary? retried;
    await tester.pumpWidget(
      _harness([
        {
          ..._row(
            id: '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a11',
            reviewStatus: 'rejected',
          ),
          'resolution_code': 'photo_quality',
        },
        {
          ..._row(
            id: '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a12',
            reviewStatus: 'rejected',
          ),
          'resolution_code': 'not_a_supplement',
        },
      ], onResubmit: (status) async => retried = status),
    );
    await tester.pumpAndSettle();

    final retry = find.text('Try again with new photos');
    expect(retry, findsOneWidget);
    await tester.tap(retry);
    await tester.pump();

    expect(retried?.submissionId, '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a11');
    expect(retried?.upc, '050428381397');
  });

  testWidgets('missing-product retry reopens capture for the rejected UPC', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness([
        {
          ..._row(
            id: '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a11',
            reviewStatus: 'rejected',
          ),
          'resolution_code': 'photo_quality',
        },
      ]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Try again with new photos'));
    await tester.pumpAndSettle();

    expect(find.text('Add this product'), findsOneWidget);
    expect(find.text('For barcode 050428381397'), findsOneWidget);
  });

  testWidgets('label-mismatch retry preserves its catalog identity', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness([
        {
          ..._row(
            id: '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a11',
            reviewStatus: 'rejected',
          ),
          'kind': 'label_mismatch',
          'resolution_code': 'label_unreadable',
          'product_submission_mismatch_details': {
            'dsld_id': '278454',
            'source_record_id': 'DSLD-278454',
            'catalog_source_version': '2026.08.25',
            'formula_fingerprint': null,
          },
        },
      ]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Try again with new photos'));
    await tester.pumpAndSettle();

    expect(find.text('Report a label mismatch'), findsOneWidget);
    expect(
      tester
          .widget<LabelMismatchSheet>(find.byType(LabelMismatchSheet))
          .product
          .dsldId,
      '278454',
    );
  });

  testWidgets('deep link renders only when the product exists locally', (
    tester,
  ) async {
    final db = CoreDatabase.memory();
    addTearDown(db.close);
    await db
        .into(db.productsCore)
        .insert(
          ProductsCoreCompanion.insert(
            dsldId: 'PG_SUB_AAAA',
            productName: 'Promoted Product',
            exportVersion: 'test',
            exportedAt: '2026-08-24T00:00:00Z',
            productStatus: const Value('active'),
          ),
        );

    await tester.pumpWidget(
      _harness([
        {
          ..._row(
            id: '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a11',
            reviewStatus: 'approved',
            catalogVersion: '2026.08.30.1',
          ),
          'resolved_dsld_id': 'PG_SUB_AAAA',
        },
        {
          ..._row(
            id: '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a12',
            reviewStatus: 'approved',
            catalogVersion: '2026.08.30.1',
          ),
          'resolved_dsld_id': 'PG_SUB_NOT_INSTALLED',
        },
      ], db: db),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('submission-view-product-PG_SUB_AAAA')),
      findsOneWidget,
    );
    expect(find.text('Promoted Product'), findsOneWidget);
    expect(
      find.byKey(const Key('submission-view-product-PG_SUB_NOT_INSTALLED')),
      findsNothing,
    );
    expect(
      find.text('Available after your next catalog update.'),
      findsOneWidget,
    );
  });

  testWidgets('unknown rejected product uses a plain name fallback above UPC', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness([
        {
          ..._row(id: 'rejected', reviewStatus: 'rejected'),
          'resolution_code': 'photo_quality',
        },
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Product name unavailable'), findsOneWidget);
    expect(find.text('UPC 050428381397'), findsOneWidget);
  });

  testWidgets('failed cards offer a confirmed non-destructive history hide', (
    tester,
  ) async {
    ProductSubmissionSummary? hidden;
    await tester.pumpWidget(
      _harness([
        {
          ..._row(id: 'rejected', reviewStatus: 'rejected'),
          'resolution_code': 'photo_quality',
        },
        _row(id: 'accepted', reviewStatus: 'approved', catalogVersion: 'v1'),
      ], onHide: (status) async => hidden = status),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Hide from history'), findsOneWidget);
    await tester.tap(find.byTooltip('Hide from history'));
    await tester.pumpAndSettle();

    expect(find.text('Hide this submission?'), findsOneWidget);
    expect(
      find.textContaining('review record stays securely stored'),
      findsOneWidget,
    );
    await tester.tap(find.text('Hide from history'));
    await tester.pumpAndSettle();

    expect(hidden?.submissionId, 'rejected');
  });

  testWidgets('impact grid counts finalized outcomes and catalog impact', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness([
        _row(
          id: '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a11',
          reviewStatus: 'under_review',
        ),
        _row(
          id: '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a12',
          reviewStatus: 'approved',
        ),
        _row(
          id: '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a13',
          reviewStatus: 'approved',
          catalogVersion: '2026.08.25.1',
        ),
        _row(
          id: '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a14',
          reviewStatus: 'rejected',
        ),
        {
          ..._row(
            id: '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a15',
            reviewStatus: 'submitted',
          ),
          'upload_state': 'pending',
        },
      ]),
    );
    await tester.pumpAndSettle();

    Text statValue(String key) => tester.widget<Text>(
      find
          .descendant(of: find.byKey(Key(key)), matching: find.byType(Text))
          .first,
    );

    expect(statValue('contributions-stat-pending').data, '1');
    expect(statValue('contributions-stat-approved').data, '1');
    expect(statValue('contributions-stat-total').data, '4');
    expect(statValue('contributions-stat-points').data, '10');
    expect(find.text('Catalog additions'), findsOneWidget);
  });

  testWidgets('points card explains one-time awards and future rewards', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness([
        _row(
          id: '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a13',
          reviewStatus: 'approved',
          catalogVersion: '2026.08.25.1',
        ),
      ]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('contributions-stat-points')));
    await tester.pumpAndSettle();

    expect(find.text('How points work'), findsOneWidget);
    expect(
      find.textContaining('Earn 10 points when a product you submit'),
      findsOneWidget,
    );
    expect(
      find.textContaining('plan to make points redeemable'),
      findsOneWidget,
    );
  });

  testWidgets('total card explains finalized outcomes without draft shells', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness([
        _row(id: 'a', reviewStatus: 'under_review'),
        _row(id: 'b', reviewStatus: 'rejected'),
        _row(id: 'c', reviewStatus: 'approved', catalogVersion: '2026.08.25.1'),
        {
          ..._row(id: 'd', reviewStatus: 'submitted'),
          'upload_state': 'pending',
        },
      ]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('contributions-stat-total')));
    await tester.pumpAndSettle();

    expect(find.text('Submission breakdown'), findsOneWidget);
    expect(find.text('Pending review'), findsNWidgets(2));
    expect(find.text('Not added'), findsNWidgets(2));
    expect(find.text('Finalized submissions'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('submission-breakdown-total')),
        matching: find.text('3'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('impact stats remain readable on a narrow large-text screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      _harness([
        for (var index = 0; index < 123; index++)
          _row(
            id: 'submission-$index',
            reviewStatus: 'approved',
            catalogVersion: '2026.08.25.1',
          ),
      ]),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('contributions-stat-points')), findsOneWidget);
  });

  test('contribution points award ten only after catalog promotion', () {
    ProductSubmissionSummary summary(Map<String, Object?> row) =>
        ProductSubmissionSummary.fromRow(row);
    expect(
      contributionPoints([
        summary({
          ..._row(id: 'a', reviewStatus: 'submitted'),
          'upload_state': 'pending',
        }),
        summary(_row(id: 'b', reviewStatus: 'rejected')),
        summary(_row(id: 'c', reviewStatus: 'approved')),
        summary(_row(id: 'd', reviewStatus: 'approved', catalogVersion: 'v1')),
      ]),
      10,
    );
  });
}

Map<String, Object?> _row({
  required String id,
  required String reviewStatus,
  String? catalogVersion,
}) {
  return {
    'id': id,
    'kind': 'missing_product',
    'normalized_upc': '050428381397',
    'upload_state': 'ready',
    'review_status': reviewStatus,
    'created_at': '2026-07-30T12:00:00Z',
    'promoted_catalog_version': catalogVersion,
  };
}

class _Backend implements ProductSubmissionBackend {
  _Backend(this.rows);

  final List<Map<String, Object?>> rows;
  @override
  String? get authenticatedUserId => 'user-id';

  @override
  Future<List<Map<String, Object?>>> listOwnSubmissions({
    required String table,
    required int offset,
    required int limit,
  }) async {
    return rows.skip(offset).take(limit).toList(growable: false);
  }

  @override
  Future<bool> finalizeSubmission({
    required String functionName,
    required String submissionId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> persistSubmission({
    required String functionName,
    required Map<String, Object?> payload,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> uploadPhoto({
    required String bucket,
    required String objectPath,
    required Uint8List bytes,
    required String contentType,
  }) {
    throw UnimplementedError();
  }
}
