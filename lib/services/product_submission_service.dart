import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pharmaguide/features/contributions/product_submission_consent_copy.dart';
import 'package:pharmaguide/services/gtin.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The only mismatch categories accepted by the unified submission system.
///
/// This intentionally has no `other` value: reports are structured signals,
/// not a channel for label text, notes, or health information.
enum LabelMismatchCategory {
  productIdentity('product_identity'),
  ingredientMissing('ingredient_missing'),
  ingredientExtra('ingredient_extra'),
  amountOrUnit('amount_or_unit'),
  formOrParenthetical('form_or_parenthetical'),
  servingSizeOrDirections('serving_size_or_directions'),
  otherIngredients('other_ingredients'),
  catalogVersionOrStatus('catalog_version_or_status');

  final String wireValue;
  const LabelMismatchCategory(this.wireValue);
}

/// The three explicit product-label photo positions supported by Storage.
/// Typed evidence categories (schema v2). One photo may satisfy several —
/// a Supplement Facts panel that also carries the ingredient list is tagged
/// with both, which is how "no separate Other Ingredients panel" labels
/// still reach full coverage.
enum ProductSubmissionEvidenceCategory {
  frontIdentity('front_identity'),
  supplementFacts('supplement_facts'),
  ingredientDisclosure('ingredient_disclosure'),
  directionsWarnings('directions_warnings'),

  /// A barcode photo or a clear photo/screenshot of the printed UPC/GTIN.
  /// Review still verifies the identity before approval.
  barcode('barcode'),
  lotExpiry('lot_expiry');

  final String wireValue;
  const ProductSubmissionEvidenceCategory(this.wireValue);

  /// The one wire-value reader for evidence categories, matching the
  /// `fromWire` pattern its sibling enums already use. Anything that reads a
  /// category off a manifest, a row, or a stored draft comes through here so
  /// the mapping cannot drift between readers.
  static ProductSubmissionEvidenceCategory? fromWire(Object? raw) {
    for (final category in ProductSubmissionEvidenceCategory.values) {
      if (category.wireValue == raw) return category;
    }
    return null;
  }
}

enum ProductSubmissionValidationFailure {
  invalidReportId,
  invalidUpc,
  missingDsldId,
  invalidMetadataValue,
  invalidFormulaFingerprint,
  unexpectedMetadata,
  noCategories,
  tooManyPhotos,
  duplicatePhotoId,
  duplicatePhotoContent,
  emptyPhoto,
  photoTooLarge,
  unsupportedPhotoContentType,
  photoSanitizationFailed,
  missingRequiredPhoto,
  invalidEvidenceCategories,
}

class ProductSubmissionValidationException implements Exception {
  final ProductSubmissionValidationFailure reason;

  const ProductSubmissionValidationException(this.reason);

  @override
  String toString() => 'ProductSubmissionValidationException($reason)';
}

/// Product identity and catalog lineage permitted in a report.
///
/// [fromUntrusted] is deliberately fail-closed: any unrecognized key is
/// rejected before values are parsed. The normal UI should use the typed
/// constructor; the factory exists for a future draft/restore boundary.
class LabelMismatchProductMetadata {
  static const allowedKeys = <String>{
    'dsld_id',
    'upc',
    'source_record_id',
    'catalog_source_version',
    'formula_fingerprint',
  };

  final String dsldId;
  final String? upc;
  final String? sourceRecordId;
  final String? catalogSourceVersion;
  final String? formulaFingerprint;

  LabelMismatchProductMetadata({
    required String dsldId,
    String? upc,
    String? sourceRecordId,
    String? catalogSourceVersion,
    String? formulaFingerprint,
  }) : dsldId = _requiredDsldId(dsldId),
       upc = upc == null ? null : _normalizeUpc(upc),
       sourceRecordId = _optionalNonblank(sourceRecordId, maxLength: 200),
       catalogSourceVersion = _optionalNonblank(
         catalogSourceVersion,
         maxLength: 120,
       ),
       formulaFingerprint = _optionalFingerprint(formulaFingerprint);

  factory LabelMismatchProductMetadata.fromUntrusted(
    Map<String, Object?> values,
  ) {
    if (values.keys.any((key) => !allowedKeys.contains(key))) {
      throw const ProductSubmissionValidationException(
        ProductSubmissionValidationFailure.unexpectedMetadata,
      );
    }

    return LabelMismatchProductMetadata(
      dsldId: _readString(values, 'dsld_id', required: true)!,
      upc: _readString(values, 'upc'),
      sourceRecordId: _readString(values, 'source_record_id'),
      catalogSourceVersion: _readString(values, 'catalog_source_version'),
      formulaFingerprint: _readString(values, 'formula_fingerprint'),
    );
  }

  Map<String, Object?> toReportColumns() {
    return <String, Object?>{
      'dsld_id': dsldId,
      if (upc != null) 'upc': upc,
      if (sourceRecordId != null) 'source_record_id': sourceRecordId,
      if (catalogSourceVersion != null)
        'catalog_source_version': catalogSourceVersion,
      if (formulaFingerprint != null) 'formula_fingerprint': formulaFingerprint,
    };
  }

  static String _requiredDsldId(String value) {
    final normalized = value.trim();
    if (!RegExp(r'^[0-9]{1,30}$').hasMatch(normalized)) {
      throw const ProductSubmissionValidationException(
        ProductSubmissionValidationFailure.missingDsldId,
      );
    }
    return normalized;
  }

  static String? _optionalNonblank(String? value, {int maxLength = 300}) {
    if (value == null) return null;
    final normalized = value.trim();
    if (normalized.isEmpty || normalized.length > maxLength) {
      throw const ProductSubmissionValidationException(
        ProductSubmissionValidationFailure.invalidMetadataValue,
      );
    }
    return normalized;
  }

  static String? _optionalFingerprint(String? value) {
    if (value == null) return null;
    final normalized = value.trim();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(normalized)) {
      throw const ProductSubmissionValidationException(
        ProductSubmissionValidationFailure.invalidFormulaFingerprint,
      );
    }
    return normalized;
  }

  static String? _readString(
    Map<String, Object?> values,
    String key, {
    bool required = false,
  }) {
    final value = values[key];
    if (value == null && !required) return null;
    if (value is! String) {
      throw const ProductSubmissionValidationException(
        ProductSubmissionValidationFailure.invalidMetadataValue,
      );
    }
    return value;
  }
}

class ProductSubmissionPhoto {
  static const maxByteSize = 15 * 1024 * 1024;
  static const maxPerSubmission = 8;
  static const allowedContentTypes = <String>{
    'image/jpeg',
    'image/png',
    'image/heic',
    'image/heif',
    'image/webp',
  };

  /// Client-minted identity; becomes the storage path leaf, so it is a
  /// validated UUID exactly like the submission id.
  final String photoId;
  final Set<ProductSubmissionEvidenceCategory> categories;
  final Uint8List _bytes;
  final String contentType;

  Uint8List get bytes => Uint8List.fromList(_bytes);
  int get byteSize => _bytes.length;
  String get contentSha256 => sha256.convert(_bytes).toString();

  List<String> get categoryWireValues {
    final ordered = categories.toList()
      ..sort((left, right) => left.index.compareTo(right.index));
    return [for (final category in ordered) category.wireValue];
  }

