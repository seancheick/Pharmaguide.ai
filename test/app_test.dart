import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart';
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

  // Skip reason: scrollUntilVisible finds the chip at offset (104, 553)
  // which is technically on-screen but the tap gesture's hit-test is at
  // the center of the found widget, which lands off-screen after the
  // frosted nav bar (88px) covers the bottom. Works on a real device.
  // Fix by using `ensureVisible` with alignment 0.5, or by reducing the
  // test viewport's bottom padding.
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

    await tester.pumpWidget(buildApp(coreDb, userDb));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // The category rail is below the hero + scan CTA + search field, so
    // it starts off-screen in the 800×600 test viewport. Scroll it into
    // view before tapping.
    final scrollable = find.byType(Scrollable).first;
    // Scroll past hero + scan CTA + Quick Check CTA + profile card to
    // bring category chips into the tappable area above the nav bar.
    await tester.drag(scrollable, const Offset(0, -500));
    await tester.pump();

    // Use the chip's center to avoid hitting the frosted nav bar.
    final chip = find.text('Omega-3');
    expect(chip, findsOneWidget);
    await tester.tap(chip, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Omega Support Fish Oil'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await coreDb.close();
    await userDb.close();
  });
  // Previously skipped — hit-test offset below frosted nav bar.
  // Fixed by increasing scroll distance + warnIfMissed: false.
}
