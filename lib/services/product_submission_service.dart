import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
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
  barcode('barcode'),
  lotExpiry('lot_expiry');

  final String wireValue;
  const ProductSubmissionEvidenceCategory(this.wireValue);
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
/// supplement_facts, and ingredient_disclosure (one photo may carry
/// several). Product/brand names are intentionally not collected as text.
class MissingProductSubmissionDraft implements ProductSubmissionDraft {
  static const requiredCategories = <ProductSubmissionEvidenceCategory>{
    ProductSubmissionEvidenceCategory.frontIdentity,
    ProductSubmissionEvidenceCategory.supplementFacts,
    ProductSubmissionEvidenceCategory.ingredientDisclosure,
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
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
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

  Future<bool> finalizeSubmission({
    required String functionName,
    required String submissionId,
  });

  Future<List<Map<String, Object?>>> listOwnSubmissions({
    required String table,
    required int offset,
    required int limit,
  });
}

class ProductSubmissionService {
  static const submissionsTable = 'product_submissions';
  static const photoBucket = 'product-submission-photos';
  static const createFunction = 'create_product_submission';
  static const finalizeFunction = 'finalize_product_submission';
  static const _submissionPageSize = 100;

  final ProductSubmissionBackend backend;

  const ProductSubmissionService({required this.backend});

  factory ProductSubmissionService.production({SupabaseClient? client}) {
    return ProductSubmissionService(
      backend: _SupabaseProductSubmissionBackend(
        client ?? Supabase.instance.client,
      ),
    );
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

    final manifest = <Map<String, Object?>>[
      for (var index = 0; index < orderedPhotos.length; index++)
        <String, Object?>{
          'photo_id': orderedPhotos[index].photoId,
          'seq': index + 1,
          'categories': orderedPhotos[index].categoryWireValues,
          'content_type': orderedPhotos[index].contentType,
          'byte_size': orderedPhotos[index].byteSize,
          'content_sha256': orderedPhotos[index].contentSha256,
        },
    ];
    final payload = <String, Object?>{
      'p_submission_id': draft.submissionId,
      'p_kind': draft.kind.wireValue,
      'p_upc': draft.upc,
      'p_mismatch_detail': draft.mismatchDetail,
      'p_no_separate_ingredient_panel': draft.noSeparateIngredientPanel,
      'p_photos': manifest,
      if (draft.resubmissionOf != null)
        'p_resubmission_of': draft.resubmissionOf,
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
    return rows.map(ProductSubmissionSummary.fromRow).toList(growable: false);
  }
}

class _SupabaseProductSubmissionBackend implements ProductSubmissionBackend {
  final SupabaseClient _client;

  const _SupabaseProductSubmissionBackend(this._client);

  @override
  String? get authenticatedUserId => _client.auth.currentUser?.id;

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
  }) async {
    final result = await _client.rpc<bool>(
      functionName,
      params: {'p_submission_id': submissionId},
    );
    return result == true;
  }

  @override
  Future<List<Map<String, Object?>>> listOwnSubmissions({
    required String table,
    required int offset,
    required int limit,
  }) async {
    final rows = await _client
        .from(table)
        .select(
          'id,kind,normalized_upc,upload_state,review_status,created_at,'
          'promoted_catalog_version,promoted_at,'
          'resolution_code,resolution_detail,resolved_dsld_id,'
          'product_submission_mismatch_details!'
          'product_submission_mismatch_details_submission_id_fkey('
          'dsld_id,source_record_id,catalog_source_version,'
          'formula_fingerprint)',
        )
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .range(offset, offset + limit - 1);
    return [for (final row in rows) Map<String, Object?>.from(row)];
  }
}

/// Closed vocabulary of user-facing review outcomes (schema v2). The copy
/// map in the status UI translates each code; `other` is accompanied by a
/// sanitized `resolution_detail` written by the reviewer.
enum ProductSubmissionResolutionCode {
  photoQuality('photo_quality'),
  missingPanel('missing_panel'),
  labelUnreadable('label_unreadable'),
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
    photoQuality || missingPanel || labelUnreadable || other => true,
    notASupplement || alreadyInCatalog || duplicateSubmission => false,
  };
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
    this.resolutionCode,
    this.resolutionDetail,
    this.resolvedDsldId,
    this.mismatchProduct,
  });

  final String submissionId;
  final ProductSubmissionKind? kind;
  final String? upc;
  final ProductSubmissionUploadState uploadState;
  final ProductSubmissionReviewStatus reviewStatus;
  final DateTime? createdAt;
  final String? promotedCatalogVersion;
  final DateTime? promotedAt;
  final ProductSubmissionResolutionCode? resolutionCode;
  final String? resolutionDetail;

  /// Catalog identity this submission resolved to: stamped at promotion for
  /// approvals (and cascaded to duplicates), or at review for
  /// already-in-catalog duplicates. Deep links must confirm the id exists in
  /// the INSTALLED local catalog before rendering a button.
  final String? resolvedDsldId;

  /// Original catalog identity for a correctable label-mismatch retry.
  final LabelMismatchProductMetadata? mismatchProduct;

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
      resolutionCode: ProductSubmissionResolutionCode.fromWire(
        row['resolution_code'],
      ),
      resolutionDetail: row['resolution_detail'] as String?,
      resolvedDsldId: row['resolved_dsld_id'] as String?,
      mismatchProduct: mismatchProduct,
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
