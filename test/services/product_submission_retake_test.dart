import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/contributions/product_submission_consent_copy.dart';
import 'package:pharmaguide/services/product_submission_service.dart';

const _submissionId = '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a11';
const _userId = '3f276b64-0836-4bea-9453-1c8db4d1f8dd';
const _front = '10000000-0000-4000-8000-000000000001';
const _facts = '10000000-0000-4000-8000-000000000002';
const _barcode = '10000000-0000-4000-8000-000000000003';
const _newFacts = '10000000-0000-4000-8000-000000000004';

void main() {
  group('summary', () {
    Map<String, Object?> row({
      String status = 'under_review',
      String upload = 'ready',
      int revision = 1,
      int? requested = 1,
      List<String>? panels = const ['supplement_facts'],
    }) => {
      'id': _submissionId,
      'kind': 'missing_product',
      'normalized_upc': '050428381397',
      'upload_state': upload,
      'review_status': status,
      'evidence_revision': revision,
      'evidence_requested_revision': requested,
      'evidence_request_reason': 'photo_quality',
      'evidence_request_panels': panels,
    };

    test('a request is open only while it names the current revision', () {
      final open = ProductSubmissionSummary.fromRow(row());
      expect(open.needsNewPhotos, isTrue);
      expect(open.evidenceRequestPanels, {
        ProductSubmissionEvidenceCategory.supplementFacts,
      });
      expect(
        open.evidenceRequestReason,
        ProductSubmissionResolutionCode.photoQuality,
      );
      for (final answered in [
        row(revision: 2, requested: 1),
        row(requested: null),
        row(panels: const []),
        row(status: 'rejected'),
        row(status: 'approved'),
        row(upload: 'pending', revision: 2),
      ]) {
        expect(ProductSubmissionSummary.fromRow(answered).needsNewPhotos, isFalse);
      }
      expect(
        ProductSubmissionSummary.fromRow(
          row(upload: 'pending', revision: 2),
        ).retakeUnfinished,
        isTrue,
      );
    });
  });

  group('plan', () {
    test('keeps every photo the reviewer did not ask about', () {
      final plan = _plan({ProductSubmissionEvidenceCategory.supplementFacts});
      expect(plan.keptPhotoIds, [_front, _barcode]);
      expect(plan.keptCategories, {
        ProductSubmissionEvidenceCategory.frontIdentity,
        ProductSubmissionEvidenceCategory.barcode,
      });
      // The facts photo also held the ingredient list, so both come back.
      expect(plan.coversRequired([]), isFalse);
      expect(plan.coversRequired([_newFactsPhoto()]), isTrue);
    });

    test('always leaves room for a new photo', () {
      final plan = ProductSubmissionRetake.plan(
        submissionId: _submissionId,
        upc: '050428381397',
        fromRevision: 1,
        requestedPanels: {ProductSubmissionEvidenceCategory.lotExpiry},
        membership: [
          for (var i = 0; i < 8; i++)
            (
              photoId: '10000000-0000-4000-8000-00000000001$i',
              categories: {ProductSubmissionEvidenceCategory.frontIdentity},
            ),
        ],
      );
      expect(plan.keptPhotoIds, hasLength(7));
      expect(plan.newPhotoCapacity, 1);
    });
  });

  test('prepareRetake plans from the current revision the owner can read', () async {
    final backend = _RetakeBackend();
    final plan = await ProductSubmissionService(backend: backend).prepareRetake(
      ProductSubmissionSummary.fromRow({
        'id': _submissionId,
        'kind': 'missing_product',
        'normalized_upc': '050428381397',
        'upload_state': 'ready',
        'review_status': 'under_review',
        'evidence_revision': 1,
        'evidence_requested_revision': 1,
        'evidence_request_panels': ['supplement_facts'],
      }),
    );
    expect(plan.fromRevision, 1);
    expect(plan.keptPhotoIds, [_front, _barcode]);
    expect(plan.earlierPhotoDigests, hasLength(3));
  });

  group('submitRetake', () {
    test('opens, records, uploads and finalizes the next revision', () async {
      final backend = _RetakeBackend();
      final service = ProductSubmissionService(backend: backend);
      final plan = _plan({ProductSubmissionEvidenceCategory.supplementFacts});

      final result = await service.submitRetake(plan, [_newFactsPhoto()]);

      expect(result, isA<ProductSubmissionSuccess>());
      expect(backend.operations, [
        'open',
        'finalize:2',
        'add:2',
        'upload:$_userId/$_submissionId/$_newFacts',
        'finalize:2',
      ]);
      expect(backend.openPayloads.single['p_expected_revision'], 1);
      expect(backend.openPayloads.single['p_keep_photo_ids'], [_front, _barcode]);
      expect(
        backend.openPayloads.single['p_consent_version'],
        productSubmissionConsentVersion,
      );
      expect(backend.revisions[2], [_front, _barcode, _newFacts]);
      expect(backend.ready, isTrue);

      // A retry after a lost response replays the same revision and stops.
      backend.operations.clear();
      final again = await service.submitRetake(plan, [_newFactsPhoto()]);
      expect(again, isA<ProductSubmissionSuccess>());
      expect(backend.operations, ['open', 'finalize:2']);
      expect(
        backend.openPayloads.last['p_request_key'],
        backend.openPayloads.first['p_request_key'],
      );
      expect(backend.revisions.keys, [1, 2]);
    });

    test('an interrupted upload resumes with the same photos', () async {
      final backend = _RetakeBackend()..failUploads = 1;
      final service = ProductSubmissionService(backend: backend);
      final plan = _plan({ProductSubmissionEvidenceCategory.supplementFacts});

      final first = await service.submitRetake(plan, [_newFactsPhoto()]);
      expect(first, isA<ProductSubmissionFailure>());
      expect(
        (first as ProductSubmissionFailure).kind,
        ProductSubmissionFailureKind.photoUploadFailed,
      );
      expect(backend.ready, isFalse);

      final second = await service.submitRetake(plan, [_newFactsPhoto()]);
      expect(second, isA<ProductSubmissionSuccess>());
      expect(backend.revisions.keys, [1, 2]);
      expect(backend.ready, isTrue);
    });

    test('refuses repeated bytes or a gap before touching the network', () async {
      final backend = _RetakeBackend();
      final service = ProductSubmissionService(backend: backend);
      final plan = ProductSubmissionRetake.plan(
        submissionId: _submissionId,
        upc: '050428381397',
        fromRevision: 1,
        requestedPanels: {ProductSubmissionEvidenceCategory.supplementFacts},
        membership: _membership,
        earlierPhotoDigests: {_newFactsPhoto().contentSha256},
      );
      final repeated = await service.submitRetake(plan, [_newFactsPhoto()]);
      expect(repeated, isA<ProductSubmissionFailure>());

      final gap = await service.submitRetake(
        _plan({ProductSubmissionEvidenceCategory.supplementFacts}),
        [
          ProductSubmissionPhoto(
            photoId: _newFacts,
            categories: {ProductSubmissionEvidenceCategory.supplementFacts},
            bytes: Uint8List.fromList([9, 9, 9]),
            contentType: 'image/jpeg',
          ),
        ],
      );
      expect(gap, isA<ProductSubmissionFailure>());
      expect(backend.operations, isEmpty);
    });
  });
}

