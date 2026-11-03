// Sean's two notices, on the real screens. Rules that are withheld or failed to
// open leave interactionDatabaseProvider failing, as main.dart leaves it, and
// withheld scores are the real withholdQualityScores on a seeded catalog.

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/widgets/withheld_checks_notice.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/interaction_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/data/providers/reference_data_provider.dart';
import 'package:pharmaguide/data/repositories/reference_data_repository.dart';
import 'package:pharmaguide/data/providers/detail_blob_provider.dart';
import 'package:pharmaguide/data/supabase/detail_blob_service.dart';
import 'package:pharmaguide/features/compare/compare_screen.dart';
import 'package:pharmaguide/features/medications/v2/medication_entry_v2_screen.dart';
import 'package:pharmaguide/features/product_detail/widgets/safety_check_sheet.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';
import 'package:pharmaguide/features/quick_check/v2/quick_check_v2_screen.dart';
import 'package:pharmaguide/features/search/v2/search_v2_screen.dart';
import 'package:pharmaguide/features/stack/providers/active_stack_provider.dart';
import 'package:pharmaguide/features/stack/providers/stack_nutrient_providers.dart'
    show stackDoseThresholdAlertsProvider;
import 'package:pharmaguide/features/stack/providers/stack_safety_providers.dart';
import 'package:pharmaguide/features/stack/providers/synergy_report_provider.dart';
import 'package:pharmaguide/features/stack/v2/stack_v2_screen.dart';
import 'package:pharmaguide/services/medications/rxnorm_api_service.dart';
import 'package:pharmaguide/services/medications/rxnorm_providers.dart';
import 'package:pharmaguide/services/recent_searches_service.dart';
import 'package:pharmaguide/services/stack/recalled_ingredient_result.dart';
import 'package:pharmaguide/services/stack/stack_safety_report.dart';
import 'package:pharmaguide/services/stack/synergy_result.dart';

enum _Rules { unset, failing }

const _productA = 'withheld-a';
const _productB = 'withheld-b';

/// Anything that could read as a clean result.
final _clean = RegExp(
  r'no known|no interaction|all clear|no concerns|looks (good|clear)|'
  r'no issues|optimi[sz]ed|\bsafe\b|still check|checks each new',
  caseSensitive: false,
);

List<String> _allText(WidgetTester tester) => tester
    .widgetList<RichText>(find.byType(RichText, skipOffstage: false))
    .map((t) => t.text.toPlainText())
    .toList();

void _expectNoCleanResult(WidgetTester tester) {
  expect(_allText(tester).where(_clean.hasMatch), isEmpty);
}

Future<CoreDatabase> _catalog(
  WidgetTester tester, {
  bool qualityWithheld = false,
}) async {
  final db = CoreDatabase.memory(qualityWithheld: qualityWithheld);
  addTearDown(db.close);
  for (final (id, name) in [
    (_productA, 'Magnesium One'),
    (_productB, 'Magnesium Two'),
  ]) {
    await db
        .into(db.productsCore)
        .insert(
          ProductsCoreCompanion.insert(
            dsldId: id,
            productName: name,
            brandName: const drift.Value('Withheld Brand'),
            primaryCategory: const drift.Value('magnesium'),
            qualityScoreV4100: const drift.Value(86),
            qualityTier: const drift.Value('Good'),
            qualityScoreStatus: const drift.Value('scored'),
            qualityAssessmentStatus: const drift.Value('complete'),
            mappedCoverage: const drift.Value(0.9),
            verdict: const drift.Value('SAFE'),
            productStatus: const drift.Value('active'),
            exportVersion: 'test',
            exportedAt: '2026-11-01T00:00:00Z',
          ),
        );
  }
  if (qualityWithheld) await db.withholdQualityScores();
  return db;
}

List<Override> _rulesOverrides(_Rules? rules, InteractionDatabase? db) => [
  if (rules == null) interactionDatabaseProvider.overrideWithValue(db!),
  if (rules == _Rules.failing)
    interactionDatabaseProvider.overrideWith(
      (ref) => throw StateError('This rules file will not open'),
    ),
];