  /// Same capture, new evidence tags. Keeps [photoId] and bytes so a
  /// mode change (e.g. "the facts panel carries the ingredient list")
  /// re-tags instead of forcing a retake.
  ProductSubmissionPhoto withCategories(
    Set<ProductSubmissionEvidenceCategory> categories,
  ) {
    if (categories.isEmpty || categories.length > 6) {
      throw const ProductSubmissionValidationException(
        ProductSubmissionValidationFailure.invalidEvidenceCategories,
      );
    }
    return ProductSubmissionPhoto._(
      _bytes,
      photoId: photoId,
      categories: Set.unmodifiable(categories),
      contentType: contentType,
    );
  }

  factory ProductSubmissionPhoto({
    required Set<ProductSubmissionEvidenceCategory> categories,
    required Uint8List bytes,
    required String contentType,
    String? photoId,
  }) {
    if (bytes.isEmpty) {
      throw const ProductSubmissionValidationException(
        ProductSubmissionValidationFailure.emptyPhoto,
      );
    }
    if (bytes.length > maxByteSize) {
      throw const ProductSubmissionValidationException(
        ProductSubmissionValidationFailure.photoTooLarge,
      );
    }
    if (!allowedContentTypes.contains(contentType)) {
      throw const ProductSubmissionValidationException(
        ProductSubmissionValidationFailure.unsupportedPhotoContentType,
      );
    }
    if (categories.isEmpty || categories.length > 6) {
      throw const ProductSubmissionValidationException(
        ProductSubmissionValidationFailure.invalidEvidenceCategories,
      );
    }
    return ProductSubmissionPhoto._(
      Uint8List.fromList(bytes),
      photoId: _validateSubmissionId(photoId ?? _newUuidV4()),
      categories: Set.unmodifiable(categories),
      contentType: contentType,
    );
  }

  ProductSubmissionPhoto._(
    this._bytes, {
    required this.photoId,
    required this.categories,
    required this.contentType,
  });
}

enum ProductSubmissionKind {
  labelMismatch('label_mismatch'),
  missingProduct('missing_product');

  final String wireValue;
  const ProductSubmissionKind(this.wireValue);
}

/// Immutable retry unit shared by both user-facing submission kinds.
///
/// Reusing the same instance reuses its UUID and every object path. The
/// service never accepts narrative user text or health/profile fields.
sealed class ProductSubmissionDraft {
  String get submissionId;
  String? get resubmissionOf;
  ProductSubmissionKind get kind;
  String? get upc;
  List<ProductSubmissionPhoto> get photos;
  Map<String, Object?>? get mismatchDetail;

  /// Reviewer cue only ("this label has no separate Other Ingredients
  /// panel") — never evidence. Coverage still requires an
  /// ingredient_disclosure-tagged photo; on such labels the Supplement
  /// Facts photo carries both categories.
  bool get noSeparateIngredientPanel;
}

/// A structured correction against one known catalog record.
class LabelMismatchReportDraft implements ProductSubmissionDraft {
  @override
  final String submissionId;
  @override
  final String? resubmissionOf;
  final LabelMismatchProductMetadata product;
  final Set<LabelMismatchCategory> categories;
  @override
  final List<ProductSubmissionPhoto> photos;

  String get reportId => submissionId;
  @override
  ProductSubmissionKind get kind => ProductSubmissionKind.labelMismatch;
  @override
  String? get upc => product.upc;
  @override
  bool get noSeparateIngredientPanel => false;
  @override
  Map<String, Object?> get mismatchDetail {
    final categoriesInWireOrder = categories.toList()
      ..sort((left, right) => left.index.compareTo(right.index));
    return <String, Object?>{
      'dsld_id': product.dsldId,
      'source_record_id': product.sourceRecordId,
      'catalog_source_version': product.catalogSourceVersion,
      'formula_fingerprint': product.formulaFingerprint,
      'mismatch_categories': [
        for (final category in categoriesInWireOrder) category.wireValue,
      ],
    };
  }

  LabelMismatchReportDraft({
    String? reportId,
    String? submissionId,
    String? resubmissionOf,
    required this.product,
    required Set<LabelMismatchCategory> categories,
    List<ProductSubmissionPhoto> photos = const [],
  }) : submissionId = _validateSubmissionId(
         _exactlyOneId(reportId: reportId, submissionId: submissionId),
       ),
       resubmissionOf = _optionalSubmissionId(resubmissionOf),
       categories = Set.unmodifiable(categories),
       photos = List.unmodifiable(photos) {
    if (categories.isEmpty) {
      throw const ProductSubmissionValidationException(
        ProductSubmissionValidationFailure.noCategories,
      );
    }
    _validatePhotoSet(photos);
    if (this.resubmissionOf == this.submissionId) {
      throw const ProductSubmissionValidationException(
        ProductSubmissionValidationFailure.invalidReportId,
      );
    }
  }

  factory LabelMismatchReportDraft.create({
    required LabelMismatchProductMetadata product,
    required Set<LabelMismatchCategory> categories,
    List<ProductSubmissionPhoto> photos = const [],
    String? resubmissionOf,
    String Function()? reportIdFactory,
  }) {
    return LabelMismatchReportDraft(
      submissionId: (reportIdFactory ?? _newUuidV4)(),
      product: product,
      categories: categories,
      photos: photos,
      resubmissionOf: resubmissionOf,
    );
  }
}

/// New product evidence created from a barcode miss.
///
/// Coverage is category-typed: the photo set must include front_identity,
/// supplement_facts, ingredient_disclosure, and barcode (one photo may carry
/// several). Product/brand names are intentionally not collected as text.
class MissingProductSubmissionDraft implements ProductSubmissionDraft {
  static const requiredCategories = <ProductSubmissionEvidenceCategory>{
    ProductSubmissionEvidenceCategory.frontIdentity,
    ProductSubmissionEvidenceCategory.supplementFacts,
    ProductSubmissionEvidenceCategory.ingredientDisclosure,
    ProductSubmissionEvidenceCategory.barcode,
  };

  @override
  final String submissionId;
  @override
  final String? resubmissionOf;
  @override
  final String upc;
  @override
  final List<ProductSubmissionPhoto> photos;
  @override
  final bool noSeparateIngredientPanel;

  MissingProductSubmissionDraft({
    required String submissionId,
    String? resubmissionOf,
    required String upc,
    required List<ProductSubmissionPhoto> photos,
    this.noSeparateIngredientPanel = false,
  }) : submissionId = _validateSubmissionId(submissionId),
       resubmissionOf = _optionalSubmissionId(resubmissionOf),
       upc = _normalizeUpc(upc),
       photos = List.unmodifiable(photos) {
    _validatePhotoSet(photos);
    if (this.resubmissionOf == this.submissionId) {
      throw const ProductSubmissionValidationException(
        ProductSubmissionValidationFailure.invalidReportId,
      );
    }
    final covered = <ProductSubmissionEvidenceCategory>{
      for (final photo in photos) ...photo.categories,
    };
    if (!covered.containsAll(requiredCategories)) {
      throw const ProductSubmissionValidationException(
        ProductSubmissionValidationFailure.missingRequiredPhoto,
      );
    }
  }

