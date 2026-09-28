// Wishlist / favorites providers — on-device only.
//
// Favorites stay in `user_data.db` and never sync to Supabase (same privacy
// boundary as profile / medications), so guests keep a wishlist too (Sean
// 2026-09-28). Like the stack, the rows stay on the device after sign-out;
// a different account signing in clears them (AccountSwitchGuard).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/services/auth_state_service.dart';
import 'package:pharmaguide/services/crash_reporting_service.dart';

/// All wishlist rows on this device, newest first.
///
/// Watching auth here is intentional: it clears the in-memory Riverpod value
/// immediately on sign-out. The account-switch composition root explicitly
/// invalidates this provider after clearing the previous owner's local rows,
/// including signed-in-to-signed-in account changes where [AuthMode] itself
/// may not change.
final favoritesProvider = FutureProvider.autoDispose<List<UserFavorite>>((ref) {
  // Re-read on sign-in/out: an account switch may have just cleared rows.
  ref.watch(authStateProvider);
  final userDb = ref.watch(userDatabaseProvider);
  return userDb.getFavorites();
});

/// Whether [dsldId] is on this device's wishlist.
final isFavoriteProvider = FutureProvider.family.autoDispose<bool, String>((
  ref,
  dsldId,
) async {
  // Depend on the list so add/remove flips every open product heart.
  final favorites = await ref.watch(favoritesProvider.future);
  return favorites.any((f) => f.dsldId == dsldId);
});

/// Imperative wishlist actions. Call only from user events (onTap), never
/// from build methods.
class FavoritesActions {
  final Ref _ref;
  FavoritesActions(this._ref);

  /// Add [dsldId] to the wishlist.
  Future<void> add(String dsldId) async {
    final userDb = _ref.read(userDatabaseProvider);
    await userDb.addFavorite(dsldId);
    _invalidate();
    CrashReportingService().log('wishlist_add');
  }

  /// Remove [dsldId] from the wishlist.
  Future<void> remove(String dsldId) async {
    final userDb = _ref.read(userDatabaseProvider);
    await userDb.removeFavorite(dsldId);
    _invalidate();
    CrashReportingService().log('wishlist_remove');
  }

  /// Toggle membership. Returns `true` when the product is saved after the
  /// call, `false` when removed.
  Future<bool> toggle(String dsldId) async {
    final userDb = _ref.read(userDatabaseProvider);
    final wasSaved = await userDb.isFavorite(dsldId);
    if (wasSaved) {
      await userDb.removeFavorite(dsldId);
      _invalidate();
      CrashReportingService().log('wishlist_remove');
      return false;
    }
    await userDb.addFavorite(dsldId);
    _invalidate();
    CrashReportingService().log('wishlist_add');
    return true;
  }

  void _invalidate() {
    _ref.invalidate(favoritesProvider);
    _ref.invalidate(isFavoriteProvider);
  }
}

final favoritesActionsProvider = Provider<FavoritesActions>((ref) {
  return FavoritesActions(ref);
});
