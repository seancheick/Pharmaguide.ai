import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:pharmaguide/core/utils/retry.dart';
import 'package:pharmaguide/data/supabase/supabase_client.dart';
import 'package:pharmaguide/data/supabase/supabase_contract.dart';
import 'package:pharmaguide/services/crash_reporting_service.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Thrown when a public-CDN fetch is denied with a status that indicates
/// the bucket prefix is not (yet) publicly readable — the caller should
/// fall back to the authed Supabase `.download()` path instead of
/// retrying, because retries will never succeed.
class PublicFetchDeniedException implements Exception {
  final int statusCode;
  const PublicFetchDeniedException(this.statusCode);

  static const deniedStatuses = {400, 401, 403, 404};

  @override
  String toString() =>
      'PublicFetchDeniedException: public storage fetch denied '
      '(HTTP $statusCode)';
}

/// A product declares a detail blob, but the app could not obtain and verify
/// it. This is deliberately distinct from a product that declares no blob.
class DetailBlobUnavailableException implements Exception {
  const DetailBlobUnavailableException(this.reason, [this.cause]);

  /// Reason used when the device has no usable network at all. Kept as a
  /// named constant because `beforeSend` in CrashReportingService matches
  /// it to drop expected-offline noise; `test/detail_blob_offline_test.dart`
  /// pins the two together.
  static const offlineReason = 'device offline';

  final String reason;
  final Object? cause;

  /// True when this failure is "the device has no network", not a defect.
  ///
  /// Offline is an expected state. The caller still surfaces an explicit
  /// unavailable state — a failed clinical fetch must never read as "this
  /// product has no warnings" — but it is not reported to Sentry as an error.
  bool get isOffline =>
      reason == offlineReason || detailBlobCauseIsNetworkFailure(cause);

  @override
  String toString() => 'DetailBlobUnavailableException: $reason';
}

/// True when [cause] means the request never reached the network.
///
/// Deliberately excludes [TimeoutException]: a timeout can indicate a slow
/// or degraded CDN, which IS worth reporting.
bool detailBlobCauseIsNetworkFailure(Object? cause) =>
    cause is SocketException || cause is http.ClientException;

/// Fetches detail blobs from Supabase Storage on demand.
///
/// The pipeline uploads blobs to a content-addressed path:
///   `{bucket}/{blobPrefix}/{sha256[0:2]}/{sha256}.json`
///
/// Blobs are content-addressed and immutable, so they are fetched via the
/// public CDN URL (cacheable, no auth handshake) with a fallback to the
/// authed `.download()` path while the bucket prefix is not yet public.
///
/// The product's `detail_blob_sha256` column in `products_core` provides
/// the hash. Callers must pass the SHA-256 hash, not the dsld_id.
class DetailBlobService {
  DetailBlobService({http.Client Function()? httpClientFactory, this.isOffline})
    : _httpClientFactory = httpClientFactory ?? http.Client.new;

  final http.Client Function() _httpClientFactory;

  /// Optional predicate: when the device is known-offline we skip the network
  /// entirely rather than burning the retry budget. Mirrors the guard already
  /// used by StackSyncQueue.
  ///
  /// A plain predicate rather than a ConnectivityService reference: it keeps
  /// this data-layer class free of a platform-channel-backed service, so unit
  /// tests can drive it without a Flutter binding. Null means "unknown" and
  /// the fetch proceeds — failing open, never suppressing a real fetch.
  final bool Function()? isOffline;

  static const _fetchTimeout = Duration(seconds: 10);

  /// Fetch detail blob by SHA-256 hash.
  ///
  /// Path: `shared/details/sha256/{sha256[0:2]}/{sha256}.json`
  /// Bucket: `pharmaguide`
  ///
  /// Returns a verified JSON object. Any fetch, integrity, or decoding failure
  /// throws [DetailBlobUnavailableException]; callers must not interpret a
  /// failed clinical-data fetch as "this product has no detail data".
  Future<Map<String, dynamic>?> fetchDetailBlobByHash(String sha256) async {
    if (sha256.length < 3) {
      throw const DetailBlobUnavailableException('invalid content hash');
    }
    try {
      final prefix = sha256.substring(0, 2);
      final path = '${SupabaseContract.blobPrefix}/$prefix/$sha256.json';
      final bytes = await _fetchBlobBytes(path);
      // Integrity gate: the path is content-addressed, but the path only
      // names what we ASKED for — the response is unauthenticated CDN
      // bytes. Verify sha256(bytes) against the products_core hash BEFORE
      // parsing; a mismatch (mis-served / stale / tampered object) is a
      // fetch failure: nothing is parsed, nothing reaches FitScore or the
      // warnings engine, nothing is cached.
      if (!detailBlobBytesMatchSha256(bytes, sha256)) {
        throw const DetailBlobUnavailableException(
          'content hash verification failed',
        );
      }
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      throw const DetailBlobUnavailableException(
        'detail payload is not a JSON object',
      );
    } on DetailBlobUnavailableException catch (error, stackTrace) {
      _reportUnavailable(error, stackTrace);
      rethrow;
    } on Object catch (error, stackTrace) {
      final unavailable = DetailBlobUnavailableException(
        'fetch or decoding failed',
        error,
      );
      _reportUnavailable(unavailable, stackTrace);
      throw unavailable;
    }
  }

  /// Offline is an expected state, not a defect: breadcrumb only, so the
  /// Sentry issue list stays a list of real bugs. Every other failure —
  /// including hash-verification failure, which is a tampered/stale-object
  /// signal — is still reported as an error.
  void _reportUnavailable(
    DetailBlobUnavailableException error,
    StackTrace stackTrace,
  ) {
    if (error.isOffline) {
      CrashReportingService().log(
        'detail blob unavailable while offline — surfacing unavailable state',
      );
      return;
    }
    CrashReportingService().recordError(
      error,
      stackTrace,
      fatal: false,
      hint: 'detail_blob:unavailable',
    );
  }