  factory MissingProductSubmissionDraft.create({
    required String upc,
    required List<ProductSubmissionPhoto> photos,
    bool noSeparateIngredientPanel = false,
    String? resubmissionOf,
    String Function()? submissionIdFactory,
  }) {
    return MissingProductSubmissionDraft(
      submissionId: (submissionIdFactory ?? _newUuidV4)(),
      upc: upc,
      photos: photos,
      noSeparateIngredientPanel: noSeparateIngredientPanel,
      resubmissionOf: resubmissionOf,
    );
  }

  @override
  ProductSubmissionKind get kind => ProductSubmissionKind.missingProduct;
  @override
  Map<String, Object?>? get mismatchDetail => null;
}

/// A reviewer asked for new photos of [requestedPanels]. Every current photo
/// that shows none of them is kept, so the user only retakes what was asked
/// for plus anything that shared a photo with it.
class ProductSubmissionRetake {
  final String submissionId;
  final String upc;

  /// The ready revision the new photos replace.
  final int fromRevision;
  final List<String> keptPhotoIds;
  final Set<ProductSubmissionEvidenceCategory> keptCategories;
  final Set<ProductSubmissionEvidenceCategory> requestedPanels;
  final Set<String> earlierPhotoDigests;
  final ProductSubmissionResolutionCode? reason;

  const ProductSubmissionRetake._({
    required this.submissionId,
    required this.upc,
    required this.fromRevision,
    required this.keptPhotoIds,
    required this.keptCategories,
    required this.requestedPanels,
    required this.earlierPhotoDigests,
    required this.reason,
  });

  factory ProductSubmissionRetake.plan({
    required String submissionId,
    required String upc,
    required int fromRevision,
    required List<
      ({String photoId, Set<ProductSubmissionEvidenceCategory> categories})
    >
    membership,
    required Set<ProductSubmissionEvidenceCategory> requestedPanels,
    Set<String> earlierPhotoDigests = const {},
    ProductSubmissionResolutionCode? reason,
  }) {
    if (requestedPanels.isEmpty) {
      throw ArgumentError('a retake names at least one panel');
    }
    // The server requires room for at least one new photo.
    final kept = membership
        .where(
          (photo) => photo.categories.intersection(requestedPanels).isEmpty,
        )
        .take(ProductSubmissionPhoto.maxPerSubmission - 1)
        .toList(growable: false);
    return ProductSubmissionRetake._(
      submissionId: _validateSubmissionId(submissionId),
      upc: _normalizeUpc(upc),
      fromRevision: fromRevision,
      keptPhotoIds: List.unmodifiable(kept.map((photo) => photo.photoId)),
      keptCategories: Set.unmodifiable({
        for (final photo in kept) ...photo.categories,
      }),
      requestedPanels: Set.unmodifiable(requestedPanels),
      earlierPhotoDigests: Set.unmodifiable(earlierPhotoDigests),
      reason: reason,
    );
  }

  int get newPhotoCapacity =>
      ProductSubmissionPhoto.maxPerSubmission - keptPhotoIds.length;

  /// The same completeness rule the server applies at finalize: kept and new
  /// photos together cover every required panel.
  bool coversRequired(Iterable<ProductSubmissionPhoto> newPhotos) => {
    ...keptCategories,
    for (final photo in newPhotos) ...photo.categories,
  }.containsAll(MissingProductSubmissionDraft.requiredCategories);

  void validateNewPhotos(List<ProductSubmissionPhoto> photos) {
    _validatePhotoSet(photos);
    if (photos.length > newPhotoCapacity) {
      throw const ProductSubmissionValidationException(
        ProductSubmissionValidationFailure.tooManyPhotos,
      );
    }
    if (photos.any(
      (photo) => earlierPhotoDigests.contains(photo.contentSha256),
    )) {
      throw const ProductSubmissionValidationException(
        ProductSubmissionValidationFailure.duplicatePhotoContent,
      );
    }
    // A retake with nothing new is not a revision (the server refuses it too).
    if (photos.isEmpty || !coversRequired(photos)) {
      throw const ProductSubmissionValidationException(
        ProductSubmissionValidationFailure.missingRequiredPhoto,
      );
    }
  }
}

/// The one place a submission identity is minted.
///
/// Capture needs an id before a validated draft can exist, because photos are
/// saved from the first shot. Exposing the service's own minter keeps that one
/// generator rather than a second UUID implementation in the UI.
String newProductSubmissionId() => _newUuidV4();

/// Normalizes and validates a submission identity at storage boundaries.
///
/// The draft store and network service must use the same UUID contract. Keep
/// the implementation here so a restored manifest cannot introduce a second
/// path/identity validator.
String normalizeProductSubmissionId(String value) =>
    _validateSubmissionId(value);

String _exactlyOneId({String? reportId, String? submissionId}) {
  if ((reportId == null) == (submissionId == null)) {
    throw const ProductSubmissionValidationException(
      ProductSubmissionValidationFailure.invalidReportId,
    );
  }
  return reportId ?? submissionId!;
}

String _validateSubmissionId(String value) {
  final normalized = value.trim().toLowerCase();
  final isUuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  ).hasMatch(normalized);
  if (!isUuid) {
    throw const ProductSubmissionValidationException(
      ProductSubmissionValidationFailure.invalidReportId,
    );
  }
  return normalized;
}

String? _optionalSubmissionId(String? value) {
  if (value == null) return null;
  return _validateSubmissionId(value);
}

String _normalizeUpc(String value) {
  try {
    return GtinIdentity.parse(value).submissionIdentity;
  } on FormatException {
    throw const ProductSubmissionValidationException(
      ProductSubmissionValidationFailure.invalidUpc,
    );
  }
}

/// Capture order is evidence order: seq is the list position, 1..N.
List<Map<String, Object?>> _photoManifest(
  List<ProductSubmissionPhoto> photos,
) => [
  for (var index = 0; index < photos.length; index++)
    <String, Object?>{
      'photo_id': photos[index].photoId,
      'seq': index + 1,
      'categories': photos[index].categoryWireValues,
      'content_type': photos[index].contentType,
      'byte_size': photos[index].byteSize,
      'content_sha256': photos[index].contentSha256,
    },
];

void _validatePhotoSet(List<ProductSubmissionPhoto> photos) {
  if (photos.length > ProductSubmissionPhoto.maxPerSubmission) {
    throw const ProductSubmissionValidationException(
      ProductSubmissionValidationFailure.tooManyPhotos,
    );
  }
  if (photos.map((photo) => photo.photoId).toSet().length != photos.length) {
    throw const ProductSubmissionValidationException(
      ProductSubmissionValidationFailure.duplicatePhotoId,
    );
  }
  // Same bytes twice in one submission is a client bug: multi-category
  // tagging covers legitimate reuse without duplicating uploads.
  if (photos.map((photo) => photo.contentSha256).toSet().length !=
      photos.length) {
    throw const ProductSubmissionValidationException(
      ProductSubmissionValidationFailure.duplicatePhotoContent,
    );
  }
}

String _newUuidV4() {
  final random = Random.secure();
  return _uuidFromBytes(
    List<int>.generate(16, (_) => random.nextInt(256)),
    version: 4,
  );
}

