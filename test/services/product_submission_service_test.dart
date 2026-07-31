import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/services/product_submission_service.dart';

const _submissionId = '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a11';
const _userId = '3f276b64-0836-4bea-9453-1c8db4d1f8dd';

void main() {
  group('missing-product evidence contract', () {
    test('requires front and Supplement Facts photos', () {
      expect(
        () => MissingProductSubmissionDraft(
          submissionId: _submissionId,
          upc: '050428381397',
          photos: [_photo(ProductSubmissionPhotoSlot.front)],
          otherIngredientsNotPresent: true,
        ),
        throwsA(
          isA<ProductSubmissionValidationException>().having(
            (error) => error.reason,
            'reason',
            ProductSubmissionValidationFailure.missingRequiredPhoto,
          ),
        ),
      );
    });

    test('requires Other Ingredients evidence or explicit label absence', () {
      expect(
        () => MissingProductSubmissionDraft(
          submissionId: _submissionId,
          upc: '050428381397',
          photos: [
            _photo(ProductSubmissionPhotoSlot.front),
            _photo(ProductSubmissionPhotoSlot.supplementFacts),
          ],
        ),
        throwsA(
          isA<ProductSubmissionValidationException>().having(
            (error) => error.reason,
            'reason',
            ProductSubmissionValidationFailure.missingOtherIngredientsEvidence,
          ),
        ),
      );
    });

    test('normalizes a scanned UPC without accepting arbitrary text', () {
      final draft = MissingProductSubmissionDraft(
        submissionId: _submissionId,
        upc: '0 50428 38139 7',
        photos: [
          _photo(ProductSubmissionPhotoSlot.front),
          _photo(ProductSubmissionPhotoSlot.supplementFacts),
          _photo(ProductSubmissionPhotoSlot.otherIngredients),
        ],
      );

      expect(draft.upc, '050428381397');
      expect(
        () => MissingProductSubmissionDraft(
          submissionId: _submissionId,
          upc: 'patient takes metformin',
          photos: [
            _photo(ProductSubmissionPhotoSlot.front),
            _photo(ProductSubmissionPhotoSlot.supplementFacts),
          ],
          otherIngredientsNotPresent: true,
        ),
        throwsA(isA<ProductSubmissionValidationException>()),
      );
    });

    test('rejects a barcode whose GTIN check digit is wrong', () {
      expect(
        () => MissingProductSubmissionDraft(
          submissionId: _submissionId,
          upc: '12345678',
          photos: [
            _photo(ProductSubmissionPhotoSlot.front),
            _photo(ProductSubmissionPhotoSlot.supplementFacts),
          ],
          otherIngredientsNotPresent: true,
        ),
        throwsA(
          isA<ProductSubmissionValidationException>().having(
            (error) => error.reason,
            'reason',
            ProductSubmissionValidationFailure.invalidUpc,
          ),
        ),
      );
    });
  });

  group('one submission orchestrator', () {
    test('persists one typed manifest before uploading private bytes', () async {
      final backend = _FakeBackend(authenticatedUserId: _userId);
      final service = ProductSubmissionService(backend: backend);
      final draft = MissingProductSubmissionDraft(
        submissionId: _submissionId,
        upc: '050428381397',
        photos: [
          _photo(ProductSubmissionPhotoSlot.front),
          _photo(ProductSubmissionPhotoSlot.supplementFacts),
        ],
        otherIngredientsNotPresent: true,
      );

      final result = await service.submit(draft);

      expect(result, isA<ProductSubmissionSuccess>());
      expect(backend.operations, [
        'persist',
        'finalize:$_submissionId',
        'upload:$_userId/$_submissionId/front',
        'upload:$_userId/$_submissionId/supplement_facts',
        'finalize:$_submissionId',
      ]);
      expect(backend.persistedPayload, {
        'p_submission_id': _submissionId,
        'p_kind': 'missing_product',
        'p_upc': '050428381397',
        'p_mismatch_detail': null,
        'p_other_ingredients_not_present': true,
        'p_photos': [
          {
            'photo_slot': 'front',
            'content_type': 'image/jpeg',
            'byte_size': 3,
            'content_sha256':
                '039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81',
          },
          {
            'photo_slot': 'supplement_facts',
            'content_type': 'image/jpeg',
            'byte_size': 3,
            'content_sha256':
                '039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81',
          },
        ],
      });
    });

    test(
      'label mismatch uses the same RPC without missing-product fields',
      () async {
        final backend = _FakeBackend(authenticatedUserId: _userId);
        final service = ProductSubmissionService(backend: backend);
        final draft = LabelMismatchReportDraft(
          submissionId: _submissionId,
          product: LabelMismatchProductMetadata(
            dsldId: '278454',
            upc: '850030689122',
          ),
          categories: const {LabelMismatchCategory.amountOrUnit},
        );

        final result = await service.submit(draft);

        expect(result, isA<ProductSubmissionSuccess>());
        expect(backend.persistedPayload, {
          'p_submission_id': _submissionId,
          'p_kind': 'label_mismatch',
          'p_upc': '850030689122',
          'p_mismatch_detail': {
            'dsld_id': '278454',
            'source_record_id': null,
            'catalog_source_version': null,
            'formula_fingerprint': null,
            'mismatch_categories': ['amount_or_unit'],
          },
          'p_other_ingredients_not_present': false,
          'p_photos': <Map<String, Object?>>[],
        });
      },
    );

    test(
      'unknown server status remains unavailable instead of looking complete',
      () async {
        final backend = _FakeBackend(
          authenticatedUserId: _userId,
          statusRows: [
            {
              'id': _submissionId,
              'kind': 'missing_product',
              'normalized_upc': '050428381397',
              'upload_state': 'ready',
              'review_status': 'future_status',
              'created_at': '2026-07-30T12:00:00Z',
              'promoted_catalog_version': null,
            },
          ],
        );
        final service = ProductSubmissionService(backend: backend);

        final statuses = await service.listOwnSubmissions();

        expect(statuses, hasLength(1));
        expect(
          statuses.single.reviewStatus,
          ProductSubmissionReviewStatus.unknown,
        );
        expect(statuses.single.isComplete, isFalse);
      },
    );
  });
}

