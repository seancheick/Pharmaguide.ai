import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:pharmaguide/core/utils/retry.dart';
import 'package:pharmaguide/data/supabase/supabase_client.dart';
import 'package:pharmaguide/data/supabase/supabase_contract.dart';
import 'package:pharmaguide/services/crash_reporting_service.dart';

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
  DetailBlobService({http.Client Function()? httpClientFactory})
    : _httpClientFactory = httpClientFactory ?? http.Client.new;

  final http.Client Function() _httpClientFactory;

  static const _fetchTimeout = Duration(seconds: 10);

  /// Fetch detail blob by SHA-256 hash.
  ///
  /// Path: `shared/details/sha256/{sha256[0:2]}/{sha256}.json`
  /// Bucket: `pharmaguide`
  ///
  /// Returns parsed JSON map or null if not found / network error.
  Future<Map<String, dynamic>?> fetchDetailBlobByHash(String sha256) async {
    if (sha256.length < 3) return null;
    try {
      final prefix = sha256.substring(0, 2);
      final path = '${SupabaseContract.blobPrefix}/$prefix/$sha256.json';
      final json = await _fetchBlobJson(path);
      final decoded = jsonDecode(json);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return null;
    } on Object {
      return null;
    }
  }

  /// Public CDN fetch (retried, 10s per-attempt timeout) with authed
  /// `.download()` fallback when the CDN denies the request (bucket
  /// prefix not yet flipped to public in the Supabase dashboard).
  Future<String> _fetchBlobJson(String path) async {
    try {
      return await retryWithBackoff(
        () => _publicGet(path),
        timeout: _fetchTimeout,
        retryIf: (e) => e is! PublicFetchDeniedException,
      );
    } on PublicFetchDeniedException catch (e) {
      // Expected until the dashboard makes shared/details/ public — fall
      // back to the authed path so nothing breaks. Breadcrumb only.
      CrashReportingService().log(
        'detail blob public CDN fetch denied (HTTP ${e.statusCode}) — '
        'falling back to authed download',
      );
      final bytes = await retryWithBackoff(
        () => supabase.storage
            .from(SupabaseContract.storageBucket)
            .download(path),
        timeout: _fetchTimeout,
      );
      return utf8.decode(bytes);
    }
  }

  Future<String> _publicGet(String path) async {
    final url = supabase.storage
        .from(SupabaseContract.storageBucket)
        .getPublicUrl(path);
    final client = _httpClientFactory();
    try {
      final response = await client.get(Uri.parse(url)).timeout(_fetchTimeout);
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
      return utf8.decode(response.bodyBytes);
    } finally {
      client.close();
    }
  }
}