/// One retake request key per (submission, replaced revision, new photos).
/// Resending the same capture after a lost response replays its revision;
/// a fresh set of photos (say, after cleanup abandoned an unfinished
/// retake and put the request back) opens a new one instead of replaying
/// the abandoned revision forever.
String _retakeRequestKey(
  String submissionId,
  int fromRevision,
  List<ProductSubmissionPhoto> photos,
) => _uuidFromBytes(
  sha256
      .convert(
        [
          'retake',
          submissionId,
          '$fromRevision',
          for (final photo in photos) photo.photoId,
        ].join(':').codeUnits,
      )
      .bytes,
  version: 5,
);

String _uuidFromBytes(List<int> source, {required int version}) {
  final bytes = List<int>.of(source.take(16));
  bytes[6] = (bytes[6] & 0x0f) | (version << 4);
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0'));
  final value = hex.join();
  return '${value.substring(0, 8)}-'
      '${value.substring(8, 12)}-'
      '${value.substring(12, 16)}-'
      '${value.substring(16, 20)}-'
      '${value.substring(20)}';
}

enum ProductSubmissionPhase { uploadingPhotos, savingReport, succeeded, failed }

enum ProductSubmissionFailureKind {
  authenticationRequired,
  photoUploadFailed,
  reportInsertFailed,
  reportFinalizeFailed,
}

sealed class ProductSubmissionResult {
  final String submissionId;
  const ProductSubmissionResult({required this.submissionId});

  String get reportId => submissionId;
}

class ProductSubmissionSuccess extends ProductSubmissionResult {
  /// Keyed by photo id — the storage path leaf.
  final Map<String, String> photoObjectPaths;

  ProductSubmissionSuccess({
    required super.submissionId,
    required Map<String, String> photoObjectPaths,
  }) : photoObjectPaths = Map.unmodifiable(photoObjectPaths);
}

class ProductSubmissionFailure extends ProductSubmissionResult {
  final ProductSubmissionFailureKind kind;
  final Object? cause;

  const ProductSubmissionFailure({
    required super.submissionId,
    required this.kind,
    this.cause,
  });

  bool get retryable =>
      kind == ProductSubmissionFailureKind.photoUploadFailed ||
      kind == ProductSubmissionFailureKind.reportInsertFailed ||
      kind == ProductSubmissionFailureKind.reportFinalizeFailed;
}

/// Injectable network boundary. Tests use an in-memory implementation; the
/// production adapter below is the only place that calls Supabase directly.
abstract interface class ProductSubmissionBackend {
  String? get authenticatedUserId;

  Future<Map<String, Object?>> fetchIntake({
    required String functionName,
    required Map<String, Object?> payload,
  });

  Future<void> uploadPhoto({
    required String bucket,
    required String objectPath,
    required Uint8List bytes,
    required String contentType,
  });

  Future<void> persistSubmission({
    required String functionName,
    required Map<String, Object?> payload,
  });

  /// [expectedRevision] names the evidence revision being finalized; null is
  /// the first one.
  Future<bool> finalizeSubmission({
    required String functionName,
    required String submissionId,
    int? expectedRevision,
  });

  Future<List<Map<String, Object?>>> listOwnSubmissions({
    required String table,
    required int offset,
    required int limit,
  });

  /// The caller's own evidence for one submission: `revisions` (revision,
  /// photo_ids) and `photos` (photo_id, categories, content_sha256,
  /// revision).
  Future<Map<String, Object?>> fetchOwnEvidence({required String submissionId});

  /// Opens (or replays) an evidence revision; returns its number.
  Future<int> openEvidenceRevision({required Map<String, Object?> payload});
}

class ProductSubmissionService {
  static const submissionsTable = 'product_submissions';
  static const photoBucket = 'product-submission-photos';
  static const createFunction = 'create_product_submission';
  static const finalizeFunction = 'finalize_product_submission';
  static const hideFromHistoryFunction = 'hide_product_submission';
  static const intakeFunction = 'get_product_submission_intake';
  static const openRevisionFunction =
      'open_product_submission_evidence_revision';
  static const addEvidenceFunction = 'add_product_submission_evidence';
  static const _submissionPageSize = 100;

  final ProductSubmissionBackend backend;

  /// Private display label only; never changes verified catalog identity.
  Future<void> setDisplayName(String submissionId, String name) async {
    if (backend.authenticatedUserId == null) {
      throw StateError('Sign in to name a submission.');
    }
    final value = name.trim();
    if (value.isEmpty ||
        value.runes.length > 160 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
      throw const FormatException('Enter a product name of 1–160 characters.');
    }
    await backend.persistSubmission(
      functionName: 'set_product_submission_display_name',
      payload: {
        'p_submission_id': _validateSubmissionId(submissionId),
        'p_display_name': value,
      },
    );
  }

  const ProductSubmissionService({required this.backend});

  factory ProductSubmissionService.production({SupabaseClient? client}) {
    return ProductSubmissionService(
      backend: _SupabaseProductSubmissionBackend(
        client ?? Supabase.instance.client,
      ),
    );
  }

  /// Read-only guidance before capture. The create/finalize transactions
  /// remain authoritative if another device submits after this check.
  Future<ProductSubmissionIntake> checkIntake({
    required ProductSubmissionKind kind,
    required String? upc,
    String? dsldId,
  }) async {
    final userId = backend.authenticatedUserId;
    if (userId == null || userId.isEmpty) {
      throw StateError('Authentication required.');
    }
    final barcode = upc == null ? null : _normalizeUpc(upc);
    if (kind == ProductSubmissionKind.missingProduct && barcode == null) {
      throw const ProductSubmissionValidationException(
        ProductSubmissionValidationFailure.invalidUpc,
      );
    }
    final target = kind == ProductSubmissionKind.labelMismatch
        ? LabelMismatchProductMetadata(dsldId: dsldId ?? '').dsldId
        : null;
    if (kind == ProductSubmissionKind.missingProduct && dsldId != null) {
      throw const ProductSubmissionValidationException(
        ProductSubmissionValidationFailure.unexpectedMetadata,
      );
    }
    final row = await backend
        .fetchIntake(
          functionName: intakeFunction,
          payload: {
            'p_kind': kind.wireValue,
            'p_upc': barcode,
            'p_dsld_id': target,
          },
        )
        .timeout(const Duration(seconds: 10));
    // An account switch during the request must not display the old
    // account's receipt or transfer its retry lineage to a new account.
    if (backend.authenticatedUserId != userId) {
      throw StateError('Submission account changed.');
    }
    final intake = ProductSubmissionIntake.fromRow(row);
    if (intake.action != ProductSubmissionIntakeAction.startNew &&
        (intake.upc == null
                ? null
                : GtinIdentity.parse(intake.upc!).canonicalGtin14) !=
            (barcode == null
                ? null
                : GtinIdentity.parse(barcode).canonicalGtin14)) {
      throw const FormatException('Intake barcode mismatch');
    }
    return intake;
  }

