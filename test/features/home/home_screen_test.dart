import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';
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

      expect(find.text('Search supplements'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await coreDb.close();
      await userDb.close();
    });

    testWidgets('does not show category rail on home', (tester) async {
      final coreDb = CoreDatabase.memory();
      final userDb = UserDatabase.memory();

      await tester.pumpWidget(buildTestWidget(coreDb, userDb));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Browse categories'), findsNothing);
      expect(find.text('Omega-3'), findsNothing);
      expect(find.text('Probiotics'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await coreDb.close();
      await userDb.close();
    });

    testWidgets('shows profile completeness banner for incomplete profile',
        (tester) async {
      final coreDb = CoreDatabase.memory();
      final userDb = UserDatabase.memory();
      await userDb.addToStack(
        const UserStacksLocalCompanion(
          id: Value('stack-profile'),
          type: Value('supplement'),
          name: Value('Seeded Product'),
          dsldId: Value('dsld-profile'),
        ),
      );

      await tester.pumpWidget(buildTestWidget(coreDb, userDb));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Complete your health profile'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await coreDb.close();
      await userDb.close();
    });

    testWidgets('shows first-launch variant when stack and history are empty',
        (tester) async {
      final coreDb = CoreDatabase.memory();
      final userDb = UserDatabase.memory();

      await tester.pumpWidget(buildTestWidget(coreDb, userDb));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.text('Check supplement quality, safety, and fit in seconds.'),
        findsOneWidget,
      );
      expect(find.text('Stack Health'), findsNothing);
      expect(find.text('Recent scans'), findsNothing);
      expect(find.text('Safe to take together?'), findsNothing);
      expect(find.text('Complete your health profile'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await coreDb.close();
      await userDb.close();
    });

    testWidgets('shows expanded home sections after user activity',
        (tester) async {
      final coreDb = CoreDatabase.memory();
      final userDb = UserDatabase.memory();
      await userDb.recordScanEvent(
        dsldId: 'dsld-1',
        productName: 'Seeded Product',
      );
      await userDb.addToStack(
        const UserStacksLocalCompanion(
          id: Value('stack-1'),
          type: Value('supplement'),
          name: Value('Seeded Product'),
          dsldId: Value('dsld-1'),
        ),
      );

      await tester.pumpWidget(buildTestWidget(coreDb, userDb));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Stack Health'), findsOneWidget);
      final scrollable = find.byType(Scrollable).first;
      await tester.drag(scrollable, const Offset(0, -700));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Safe to take together?'), findsOneWidget);
      expect(
        find.text('Check supplement quality, safety, and fit in seconds.'),
        findsNothing,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await coreDb.close();
      await userDb.close();
    });
  });
}
