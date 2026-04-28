import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/home/home_screen.dart';
import 'package:pharmaguide/features/stack/providers/active_stack_provider.dart';

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

    testWidgets('exits first-launch mode when stack gains an item (reactive)',
        (tester) async {
      // Reactivity contract: home must re-evaluate first-launch when the
      // active stack changes. Previously the provider used ref.read inside
      // a FutureProvider — which captures the future once and never re-fires.
      // After ref.watch fix, invalidating activeStackProvider must cause home
      // to flip from collapsed (first-launch) to expanded.
      final coreDb = CoreDatabase.memory();
      final userDb = UserDatabase.memory();
      final container = ProviderContainer(overrides: [
        coreDatabaseProvider.overrideWithValue(coreDb),
        userDatabaseProvider.overrideWithValue(userDb),
      ]);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Initial state — empty DB, first-launch variant.
      expect(find.text('Stack Health'), findsNothing,
          reason: 'first-launch should hide Stack Health');

      // User mutation: add a stack item AND invalidate (mirrors what
      // StackActions.addProduct does in production at active_stack_provider:188).
      await userDb.addToStack(
        const UserStacksLocalCompanion(
          id: Value('stack-react'),
          type: Value('supplement'),
          name: Value('Reactive Test'),
          dsldId: Value('dsld-react'),
        ),
      );
      container.invalidate(activeStackProvider);

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // After fix: home re-evaluates first-launch → expanded sections render.
      expect(find.text('Stack Health'), findsOneWidget,
          reason: 'after stack mutation + invalidation, expanded home should '
              'render — bug under ref.read is that this stays hidden');

      await tester.pumpWidget(const SizedBox.shrink());
      await coreDb.close();
      await userDb.close();
      container.dispose();
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
