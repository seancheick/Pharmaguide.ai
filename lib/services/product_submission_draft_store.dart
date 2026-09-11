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

  /// The ready revision a requested retake replaces, or null for a new
  /// submission. See [ProductSubmissionDraftStorage.save].
  int? get retakeOfRevision => _retakeOf(evidenceRevision);
}

/// `evidence_revision` is 1 for a new submission and `replaced + 1` for a
/// retake capture; the server numbers the revision itself when it opens.
int? _retakeOf(int evidenceRevision) =>
    evidenceRevision > 1 ? evidenceRevision - 1 : null;

/// What the capture flow needs from durable storage.
///
/// The sheet depends on this rather than on the file-backed implementation so
/// a widget test can supply an in-memory one. Real file I/O inside a widget
/// test never advances under `pumpAndSettle`, which turns a UI assertion into
/// a multi-minute hang; the interface keeps the UI honest and the tests fast.
abstract class ProductSubmissionDraftStorage {
  /// Persist the capture as it currently stands, owned by one account.
  ///
  /// Deliberately takes photos rather than a validated draft: a capture is
  /// worth keeping from the first shot, and a draft cannot exist until every
  /// required panel is present. Coverage is the submit gate, not the save gate.
  ///
  /// A retake capture passes `evidenceRevision: replaced + 1` under the
  /// existing submission's id; it only ever resumes through its own
  /// submission, never as a new product capture.
  ///
  /// Every operation carries [userId] because a phone is shared and an account
  /// can be switched. These are private label photos belonging to whoever took
  /// them; another account must not see them, resume them, or submit them.
  Future<void> save({
    required String userId,
    required String submissionId,
    required String upc,
    required List<ProductSubmissionPhoto> photos,
    required String consentVersion,
    String? resubmissionOf,
    bool noSeparateIngredientPanel,
    int evidenceRevision,
  });

  Future<List<PendingProductSubmission>> list(String userId);

  Future<PendingProductSubmission?> findByUpc(String userId, String upc);

  /// The photos and answers as captured, without judging completeness.
  Future<RestoredCapture?> restore(String userId, String submissionId);

  Future<void> discard(String userId, String submissionId);
}

/// A capture read back from storage, complete or not.
class RestoredCapture {
  final String submissionId;
  final String upc;
  final String? resubmissionOf;
  final bool noSeparateIngredientPanel;
  final List<ProductSubmissionPhoto> photos;
  final int evidenceRevision;

  const RestoredCapture({
    required this.submissionId,
    required this.upc,
    required this.resubmissionOf,
    required this.noSeparateIngredientPanel,
    required this.photos,
    this.evidenceRevision = 1,
  });

  int? get retakeOfRevision => _retakeOf(evidenceRevision);
}

