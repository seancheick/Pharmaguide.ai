import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:pharmaguide/data/database/tables/detail_cache_table.dart';
import 'package:pharmaguide/data/database/tables/scan_history_table.dart';
import 'package:pharmaguide/data/database/tables/user_favorites_table.dart';
import 'package:pharmaguide/data/database/tables/user_profile_table.dart';
import 'package:pharmaguide/data/database/tables/user_stacks_table.dart';

part 'user_database.g.dart';

/// READ-WRITE database for user-owned data: profile, stack, favorites,
/// scan history, and detail cache. Created locally on first launch.
@DriftDatabase(tables: [
  UserProfiles,
  UserStacksLocal,
  UserFavorites,
  ScanHistory,
  DetailCache,
])
class UserDatabase extends _$UserDatabase {
  UserDatabase(File dbFile)
      : super(NativeDatabase(dbFile, logStatements: false));

  /// In-memory database for testing.
  UserDatabase.memory() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 1;

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
            (t) => OrderingTerm(
                  expression: t.addedAt,
                  mode: OrderingMode.desc,
                ),
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
    return (update(userStacksLocal)..where((t) => t.id.equals(id)))
        .write(UserStacksLocalCompanion(
      deletedAt: Value(DateTime.now()),
      clientUpdatedAt: Value(DateTime.now()),
    ));
  }

  // ---------------------------------------------------------------------------
  // Favorites
  // ---------------------------------------------------------------------------

  /// Returns all favorites, newest first.
  Future<List<UserFavorite>> getFavorites() {
    return (select(userFavorites)
          ..orderBy([
            (t) => OrderingTerm(
                  expression: t.addedAt,
                  mode: OrderingMode.desc,
                ),
          ]))
        .get();
  }

  /// Bookmark a product by DSLD ID.
  Future<void> addFavorite(String dsldId) {
    return into(userFavorites).insert(
      UserFavoritesCompanion(dsldId: Value(dsldId)),
    );
  }

  /// Remove a product bookmark.
  Future<void> removeFavorite(String dsldId) {
    return (delete(userFavorites)
          ..where((t) => t.dsldId.equals(dsldId)))
        .go();
  }

  // ---------------------------------------------------------------------------
  // Detail Cache
  // ---------------------------------------------------------------------------

  /// Retrieve a cached detail blob by DSLD ID, or null if not cached.
  Future<DetailCacheData?> getCachedDetail(String dsldId) {
    return (select(detailCache)
          ..where((t) => t.dsldId.equals(dsldId)))
        .getSingleOrNull();
  }

  /// Cache (or refresh) a product detail blob.
  Future<void> cacheDetail(
      String dsldId, String json, String? sha256Hash) {
    return into(detailCache).insertOnConflictUpdate(
      DetailCacheCompanion(
        dsldId: Value(dsldId),
        blobJson: Value(json),
        sha256: Value(sha256Hash),
        cachedAt: Value(DateTime.now()),
      ),
    );
  }
}
