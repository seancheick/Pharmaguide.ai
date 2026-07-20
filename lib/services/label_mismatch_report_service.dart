import 'dart:math';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

/// The only mismatch categories accepted by the client and database.
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
enum LabelMismatchPhotoSlot {
  front('front'),
  supplementFacts('supplement_facts'),
  otherIngredients('other_ingredients');

  final String wireValue;
  const LabelMismatchPhotoSlot(this.wireValue);
}

enum LabelMismatchValidationFailure {
  invalidReportId,
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
}

class LabelMismatchValidationException implements Exception {
  final LabelMismatchValidationFailure reason;

  const LabelMismatchValidationException(this.reason);

  @override
  String toString() => 'LabelMismatchValidationException($reason)';
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
       upc = _optionalNonblank(upc),
       sourceRecordId = _optionalNonblank(sourceRecordId),
       catalogSourceVersion = _optionalNonblank(catalogSourceVersion),
       formulaFingerprint = _optionalFingerprint(formulaFingerprint);

  factory LabelMismatchProductMetadata.fromUntrusted(
    Map<String, Object?> values,
  ) {
    if (values.keys.any((key) => !allowedKeys.contains(key))) {
      throw const LabelMismatchValidationException(
        LabelMismatchValidationFailure.unexpectedMetadata,
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
    if (normalized.isEmpty) {
      throw const LabelMismatchValidationException(
        LabelMismatchValidationFailure.missingDsldId,
      );
    }
    return normalized;
  }

  static String? _optionalNonblank(String? value) {
    if (value == null) return null;
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw const LabelMismatchValidationException(
        LabelMismatchValidationFailure.invalidMetadataValue,
      );
    }
    return normalized;
  }

  static String? _optionalFingerprint(String? value) {
    if (value == null) return null;
    final normalized = value.trim();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(normalized)) {
      throw const LabelMismatchValidationException(
        LabelMismatchValidationFailure.invalidFormulaFingerprint,
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
      throw const LabelMismatchValidationException(
        LabelMismatchValidationFailure.invalidMetadataValue,
      );
    }
    return value;
  }
}

class LabelMismatchPhoto {
  static const maxByteSize = 15 * 1024 * 1024;
  static const allowedContentTypes = <String>{
    'image/jpeg',
    'image/png',
    'image/heic',
    'image/heif',
    'image/webp',
  };

  final LabelMismatchPhotoSlot slot;
  final Uint8List _bytes;
  final String contentType;

  Uint8List get bytes => Uint8List.fromList(_bytes);
  int get byteSize => _bytes.length;

  factory LabelMismatchPhoto({
    required LabelMismatchPhotoSlot slot,
    required Uint8List bytes,
    required String contentType,
  }) {
    if (bytes.isEmpty) {
      throw const LabelMismatchValidationException(
        LabelMismatchValidationFailure.emptyPhoto,
      );
    }
    if (bytes.length > maxByteSize) {
      throw const LabelMismatchValidationException(
        LabelMismatchValidationFailure.photoTooLarge,
      );
    }
    if (!allowedContentTypes.contains(contentType)) {
      throw const LabelMismatchValidationException(
        LabelMismatchValidationFailure.unsupportedPhotoContentType,
      );
    }
    return LabelMismatchPhoto._(
      Uint8List.fromList(bytes),
      slot: slot,
      contentType: contentType,
    );
  }

  LabelMismatchPhoto._(
    this._bytes, {
    required this.slot,
    required this.contentType,
  });
}

/// An immutable retry unit. Reusing this instance reuses its report ID and
/// every object path; callers must not reconstruct it when the user taps Retry.
class LabelMismatchReportDraft {
  final String reportId;
  final LabelMismatchProductMetadata product;
  final Set<LabelMismatchCategory> categories;
  final List<LabelMismatchPhoto> photos;

  LabelMismatchReportDraft({
    required String reportId,
    required this.product,
    required Set<LabelMismatchCategory> categories,
    List<LabelMismatchPhoto> photos = const [],
  }) : reportId = _validateReportId(reportId),
       categories = Set.unmodifiable(categories),
       photos = List.unmodifiable(photos) {
    if (categories.isEmpty) {
      throw const LabelMismatchValidationException(
        LabelMismatchValidationFailure.noCategories,
      );
    }
    if (photos.length > LabelMismatchPhotoSlot.values.length) {
      throw const LabelMismatchValidationException(
        LabelMismatchValidationFailure.tooManyPhotos,
      );
    }
    if (photos.map((photo) => photo.slot).toSet().length != photos.length) {
      throw const LabelMismatchValidationException(
        LabelMismatchValidationFailure.duplicatePhotoSlot,
      );
    }
  }

