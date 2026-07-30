import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
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
enum ProductSubmissionPhotoSlot {
  front('front'),
  supplementFacts('supplement_facts'),
  otherIngredients('other_ingredients');

  final String wireValue;
  const ProductSubmissionPhotoSlot(this.wireValue);
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
  duplicatePhotoSlot,
  emptyPhoto,
  photoTooLarge,
  unsupportedPhotoContentType,
  photoSanitizationFailed,
  missingRequiredPhoto,
  missingOtherIngredientsEvidence,
  conflictingOtherIngredientsEvidence,
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
  static const allowedContentTypes = <String>{
    'image/jpeg',
    'image/png',
    'image/heic',
    'image/heif',
    'image/webp',
  };

  final ProductSubmissionPhotoSlot slot;
  final Uint8List _bytes;
  final String contentType;

  Uint8List get bytes => Uint8List.fromList(_bytes);
  int get byteSize => _bytes.length;
  String get contentSha256 => sha256.convert(_bytes).toString();

  factory ProductSubmissionPhoto({
    required ProductSubmissionPhotoSlot slot,
    required Uint8List bytes,
    required String contentType,
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
    return ProductSubmissionPhoto._(
      Uint8List.fromList(bytes),
      slot: slot,
      contentType: contentType,
    );
  }

  ProductSubmissionPhoto._(
    this._bytes, {
    required this.slot,
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
  ProductSubmissionKind get kind;
  String? get upc;
  List<ProductSubmissionPhoto> get photos;
  Map<String, Object?>? get mismatchDetail;
  bool get otherIngredientsNotPresent;
}

/// A structured correction against one known catalog record.
class LabelMismatchReportDraft implements ProductSubmissionDraft {
  @override
  final String submissionId;
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
  bool get otherIngredientsNotPresent => false;
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
    required this.product,
    required Set<LabelMismatchCategory> categories,
    List<ProductSubmissionPhoto> photos = const [],
  }) : submissionId = _validateSubmissionId(
         _exactlyOneId(reportId: reportId, submissionId: submissionId),
       ),
       categories = Set.unmodifiable(categories),
       photos = List.unmodifiable(photos) {
    if (categories.isEmpty) {
      throw const ProductSubmissionValidationException(
        ProductSubmissionValidationFailure.noCategories,
      );
    }
    if (photos.length > ProductSubmissionPhotoSlot.values.length) {
      throw const ProductSubmissionValidationException(
        ProductSubmissionValidationFailure.tooManyPhotos,
      );
    }
    if (photos.map((photo) => photo.slot).toSet().length != photos.length) {
      throw const ProductSubmissionValidationException(
        ProductSubmissionValidationFailure.duplicatePhotoSlot,
      );
    }
  }

  factory LabelMismatchReportDraft.create({
    required LabelMismatchProductMetadata product,
    required Set<LabelMismatchCategory> categories,
    List<ProductSubmissionPhoto> photos = const [],
    String Function()? reportIdFactory,
  }) {
    return LabelMismatchReportDraft(
      submissionId: (reportIdFactory ?? _newUuidV4)(),
      product: product,
      categories: categories,
      photos: photos,
    );
  }
}

/// New product evidence created from a barcode miss.
///
/// Front and Supplement Facts are always required. Other Ingredients is
/// required unless the user explicitly confirms that no such panel appears on
/// the product. Product/brand names are intentionally not collected as text.
class MissingProductSubmissionDraft implements ProductSubmissionDraft {
  @override
  final String submissionId;
  @override
  final String upc;
  @override
  final List<ProductSubmissionPhoto> photos;
  @override
  final bool otherIngredientsNotPresent;

  MissingProductSubmissionDraft({
    required String submissionId,
    required String upc,
    required List<ProductSubmissionPhoto> photos,
    this.otherIngredientsNotPresent = false,
  }) : submissionId = _validateSubmissionId(submissionId),
       upc = _normalizeUpc(upc),
       photos = List.unmodifiable(photos) {
    _validatePhotoSet(photos);
    final slots = photos.map((photo) => photo.slot).toSet();
    if (!slots.contains(ProductSubmissionPhotoSlot.front) ||
        !slots.contains(ProductSubmissionPhotoSlot.supplementFacts)) {
      throw const ProductSubmissionValidationException(
        ProductSubmissionValidationFailure.missingRequiredPhoto,
      );
    }
    final hasOther = slots.contains(
      ProductSubmissionPhotoSlot.otherIngredients,
    );
    if (!hasOther && !otherIngredientsNotPresent) {
      throw const ProductSubmissionValidationException(
        ProductSubmissionValidationFailure.missingOtherIngredientsEvidence,
      );
    }
    if (hasOther && otherIngredientsNotPresent) {
      throw const ProductSubmissionValidationException(
        ProductSubmissionValidationFailure.conflictingOtherIngredientsEvidence,
      );
    }
  }