  Future<ProductSubmissionResult> submit(
    ProductSubmissionDraft draft, {
    void Function(ProductSubmissionPhase phase)? onPhaseChanged,
  }) async {
    final userId = backend.authenticatedUserId;
    if (userId == null || userId.isEmpty) {
      return ProductSubmissionFailure(
        submissionId: draft.submissionId,
        kind: ProductSubmissionFailureKind.authenticationRequired,
      );
    }

    // Capture order IS evidence order: seq derives from the draft's list
    // position, and the storage path leaf is the photo's own identity.
    final orderedPhotos = draft.photos;
    final objectPaths = <String, String>{};
    for (final photo in orderedPhotos) {
      objectPaths[photo.photoId] =
          '$userId/${draft.submissionId}/${photo.photoId}';
    }

    final payload = <String, Object?>{
      'p_submission_id': draft.submissionId,
      'p_kind': draft.kind.wireValue,
      'p_upc': draft.upc,
      'p_mismatch_detail': draft.mismatchDetail,
      'p_no_separate_ingredient_panel': draft.noSeparateIngredientPanel,
      'p_photos': _photoManifest(orderedPhotos),
      if (draft.resubmissionOf != null)
        'p_resubmission_of': draft.resubmissionOf,
      // Recorded server-side at first creation; a replay keeps the original.
      'p_consent_version': productSubmissionConsentVersion,
    };

    // Persist the immutable submission and photo manifest before
    // uploading any bytes. A timeout may still leave a committed row, but can
    // never leave an untracked private object. Retrying the same draft is
    // idempotent because the RPC validates exact replay identity.
    onPhaseChanged?.call(ProductSubmissionPhase.savingReport);
    try {
      await backend.persistSubmission(
        functionName: createFunction,
        payload: payload,
      );
    } on Object catch (error) {
      onPhaseChanged?.call(ProductSubmissionPhase.failed);
      return ProductSubmissionFailure(
        submissionId: draft.submissionId,
        kind: ProductSubmissionFailureKind.reportInsertFailed,
        cause: error,
      );
    }

    // Finalize before uploading. This makes retries safe after an ambiguous
    // prior response: a report already committed as ready succeeds without
    // trying to mutate immutable ready-state objects. For a new report with a
    // photo manifest, the database returns false until every path exists.
    try {
      final alreadyReady = await backend.finalizeSubmission(
        functionName: finalizeFunction,
        submissionId: draft.submissionId,
      );
      if (alreadyReady) {
        onPhaseChanged?.call(ProductSubmissionPhase.succeeded);
        return ProductSubmissionSuccess(
          submissionId: draft.submissionId,
          photoObjectPaths: objectPaths,
        );
      }
    } on Object catch (error) {
      onPhaseChanged?.call(ProductSubmissionPhase.failed);
      return ProductSubmissionFailure(
        submissionId: draft.submissionId,
        kind: ProductSubmissionFailureKind.reportFinalizeFailed,
        cause: error,
      );
    }

    if (orderedPhotos.isNotEmpty) {
      onPhaseChanged?.call(ProductSubmissionPhase.uploadingPhotos);
    }
    for (final photo in orderedPhotos) {
      final objectPath = objectPaths[photo.photoId]!;
      try {
        await backend.uploadPhoto(
          bucket: photoBucket,
          objectPath: objectPath,
          bytes: photo.bytes,
          contentType: photo.contentType,
        );
      } on Object catch (error) {
        onPhaseChanged?.call(ProductSubmissionPhase.failed);
        return ProductSubmissionFailure(
          submissionId: draft.submissionId,
          kind: ProductSubmissionFailureKind.photoUploadFailed,
          cause: error,
        );
      }
    }

    onPhaseChanged?.call(ProductSubmissionPhase.savingReport);
    try {
      final finalized = await backend.finalizeSubmission(
        functionName: finalizeFunction,
        submissionId: draft.submissionId,
      );
      if (!finalized) {
        throw StateError('Submission evidence manifest is incomplete.');
      }
    } on Object catch (error) {
      onPhaseChanged?.call(ProductSubmissionPhase.failed);
      return ProductSubmissionFailure(
        submissionId: draft.submissionId,
        kind: ProductSubmissionFailureKind.reportFinalizeFailed,
        cause: error,
      );
    }

    onPhaseChanged?.call(ProductSubmissionPhase.succeeded);
    return ProductSubmissionSuccess(
      submissionId: draft.submissionId,
      photoObjectPaths: objectPaths,
    );
  }

  /// What a requested retake starts from: the photos of the current revision
  /// the reviewer did not ask about, and every earlier photo's digest (the
  /// server refuses the same bytes twice, so capture can say so first).
  Future<ProductSubmissionRetake> prepareRetake(
    ProductSubmissionSummary status,
  ) async {
    final upc = status.upc;
    // An unfinished retake replays from the revision the request named, so
    // it keeps the same photos and reuses the same request key.
    final fromRevision = status.needsNewPhotos
        ? status.evidenceRevision
        : status.retakeUnfinished
        ? status.evidenceRequestedRevision
        : null;
    if (fromRevision == null ||
        upc == null ||
        status.evidenceRequestPanels.isEmpty) {
      throw StateError('No new photos were requested.');
    }
    final evidence = await backend.fetchOwnEvidence(
      submissionId: status.submissionId,
    );
    final revisions = (evidence['revisions'] as List? ?? const [])
        .cast<Map<String, Object?>>();
    final photos = (evidence['photos'] as List? ?? const [])
        .cast<Map<String, Object?>>();
    final current = revisions.where((row) => row['revision'] == fromRevision);
    if (current.length != 1) {
      throw StateError('Current evidence revision unavailable.');
    }
    final memberIds = (current.single['photo_ids'] as List? ?? const [])
        .cast<String>();
    final byId = {for (final row in photos) row['photo_id'] as String: row};
    return ProductSubmissionRetake.plan(
      submissionId: status.submissionId,
      upc: upc,
      fromRevision: fromRevision,
      reason: status.evidenceRequestReason,
      requestedPanels: status.evidenceRequestPanels,
      membership: [
        for (final id in memberIds)
          (
            photoId: id,
            categories: (byId[id]?['categories'] as List? ?? const [])
                .map(ProductSubmissionEvidenceCategory.fromWire)
                .whereType<ProductSubmissionEvidenceCategory>()
                .toSet(),
          ),
      ],
      // Photos already recorded in the open revision are this retake's own,
      // resent as they are; everything else (abandoned retakes included)
      // the server refuses to accept twice.
      earlierPhotoDigests: {
        for (final row in photos)
          if (row['content_sha256'] is String &&
              !(status.retakeUnfinished &&
                  row['revision'] == status.evidenceRevision))
            row['content_sha256'] as String,
      },
    );
  }

