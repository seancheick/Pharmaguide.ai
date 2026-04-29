import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/stack/providers/active_stack_provider.dart';
import 'package:pharmaguide/features/stack/providers/stack_safety_providers.dart';
import 'package:pharmaguide/features/stack/providers/synergy_report_provider.dart';
import 'package:pharmaguide/features/stack/stack_screen.dart';
import 'package:pharmaguide/services/stack/recalled_ingredient_result.dart';
import 'package:pharmaguide/services/stack/stack_safety_report.dart';
import 'package:pharmaguide/services/stack/synergy_result.dart';

void main() {
  UserStacksLocalData stackEntry({
    required String id,
    required String name,
    required String type,
  }) {
    final ts = DateTime.utc(2026, 4, 28, 12);
    return UserStacksLocalData(
      id: id,
      type: type,
      name: name,
      dsldId: null,
      rxcui: null,
      ingredientKeys: null,
      drugClassesCol: null,
      genericRxcui: null,
      ingredientRxcuisCol: null,
      dosage: null,
      frequency: null,
      addedAt: ts,
      clientUpdatedAt: ts,
      deletedAt: null,
      syncedAt: null,
    );
  }

  group('StackScreen', () {
    testWidgets('shows stack and wishlist tabs', (tester) async {
      final coreDb = CoreDatabase.memory();
      final userDb = UserDatabase.memory();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userDatabaseProvider.overrideWithValue(userDb),
            coreDatabaseProvider.overrideWithValue(coreDb),
          ],
          child: const MaterialApp(home: StackScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('My stack'), findsWidgets);
      expect(find.text('Wishlist'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await coreDb.close();
      await userDb.close();
    });

    testWidgets('shows empty stack state', (tester) async {
      final coreDb = CoreDatabase.memory();
      final userDb = UserDatabase.memory();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userDatabaseProvider.overrideWithValue(userDb),
            coreDatabaseProvider.overrideWithValue(coreDb),
          ],
          child: const MaterialApp(home: StackScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Your stack is empty'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await coreDb.close();
      await userDb.close();
    });

    testWidgets(
      'uses intelligence verdict and unsafe subcopy for recalled stack',
      (tester) async {
        final coreDb = CoreDatabase.memory();
        final userDb = UserDatabase.memory();
        final stack = [
          stackEntry(
            id: 'supp-1',
            name: 'Flagged Supplement',
            type: 'supplement',
          ),
        ];

        final recallReport = RecalledIngredientsReport(
          violations: [
            RecalledIngredientViolation(
              productDsldId: 'flagged-1',
              productName: 'Flagged Supplement',
              brandName: 'Brand',
              recalledIngredients: [
                RecalledIngredientAlert(
                  canonicalId: 'dmaa',
                  commonNames: const ['DMAA'],
                  recallStatus: 'warning',
                  regulatoryBasis: 'FDA',
                  reason: 'recall',
                  effectiveDate: '2026-01-01',
                  severity: 'major',
                  safetyWarning: 'warning',
                  safetyWarningOneLiner: 'Recall notice',
                  banContext: 'contamination_recall',
                ),
              ],
            ),
          ],
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              userDatabaseProvider.overrideWithValue(userDb),
              coreDatabaseProvider.overrideWithValue(coreDb),
              activeStackProvider.overrideWith((ref) async => stack),
              stackSafetyReportProvider.overrideWith(
                (ref) async => const StackSafetyReport(),
              ),
              synergyReportProvider.overrideWith(
                (ref) async => SynergyReport.empty(),
              ),
              recalledIngredientsReportProvider.overrideWith(
                (ref) async => recallReport,
              ),
            ],
            child: const MaterialApp(home: StackScreen()),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('Unsafe'), findsOneWidget);
        expect(
          find.text('Recalled ingredient found — review immediately.'),
          findsOneWidget,
        );
        expect(
          find.textContaining('well within recommended ranges'),
          findsNothing,
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await coreDb.close();
        await userDb.close();
      },
    );
  });
}
