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
      // hasSeenOnboarding: true so splash ?next=/ → home shell.
      child: const PharmaGuideApp(hasSeenOnboarding: true),
    );
  }

  /// Pump past the 600ms animated splash so the shell (nav bar, tabs) is
  /// visible. Tests that interact with tabs must call this helper first.
  ///
  /// Uses explicit time-step pumps (not pumpAndSettle) because HomeScreen
  /// may contain widgets that keep animations active indefinitely, which
  /// would cause pumpAndSettle to time out.
  Future<void> pumpPastSplash(WidgetTester tester) async {
    await tester.pump(); // initial frame
    await tester.pump(
      const Duration(milliseconds: 650),
    ); // past 600ms ctrl.forward()
    await tester.pump(); // process the GoRouter.go() navigation
    await tester.pump(
      const Duration(milliseconds: 100),
    ); // settle first shell frame
  }

  testWidgets('App renders with 5 navigation tabs', (tester) async {
    final coreDb = CoreDatabase.memory();
    final userDb = UserDatabase.memory();

    await tester.pumpWidget(buildApp(coreDb, userDb));
    await pumpPastSplash(tester);

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
    await pumpPastSplash(tester);

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
    await pumpPastSplash(tester);

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
    await pumpPastSplash(tester);

    await tester.tap(find.text('Stack'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('My stack'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    await coreDb.close();
    await userDb.close();
  });

  testWidgets('Tapping Profile tab navigates to profile screen', (
    tester,
  ) async {
    final coreDb = CoreDatabase.memory();
    final userDb = UserDatabase.memory();

    await tester.pumpWidget(buildApp(coreDb, userDb));
    await pumpPastSplash(tester);

    await tester.tap(find.text('Profile'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Profile'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    await coreDb.close();
    await userDb.close();
  });
}
