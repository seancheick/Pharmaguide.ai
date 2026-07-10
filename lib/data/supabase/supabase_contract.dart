/// Single source of truth for Supabase bucket names, storage paths,
/// and table names. Both the Flutter app and the pipeline use these
/// exact values — any mismatch causes silent fetch failures.
///
/// Pipeline equivalents (sync_to_supabase.py):
///   BUCKET          = "pharmaguide"
///   BLOB_PREFIX     = "shared/details/sha256"
///   DB_PATH         = "v{version}/pharmaguide_core.db"
///   DETAIL_INDEX    = "v{version}/detail_index.json"
///   MANIFEST_TABLE  = "export_manifest"
///
/// If the pipeline changes any of these, update this file and the
/// corresponding pipeline constant simultaneously.
abstract final class SupabaseContract {
  // ---- Storage ----

  /// The Supabase Storage bucket used for pipeline artifacts (core DB,
  /// detail blobs, manifest).
  static const storageBucket = 'pharmaguide';

  /// The Supabase Storage bucket used for product images. This is a
  /// SEPARATE bucket from [storageBucket] — image fetches must use this
  /// constant, not concatenate 'product-images/' as a path prefix inside
  /// [storageBucket]. Future image-fetch wiring should read this value.
  static const productImageBucket = 'product-images';

  /// Prefix for content-addressed detail blobs.
  /// Full path: `{blobPrefix}/{sha256[0:2]}/{sha256}.json`
  static const blobPrefix = 'shared/details/sha256';

  /// Core DB path pattern. Replace `{version}` with the db_version string.
  /// Full path: `v{version}/pharmaguide_core.db`
  static String coreDbPath(String version) => 'v$version/pharmaguide_core.db';

  /// Detail index path pattern.
  static String detailIndexPath(String version) =>
      'v$version/detail_index.json';

  /// Product image object key inside the [productImageBucket] bucket.
  /// NOTE: the returned value is the object path *within* the bucket —
  /// callers must target [productImageBucket], not [storageBucket].
  /// Full URL: `{productImageBucket}/{dsldId}.webp`
  static String productImagePath(String dsldId) => '$dsldId.webp';

  // ---- Tables ----

  /// Pipeline manifest table — tracks current DB version.
  static const manifestTable = 'export_manifest';

  /// User supplement/medication stack — synced between devices.
  static const userStacksTable = 'user_stacks';

  /// Product-state identity used by every PostgREST user-stack upsert. The
  /// database enforces this as a full UNIQUE constraint, not a partial index.
  static const userStacksProductConflictTarget = 'user_id,dsld_id';

  // ---- RPC ----

  /// Atomically rotates the current manifest row.
  static const rotateManifestRpc = 'rotate_manifest';
}
