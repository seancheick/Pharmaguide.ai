import 'dart:convert';
import 'package:pharmaguide/data/supabase/supabase_client.dart';
import 'package:pharmaguide/data/supabase/supabase_contract.dart';

/// Fetches detail blobs from Supabase Storage on demand.
///
/// The pipeline uploads blobs to a content-addressed path:
///   `{bucket}/{blobPrefix}/{sha256[0:2]}/{sha256}.json`
///
/// The product's `detail_blob_sha256` column in `products_core` provides
/// the hash. Callers must pass the SHA-256 hash, not the dsld_id.
class DetailBlobService {
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
      final bytes = await supabase.storage
          .from(SupabaseContract.storageBucket)
          .download('${SupabaseContract.blobPrefix}/$prefix/$sha256.json');
      final json = utf8.decode(bytes);
      final decoded = jsonDecode(json);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return null;
    } on Object {
      return null;
    }
  }
}
