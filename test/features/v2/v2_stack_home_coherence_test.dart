import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' as drift;
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/home/v2/home_v2_screen.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';
import 'package:pharmaguide/features/stack/providers/active_stack_provider.dart';
import 'package:pharmaguide/features/stack/providers/stack_safety_providers.dart';
import 'package:pharmaguide/features/stack/providers/synergy_report_provider.dart';
import 'package:pharmaguide/features/stack/v2/stack_v2_screen.dart';
import 'package:pharmaguide/services/stack/recalled_ingredient_result.dart';
import 'package:pharmaguide/services/stack/stack_safety_report.dart';
import 'package:pharmaguide/services/stack/synergy_result.dart';

void main() {
  UserStacksLocalData stackEntry({
    required String id,
    required String name,
    required String type,
    String? dsldId,
  }) {
    final ts = DateTime.utc(2026, 5, 16, 12);
    return UserStacksLocalData(
      id: id,
      type: type,
      name: name,
      dsldId: dsldId,
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

  Future<void> pumpWithStack(
    WidgetTester tester,
    Widget child, {
    List<UserStacksLocalData> stack = const [],
    Future<void> Function(CoreDatabase coreDb)? seedCore,
  }) async {
    final coreDb = CoreDatabase.memory();
    final userDb = UserDatabase.memory();
    await seedCore?.call(coreDb);
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
          activeStackProvider.overrideWith((ref) async => stack),
          stackSafetyReportProvider.overrideWith(
            (ref) async => const StackSafetyReport(),
          ),
          synergyReportProvider.overrideWith(
            (ref) async => SynergyReport.empty(),
          ),
          recalledIngredientsReportProvider.overrideWith(
            (ref) async => RecalledIngredientsReport.empty(),
          ),
          profileProvider.overrideWith((ref) => ProfileNotifier()),
        ],
        child: MaterialApp(home: child),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
  }

  Future<void> pumpWithEmptyStack(WidgetTester tester, Widget child) {
    return pumpWithStack(tester, child);
  }

  group('v2 stack/home coherence', () {
    testWidgets('Stack v2 never shows fixture counts after empty stack loads', (
      tester,
    ) async {
      await pumpWithEmptyStack(tester, const StackV2Screen(showNavBar: false));

      expect(find.text('Your stack is empty'), findsOneWidget);
      expect(find.text('3 supplements · 1 medication'), findsNothing);
      expect(find.text('0'), findsNWidgets(2));
    });

    testWidgets('Stack v2 nutrients tab does not show fixtures when empty', (
      tester,
    ) async {
      await pumpWithEmptyStack(tester, const StackV2Screen(showNavBar: false));

      await tester.tap(find.text('Nutrients'));
      await tester.pumpAndSettle();

      expect(find.text('No nutrient totals yet'), findsOneWidget);
      expect(find.text('Vitamin A'), findsNothing);
      expect(find.text('120% of UL'), findsNothing);
    });

    testWidgets('Stack v2 real list uses dismissible v2 rows', (tester) async {
      await pumpWithStack(
        tester,
        const StackV2Screen(showNavBar: false),
        stack: [
          stackEntry(
            id: 'stack-1',
            name: 'Magnesium Glycinate',
            type: 'supplement',
            dsldId: '12345',
          ),
        ],
      );

      // The Coverage card above the list can push these below the test
      // viewport fold — assert presence in the tree, not on-screen.
      expect(
        find.text('Your supplements', skipOffstage: false),
        findsOneWidget,
      );
      expect(
        find.text('Swipe left to remove', skipOffstage: false),
        findsOneWidget,
      );
      expect(find.byType(Dismissible, skipOffstage: false), findsOneWidget);
      expect(
        find.text('Magnesium Glycinate', skipOffstage: false),
        findsOneWidget,
      );
    });

    testWidgets('Stack v2 real rows hydrate product brand and score', (
      tester,
    ) async {
      await pumpWithStack(
        tester,
        const StackV2Screen(showNavBar: false),
        seedCore: (coreDb) async {
          await coreDb
              .into(coreDb.productsCore)
              .insert(
                ProductsCoreCompanion.insert(
                  dsldId: 'magnesium-1',
                  productName: 'Magnesium Glycinate 200',
                  brandName: const drift.Value('Clean Lab'),
                  qualityScoreV4100: const drift.Value(87),
                  score100Equivalent: const drift.Value(87),
                  qualityScoreStatus: const drift.Value('scored'),
                  exportVersion: 'test',
                  exportedAt: '2026-05-18T00:00:00Z',
                ),
              );
        },
        stack: [
          stackEntry(
            id: 'stack-1',
            name: 'Magnesium Glycinate',
            type: 'supplement',
            dsldId: 'magnesium-1',
          ),
        ],
      );

      // The Coverage card above the list can push the row below the test
      // viewport fold — assert presence in the tree, not on-screen.
      expect(
        find.text('Magnesium Glycinate 200', skipOffstage: false),
        findsOneWidget,
      );
      expect(find.text('Clean Lab', skipOffstage: false), findsOneWidget);
      expect(find.text('87/100', skipOffstage: false), findsOneWidget);
    });

    testWidgets(
      'Home v2 never shows fixture stack counts after empty stack loads',
      (tester) async {
        await pumpWithEmptyStack(tester, const HomeV2Screen(showNavBar: false));

        expect(find.text('3 supplements · 1 medication'), findsNothing);
        expect(find.text('0 supplements · 0 medications'), findsWidgets);
      },
    );
  });
}
