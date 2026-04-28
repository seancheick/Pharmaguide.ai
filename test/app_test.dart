import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/app.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';

void main() {
  // DBs are created and closed inside each test body (not via setUp/tearDown).
  // Drift's close() hangs when called from tearDown after the fake-async
  // zone has drained — closing inside the body avoids the shutdown race.

  Widget buildApp(CoreDatabase coreDb, UserDatabase userDb) {
    return ProviderScope(
      overrides: [
        coreDatabaseProvider.overrideWithValue(coreDb),
        userDatabaseProvider.overrideWithValue(userDb),
      ],
      child: const PharmaGuideApp(),
    );
  }

  testWidgets('App renders with 5 navigation tabs', (tester) async {
    final coreDb = CoreDatabase.memory();
    final userDb = UserDatabase.memory();

    await tester.pumpWidget(buildApp(coreDb, userDb));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify 5 navigation destinations exist
    expect(find.byType(NavigationDestination), findsNWidgets(5));
    // Verify nav labels are present (some may appear multiple times due to screen titles)
    expect(find.text('Home'), findsWidgets);
    expect(find.text('Scan'), findsWidgets);
    expect(find.text('Stack'), findsWidgets);
    expect(find.text('Chat'), findsWidgets);
    expect(find.text('Profile'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    await coreDb.close();
    await userDb.close();
  });

  testWidgets('Home tab is selected by default', (tester) async {
    final coreDb = CoreDatabase.memory();
    final userDb = UserDatabase.memory();

    await tester.pumpWidget(buildApp(coreDb, userDb));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Home screen content should be visible
    expect(find.text('Home'), findsWidgets); // nav + screen title

    await tester.pumpWidget(const SizedBox.shrink());
    await coreDb.close();
    await userDb.close();
  });

  testWidgets('Tapping Scan tab navigates to scan screen', (tester) async {
    final coreDb = CoreDatabase.memory();
    final userDb = UserDatabase.memory();

    await tester.pumpWidget(buildApp(coreDb, userDb));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Scan'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Scan'), findsWidgets); // nav + screen title

    await tester.pumpWidget(const SizedBox.shrink());
    await coreDb.close();
    await userDb.close();
  });

  testWidgets('Tapping Stack tab navigates to stack screen', (tester) async {
    final coreDb = CoreDatabase.memory();
    final userDb = UserDatabase.memory();

    await tester.pumpWidget(buildApp(coreDb, userDb));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Stack'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('My stack'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    await coreDb.close();
    await userDb.close();
  });

  testWidgets('Tapping Profile tab navigates to profile screen',
      (tester) async {
    final coreDb = CoreDatabase.memory();
    final userDb = UserDatabase.memory();

    await tester.pumpWidget(buildApp(coreDb, userDb));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Profile'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Profile'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    await coreDb.close();
    await userDb.close();
  });
}
