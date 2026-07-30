import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/settings/v2/product_submission_status_sheet.dart';
import 'package:pharmaguide/services/product_submission_service.dart';

void main() {
  testWidgets('shows review and shipped states without exposing other users', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProductSubmissionStatusSheet(
            service: ProductSubmissionService(
              backend: _Backend([
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
            ),
          ),
        ),
      ),
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
      MaterialApp(
        home: Scaffold(
          body: ProductSubmissionStatusSheet(
            service: ProductSubmissionService(
              backend: _Backend([
                _row(
                  id: '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a11',
                  reviewStatus: 'future_state',
                ),
              ]),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Status unavailable'), findsOneWidget);
    expect(find.text('Added to catalog'), findsNothing);
  });

  testWidgets(
    'unknown upload or kind is unavailable, not an incomplete upload',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProductSubmissionStatusSheet(
              service: ProductSubmissionService(
                backend: _Backend([
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
              ),
            ),
          ),
        ),
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
      MaterialApp(
        home: Scaffold(
          body: ProductSubmissionStatusSheet(
            service: ProductSubmissionService(
              backend: _Backend([
                {
                  ..._row(
                    id: '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a11',
                    reviewStatus: 'submitted',
                  ),
                  'upload_state': 'pending',
                },
              ]),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('start a new submission'), findsOneWidget);
    expect(find.textContaining('reopen the submission'), findsNothing);
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