  /// Public CDN fetch (retried, 10s per-attempt timeout) with authed
  /// `.download()` fallback when the CDN denies the request (bucket
  /// prefix not yet flipped to public in the Supabase dashboard).
  ///
  /// Returns the RAW bytes — the caller verifies the SHA-256 against the
  /// content-addressed hash before decoding, on BOTH paths.
  Future<Uint8List> _fetchBlobBytes(String path) async {
    // Known-offline: fail immediately. Retrying a socket that cannot open
    // costs the user ~3-5s of spinner and emits one error span per attempt,
    // for an outcome we already know.
    if (isOffline?.call() ?? false) {
      throw const DetailBlobUnavailableException(
        DetailBlobUnavailableException.offlineReason,
      );
    }
    try {
      return await retryWithBackoff(
        () => _publicGet(path),
        timeout: _fetchTimeout,
        // A denied public fetch will never succeed on retry; neither will a
        // socket failure on a device whose connectivity stream has not yet
        // flipped to offline. Both fail fast.
        retryIf: (e) =>
            e is! PublicFetchDeniedException &&
            !detailBlobCauseIsNetworkFailure(e),
      );
    } on PublicFetchDeniedException catch (e) {
      // Expected until the dashboard makes shared/details/ public — fall
      // back to the authed path so nothing breaks. Breadcrumb only.
      CrashReportingService().log(
        'detail blob public CDN fetch denied (HTTP ${e.statusCode}) — '
        'falling back to authed download',
      );
      final span = _startDependencySpan(
        operation: 'http.client',
        description: 'GET Supabase detail blob fallback',
        surface: 'detail_blob_authed',
      );
      SpanStatus status = const SpanStatus.ok();
      try {
        final bytes = await retryWithBackoff(() async {
          try {
            final downloaded = await supabase.storage
                .from(SupabaseContract.storageBucket)
                .download(path);
            status = const SpanStatus.ok();
            span?.setData('http.response.body.size', downloaded.length);
            span?.throwable = null;
            return downloaded;
          } on Object catch (error) {
            status = _spanStatusForError(error);
            span?.throwable = error;
            rethrow;
          }
        }, timeout: _fetchTimeout);
        return bytes;
      } finally {
        _finishDependencySpan(span, status);
      }
    }
  }

  Future<Uint8List> _publicGet(String path) async {
    final url = supabase.storage
        .from(SupabaseContract.storageBucket)
        .getPublicUrl(path);
    final client = _httpClientFactory();
    final span = _startDependencySpan(
      operation: 'http.client',
      description: 'GET Supabase detail blob public',
      surface: 'detail_blob_public',
    );
    SpanStatus status = const SpanStatus.ok();
    try {
      final response = await client.get(Uri.parse(url)).timeout(_fetchTimeout);
      status = SpanStatus.fromHttpStatusCode(response.statusCode);
      span
        ?..setData('http.response.status_code', response.statusCode)
        ..setData('http.response.body.size', response.bodyBytes.length);
      if (PublicFetchDeniedException.deniedStatuses.contains(
        response.statusCode,
      )) {
        throw PublicFetchDeniedException(response.statusCode);
      }
      if (response.statusCode != 200) {
        // 5xx / 429 etc. — retryable.
        throw http.ClientException(
          'detail blob fetch failed: HTTP ${response.statusCode}',
        );
      }
      return response.bodyBytes;
    } on Object catch (error) {
      status = _spanStatusForError(error, fallback: status);
      span?.throwable = error;
      rethrow;
    } finally {
      _finishDependencySpan(span, status);
      client.close();
    }
  }
}

/// PURE integrity gate for fetched detail blobs: true only when the
/// SHA-256 of [bytes] equals [expectedSha256] (hex, case-insensitive,
/// surrounding whitespace tolerated).
///
/// Applied by [DetailBlobService.fetchDetailBlobByHash] to the raw bytes
/// of BOTH the public-CDN and authed-fallback paths before any parsing —
/// the content-addressed path names what was requested, not what was
/// served.
@visibleForTesting
bool detailBlobBytesMatchSha256(List<int> bytes, String expectedSha256) {
  return crypto.sha256.convert(bytes).toString() ==
      expectedSha256.trim().toLowerCase();
}

ISentrySpan? _startDependencySpan({
  required String operation,
  required String description,
  required String surface,
}) {
  try {
    final parent = Sentry.getSpan();
    final span =
        parent?.startChild(operation, description: description) ??
        Sentry.startTransaction(description, operation, bindToScope: false);
    span
      ..setTag('pg.surface', surface)
      ..setData('server.address', Uri.parse(SupabaseConfig.url).host)
      ..setData('storage.bucket', SupabaseContract.storageBucket)
      ..setData('http.request.method', 'GET');
    return span;
  } on Object {
    return null;
  }
}

void _finishDependencySpan(ISentrySpan? span, SpanStatus status) {
  if (span == null || span.finished) return;
  unawaited(span.finish(status: status));
}

SpanStatus _spanStatusForError(Object error, {SpanStatus? fallback}) {
  if (error is TimeoutException) return const SpanStatus.deadlineExceeded();
  if (error is PublicFetchDeniedException) {
    return SpanStatus.fromHttpStatusCode(error.statusCode);
  }
  return fallback == const SpanStatus.ok()
      ? const SpanStatus.unknownError()
      : fallback ?? const SpanStatus.unknownError();
}
