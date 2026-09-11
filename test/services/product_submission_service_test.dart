import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/contributions/product_submission_consent_copy.dart';
import 'package:pharmaguide/services/product_submission_service.dart';

const _submissionId = '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a11';
const _rejectedSubmissionId = '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a10';
const _userId = '3f276b64-0836-4bea-9453-1c8db4d1f8dd';

void main() {
  test('display name is trimmed and never changes identity fields', () async {
    final backend = _FakeBackend(authenticatedUserId: _userId);
    await ProductSubmissionService(
      backend: backend,
    ).setDisplayName(_submissionId, ' Seed · DS-01 ');
    expect(
      backend.persistedFunctionName,
      'set_product_submission_display_name',
    );
    expect(backend.persistedPayload, {
      'p_submission_id': _submissionId,
      'p_display_name': 'Seed · DS-01',
    });
    for (final name in ['', 'x\nname', 'x' * 161]) {
      await expectLater(
        ProductSubmissionService(
          backend: backend,
        ).setDisplayName(_submissionId, name),
        throwsFormatException,
      );
    }
  });
  group('owner-scoped intake', () {
    test(
      'sends validated original barcode and parses only known actions',
      () async {
        final backend = _FakeBackend(authenticatedUserId: _userId);
        final service = ProductSubmissionService(backend: backend);
        final result = await service.checkIntake(
          kind: ProductSubmissionKind.missingProduct,
          upc: '050428381397',
        );
        expect(result.action, ProductSubmissionIntakeAction.startNew);
        expect(backend.intakePayload, {
          'p_kind': 'missing_product',
          'p_upc': '050428381397',
          'p_dsld_id': null,
        });
        expect(backend.persistedPayload, isNull);
        expect(backend.uploadedPaths, isEmpty);
      },
    );

    test(
      'refuses signed-out and invalid-barcode requests before networking',
      () async {
        final backend = _FakeBackend();
        final service = ProductSubmissionService(backend: backend);
        await expectLater(
          service.checkIntake(
            kind: ProductSubmissionKind.missingProduct,
            upc: '050428381397',
          ),
          throwsStateError,
        );
        expect(backend.intakePayload, isNull);
        backend.authenticatedUserId = _userId;
        await expectLater(
          service.checkIntake(
            kind: ProductSubmissionKind.missingProduct,
            upc: '1234',
          ),
          throwsA(isA<ProductSubmissionValidationException>()),
        );
        expect(backend.intakePayload, isNull);
      },
    );

    test('account switch during lookup discards the old receipt', () async {
      final backend = _FakeBackend(authenticatedUserId: _userId)
        ..onIntake = () {};
      backend.onIntake = () => backend.authenticatedUserId = 'other-user';
      await expectLater(
        ProductSubmissionService(backend: backend).checkIntake(
          kind: ProductSubmissionKind.missingProduct,
          upc: '050428381397',
        ),
        throwsStateError,
      );
    });

    for (final response in <Map<String, Object?>>[
      {'action': 'future_action'},
      {'action': 'start_new', 'submission_id': _submissionId},
      {'action': 'open_existing'},
      {
        'action': 'retry_rejected',
        'submission_id': _submissionId,
        'normalized_upc': '050428381397',
        'resolution_code': 'not_a_supplement',
      },
      {
        'action': 'retry_rejected',
        'submission_id': _submissionId,
        'normalized_upc': '050428381397',
        'resolution_code': 'product_identity_mismatch',
      },
      {
        'action': 'open_existing',
        'submission_id': _submissionId,
        'normalized_upc': '850021920654',
      },
    ]) {
      test('fails closed on invalid intake $response', () async {
        final backend = _FakeBackend(authenticatedUserId: _userId)
          ..intakeResponse = response;
        await expectLater(
          ProductSubmissionService(backend: backend).checkIntake(
            kind: ProductSubmissionKind.missingProduct,
            upc: '050428381397',
          ),
          throwsFormatException,
        );
      });
    }

    test(
      'accepts width-equivalent receipt without rewriting scanned barcode',
      () async {
        final backend = _FakeBackend(authenticatedUserId: _userId)
          ..intakeResponse = {
            'action': 'open_existing',
            'submission_id': _submissionId,
            'normalized_upc': '0050428381397',
          };
        final result = await ProductSubmissionService(backend: backend)
            .checkIntake(
              kind: ProductSubmissionKind.missingProduct,
              upc: '050428381397',
            );
        expect(result.submissionId, _submissionId);
        expect(backend.intakePayload!['p_upc'], '050428381397');
      },
    );
  });

  group('missing-product evidence contract', () {
    test('requires full evidence-category coverage', () {
      expect(
        () => MissingProductSubmissionDraft(
          submissionId: _submissionId,
          upc: '050428381397',
          photos: [_photo(ProductSubmissionEvidenceCategory.frontIdentity)],
          noSeparateIngredientPanel: true,
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

    test('requires barcode evidence to bind photos to the scanned product', () {
      expect(
        () => MissingProductSubmissionDraft(
          submissionId: _submissionId,
          upc: '050428381397',
          photos: [
            _photo(ProductSubmissionEvidenceCategory.frontIdentity),
            _photo(ProductSubmissionEvidenceCategory.supplementFacts),
            _photo(ProductSubmissionEvidenceCategory.ingredientDisclosure),
          ],
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

    test('ingredient disclosure is evidence, never a checkbox waiver', () {
      // The cue flag alone must NOT unlock submission: a facts photo
      // carrying the ingredient list is dual-tagged instead.
      expect(
        () => MissingProductSubmissionDraft(
          submissionId: _submissionId,
          upc: '050428381397',
          photos: [
            _photo(ProductSubmissionEvidenceCategory.frontIdentity),
            _photo(ProductSubmissionEvidenceCategory.supplementFacts),
          ],
          noSeparateIngredientPanel: true,
        ),
        throwsA(
          isA<ProductSubmissionValidationException>().having(
            (error) => error.reason,
            'reason',
            ProductSubmissionValidationFailure.missingRequiredPhoto,
          ),
        ),
      );

      final dualTagged = MissingProductSubmissionDraft(
        submissionId: _submissionId,
        upc: '050428381397',
        photos: [
          _photo(ProductSubmissionEvidenceCategory.frontIdentity),
          ProductSubmissionPhoto(
            photoId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2',
            categories: const {
              ProductSubmissionEvidenceCategory.supplementFacts,
              ProductSubmissionEvidenceCategory.ingredientDisclosure,
            },
            bytes: Uint8List.fromList([7, 7, 7]),
            contentType: 'image/jpeg',
          ),
          _photo(ProductSubmissionEvidenceCategory.barcode),
        ],
        noSeparateIngredientPanel: true,
      );
      expect(dualTagged.noSeparateIngredientPanel, isTrue);
    });

    test('normalizes a scanned UPC without accepting arbitrary text', () {
      final draft = MissingProductSubmissionDraft(
        submissionId: _submissionId,
        upc: '0 50428 38139 7',
        photos: [
          _photo(ProductSubmissionEvidenceCategory.frontIdentity),
          _photo(ProductSubmissionEvidenceCategory.supplementFacts),
          _photo(ProductSubmissionEvidenceCategory.ingredientDisclosure),
          _photo(ProductSubmissionEvidenceCategory.barcode),
        ],
      );

      expect(draft.upc, '050428381397');
      expect(
        () => MissingProductSubmissionDraft(
          submissionId: _submissionId,
          upc: 'patient takes metformin',
          photos: [
            _photo(ProductSubmissionEvidenceCategory.frontIdentity),
            _photo(ProductSubmissionEvidenceCategory.supplementFacts),
            _photo(ProductSubmissionEvidenceCategory.ingredientDisclosure),
          ],
        ),
        throwsA(isA<ProductSubmissionValidationException>()),
      );
    });

    test('expands UPC-E into the canonical submit identity', () {
      final draft = MissingProductSubmissionDraft(
        submissionId: _submissionId,
        upc: '06543217',
        photos: [
          _photo(ProductSubmissionEvidenceCategory.frontIdentity),
          _photo(ProductSubmissionEvidenceCategory.supplementFacts),
          _photo(ProductSubmissionEvidenceCategory.ingredientDisclosure),
          _photo(ProductSubmissionEvidenceCategory.barcode),
        ],
      );

      expect(draft.upc, '065100004327');
    });

    test('rejects a barcode whose GTIN check digit is wrong', () {
      expect(
        () => MissingProductSubmissionDraft(
          submissionId: _submissionId,
          upc: '12345678',
          photos: [
            _photo(ProductSubmissionEvidenceCategory.frontIdentity),
            _photo(ProductSubmissionEvidenceCategory.supplementFacts),
            _photo(ProductSubmissionEvidenceCategory.ingredientDisclosure),
            _photo(ProductSubmissionEvidenceCategory.barcode),
          ],
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

    test('rejects malformed resubmission lineage before network work', () {
      expect(
        () => MissingProductSubmissionDraft(
          submissionId: _submissionId,
          upc: '050428381397',
          resubmissionOf: 'not-a-uuid',
          photos: [
            _photo(ProductSubmissionEvidenceCategory.frontIdentity),
            _photo(ProductSubmissionEvidenceCategory.supplementFacts),
            _photo(ProductSubmissionEvidenceCategory.ingredientDisclosure),
            _photo(ProductSubmissionEvidenceCategory.barcode),
          ],
        ),
        throwsA(
          isA<ProductSubmissionValidationException>().having(
            (error) => error.reason,
            'reason',
            ProductSubmissionValidationFailure.invalidReportId,
          ),
        ),
      );
    });
  });

  group('one submission orchestrator', () {
    test(
      'persists one typed manifest before uploading private bytes',
      () async {
        final backend = _FakeBackend(authenticatedUserId: _userId);
        final service = ProductSubmissionService(backend: backend);
        final draft = MissingProductSubmissionDraft(
          submissionId: _submissionId,
          upc: '050428381397',
          photos: [
            _photo(ProductSubmissionEvidenceCategory.frontIdentity),
            _photo(ProductSubmissionEvidenceCategory.supplementFacts),
            _photo(ProductSubmissionEvidenceCategory.ingredientDisclosure),
            _photo(ProductSubmissionEvidenceCategory.barcode),
          ],
        );

        final result = await service.submit(draft);

        expect(result, isA<ProductSubmissionSuccess>());
        expect(backend.operations, [
          'persist',
          'finalize:$_submissionId',
          'upload:$_userId/$_submissionId/$_frontPhotoId',
          'upload:$_userId/$_submissionId/$_factsPhotoId',
          'upload:$_userId/$_submissionId/$_ingredientsPhotoId',
          'upload:$_userId/$_submissionId/$_barcodePhotoId',
          'finalize:$_submissionId',
        ]);
        expect(backend.persistedPayload, {
          'p_submission_id': _submissionId,
          'p_kind': 'missing_product',
          'p_upc': '050428381397',
          'p_mismatch_detail': null,
          'p_no_separate_ingredient_panel': false,
          'p_consent_version': productSubmissionConsentVersion,
          'p_photos': [
            {
              'photo_id': _frontPhotoId,
              'seq': 1,
              'categories': ['front_identity'],
              'content_type': 'image/jpeg',
              'byte_size': 4,
              'content_sha256': _photo(
                ProductSubmissionEvidenceCategory.frontIdentity,
              ).contentSha256,
            },
            {
              'photo_id': _factsPhotoId,
              'seq': 2,
              'categories': ['supplement_facts'],
              'content_type': 'image/jpeg',
              'byte_size': 4,
              'content_sha256': _photo(
                ProductSubmissionEvidenceCategory.supplementFacts,
              ).contentSha256,
            },
            {
              'photo_id': _ingredientsPhotoId,
              'seq': 3,
              'categories': ['ingredient_disclosure'],
              'content_type': 'image/jpeg',
              'byte_size': 4,
              'content_sha256': _photo(
                ProductSubmissionEvidenceCategory.ingredientDisclosure,
              ).contentSha256,
            },
            {
              'photo_id': _barcodePhotoId,
              'seq': 4,
              'categories': ['barcode'],
              'content_type': 'image/jpeg',
              'byte_size': 4,
              'content_sha256': _photo(
                ProductSubmissionEvidenceCategory.barcode,
              ).contentSha256,
            },
          ],
        });
      },
    );

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
          'p_no_separate_ingredient_panel': false,
          'p_consent_version': productSubmissionConsentVersion,
          'p_photos': <Map<String, Object?>>[],
        });
      },
    );

    test('sends rejected-submission lineage only on a resubmission', () async {
      final backend = _FakeBackend(authenticatedUserId: _userId);
      final service = ProductSubmissionService(backend: backend);
      final draft = MissingProductSubmissionDraft(
        submissionId: _submissionId,
        resubmissionOf: _rejectedSubmissionId,
        upc: '050428381397',
        photos: [
          _photo(ProductSubmissionEvidenceCategory.frontIdentity),
          _photo(ProductSubmissionEvidenceCategory.supplementFacts),
          _photo(ProductSubmissionEvidenceCategory.ingredientDisclosure),
          _photo(ProductSubmissionEvidenceCategory.barcode),
        ],
      );

      final result = await service.submit(draft);

      expect(result, isA<ProductSubmissionSuccess>());
      expect(
        backend.persistedPayload?['p_resubmission_of'],
        _rejectedSubmissionId,
      );
    });

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

    test('loads every submission instead of stopping at one page', () async {
      final backend = _FakeBackend(
        authenticatedUserId: _userId,
        statusRows: [
          for (var index = 0; index < 205; index++)
            {
              'id': 'submission-$index',
              'kind': 'missing_product',
              'normalized_upc': '050428381397',
              'upload_state': 'ready',
              'review_status': 'submitted',
              'created_at': '2026-07-30T12:00:00Z',
              'promoted_catalog_version': null,
            },
        ],
      );
      final service = ProductSubmissionService(backend: backend);

      final statuses = await service.listOwnSubmissions();

      expect(statuses, hasLength(205));
      expect(statuses.first.submissionId, 'submission-0');
      expect(statuses.last.submissionId, 'submission-204');
    });

    test('hides a terminal submission through the owner-scoped RPC', () async {
      final backend = _FakeBackend(authenticatedUserId: _userId);
      final service = ProductSubmissionService(backend: backend);

      await service.hideFromHistory(_rejectedSubmissionId);

      expect(
        backend.persistedFunctionName,
        ProductSubmissionService.hideFromHistoryFunction,
      );
      expect(backend.persistedPayload, {
        'p_submission_id': _rejectedSubmissionId,
      });
    });
  });
}

const _frontPhotoId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1';
const _factsPhotoId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2';
const _ingredientsPhotoId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3';
const _barcodePhotoId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4';

ProductSubmissionPhoto _photo(ProductSubmissionEvidenceCategory category) {
  final id = switch (category) {
    ProductSubmissionEvidenceCategory.frontIdentity => _frontPhotoId,
    ProductSubmissionEvidenceCategory.supplementFacts => _factsPhotoId,
    ProductSubmissionEvidenceCategory.ingredientDisclosure =>
      _ingredientsPhotoId,
    ProductSubmissionEvidenceCategory.barcode => _barcodePhotoId,
    _ => _frontPhotoId,
  };
  return ProductSubmissionPhoto(
    photoId: id,
    categories: {category},
    bytes: Uint8List.fromList([1, 2, 3, id.codeUnitAt(id.length - 1)]),
    contentType: 'image/jpeg',
  );
}

class _FakeBackend implements ProductSubmissionBackend {
  @override
  Future<Map<String, Object?>> fetchIntake({
    required String functionName,
    required Map<String, Object?> payload,
  }) async {
    expect(functionName, ProductSubmissionService.intakeFunction);
    intakePayload = payload;
    onIntake?.call();
    return intakeResponse;
  }

  _FakeBackend({this.authenticatedUserId, this.statusRows = const []});

  @override
  String? authenticatedUserId;
  Map<String, Object?> intakeResponse = {'action': 'start_new'};
  Map<String, Object?>? intakePayload;
  void Function()? onIntake;
  final List<Map<String, Object?>> statusRows;
  final operations = <String>[];
  final Set<String> uploadedPaths = {};
  Map<String, Object?>? persistedPayload;
  String? persistedFunctionName;

  @override
  Future<void> persistSubmission({
    required String functionName,
    required Map<String, Object?> payload,
  }) async {
    expect(
      functionName,
      anyOf(
        ProductSubmissionService.createFunction,
        ProductSubmissionService.hideFromHistoryFunction,
        'set_product_submission_display_name',
      ),
    );
    persistedFunctionName = functionName;
    operations.add('persist');
    persistedPayload = payload;
  }

  @override
  Future<Map<String, Object?>> fetchOwnEvidence({
    required String submissionId,
  }) => throw UnimplementedError();

  @override
  Future<int> openEvidenceRevision({required Map<String, Object?> payload}) =>
      throw UnimplementedError();

  @override
  Future<bool> finalizeSubmission({
    required String functionName,
    required String submissionId,
    int? expectedRevision,
  }) async {
    expect(functionName, ProductSubmissionService.finalizeFunction);
    operations.add('finalize:$submissionId');
    final photos =
        persistedPayload?['p_photos'] as List<Map<String, Object?>>? ??
        const [];
    final expected = photos.map(
      (photo) => '$_userId/$submissionId/${photo['photo_id']}',
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
    int offset = 0,
    int limit = 100,
  }) async {
    expect(table, ProductSubmissionService.submissionsTable);
    return statusRows.skip(offset).take(limit).toList(growable: false);
  }
}
