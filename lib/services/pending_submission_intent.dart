import 'dart:async';
import 'dart:convert';

import 'package:pharmaguide/services/gtin.dart';
import 'package:pharmaguide/services/product_submission_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum PendingSubmissionIntentKind {
  missingProduct('missing_product'),
  labelMismatch('label_mismatch');

  const PendingSubmissionIntentKind(this.wireValue);

  final String wireValue;

  static PendingSubmissionIntentKind? fromWireValue(Object? value) {
    for (final kind in values) {
      if (kind.wireValue == value) return kind;
    }
    return null;
  }
}

/// A typed, one-shot action that can safely resume after authentication.
class PendingSubmissionIntentValue {
  const PendingSubmissionIntentValue.missingProduct(String upc)
    : kind = PendingSubmissionIntentKind.missingProduct,
      identifier = upc,
      submissionIdentifier = null,
      submissionId = null,
      resubmissionOf = null;

  const PendingSubmissionIntentValue.labelMismatch(String dsldId)
    : kind = PendingSubmissionIntentKind.labelMismatch,
      identifier = dsldId,
      submissionIdentifier = null,
      submissionId = null,
      resubmissionOf = null;

  const PendingSubmissionIntentValue.alternateProduct(
    this.submissionIdentifier,
    this.submissionId, {
    this.resubmissionOf,
  }) : kind = PendingSubmissionIntentKind.missingProduct,
       identifier = '';
  final ProductSubmissionIdentifier? submissionIdentifier;
  final String? submissionId;
  final String? resubmissionOf;
  final PendingSubmissionIntentKind kind;
  final String identifier;
}

/// Dispatches a consumed intent without coupling persistence to Flutter UI.
/// A label-mismatch intent is deliberately dropped when its catalog product
/// no longer exists; reopening a report against an unverified identity would
/// attach evidence to the wrong record.
Future<void> routePendingSubmissionIntent<T>(
  PendingSubmissionIntentValue intent, {
  required FutureOr<void> Function(String upc) openMissingProduct,
  FutureOr<void> Function(
    ProductSubmissionIdentifier identifier,
    String submissionId,
  )?
  openAlternateProduct,
  required Future<T?> Function(String dsldId) resolveLabelMismatch,
  required FutureOr<void> Function(T product) openLabelMismatch,
}) async {
  switch (intent.kind) {
    case PendingSubmissionIntentKind.missingProduct:
      if (intent.submissionIdentifier != null) {
        await openAlternateProduct?.call(
          intent.submissionIdentifier!,
          intent.submissionId!,
        );
      } else {
        await openMissingProduct(intent.identifier);
      }
    case PendingSubmissionIntentKind.labelMismatch:
      final product = await resolveLabelMismatch(intent.identifier);
      if (product != null) await openLabelMismatch(product);
  }
}

/// Persists a submission action while a signed-out user authenticates.
///
/// The global auth listener replaces the current route after sign-in, and a
/// magic link may restart the app. This small typed intent survives both.
/// Consumption is one-shot and TTL-bounded so stale UI never appears later.
class PendingSubmissionIntent {
  static const storageKey = 'pg_pending_submission_intent';
  static const ttl = Duration(minutes: 60);

  static Future<void> saveAlternateProduct(
    ProductSubmissionIdentifier identifier,
    String submissionId, {
    String? resubmissionOf,
    DateTime Function()? now,
  }) async {
    final id = normalizeProductSubmissionId(submissionId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      storageKey,
      jsonEncode({
        'kind': 'missing_product',
        'identifier': identifier.toJson(),
        'submission_id': id,
        if (resubmissionOf != null)
          'resubmission_of': normalizeProductSubmissionId(resubmissionOf),
        'created_at': (now ?? DateTime.now)().toUtc().toIso8601String(),
      }),
    );
  }

  static Future<void> saveMissingProduct(
    String upc, {
    DateTime Function()? now,
  }) async {
    try {
      final identity = GtinIdentity.parse(upc);
      await _save(
        PendingSubmissionIntentKind.missingProduct,
        field: 'upc',
        identifier: identity.submissionIdentity,
        now: now,
      );
    } on FormatException {
      return;
    }
  }

  static Future<void> saveLabelMismatch(
    String dsldId, {
    DateTime Function()? now,
  }) async {
    final normalized = dsldId.trim();
    if (!LabelMismatchProductMetadata.isValidCatalogId(normalized)) return;
    await _save(
      PendingSubmissionIntentKind.labelMismatch,
      field: 'dsld_id',
      identifier: normalized,
      now: now,
    );
  }

  static Future<void> _save(
    PendingSubmissionIntentKind kind, {
    required String field,
    required String identifier,
    DateTime Function()? now,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      storageKey,
      jsonEncode({
        'kind': kind.wireValue,
        field: identifier,
        'created_at': (now ?? DateTime.now)().toUtc().toIso8601String(),
      }),
    );
  }

  /// Returns the pending action exactly once, or null when absent, expired,
  /// or malformed. Payloads written before `kind` existed remain compatible
  /// and are interpreted as missing-product intents.
  static Future<PendingSubmissionIntentValue?> consume({
    DateTime Function()? now,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    if (raw == null) return null;
    await prefs.remove(storageKey);

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final createdAtRaw = decoded['created_at'];
      if (createdAtRaw is! String) return null;
      final createdAt = DateTime.tryParse(createdAtRaw)?.toUtc();
      if (createdAt == null) return null;
      final age = (now ?? DateTime.now)().toUtc().difference(createdAt);
      if (age.isNegative || age > ttl) return null;

      // `kind` was absent in the first shipped payload. Preserve that one
      // compatibility path; unknown explicit kinds fail closed.
      final kind = decoded.containsKey('kind')
          ? PendingSubmissionIntentKind.fromWireValue(decoded['kind'])
          : PendingSubmissionIntentKind.missingProduct;
      if (kind == null) return null;

      switch (kind) {
        case PendingSubmissionIntentKind.missingProduct:
          if (decoded['identifier'] is Map) {
            return PendingSubmissionIntentValue.alternateProduct(
              ProductSubmissionIdentifier.fromJson(
                Map<String, dynamic>.from(decoded['identifier'] as Map),
              ),
              normalizeProductSubmissionId(decoded['submission_id'] as String),
              resubmissionOf: decoded['resubmission_of'] == null
                  ? null
                  : normalizeProductSubmissionId(
                      decoded['resubmission_of'] as String,
                    ),
            );
          }
          final upc = decoded['upc'];
          if (upc is! String) return null;
          try {
            return PendingSubmissionIntentValue.missingProduct(
              GtinIdentity.parse(upc).submissionIdentity,
            );
          } on FormatException {
            return null;
          }
        case PendingSubmissionIntentKind.labelMismatch:
          final dsldId = decoded['dsld_id'];
          if (dsldId is! String ||
              !LabelMismatchProductMetadata.isValidCatalogId(dsldId)) {
            return null;
          }
          return PendingSubmissionIntentValue.labelMismatch(dsldId);
      }
    } on Object {
      return null;
    }
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(storageKey);
  }
}
