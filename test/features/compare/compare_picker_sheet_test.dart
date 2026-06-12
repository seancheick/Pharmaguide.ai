// Compare picker sheet tests — candidate sourcing + exclusion rules.

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/compare/compare_picker_sheet.dart';
import 'package:pharmaguide/features/compare/compare_providers.dart';

Future<void> _insertProduct(
  CoreDatabase coreDb, {
  required String dsldId,
  required String name,
  String brand = 'Brand',
}) {
  return coreDb
      .into(coreDb.productsCore)
      .insert(
        ProductsCoreCompanion.insert(
          dsldId: dsldId,
          productName: name,
          brandName: drift.Value(brand),
          exportVersion: 'test',
          exportedAt: '2026-06-01T00:00:00Z',
        ),
      );
}

void main() {
  testWidgets('picker lists stack + recent scans and excludes the current '
      'product', (tester) async {
    final coreDb = CoreDatabase.memory();
    final userDb = UserDatabase.memory();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await coreDb.close();
      await userDb.close();
    });

    await _insertProduct(coreDb, dsldId: 'current-1', name: 'Current Product');
    await _insertProduct(coreDb, dsldId: 'stack-1', name: 'Stack Product');
    await _insertProduct(coreDb, dsldId: 'scan-1', name: 'Scanned Product');

    // Stack: the current product AND another supplement.
    await userDb
        .into(userDb.userStacksLocal)
        .insert(
          UserStacksLocalCompanion.insert(
            id: 'stack-entry-current',
            name: 'Current Product',
            dsldId: const drift.Value('current-1'),
          ),
        );
    await userDb
        .into(userDb.userStacksLocal)
        .insert(
          UserStacksLocalCompanion.insert(
            id: 'stack-entry-1',
            name: 'Stack Product',
            dsldId: const drift.Value('stack-1'),
          ),
        );

    // Recent scans: the current product AND another product.
    await userDb.recordScanEvent(dsldId: 'current-1');
    await userDb.recordScanEvent(dsldId: 'scan-1');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          coreDatabaseProvider.overrideWithValue(coreDb),
          userDatabaseProvider.overrideWithValue(userDb),
        ],
        child: const MaterialApp(
          home: Scaffold(body: ComparePickerSheet(currentDsldId: 'current-1')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Your stack'), findsOneWidget);
    expect(find.text('Recent scans'), findsOneWidget);
    expect(find.text('Stack Product'), findsOneWidget);
    expect(find.text('Scanned Product'), findsOneWidget);
    // The product being compared FROM never appears as a candidate.
    expect(find.text('Current Product'), findsNothing);
  });

  testWidgets('picker shows calm empty state with nothing to compare', (
    tester,
  ) async {
    final coreDb = CoreDatabase.memory();
    final userDb = UserDatabase.memory();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await coreDb.close();
      await userDb.close();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          coreDatabaseProvider.overrideWithValue(coreDb),
          userDatabaseProvider.overrideWithValue(userDb),
        ],
        child: const MaterialApp(
          home: Scaffold(body: ComparePickerSheet(currentDsldId: 'current-1')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Nothing to compare with yet'), findsOneWidget);
  });

  test('compareCandidatesProvider excludes current and de-dupes stack vs '
      'scans', () async {
    final coreDb = CoreDatabase.memory();
    final userDb = UserDatabase.memory();
    addTearDown(() async {
      await coreDb.close();
      await userDb.close();
    });

    await _insertProduct(coreDb, dsldId: 'current-1', name: 'Current');
    await _insertProduct(coreDb, dsldId: 'both-1', name: 'In Stack And Scans');

    await userDb
        .into(userDb.userStacksLocal)
        .insert(
          UserStacksLocalCompanion.insert(
            id: 'stack-entry-1',
            name: 'In Stack And Scans',
            dsldId: const drift.Value('both-1'),
          ),
        );
    await userDb.recordScanEvent(dsldId: 'both-1');
    await userDb.recordScanEvent(dsldId: 'current-1');

    final container = ProviderContainer(
      overrides: [
        coreDatabaseProvider.overrideWithValue(coreDb),
        userDatabaseProvider.overrideWithValue(userDb),
      ],
    );
    addTearDown(container.dispose);

    final candidates = await container.read(
      compareCandidatesProvider('current-1').future,
    );

    expect(candidates.stack.map((c) => c.dsldId), ['both-1']);
    // Already in the stack section — not repeated under recent scans.
    expect(candidates.recentScans, isEmpty);
  });
}