final _membership = [
  (photoId: _front, categories: {ProductSubmissionEvidenceCategory.frontIdentity}),
  (
    photoId: _facts,
    categories: {
      ProductSubmissionEvidenceCategory.supplementFacts,
      ProductSubmissionEvidenceCategory.ingredientDisclosure,
    },
  ),
  (photoId: _barcode, categories: {ProductSubmissionEvidenceCategory.barcode}),
];

ProductSubmissionRetake _plan(Set<ProductSubmissionEvidenceCategory> panels) =>
    ProductSubmissionRetake.plan(
      submissionId: _submissionId,
      upc: '050428381397',
      fromRevision: 1,
      requestedPanels: panels,
      membership: _membership,
    );

ProductSubmissionPhoto _newFactsPhoto() => ProductSubmissionPhoto(
  photoId: _newFacts,
  categories: {
    ProductSubmissionEvidenceCategory.supplementFacts,
    ProductSubmissionEvidenceCategory.ingredientDisclosure,
  },
  bytes: Uint8List.fromList([4, 4, 4, 4]),
  contentType: 'image/jpeg',
);

/// Just enough of the server's revision rules: open replays by request key,
/// finalize needs a new photo and every member's bytes, add is idempotent.
class _RetakeBackend implements ProductSubmissionBackend {
  @override
  String? authenticatedUserId = _userId;