ProductSubmissionPhoto _photo(ProductSubmissionPhotoSlot slot) {
  return ProductSubmissionPhoto(
    slot: slot,
    bytes: Uint8List.fromList([1, 2, 3]),
    contentType: 'image/jpeg',
  );
}

class _FakeBackend implements ProductSubmissionBackend {
  _FakeBackend({this.authenticatedUserId, this.statusRows = const []});

  @override
  final String? authenticatedUserId;
  final List<Map<String, Object?>> statusRows;
  final operations = <String>[];
  final Set<String> uploadedPaths = {};
  Map<String, Object?>? persistedPayload;

  @override
  Future<void> persistSubmission({
    required String functionName,
    required Map<String, Object?> payload,
  }) async {
    expect(functionName, ProductSubmissionService.createFunction);
    operations.add('persist');
    persistedPayload = payload;
  }

  @override
  Future<bool> finalizeSubmission({
    required String functionName,
    required String submissionId,
  }) async {
    expect(functionName, ProductSubmissionService.finalizeFunction);
    operations.add('finalize:$submissionId');
    final photos =
        persistedPayload?['p_photos'] as List<Map<String, Object?>>? ??
        const [];
    final expected = photos.map(
      (photo) => '$_userId/$submissionId/${photo['photo_slot']}',
    );
    return expected.every(uploadedPaths.contains);
  }

  @override
  Future<void> uploadPhoto({
    required String bucket,
    required String objectPath,
    required Uint8List bytes,
    required String contentType,
  }) async {
    expect(bucket, ProductSubmissionService.photoBucket);
    operations.add('upload:$objectPath');
    uploadedPaths.add(objectPath);
  }

  @override
  Future<List<Map<String, Object?>>> listOwnSubmissions({
    required String table,
  }) async {
    expect(table, ProductSubmissionService.submissionsTable);
    return statusRows;
  }
}
