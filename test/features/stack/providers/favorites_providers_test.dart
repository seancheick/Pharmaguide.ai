// Wishlist / favorites — domain contracts.
//
// Guests and signed-in users alike get idempotent add/remove; toggle flips
// membership. On-device only (no sync), so no account is needed (Sean
// 2026-09-28).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/stack/providers/favorites_providers.dart';
import 'package:pharmaguide/services/auth_state_service.dart';

void main() {
  late UserDatabase userDb;
  late ProviderContainer container;

  setUp(() {
    userDb = UserDatabase.memory();
    container = ProviderContainer(
      overrides: [userDatabaseProvider.overrideWithValue(userDb)],
    );
  });

  tearDown(() async {
    container.dispose();
    await userDb.close();
  });

  group('FavoritesActions as a guest', () {
    test('guest wishlist saves, reads back and toggles off', () async {
      final actions = container.read(favoritesActionsProvider);
      await actions.add('dsld-1');
      expect((await userDb.getFavorites()).map((r) => r.dsldId), ['dsld-1']);
      expect(await container.read(favoritesProvider.future), hasLength(1));
      expect(await container.read(isFavoriteProvider('dsld-1').future), isTrue);

      await actions.toggle('dsld-1');
      expect(await userDb.getFavorites(), isEmpty);
    });
  });

  group('FavoritesActions signed-in', () {
    setUp(() {
      container.read(authStateProvider.notifier).onSignedIn();
    });

    test('add then getFavorites returns the row', () async {
      final actions = container.read(favoritesActionsProvider);
      await actions.add('dsld-1');
      final rows = await userDb.getFavorites();
      expect(rows.map((r) => r.dsldId), ['dsld-1']);
    });

    test('add is idempotent — no duplicate rows', () async {
      final actions = container.read(favoritesActionsProvider);
      await actions.add('dsld-1');
      await actions.add('dsld-1');
      expect(await userDb.getFavorites(), hasLength(1));
    });

    test('remove clears membership', () async {
      final actions = container.read(favoritesActionsProvider);
      await actions.add('dsld-1');
      await actions.remove('dsld-1');
      expect(await userDb.getFavorites(), isEmpty);
    });

    test('toggle add then remove', () async {
      final actions = container.read(favoritesActionsProvider);
      expect(await actions.toggle('dsld-1'), isTrue);
      expect(await userDb.isFavorite('dsld-1'), isTrue);
      expect(await actions.toggle('dsld-1'), isFalse);
      expect(await userDb.isFavorite('dsld-1'), isFalse);
    });

    // Like the stack ("Sign out · Keep local health data on this device"),
    // the wishlist stays on the device after sign-out. A different account
    // signing in clears it (AccountSwitchGuard → clearAllLocalUserData).
    test('wishlist rows stay on the device after sign-out', () async {
      await userDb.addFavorite('dsld-kept');
      container.read(authStateProvider.notifier).onSignedOut();

      final saved = await container.read(
        isFavoriteProvider('dsld-kept').future,
      );
      expect(saved, isTrue);
    });

    test('isFavoriteProvider true after add while signed in', () async {
      final actions = container.read(favoritesActionsProvider);
      await actions.add('dsld-2');
      final saved = await container.read(isFavoriteProvider('dsld-2').future);
      expect(saved, isTrue);
    });

    test(
      'favoritesProvider re-reads after an account switch clears rows',
      () async {
        await userDb.addFavorite('previous-user-product');
        final subscription = container.listen(favoritesProvider, (_, __) {});
        addTearDown(subscription.close);

        expect(
          (await container.read(
            favoritesProvider.future,
          )).map((row) => row.dsldId),
          contains('previous-user-product'),
        );

        container.read(authStateProvider.notifier).onSignedOut();
        // What AccountSwitchGuard does when a different account signs in.
        await userDb.clearAllLocalUserData();
        container.read(authStateProvider.notifier).onSignedIn();
        expect(await container.read(favoritesProvider.future), isEmpty);
      },
    );
  });

  group('UserDatabase favorites helpers', () {
    test('isFavorite false then true after addFavorite', () async {
      expect(await userDb.isFavorite('x'), isFalse);
      await userDb.addFavorite('x');
      expect(await userDb.isFavorite('x'), isTrue);
    });

    test('concurrent addFavorite calls yield one row', () async {
      await Future.wait([
        userDb.addFavorite('x'),
        userDb.addFavorite('x'),
        userDb.addFavorite('x'),
      ]);
      expect(await userDb.getFavorites(), hasLength(1));
    });
  });
}