  factory LabelMismatchReportDraft.create({
    required LabelMismatchProductMetadata product,
    required Set<LabelMismatchCategory> categories,
    List<LabelMismatchPhoto> photos = const [],
    String Function()? reportIdFactory,
  }) {
    return LabelMismatchReportDraft(
      reportId: (reportIdFactory ?? _newUuidV4)(),
      product: product,
      categories: categories,
      photos: photos,
    );
  }

  static String _validateReportId(String value) {
    final normalized = value.trim().toLowerCase();
    final isUuid = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    ).hasMatch(normalized);
    if (!isUuid) {
      throw const LabelMismatchValidationException(
        LabelMismatchValidationFailure.invalidReportId,
      );
    }
    return normalized;
  }

  static String _newUuidV4() {
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
}

enum LabelMismatchSubmissionPhase {
  uploadingPhotos,
  savingReport,
  succeeded,
  failed,
}

enum LabelMismatchFailureKind {
  authenticationRequired,
  photoUploadFailed,
  reportInsertFailed,
  reportFinalizeFailed,
}

sealed class LabelMismatchSubmissionResult {
  final String reportId;
  const LabelMismatchSubmissionResult({required this.reportId});
}

class LabelMismatchSubmissionSuccess extends LabelMismatchSubmissionResult {
  final Map<LabelMismatchPhotoSlot, String> photoObjectPaths;

  LabelMismatchSubmissionSuccess({
    required super.reportId,
    required Map<LabelMismatchPhotoSlot, String> photoObjectPaths,
  }) : photoObjectPaths = Map.unmodifiable(photoObjectPaths);
}

class LabelMismatchSubmissionFailure extends LabelMismatchSubmissionResult {
  final LabelMismatchFailureKind kind;
  final Object? cause;

  const LabelMismatchSubmissionFailure({
    required super.reportId,
    required this.kind,
    this.cause,
  });

  bool get retryable =>
      kind == LabelMismatchFailureKind.photoUploadFailed ||
      kind == LabelMismatchFailureKind.reportInsertFailed ||
      kind == LabelMismatchFailureKind.reportFinalizeFailed;
}

/// Injectable network boundary. Tests use an in-memory implementation; the
/// production adapter below is the only place that calls Supabase directly.
abstract interface class LabelMismatchReportBackend {
  String? get authenticatedUserId;

  Future<void> uploadPhoto({
    required String bucket,
    required String objectPath,
    required Uint8List bytes,
    required String contentType,
  });

  Future<void> persistReport({
    required String reportsTable,
    required Map<String, Object?> reportRow,
    required String photosTable,
    required List<Map<String, Object?>> photoRows,
  });

  Future<bool> finalizeReport({
    required String functionName,
    required String reportId,
  });
}

class LabelMismatchReportService {
  static const reportsTable = 'label_mismatch_reports';
  static const photosTable = 'label_mismatch_report_photos';
  static const photoBucket = 'label-mismatch-report-photos';
  static const finalizeFunction = 'finalize_label_mismatch_report';
  static const reportInsertColumns = <String>{
    'id',
    'user_id',
    'dsld_id',
    'upc',
    'source_record_id',
    'catalog_source_version',
    'formula_fingerprint',
    'mismatch_categories',
  };

  final LabelMismatchReportBackend backend;

  const LabelMismatchReportService({required this.backend});

  factory LabelMismatchReportService.production({SupabaseClient? client}) {
    return LabelMismatchReportService(
      backend: _SupabaseLabelMismatchReportBackend(
        client ?? Supabase.instance.client,
      ),
    );
  }

