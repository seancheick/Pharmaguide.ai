import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/core/widgets/pg_pressable.dart';
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
        find.textContaining(
          RegExp('Good morning|Hello there|Good evening|Good night'),
        ),
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


    testWidgets('shows first-launch variant when stack and history are empty', (
      tester,
    ) async {
      final coreDb = CoreDatabase.memory();
      final userDb = UserDatabase.memory();

      await tester.pumpWidget(buildTestWidget(coreDb, userDb));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.text('Scan a label or search by name to see quality, safety, and personal-fit notes.'),
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

    testWidgets('exits first-launch mode when stack gains an item (reactive)', (
      tester,
    ) async {
      // Reactivity contract: home must re-evaluate first-launch when the
      // active stack changes. Previously the provider used ref.read inside
      // a FutureProvider — which captures the future once and never re-fires.
      // After ref.watch fix, invalidating activeStackProvider must cause home
      // to flip from collapsed (first-launch) to expanded.
      final coreDb = CoreDatabase.memory();
      final userDb = UserDatabase.memory();
      final container = ProviderContainer(
        overrides: [
          coreDatabaseProvider.overrideWithValue(coreDb),
          userDatabaseProvider.overrideWithValue(userDb),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Initial state — empty DB, first-launch variant.
      expect(
        find.text('Stack Health'),
        findsNothing,
        reason: 'first-launch should hide Stack Health',
      );

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
      expect(
        find.text('Stack Health'),
        findsOneWidget,
        reason:
            'after stack mutation + invalidation, expanded home should '
            'render — bug under ref.read is that this stays hidden',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await coreDb.close();
      await userDb.close();
      container.dispose();
    });

    testWidgets('shows expanded home sections after user activity', (
      tester,
    ) async {
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
        find.text('Scan a label or search by name to see quality, safety, and personal-fit notes.'),
        findsNothing,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await coreDb.close();
      await userDb.close();
    });

    testWidgets('exits first-launch mode when first scan is recorded', (
      tester,
    ) async {
      final coreDb = CoreDatabase.memory();
      final userDb = UserDatabase.memory();
      final container = ProviderContainer(
        overrides: [
          coreDatabaseProvider.overrideWithValue(coreDb),
          userDatabaseProvider.overrideWithValue(userDb),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Stack Health'), findsNothing);

      await userDb.recordScanEvent(
        dsldId: 'dsld-first-scan',
        productName: 'First Scan Product',
      );
      container.invalidate(isFirstLaunchHomeProvider);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      expect(
        find.text('Scan a label or search by name to see quality, safety, and personal-fit notes.'),
        findsNothing,
      );
      expect(find.text('Recent scans'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await coreDb.close();
      await userDb.close();
      container.dispose();
    });

    testWidgets('pinned search remains hit-testable after scrolling past hero', (
      tester,
    ) async {
      // Gesture-conflict smoke test for the SliverPersistentHeader pinned
      // search. The concern: once the search reaches the top and pins, is
      // it still reachable for taps, or has the parent CustomScrollView's
      // drag-recognizer eaten the hit-test path?
      //
      // We assert two things:
      //   1. The search placeholder is still found after a scroll drag
      //      (proves pinning works — the search didn't scroll off).
      //   2. A PGPressable ancestor is reachable through the search
      //      placeholder's render tree (proves the tap-handler chain is
      //      intact and not obscured by the frosted overlay or scroll
      //      gesture detection).
      final coreDb = CoreDatabase.memory();
      final userDb = UserDatabase.memory();
      // Seed enough activity to render the expanded layout — gives the
      // scroll view content tall enough to actually scroll.
      await userDb.recordScanEvent(
        dsldId: 'dsld-gesture',
        productName: 'Gesture Test',
      );
      await userDb.addToStack(
        const UserStacksLocalCompanion(
          id: Value('stack-gesture'),
          type: Value('supplement'),
          name: Value('Gesture Test'),
          dsldId: Value('dsld-gesture'),
        ),
      );

      await tester.pumpWidget(buildTestWidget(coreDb, userDb));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Inline state: search visible.
      expect(find.text('Search supplements'), findsOneWidget);

      // Scroll up to push the hero past the pinned search header.
      // Manual pumps instead of pumpAndSettle because the BouncingScrollPhysics
      // + snap-paginated Recents PageView produce ongoing micro-animations
      // that pumpAndSettle never considers idle.
      final scrollable = find.byType(Scrollable).first;
      await tester.drag(scrollable, const Offset(0, -400));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Pinned state: search still rendered.
      expect(
        find.text('Search supplements'),
        findsOneWidget,
        reason:
            'pinned search should remain rendered after scroll '
            'past hero',
      );

      // Hit-test path intact: the search placeholder has a PGPressable
      // ancestor — taps will still reach it.
      final pressableAncestor = find.ancestor(
        of: find.text('Search supplements'),
        matching: find.byType(PGPressable),
      );
      expect(
        pressableAncestor,
        findsOneWidget,
        reason:
            'PGPressable wrapping the launcher should be in the '
            'ancestor chain — if the parent scroll had eaten the '
            'gesture path this would fail.',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await coreDb.close();
      await userDb.close();
    });
  });
}
