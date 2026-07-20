import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/services/label_mismatch_report_service.dart';

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
        LabelMismatchPhotoSlot.values.map((slot) => slot.wireValue),
        const ['front', 'supplement_facts', 'other_ingredients'],
      );
      expect(LabelMismatchPhoto.maxByteSize, 15728640);
      expect(LabelMismatchPhoto.allowedContentTypes, const {
        'image/jpeg',
        'image/png',
        'image/heic',
        'image/heif',
        'image/webp',
      });
    });

    test('photo bytes remain immutable across retries', () {
      final source = Uint8List.fromList([1, 2, 3]);
      final photo = LabelMismatchPhoto(
        slot: LabelMismatchPhotoSlot.front,
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
            _photo(LabelMismatchPhotoSlot.front),
            _photo(LabelMismatchPhotoSlot.supplementFacts),
            _photo(LabelMismatchPhotoSlot.otherIngredients),
            _photo(LabelMismatchPhotoSlot.front),
          ],
        ),
        throwsA(
          isA<LabelMismatchValidationException>().having(
            (error) => error.reason,
            'reason',
            LabelMismatchValidationFailure.tooManyPhotos,
          ),
        ),
      );
    });

    test('rejects duplicate named photo slots', () {
      expect(
        () => _draft(
          photos: [
            _photo(LabelMismatchPhotoSlot.front),
            _photo(LabelMismatchPhotoSlot.front),
          ],
        ),
        throwsA(
          isA<LabelMismatchValidationException>().having(
            (error) => error.reason,
            'reason',
            LabelMismatchValidationFailure.duplicatePhotoSlot,
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
            isA<LabelMismatchValidationException>().having(
              (error) => error.reason,
              'reason',
              LabelMismatchValidationFailure.noCategories,
            ),
          ),
        );
        expect(
          () => _photo(LabelMismatchPhotoSlot.front, bytes: Uint8List(0)),
          throwsA(
            isA<LabelMismatchValidationException>().having(
              (error) => error.reason,
              'reason',
              LabelMismatchValidationFailure.emptyPhoto,
            ),
          ),
        );
        expect(
          () => LabelMismatchPhoto(
            slot: LabelMismatchPhotoSlot.front,
            bytes: Uint8List.fromList([1]),
            contentType: 'image/svg+xml',
          ),
          throwsA(
            isA<LabelMismatchValidationException>().having(
              (error) => error.reason,
              'reason',
              LabelMismatchValidationFailure.unsupportedPhotoContentType,
            ),
          ),
        );
        expect(
          () => _photo(
            LabelMismatchPhotoSlot.front,
            bytes: Uint8List(LabelMismatchPhoto.maxByteSize + 1),
          ),
          throwsA(
            isA<LabelMismatchValidationException>().having(
              (error) => error.reason,
              'reason',
              LabelMismatchValidationFailure.photoTooLarge,
            ),
          ),
        );
        expect(
          () => LabelMismatchProductMetadata(dsldId: '  '),
          throwsA(
            isA<LabelMismatchValidationException>().having(
              (error) => error.reason,
              'reason',
              LabelMismatchValidationFailure.missingDsldId,
            ),
          ),
        );
        expect(
          () => _draft(reportId: '../different-owner/report'),
          throwsA(
            isA<LabelMismatchValidationException>().having(
              (error) => error.reason,
              'reason',
              LabelMismatchValidationFailure.invalidReportId,
            ),
          ),
        );
        expect(
          () => _draft(reportId: '018f4c79-7c7e-7c70-9d62-7fc3b9ce6a11'),
          throwsA(
            isA<LabelMismatchValidationException>().having(
              (error) => error.reason,
              'reason',
              LabelMismatchValidationFailure.invalidReportId,
            ),
          ),
        );
        expect(
          () => LabelMismatchProductMetadata(
            dsldId: '12345',
            formulaFingerprint: 'sha256:abc123',
          ),
          throwsA(
            isA<LabelMismatchValidationException>().having(
              (error) => error.reason,
              'reason',
              LabelMismatchValidationFailure.invalidFormulaFingerprint,
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
              isA<LabelMismatchValidationException>().having(
                (error) => error.reason,
                'reason for $key',
                LabelMismatchValidationFailure.unexpectedMetadata,
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
        final service = LabelMismatchReportService(backend: backend);

        final result = await service.submit(_draft());

        expect(
          result,
          isA<LabelMismatchSubmissionFailure>()
              .having(
                (failure) => failure.kind,
                'kind',
                LabelMismatchFailureKind.authenticationRequired,
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
        final service = LabelMismatchReportService(backend: backend);
        final phases = <LabelMismatchSubmissionPhase>[];

        final result = await service.submit(
          _draft(
            photos: [
              _photo(LabelMismatchPhotoSlot.front),
              _photo(LabelMismatchPhotoSlot.supplementFacts),
            ],
          ),
          onPhaseChanged: phases.add,
        );

        expect(
          result,
          isA<LabelMismatchSubmissionSuccess>(),
          reason:
              'operations: ${backend.operations}; '
              'cause: ${result is LabelMismatchSubmissionFailure ? result.cause : null}',
        );
        expect(backend.operations, [
          'persist',
          'finalize:$_reportId',
          'upload:$_userId/$_reportId/front',
          'upload:$_userId/$_reportId/supplement_facts',
          'finalize:$_reportId',
        ]);
        expect(phases, [
          LabelMismatchSubmissionPhase.savingReport,
          LabelMismatchSubmissionPhase.uploadingPhotos,
          LabelMismatchSubmissionPhase.savingReport,
          LabelMismatchSubmissionPhase.succeeded,
        ]);
        expect(backend.uploads.map((upload) => upload.bucket).toSet(), {
          LabelMismatchReportService.photoBucket,
        });
      },
    );

    test(
      'writes only product/source/version/fingerprint report metadata',
      () async {
        final backend = _FakeBackend(authenticatedUserId: _userId);
        final service = LabelMismatchReportService(backend: backend);

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
            photos: [_photo(LabelMismatchPhotoSlot.otherIngredients)],
          ),
        );

        expect(backend.reportsTable, LabelMismatchReportService.reportsTable);
        expect(backend.photosTable, LabelMismatchReportService.photosTable);
        expect(backend.reportRow, {
          'id': _reportId,
          'user_id': _userId,
          'dsld_id': '12345',
          'upc': '031604010206',
          'source_record_id': 'DSLD-12345',
          'catalog_source_version': '2026-07-19',
          'formula_fingerprint':
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          'mismatch_categories': ['amount_or_unit', 'form_or_parenthetical'],
        });
        expect(backend.photoRows, [
          {
            'report_id': _reportId,
            'user_id': _userId,
            'photo_slot': 'other_ingredients',
            'object_path': '$_userId/$_reportId/other_ingredients',
            'content_type': 'image/jpeg',
            'byte_size': 3,
          },
        ]);
      },
    );

    test(
      'omits absent nullable metadata instead of inventing values',
      () async {
        final backend = _FakeBackend(authenticatedUserId: _userId);
        final service = LabelMismatchReportService(backend: backend);

        await service.submit(_draft());

        expect(backend.reportRow, {
          'id': _reportId,
          'user_id': _userId,
          'dsld_id': '12345',
          'mismatch_categories': ['product_identity'],
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
        final service = LabelMismatchReportService(backend: backend);
        final draft = _draft(
          photos: [_photo(LabelMismatchPhotoSlot.supplementFacts)],
        );

        final first = await service.submit(draft);
        final second = await service.submit(draft);

        expect(
          first,
          isA<LabelMismatchSubmissionFailure>()
              .having(
                (failure) => failure.kind,
                'kind',
                LabelMismatchFailureKind.reportInsertFailed,
              )
              .having((failure) => failure.retryable, 'retryable', isTrue),
        );
        expect(
          second,
          isA<LabelMismatchSubmissionSuccess>(),
          reason:
              'operations: ${backend.operations}; '
              'cause: ${second is LabelMismatchSubmissionFailure ? second.cause : null}',
        );
        expect(backend.uploads.map((upload) => upload.objectPath), const [
          '$_userId/$_reportId/supplement_facts',
        ]);
        expect(backend.reportRows.map((row) => row['id']), [
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
      final service = LabelMismatchReportService(backend: backend);

      final result = await service.submit(
        _draft(
          photos: [
            _photo(LabelMismatchPhotoSlot.front),
            _photo(LabelMismatchPhotoSlot.otherIngredients),
          ],
        ),
      );

      expect(
        result,
        isA<LabelMismatchSubmissionFailure>().having(
          (failure) => failure.kind,
          'kind',
          LabelMismatchFailureKind.reportInsertFailed,
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
        final service = LabelMismatchReportService(backend: backend);

        final result = await service.submit(
          _draft(
            photos: [
              _photo(LabelMismatchPhotoSlot.front),
              _photo(LabelMismatchPhotoSlot.supplementFacts),
            ],
          ),
        );

        expect(
          result,
          isA<LabelMismatchSubmissionFailure>()
              .having(
                (failure) => failure.kind,
                'kind',
                LabelMismatchFailureKind.photoUploadFailed,
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
      final service = LabelMismatchReportService(backend: backend);

      final result = await service.submit(
        _draft(photos: [_photo(LabelMismatchPhotoSlot.front)]),
      );

      expect(
        result,
        isA<LabelMismatchSubmissionFailure>().having(
          (failure) => failure.kind,
          'primary kind',
          LabelMismatchFailureKind.reportInsertFailed,
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
        final service = LabelMismatchReportService(backend: backend);

        final result = await service.submit(
          _draft(photos: [_photo(LabelMismatchPhotoSlot.front)]),
        );

        expect(
          result,
          isA<LabelMismatchSubmissionFailure>().having(
            (failure) => failure.kind,
            'kind',
            LabelMismatchFailureKind.reportInsertFailed,
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
        final service = LabelMismatchReportService(backend: backend);

        final result = await service.submit(
          _draft(photos: [_photo(LabelMismatchPhotoSlot.front)]),
        );

        expect(
          result,
          isA<LabelMismatchSubmissionFailure>().having(
            (failure) => failure.kind,
            'kind',
            LabelMismatchFailureKind.photoUploadFailed,
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
      final service = LabelMismatchReportService(backend: backend);

      final result = await service.submit(
        _draft(photos: [_photo(LabelMismatchPhotoSlot.front)]),
      );

      expect(
        result,
        isA<LabelMismatchSubmissionFailure>().having(
          (failure) => failure.kind,
          'primary error',
          LabelMismatchFailureKind.reportInsertFailed,
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
      final service = LabelMismatchReportService(backend: backend);

      final result = await service.submit(
        _draft(
          photos: [
            _photo(LabelMismatchPhotoSlot.front),
            _photo(LabelMismatchPhotoSlot.supplementFacts),
          ],
        ),
      );

      expect(
        result,
        isA<LabelMismatchSubmissionFailure>().having(
          (failure) => failure.kind,
          'kind',
          LabelMismatchFailureKind.photoUploadFailed,
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
      final service = LabelMismatchReportService(backend: backend);

      final result = await service.submit(
        _draft(photos: [_photo(LabelMismatchPhotoSlot.front)]),
      );

      expect(
        result,
        isA<LabelMismatchSubmissionFailure>()
            .having(
              (failure) => failure.kind,
              'kind',
              LabelMismatchFailureKind.reportFinalizeFailed,
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
        final service = LabelMismatchReportService(backend: backend);
        final draft = _draft(photos: [_photo(LabelMismatchPhotoSlot.front)]);

        final first = await service.submit(draft);
        final second = await service.submit(draft);

        expect(
          first,
          isA<LabelMismatchSubmissionFailure>().having(
            (failure) => failure.kind,
            'kind',
            LabelMismatchFailureKind.reportFinalizeFailed,
          ),
        );
        expect(second, isA<LabelMismatchSubmissionSuccess>());
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
  List<LabelMismatchPhoto> photos = const [],
}) {
  return LabelMismatchReportDraft(
    reportId: reportId,
    product: metadata ?? LabelMismatchProductMetadata(dsldId: '12345'),
    categories: categories,
    photos: photos,
  );
}

LabelMismatchPhoto _photo(LabelMismatchPhotoSlot slot, {Uint8List? bytes}) {
  return LabelMismatchPhoto(
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

class _FakeBackend implements LabelMismatchReportBackend {
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
  String? reportsTable;
  String? photosTable;
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
  Future<void> persistReport({
    required String reportsTable,
    required Map<String, Object?> reportRow,
    required String photosTable,
    required List<Map<String, Object?>> photoRows,
  }) async {
    this.reportsTable = reportsTable;
    this.photosTable = photosTable;
    this.reportRow = Map<String, Object?>.unmodifiable(reportRow);
    this.photoRows = List.unmodifiable(
      photoRows.map(Map<String, Object?>.unmodifiable),
    );
    reportRows.add(Map<String, Object?>.unmodifiable(reportRow));
    operations.add('persist');
    if (commitThenThrowFailuresRemaining > 0) {
      commitThenThrowFailuresRemaining--;
      persistedReportIds.add(reportRow['id']! as String);
      throw StateError('response lost after commit');
    }
    if (persistFailuresRemaining > 0) {
      persistFailuresRemaining--;
      throw StateError('row insert failed');
    }
    persistedReportIds.add(reportRow['id']! as String);
  }

  @override
  Future<bool> finalizeReport({
    required String functionName,
    required String reportId,
  }) async {
    expect(functionName, LabelMismatchReportService.finalizeFunction);
    operations.add('finalize:$reportId');
    if (finalizeFailuresRemaining > 0) {
      finalizeFailuresRemaining--;
      throw StateError('finalize failed');
    }
    if (readyReportIds.contains(reportId)) return true;
    if (!persistedReportIds.contains(reportId)) {
      throw StateError('report missing');
    }
    final expectedPaths = (photoRows ?? const <Map<String, Object?>>[]).map(
      (row) => row['object_path']! as String,
    );
    if (!expectedPaths.every(successfulObjectPaths.contains)) return false;
    readyReportIds.add(reportId);
    if (commitThenThrowFinalizeFailuresRemaining > 0) {
      commitThenThrowFinalizeFailuresRemaining--;
      throw StateError('response lost after finalize commit');
    }
    return true;
  }
}
