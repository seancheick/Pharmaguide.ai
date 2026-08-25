import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/contributions/providers/product_submission_providers.dart';
import 'package:pharmaguide/services/product_submission_service.dart';

Map<String, Object?> _row({
  required String id,
  required String upc,
  required String uploadState,
  required String reviewStatus,
}) => {
  'id': id,
  'kind': 'missing_product',
  'normalized_upc': upc,
  'upload_state': uploadState,
  'review_status': reviewStatus,
  'created_at': '2026-08-25T15:41:35.000Z',
  'promoted_catalog_version': null,
  'promoted_at': null,
  'resolution_code': null,
  'resolution_detail': null,
  'resolved_dsld_id': null,
};

class _ListBackend implements ProductSubmissionBackend {
  _ListBackend(this.rows);

  final List<Map<String, Object?>> rows;

  @override
  String? get authenticatedUserId => '3f276b64-0836-4bea-9453-1c8db4d1f8dd';

  @override
  Future<List<Map<String, Object?>>> listOwnSubmissions({
    required String table,
  }) async => rows;

  @override
  Future<void> persistSubmission({
    required String functionName,
    required Map<String, Object?> payload,
  }) async => throw UnimplementedError();

  @override
  Future<void> uploadPhoto({
    required String bucket,
    required String objectPath,
    required Uint8List bytes,
    required String contentType,
  }) async => throw UnimplementedError();

  @override
  Future<bool> finalizeSubmission({
    required String functionName,
    required String submissionId,
  }) async => throw UnimplementedError();
}

void main() {
  test(
    'hides abandoned duplicate uploads behind their completed sibling',
    () async {
      // The field failure: two "Upload incomplete — try again" orphans for a
      // barcode whose submission already completed and was approved. They
      // were minted when the duplicate check only fired at finalize; their
      // retry copy sent the user straight back into the conflict.
      final container = ProviderContainer(
        overrides: [
          productSubmissionServiceProvider.overrideWithValue(
            ProductSubmissionService(
              backend: _ListBackend([
                _row(
                  id: '00000000-0000-4000-8000-000000000001',
                  upc: '0850021920654',
                  uploadState: 'pending',
                  reviewStatus: 'submitted',
                ),
                _row(
                  id: '00000000-0000-4000-8000-000000000002',
                  upc: '0850021920654',
                  uploadState: 'pending',
                  reviewStatus: 'submitted',
                ),
                _row(
                  id: '00000000-0000-4000-8000-000000000003',
                  upc: '0850021920654',
                  uploadState: 'ready',
                  reviewStatus: 'approved',
                ),
                // A genuinely interrupted submission with no completed
                // sibling keeps its retry guidance.
                _row(
                  id: '00000000-0000-4000-8000-000000000004',
                  upc: '0850051911561',
                  uploadState: 'pending',
                  reviewStatus: 'submitted',
                ),
              ]),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final visible = await container.read(productSubmissionsProvider.future);

      expect(visible.map((s) => s.submissionId), [
        '00000000-0000-4000-8000-000000000003',
        '00000000-0000-4000-8000-000000000004',
      ]);
    },
  );
}
