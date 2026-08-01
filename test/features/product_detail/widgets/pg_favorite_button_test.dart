// PGFavoriteButton — guest → auth; signed-in → toggle wishlist.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/product_detail/widgets/pg_favorite_button.dart';
import 'package:pharmaguide/services/auth_state_service.dart';

const _dsldId = 'dsld-fav-test';

class _BlockingFavoritesDatabase extends UserDatabase {
  final addCompleter = Completer<void>();

  _BlockingFavoritesDatabase() : super.memory();

  @override
  Future<void> addFavorite(String dsldId) async {
    await addCompleter.future;
    await super.addFavorite(dsldId);
  }
}

Widget _wrap({required UserDatabase userDb, required bool signedIn}) {
  return ProviderScope(
    overrides: [
      userDatabaseProvider.overrideWithValue(userDb),
      authStateProvider.overrideWith((ref) {
        final service = AuthStateService();
        if (signedIn) service.onSignedIn();
        return service;
      }),
    ],
    child: MaterialApp.router(
      routerConfig: GoRouter(
        initialLocation: '/product',
        routes: [
          GoRoute(
            path: '/product',
            builder: (_, __) => Scaffold(
              appBar: AppBar(
                actions: const [PGFavoriteButton(dsldId: _dsldId)],
              ),
              body: const SizedBox.shrink(),
            ),
          ),
          GoRoute(
            path: Routes.authInvitation,
            builder: (_, __) => const Scaffold(body: Text('Auth invitation')),
          ),
          GoRoute(
            path: Routes.stack,
            builder: (_, __) => const Scaffold(body: Text('Stack')),
          ),
        ],
      ),
    ),
  );
}

void main() {
  group('PGFavoriteButton', () {
    testWidgets('guest tap navigates to auth invitation', (tester) async {
      final userDb = UserDatabase.memory();
      addTearDown(userDb.close);

      await tester.pumpWidget(_wrap(userDb: userDb, signedIn: false));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('product-favorite-heart')));
      await tester.pumpAndSettle();

      expect(find.text('Auth invitation'), findsOneWidget);
      expect(await userDb.getFavorites(), isEmpty);
    });

    testWidgets('signed-in tap saves then removes', (tester) async {
      final userDb = UserDatabase.memory();
      addTearDown(userDb.close);

      await tester.pumpWidget(_wrap(userDb: userDb, signedIn: true));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('product-favorite-heart')));
      await tester.pumpAndSettle();

      expect(await userDb.isFavorite(_dsldId), isTrue);
      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
      expect(
        tester.widget<Icon>(find.byIcon(Icons.favorite_rounded)).color,
        V2Palette.light.accent,
      );

      await tester.tap(find.byKey(const Key('product-favorite-heart')));
      await tester.pumpAndSettle();

      expect(await userDb.isFavorite(_dsldId), isFalse);
      expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
    });

    testWidgets('disables the heart while a save is in flight', (tester) async {
      final userDb = _BlockingFavoritesDatabase();
      addTearDown(userDb.close);

      await tester.pumpWidget(_wrap(userDb: userDb, signedIn: true));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('product-favorite-heart')));
      await tester.pump();

      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('product-favorite-heart')))
            .onPressed,
        isNull,
      );

      userDb.addCompleter.complete();
      await tester.pumpAndSettle();
      expect(await userDb.isFavorite(_dsldId), isTrue);
    });
  });
}
