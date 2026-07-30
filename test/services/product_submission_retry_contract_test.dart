import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/services/product_submission_service.dart';

const _reportId = '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a11';
const _userId = '3f276b64-0836-4bea-9453-1c8db4d1f8dd';

void main() {
  group('closed report contract', () {
    test('category wire values exactly match the database allowlist', () {
      expect(
        LabelMismatchCategory.values.map((category) => category.wireValue),
        const [
          'product_identity',
          'ingredient_missing',
          'ingredient_extra',
          'amount_or_unit',
          'form_or_parenthetical',
          'serving_size_or_directions',
          'other_ingredients',
          'catalog_version_or_status',
        ],
      );
    });

    test('photo slots exactly match the private-storage contract', () {
      expect(
        ProductSubmissionPhotoSlot.values.map((slot) => slot.wireValue),
        const ['front', 'supplement_facts', 'other_ingredients'],
      );
      expect(ProductSubmissionPhoto.maxByteSize, 15728640);
      expect(ProductSubmissionPhoto.allowedContentTypes, const {
        'image/jpeg',
        'image/png',
        'image/heic',
        'image/heif',
        'image/webp',
      });
    });

    test('photo bytes remain immutable across retries', () {
      final source = Uint8List.fromList([1, 2, 3]);
      final photo = ProductSubmissionPhoto(
        slot: ProductSubmissionPhotoSlot.front,
        bytes: source,
        contentType: 'image/jpeg',
      );

      source[0] = 9;
      final exposed = photo.bytes;
      exposed[1] = 9;

      expect(photo.bytes, [1, 2, 3]);
      expect(photo.byteSize, 3);
    });

    test('rejects a fourth photo before any network operation', () {
      expect(
        () => _draft(
          photos: [
            _photo(ProductSubmissionPhotoSlot.front),
            _photo(ProductSubmissionPhotoSlot.supplementFacts),
            _photo(ProductSubmissionPhotoSlot.otherIngredients),
            _photo(ProductSubmissionPhotoSlot.front),
          ],
        ),
        throwsA(
          isA<ProductSubmissionValidationException>().having(
            (error) => error.reason,
            'reason',
            ProductSubmissionValidationFailure.tooManyPhotos,
          ),
        ),
      );
    });

    test('rejects duplicate named photo slots', () {
      expect(
        () => _draft(
          photos: [
            _photo(ProductSubmissionPhotoSlot.front),
            _photo(ProductSubmissionPhotoSlot.front),
          ],
        ),
        throwsA(
          isA<ProductSubmissionValidationException>().having(
            (error) => error.reason,
            'reason',
            ProductSubmissionValidationFailure.duplicatePhotoSlot,
          ),
        ),
      );
    });

    test(
      'rejects empty/oversize/unsupported images and invalid identifiers',
      () {
        expect(
          () => _draft(categories: const {}),
          throwsA(
            isA<ProductSubmissionValidationException>().having(
              (error) => error.reason,
              'reason',
              ProductSubmissionValidationFailure.noCategories,
            ),
          ),
        );
        expect(
          () => _photo(ProductSubmissionPhotoSlot.front, bytes: Uint8List(0)),
          throwsA(
            isA<ProductSubmissionValidationException>().having(
              (error) => error.reason,
              'reason',
              ProductSubmissionValidationFailure.emptyPhoto,
            ),
          ),
        );
        expect(
          () => ProductSubmissionPhoto(
            slot: ProductSubmissionPhotoSlot.front,
            bytes: Uint8List.fromList([1]),
            contentType: 'image/svg+xml',
          ),
          throwsA(
            isA<ProductSubmissionValidationException>().having(
              (error) => error.reason,
              'reason',
              ProductSubmissionValidationFailure.unsupportedPhotoContentType,
            ),
          ),
        );
        expect(
          () => _photo(
            ProductSubmissionPhotoSlot.front,
            bytes: Uint8List(ProductSubmissionPhoto.maxByteSize + 1),
          ),
          throwsA(
            isA<ProductSubmissionValidationException>().having(
              (error) => error.reason,
              'reason',
              ProductSubmissionValidationFailure.photoTooLarge,
            ),
          ),
        );
        expect(
          () => LabelMismatchProductMetadata(dsldId: '  '),
          throwsA(
            isA<ProductSubmissionValidationException>().having(
              (error) => error.reason,
              'reason',
              ProductSubmissionValidationFailure.missingDsldId,
            ),
          ),
        );
        expect(
          () => _draft(reportId: '../different-owner/report'),
          throwsA(
            isA<ProductSubmissionValidationException>().having(
              (error) => error.reason,
              'reason',
              ProductSubmissionValidationFailure.invalidReportId,
            ),
          ),
        );
        expect(
          () => _draft(reportId: '018f4c79-7c7e-7c70-9d62-7fc3b9ce6a11'),
          throwsA(
            isA<ProductSubmissionValidationException>().having(
              (error) => error.reason,
              'reason',
              ProductSubmissionValidationFailure.invalidReportId,
            ),
          ),
        );
        expect(
          () => LabelMismatchProductMetadata(
            dsldId: '12345',
            formulaFingerprint: 'sha256:abc123',
          ),
          throwsA(
            isA<ProductSubmissionValidationException>().having(
              (error) => error.reason,
              'reason',
              ProductSubmissionValidationFailure.invalidFormulaFingerprint,
            ),
          ),
        );
      },
    );

    test(
      'raw metadata rejects free text, label data, and all health fields',
      () {
        const forbiddenKeys = [
          'product_name',
          'notes',
          'free_text',
          'label_text',
          'raw_label',
          'profile',
          'medication',
          'medications',
          'condition',
          'conditions',
          'allergy',
          'allergies',
          'stack',
          'health',
          'fit_score',
        ];

        for (final key in forbiddenKeys) {
          expect(
            () => LabelMismatchProductMetadata.fromUntrusted({
              'dsld_id': '12345',
              key: 'must stay local',
            }),
            throwsA(
              isA<ProductSubmissionValidationException>().having(
                (error) => error.reason,
                'reason for $key',
                ProductSubmissionValidationFailure.unexpectedMetadata,
              ),
            ),
          );
        }
      },
    );
  });

  group('submission orchestration', () {
    test(
      'requires the live authenticated user before doing any work',
      () async {
        final backend = _FakeBackend();
        final service = ProductSubmissionService(backend: backend);

        final result = await service.submit(_draft());

        expect(
          result,
          isA<ProductSubmissionFailure>()
              .having(
                (failure) => failure.kind,
                'kind',
                ProductSubmissionFailureKind.authenticationRequired,
              )
              .having((failure) => failure.retryable, 'retryable', isFalse),
        );
        expect(backend.operations, isEmpty);
      },
    );

    test(
      'persists the report and photo manifest before uploading bytes',
      () async {
        final backend = _FakeBackend(authenticatedUserId: _userId);
        final service = ProductSubmissionService(backend: backend);
        final phases = <ProductSubmissionPhase>[];

        final result = await service.submit(
          _draft(
            photos: [
              _photo(ProductSubmissionPhotoSlot.front),
              _photo(ProductSubmissionPhotoSlot.supplementFacts),
            ],
          ),
          onPhaseChanged: phases.add,
        );

        expect(
          result,
          isA<ProductSubmissionSuccess>(),
          reason:
              'operations: ${backend.operations}; '
              'cause: ${result is ProductSubmissionFailure ? result.cause : null}',
        );
        expect(backend.operations, [
          'persist',
          'finalize:$_reportId',
          'upload:$_userId/$_reportId/front',
          'upload:$_userId/$_reportId/supplement_facts',
          'finalize:$_reportId',
        ]);
        expect(phases, [
          ProductSubmissionPhase.savingReport,
          ProductSubmissionPhase.uploadingPhotos,
          ProductSubmissionPhase.savingReport,
          ProductSubmissionPhase.succeeded,
        ]);
        expect(backend.uploads.map((upload) => upload.bucket).toSet(), {
          ProductSubmissionService.photoBucket,
        });
      },
    );

    test('writes only product/source/version/fingerprint report metadata', () async {
      final backend = _FakeBackend(authenticatedUserId: _userId);
      final service = ProductSubmissionService(backend: backend);

      await service.submit(
        _draft(
          metadata: LabelMismatchProductMetadata(
            dsldId: '12345',
            upc: '031604010206',
            sourceRecordId: 'DSLD-12345',
            catalogSourceVersion: '2026-07-19',
            formulaFingerprint:
                'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          ),
          categories: const {
            LabelMismatchCategory.amountOrUnit,
            LabelMismatchCategory.formOrParenthetical,
          },
          photos: [_photo(ProductSubmissionPhotoSlot.otherIngredients)],
        ),
      );

      expect(backend.reportRow, {
        'p_submission_id': _reportId,
        'p_kind': 'label_mismatch',
        'p_upc': '031604010206',
        'p_mismatch_detail': {
          'dsld_id': '12345',
          'source_record_id': 'DSLD-12345',
          'catalog_source_version': '2026-07-19',
          'formula_fingerprint':
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          'mismatch_categories': ['amount_or_unit', 'form_or_parenthetical'],
        },
        'p_other_ingredients_not_present': false,
        'p_photos': backend.photoRows,
      });
      expect(backend.photoRows, [
        {
          'photo_slot': 'other_ingredients',
          'content_type': 'image/jpeg',
          'byte_size': 3,
          'content_sha256':
              '039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81',
        },
      ]);
    });

    test(
      'omits absent nullable metadata instead of inventing values',
      () async {
        final backend = _FakeBackend(authenticatedUserId: _userId);
        final service = ProductSubmissionService(backend: backend);

        await service.submit(_draft());

        expect(backend.reportRow, {
          'p_submission_id': _reportId,
          'p_kind': 'label_mismatch',
          'p_upc': null,
          'p_mismatch_detail': {
            'dsld_id': '12345',
            'source_record_id': null,
            'catalog_source_version': null,
            'formula_fingerprint': null,
            'mismatch_categories': ['product_identity'],
          },
          'p_other_ingredients_not_present': false,
          'p_photos': <Map<String, Object?>>[],
        });
        expect(backend.photoRows, isEmpty);
      },
    );

    test('generated retry ids satisfy the storage UUID path policy', () {
      final draft = LabelMismatchReportDraft.create(
        product: LabelMismatchProductMetadata(dsldId: '12345'),
        categories: const {LabelMismatchCategory.productIdentity},
      );

      expect(
        draft.reportId,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
    });

    test(
      'retry reuses the same report id and extensionless object paths',
      () async {
        final backend = _FakeBackend(
          authenticatedUserId: _userId,
          persistFailuresRemaining: 1,
        );
        final service = ProductSubmissionService(backend: backend);
        final draft = _draft(
          photos: [_photo(ProductSubmissionPhotoSlot.supplementFacts)],
        );

        final first = await service.submit(draft);
        final second = await service.submit(draft);

        expect(
          first,
          isA<ProductSubmissionFailure>()
              .having(
                (failure) => failure.kind,
                'kind',
                ProductSubmissionFailureKind.reportInsertFailed,
              )
              .having((failure) => failure.retryable, 'retryable', isTrue),
        );
        expect(
          second,
          isA<ProductSubmissionSuccess>(),
          reason:
              'operations: ${backend.operations}; '
              'cause: ${second is ProductSubmissionFailure ? second.cause : null}',
        );
        expect(backend.uploads.map((upload) => upload.objectPath), const [
          '$_userId/$_reportId/supplement_facts',
        ]);
        expect(backend.reportRows.map((row) => row['p_submission_id']), [
          _reportId,
          _reportId,
        ]);
      },
    );

    test('report-row failure happens before any photo bytes upload', () async {
      final backend = _FakeBackend(
        authenticatedUserId: _userId,
        persistFailuresRemaining: 1,
      );
      final service = ProductSubmissionService(backend: backend);

      final result = await service.submit(
        _draft(
          photos: [
            _photo(ProductSubmissionPhotoSlot.front),
            _photo(ProductSubmissionPhotoSlot.otherIngredients),
          ],
        ),
      );

      expect(
        result,
        isA<ProductSubmissionFailure>().having(
          (failure) => failure.kind,
          'kind',
          ProductSubmissionFailureKind.reportInsertFailed,
        ),
      );
      expect(backend.operations, ['persist']);
      expect(backend.uploads, isEmpty);
    });

    test(
      'upload failure remains linked to its persisted report manifest',
      () async {
        final backend = _FakeBackend(
          authenticatedUserId: _userId,
          failUploadNumber: 2,
        );
        final service = ProductSubmissionService(backend: backend);

        final result = await service.submit(
          _draft(
            photos: [
              _photo(ProductSubmissionPhotoSlot.front),
              _photo(ProductSubmissionPhotoSlot.supplementFacts),
            ],
          ),
        );

        expect(
          result,
          isA<ProductSubmissionFailure>()
              .having(
                (failure) => failure.kind,
                'kind',
                ProductSubmissionFailureKind.photoUploadFailed,
              )
              .having((failure) => failure.retryable, 'retryable', isTrue),
        );
        expect(backend.reportRows, hasLength(1));
        expect(backend.operations.first, 'persist');
        expect(backend.readyReportIds, isEmpty);
      },
    );

    test('ambiguous persistence never uploads untracked photo bytes', () async {
      final backend = _FakeBackend(
        authenticatedUserId: _userId,
        persistFailuresRemaining: 1,
      );
      final service = ProductSubmissionService(backend: backend);

      final result = await service.submit(
        _draft(photos: [_photo(ProductSubmissionPhotoSlot.front)]),
      );

      expect(
        result,
        isA<ProductSubmissionFailure>().having(
          (failure) => failure.kind,
          'primary kind',
          ProductSubmissionFailureKind.reportInsertFailed,
        ),
      );
      expect(backend.operations, ['persist']);
      expect(backend.uploads, isEmpty);
    });

    test(
      'post-commit transport error never deletes persisted report photos',
      () async {
        final backend = _FakeBackend(
          authenticatedUserId: _userId,
          commitThenThrowFailuresRemaining: 1,
        );
        final service = ProductSubmissionService(backend: backend);

        final result = await service.submit(
          _draft(photos: [_photo(ProductSubmissionPhotoSlot.front)]),
        );

        expect(
          result,
          isA<ProductSubmissionFailure>().having(
            (failure) => failure.kind,
            'kind',
            ProductSubmissionFailureKind.reportInsertFailed,
          ),
        );
        expect(backend.persistedReportIds, contains(_reportId));
        expect(backend.operations.last, 'persist');
        expect(backend.uploads, isEmpty);
      },
    );

    test(
      'retry upload failure never deletes photos for an existing report',
      () async {
        final backend = _FakeBackend(
          authenticatedUserId: _userId,
          failUploadNumber: 1,
        );
        final service = ProductSubmissionService(backend: backend);

        final result = await service.submit(
          _draft(photos: [_photo(ProductSubmissionPhotoSlot.front)]),
        );

        expect(
          result,
          isA<ProductSubmissionFailure>().having(
            (failure) => failure.kind,
            'kind',
            ProductSubmissionFailureKind.photoUploadFailed,
          ),
        );
        expect(backend.operations.first, 'persist');
        expect(backend.operations.last, 'upload:$_userId/$_reportId/front');
      },
    );

    test('persistence failure stops before finalization or upload', () async {
      final backend = _FakeBackend(
        authenticatedUserId: _userId,
        persistFailuresRemaining: 1,
      );
      final service = ProductSubmissionService(backend: backend);

      final result = await service.submit(
        _draft(photos: [_photo(ProductSubmissionPhotoSlot.front)]),
      );

      expect(
        result,
        isA<ProductSubmissionFailure>().having(
          (failure) => failure.kind,
          'primary error',
          ProductSubmissionFailureKind.reportInsertFailed,
        ),
      );
      expect(backend.operations, ['persist']);
      expect(backend.uploads, isEmpty);
    });

    test('partial photo upload can never become review-ready', () async {
      final backend = _FakeBackend(
        authenticatedUserId: _userId,
        failUploadNumber: 2,
      );
      final service = ProductSubmissionService(backend: backend);

      final result = await service.submit(
        _draft(
          photos: [
            _photo(ProductSubmissionPhotoSlot.front),
            _photo(ProductSubmissionPhotoSlot.supplementFacts),
          ],
        ),
      );

      expect(
        result,
        isA<ProductSubmissionFailure>().having(
          (failure) => failure.kind,
          'kind',
          ProductSubmissionFailureKind.photoUploadFailed,
        ),
      );
      expect(backend.successfulObjectPaths, hasLength(1));
      expect(backend.readyReportIds, isEmpty);
      expect(
        backend.operations.where(
          (operation) => operation.startsWith('finalize'),
        ),
        hasLength(1),
      );
    });

    test('finalize transport failure stops before photo upload', () async {
      final backend = _FakeBackend(
        authenticatedUserId: _userId,
        finalizeFailuresRemaining: 1,
      );
      final service = ProductSubmissionService(backend: backend);

      final result = await service.submit(
        _draft(photos: [_photo(ProductSubmissionPhotoSlot.front)]),
      );

      expect(
        result,
        isA<ProductSubmissionFailure>()
            .having(
              (failure) => failure.kind,
              'kind',
              ProductSubmissionFailureKind.reportFinalizeFailed,
            )
            .having((failure) => failure.retryable, 'retryable', isTrue),
      );
      expect(backend.operations, ['persist', 'finalize:$_reportId']);
      expect(backend.uploads, isEmpty);
      expect(backend.readyReportIds, isEmpty);
    });

    test(
      'retry resolves an ambiguous finalize without uploading photos again',
      () async {
        final backend = _FakeBackend(
          authenticatedUserId: _userId,
          commitThenThrowFinalizeFailuresRemaining: 1,
        );
        final service = ProductSubmissionService(backend: backend);
        final draft = _draft(
          photos: [_photo(ProductSubmissionPhotoSlot.front)],
        );

        final first = await service.submit(draft);
        final second = await service.submit(draft);

        expect(
          first,
          isA<ProductSubmissionFailure>().having(
            (failure) => failure.kind,
            'kind',
            ProductSubmissionFailureKind.reportFinalizeFailed,
          ),
        );
        expect(second, isA<ProductSubmissionSuccess>());
        expect(backend.uploads, hasLength(1));
        expect(backend.readyReportIds, contains(_reportId));
        expect(backend.operations, [
          'persist',
          'finalize:$_reportId',
          'upload:$_userId/$_reportId/front',
          'finalize:$_reportId',
          'persist',
          'finalize:$_reportId',
        ]);
      },
    );
  });
}

LabelMismatchReportDraft _draft({
  String reportId = _reportId,
  LabelMismatchProductMetadata? metadata,
  Set<LabelMismatchCategory> categories = const {
    LabelMismatchCategory.productIdentity,
  },
  List<ProductSubmissionPhoto> photos = const [],
}) {
  return LabelMismatchReportDraft(
    reportId: reportId,
    product: metadata ?? LabelMismatchProductMetadata(dsldId: '12345'),
    categories: categories,
    photos: photos,
  );
}

ProductSubmissionPhoto _photo(
  ProductSubmissionPhotoSlot slot, {
  Uint8List? bytes,
}) {
  return ProductSubmissionPhoto(
    slot: slot,
    bytes: bytes ?? Uint8List.fromList([1, 2, 3]),
    contentType: 'image/jpeg',
  );
}

class _UploadCall {
  final String bucket;
  final String objectPath;

  const _UploadCall({required this.bucket, required this.objectPath});
}

class _FakeBackend implements ProductSubmissionBackend {
  @override
  final String? authenticatedUserId;
  int persistFailuresRemaining;
  int commitThenThrowFailuresRemaining;
  int finalizeFailuresRemaining;
  int commitThenThrowFinalizeFailuresRemaining;
  final int? failUploadNumber;
  final Set<String> persistedReportIds;
  final Set<String> readyReportIds;
  final Set<String> successfulObjectPaths = {};

  final operations = <String>[];
  final uploads = <_UploadCall>[];
  final reportRows = <Map<String, Object?>>[];
  Map<String, Object?>? reportRow;
  List<Map<String, Object?>>? photoRows;

  _FakeBackend({
    this.authenticatedUserId,
    this.persistFailuresRemaining = 0,
    this.commitThenThrowFailuresRemaining = 0,
    this.finalizeFailuresRemaining = 0,
    this.commitThenThrowFinalizeFailuresRemaining = 0,
    this.failUploadNumber,
    Set<String> persistedReportIds = const {},
    Set<String> readyReportIds = const {},
  }) : persistedReportIds = {...persistedReportIds},
       readyReportIds = {...readyReportIds};

  @override
  Future<void> uploadPhoto({
    required String bucket,
    required String objectPath,
    required Uint8List bytes,
    required String contentType,
  }) async {
    uploads.add(_UploadCall(bucket: bucket, objectPath: objectPath));
    operations.add('upload:$objectPath');
    if (failUploadNumber != null && uploads.length == failUploadNumber) {
      throw StateError('upload failed');
    }
    successfulObjectPaths.add(objectPath);
  }

  @override
  Future<void> persistSubmission({
    required String functionName,
    required Map<String, Object?> payload,
  }) async {
    expect(functionName, ProductSubmissionService.createFunction);
    reportRow = Map<String, Object?>.unmodifiable(payload);
    final manifest = payload['p_photos']! as List<Map<String, Object?>>;
    photoRows = List.unmodifiable(
      manifest.map(Map<String, Object?>.unmodifiable),
    );
    reportRows.add(Map<String, Object?>.unmodifiable(payload));
    operations.add('persist');
    final submissionId = payload['p_submission_id']! as String;
    if (commitThenThrowFailuresRemaining > 0) {
      commitThenThrowFailuresRemaining--;
      persistedReportIds.add(submissionId);
      throw StateError('response lost after commit');
    }
    if (persistFailuresRemaining > 0) {
      persistFailuresRemaining--;
      throw StateError('row insert failed');
    }
    persistedReportIds.add(submissionId);
  }

  @override
  Future<bool> finalizeSubmission({
    required String functionName,
    required String submissionId,
  }) async {
    expect(functionName, ProductSubmissionService.finalizeFunction);
    operations.add('finalize:$submissionId');
    if (finalizeFailuresRemaining > 0) {
      finalizeFailuresRemaining--;
      throw StateError('finalize failed');
    }
    if (readyReportIds.contains(submissionId)) return true;
    if (!persistedReportIds.contains(submissionId)) {
      throw StateError('report missing');
    }
    final expectedPaths = (photoRows ?? const <Map<String, Object?>>[]).map(
      (row) => '$_userId/$submissionId/${row['photo_slot']}',
    );
    if (!expectedPaths.every(successfulObjectPaths.contains)) return false;
    readyReportIds.add(submissionId);
    if (commitThenThrowFinalizeFailuresRemaining > 0) {
      commitThenThrowFinalizeFailuresRemaining--;
      throw StateError('response lost after finalize commit');
    }
    return true;
  }

  @override
  Future<List<Map<String, Object?>>> listOwnSubmissions({
    required String table,
  }) async {
    return const [];
  }
}
