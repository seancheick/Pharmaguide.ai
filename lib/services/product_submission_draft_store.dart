import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:pharmaguide/services/gtin.dart';
import 'package:pharmaguide/services/product_submission_service.dart';

/// One unfinished capture, kept on this device.
///
/// A submission is worth several minutes of a user's time: they walk to the
/// cupboard, find the bottle, and take four photos. Losing that to a crash, to
/// the OS killing the app behind the camera activity, or to being offline in a
/// shop aisle is the difference between a contribution and an abandoned one.
/// So sanitized bytes are written to app-private storage the moment they are
/// captured, and the submission can always be finished later.
///
/// This is local state only. Nothing here means the server accepted anything;
/// [acceptedByServer] exists so no caller can imply otherwise.
class PendingProductSubmission {
  final String submissionId;
  final String upc;
  final String? resubmissionOf;
  final bool noSeparateIngredientPanel;
  final String consentVersion;
  final int evidenceRevision;
  final int photoCount;
  final DateTime capturedAt;

  const PendingProductSubmission({
    required this.submissionId,
    required this.upc,
    required this.resubmissionOf,
    required this.noSeparateIngredientPanel,
    required this.consentVersion,
    required this.evidenceRevision,
    required this.photoCount,
    required this.capturedAt,
  });

  /// Always false. A draft lives here precisely because the round trip has not
  /// completed; the server's own receipt is the only acceptance.
  bool get acceptedByServer => false;
}

/// What the capture flow needs from durable storage.
///
/// The sheet depends on this rather than on the file-backed implementation so
/// a widget test can supply an in-memory one. Real file I/O inside a widget
/// test never advances under `pumpAndSettle`, which turns a UI assertion into
/// a multi-minute hang; the interface keeps the UI honest and the tests fast.
abstract class ProductSubmissionDraftStorage {
  Future<void> save(
    ProductSubmissionDraft draft, {
    required String consentVersion,
    int evidenceRevision,
  });

  Future<List<PendingProductSubmission>> list();

  Future<PendingProductSubmission?> findByUpc(String upc);

  Future<MissingProductSubmissionDraft?> restore(String submissionId);

  Future<void> discard(String submissionId);
}

/// Durable storage for captures that have not completed the submit sequence.
///
/// Layout is one directory per submission: `<root>/<submission id>/manifest.json`
/// plus one file per photo named by its photo id. Files rather than the app
/// database because these are private label images, not queryable rows, and
/// because a blob column would put multi-megabyte photos into a schema that
/// ships with the catalog.
class ProductSubmissionDraftStore implements ProductSubmissionDraftStorage {
  static const _manifestName = 'manifest.json';
  static const _schemaVersion = 'pending_submission_v1';

  final Directory root;

  ProductSubmissionDraftStore({required this.root});

  /// App-private support storage, never the system temporary directory: the OS
  /// reclaims temp between launches, which is exactly the case this exists for.
  static Future<Directory> resolveRoot([
    Future<Directory> Function()? supportDirectory,
  ]) async {
    final base = await (supportDirectory ?? getApplicationSupportDirectory)();
    return Directory('${base.path}/product_submission_drafts');
  }

  static Future<ProductSubmissionDraftStore> open([
    Future<Directory> Function()? supportDirectory,
  ]) async =>
      ProductSubmissionDraftStore(root: await resolveRoot(supportDirectory));

  Directory _directoryFor(String submissionId) =>
      Directory('${root.path}/$submissionId');

  @override
  Future<void> save(
    ProductSubmissionDraft draft, {
    required String consentVersion,
    int evidenceRevision = 1,
  }) async {
    final upc = draft.upc;
    if (upc == null || upc.isEmpty) {
      throw ArgumentError('a durable draft needs the barcode it belongs to');
    }
    final directory = _directoryFor(draft.submissionId);
    // Replace rather than merge: the capture in hand is the whole truth, and a
    // leftover image from a superseded attempt is private data with no owner.
    if (directory.existsSync()) {
      await directory.delete(recursive: true);
    }
    await directory.create(recursive: true);

    final photos = <Map<String, Object?>>[];
    for (final photo in draft.photos) {
      final bytes = photo.bytes;
      await File('${directory.path}/${photo.photoId}').writeAsBytes(
        bytes,
        flush: true,
      );
      photos.add({
        'photo_id': photo.photoId,
        'categories': photo.categoryWireValues,
        'content_type': photo.contentType,
        'byte_size': bytes.length,
        'content_sha256': photo.contentSha256,
      });
    }

    final manifest = <String, Object?>{
      'schema_version': _schemaVersion,
      'submission_id': draft.submissionId,
      'kind': draft.kind.wireValue,
      'upc': upc,
      'resubmission_of': draft.resubmissionOf,
      'no_separate_ingredient_panel': draft.noSeparateIngredientPanel,
      'consent_version': consentVersion,
      'evidence_revision': evidenceRevision,
      'captured_at': DateTime.now().toUtc().toIso8601String(),
      'photos': photos,
    };
    await File('${directory.path}/$_manifestName').writeAsString(
      jsonEncode(manifest),
      flush: true,
    );
  }

