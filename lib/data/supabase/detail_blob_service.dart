import 'dart:convert';
import 'package:pharmaguide/data/supabase/supabase_client.dart';

/// Fetches detail blobs from Supabase on demand.
class DetailBlobService {
  /// Fetch a detail blob by DSLD ID.
  /// Returns parsed JSON map or null if not found.
  ///
  /// Catches broadly ([Object]) because Supabase storage can throw
  /// StorageException, FormatException, network errors, or type-cast
  /// failures — all of which should map to "no blob available" so the
  /// caller falls back to the bundled data.
  Future<Map<String, dynamic>?> fetchDetailBlob(String dsldId) async {
    try {
      final bytes = await supabase.storage
          .from('detail-blobs')
          .download('$dsldId.json');
      final json = utf8.decode(bytes);
      return jsonDecode(json) as Map<String, dynamic>;
    } on Object {
      return null;
    }
  }

  /// Fetch detail blob by SHA-256 hash (for hashed storage paths).
  Future<Map<String, dynamic>?> fetchDetailBlobByHash(String sha256) async {
    try {
      final prefix = sha256.substring(0, 2);
      final bytes = await supabase.storage
          .from('detail-blobs')
          .download('$prefix/$sha256.json');
      final json = utf8.decode(bytes);
      return jsonDecode(json) as Map<String, dynamic>;
    } on Object {
      return null;
    }
  }
}
