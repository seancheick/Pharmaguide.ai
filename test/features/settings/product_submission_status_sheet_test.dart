import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/contributions/providers/product_submission_providers.dart';
import 'package:pharmaguide/features/settings/v2/product_submission_status_sheet.dart';
import 'package:pharmaguide/services/product_submission_service.dart';

Widget _harness(List<Map<String, Object?>> rows, {CoreDatabase? db}) {
  final database = db ?? CoreDatabase.memory();
  return ProviderScope(
    overrides: [
      productSubmissionServiceProvider.overrideWithValue(
        ProductSubmissionService(backend: _Backend(rows)),
      ),
      coreDatabaseProvider.overrideWithValue(database),
    ],
    child: const MaterialApp(
      home: Scaffold(body: ProductSubmissionStatusSheet()),
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

    expect(find.text('Product submissions'), findsOneWidget);
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
      _harness(
        [
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
        ],
        db: db,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('submission-view-product-PG_SUB_AAAA')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('submission-view-product-PG_SUB_NOT_INSTALLED')),
      findsNothing,
    );
    expect(
      find.text('Available after your next catalog update.'),
      findsOneWidget,
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
  }) async {
    return rows;
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