UserStacksLocalData _stackRow(String dsldId, String name) {
  final at = DateTime.utc(2026, 11, 1);
  return UserStacksLocalData(
    id: 'row-$dsldId',
    type: 'supplement',
    name: name,
    dsldId: dsldId,
    addedAt: at,
    clientUpdatedAt: at,
  );
}

Future<void> _pumpStack(
  WidgetTester tester, {
  required CoreDatabase core,
  required List<UserStacksLocalData> stack,
  required List<Override> overrides,
}) async {
  final userDb = UserDatabase.memory();
  addTearDown(userDb.close);
  addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
  final router = GoRouter(
    initialLocation: Routes.stack,
    routes: [
      GoRoute(
        path: Routes.stack,
        builder: (_, __) => const StackV2Screen(showNavBar: false),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        coreDatabaseProvider.overrideWithValue(core),
        userDatabaseProvider.overrideWithValue(userDb),
        activeStackProvider.overrideWith((ref) async => stack),
        synergyReportProvider.overrideWith(
          (ref) async => SynergyReport.empty(),
        ),
        recalledIngredientsReportProvider.overrideWith(
          (ref) async => RecalledIngredientsReport.empty(),
        ),
        stackDoseThresholdAlertsProvider.overrideWith((ref) async => const []),
        profileProvider.overrideWith((ref) => ProfileNotifier()),
        ...overrides,
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 150));
}

class _EmptyRulesRepository extends ReferenceDataRepository {
  @override
  Future<Map<String, dynamic>> loadMedicationProfileGateRules() async {
    return const {'medication_profile_gate_rules': <dynamic>[]};
  }
}

class _NoRecents extends RecentSearchesService {
  @override
  Future<List<String>> getRecent() async => const [];

  @override
  Future<void> addSearch(String query) async {}
}

class _OfflineBlobs extends DetailBlobService {
  @override
  Future<Map<String, dynamic>?> fetchDetailBlobByHash(String sha256) async {
    throw Exception('offline');
  }
}

Future<String> _rxNormHttp(Uri url) async {
  if (url.path == '/REST/approximateTerm.json') {
    return '{"approximateGroup":{"candidate":['
        '{"rxcui":"202488","name":"Motrin","score":"100"}]}}';
  }
  throw StateError('No fake RxNorm response for $url');
}

void main() {
  group('rules withheld or failed to open', () {
    for (final rules in _Rules.values) {
      group(rules.name, () {
        testWidgets('Quick Check: says so, still finds products, and a check '
            'is never a clean result', (tester) async {
          final core = await _catalog(tester);
          addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                coreDatabaseProvider.overrideWithValue(core),
                ..._rulesOverrides(rules, null),
              ],
              child: const MaterialApp(home: QuickCheckV2Screen()),
            ),
          );
          await tester.pump();
          expect(find.text(kRulesWithheldNotice), findsOneWidget);

          await tester.enterText(find.byType(TextField).first, 'magnesium');
          await tester.pump(const Duration(milliseconds: 350));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text('Magnesium One'), findsOneWidget);

          await tester.tap(find.text('Magnesium One'));
          await tester.pumpAndSettle();
          // A chosen slot hides its field, so the other slot's is now first.
          await tester.enterText(find.byType(TextField).first, 'magnesium');
          await tester.pump(const Duration(milliseconds: 350));
          await tester.pumpAndSettle();
          final second = find.text('Magnesium Two').last;
          await tester.ensureVisible(second);
          await tester.pumpAndSettle();
          await tester.tap(second);
          await tester.pumpAndSettle();

          final check = find.text('Check interactions');
          await tester.ensureVisible(check);
          await tester.pumpAndSettle();
          await tester.tap(check);
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(find.text('Database unavailable'), findsOneWidget);
          expect(find.text(kRulesWithheldNotice), findsOneWidget);
          _expectNoCleanResult(tester);
        });

        testWidgets('medication entry: says so, and a search neither hangs '
            'nor promises a check', (tester) async {
          addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                ..._rulesOverrides(rules, null),
                referenceDataRepositoryProvider.overrideWith(
                  (ref) => _EmptyRulesRepository(),
                ),
                loadedProfileProvider.overrideWith(
                  (ref) async => const ProfileState(),
                ),
              ],
              child: const MaterialApp(home: MedicationEntryV2Screen()),
            ),
          );
          await tester.pump();
          expect(find.text(kRulesWithheldNotice), findsOneWidget);

          await tester.enterText(
            find.byKey(const Key('med-entry-search')),
            'motrin',
          );
          await tester.pump(const Duration(milliseconds: 350));
          await tester.pump(const Duration(seconds: 1));

          expect(tester.takeException(), isNull);
          expect(find.text('No match found'), findsNothing);
          expect(find.text(kRulesWithheldNotice), findsOneWidget);
          _expectNoCleanResult(tester);
        });

        for (final (name, stack) in [
          ('empty', const <UserStacksLocalData>[]),
          ('with a product', [_stackRow(_productA, 'Magnesium One')]),
        ]) {
          testWidgets('stack ($name): says so once, with no clean result', (
            tester,
          ) async {
            final core = await _catalog(tester);
            await _pumpStack(
              tester,
              core: core,
              stack: stack,
              overrides: _rulesOverrides(rules, null),
            );
            await tester.pump(const Duration(milliseconds: 300));

            expect(tester.takeException(), isNull);
            expect(find.text(kRulesWithheldNotice), findsOneWidget);
            expect(find.text("Couldn't check your stack"), findsNothing);
            _expectNoCleanResult(tester);
          });
        }

        for (final (name, stack) in [
          ('empty stack', const <UserStacksLocalData>[]),
          ('a stack', [_stackRow(_productB, 'Magnesium Two')]),
        ]) {
          testWidgets('add sheet ($name): says so, and promises nothing', (
            tester,
          ) async {
            final core = await _catalog(tester);
            final userDb = UserDatabase.memory();
            addTearDown(userDb.close);
            addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
            final haptics = <Object?>[];
            tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
              SystemChannels.platform,
              (call) async {
                if (call.method == 'HapticFeedback.vibrate') {
                  haptics.add(call.arguments);
                }
                return null;
              },
            );
            addTearDown(
              () => tester.binding.defaultBinaryMessenger
                  .setMockMethodCallHandler(SystemChannels.platform, null),
            );
            await tester.pumpWidget(
              ProviderScope(
                overrides: [
                  coreDatabaseProvider.overrideWithValue(core),
                  userDatabaseProvider.overrideWithValue(userDb),
                  activeStackProvider.overrideWith((ref) async => stack),
                  ..._rulesOverrides(rules, null),
                ],
                child: MaterialApp(
                  home: Consumer(
                    builder: (context, ref, _) => Scaffold(
                      body: TextButton(
                        onPressed: () => showSafetyCheckSheet(
                          context,
                          ref,
                          dsldId: _productA,
                          productName: 'Magnesium One',
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

            expect(tester.takeException(), isNull);
            expect(find.text(kRulesWithheldNotice), findsOneWidget);
            expect(find.text('Could not verify interactions'), findsNothing);
            _expectNoCleanResult(tester);

            final add = find.text('Add to stack').last;
            if (tester
                    .widget<FilledButton>(
                      find.ancestor(
                        of: add,
                        matching: find.byType(FilledButton),
                      ),
                    )
                    .onPressed !=
                null) {
              await tester.tap(add);
              await tester.pumpAndSettle();
              // The success buzz means "nothing found"; a check never ran.
              expect(
                haptics,
                isNot(contains('HapticFeedbackType.mediumImpact')),
              );
              expect(
                haptics,
                isNot(contains('HapticFeedbackType.lightImpact')),
              );
            }
          });
        }
      });
    }

    group('control: with the rules', () {
      testWidgets('Quick Check, medication entry and stack show no notice', (
        tester,
      ) async {
        final core = await _catalog(tester);
        final rulesDb = InteractionDatabase.memory();
        addTearDown(rulesDb.close);
        final userDb = UserDatabase.memory();
        addTearDown(userDb.close);
        addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              coreDatabaseProvider.overrideWithValue(core),
              interactionDatabaseProvider.overrideWithValue(rulesDb),
              rxNormApiServiceProvider.overrideWithValue(
                RxNormApiService(httpGet: _rxNormHttp, offlineDb: rulesDb),
              ),
              referenceDataRepositoryProvider.overrideWith(
                (ref) => _EmptyRulesRepository(),
              ),
              loadedProfileProvider.overrideWith(
                (ref) async => const ProfileState(),
              ),
            ],
            child: const MaterialApp(home: QuickCheckV2Screen()),
          ),
        );
        await tester.pump();
        expect(find.text(kRulesWithheldNotice), findsNothing);

        await tester.pumpWidget(
          ProviderScope(
            key: UniqueKey(),
            overrides: [
              interactionDatabaseProvider.overrideWithValue(rulesDb),
              rxNormApiServiceProvider.overrideWithValue(
                RxNormApiService(httpGet: _rxNormHttp, offlineDb: rulesDb),
              ),
              referenceDataRepositoryProvider.overrideWith(
                (ref) => _EmptyRulesRepository(),
              ),
              loadedProfileProvider.overrideWith(
                (ref) async => const ProfileState(),
              ),
            ],
            child: const MaterialApp(home: MedicationEntryV2Screen()),
          ),
        );
        await tester.pump();
        expect(find.text(kRulesWithheldNotice), findsNothing);
        await tester.enterText(
          find.byKey(const Key('med-entry-search')),
          'motrin',
        );
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('med-entry-suggestion-202488')),
          findsOneWidget,
        );

        await _pumpStack(
          tester,
          core: core,
          stack: [_stackRow(_productA, 'Magnesium One')],
          overrides: [
            interactionDatabaseProvider.overrideWithValue(rulesDb),
            stackSafetyReportProvider.overrideWith(
              (ref) async => const StackSafetyReport(),
            ),
          ],
        );
        expect(find.text(kRulesWithheldNotice), findsNothing);
      });
    });
  });

  group('quality scores withheld', () {
    Future<void> pumpSearch(WidgetTester tester, CoreDatabase core) async {
      addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            coreDatabaseProvider.overrideWithValue(core),
            recentSearchesServiceProvider.overrideWithValue(_NoRecents()),
          ],
          child: const MaterialApp(home: SearchV2Screen()),
        ),
      );
      await tester.pump();
      await tester.enterText(find.byType(TextField).first, 'magnesium');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
    }

    Future<void> pumpCompare(WidgetTester tester, CoreDatabase core) async {
      final userDb = UserDatabase.memory();
      addTearDown(userDb.close);
      addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            coreDatabaseProvider.overrideWithValue(core),
            userDatabaseProvider.overrideWithValue(userDb),
            detailBlobServiceProvider.overrideWithValue(_OfflineBlobs()),
          ],
          child: const MaterialApp(
            home: CompareScreen(dsldIdA: _productA, dsldIdB: _productB),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> pumpStackRows(WidgetTester tester, CoreDatabase core) async {
      await _pumpStack(
        tester,
        core: core,
        stack: [_stackRow(_productA, 'Magnesium One')],
        overrides: [
          stackSafetyReportProvider.overrideWith(
            (ref) async => const StackSafetyReport(),
          ),
        ],
      );
      await tester.pump(const Duration(milliseconds: 300));
    }

    Finder score() => find.textContaining('86', skipOffstage: false);

    for (final (screen, pump) in [
      ('search rows', pumpSearch),
      ('stack rows', pumpStackRows),
      ('Compare', pumpCompare),
    ]) {
      testWidgets('$screen: says so, and shows no score', (tester) async {
        final core = await _catalog(tester, qualityWithheld: true);
        await pump(tester, core);

        expect(tester.takeException(), isNull);
        expect(find.text(kQualityWithheldNotice), findsOneWidget);
        expect(score(), findsNothing);
        expect(find.text('Magnesium One', skipOffstage: false), findsWidgets);
      });

      testWidgets('$screen control: scored catalog shows the score and no '
          'notice', (tester) async {
        final core = await _catalog(tester);
        await pump(tester, core);

        expect(find.text(kQualityWithheldNotice), findsNothing);
        expect(score(), findsWidgets);
      });
    }
  });
}