  /// Sends the new photos for a requested retake. Same order as [submit]:
  /// open (replayed by a stable key), finalize if a lost response already
  /// finished it, record the new photos, upload, finalize.
  Future<ProductSubmissionResult> submitRetake(
    ProductSubmissionRetake retake,
    List<ProductSubmissionPhoto> photos, {
    void Function(ProductSubmissionPhase phase)? onPhaseChanged,
  }) async {
    final userId = backend.authenticatedUserId;
    if (userId == null || userId.isEmpty) {
      return ProductSubmissionFailure(
        submissionId: retake.submissionId,
        kind: ProductSubmissionFailureKind.authenticationRequired,
      );
    }
    try {
      retake.validateNewPhotos(photos);
    } on ProductSubmissionValidationException catch (error) {
      return ProductSubmissionFailure(
        submissionId: retake.submissionId,
        kind: ProductSubmissionFailureKind.reportInsertFailed,
        cause: error,
      );
    }
    final objectPaths = {
      for (final photo in photos)
        photo.photoId: '$userId/${retake.submissionId}/${photo.photoId}',
    };

    onPhaseChanged?.call(ProductSubmissionPhase.savingReport);
    late final int revision;
    try {
      revision = await backend.openEvidenceRevision(
        payload: {
          'p_submission_id': retake.submissionId,
          'p_expected_revision': retake.fromRevision,
          'p_request_key': _retakeRequestKey(
            retake.submissionId,
            retake.fromRevision,
            photos,
          ),
          'p_keep_photo_ids': retake.keptPhotoIds,
          'p_consent_version': productSubmissionConsentVersion,
        },
      );
      final alreadyReady = await backend.finalizeSubmission(
        functionName: finalizeFunction,
        submissionId: retake.submissionId,
        expectedRevision: revision,
      );
      if (alreadyReady) {
        onPhaseChanged?.call(ProductSubmissionPhase.succeeded);
        return ProductSubmissionSuccess(
          submissionId: retake.submissionId,
          photoObjectPaths: objectPaths,
        );
      }
      await backend.persistSubmission(
        functionName: addEvidenceFunction,
        payload: {
          'p_submission_id': retake.submissionId,
          'p_expected_revision': revision,
          'p_photos': _photoManifest(photos),
        },
      );
    } on Object catch (error) {
      onPhaseChanged?.call(ProductSubmissionPhase.failed);
      return ProductSubmissionFailure(
        submissionId: retake.submissionId,
        kind: ProductSubmissionFailureKind.reportInsertFailed,
        cause: error,
      );
    }

    onPhaseChanged?.call(ProductSubmissionPhase.uploadingPhotos);
    for (final photo in photos) {
      try {
        await backend.uploadPhoto(
          bucket: photoBucket,
          objectPath: objectPaths[photo.photoId]!,
          bytes: photo.bytes,
          contentType: photo.contentType,
        );
      } on Object catch (error) {
        onPhaseChanged?.call(ProductSubmissionPhase.failed);
        return ProductSubmissionFailure(
          submissionId: retake.submissionId,
          kind: ProductSubmissionFailureKind.photoUploadFailed,
          cause: error,
        );
      }
    }

    onPhaseChanged?.call(ProductSubmissionPhase.savingReport);
    try {
      final finalized = await backend.finalizeSubmission(
        functionName: finalizeFunction,
        submissionId: retake.submissionId,
        expectedRevision: revision,
      );
      if (!finalized) {
        throw StateError('Retake evidence manifest is incomplete.');
      }
    } on Object catch (error) {
      onPhaseChanged?.call(ProductSubmissionPhase.failed);
      return ProductSubmissionFailure(
        submissionId: retake.submissionId,
        kind: ProductSubmissionFailureKind.reportFinalizeFailed,
        cause: error,
      );
    }
    onPhaseChanged?.call(ProductSubmissionPhase.succeeded);
    return ProductSubmissionSuccess(
      submissionId: retake.submissionId,
      photoObjectPaths: objectPaths,
    );
  }

  Future<List<ProductSubmissionSummary>> listOwnSubmissions() async {
    final userId = backend.authenticatedUserId;
    if (userId == null || userId.isEmpty) return const [];
    final rows = <Map<String, Object?>>[];
    var offset = 0;
    while (true) {
      final page = await backend.listOwnSubmissions(
        table: submissionsTable,
        offset: offset,
        limit: _submissionPageSize,
      );
      rows.addAll(page);
      if (page.length < _submissionPageSize) break;
      offset += page.length;
    }
    if (backend.authenticatedUserId != userId) return const [];
    return rows.map(ProductSubmissionSummary.fromRow).toList(growable: false);
  }

  Future<void> hideFromHistory(String submissionId) {
    return backend.persistSubmission(
      functionName: hideFromHistoryFunction,
      payload: {'p_submission_id': _validateSubmissionId(submissionId)},
    );
  }
}

class _SupabaseProductSubmissionBackend implements ProductSubmissionBackend {
  final SupabaseClient _client;

  const _SupabaseProductSubmissionBackend(this._client);

  @override
  String? get authenticatedUserId => _client.auth.currentUser?.id;

  @override
  Future<Map<String, Object?>> fetchIntake({
    required String functionName,
    required Map<String, Object?> payload,
  }) async {
    final result = await _client.rpc<Object?>(functionName, params: payload);
    if (result is! Map) {
      throw const FormatException('Invalid submission intake response');
    }
    return Map<String, Object?>.from(result);
  }

  @override
  Future<void> uploadPhoto({
    required String bucket,
    required String objectPath,
    required Uint8List bytes,
    required String contentType,
  }) async {
    await _client.storage
        .from(bucket)
        .uploadBinary(
          objectPath,
          bytes,
          fileOptions: FileOptions(
            contentType: contentType,
            upsert: true,
            metadata: {'content_sha256': sha256.convert(bytes).toString()},
          ),
        );
  }

  @override
  Future<void> persistSubmission({
    required String functionName,
    required Map<String, Object?> payload,
  }) async {
    final persisted = await _client.rpc<bool>(functionName, params: payload);
    if (persisted != true) {
      throw StateError('Submission manifest was not accepted.');
    }
  }

  @override
  Future<bool> finalizeSubmission({
    required String functionName,
    required String submissionId,
    int? expectedRevision,
  }) async {
    final result = await _client.rpc<bool>(
      functionName,
      params: {
        'p_submission_id': submissionId,
        if (expectedRevision != null) 'p_expected_revision': expectedRevision,
      },
    );
    return result == true;
  }

  @override
  Future<Map<String, Object?>> fetchOwnEvidence({
    required String submissionId,
  }) async {
    final revisions = await _client
        .from('product_submission_evidence_revisions')
        .select('revision,photo_ids')
        .eq('submission_id', submissionId);
    final photos = await _client
        .from('product_submission_photos')
        .select('photo_id,categories,content_sha256,revision')
        .eq('submission_id', submissionId);
    return {
      'revisions': [
        for (final row in revisions) Map<String, Object?>.from(row),
      ],
      'photos': [for (final row in photos) Map<String, Object?>.from(row)],
    };
  }

  @override
  Future<int> openEvidenceRevision({
    required Map<String, Object?> payload,
  }) async {
    final revision = await _client.rpc<Object?>(
      ProductSubmissionService.openRevisionFunction,
      params: payload,
    );
    if (revision is! int || revision < 2) {
      throw StateError('Evidence revision was not opened.');
    }
    return revision;
  }

