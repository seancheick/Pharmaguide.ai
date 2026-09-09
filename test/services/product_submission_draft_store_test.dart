import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/contributions/product_submission_consent_copy.dart';
import 'package:pharmaguide/services/product_submission_draft_store.dart';
import 'package:pharmaguide/services/product_submission_service.dart';

const _submissionId = '11111111-1111-4111-8111-111111111111';
const _photoId = '22222222-2222-4222-8222-222222222222';
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

MissingProductSubmissionDraft _draft({List<ProductSubmissionPhoto>? photos}) =>
    MissingProductSubmissionDraft(
      submissionId: _submissionId,
      upc: _upc,
      photos: photos ?? [_photo()],
    );

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
    await store.save(_draft(), consentVersion: productSubmissionConsentVersion);

    // A new instance over the same directory is what a relaunch sees.
    final reopened = ProductSubmissionDraftStore(root: root);
    final pending = await reopened.list();

    expect(pending, hasLength(1));
    expect(pending.single.submissionId, _submissionId);
    expect(pending.single.upc, _upc);
    expect(pending.single.consentVersion, productSubmissionConsentVersion);
    final restored = await reopened.restore(_submissionId);
    expect(restored, isNotNull);
    expect(restored!.submissionId, _submissionId);
    expect(restored.photos.single.photoId, _photoId);
    expect(restored.photos.single.bytes, _bytes(1));
    expect(restored.photos.single.categories,
        MissingProductSubmissionDraft.requiredCategories);
  });

  test('restoring rebuilds the same submission so a retry is idempotent', () async {
    await store.save(_draft(), consentVersion: productSubmissionConsentVersion);

    final first = await store.restore(_submissionId);
    final second = await store.restore(_submissionId);

    // Same identity twice: the server replay contract depends on it.
    expect(first!.submissionId, second!.submissionId);
    expect(first.photos.single.photoId, second.photos.single.photoId);
    expect(first.photos.single.contentSha256, second.photos.single.contentSha256);
  });

  test('discarding removes the label images from disk, not just the record', () async {
    await store.save(_draft(), consentVersion: productSubmissionConsentVersion);
    final filesBefore = root
        .listSync(recursive: true)
        .whereType<File>()
        .length;
    expect(filesBefore, greaterThan(1));

    await store.discard(_submissionId);

    expect(await store.list(), isEmpty);
    expect(
      root.listSync(recursive: true).whereType<File>(),
      isEmpty,
      reason: 'private label photos must not outlive the draft that owns them',
    );
  });

  test('a truncated manifest is discarded instead of crashing capture', () async {
    await store.save(_draft(), consentVersion: productSubmissionConsentVersion);
    final manifest = root
        .listSync(recursive: true)
        .whereType<File>()
        .firstWhere((file) => file.path.endsWith('.json'));
    await manifest.writeAsString('{"submission_id": "11111111');

    expect(await store.list(), isEmpty);
    expect(await store.restore(_submissionId), isNull);
  });

  test('a photo whose bytes changed on disk is not restored as evidence', () async {
    await store.save(_draft(), consentVersion: productSubmissionConsentVersion);
    final image = root
        .listSync(recursive: true)
        .whereType<File>()
        .firstWhere((file) => !file.path.endsWith('.json'));
    await image.writeAsBytes(_bytes(9));

    expect(
      await store.restore(_submissionId),
      isNull,
      reason: 'the manifest hash is the evidence contract; altered bytes are not it',
    );
  });

  test('a pending draft never claims the server accepted it', () async {
    await store.save(_draft(), consentVersion: productSubmissionConsentVersion);

    final pending = (await store.list()).single;

    expect(pending.acceptedByServer, isFalse);
    expect(pending.capturedAt, isNotNull);
  });

  test('the newest capture for a barcode is the one offered for resume', () async {
    await store.save(_draft(), consentVersion: productSubmissionConsentVersion);

    final found = await store.findByUpc(' 0-12345-678905 ');

    expect(found?.submissionId, _submissionId);
    expect(await store.findByUpc('036000291452'), isNull);
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
    await store.save(
      _draft(),
      consentVersion: productSubmissionConsentVersion,
      evidenceRevision: 2,
    );

    expect((await store.list()).single.evidenceRevision, 2);
  });

  test('saving twice replaces the capture rather than duplicating it', () async {
    await store.save(_draft(), consentVersion: productSubmissionConsentVersion);
    await store.save(
      _draft(photos: [_photo(seed: 5)]),
      consentVersion: productSubmissionConsentVersion,
    );

    final pending = await store.list();
    expect(pending, hasLength(1));
    final restored = await store.restore(_submissionId);
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

    expect(await missing.list(), isEmpty);
    expect(await missing.restore(_submissionId), isNull);
    expect(() => missing.discard(_submissionId), returnsNormally);
  });
}
