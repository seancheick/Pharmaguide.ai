import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:pharmaguide/data/database/tables/detail_cache_table.dart';
import 'package:pharmaguide/data/database/tables/scan_history_table.dart';
import 'package:pharmaguide/data/database/tables/user_favorites_table.dart';
import 'package:pharmaguide/data/database/tables/user_profile_table.dart';
import 'package:pharmaguide/data/database/tables/product_image_cache_table.dart';
import 'package:pharmaguide/data/database/tables/user_stacks_table.dart';

part 'user_database.g.dart';

/// READ-WRITE database for user-owned data: profile, stack, favorites,
/// scan history, and detail cache. Created locally on first launch.
@DriftDatabase(
  tables: [
    UserProfiles,
    UserStacksLocal,
    UserFavorites,
    ScanHistory,
    DetailCache,
    ProductImageCache,
  ],
)
class UserDatabase extends _$UserDatabase {
  UserDatabase(File dbFile)
    : super(NativeDatabase(dbFile, logStatements: false));

  /// In-memory database for testing.
  UserDatabase.memory() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        // v2: add generic_rxcui + ingredient_rxcuis for brand→generic
        // interaction matching and combination drug decomposition.
        await m.addColumn(userStacksLocal, userStacksLocal.genericRxcui);
        await m.addColumn(userStacksLocal, userStacksLocal.ingredientRxcuisCol);
      }
      if (from < 3) {
        // v3: product image cache for OFF API lookups.
        await m.createTable(productImageCache);
      }
      if (from == 3) {
        // v4: clear stale image cache — prior UPC sanitization bug
        // sent malformed barcodes to OFF, caching false negatives.
        // Scoped to `from == 3` only: users on v1/v2 never had the
        // buggy cache, and fresh installs created the table at v4
        // with no rows to clear.
        await customStatement('DELETE FROM product_image_cache');
      }
      if (from < 5) {
        // v5: add profile_flags column to user_profile for v6.0
        // profile_gate evaluation (post_op_recovery, hypoglycemia_history,
        // bleeding_history). Defaults to empty JSON array; existing
        // pregnant/breastfeeding/ttc/surgery_scheduled are still derived
        // from conditions[] for backward compatibility.
        await m.addColumn(userProfiles, userProfiles.profileFlags);
      }
    },
  );

  /// Open (or create) the user database at the given path.
  static UserDatabase open(String dbPath) {
    return UserDatabase(File(dbPath));
  }

  // ---------------------------------------------------------------------------
  // Profile
  // ---------------------------------------------------------------------------

  /// Returns the single user profile, or null if none exists yet.
  Future<UserProfile?> getProfile() {
    return (select(userProfiles)..limit(1)).getSingleOrNull();
  }

  /// Insert or update the user profile (upsert on id conflict).
  Future<int> saveProfile(UserProfilesCompanion profile) {
    return into(userProfiles).insertOnConflictUpdate(profile);
  }

  // ---------------------------------------------------------------------------
  // Stack
  // ---------------------------------------------------------------------------

  /// Returns all non-deleted stack items, newest first.
  Future<List<UserStacksLocalData>> getActiveStack() {
    return (select(userStacksLocal)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([
            (t) => OrderingTerm(expression: t.addedAt, mode: OrderingMode.desc),
          ]))
        .get();
  }

  /// Returns the active (non-deleted) stack entry for a given DSLD product
  /// id, or null if the user has not added that product to their stack.
  ///
  /// Used by the product detail screen to show the refill-reminder card —
  /// the card needs the entry's `addedAt` to compute days remaining.
  Future<UserStacksLocalData?> findStackEntryByDsldId(String dsldId) {
    return (select(userStacksLocal)
          ..where((t) => t.dsldId.equals(dsldId) & t.deletedAt.isNull())
          ..limit(1))
        .getSingleOrNull();
  }

  /// Add a supplement or medication to the stack.
  Future<void> addToStack(UserStacksLocalCompanion item) {
    return into(userStacksLocal).insert(item);
  }

  /// Soft-delete a stack item by setting [deletedAt].
  Future<void> removeFromStack(String id) {
    return (update(userStacksLocal)..where((t) => t.id.equals(id))).write(
      UserStacksLocalCompanion(
        deletedAt: Value(DateTime.now()),
        clientUpdatedAt: Value(DateTime.now()),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Favorites
  // ---------------------------------------------------------------------------

  /// Returns all favorites, newest first.
  Future<List<UserFavorite>> getFavorites() {
    return (select(userFavorites)..orderBy([
          (t) => OrderingTerm(expression: t.addedAt, mode: OrderingMode.desc),
        ]))
        .get();
  }

  /// Bookmark a product by DSLD ID.
  Future<void> addFavorite(String dsldId) {
    return into(
      userFavorites,
    ).insert(UserFavoritesCompanion(dsldId: Value(dsldId)));
  }

  /// Remove a product bookmark.
  Future<void> removeFavorite(String dsldId) {
    return (delete(userFavorites)..where((t) => t.dsldId.equals(dsldId))).go();
  }

  // ---------------------------------------------------------------------------
  // Scan History
  // ---------------------------------------------------------------------------

  /// Record a barcode scan. Duplicate dsld_ids create new rows (each scan
  /// is a distinct event). The table is capped at 50 rows — oldest rows
  /// are pruned after insert to keep storage bounded.
  Future<void> recordScanEvent({
    required String dsldId,
    String? upcSku,
    String? productName,
  }) async {
    await into(scanHistory).insert(
      ScanHistoryCompanion(
        dsldId: Value(dsldId),
        upcSku: Value(upcSku),
        productName: Value(productName),
      ),
    );

    // Prune old rows beyond the 50-row cap.
    await customStatement(
      'DELETE FROM user_scan_history '
      'WHERE id NOT IN ('
      '  SELECT id FROM user_scan_history ORDER BY scanned_at DESC LIMIT 50'
      ')',
    );
  }

  /// Returns the most recent scans (unique products), newest first.
  /// De-duplicates by dsld_id, keeping only the latest scan per product.
  Future<List<ScanHistoryData>> getRecentScans({int limit = 10}) async {
    final rows = await customSelect(
      'SELECT * FROM user_scan_history '
      'WHERE id IN ('
      '  SELECT MAX(id) FROM user_scan_history GROUP BY dsld_id'
      ') '
      'ORDER BY scanned_at DESC '
      'LIMIT ?',
      variables: [Variable.withInt(limit)],
      readsFrom: {scanHistory},
    ).get();
    return rows.map((r) => scanHistory.map(r.data)).toList();
  }

  // ---------------------------------------------------------------------------
  // Detail Cache
  // ---------------------------------------------------------------------------

  /// Retrieve a cached detail blob by DSLD ID, or null if not cached.
  Future<DetailCacheData?> getCachedDetail(String dsldId) {
    return (select(
      detailCache,
    )..where((t) => t.dsldId.equals(dsldId))).getSingleOrNull();
  }

  /// Cache (or refresh) a product detail blob.
  Future<void> cacheDetail(String dsldId, String json, String? sha256Hash) {
    return into(detailCache).insertOnConflictUpdate(
      DetailCacheCompanion(
        dsldId: Value(dsldId),
        blobJson: Value(json),
        sha256: Value(sha256Hash),
        cachedAt: Value(DateTime.now()),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Product Image Cache (OFF API lookups)
  // ---------------------------------------------------------------------------

  /// Returns the cached image entry for a product, or null if not cached.
  Future<ProductImageCacheData?> getCachedImage(String dsldId) {
    return (select(
      productImageCache,
    )..where((t) => t.dsldId.equals(dsldId))).getSingleOrNull();
  }

  /// Cache (or refresh) a product image URL. Use "no_image" as [imageUrl]
  /// to mark a negative lookup (product has no image on OFF).
  Future<void> cacheImageUrl(String dsldId, String imageUrl) {
    return into(productImageCache).insertOnConflictUpdate(
      ProductImageCacheCompanion(
        dsldId: Value(dsldId),
        imageUrl: Value(imageUrl),
        cachedAt: Value(DateTime.now()),
      ),
    );
  }
}
