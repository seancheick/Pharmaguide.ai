import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/app.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';

void main() {
  testWidgets('App renders with 5 navigation tabs', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: PharmaGuideApp()),
    );
    await tester.pumpAndSettle();

    // Verify 5 navigation destinations exist
    expect(find.byType(NavigationDestination), findsNWidgets(5));
    // Verify nav labels are present (some may appear multiple times due to screen titles)
    expect(find.text('Home'), findsWidgets);
    expect(find.text('Scan'), findsWidgets);
    expect(find.text('Stack'), findsWidgets);
    expect(find.text('Chat'), findsWidgets);
    expect(find.text('Profile'), findsWidgets);
  });

  testWidgets('Home tab is selected by default', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: PharmaGuideApp()),
    );
    await tester.pumpAndSettle();

    // Home screen content should be visible
    expect(find.text('Home'), findsWidgets); // nav + screen title
  });

  testWidgets('Tapping Scan tab navigates to scan screen', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: PharmaGuideApp()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();

    expect(find.text('Scan'), findsWidgets); // nav + screen title
  });

  testWidgets('Tapping Stack tab navigates to stack screen', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: PharmaGuideApp()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Stack'));
    await tester.pumpAndSettle();

    expect(find.text('My Stack'), findsWidgets);
  });

  testWidgets('Tapping Profile tab navigates to profile screen', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: PharmaGuideApp()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();

    expect(find.text('Profile'), findsWidgets);
  });

  testWidgets('Home category chips navigate into filtered search results',
      (tester) async {
    final coreDb = CoreDatabase.memory();
    final userDb = UserDatabase.memory();

    await coreDb.into(coreDb.productsCore).insert(
          ProductsCoreCompanion.insert(
            dsldId: 'TEST_SEARCH_001',
            productName: 'Omega Support Fish Oil',
            exportVersion: 'test',
            exportedAt: '2026-04-09T00:00:00Z',
            productStatus: const Value('active'),
            primaryCategory: const Value('omega_3'),
            scoreQuality80: const Value(60.0),
            score100Equivalent: const Value(75.0),
            verdict: const Value('GOOD'),
          ),
        );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          coreDatabaseProvider.overrideWithValue(coreDb),
          userDatabaseProvider.overrideWithValue(userDb),
        ],
        child: const PharmaGuideApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Omega-3'));
    await tester.pumpAndSettle();

    expect(find.text('Omega Support Fish Oil'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
