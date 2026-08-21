import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:drift/drift.dart' as drift;
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/interaction_result.dart';
import 'package:pharmaguide/features/home/v2/home_v2_screen.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';
import 'package:pharmaguide/features/stack/providers/active_stack_provider.dart';
import 'package:pharmaguide/features/stack/providers/coverage_report_provider.dart';
import 'package:pharmaguide/features/stack/providers/stack_safety_providers.dart';
import 'package:pharmaguide/features/stack/providers/stack_nutrient_providers.dart';
import 'package:pharmaguide/features/stack/providers/synergy_report_provider.dart';
import 'package:pharmaguide/features/stack/v2/stack_v2_screen.dart';
import 'package:pharmaguide/services/auth_state_service.dart';
import 'package:pharmaguide/services/stack/recalled_ingredient_result.dart';
import 'package:pharmaguide/services/stack/stack_dose_summer.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';
import 'package:pharmaguide/services/stack/stack_safety_report.dart';
import 'package:pharmaguide/services/stack/synergy_result.dart';

void main() {
  UserStacksLocalData stackEntry({
    required String id,
    required String name,
    required String type,
    String? dsldId,
    String? rxcui,
    String? genericRxcui,
    String? drugClassesCol,
    String? ingredientRxcuisCol,
    String? dosage,
    String? frequency,
  }) {
    final ts = DateTime.utc(2026, 5, 16, 12);
    return UserStacksLocalData(
      id: id,
      type: type,
      name: name,
      dsldId: dsldId,
      rxcui: rxcui,
      ingredientKeys: null,
      drugClassesCol: drugClassesCol,
      genericRxcui: genericRxcui,
      ingredientRxcuisCol: ingredientRxcuisCol,
      dosage: dosage,
      frequency: frequency,
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
    bool stackSafetyFails = false,
    bool coverageFails = false,
    StackSafetyReport safetyReport = const StackSafetyReport(),
    List<StackDoseThresholdAlert> doseThresholdAlerts = const [],
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
          stackSafetyReportProvider.overrideWith((ref) async {
            if (stackSafetyFails) {
              throw StateError('stack safety unavailable');
            }
            return safetyReport;
          }),
          if (coverageFails)
            coverageReportProvider.overrideWith(
              (ref) async => throw StateError('coverage unavailable'),
            ),
          synergyReportProvider.overrideWith(
            (ref) async => SynergyReport.empty(),
          ),
          recalledIngredientsReportProvider.overrideWith(
            (ref) async => RecalledIngredientsReport.empty(),
          ),
          stackDoseThresholdAlertsProvider.overrideWith(
            (ref) async => doseThresholdAlerts,
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
    testWidgets(
      'incomplete non-empty stack uses a neutral More info needed state',
      (tester) async {
        await pumpWithStack(
          tester,
          const StackV2Screen(showNavBar: false),
          stack: [
            stackEntry(
              id: 'supp-1',
              name: 'Partially mapped supplement',
              type: 'supplement',
              dsldId: '12345',
            ),
          ],
          safetyReport: const StackSafetyReport(checksIncomplete: true),
        );

        expect(
          find.text('More info needed', skipOffstage: false),
          findsNWidgets(2),
          reason: 'the summary and hero share the same neutral state',
        );
        expect(find.text('Decent', skipOffstage: false), findsNothing);
        expect(find.text('No data yet', skipOffstage: false), findsNothing);
      },
    );

    testWidgets(
      'dose-alert-only stack shares one tappable signal across summary, hero, and sheet',
      (tester) async {
        const alert = StackDoseThresholdAlert(
          conditionId: 'pregnancy',
          canonicalId: 'caffeine',
          displayName: 'Caffeine',
          totalValue: 240,
          unit: 'mg',
          thresholdValue: 200,
          thresholdUnit: 'mg',
          contributions: [],
        );

        await pumpWithStack(
          tester,
          const StackV2Screen(showNavBar: false),
          stack: [
            stackEntry(
              id: 'supp-1',
              name: 'Caffeine',
              type: 'supplement',
              dsldId: '12345',
            ),
          ],
          doseThresholdAlerts: const [alert],
        );

        expect(
          find.text('1 safety signal to review', skipOffstage: false),
          findsOneWidget,
        );
        expect(find.text('Caffeine', skipOffstage: false), findsWidgets);
        expect(
          find.text('Review details', skipOffstage: false),
          findsOneWidget,
        );

        await tester.tap(find.text('Stack Health'));
        await tester.pumpAndSettle();

        expect(find.text('1 SAFETY SIGNAL TO REVIEW'), findsOneWidget);
        expect(find.text('DOSE-THRESHOLD GUIDANCE'), findsOneWidget);
        expect(find.textContaining('threshold 200 mg'), findsOneWidget);
      },
    );

    testWidgets('Home Stack Health uses the complete safety-signal count', (
      tester,
    ) async {
      InteractionResult interaction(String id, String nutrient) {
        return InteractionResult(
          id: id,
          type: InteractionType.drugSupplement,
          severity: Severity.caution,
          evidenceLevel: EvidenceLevel.established,
          agent1Name: 'Warfarin',
          agent2Name: nutrient,
          mechanism: 'Mechanism',
          management: 'Review with your clinician.',
          doseDependant: false,
          doseThreshold: null,
          sourceUrls: const [],
          source: InteractionSource.pipeline,
        );
      }

      final report = StackSafetyReport(
        medicationInteractions: [
          interaction('warfarin-e', 'Vitamin E'),
          interaction('warfarin-other', 'Another supplement'),
        ],
        nutrientStatuses: [
          const NutrientStatus(
            total: NutrientTotal(
              canonicalId: 'vitamin_d',
              displayName: 'Vitamin D',
              totalAmount: 125,
              unit: 'mcg',
              contributions: [],
            ),
            tier: NutrientTier.exceedsUl,
            ul: 100,
            pctOfUl: 125,
          ),
        ],
      );

      await pumpWithStack(
        tester,
        const HomeV2Screen(showNavBar: false),
        stack: [
          stackEntry(
            id: 'supp-1',
            name: 'Vitamin E',
            type: 'supplement',
            dsldId: '12345',
          ),
        ],
        safetyReport: report,
      );

      expect(find.text('3 safety signals to review'), findsOneWidget);
      expect(find.text('3 Signals'), findsOneWidget);
      expect(find.textContaining('2 interactions'), findsNothing);
      expect(find.text('No conflicts'), findsNothing);
    });

    testWidgets('Home uses a neutral icon when more information is needed', (
      tester,
    ) async {
      await pumpWithStack(
        tester,
        const HomeV2Screen(showNavBar: false),
        stack: [
          stackEntry(
            id: 'supp-1',
            name: 'Partially mapped supplement',
            type: 'supplement',
            dsldId: '12345',
          ),
        ],
        safetyReport: const StackSafetyReport(checksIncomplete: true),
      );

      final insightRow = find.ancestor(
        of: find.text(
          'Some checks need more information before this stack can be rated.',
          skipOffstage: false,
        ),
        matching: find.byType(Row, skipOffstage: false),
      );
      expect(
        find.descendant(
          of: insightRow,
          matching: find.byIcon(
            Icons.info_outline_rounded,
            skipOffstage: false,
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('Home uses a review icon for a Decent stack', (tester) async {
      const report = StackSafetyReport(
        medicationInteractions: [
          InteractionResult(
            id: 'warfarin-e',
            type: InteractionType.drugSupplement,
            severity: Severity.caution,
            evidenceLevel: EvidenceLevel.established,
            agent1Name: 'Warfarin',
            agent2Name: 'Vitamin E',
            mechanism: 'Mechanism',
            management: 'Review with your clinician.',
            doseDependant: false,
            doseThreshold: null,
            sourceUrls: [],
            source: InteractionSource.pipeline,
          ),
        ],
      );

      await pumpWithStack(
        tester,
        const HomeV2Screen(showNavBar: false),
        stack: [
          stackEntry(
            id: 'supp-1',
            name: 'Vitamin E',
            type: 'supplement',
            dsldId: '12345',
          ),
        ],
        safetyReport: report,
      );

      final insightRow = find.ancestor(
        of: find.text('1 safety signal to review', skipOffstage: false),
        matching: find.byType(Row, skipOffstage: false),
      );
      expect(
        find.descendant(
          of: insightRow,
          matching: find.byIcon(
            Icons.warning_amber_rounded,
            skipOffstage: false,
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('Stack Health summary and sheet use one safety-signal count', (
      tester,
    ) async {
      InteractionResult interaction(String id, String nutrient) {
        return InteractionResult(
          id: id,
          type: InteractionType.drugSupplement,
          severity: Severity.caution,
          evidenceLevel: EvidenceLevel.established,
          agent1Name: 'Warfarin',
          agent2Name: nutrient,
          mechanism: 'Mechanism',
          management: 'Review with your clinician.',
          doseDependant: false,
          doseThreshold: null,
          sourceUrls: const [],
          source: InteractionSource.pipeline,
        );
      }

      final report = StackSafetyReport(
        medicationInteractions: [
          interaction('warfarin-e', 'Vitamin E'),
          interaction('warfarin-other', 'Another supplement'),
        ],
        nutrientStatuses: [
          const NutrientStatus(
            total: NutrientTotal(
              canonicalId: 'vitamin_d',
              displayName: 'Vitamin D',
              totalAmount: 125,
              unit: 'mcg',
              contributions: [],
            ),
            tier: NutrientTier.exceedsUl,
            ul: 100,
            pctOfUl: 125,
          ),
        ],
      );

      await pumpWithStack(
        tester,
        const StackV2Screen(showNavBar: false),
        stack: [
          stackEntry(
            id: 'supp-1',
            name: 'Vitamin E',
            type: 'supplement',
            dsldId: '12345',
          ),
        ],
        safetyReport: report,
      );

      expect(
        find.text('3 safety signals to review', skipOffstage: false),
        findsOneWidget,
        reason: 'Stack Health uses the complete typed finding count',
      );
      expect(
        find.text('Warfarin × Vitamin E', skipOffstage: false),
        findsOneWidget,
      );
      expect(
        find.textContaining('2 interactions', skipOffstage: false),
        findsNothing,
      );

      await tester.tap(find.text('Stack Health'));
      await tester.pumpAndSettle();
      expect(find.text('3 SAFETY SIGNALS TO REVIEW'), findsOneWidget);
    });

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

      expect(find.text('Supplement nutrient totals'), findsOneWidget);
      expect(
        find.text(
          'From your supplements only · compared with RDA/AI and upper limits',
        ),
        findsOneWidget,
      );
      expect(find.text('Daily nutrient coverage'), findsNothing);
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

    testWidgets(
      'supplement tracking never exposes or displays user-entered dose fields',
      (tester) async {
        await pumpWithStack(
          tester,
          const StackV2Screen(showNavBar: false),
          signedIn: true,
          stack: [
            stackEntry(
              id: 'supplement-1',
              name: 'Verified Multivitamin',
              type: 'supplement',
              dsldId: '278454',
              dosage: '8 capsules',
              frequency: 'At bedtime',
            ),
          ],
        );

        expect(find.text('8 capsules', skipOffstage: false), findsNothing);
        expect(find.text('At bedtime', skipOffstage: false), findsNothing);

        final edit = find.byTooltip(
          'Edit tracking for Verified Multivitamin',
          skipOffstage: false,
        );
        await tester.ensureVisible(edit);
        await tester.tap(edit);
        await tester.pumpAndSettle();

        expect(find.text('TRACKING DETAILS'), findsOneWidget);
        expect(find.text('Dose (optional)'), findsNothing);
        expect(find.text('Schedule (optional)'), findsNothing);
        expect(find.textContaining('verified product label'), findsOneWidget);
        expect(find.text('Set start date'), findsOneWidget);
        expect(find.text('No reminder'), findsOneWidget);
      },
    );

    testWidgets(
      'medication tracking keeps dose editable without a fake timing schedule',
      (tester) async {
        await pumpWithStack(
          tester,
          const StackV2Screen(showNavBar: false),
          signedIn: true,
          stack: [
            stackEntry(
              id: 'medication-1',
              name: 'Metformin',
              type: 'medication',
              rxcui: '6809',
              dosage: '500 mg',
              frequency: 'Twice daily',
            ),
          ],
        );

        final edit = find.byTooltip(
          'Edit dose and tracking for Metformin',
          skipOffstage: false,
        );
        await tester.ensureVisible(edit);
        await tester.tap(edit);
        await tester.pumpAndSettle();

        expect(find.text('DOSE & TRACKING'), findsOneWidget);
        expect(find.text('Dose (optional)'), findsOneWidget);
        expect(find.text('Schedule (optional)'), findsNothing);
        expect(find.text('500 mg'), findsWidgets);
        expect(find.text('No reminder'), findsOneWidget);
      },
    );

    testWidgets('confirming discard closes a dirty medication tracking sheet', (
      tester,
    ) async {
      await pumpWithStack(
        tester,
        const StackV2Screen(showNavBar: false),
        stack: [
          stackEntry(
            id: 'medication-1',
            name: 'Metformin',
            type: 'medication',
            rxcui: '6809',
            dosage: '500 mg',
            frequency: 'Twice daily',
          ),
        ],
      );

      final edit = find.byTooltip(
        'Edit dose and tracking for Metformin',
        skipOffstage: false,
      );
      await tester.ensureVisible(edit);
      await tester.tap(edit);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '750 mg');
      tester.testTextInput.hide();
      await tester.pump();
      final sheetContext = tester.element(find.text('DOSE & TRACKING'));
      await Navigator.of(sheetContext).maybePop();
      await tester.pumpAndSettle();

      expect(find.text('Discard changes?'), findsOneWidget);
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();

      expect(find.text('DOSE & TRACKING'), findsNothing);
      expect(find.text('Metformin'), findsOneWidget);
    });

    testWidgets(
      'Stack v2 surfaces stack-safety errors instead of hiding timing checks',
      (tester) async {
        await pumpWithStack(
          tester,
          const StackV2Screen(showNavBar: false),
          stackSafetyFails: true,
          stack: [
            stackEntry(
              id: 'stack-1',
              name: 'Magnesium',
              type: 'supplement',
              dsldId: '12345',
            ),
          ],
        );

        expect(
          find.text("Couldn't check your stack", skipOffstage: false),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            'interactions or timing guidance',
            skipOffstage: false,
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Stack v2 surfaces coverage errors instead of an empty gap card',
      (tester) async {
        await pumpWithStack(
          tester,
          const StackV2Screen(showNavBar: false),
          coverageFails: true,
          stack: [
            stackEntry(
              id: 'stack-1',
              name: 'Magnesium',
              type: 'supplement',
              dsldId: '12345',
            ),
          ],
        );

        expect(
          find.text("Couldn't check goal support", skipOffstage: false),
          findsOneWidget,
        );
        expect(
          find.textContaining('Try again shortly', skipOffstage: false),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Stack v2 separates medications and opens local medication details',
      (tester) async {
        await pumpWithStack(
          tester,
          const StackV2Screen(showNavBar: false),
          stack: [
            stackEntry(
              id: 'med-1',
              name: 'metformin Pill',
              type: 'medication',
              rxcui: '1161611',
              genericRxcui: '6809',
              drugClassesCol: '["class:diabetes_meds"]',
              dosage: '500 mg',
              frequency: 'Twice daily',
            ),
            stackEntry(
              id: 'supp-1',
              name: 'Magnesium Glycinate',
              type: 'supplement',
              dsldId: '12345',
            ),
          ],
        );

        expect(
          find.text('Your medications', skipOffstage: false),
          findsOneWidget,
        );
        expect(
          find.text('Your supplements', skipOffstage: false),
          findsOneWidget,
        );
        expect(find.text('metformin Pill', skipOffstage: false), findsNothing);
        expect(find.text('Metformin', skipOffstage: false), findsOneWidget);

        await tester.tap(find.text('Metformin'));
        await tester.pumpAndSettle();

        expect(find.text('MEDICATION DETAILS'), findsOneWidget);
        expect(find.byType(BottomSheet), findsOneWidget);
        expect(find.text('MATCHING INCOMPLETE'), findsOneWidget);
        expect(
          find.textContaining('medication checks may be incomplete'),
          findsOneWidget,
        );
        expect(find.text('YOUR DETAILS'), findsOneWidget);
        expect(find.text('500 mg · Twice daily'), findsWidgets);
        // RxNorm identity stays collapsed until Technical details is opened.
        expect(find.textContaining('RxNorm concept 1161611'), findsNothing);
        await tester.tap(find.text('Technical details'));
        await tester.pump();
        expect(find.textContaining('RxNorm concept 1161611'), findsOneWidget);
        expect(find.byType(Scrollable), findsWidgets);
        expect(
          find.textContaining("doesn't provide prescribing"),
          findsOneWidget,
        );
        expect(find.text('Saved only on this device.'), findsOneWidget);
        expect(
          find.text("Medications don't have a detail page yet."),
          findsNothing,
        );
      },
    );

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
                  qualityScoreStatus: const drift.Value('scored'),
                  productSafetyStatus: const drift.Value(
                    'no_known_catalog_concern',
                  ),
                  qualityAssessmentStatus: const drift.Value('complete'),
                  mappedCoverage: const drift.Value(0.9),
                  qualityScoreConfidence: const drift.Value('high'),
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
      expect(
        find.textContaining('Score confidence:', skipOffstage: false),
        findsNothing,
      );
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
      expect(heart.color, V2Palette.light.accent);
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
