import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/product_detail/v2/product_detail_v2_connected.dart';

void main() {
  testWidgets('missing product id renders v2 unavailable state', (
    tester,
  ) async {
    final coreDb = CoreDatabase.memory();
    final router = GoRouter(
      initialLocation: Routes.productDetail('missing-product'),
      routes: [
        GoRoute(
          path: '${Routes.product}/:dsldId',
          builder: (_, state) => ProductDetailV2ConnectedScreen(
            dsldId: state.pathParameters['dsldId']!,
          ),
        ),
        GoRoute(
          path: Routes.search,
          builder: (_, __) => const Scaffold(body: Text('Search v2')),
        ),
        GoRoute(
          path: Routes.home,
          builder: (_, __) => const Scaffold(body: Text('Home v2')),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [coreDatabaseProvider.overrideWithValue(coreDb)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Product unavailable'), findsOneWidget);
    expect(find.textContaining('verified catalog'), findsOneWidget);

    await tester.tap(find.text('Search catalog'));
    await tester.pumpAndSettle();
    expect(find.text('Search v2'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await coreDb.close();
  });
}
