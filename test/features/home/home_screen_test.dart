import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/home/home_screen.dart';

void main() {
  // DBs are created and closed inside each test body (not via setUp/tearDown).
  // Drift's close() hangs when called from tearDown after the fake-async
  // zone has drained — closing inside the body avoids the shutdown race.

  Widget buildTestWidget(CoreDatabase coreDb, UserDatabase userDb) {
    return ProviderScope(
      overrides: [
        coreDatabaseProvider.overrideWithValue(coreDb),
        userDatabaseProvider.overrideWithValue(userDb),
      ],
      child: const MaterialApp(home: HomeScreen()),
    );
  }

  group('HomeScreen', () {
    testWidgets('shows greeting', (tester) async {
      final coreDb = CoreDatabase.memory();
      final userDb = UserDatabase.memory();

      await tester.pumpWidget(buildTestWidget(coreDb, userDb));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.textContaining(RegExp('Good (morning|afternoon|evening)')),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await coreDb.close();
      await userDb.close();
    });

    testWidgets('shows search bar placeholder', (tester) async {
      final coreDb = CoreDatabase.memory();
      final userDb = UserDatabase.memory();

      await tester.pumpWidget(buildTestWidget(coreDb, userDb));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('Search'), findsWidgets);

      await tester.pumpWidget(const SizedBox.shrink());
      await coreDb.close();
      await userDb.close();
    });

    testWidgets('shows category filter chips', (tester) async {
      final coreDb = CoreDatabase.memory();
      final userDb = UserDatabase.memory();

      await tester.pumpWidget(buildTestWidget(coreDb, userDb));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Scroll past Quick Check CTA + profile card to reach categories.
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -250));
      await tester.pump();

      expect(find.text('Omega-3'), findsOneWidget);
      expect(find.text('Probiotics'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await coreDb.close();
      await userDb.close();
    });

    testWidgets('shows profile completeness banner for incomplete profile',
        (tester) async {
      final coreDb = CoreDatabase.memory();
      final userDb = UserDatabase.memory();

      await tester.pumpWidget(buildTestWidget(coreDb, userDb));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Complete your health profile'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await coreDb.close();
      await userDb.close();
    });

    testWidgets('shows recent scans empty state', (tester) async {
      final coreDb = CoreDatabase.memory();
      final userDb = UserDatabase.memory();

      await tester.pumpWidget(buildTestWidget(coreDb, userDb));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Scroll the CustomScrollView to ensure the Recent scans section is
      // rendered — in the default 800×600 test viewport it starts below
      // the fold. Use manual drag + pump instead of scrollUntilVisible
      // (which calls pumpAndSettle and can hang with async providers).
      final scrollable = find.byType(Scrollable).first;
      await tester.drag(scrollable, const Offset(0, -600));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Nothing scanned yet'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await coreDb.close();
      await userDb.close();
    });
  });
}