  factory MissingProductSubmissionDraft.create({
    required String upc,
    required List<ProductSubmissionPhoto> photos,
    bool otherIngredientsNotPresent = false,
    String Function()? submissionIdFactory,
  }) {
    return MissingProductSubmissionDraft(
      submissionId: (submissionIdFactory ?? _newUuidV4)(),
      upc: upc,
      photos: photos,
      otherIngredientsNotPresent: otherIngredientsNotPresent,
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

String _normalizeUpc(String value) {
  if (RegExp(r'[^0-9\s-]').hasMatch(value)) {
    throw const ProductSubmissionValidationException(
      ProductSubmissionValidationFailure.invalidUpc,
    );
  }
  final normalized = value.replaceAll(RegExp(r'[^0-9]'), '');
  if (!_isValidGtin(normalized)) {
    throw const ProductSubmissionValidationException(
      ProductSubmissionValidationFailure.invalidUpc,
    );
  }
  return normalized;
}

bool _isValidGtin(String value) {
  if (!RegExp(
    r'^(?:[0-9]{8}|[0-9]{12}|[0-9]{13}|[0-9]{14})$',
  ).hasMatch(value)) {
    return false;
  }
  final body = value.substring(0, value.length - 1);
  var sum = 0;
  for (
    var positionFromRight = 1;
    positionFromRight <= body.length;
    positionFromRight++
  ) {
    final digit = int.parse(body[body.length - positionFromRight]);
    sum += digit * (positionFromRight.isOdd ? 3 : 1);
  }
  final expectedCheckDigit = (10 - (sum % 10)) % 10;
  return expectedCheckDigit == int.parse(value[value.length - 1]);
}

void _validatePhotoSet(List<ProductSubmissionPhoto> photos) {
  if (photos.length > ProductSubmissionPhotoSlot.values.length) {
    throw const ProductSubmissionValidationException(
      ProductSubmissionValidationFailure.tooManyPhotos,
    );
  }
  if (photos.map((photo) => photo.slot).toSet().length != photos.length) {
    throw const ProductSubmissionValidationException(
      ProductSubmissionValidationFailure.duplicatePhotoSlot,
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
  final Map<ProductSubmissionPhotoSlot, String> photoObjectPaths;

  ProductSubmissionSuccess({
    required super.submissionId,
    required Map<ProductSubmissionPhotoSlot, String> photoObjectPaths,
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
  });
}

class ProductSubmissionService {
  static const submissionsTable = 'product_submissions';
  static const photoBucket = 'product-submission-photos';
  static const createFunction = 'create_product_submission';
  static const finalizeFunction = 'finalize_product_submission';

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

    final orderedPhotos = draft.photos.toList()
      ..sort((left, right) => left.slot.index.compareTo(right.slot.index));
    final objectPaths = <ProductSubmissionPhotoSlot, String>{};
    for (final photo in orderedPhotos) {
      final objectPath =
          '$userId/${draft.submissionId}/${photo.slot.wireValue}';
      objectPaths[photo.slot] = objectPath;
    }

    final manifest = <Map<String, Object?>>[
      for (final photo in orderedPhotos)
        <String, Object?>{
          'photo_slot': photo.slot.wireValue,
          'content_type': photo.contentType,
          'byte_size': photo.byteSize,
          'content_sha256': photo.contentSha256,
        },
    ];
    final payload = <String, Object?>{
      'p_submission_id': draft.submissionId,
      'p_kind': draft.kind.wireValue,
      'p_upc': draft.upc,
      'p_mismatch_detail': draft.mismatchDetail,
      'p_other_ingredients_not_present': draft.otherIngredientsNotPresent,
      'p_photos': manifest,
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
      final objectPath = objectPaths[photo.slot]!;
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
    final rows = await backend.listOwnSubmissions(table: submissionsTable);
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
  }) async {
    final rows = await _client
        .from(table)
        .select(
          'id,kind,normalized_upc,upload_state,review_status,created_at,'
          'promoted_catalog_version',
        )
        .order('created_at', ascending: false)
        .limit(100);
    return [for (final row in rows) Map<String, Object?>.from(row)];
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
  });

  final String submissionId;
  final ProductSubmissionKind? kind;
  final String? upc;
  final ProductSubmissionUploadState uploadState;
  final ProductSubmissionReviewStatus reviewStatus;
  final DateTime? createdAt;
  final String? promotedCatalogVersion;

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

  factory ProductSubmissionSummary.fromRow(Map<String, Object?> row) {
    final kind = switch (row['kind']) {
      'label_mismatch' => ProductSubmissionKind.labelMismatch,
      'missing_product' => ProductSubmissionKind.missingProduct,
      _ => null,
    };
    final createdAtRaw = row['created_at'];
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
    );
  }
}
