import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:pharmaguide/data/database/tables/detail_cache_table.dart';
import 'package:pharmaguide/data/database/tables/failed_scans_table.dart';
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
    FailedScans,
  ],
)
class UserDatabase extends _$UserDatabase {
  UserDatabase(File dbFile)
    : super(NativeDatabase(dbFile, logStatements: false));

  /// In-memory database for testing.
  UserDatabase.memory() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 8;

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
      if (from < 6) {
        // v6: failed-scan queue for the Layer 4 missing-UPC sensor. Holds
        // only the UPC + aggregate counts; no user identifier. See the
        // privacy contract in failed_scans_table.dart.
        await m.createTable(failedScans);
      }
      if (from < 7) {
        // v7: preserve terminal stack-sync failures locally so an unchanged
        // row cannot retry and emit the same non-fatal crash on every sync
        // trigger. A newer client_updated_at automatically re-enters it.
        await m.addColumn(userStacksLocal, userStacksLocal.syncBlockedAt);
      }
      if (from < 8) {
        // v8: retain the non-health catalog version identifiers that were
        // shown when a scan was recorded. Existing history remains valid
        // with null lineage values.
        await m.addColumn(scanHistory, scanHistory.formulaFingerprint);
        await m.addColumn(scanHistory, scanHistory.catalogSourceVersion);
      }
    },
    beforeOpen: (details) async {
      // WAL keeps readers from blocking on writes (e.g. scan-history
      // insert while the home screen reads the stack); synchronous=NORMAL
      // is the standard safe pairing with WAL on mobile.
      await customStatement('PRAGMA journal_mode=WAL');
      await customStatement('PRAGMA synchronous=NORMAL');
      // Hot-path indexes. Kept outside the versioned migration ladder on
      // purpose: IF NOT EXISTS is idempotent, runs on every open, and
      // covers both fresh installs and upgrades without a schema bump.
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_user_stack_active '
        'ON user_stacks_local (deleted_at, added_at DESC)',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_user_stack_dsld '
        'ON user_stacks_local (dsld_id)',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_user_scan_dsld '
        'ON user_scan_history (dsld_id)',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_user_fav_added '
        'ON user_favorites (added_at DESC)',
      );
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

  /// Update resolved RxNorm identity fields for a local medication row.
  ///
  /// Medications are PHI and remain local-only; this method is used by the
  /// background identity hydrator to repair rows saved while RxNorm was flaky.
  Future<int> updateMedicationIdentity({
    required String id,
    String? genericRxcui,
    String? drugClassesJson,
    String? ingredientRxcuisJson,
  }) {
    return (update(userStacksLocal)..where((t) => t.id.equals(id))).write(
      UserStacksLocalCompanion(
        genericRxcui: Value(genericRxcui),
        drugClassesCol: Value(drugClassesJson),
        ingredientRxcuisCol: Value(ingredientRxcuisJson),
        clientUpdatedAt: Value(DateTime.now()),
      ),
    );
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
    String? formulaFingerprint,
    String? catalogSourceVersion,
  }) async {
    await into(scanHistory).insert(
      ScanHistoryCompanion(
        dsldId: Value(dsldId),
        upcSku: Value(upcSku),
        productName: Value(productName),
        formulaFingerprint: Value(formulaFingerprint),
        catalogSourceVersion: Value(catalogSourceVersion),
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
  // Failed-scan queue (Layer 4 missing-UPC sensor)
  // ---------------------------------------------------------------------------

  /// Record a UPC that the catalog couldn't resolve. On first miss inserts
  /// a row; on subsequent misses bumps `attempt_count` and `last_seen`.
  /// No user identifier is stored — see failed_scans_table.dart for the
  /// privacy contract.
  Future<void> recordFailedScan(String upc) async {
    final trimmed = upc.trim();
    if (trimmed.isEmpty) return;
    final now = DateTime.now().toUtc();
    await transaction(() async {
      final existing = await (select(
        failedScans,
      )..where((t) => t.upc.equals(trimmed))).getSingleOrNull();
      if (existing == null) {
        await into(failedScans).insert(
          FailedScansCompanion(
            upc: Value(trimmed),
            attemptCount: const Value(1),
            firstSeen: Value(now),
            lastSeen: Value(now),
          ),
        );
      } else {
        await (update(failedScans)..where((t) => t.upc.equals(trimmed))).write(
          FailedScansCompanion(
            attemptCount: Value(existing.attemptCount + 1),
            lastSeen: Value(now),
          ),
        );
      }
    });
  }

  /// Returns the failed-scan queue ordered by attempt count desc, then
  /// last_seen desc. Used by debug surfaces and the
  /// `/triage-missing-upcs` slash command export flow.
  Future<List<FailedScan>> getFailedScans({int limit = 100}) {
    return (select(failedScans)
          ..orderBy([
            (t) => OrderingTerm(
              expression: t.attemptCount,
              mode: OrderingMode.desc,
            ),
            (t) =>
                OrderingTerm(expression: t.lastSeen, mode: OrderingMode.desc),
          ])
          ..limit(limit))
        .get();
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

  // ---------------------------------------------------------------------------
  // Cache eviction
  // ---------------------------------------------------------------------------

  /// LRU-style cap on detail-cache rows kept after a purge pass.
  static const int detailCacheMaxRows = 5000;

  /// Evicts expired cache rows. Fire-and-forget after DB open — best-effort
  /// housekeeping, never user-facing.
  ///
  /// TTLs mirror the read-side conventions (the readers already treat
  /// expired rows as misses; this just reclaims the storage):
  ///   - product_detail_cache: 24h ([kDetailBlobCacheTtl] in
  ///     detail_blob_provider.dart), plus a ~5000-row LRU cap.
  ///   - product_image_cache: 30d positive / 7d negative ("no_image"),
  ///     matching ProductImageResolver.
  ///   - user_failed_scans: 90 days since last_seen.
  Future<void> purgeExpiredCaches() async {
    final now = DateTime.now();

    // Detail cache: TTL expiry, then LRU cap on whatever survives.
    await (delete(detailCache)..where(
          (t) => t.cachedAt.isSmallerThanValue(
            now.subtract(const Duration(hours: 24)),
          ),
        ))
        .go();
    await customStatement(
      'DELETE FROM product_detail_cache '
      'WHERE dsld_id NOT IN ('
      '  SELECT dsld_id FROM product_detail_cache '
      '  ORDER BY cached_at DESC LIMIT $detailCacheMaxRows'
      ')',
    );

    // Image cache: negative entries ("no_image") expire faster.
    await (delete(productImageCache)..where(
          (t) =>
              (t.imageUrl.equals('no_image') &
                  t.cachedAt.isSmallerThanValue(
                    now.subtract(const Duration(days: 7)),
                  )) |
              (t.imageUrl.equals('no_image').not() &
                  t.cachedAt.isSmallerThanValue(
                    now.subtract(const Duration(days: 30)),
                  )),
        ))
        .go();

    // Failed-scan queue: a UPC unseen for 90 days is stale triage data.
    await (delete(failedScans)..where(
          (t) => t.lastSeen.isSmallerThanValue(
            now.toUtc().subtract(const Duration(days: 90)),
          ),
        ))
        .go();
  }

  /// Deletes ALL detail-cache rows. Called on OTA catalog activation —
  /// cached blobs were fetched against the previous catalog snapshot and
  /// may not match the new rows' detail_blob_sha256.
  Future<void> clearDetailCache() {
    return delete(detailCache).go();
  }

  // ---------------------------------------------------------------------------
  // Account-switch hygiene
  // ---------------------------------------------------------------------------

  /// Deletes ALL user-owned data. Called by the account-switch guard when
  /// a DIFFERENT uid signs in on this device — the next user must not
  /// inherit (or upload) the previous user's medical data.
  ///
  /// DESTRUCTIVE and unrecoverable: profile, medications, conditions, and
  /// allergens have NO cloud backup. Never call this outside
  /// `AccountSwitchGuard` (see pg_auth_service.dart), which gates it on a
  /// genuine different-uid sign-in.
  ///
  /// Scope:
  ///   WIPED — user_profile (conditions/allergens/goals/drug classes/
  ///     flags), user_stacks_local (supplements, medications, tombstones —
  ///     hard-deleting rows also destroys all sync dirty/queue state, so
  ///     nothing of the previous user can ever push under the new uid),
  ///     user_favorites, user_scan_history.
  ///   PRESERVED — product_detail_cache and product_image_cache (product-
  ///     keyed catalog mirrors, no user linkage) and user_failed_scans
  ///     (no-PII device telemetry; see failed_scans_table.dart).
  ///
  /// Runs in a single transaction so a crash mid-clear can't leave a
  /// half-wiped, half-attributable state.
  Future<void> clearAllLocalUserData() {
    return transaction(() async {
      await delete(userStacksLocal).go();
      await delete(userProfiles).go();
      await delete(userFavorites).go();
      await delete(scanHistory).go();
    });
  }
}