  @override
  Future<List<PendingProductSubmission>> list() async {
    if (!root.existsSync()) return const [];
    final pending = <PendingProductSubmission>[];
    for (final entry in root.listSync().whereType<Directory>()) {
      final manifest = await _readManifest(entry);
      if (manifest == null) continue;
      pending.add(
        PendingProductSubmission(
          submissionId: manifest['submission_id'] as String,
          upc: manifest['upc'] as String,
          resubmissionOf: manifest['resubmission_of'] as String?,
          noSeparateIngredientPanel:
              manifest['no_separate_ingredient_panel'] == true,
          consentVersion: manifest['consent_version'] as String,
          evidenceRevision: manifest['evidence_revision'] as int,
          photoCount: (manifest['photos'] as List).length,
          capturedAt:
              DateTime.parse(manifest['captured_at'] as String).toUtc(),
        ),
      );
    }
    pending.sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
    return pending;
  }

  /// The newest unfinished capture for this barcode.
  ///
  /// Comparison goes through [GtinIdentity], the one owner of product identity
  /// in this app, so a scan formatted differently from the saved one still
  /// finds its own draft and this never drifts from how the sheet, the server
  /// and the catalog compare the same barcode.
  @override
  Future<PendingProductSubmission?> findByUpc(String upc) async {
    final wanted = _canonicalOrNull(upc);
    if (wanted == null) return null;
    for (final pending in await list()) {
      if (_canonicalOrNull(pending.upc) == wanted) return pending;
    }
    return null;
  }

  static String? _canonicalOrNull(String value) {
    try {
      return GtinIdentity.parse(value).canonicalGtin14;
    } on FormatException {
      return null;
    }
  }

  /// Rebuild the draft exactly as captured, or null when it can no longer be
  /// trusted. Same submission id and same photo ids, so finishing a recovered
  /// capture replays the server's idempotent sequence instead of creating a
  /// second contribution.
  @override
  Future<MissingProductSubmissionDraft?> restore(String submissionId) async {
    final directory = _directoryFor(submissionId);
    final manifest = await _readManifest(directory);
    if (manifest == null) return null;
    if (manifest['kind'] != ProductSubmissionKind.missingProduct.wireValue) {
      return null;
    }
    final photos = <ProductSubmissionPhoto>[];
    for (final entry in (manifest['photos'] as List).cast<Map<String, Object?>>()) {
      final photoId = entry['photo_id'] as String;
      final file = File('${directory.path}/$photoId');
      if (!file.existsSync()) return null;
      final bytes = Uint8List.fromList(await file.readAsBytes());
      final categories = <ProductSubmissionEvidenceCategory>{};
      for (final wire in (entry['categories'] as List).cast<String>()) {
        final category = ProductSubmissionEvidenceCategory.fromWire(wire);
        if (category == null) return null;
        categories.add(category);
      }
      final ProductSubmissionPhoto photo;
      try {
        photo = ProductSubmissionPhoto(
          photoId: photoId,
          categories: categories,
          bytes: bytes,
          contentType: entry['content_type'] as String,
        );
      } on ProductSubmissionValidationException {
        return null;
      }
      // The manifest hash is the evidence contract, and the photo itself owns
      // how content is hashed. Bytes that no longer agree are not this user's
      // evidence any more, whatever the reason.
      if (photo.contentSha256 != entry['content_sha256']) return null;
      photos.add(photo);
    }
    try {
      return MissingProductSubmissionDraft(
        submissionId: manifest['submission_id'] as String,
        resubmissionOf: manifest['resubmission_of'] as String?,
        upc: manifest['upc'] as String,
        photos: photos,
        noSeparateIngredientPanel:
            manifest['no_separate_ingredient_panel'] == true,
      );
    } on ProductSubmissionValidationException {
      return null;
    }
  }

  /// Remove the record and every private image it owns.
  @override
  Future<void> discard(String submissionId) async {
    final directory = _directoryFor(submissionId);
    if (!directory.existsSync()) return;
    try {
      await directory.delete(recursive: true);
    } on FileSystemException {
      // Storage that refuses deletion is not a reason to fail a submission the
      // server already accepted; the next launch tries again.
    }
  }

  Future<Map<String, Object?>?> _readManifest(Directory directory) async {
    final file = File('${directory.path}/$_manifestName');
    if (!file.existsSync()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, Object?>) return null;
      if (decoded['schema_version'] != _schemaVersion) return null;
      if (decoded['submission_id'] is! String ||
          decoded['upc'] is! String ||
          decoded['kind'] is! String ||
          decoded['consent_version'] is! String ||
          decoded['evidence_revision'] is! int ||
          decoded['captured_at'] is! String ||
          decoded['photos'] is! List) {
        return null;
      }
      DateTime.parse(decoded['captured_at'] as String);
      for (final photo in decoded['photos'] as List) {
        if (photo is! Map<String, Object?> ||
            photo['photo_id'] is! String ||
            photo['categories'] is! List ||
            photo['content_type'] is! String ||
            photo['content_sha256'] is! String) {
          return null;
        }
      }
      return decoded;
    } on Object {
      // A half-written manifest is a torn capture, not a crash: capture starts
      // clean rather than the app failing to open.
      return null;
    }
  }

}