  @override
  Future<List<Map<String, Object?>>> listOwnSubmissions({
    required String table,
    required int offset,
    required int limit,
  }) async {
    final owner = authenticatedUserId;
    if (owner == null) return [];
    final rows = await _client
        .from(table)
        .select(
          'id,kind,normalized_upc,upload_state,review_status,created_at,display_name,'
          'promoted_catalog_version,promoted_at,dismissed_at,'
          'resolution_code,resolution_detail,resolved_dsld_id,'
          'evidence_revision,evidence_requested_revision,'
          'evidence_request_reason,evidence_request_panels,'
          'product_submission_mismatch_details!'
          'product_submission_mismatch_details_submission_id_fkey('
          'dsld_id,source_record_id,catalog_source_version,'
          'formula_fingerprint)',
        )
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .range(offset, offset + limit - 1);
    final result = [for (final row in rows) Map<String, Object?>.from(row)];
    if (result.isNotEmpty) {
      try {
        final ids = [for (final row in result) row['id']! as String];
        final revisions = await _client
            .from('product_submission_evidence_revisions')
            .select('submission_id,revision,photo_ids')
            .inFilter('submission_id', ids);
        final photos = await _client
            .from('product_submission_photos')
            .select('submission_id,photo_id,seq,categories,object_path')
            .eq('user_id', owner)
            .inFilter('submission_id', ids)
            .order('seq');
        final pathsById = {
          for (final row in result)
            row['id']! as String: submissionHistoryPhotoPaths(
              row,
              revisions,
              photos,
            ),
        };
        final paths = pathsById.values
            .expand((paths) => paths)
            .toSet()
            .toList();
        if (paths.isNotEmpty) {
          final signed = await _client.storage
              .from(ProductSubmissionService.photoBucket)
              .createSignedUrlsResult(paths, 300);
          final urls = {
            for (final item in signed.whereType<SignedUrlSuccess>())
              item.path: item.signedUrl,
          };
          for (final row in result) {
            row['photo_urls'] = [
              for (final path in pathsById[row['id']]!)
                if (urls[path] != null) urls[path]!,
            ];
          }
        }
      } on Object {
        // Expired/purged evidence must not hide the history or its saved name.
        // Signed URLs are short lived and never persisted or sent to telemetry.
      }
    }
    if (authenticatedUserId != owner) return [];
    return result;
  }
}

/// Current evidence membership owns which photographs belong to this history
/// item. Keep retained front photos, but never show a superseded Facts panel.
List<String> submissionHistoryPhotoPaths(
  Map<String, Object?> submission,
  List<Map<String, dynamic>> revisions,
  List<Map<String, dynamic>> photos,
) {
  final current = revisions.where(
    (r) =>
        r['submission_id'] == submission['id'] &&
        r['revision'] == (submission['evidence_revision'] ?? 1),
  );
  if (current.length != 1) return const [];
  final members = (current.single['photo_ids'] as List? ?? const []).toSet();
  final selected = photos
      .where(
        (p) =>
            p['submission_id'] == submission['id'] &&
            members.contains(p['photo_id']) &&
            p['object_path'] is String,
      )
      .toList();
  selected.sort((a, b) {
    final frontA = (a['categories'] as List? ?? const []).contains(
      'front_identity',
    );
    final frontB = (b['categories'] as List? ?? const []).contains(
      'front_identity',
    );
    return frontA != frontB
        ? (frontA ? -1 : 1)
        : (a['seq'] as int).compareTo(b['seq'] as int);
  });
  return [for (final photo in selected) photo['object_path'] as String];
}

/// Closed vocabulary of user-facing review outcomes (schema v2). The copy
/// map in the status UI translates each code; `other` is accompanied by a
/// sanitized `resolution_detail` written by the reviewer.
enum ProductSubmissionResolutionCode {
  photoQuality('photo_quality'),
  missingPanel('missing_panel'),
  labelUnreadable('label_unreadable'),
  productIdentityMismatch('product_identity_mismatch'),
  notASupplement('not_a_supplement'),
  alreadyInCatalog('already_in_catalog'),
  duplicateSubmission('duplicate_submission'),
  other('other');

  final String wireValue;
  const ProductSubmissionResolutionCode(this.wireValue);

  static ProductSubmissionResolutionCode? fromWire(Object? raw) {
    for (final code in values) {
      if (code.wireValue == raw) return code;
    }
    return null;
  }

  /// Whether a fresh submission with better evidence can succeed.
  bool get resubmittable => switch (this) {
    photoQuality ||
    missingPanel ||
    labelUnreadable ||
    productIdentityMismatch ||
    other => true,
    notASupplement || alreadyInCatalog || duplicateSubmission => false,
  };
}

enum ProductSubmissionIntakeAction {
  startNew,
  openExisting,
  retryRejected,
  incompleteUpload,
}

/// Minimal owner-scoped response; it carries no internal review notes or
/// other submitter's receipt. Unknown responses never authorize capture.
class ProductSubmissionIntake {
  const ProductSubmissionIntake._({
    required this.action,
    this.submissionId,
    this.upc,
    this.resolutionCode,
    this.resolutionDetail,
  });

  final ProductSubmissionIntakeAction action;
  final String? submissionId;
  final String? upc;
  final ProductSubmissionResolutionCode? resolutionCode;
  final String? resolutionDetail;

  factory ProductSubmissionIntake.fromRow(Map<String, Object?> row) {
    final action = switch (row['action']) {
      'start_new' => ProductSubmissionIntakeAction.startNew,
      'open_existing' => ProductSubmissionIntakeAction.openExisting,
      'retry_rejected' => ProductSubmissionIntakeAction.retryRejected,
      'incomplete_upload' => ProductSubmissionIntakeAction.incompleteUpload,
      _ => throw const FormatException('Unknown submission intake action'),
    };
    if (action == ProductSubmissionIntakeAction.startNew) {
      if (row['submission_id'] != null) {
        throw const FormatException('Unexpected intake receipt');
      }
      return ProductSubmissionIntake._(action: action);
    }
    final id = row['submission_id'];
    final barcode = row['normalized_upc'];
    final detail = row['resolution_detail'];
    if (id is! String ||
        (barcode != null && barcode is! String) ||
        (detail != null && (detail is! String || detail.length > 280))) {
      throw const FormatException('Invalid intake receipt');
    }
    final code = ProductSubmissionResolutionCode.fromWire(
      row['resolution_code'],
    );
    if (action == ProductSubmissionIntakeAction.retryRejected &&
        (code == null ||
            !code.resubmittable ||
            code == ProductSubmissionResolutionCode.productIdentityMismatch)) {
      throw const FormatException('Invalid suggested retry');
    }
    return ProductSubmissionIntake._(
      action: action,
      submissionId: _validateSubmissionId(id),
      upc: barcode == null ? null : _normalizeUpc(barcode as String),
      resolutionCode: code,
      resolutionDetail: detail as String?,
    );
  }
}

enum ProductSubmissionReviewStatus {
  submitted,
  underReview,
  approved,
  rejected,
  duplicate,
  unknown;

  static ProductSubmissionReviewStatus fromWire(Object? raw) => switch (raw) {
    'submitted' => submitted,
    'under_review' => underReview,
    'approved' => approved,
    'rejected' => rejected,
    'duplicate' => duplicate,
    _ => unknown,
  };
}

enum ProductSubmissionUploadState {
  pending,
  ready,
  cleaning,
  unknown;

  static ProductSubmissionUploadState fromWire(Object? raw) => switch (raw) {
    'pending' => pending,
    'ready' => ready,
    'cleaning' => cleaning,
    _ => unknown,
  };
}