  Future<LabelMismatchSubmissionResult> submit(
    LabelMismatchReportDraft draft, {
    void Function(LabelMismatchSubmissionPhase phase)? onPhaseChanged,
  }) async {
    final userId = backend.authenticatedUserId;
    if (userId == null || userId.isEmpty) {
      return LabelMismatchSubmissionFailure(
        reportId: draft.reportId,
        kind: LabelMismatchFailureKind.authenticationRequired,
      );
    }

    final orderedPhotos = draft.photos.toList()
      ..sort((left, right) => left.slot.index.compareTo(right.slot.index));
    final objectPaths = <LabelMismatchPhotoSlot, String>{};
    for (final photo in orderedPhotos) {
      final objectPath = '$userId/${draft.reportId}/${photo.slot.wireValue}';
      objectPaths[photo.slot] = objectPath;
    }

    final categories = draft.categories.toList()
      ..sort((left, right) => left.index.compareTo(right.index));
    final reportRow = <String, Object?>{
      'id': draft.reportId,
      'user_id': userId,
      ...draft.product.toReportColumns(),
      'mismatch_categories': [
        for (final category in categories) category.wireValue,
      ],
    };
    final photoBySlot = {for (final photo in orderedPhotos) photo.slot: photo};
    final photoRows = <Map<String, Object?>>[
      for (final entry in objectPaths.entries)
        <String, Object?>{
          'report_id': draft.reportId,
          'user_id': userId,
          'photo_slot': entry.key.wireValue,
          'object_path': entry.value,
          'content_type': photoBySlot[entry.key]!.contentType,
          'byte_size': photoBySlot[entry.key]!.byteSize,
        },
    ];

    // Persist the immutable report and its three-slot photo manifest before
    // uploading any bytes. A timeout may still leave a committed row, but can
    // never leave an untracked private object. Retrying the same draft is
    // idempotent because both table writes ignore duplicate primary keys.
    onPhaseChanged?.call(LabelMismatchSubmissionPhase.savingReport);
    try {
      await backend.persistReport(
        reportsTable: reportsTable,
        reportRow: reportRow,
        photosTable: photosTable,
        photoRows: photoRows,
      );
    } on Object catch (error) {
      onPhaseChanged?.call(LabelMismatchSubmissionPhase.failed);
      return LabelMismatchSubmissionFailure(
        reportId: draft.reportId,
        kind: LabelMismatchFailureKind.reportInsertFailed,
        cause: error,
      );
    }

    // Finalize before uploading. This makes retries safe after an ambiguous
    // prior response: a report already committed as ready succeeds without
    // trying to mutate immutable ready-state objects. For a new report with a
    // photo manifest, the database returns false until every path exists.
    try {
      final alreadyReady = await backend.finalizeReport(
        functionName: finalizeFunction,
        reportId: draft.reportId,
      );
      if (alreadyReady) {
        onPhaseChanged?.call(LabelMismatchSubmissionPhase.succeeded);
        return LabelMismatchSubmissionSuccess(
          reportId: draft.reportId,
          photoObjectPaths: objectPaths,
        );
      }
    } on Object catch (error) {
      onPhaseChanged?.call(LabelMismatchSubmissionPhase.failed);
      return LabelMismatchSubmissionFailure(
        reportId: draft.reportId,
        kind: LabelMismatchFailureKind.reportFinalizeFailed,
        cause: error,
      );
    }

    if (orderedPhotos.isNotEmpty) {
      onPhaseChanged?.call(LabelMismatchSubmissionPhase.uploadingPhotos);
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
        onPhaseChanged?.call(LabelMismatchSubmissionPhase.failed);
        return LabelMismatchSubmissionFailure(
          reportId: draft.reportId,
          kind: LabelMismatchFailureKind.photoUploadFailed,
          cause: error,
        );
      }
    }

    onPhaseChanged?.call(LabelMismatchSubmissionPhase.savingReport);
    try {
      final finalized = await backend.finalizeReport(
        functionName: finalizeFunction,
        reportId: draft.reportId,
      );
      if (!finalized) {
        throw StateError('Report photo manifest is incomplete.');
      }
    } on Object catch (error) {
      onPhaseChanged?.call(LabelMismatchSubmissionPhase.failed);
      return LabelMismatchSubmissionFailure(
        reportId: draft.reportId,
        kind: LabelMismatchFailureKind.reportFinalizeFailed,
        cause: error,
      );
    }

    onPhaseChanged?.call(LabelMismatchSubmissionPhase.succeeded);
    return LabelMismatchSubmissionSuccess(
      reportId: draft.reportId,
      photoObjectPaths: objectPaths,
    );
  }
}

class _SupabaseLabelMismatchReportBackend
    implements LabelMismatchReportBackend {
  final SupabaseClient _client;

  const _SupabaseLabelMismatchReportBackend(this._client);

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
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        );
  }

  @override
  Future<void> persistReport({
    required String reportsTable,
    required Map<String, Object?> reportRow,
    required String photosTable,
    required List<Map<String, Object?>> photoRows,
  }) async {
    // Ignore duplicate primary keys so an ambiguous network response can be
    // retried with the same report ID without mutating an existing report.
    await _client
        .from(reportsTable)
        .upsert(reportRow, onConflict: 'id', ignoreDuplicates: true);
    if (photoRows.isEmpty) return;
    await _client
        .from(photosTable)
        .upsert(
          photoRows,
          onConflict: 'report_id,photo_slot',
          ignoreDuplicates: true,
        );
  }

  @override
  Future<bool> finalizeReport({
    required String functionName,
    required String reportId,
  }) async {
    final result = await _client.rpc<bool>(
      functionName,
      params: {'p_report_id': reportId},
    );
    return result == true;
  }
}
