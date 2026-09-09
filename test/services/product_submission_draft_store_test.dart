import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/contributions/product_submission_consent_copy.dart';
import 'package:pharmaguide/services/product_submission_draft_store.dart';
import 'package:pharmaguide/services/product_submission_service.dart';

const _submissionId = '11111111-1111-4111-8111-111111111111';
const _photoId = '22222222-2222-4222-8222-222222222222';
const _photoIdB = '33333333-3333-4333-8333-333333333333';
const _upc = '012345678905';

Uint8List _bytes(int seed) =>
    Uint8List.fromList(List<int>.generate(64, (i) => (i + seed) % 256));

ProductSubmissionPhoto _photo({String? id, int seed = 1}) =>
    ProductSubmissionPhoto(
      photoId: id ?? _photoId,
      categories: MissingProductSubmissionDraft.requiredCategories,
      bytes: _bytes(seed),
      contentType: 'image/jpeg',
    );

const _userA = '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a01';
const _userB = '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a02';

Future<void> _save(
  ProductSubmissionDraftStore store, {
  String userId = _userA,
  String submissionId = _submissionId,
  List<ProductSubmissionPhoto>? photos,
  String? resubmissionOf,
  int evidenceRevision = 1,
}) {
  return store.save(
    userId: userId,
    submissionId: submissionId,
    upc: _upc,
    photos: photos ?? [_photo()],
    consentVersion: productSubmissionConsentVersion,
    resubmissionOf: resubmissionOf,
    evidenceRevision: evidenceRevision,
  );
}