class ProductSubmissionSummary {
  const ProductSubmissionSummary({
    required this.submissionId,
    required this.kind,
    required this.upc,
    required this.uploadState,
    required this.reviewStatus,
    required this.createdAt,
    required this.promotedCatalogVersion,
    this.promotedAt,
    this.dismissedAt,
    this.resolutionCode,
    this.resolutionDetail,
    this.resolvedDsldId,
    this.mismatchProduct,
    this.displayName,
    this.photoUrls = const [],
    this.evidenceRevision = 1,
    this.evidenceRequestedRevision,
    this.evidenceRequestReason,
    this.evidenceRequestPanels = const {},
  });

  final String submissionId;

  /// Recognition label projected from review, not a matching/scoring input.
  final String? displayName;

  /// Short-lived owner-authorized evidence URLs; never persisted.
  final List<String> photoUrls;

  /// The evidence revision the submission currently stands on.
  final int evidenceRevision;

  /// The revision a reviewer last asked new photos for, why, and of which
  /// panels. A request is open only while it names the current revision.
  final int? evidenceRequestedRevision;
  final ProductSubmissionResolutionCode? evidenceRequestReason;
  final Set<ProductSubmissionEvidenceCategory> evidenceRequestPanels;
  final ProductSubmissionKind? kind;
  final String? upc;
  final ProductSubmissionUploadState uploadState;
  final ProductSubmissionReviewStatus reviewStatus;
  final DateTime? createdAt;
  final String? promotedCatalogVersion;
  final DateTime? promotedAt;
  final DateTime? dismissedAt;
  final ProductSubmissionResolutionCode? resolutionCode;
  final String? resolutionDetail;

  /// Catalog identity this submission resolved to: stamped at promotion for
  /// approvals (and cascaded to duplicates), or at review for
  /// already-in-catalog duplicates. Deep links must confirm the id exists in
  /// the INSTALLED local catalog before rendering a button.
  final String? resolvedDsldId;

  /// Original catalog identity for a correctable label-mismatch retry.
  final LabelMismatchProductMetadata? mismatchProduct;

  /// Validated comparison identity only; [upc] retains the original digits.
  String? get canonicalGtin14 {
    final barcode = upc;
    if (barcode == null) return null;
    try {
      return GtinIdentity.parse(barcode).canonicalGtin14;
    } on FormatException {
      return null;
    }
  }

  bool get uploadReady => uploadState == ProductSubmissionUploadState.ready;

  bool get hasKnownState =>
      submissionId.isNotEmpty &&
      kind != null &&
      uploadState != ProductSubmissionUploadState.unknown &&
      reviewStatus != ProductSubmissionReviewStatus.unknown;

  bool get isComplete =>
      hasKnownState &&
      uploadReady &&
      reviewStatus == ProductSubmissionReviewStatus.approved &&
      promotedCatalogVersion != null;

  /// A reviewer is waiting on new photos of this submission's current label.
  bool get needsNewPhotos =>
      hasKnownState &&
      kind == ProductSubmissionKind.missingProduct &&
      uploadReady &&
      (reviewStatus == ProductSubmissionReviewStatus.submitted ||
          reviewStatus == ProductSubmissionReviewStatus.underReview) &&
      evidenceRequestedRevision == evidenceRevision &&
      evidenceRequestPanels.isNotEmpty;

  /// New photos were started for a later revision but not finished sending.
  bool get retakeUnfinished =>
      hasKnownState &&
      uploadState == ProductSubmissionUploadState.pending &&
      evidenceRevision > 1;

  bool get hasResubmissionTarget => switch (kind) {
    ProductSubmissionKind.missingProduct => upc != null,
    ProductSubmissionKind.labelMismatch => mismatchProduct != null,
    null => false,
  };

  factory ProductSubmissionSummary.fromRow(Map<String, Object?> row) {
    final kind = switch (row['kind']) {
      'label_mismatch' => ProductSubmissionKind.labelMismatch,
      'missing_product' => ProductSubmissionKind.missingProduct,
      _ => null,
    };
    final createdAtRaw = row['created_at'];
    final promotedAtRaw = row['promoted_at'];
    final dismissedAtRaw = row['dismissed_at'];
    final mismatchRow = _nestedMismatchRow(
      row['product_submission_mismatch_details'],
    );
    LabelMismatchProductMetadata? mismatchProduct;
    if (kind == ProductSubmissionKind.labelMismatch && mismatchRow != null) {
      try {
        mismatchProduct = LabelMismatchProductMetadata(
          dsldId: mismatchRow['dsld_id'] as String,
          upc: row['normalized_upc'] as String?,
          sourceRecordId: mismatchRow['source_record_id'] as String?,
          catalogSourceVersion:
              mismatchRow['catalog_source_version'] as String?,
          formulaFingerprint: mismatchRow['formula_fingerprint'] as String?,
        );
      } on Object {
        mismatchProduct = null;
      }
    }
    return ProductSubmissionSummary(
      submissionId: row['id'] is String ? row['id']! as String : '',
      kind: kind,
      upc: row['normalized_upc'] as String?,
      uploadState: ProductSubmissionUploadState.fromWire(row['upload_state']),
      reviewStatus: ProductSubmissionReviewStatus.fromWire(
        row['review_status'],
      ),
      createdAt: createdAtRaw is String
          ? DateTime.tryParse(createdAtRaw)?.toUtc()
          : null,
      promotedCatalogVersion: row['promoted_catalog_version'] as String?,
      promotedAt: promotedAtRaw is String
          ? DateTime.tryParse(promotedAtRaw)?.toUtc()
          : null,
      dismissedAt: dismissedAtRaw is String
          ? DateTime.tryParse(dismissedAtRaw)?.toUtc()
          : null,
      resolutionCode: ProductSubmissionResolutionCode.fromWire(
        row['resolution_code'],
      ),
      resolutionDetail: row['resolution_detail'] as String?,
      resolvedDsldId: row['resolved_dsld_id'] as String?,
      mismatchProduct: mismatchProduct,
      displayName:
          row['display_name'] is String &&
              (row['display_name']! as String).trim().isNotEmpty
          ? (row['display_name']! as String).trim()
          : null,
      photoUrls: List.unmodifiable(
        (row['photo_urls'] as List? ?? const []).whereType<String>(),
      ),
      evidenceRevision: row['evidence_revision'] is int
          ? row['evidence_revision']! as int
          : 1,
      evidenceRequestedRevision: row['evidence_requested_revision'] as int?,
      evidenceRequestReason: ProductSubmissionResolutionCode.fromWire(
        row['evidence_request_reason'],
      ),
      evidenceRequestPanels:
          (row['evidence_request_panels'] as List? ?? const [])
              .map(ProductSubmissionEvidenceCategory.fromWire)
              .whereType<ProductSubmissionEvidenceCategory>()
              .toSet(),
    );
  }
}

Map<String, Object?>? _nestedMismatchRow(Object? raw) {
  if (raw is Map) return Map<String, Object?>.from(raw);
  if (raw is List && raw.length == 1 && raw.single is Map) {
    return Map<String, Object?>.from(raw.single as Map);
  }
  return null;
}