/// Durable storage for captures that have not completed the submit sequence.
///
/// Layout is one account directory per user, then one directory per submission:
/// `<root>/<account id>/<submission id>/manifest.json` plus one file per photo
/// named by its photo id. Files rather than the app database because these are
/// private label images, not queryable rows, and because a blob column would
/// put multi-megabyte photos into a schema that ships with the catalog.
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

  /// One directory per account, so a different account cannot even enumerate
  /// another's captures, and one directory per submission inside it.
  Directory _directoryFor(String userId, String submissionId) => Directory(
    '${root.path}/${_scope(userId)}/${normalizeProductSubmissionId(submissionId)}',
  );

  Directory _accountRoot(String userId) =>
      Directory('${root.path}/${_scope(userId)}');

  static final _accountName = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

  /// The account's own identifier, used directly as a directory name.
  ///
  /// Supabase user ids are UUIDs, so no encoding is needed; the charset check
  /// is what keeps an unexpected value from escaping the drafts directory.
  static String _scope(String userId) {
    if (!_accountName.hasMatch(userId)) {
      throw ArgumentError('a capture must belong to a signed-in account');
    }
    return userId;
  }

  @override
  Future<void> save({
    required String userId,
    required String submissionId,
    required String upc,
    required List<ProductSubmissionPhoto> photos,
    required String consentVersion,
    String? resubmissionOf,
    bool noSeparateIngredientPanel = false,
    int evidenceRevision = 1,
  }) async {
    if (upc.isEmpty) {
      throw ArgumentError('a durable capture needs the barcode it belongs to');
    }
    final directory = _directoryFor(userId, submissionId);
    // Replace rather than merge: the capture in hand is the whole truth, and a
    // leftover image from a superseded attempt is private data with no owner.
    if (directory.existsSync()) {
      await directory.delete(recursive: true);
    }
    await directory.create(recursive: true);

    final entries = <Map<String, Object?>>[];
    for (final photo in photos) {
      final bytes = photo.bytes;
      await File(
        '${directory.path}/${photo.photoId}',
      ).writeAsBytes(bytes, flush: true);
      entries.add({
        'photo_id': photo.photoId,
        'categories': photo.categoryWireValues,
        'content_type': photo.contentType,
        'byte_size': bytes.length,
        'content_sha256': photo.contentSha256,
      });
    }

    final manifest = <String, Object?>{
      'schema_version': _schemaVersion,
      'submission_id': submissionId,
      'owner_scope': _scope(userId),
      'kind': ProductSubmissionKind.missingProduct.wireValue,
      'upc': upc,
      'resubmission_of': resubmissionOf,
      'no_separate_ingredient_panel': noSeparateIngredientPanel,
      'consent_version': consentVersion,
      'evidence_revision': evidenceRevision,
      'captured_at': DateTime.now().toUtc().toIso8601String(),
      'photos': entries,
    };
    await File(
      '${directory.path}/$_manifestName',
    ).writeAsString(jsonEncode(manifest), flush: true);
  }

  @override
  Future<List<PendingProductSubmission>> list(String userId) async {
    final accountRoot = _accountRoot(userId);
    if (!accountRoot.existsSync()) return const [];
    final pending = <PendingProductSubmission>[];
    for (final entry in accountRoot.listSync().whereType<Directory>()) {
      final manifest = await _readManifest(entry);
      // Belt and braces: the directory says whose it is, and so does the
      // manifest. A mismatch is not this account's capture.
      if (manifest?['owner_scope'] != _scope(userId)) continue;
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
          capturedAt: DateTime.parse(manifest['captured_at'] as String).toUtc(),
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
  Future<PendingProductSubmission?> findByUpc(String userId, String upc) async {
    final wanted = _canonicalOrNull(upc);
    if (wanted == null) return null;
    for (final pending in await list(userId)) {
      if (pending.retakeOfRevision != null) continue;
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

  /// Read the capture back exactly as taken, or null when it can no longer be
  /// trusted. Same submission id and same photo ids, so finishing a recovered
  /// capture replays the server's idempotent sequence instead of creating a
  /// second contribution. Completeness is not checked here: a half-finished
  /// capture is still the user's work.
  @override
  Future<RestoredCapture?> restore(String userId, String submissionId) async {
    final directory = _directoryFor(userId, submissionId);
    final manifest = await _readManifest(directory);
    if (manifest == null) return null;
    if (manifest['owner_scope'] != _scope(userId)) return null;
    if (manifest['kind'] != ProductSubmissionKind.missingProduct.wireValue) {
      return null;
    }
    final photos = <ProductSubmissionPhoto>[];
    for (final entry
        in (manifest['photos'] as List).cast<Map<String, Object?>>()) {
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
    return RestoredCapture(
      submissionId: manifest['submission_id'] as String,
      upc: manifest['upc'] as String,
      resubmissionOf: manifest['resubmission_of'] as String?,
      noSeparateIngredientPanel:
          manifest['no_separate_ingredient_panel'] == true,
      photos: photos,
      evidenceRevision: manifest['evidence_revision'] as int,
    );
  }

  /// Remove the record and every private image it owns.
  @override
  Future<void> discard(String userId, String submissionId) async {
    final directory = _directoryFor(userId, submissionId);
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
          decoded['owner_scope'] is! String ||
          decoded['upc'] is! String ||
          decoded['kind'] is! String ||
          decoded['consent_version'] is! String ||
          decoded['evidence_revision'] is! int ||
          decoded['captured_at'] is! String ||
          decoded['photos'] is! List) {
        return null;
      }
      final normalizedSubmissionId = normalizeProductSubmissionId(
        decoded['submission_id'] as String,
      );
      final directoryName = directory.uri.pathSegments
          .where((segment) => segment.isNotEmpty)
          .lastOrNull;
      if (directoryName != normalizedSubmissionId) return null;
      DateTime.parse(decoded['captured_at'] as String);
      for (final photo in decoded['photos'] as List) {
        if (photo is! Map<String, Object?> ||
            photo['photo_id'] is! String ||
            photo['categories'] is! List ||
            photo['content_type'] is! String ||
            photo['content_sha256'] is! String) {
          return null;
        }
        final categories = photo['categories'] as List;
        if (categories.any((category) => category is! String)) return null;
      }
      return decoded;
    } on Object {
      // A half-written manifest is a torn capture, not a crash: capture starts
      // clean rather than the app failing to open.
      return null;
    }
  }
}