  final operations = <String>[];
  final openPayloads = <Map<String, Object?>>[];
  final revisions = <int, List<String>>{
    1: [_front, _facts, _barcode],
  };
  final newInRevision = <int, List<String>>{};
  final keys = <String, int>{};
  final uploaded = <String>{
    for (final id in [_front, _facts, _barcode]) '$_userId/$_submissionId/$id',
  };
  int current = 1;
  bool ready = true;
  int failUploads = 0;

  @override
  Future<Map<String, Object?>> fetchOwnEvidence({
    required String submissionId,
  }) async => {
    'revisions': [
      for (final entry in revisions.entries)
        {'revision': entry.key, 'photo_ids': entry.value},
    ],
    'photos': [
      {'photo_id': _front, 'categories': ['front_identity'], 'content_sha256': 'a' * 64},
      {
        'photo_id': _facts,
        'categories': ['supplement_facts', 'ingredient_disclosure'],
        'content_sha256': 'b' * 64,
      },
      {'photo_id': _barcode, 'categories': ['barcode'], 'content_sha256': 'c' * 64},
    ],
  };

  @override
  Future<int> openEvidenceRevision({
    required Map<String, Object?> payload,
  }) async {
    operations.add('open');
    openPayloads.add(payload);
    final key = payload['p_request_key']! as String;
    final replay = keys[key];
    if (replay != null) return replay;
    expect(payload['p_expected_revision'], current);
    current = revisions.keys.last + 1;
    revisions[current] = List.of((payload['p_keep_photo_ids']! as List).cast());
    keys[key] = current;
    ready = false;
    return current;
  }

  @override
  Future<bool> finalizeSubmission({
    required String functionName,
    required String submissionId,
    int? expectedRevision,
  }) async {
    operations.add('finalize:$expectedRevision');
    expect(expectedRevision, current);
    if (ready) return true;
    if ((newInRevision[current] ?? const []).isEmpty) return false;
    if (!revisions[current]!.every(
      (id) => uploaded.contains('$_userId/$submissionId/$id'),
    )) {
      return false;
    }
    ready = true;
    return true;
  }

  @override
  Future<void> persistSubmission({
    required String functionName,
    required Map<String, Object?> payload,
  }) async {
    expect(functionName, ProductSubmissionService.addEvidenceFunction);
    final revision = payload['p_expected_revision']! as int;
    operations.add('add:$revision');
    final ids = [
      for (final photo in payload['p_photos']! as List)
        (photo as Map)['photo_id'] as String,
    ];
    final existing = newInRevision[revision];
    if (existing != null) {
      expect(existing, ids, reason: 'a different manifest would conflict');
      return;
    }
    newInRevision[revision] = ids;
    revisions[revision] = [...revisions[revision]!, ...ids];
  }

  @override
  Future<void> uploadPhoto({
    required String bucket,
    required String objectPath,
    required Uint8List bytes,
    required String contentType,
  }) async {
    operations.add('upload:$objectPath');
    if (failUploads > 0) {
      failUploads--;
      throw StateError('network');
    }
    uploaded.add(objectPath);
  }

  @override
  Future<Map<String, Object?>> fetchIntake({
    required String functionName,
    required Map<String, Object?> payload,
  }) => throw UnimplementedError();

  @override
  Future<List<Map<String, Object?>>> listOwnSubmissions({
    required String table,
    required int offset,
    required int limit,
  }) => throw UnimplementedError();
}
