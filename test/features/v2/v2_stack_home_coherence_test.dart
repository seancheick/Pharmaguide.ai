import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' as drift;
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/features/home/v2/home_v2_screen.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';
import 'package:pharmaguide/features/stack/providers/active_stack_provider.dart';
import 'package:pharmaguide/features/stack/providers/stack_safety_providers.dart';
import 'package:pharmaguide/features/stack/providers/synergy_report_provider.dart';
import 'package:pharmaguide/features/stack/v2/stack_v2_screen.dart';
import 'package:pharmaguide/services/auth_state_service.dart';
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
    Future<void> Function(UserDatabase userDb)? seedUser,
    bool signedIn = false,
  }) async {
    final coreDb = CoreDatabase.memory();
    final userDb = UserDatabase.memory();
    await seedCore?.call(coreDb);
    await seedUser?.call(userDb);
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
          authStateProvider.overrideWith((ref) {
            final service = AuthStateService();
            if (signedIn) service.onSignedIn();
            return service;
          }),
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

  Future<void> pumpStackRouteHarness(WidgetTester tester) async {
    final coreDb = CoreDatabase.memory();
    final userDb = UserDatabase.memory();
    final router = GoRouter(
      initialLocation: Routes.stack,
      routes: [
        GoRoute(
          path: Routes.stack,
          builder: (_, __) => const StackV2Screen(showNavBar: false),
        ),
        GoRoute(
          path: Routes.search,
          builder: (_, __) =>
              const Scaffold(body: Center(child: Text('Search route opened'))),
        ),
        GoRoute(
          path: Routes.medicationEntry,
          builder: (_, __) => const Scaffold(
            body: Center(child: Text('Medication route opened')),
          ),
        ),
      ],
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
      await coreDb.close();
      await userDb.close();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          coreDatabaseProvider.overrideWithValue(coreDb),
          userDatabaseProvider.overrideWithValue(userDb),
          activeStackProvider.overrideWith((ref) async => const []),
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
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
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

    testWidgets('Stack v2 add button opens supplement/medication choices', (
      tester,
    ) async {
      await pumpStackRouteHarness(tester);

      await tester.tap(find.byTooltip('Add to stack'));
      await tester.pumpAndSettle();

      expect(find.text('What are you adding?'), findsOneWidget);
      expect(find.text('Supplement'), findsOneWidget);
      expect(find.text('Medication'), findsOneWidget);
    });

    testWidgets('Stack v2 add supplement choice opens search route', (
      tester,
    ) async {
      await pumpStackRouteHarness(tester);

      await tester.tap(find.byTooltip('Add to stack'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Supplement'));
      await tester.pumpAndSettle();

      expect(find.text('Search route opened'), findsOneWidget);
    });

    testWidgets('Stack v2 add medication choice opens medication route', (
      tester,
    ) async {
      await pumpStackRouteHarness(tester);

      await tester.tap(find.byTooltip('Add to stack'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Medication'));
      await tester.pumpAndSettle();

      expect(find.text('Medication route opened'), findsOneWidget);
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

    testWidgets('Wishlist asks guests to sign in without reading saved rows', (
      tester,
    ) async {
      await pumpWithStack(
        tester,
        const StackV2Screen(showNavBar: false, initialSegment: 2),
        seedUser: (userDb) => userDb.addFavorite('stale-product'),
      );

      expect(find.text('Sign in to save products'), findsOneWidget);
      expect(find.text('1 saved'), findsNothing);
    });

    testWidgets('Wishlist renders a saved product with a neutral brand heart', (
      tester,
    ) async {
      await pumpWithStack(
        tester,
        const StackV2Screen(showNavBar: false, initialSegment: 2),
        signedIn: true,
        seedUser: (userDb) => userDb.addFavorite('saved-1'),
        seedCore: (coreDb) async {
          await coreDb
              .into(coreDb.productsCore)
              .insert(
                ProductsCoreCompanion.insert(
                  dsldId: 'saved-1',
                  productName: 'Saved Magnesium',
                  brandName: const drift.Value('Clean Lab'),
                  qualityScoreV4100: const drift.Value(87),
                  score100Equivalent: const drift.Value(87),
                  qualityScoreStatus: const drift.Value('scored'),
                  exportVersion: 'test',
                  exportedAt: '2026-05-18T00:00:00Z',
                ),
              );
        },
      );
      await tester.pumpAndSettle();

      expect(find.text('1 saved'), findsOneWidget);
      expect(find.text('Saved Magnesium'), findsOneWidget);
      expect(find.text('Clean Lab'), findsOneWidget);
      final heart = tester.widget<Icon>(find.byIcon(Icons.favorite_rounded));
      expect(heart.color, V2Colors.accent);
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
