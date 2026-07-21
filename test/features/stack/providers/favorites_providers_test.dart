// Wishlist / favorites — domain contracts.
//
// Guests cannot persist; signed-in users get idempotent add/remove;
// toggle flips membership. On-device only (no sync).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/stack/providers/active_stack_provider.dart';
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

  group('FavoritesActions auth gate', () {
    test('guest add throws StackRequiresSignInException', () async {
      final actions = container.read(favoritesActionsProvider);
      expect(
        () => actions.add('dsld-1'),
        throwsA(isA<StackRequiresSignInException>()),
      );
      expect(await userDb.getFavorites(), isEmpty);
    });

    test('guest remove throws StackRequiresSignInException', () async {
      final actions = container.read(favoritesActionsProvider);
      expect(
        () => actions.remove('dsld-1'),
        throwsA(isA<StackRequiresSignInException>()),
      );
    });

    test('guest toggle throws StackRequiresSignInException', () async {
      final actions = container.read(favoritesActionsProvider);
      expect(
        () => actions.toggle('dsld-1'),
        throwsA(isA<StackRequiresSignInException>()),
      );
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

    test('isFavoriteProvider is false for guests even if DB has rows', () async {
      // Simulate leftover local rows from a prior signed-in session on
      // the same install (clear-on-sign-out is separate; heart must not
      // claim a guest has a wishlist).
      await userDb.addFavorite('dsld-stale');
      container.read(authStateProvider.notifier).onSignedOut();

      final saved = await container.read(isFavoriteProvider('dsld-stale').future);
      expect(saved, isFalse);
    });

    test('isFavoriteProvider true after add while signed in', () async {
      final actions = container.read(favoritesActionsProvider);
      await actions.add('dsld-2');
      final saved = await container.read(isFavoriteProvider('dsld-2').future);
      expect(saved, isTrue);
    });
  });

  group('UserDatabase favorites helpers', () {
    test('isFavorite false then true after addFavorite', () async {
      expect(await userDb.isFavorite('x'), isFalse);
      await userDb.addFavorite('x');
      expect(await userDb.isFavorite('x'), isTrue);
    });

    test('addFavorite twice yields one row', () async {
      await userDb.addFavorite('x');
      await userDb.addFavorite('x');
      expect(await userDb.getFavorites(), hasLength(1));
    });
  });
}
