import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';

/// Resolves the best available product image URL for a given product.
///
/// Priority:
///   1. Local cache hit (user_data.db product_image_cache)
///   2. Open Food Facts API lookup by UPC barcode
///   3. null → caller renders BrandedPlaceholder
///
/// Caching:
///   - Positive results (real URL): 30 days
///   - Negative results ("no_image"): 7 days
///   - Network errors: not cached (retry next time)
///
/// Rate limiting: max 2 concurrent OFF requests via semaphore.
class ProductImageResolver {
  ProductImageResolver(this._userDb, {http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final UserDatabase _userDb;
  final http.Client _http;

  static const _offBaseUrl = 'https://world.openfoodfacts.org/api/v2/product';
  static const _userAgent = 'PharmaGuide/1.0 (supplement-safety-app)';
  static const _noImageMarker = 'no_image';
  static const _positiveTtl = Duration(days: 30);
  static const _negativeTtl = Duration(days: 7);
  static const _requestTimeout = Duration(seconds: 8);

  /// Simple semaphore — max 2 concurrent OFF requests across the whole
  /// app, enforced via static fields so every resolver instance shares
  /// the same rate-limit budget. Tests that create fresh resolvers must
  /// call [resetSemaphore] in tearDown to clear pending completers.
  static int _activeRequests = 0;
  static final _queue = <Completer<void>>[];

  /// Reset semaphore state — call in test tearDown to prevent leaks.
  static void resetSemaphore() {
    _activeRequests = 0;
    for (final c in _queue) {
      c.complete();
    }
    _queue.clear();
  }

  /// Returns the best image URL for a product, or null for placeholder.
  Future<String?> resolve(String dsldId, String? upc) async {
    // 1. Check cache
    final cached = await _userDb.getCachedImage(dsldId);
    if (cached != null) {
      final age = DateTime.now().difference(cached.cachedAt);
      final isNegative = cached.imageUrl == _noImageMarker;
      final ttl = isNegative ? _negativeTtl : _positiveTtl;
      if (age < ttl) {
        return isNegative ? null : cached.imageUrl;
      }
      // Cache expired — fall through to re-query
    }

    // 2. No UPC → can't query OFF
    if (upc == null || upc.trim().isEmpty) {
      await _userDb.cacheImageUrl(dsldId, _noImageMarker);
      return null;
    }

    // 3. Query OFF API (rate-limited)
    try {
      await _acquireSemaphore();
      try {
        return await _queryOff(
        dsldId,
        upc.replaceAll(RegExp(r'[^0-9]'), ''),
      );
      } finally {
        _releaseSemaphore();
      }
    } on Exception {
      // Network error — don't cache, allow retry next time
      return null;
    }
  }

  Future<String?> _queryOff(String dsldId, String upc) async {
    final uri = Uri.parse(
      '$_offBaseUrl/$upc.json'
      '?fields=code,product_name,image_front_url,image_front_small_url',
    );

    final response = await _http
        .get(uri, headers: {'User-Agent': _userAgent})
        .timeout(_requestTimeout);

    if (response.statusCode != 200) {
      await _userDb.cacheImageUrl(dsldId, _noImageMarker);
      return null;
    }

    final decoded = json.decode(response.body);
    if (decoded is! Map) {
      await _userDb.cacheImageUrl(dsldId, _noImageMarker);
      return null;
    }
    final body = decoded is Map<String, dynamic>
        ? decoded
        : Map<String, dynamic>.from(decoded);
    final statusRaw = body['status'];
    final status = statusRaw is num ? statusRaw.toInt() : 0;

    if (status != 1) {
      await _userDb.cacheImageUrl(dsldId, _noImageMarker);
      return null;
    }

    final productRaw = body['product'];
    if (productRaw is! Map<String, dynamic>) {
      await _userDb.cacheImageUrl(dsldId, _noImageMarker);
      return null;
    }
    final imageUrlRaw = productRaw['image_front_url'];
    final imageUrl = imageUrlRaw is String ? imageUrlRaw : null;

    if (imageUrl == null || imageUrl.isEmpty) {
      await _userDb.cacheImageUrl(dsldId, _noImageMarker);
      return null;
    }

    await _userDb.cacheImageUrl(dsldId, imageUrl);
    return imageUrl;
  }

  // ---------------------------------------------------------------------------
  // Semaphore — limits concurrent OFF requests to 2
  // ---------------------------------------------------------------------------

  static Future<void> _acquireSemaphore() async {
    if (_activeRequests < 2) {
      _activeRequests++;
      return;
    }
    final completer = Completer<void>();
    _queue.add(completer);
    await completer.future;
  }

  static void _releaseSemaphore() {
    if (_queue.isNotEmpty) {
      _queue.removeAt(0).complete();
    } else {
      _activeRequests--;
    }
  }
}

/// Provides a singleton [ProductImageResolver].
final productImageResolverProvider = Provider<ProductImageResolver>((ref) {
  final userDb = ref.read(userDatabaseProvider);
  return ProductImageResolver(userDb);
});
