import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/product_detail/widgets/safety_check_sheet.dart';
import 'package:pharmaguide/features/stack/providers/stack_providers.dart';

// The pre-add sheet told a guest with an empty stack and no profile "No stack
// interactions found … Safe to add." Nothing had been checked, and even a
// full check only covers PharmaGuide's curated interactions, so the sheet
// never asserts safety.
void main() {
  Future<void> openSheet(WidgetTester tester, PreAddSafetyResult check) async {
    final coreDb = CoreDatabase.memory();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await coreDb.close();
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          coreDatabaseProvider.overrideWithValue(coreDb),
          safetyCheckForAddProvider.overrideWith((ref, id) async => check),
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: TextButton(
                onPressed: () => showSafetyCheckSheet(
                  context,
                  ref,
                  dsldId: 'p1',
                  productName: 'Test Product',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('empty stack says there is nothing to check against', (
    tester,
  ) async {
    await openSheet(tester, PreAddSafetyResult.emptyStack);

    expect(find.text('Nothing in your stack to check against yet'), findsOne);
    expect(find.textContaining('Safe'), findsNothing);
    expect(find.text('Add to stack'), findsOneWidget);
  });

  testWidgets('a clear check reports no known interactions, not safety', (
    tester,
  ) async {
    await openSheet(
      tester,
      const PreAddSafetyResult(results: [], checksIncomplete: false),
    );

    expect(find.text('No known interactions with your stack'), findsOne);
    expect(find.textContaining('Safe'), findsNothing);
    expect(find.text('Add to stack'), findsOneWidget);
  });
}