void main() {
  late Directory root;
  late ProductSubmissionDraftStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('pg-draft-store');
    store = ProductSubmissionDraftStore(root: root);
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  test('a saved capture survives a restart with identical bytes and ids', () async {
    await _save(store);

    // A new instance over the same directory is what a relaunch sees.
    final reopened = ProductSubmissionDraftStore(root: root);
    final pending = await reopened.list(_userA);

    expect(pending, hasLength(1));
    expect(pending.single.submissionId, _submissionId);
    expect(pending.single.upc, _upc);
    expect(pending.single.consentVersion, productSubmissionConsentVersion);
    final restored = await reopened.restore(_userA, _submissionId);
    expect(restored, isNotNull);
    expect(restored!.submissionId, _submissionId);
    expect(restored.photos.single.photoId, _photoId);
    expect(restored.photos.single.bytes, _bytes(1));
    expect(restored.photos.single.categories,
        MissingProductSubmissionDraft.requiredCategories);
  });

  test('restoring rebuilds the same submission so a retry is idempotent', () async {
    await _save(store);

    final first = await store.restore(_userA, _submissionId);
    final second = await store.restore(_userA, _submissionId);

    // Same identity twice: the server replay contract depends on it.
    expect(first!.submissionId, second!.submissionId);
    expect(first.photos.single.photoId, second.photos.single.photoId);
    expect(first.photos.single.contentSha256, second.photos.single.contentSha256);
  });

  test('discarding removes the label images from disk, not just the record', () async {
    await _save(store);
    final filesBefore = root
        .listSync(recursive: true)
        .whereType<File>()
        .length;
    expect(filesBefore, greaterThan(1));

    await store.discard(_userA, _submissionId);

    expect(await store.list(_userA), isEmpty);
    expect(
      root.listSync(recursive: true).whereType<File>(),
      isEmpty,
      reason: 'private label photos must not outlive the draft that owns them',
    );
  });

  test('a truncated manifest is discarded instead of crashing capture', () async {
    await _save(store);
    final manifest = root
        .listSync(recursive: true)
        .whereType<File>()
        .firstWhere((file) => file.path.endsWith('.json'));
    await manifest.writeAsString('{"submission_id": "11111111');

    expect(await store.list(_userA), isEmpty);
    expect(await store.restore(_userA, _submissionId), isNull);
  });

  test('a photo whose bytes changed on disk is not restored as evidence', () async {
    await _save(store);
    final image = root
        .listSync(recursive: true)
        .whereType<File>()
        .firstWhere((file) => !file.path.endsWith('.json'));
    await image.writeAsBytes(_bytes(9));

    expect(
      await store.restore(_userA, _submissionId),
      isNull,
      reason: 'the manifest hash is the evidence contract; altered bytes are not it',
    );
  });

  test('a pending draft never claims the server accepted it', () async {
    await _save(store);

    final pending = (await store.list(_userA)).single;

    expect(pending.acceptedByServer, isFalse);
    expect(pending.capturedAt, isNotNull);
  });

  test('the newest capture for a barcode is the one offered for resume', () async {
    await _save(store);

    final found = await store.findByUpc(_userA, ' 0-12345-678905 ');

    expect(found?.submissionId, _submissionId);
    expect(await store.findByUpc(_userA, '036000291452'), isNull);
  });

  test('drafts are kept under app-private support storage', () async {
    // The OS reclaims the temporary directory between launches, which is
    // exactly the case this store exists to survive.
    final located = await ProductSubmissionDraftStore.resolveRoot(
      () async => Directory('/private-support'),
    );

    expect(located.path, startsWith('/private-support'));
    expect(located.path, endsWith('product_submission_drafts'));
    final source = File('lib/services/product_submission_draft_store.dart')
        .readAsStringSync();
    expect(source, contains('getApplicationSupportDirectory'));
    expect(source, isNot(contains('getTemporaryDirectory')));
    expect(source, isNot(contains('systemTemp')));
  });

  test('a saved draft records the evidence revision it belongs to', () async {
    await _save(store, evidenceRevision: 2);

    expect((await store.list(_userA)).single.evidenceRevision, 2);
  });

  test('saving twice replaces the capture rather than duplicating it', () async {
    await _save(store);
    await _save(store, photos: [_photo(seed: 5)]);

    final pending = await store.list(_userA);
    expect(pending, hasLength(1));
    final restored = await store.restore(_userA, _submissionId);
    expect(restored!.photos.single.bytes, _bytes(5));
    expect(
      root.listSync(recursive: true).whereType<File>().length,
      2,
      reason: 'the superseded image must not linger on disk',
    );
  });

  test('an unreadable draft directory reports empty instead of throwing', () async {
    final missing = ProductSubmissionDraftStore(
      root: Directory('${root.path}/never-created'),
    );

    expect(await missing.list(_userA), isEmpty);
    expect(await missing.restore(_userA, _submissionId), isNull);
    expect(() => missing.discard(_userA, _submissionId), returnsNormally);
  });

  group('accounts are isolated', () {
    test('another account cannot see, resume or discard these photos', () async {
      await _save(store);

      // Everything a second account could reach for.
      expect(await store.list(_userB), isEmpty);
      expect(await store.findByUpc(_userB, _upc), isNull);
      expect(await store.restore(_userB, _submissionId), isNull);

      // And a second account's cleanup must not destroy the first's evidence.
      await store.discard(_userB, _submissionId);
      expect(await store.list(_userA), hasLength(1));
      expect(await store.restore(_userA, _submissionId), isNotNull);
    });

    test('two accounts keep separate captures for the same barcode', () async {
      await _save(store, photos: [_photo(seed: 1)]);
      await _save(
        store,
        userId: _userB,
        submissionId: '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a03',
        photos: [_photo(id: '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a04', seed: 5)],
      );

      final a = await store.restore(_userA, _submissionId);
      final b = await store.findByUpc(_userB, _upc);

      expect(a!.photos.single.bytes, _bytes(1));
      expect(b!.submissionId, '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a03');
      expect((await store.list(_userA)), hasLength(1));
    });

    test('a capture cannot be stored without an account', () async {
      expect(
        () => _save(store, userId: ''),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => _save(store, userId: '../../escape'),
        throwsA(isA<ArgumentError>()),
        reason: 'an unexpected id must not escape the drafts directory',
      );
    });
  });

  group('recovery survives interruption', () {
    test('a retry reuses the same submission identity', () async {
      await _save(store);

      final first = await store.restore(_userA, _submissionId);
      await _save(store, photos: [_photo(seed: 2)]);
      final second = await store.restore(_userA, _submissionId);

      expect(first!.submissionId, _submissionId);
      expect(second!.submissionId, _submissionId);
      expect((await store.list(_userA)), hasLength(1));
    });

    test('resubmission lineage survives a restart', () async {
      const lineage = '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a77';
      await _save(store, resubmissionOf: lineage);

      final reopened = ProductSubmissionDraftStore(root: root);

      expect((await reopened.list(_userA)).single.resubmissionOf, lineage);
      expect(
        (await reopened.restore(_userA, _submissionId))!.resubmissionOf,
        lineage,
      );
    });

    test('a write interrupted before the manifest leaves nothing to resume',
        () async {
      await _save(store);
      final manifest = root
          .listSync(recursive: true)
          .whereType<File>()
          .firstWhere((file) => file.path.endsWith('.json'));
      await manifest.delete();

      // Photos with no manifest are bytes without provenance, not evidence.
      expect(await store.list(_userA), isEmpty);
      expect(await store.restore(_userA, _submissionId), isNull);
    });

    test('a photo missing from disk fails the whole capture, not silently',
        () async {
      await _save(store, photos: [_photo(seed: 1), _photo(id: _photoIdB, seed: 2)]);
      final image = root
          .listSync(recursive: true)
          .whereType<File>()
          .firstWhere((file) => file.path.endsWith(_photoIdB));
      await image.delete();

      expect(
        await store.restore(_userA, _submissionId),
        isNull,
        reason: 'a partial photo set would submit as if it were complete',
      );
    });

    test('concurrent saves of the same capture leave one consistent record',
        () async {
      await Future.wait([
        _save(store, photos: [_photo(seed: 3)]),
        _save(store, photos: [_photo(seed: 3)]),
      ]);

      expect(await store.list(_userA), hasLength(1));
      final restored = await store.restore(_userA, _submissionId);
      expect(restored!.photos.single.bytes, _bytes(3));
    });

    test('discarding twice is not an error', () async {
      await _save(store);
      await store.discard(_userA, _submissionId);
      await store.discard(_userA, _submissionId);

      expect(await store.list(_userA), isEmpty);
    });
  });
}
