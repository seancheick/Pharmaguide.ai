// Spec: INITIATIVE_PRODUCT_TRUST_AND_IA.md, Sprint 1, T1.15.

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/product_detail/widgets/pg_stack_action_buttons.dart';

const _dsldId = 'dsld-test';

Future<void> _seedProduct(
  CoreDatabase coreDb, {
  String dsldId = _dsldId,
  String verdict = 'GOOD',
}) async {
  await coreDb
      .into(coreDb.productsCore)
      .insert(
        ProductsCoreCompanion.insert(
          dsldId: dsldId,
          productName: 'Test Product',
          exportVersion: 'test',
          exportedAt: '2026-04-29T00:00:00Z',
          verdict: Value(verdict),
        ),
      );
}

Future<void> _addToStack(UserDatabase userDb, {String dsldId = _dsldId}) async {
  await userDb.addToStack(
    UserStacksLocalCompanion.insert(
      id: 'stack-$dsldId',
      name: 'Test Product',
      dsldId: Value(dsldId),
    ),
  );
}

Widget _wrap(
  CoreDatabase coreDb,
  UserDatabase userDb, {
  bool isUnsafe = false,
  VoidCallback? onSeeAlternatives,
  VoidCallback? onLogDose,
}) {
  return ProviderScope(
    overrides: [
      coreDatabaseProvider.overrideWithValue(coreDb),
      userDatabaseProvider.overrideWithValue(userDb),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: PGStackActionButtons(
          dsldId: _dsldId,
          isUnsafe: isUnsafe,
          onSeeAlternatives: onSeeAlternatives,
          onLogDose: onLogDose,
        ),
      ),
    ),
  );
}

