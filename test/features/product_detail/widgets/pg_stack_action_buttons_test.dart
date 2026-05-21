// Spec: docs/sprints/product_detail_page_sprint.md — T1A.

import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/product_detail/widgets/pg_stack_action_buttons.dart';
import 'package:pharmaguide/features/product_detail/widgets/safety_check_sheet.dart';

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

class _RaceCoreDatabase extends CoreDatabase {
  final ProductsCoreData product;
  final Completer<ProductsCoreData?> verdictLookup;
  int findCalls = 0;

  _RaceCoreDatabase({required this.product, required this.verdictLookup})
    : super.memory();

  @override
  Future<ProductsCoreData?> findById(String dsldId) {
    if (dsldId != product.dsldId) return Future.value(null);
    findCalls++;
    if (findCalls == 1) return Future.value(product);
    return verdictLookup.future;
  }
}

Widget _wrap(
  CoreDatabase coreDb,
  UserDatabase userDb, {
  bool isUnsafe = false,
  VoidCallback? onSeeAlternatives,
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
        ),
      ),
    ),
  );
}

Widget _wrapSafetySheetOpener(CoreDatabase coreDb, UserDatabase userDb) {
  return ProviderScope(
    overrides: [
      coreDatabaseProvider.overrideWithValue(coreDb),
      userDatabaseProvider.overrideWithValue(userDb),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Consumer(
          builder: (context, ref, _) {
            return FilledButton(
              onPressed: () => showSafetyCheckSheet(
                context,
                ref,
                dsldId: _dsldId,
                productName: 'Test Product',
              ),
              child: const Text('Open sheet'),
            );
          },
        ),
      ),
    ),
  );
}

void main() {
  group('PGStackActionButtons — conditional primary', () {
    testWidgets('safe + not in stack → "Add to my stack" only', (tester) async {
      final coreDb = CoreDatabase.memory();
      final userDb = UserDatabase.memory();
      await _seedProduct(coreDb);

      await tester.pumpWidget(_wrap(coreDb, userDb));
      await tester.pumpAndSettle();

      expect(find.text('Add to my stack'), findsOneWidget);
      expect(find.text('See safer alternatives'), findsNothing);
      expect(find.text('Log dose'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await coreDb.close();
      await userDb.close();
    });

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
        expect(find.text('Log dose'), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
        await coreDb.close();
        await userDb.close();
      },
    );

    testWidgets('already in stack → "In your stack" panel only', (
      tester,
    ) async {
      final coreDb = CoreDatabase.memory();
      final userDb = UserDatabase.memory();
      await _seedProduct(coreDb);
      await _addToStack(userDb);

      await tester.pumpWidget(_wrap(coreDb, userDb));
      await tester.pumpAndSettle();

      expect(find.text('In your stack'), findsOneWidget);
      expect(find.text('Remove'), findsOneWidget);
      expect(find.text('Add to my stack'), findsNothing);
      expect(find.text('Log dose'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await coreDb.close();
      await userDb.close();
    });

    testWidgets(
      'T1A — in-stack pill is persistent (does NOT auto-collapse after 3s)',
      (tester) async {
        // The previous version cross-faded the bar to height-zero after
        // 3s. Sean's new call: the bar must stay visible so users can
        // remove without leaving the page. Only the snackbar is
        // ephemeral; the bar itself is persistent.
        final coreDb = CoreDatabase.memory();
        final userDb = UserDatabase.memory();
        await _seedProduct(coreDb);
        await _addToStack(userDb);

        await tester.pumpWidget(_wrap(coreDb, userDb));
        await tester.pumpAndSettle();

        // Pill visible immediately.
        expect(find.text('In your stack'), findsOneWidget);
        expect(find.text('Remove'), findsOneWidget);

        // Past the old 3s window — bar must still render.
        await tester.pump(const Duration(seconds: 5));
        expect(find.text('In your stack'), findsOneWidget);
        expect(find.text('Remove'), findsOneWidget);
        // No AnimatedCrossFade — the auto-collapse machinery is gone.
        expect(find.byType(AnimatedCrossFade), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
        await coreDb.close();
        await userDb.close();
      },
    );

    testWidgets(
      'unsafe wins over in-stack — "See safer alternatives" beats Remove panel',
      (tester) async {
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

    testWidgets('add flow preserved — Add button has non-null onPressed', (
      tester,
    ) async {
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
        reason: '_handleAdd handler should be wired up',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await coreDb.close();
      await userDb.close();
    });

    testWidgets(
      'direct safety sheet does not show safe-to-add while verdict is pending',
      (tester) async {
        final verdictLookup = Completer<ProductsCoreData?>();
        const product = ProductsCoreData(
          dsldId: _dsldId,
          productName: 'Test Product',
          exportVersion: 'test',
          exportedAt: '2026-04-29T00:00:00Z',
          verdict: 'UNSAFE',
        );
        final coreDb = _RaceCoreDatabase(
          product: product,
          verdictLookup: verdictLookup,
        );
        final userDb = UserDatabase.memory();

        await tester.pumpWidget(_wrapSafetySheetOpener(coreDb, userDb));
        await tester.tap(find.text('Open sheet'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('Checking product safety…'), findsOneWidget);
        expect(find.text('No stack interactions found'), findsNothing);
        expect(find.textContaining('Safe to add'), findsNothing);

        final pendingButton = tester.widget<FilledButton>(
          find.ancestor(
            of: find.text('Add to stack'),
            matching: find.byType(FilledButton),
          ),
        );
        expect(pendingButton.onPressed, isNull);

        verdictLookup.complete(product);
        await tester.pumpAndSettle();

        expect(find.text('This product cannot be added'), findsOneWidget);
        expect(find.text('Cannot add'), findsOneWidget);
        expect(find.text('No stack interactions found'), findsNothing);
        expect(find.textContaining('Safe to add'), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
        await coreDb.close();
        await userDb.close();
      },
    );
  });
}
