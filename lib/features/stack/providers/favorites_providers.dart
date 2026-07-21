// Wishlist / favorites providers — on-device only.
//
// Favorites stay in `user_data.db` and never sync to Supabase (same privacy
// boundary as profile / medications). Auth gate mirrors [StackActions]:
// guests may browse the catalog but cannot persist wishlist rows.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/stack/providers/active_stack_provider.dart';
import 'package:pharmaguide/services/auth_state_service.dart';
import 'package:pharmaguide/services/crash_reporting_service.dart';

/// All wishlist rows for the current signed-in session, newest first.
///
/// Watching auth here is intentional: it clears the in-memory Riverpod value
/// immediately on sign-out. The account-switch composition root explicitly
/// invalidates this provider after clearing the previous owner's local rows,
/// including signed-in-to-signed-in account changes where [AuthMode] itself
/// may not change.
final favoritesProvider = FutureProvider.autoDispose<List<UserFavorite>>((ref) {
  if (ref.watch(authStateProvider) == AuthMode.guest) {
    return Future.value(const <UserFavorite>[]);
  }
  final userDb = ref.watch(userDatabaseProvider);
  return userDb.getFavorites();
});

/// Whether [dsldId] is on the signed-in user's wishlist.
///
/// Guests always resolve to `false` so the heart renders as outline and
/// never implies a phantom save from a previous session on a shared device.
final isFavoriteProvider = FutureProvider.family.autoDispose<bool, String>((
  ref,
  dsldId,
) async {
  if (ref.watch(authStateProvider) == AuthMode.guest) return false;
  // Depend on the list so add/remove flips every open product heart.
  final favorites = await ref.watch(favoritesProvider.future);
  return favorites.any((f) => f.dsldId == dsldId);
});

/// Imperative wishlist actions. Call only from user events (onTap), never
/// from build methods.
class FavoritesActions {
  final Ref _ref;
  FavoritesActions(this._ref);

  /// Add [dsldId] to the wishlist. Throws [StackRequiresSignInException]
  /// for guests — same contract as stack save so UI can route to auth with
  /// one catch path.
  Future<void> add(String dsldId) async {
    _requireSignedIn();
    final userDb = _ref.read(userDatabaseProvider);
    await userDb.addFavorite(dsldId);
    _invalidate();
    CrashReportingService().log('wishlist_add');
  }

  /// Remove [dsldId] from the wishlist. Sign-in required so a guest tap
  /// cannot silently no-op a heart that should prompt for account.
  Future<void> remove(String dsldId) async {
    _requireSignedIn();
    final userDb = _ref.read(userDatabaseProvider);
    await userDb.removeFavorite(dsldId);
    _invalidate();
    CrashReportingService().log('wishlist_remove');
  }

  /// Toggle membership. Returns `true` when the product is saved after the
  /// call, `false` when removed.
  Future<bool> toggle(String dsldId) async {
    _requireSignedIn();
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

  void _requireSignedIn() {
    if (_ref.read(authStateProvider) == AuthMode.guest) {
      throw const StackRequiresSignInException();
    }
  }
}

final favoritesActionsProvider = Provider<FavoritesActions>((ref) {
  return FavoritesActions(ref);
});