void main() {
  group('PGStackActionButtons — T1.15 conditional primary', () {
    testWidgets(
      'safe + not in stack → "Add to my stack" + "Log dose" (2 buttons)',
      (tester) async {
        final coreDb = CoreDatabase.memory();
        final userDb = UserDatabase.memory();
        await _seedProduct(coreDb);

        await tester.pumpWidget(_wrap(coreDb, userDb));
        await tester.pumpAndSettle();

        expect(find.text('Add to my stack'), findsOneWidget);
        expect(find.text('Log dose'), findsOneWidget);
        expect(find.text('See safer alternatives'), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
        await coreDb.close();
        await userDb.close();
      },
    );

    testWidgets(
      'unsafe verdict → "See safer alternatives" replaces "Add to my stack"',
      (tester) async {
        final coreDb = CoreDatabase.memory();
        final userDb = UserDatabase.memory();
        await _seedProduct(coreDb, verdict: 'UNSAFE');

        await tester.pumpWidget(_wrap(coreDb, userDb, isUnsafe: true));
        await tester.pumpAndSettle();

        expect(find.text('See safer alternatives'), findsOneWidget);
        expect(find.text('Add to my stack'), findsNothing);
        // Log dose still rendered (always-visible secondary).
        expect(find.text('Log dose'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await coreDb.close();
        await userDb.close();
      },
    );

    testWidgets(
      'already in stack → "In your stack" panel (with Remove) + "Log dose"',
      (tester) async {
        final coreDb = CoreDatabase.memory();
        final userDb = UserDatabase.memory();
        await _seedProduct(coreDb);
        await _addToStack(userDb);

        await tester.pumpWidget(_wrap(coreDb, userDb));
        await tester.pumpAndSettle();

        // In-stack pill renders + Remove button inside it.
        expect(find.text('In your stack'), findsOneWidget);
        expect(find.text('Remove'), findsOneWidget);
        // Add button should NOT be visible.
        expect(find.text('Add to my stack'), findsNothing);
        // Log dose still rendered.
        expect(find.text('Log dose'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await coreDb.close();
        await userDb.close();
      },
    );

    testWidgets(
      'unsafe wins over in-stack — "See safer alternatives" beats Remove panel',
      (tester) async {
        // Edge case: the user already has the product in their stack
        // and a later catalog update flipped it to UNSAFE. The right
        // call is to direct them to safer alternatives, not let them
        // re-open the remove flow as the loudest button.
        final coreDb = CoreDatabase.memory();
        final userDb = UserDatabase.memory();
        await _seedProduct(coreDb, verdict: 'UNSAFE');
        await _addToStack(userDb);

        await tester.pumpWidget(_wrap(coreDb, userDb, isUnsafe: true));
        await tester.pumpAndSettle();

        expect(find.text('See safer alternatives'), findsOneWidget);
        expect(find.text('In your stack'), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
        await coreDb.close();
        await userDb.close();
      },
    );

    testWidgets(
      'log dose disabled when not in stack (incoherent to log without tracking)',
      (tester) async {
        final coreDb = CoreDatabase.memory();
        final userDb = UserDatabase.memory();
        await _seedProduct(coreDb);

        var taps = 0;
        await tester.pumpWidget(_wrap(coreDb, userDb, onLogDose: () => taps++));
        await tester.pumpAndSettle();

        // Tap should be ignored when disabled.
        await tester.tap(find.text('Log dose'));
        await tester.pumpAndSettle();
        expect(taps, 0);

        await tester.pumpWidget(const SizedBox.shrink());
        await coreDb.close();
        await userDb.close();
      },
    );

    testWidgets(
      'log dose enabled when in stack — tap fires onLogDose callback',
      (tester) async {
        final coreDb = CoreDatabase.memory();
        final userDb = UserDatabase.memory();
        await _seedProduct(coreDb);
        await _addToStack(userDb);

        var taps = 0;
        await tester.pumpWidget(_wrap(coreDb, userDb, onLogDose: () => taps++));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Log dose'));
        await tester.pumpAndSettle();
        expect(taps, 1);

        await tester.pumpWidget(const SizedBox.shrink());
        await coreDb.close();
        await userDb.close();
      },
    );

    testWidgets(
      'log dose disabled in unsafe state (even if user added the product)',
      (tester) async {
        // Defense-in-depth: user shouldn't be encouraged to log doses
        // for a product the catalog now flags as unsafe.
        final coreDb = CoreDatabase.memory();
        final userDb = UserDatabase.memory();
        await _seedProduct(coreDb, verdict: 'UNSAFE');
        await _addToStack(userDb);

        var taps = 0;
        await tester.pumpWidget(
          _wrap(coreDb, userDb, isUnsafe: true, onLogDose: () => taps++),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Log dose'));
        await tester.pumpAndSettle();
        expect(taps, 0);

        await tester.pumpWidget(const SizedBox.shrink());
        await coreDb.close();
        await userDb.close();
      },
    );

    testWidgets(
      'tap "See safer alternatives" → fires onSeeAlternatives callback',
      (tester) async {
        final coreDb = CoreDatabase.memory();
        final userDb = UserDatabase.memory();
        await _seedProduct(coreDb, verdict: 'UNSAFE');

        var taps = 0;
        await tester.pumpWidget(
          _wrap(
            coreDb,
            userDb,
            isUnsafe: true,
            onSeeAlternatives: () => taps++,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('See safer alternatives'));
        await tester.pumpAndSettle();
        expect(taps, 1);

        await tester.pumpWidget(const SizedBox.shrink());
        await coreDb.close();
        await userDb.close();
      },
    );

    testWidgets(
      'add flow preserved — Add button has non-null onPressed (V0 wiring intact)',
      (tester) async {
        // Per spec: "Tap [Add to Stack] → existing flow (no behavior
        // change)". The full V0 add flow goes through showSafetyCheckSheet
        // which depends on a chain of providers (safetyCheckForAddProvider,
        // verdict provider, interaction DB) that aren't worth full-staging
        // for this widget test. Instead we assert the structural invariant:
        // the Add button is rendered as an enabled FilledButton wired to
        // the V0 _handleAdd handler — exact same construction as before
        // T1.15's refactor.
        final coreDb = CoreDatabase.memory();
        final userDb = UserDatabase.memory();
        await _seedProduct(coreDb);

        await tester.pumpWidget(_wrap(coreDb, userDb));
        await tester.pumpAndSettle();

        final addButton = tester.widget<FilledButton>(
          find.ancestor(
            of: find.text('Add to my stack'),
            matching: find.byType(FilledButton),
          ),
        );
        expect(
          addButton.onPressed,
          isNotNull,
          reason: 'V0 _handleAdd handler should be wired up',
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await coreDb.close();
        await userDb.close();
      },
    );
  });
}
