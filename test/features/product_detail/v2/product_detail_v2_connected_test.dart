import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/components/pg_ingredient_tile.dart';
import 'package:pharmaguide/core/components/pg_score_breakdown_card.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/interaction_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/data/providers/reference_data_provider.dart';
import 'package:pharmaguide/features/product_detail/providers/detail_blob_provider.dart';
import 'package:pharmaguide/core/models/fit_score_result.dart';
import 'package:pharmaguide/features/product_detail/providers/fit_score_provider.dart';
import 'package:pharmaguide/features/product_detail/providers/profile_warning_rule_provider.dart';
import 'package:pharmaguide/features/product_detail/providers/personalized_warnings_provider.dart';
import 'package:pharmaguide/features/product_detail/v2/product_detail_v2_connected.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/ingredients_section.dart';
import 'package:pharmaguide/features/safety_alerts/providers/safety_alert_providers.dart';
import 'package:pharmaguide/services/connectivity_service.dart';
import 'package:pharmaguide/services/safety_alerts/safety_alert.dart';
import 'package:pharmaguide/services/safety_alerts/safety_alert_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';
import 'package:pharmaguide/features/stack/providers/active_stack_provider.dart';
import 'package:pharmaguide/features/stack/providers/stack_safety_providers.dart';

const _connectedDsldId = 'label-ledger-connected';
const _connectedFingerprint =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

Map<String, dynamic> _connectedLabelRecord() {
  const fields = <String, String>{
    'source_name': 'NIH DSLD',
    'source_record_id': '999',
    'catalog_version': '7',
    'formula_fingerprint': _connectedFingerprint,
    'source_date': '2026-01-01',
    'source_updated_date': '2026-01-02T00:00:00Z',
    'product_status': 'active',
    'label_source_url': 'https://example.test/labels/999',
    'lineage_key': 'dsld:999',
  };
  return {
    ...fields,
    'field_statuses': {for (final field in fields.keys) field: 'available'},
    'metadata_status': 'available',
    'metadata_issues': const <String>[],
    'history_status': 'available',
    'formula_history': [
      {
        'snapshot_id': 'older-label',
        'source_record_id': '999',
        'lineage_key': 'dsld:999',
        'formula_fingerprint':
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        'source_date': '2025-01-01',
        'display_ingredients': const [
          {
            'label_order': 0,
            'nested_depth': 0,
            'label_display_name': 'EPA',
            'exact_dose_text': '300 mg',
          },
        ],
      },
    ],
  };
}

Future<void> _seedConnectedProduct(
  CoreDatabase coreDb, {
  bool blocked = false,
  double mappedCoverage = 1,
}) async {
  await _seedProduct(
    coreDb,
    dsldId: _connectedDsldId,
    productName: 'Connected Label Trust Product',
    blocked: blocked,
    mappedCoverage: mappedCoverage,
  );
}

Future<void> _seedProduct(
  CoreDatabase coreDb, {
  required String dsldId,
  required String productName,
  bool blocked = false,
  double mappedCoverage = 1,
}) async {
  await coreDb
      .into(coreDb.productsCore)
      .insert(
        ProductsCoreCompanion.insert(
          dsldId: dsldId,
          productName: productName,
          exportVersion: 'test',
          exportedAt: '2026-07-19T00:00:00Z',
          qualityScoreV4100: const Value(88),
          qualityScoreStatus: const Value('scored'),
          mappedCoverage: Value(mappedCoverage),
          verdict: Value(blocked ? 'BLOCKED' : 'SAFE'),
          productSafetyStatus: Value(blocked ? 'blocked' : null),
          blockingReason: Value(blocked ? 'banned_ingredient' : null),
          hasBannedSubstance: Value(blocked ? 1 : 0),
          topWarnings: Value(
            blocked
                ? '[{"type":"banned_substance","severity":"critical",'
                      '"title":"Banned substance: organic Hemp Oil extract"}]'
                : null,
          ),
        ),
      );
}

Map<String, dynamic> _connectedV4Pillars() => {
  'formulation': {
    'score': 12.0,
    'max': 20,
    'reason': 'Pipeline formulation reason.',
  },
  'dose': {'score': 20.0, 'max': 20, 'reason': 'Pipeline dose reason.'},
  'evidence': {'score': 17.0, 'max': 20, 'reason': 'Pipeline evidence reason.'},
  'transparency': {
    'score': 14.0,
    'max': 15,
    'reason': 'Pipeline transparency reason.',
  },
  'verification': {
    'score': 15.0,
    'max': 15,
    'reason': 'Pipeline verification reason.',
  },
  'safety_hygiene': {
    'score': 10.0,
    'max': 10,
    'reason': 'Pipeline safety reason.',
  },
};

Map<String, dynamic> _zeroTransparencyPillars() {
  final pillars = _connectedV4Pillars();
  pillars['transparency'] = {
    'score': 0.0,
    'max': 15,
    'reason': 'Pipeline transparency reason.',
  };
  return pillars;
}

Map<String, dynamic> _activeLedgerRow(String name, int order) => {
  'label_display_name': name,
  'label_order': order,
  'nested_depth': 0,
  'score_included': true,
  'display_disposition': 'scored',
  'form_display_state': 'not_disclosed',
};

/// How the interaction rules reach the page. On a phone, withheld rules and
/// rules that failed to open both leave the provider unset (lib/main.dart).
enum _Rules { available, unset, failing }

const _rulesNotice =
    'Interaction checks are temporarily unavailable. Product information is '
    'still available.';

Future<void> _pumpConnectedScreen(
  WidgetTester tester, {
  required Map<String, dynamic>? detailBlob,
  String? initialSection = 'ingredients',
  bool fitFails = false,
  Completer<void>? fitGate,
  List<int>? fitCalls,
  bool settle = true,
  bool blocked = false,
  double mappedCoverage = 1,
  FitScoreResult? fitResult,
  bool profiled = false,
  bool warningsFail = false,
  bool profileRulesFail = false,
  List<UserStacksLocalData>? stack,
  bool classLookupFails = false,
  Set<String> stackMedicationClassIds = const {},
  _Rules rules = _Rules.available,
  bool realWarnings = false,
  List<SafetyAlert> liveAlerts = const [],
  bool qualityWithheld = false,
  SafetyAlertRepository Function()? buildAlertFeed,
  Stream<ConnectionStatus>? connection,
}) async {
  final coreDb = CoreDatabase.memory(qualityWithheld: qualityWithheld);
  final userDb = UserDatabase.memory();
  final interactionDb = InteractionDatabase.memory();
  await _seedConnectedProduct(
    coreDb,
    blocked: blocked,
    mappedCoverage: mappedCoverage,
  );
  if (qualityWithheld) await coreDb.withholdQualityScores();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await coreDb.close();
    await userDb.close();
    await interactionDb.close();
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        coreDatabaseProvider.overrideWithValue(coreDb),
        userDatabaseProvider.overrideWithValue(userDb),
        if (rules == _Rules.available)
          interactionDatabaseProvider.overrideWithValue(interactionDb),
        if (rules == _Rules.failing)
          interactionDatabaseProvider.overrideWith(
            (ref) => throw StateError('This rules file will not open'),
          ),
        if (liveAlerts.isNotEmpty)
          productSafetyAlertsProvider.overrideWith(
            (ref, product) async => liveAlerts,
          ),
        safetyAlertRepositoryProvider.overrideWith(
          (ref) => (buildAlertFeed ?? _VerifiedNoAlerts.new)(),
        ),
        if (connection != null)
          connectionStatusProvider.overrideWith((ref) => connection),
        detailBlobProvider.overrideWith((ref, dsldId) async {
          expect(dsldId, _connectedDsldId);
          return detailBlob;
        }),
        if (profiled)
          profileProvider.overrideWith(
            (ref) => ProfileNotifier()..setAgeBracket('31-50'),
          ),
        if (!realWarnings)
          personalizedInteractionWarningsProvider.overrideWith((
            ref,
            dsldId,
          ) async {
            if (warningsFail) throw StateError('interaction check unavailable');
            return const [];
          }),
        if (profileRulesFail)
          profileWarningRuleWarningsProvider.overrideWith(
            (ref, dsldId) async => throw StateError('rules unavailable'),
          ),
        fitScoreForProductProvider.overrideWith((ref, dsldId) async {
          fitCalls?.add(1);
          if (fitGate != null) await fitGate.future;
          if (fitFails && (fitCalls == null || fitCalls.length == 1)) {
            throw StateError('fit inputs unavailable');
          }
          return fitResult;
        }),
        if (stack != null)
          activeStackProvider.overrideWith((ref) async => stack),
        currentStackMedicationClassIdsProvider.overrideWith((ref) async {
          if (classLookupFails) throw StateError('rules withheld');
          return stackMedicationClassIds;
        }),
        // The clinical schema behind these flags is an app asset that never
        // resolves in widget tests; left pending, every check stays running.
        evaluatorProfileFlagsProvider.overrideWith(
          (ref) async => const <String>{},
        ),
        rdaOptimalUlsProvider.overrideWith((ref) async => const {}),
      ],
      child: Consumer(
        builder: (context, ref, child) {
          if (connection != null) ref.watch(safetyAlertRefreshProvider);
          return child!;
        },
        child: MaterialApp(
          home: ProductDetailV2ConnectedScreen(
            dsldId: _connectedDsldId,
            initialSection: initialSection,
          ),
        ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
}

/// A feed that loaded and has nothing to say, for tests about something else.
class _VerifiedNoAlerts implements SafetyAlertRepository {
  @override
  Future<SafetyAlertRelease> loadCurrent() async => const SafetyAlertRelease(
    alerts: [],
    baselineRevisions: {},
    isComplete: true,
  );

  @override
  Future<List<SafetyAlert>> loadCachedAlerts() async => const [];
}

enum _FeedServer { unreachable, noCurrentRelease, serving, servingNoAlerts }

/// The real repository over a fake server and this phone's saved preferences.
class _AlertFeed {
  _AlertFeed() {
    // Nothing here signs in, and its refresh timer would outlive the test.
    _client.auth.stopAutoRefresh();
  }

  static final _alertsForOtherProducts = File(
    'test/fixtures/safety_alerts/interaction_rule_base_feed.json',
  ).readAsBytesSync();
  static final _noAlerts = utf8.encode('{"alerts":[]}');

  var server = _FeedServer.unreachable;
  Completer<void>? gate;
  final saved = _SavedPreferences();

  late final _client = SupabaseClient(
    'https://example.test',
    'test-key',
    httpClient: MockClient((request) async {
      await gate?.future;
      switch (server) {
        case _FeedServer.unreachable:
          throw http.ClientException('offline');
        case _FeedServer.noCurrentRelease:
          return http.Response(
            'null',
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        case _FeedServer.serving || _FeedServer.servingNoAlerts:
          final bytes = server == _FeedServer.serving
              ? _alertsForOtherProducts
              : _noAlerts;
          if (request.url.path.contains('/storage/')) {
            return http.Response.bytes(bytes, 200, request: request);
          }
          return http.Response(
            jsonEncode({
              'feed_path': 'safety/feed.json',
              'checksum': 'sha256:${sha256.convert(bytes)}',
              'manifest': null,
            }),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
      }
    }),
  );

  late final repository = SafetyAlertRepository(
    client: _client,
    preferences: saved,
  );

  /// Fetches once, so this phone holds a verified copy, then loses the server.
  Future<void> saveACopyThenGoOffline() async {
    server = _FeedServer.serving;
    await repository.loadCurrent();
    server = _FeedServer.unreachable;
  }
}

class _SavedPreferences implements SharedPreferencesAsync {
  final values = <String, String>{};

  @override
  Future<String?> getString(String key) async => values[key];

  @override
  Future<void> setString(String key, String value) async => values[key] = value;

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnreadablePreferences extends _SavedPreferences {
  @override
  Future<String?> getString(String key) async =>
      throw StateError('This storage will not open');
}

class _FailingCoreDatabase extends CoreDatabase {
  _FailingCoreDatabase() : super.memory();

  var failing = true;

  @override
  Future<ProductsCoreData?> findById(String dsldId) => failing
      ? Future.error(StateError('disk I/O error'))
      : super.findById(dsldId);
}

Future<void> _scrollConnectedTowardTop(WidgetTester tester) async {
  final scrollView = find.byType(CustomScrollView);
  for (var attempt = 0; attempt < 8; attempt++) {
    await tester.drag(scrollView, const Offset(0, 400));
    await tester.pumpAndSettle();
  }
}

Future<void> _scrollConnectedTowardBottomUntil(
  WidgetTester tester,
  Finder target,
) async {
  final scrollView = find.byType(CustomScrollView);
  for (var attempt = 0; attempt < 12 && target.evaluate().isEmpty; attempt++) {
    await tester.drag(scrollView, const Offset(0, -250));
    await tester.pumpAndSettle();
  }
}

Widget _ingredientsHarness({
  required List<Map<String, dynamic>> ingredients,
  List<Map<String, dynamic>>? displayIngredients,
  List<Map<String, dynamic>> inactiveIngredients = const [],
  TextScaler? textScaler,
  bool scrollable = false,
}) {
  return MaterialApp(
    builder: textScaler == null
        ? null
        : (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: textScaler),
            child: child!,
          ),
    home: Scaffold(
      body: Builder(
        builder: (context) {
          final section = buildIngredientsSection(
            context: context,
            ingredients: ingredients,
            displayIngredients: displayIngredients,
            inactiveIngredients: inactiveIngredients,
            ulAnalysis: null,
            blends: const [],
          );
          return scrollable ? SingleChildScrollView(child: section) : section;
        },
      ),
    ),
  );
}

List<Map<String, dynamic>> _analysisLedger() => [
  {
    'label_display_name': 'Fish Oil',
    'exact_dose_text': '2,400 mg',
    'label_order': 0,
    'nested_depth': 0,
    'score_included': true,
    'display_disposition': 'scored',
    'form_display_state': 'not_disclosed',
  },
  {
    'label_display_name': 'Total Omega-3 Fatty Acids',
    'exact_dose_text': '720 mg',
    'label_order': 1,
    'nested_depth': 1,
    'parent_label': 'Fish Oil',
    'score_included': false,
    'display_disposition': 'label_context',
    'form_display_state': 'not_applicable',
  },
  {
    'label_display_name': 'EPA',
    'exact_dose_text': '360 mg',
    'label_order': 2,
    'nested_depth': 2,
    'parent_label': 'Total Omega-3 Fatty Acids',
    'score_included': true,
    'display_disposition': 'scored',
    'form_display_state': 'not_disclosed',
  },
  {
    'label_display_name': 'DHA',
    'exact_dose_text': '240 mg',
    'label_order': 3,
    'nested_depth': 2,
    'parent_label': 'Total Omega-3 Fatty Acids',
    'score_included': true,
    'display_disposition': 'scored',
    'form_display_state': 'not_disclosed',
  },
  {
    'label_display_name': 'Other Omega-3 Fatty Acids',
    'exact_dose_text': '120 mg',
    'label_order': 4,
    'nested_depth': 2,
    'parent_label': 'Total Omega-3 Fatty Acids',
    'score_included': false,
    'display_disposition': 'label_context',
    'form_display_state': 'not_applicable',
  },
];

void main() {
  group('source-backed blend disclosure', () {
    for (final level in ['full', 'partial', 'none', 'invalid']) {
      testWidgets(
        'does not turn $level blend disclosure into global coverage',
        (tester) async {
          await _pumpConnectedScreen(
            tester,
            initialSection: null,
            detailBlob: {
              'ingredients': const <Map<String, dynamic>>[],
              'display_ingredients': [
                _activeLedgerRow('Declared preparation', 0),
              ],
              'quality_pillars_v4': _connectedV4Pillars(),
              'proprietary_blend_detail': {
                'has_proprietary_blends': true,
                'blends': [
                  {
                    'name': 'Label preparation',
                    'disclosure_level': level,
                    'total_weight': 500,
                    'unit': 'mg',
                  },
                ],
              },
            },
          );
          expect(find.text('88/100'), findsOneWidget);
          expect(find.text('Blend amounts not disclosed'), findsNothing);
          expect(find.textContaining('Analysis coverage'), findsNothing);
          expect(find.text('Some blend amounts not disclosed'), findsNothing);
          expect(find.text('Blend composition incomplete'), findsNothing);
          expect(find.text('Blend disclosure not verified'), findsNothing);
        },
      );
    }
  });
  group('connected unavailable states', () {
    testWidgets('a failed catalog read leaves the loading state', (
      tester,
    ) async {
      final coreDb = _FailingCoreDatabase();
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
            home: ProductDetailV2ConnectedScreen(dsldId: _connectedDsldId),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Product unavailable'), findsNothing);
      expect(find.textContaining('not an all-clear'), findsOneWidget);

      coreDb.failing = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      // The read works now, and this id genuinely isn't in the catalog.
      expect(find.text('Product unavailable'), findsOneWidget);
    });

    testWidgets('low coverage keeps the score and shows coverage beside it', (
      tester,
    ) async {
      await _pumpConnectedScreen(
        tester,
        mappedCoverage: 0.2,
        initialSection: null,
        detailBlob: {
          'ingredients': const <Map<String, dynamic>>[],
          'display_ingredients': [_activeLedgerRow('Active row', 0)],
          'quality_pillars_v4': _connectedV4Pillars(),
        },
      );

      expect(find.text('88/100'), findsOneWidget);
      expect(find.text('Analysis coverage: Limited'), findsOneWidget);
      expect(find.text('Product quality score unavailable.'), findsNothing);
    });

    testWidgets('fit failure is visible and cannot look like an all-clear', (
      tester,
    ) async {
      await _pumpConnectedScreen(
        tester,
        fitFails: true,
        initialSection: null,
        detailBlob: {
          'ingredients': const <Map<String, dynamic>>[],
          'display_ingredients': [_activeLedgerRow('Active row', 0)],
          'quality_pillars_v4': _connectedV4Pillars(),
        },
      );

      expect(
        find.byKey(const Key('personalized-checks-error-banner')),
        findsOneWidget,
      );
      expect(find.text('Personalized checks are incomplete'), findsOneWidget);
      expect(find.textContaining('not an all-clear'), findsOneWidget);
    });

    testWidgets(
      'withheld rules keep a catalog warning for a medication already on the stack',
      (tester) async {
        final addedAt = DateTime.utc(2026, 11, 3);
        await _pumpConnectedScreen(
          tester,
          initialSection: null,
          warningsFail: true,
          classLookupFails: true,
          rules: _Rules.unset,
          stack: [
            UserStacksLocalData(
              id: 'warfarin',
              type: 'medication',
              name: 'Warfarin',
              rxcui: '11289',
              drugClassesCol: '["class:anticoagulants"]',
              addedAt: addedAt,
              clientUpdatedAt: addedAt,
            ),
          ],
          detailBlob: {
            'ingredients': const <Map<String, dynamic>>[],
            'display_ingredients': [_activeLedgerRow('Active row', 0)],
            'quality_pillars_v4': _connectedV4Pillars(),
            'warnings': [
              {
                'type': 'interaction',
                'severity': 'contraindicated',
                'alert_headline': 'Do not combine with warfarin',
                'alert_body': 'Catalog warning body.',
                'evidence_level': 'established',
                'drug_class_ids': ['anticoagulants'],
              },
            ],
          },
        );

        expect(find.text(_rulesNotice), findsOneWidget);
        expect(find.text('Do not combine with warfarin'), findsOneWidget);
      },
    );

    group('quality scores that are withheld', () {
      const qualityNotice =
          'Quality scores are temporarily unavailable. Product information is '
          'still available.';
      final blob = <String, dynamic>{
        'quality_pillars_v4': _connectedV4Pillars(),
      };

      testWidgets('the page says so and shows no score', (tester) async {
        await _pumpConnectedScreen(
          tester,
          initialSection: null,
          detailBlob: blob,
          qualityWithheld: true,
        );

        expect(find.text(qualityNotice), findsOneWidget);
        expect(find.textContaining('88', skipOffstage: false), findsNothing);
      });

      testWidgets('the same product with its score shows no notice', (
        tester,
      ) async {
        await _pumpConnectedScreen(
          tester,
          initialSection: null,
          detailBlob: blob,
        );

        expect(find.text(qualityNotice), findsNothing);
        expect(find.text('88/100'), findsOneWidget);
      });
    });

    group('an alert feed this phone has never had', () {
      const cleanFit = FitScoreResult(
        missingFields: [],
        state: FitAssessmentState.limitedFit,
        reasons: [],
        mappedCoverage: 1,
      );
      const allClear = 'No known concerns';
      const incomplete = 'Personalized checks are incomplete';
      final blob = <String, dynamic>{
        'ingredients': const <Map<String, dynamic>>[],
        'display_ingredients': [_activeLedgerRow('Active row', 0)],
        'quality_pillars_v4': _connectedV4Pillars(),
      };
      final addedAt = DateTime.utc(2026, 11, 3);
      final supplementRow = UserStacksLocalData(
        id: 'other',
        type: 'supplement',
        name: 'Another supplement',
        addedAt: addedAt,
        clientUpdatedAt: addedAt,
      );

      Future<void> settleFeed(WidgetTester tester) async {
        for (var i = 0; i < 6; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          // A failed fetch retries after 1, 2 and 4 seconds.
          await tester.pump(const Duration(seconds: 2));
        }
      }

      Future<void> open(
        WidgetTester tester,
        _AlertFeed? feed, {
        SafetyAlertRepository Function()? buildAlertFeed,
        bool profiled = true,
        List<UserStacksLocalData> stack = const [],
        Stream<ConnectionStatus>? connection,
      }) async {
        await _pumpConnectedScreen(
          tester,
          initialSection: null,
          detailBlob: blob,
          settle: false,
          profiled: profiled,
          fitResult: cleanFit,
          realWarnings: true,
          stack: stack,
          buildAlertFeed: buildAlertFeed ?? () => feed!.repository,
          connection: connection,
        );
        await settleFeed(tester);
      }

      for (final profiled in [true, false]) {
        for (final (stackName, stack) in [
          ('empty stack', const <UserStacksLocalData>[]),
          ('stack', [supplementRow]),
        ]) {
          testWidgets(
            'offline, ${profiled ? 'profile' : 'no profile'}, $stackName: '
            'says the checks are incomplete, and is never an all-clear',
            (tester) async {
              await open(
                tester,
                _AlertFeed(),
                profiled: profiled,
                stack: stack,
              );

              expect(find.text(allClear), findsNothing);
              expect(find.text(incomplete), findsOneWidget);
              expect(find.text('Retry'), findsOneWidget);
            },
          );
        }
      }

      testWidgets('a saved copy keeps its result when the fetch fails', (
        tester,
      ) async {
        final feed = _AlertFeed();
        await tester.runAsync(feed.saveACopyThenGoOffline);

        await open(tester, feed);

        expect(find.text(allClear), findsOneWidget);
        expect(find.text(incomplete), findsNothing);
      });

      testWidgets('a successful fetch gives the all-clear', (tester) async {
        await open(tester, _AlertFeed()..server = _FeedServer.serving);

        expect(find.text(allClear), findsOneWidget);
        expect(find.text(incomplete), findsNothing);
      });

      testWidgets('a verified feed with no alerts keeps the all-clear', (
        tester,
      ) async {
        await open(tester, _AlertFeed()..server = _FeedServer.servingNoAlerts);

        expect(find.text(allClear), findsOneWidget);
        expect(find.text(incomplete), findsNothing);
      });

      testWidgets('a saved copy with no alerts keeps the all-clear offline', (
        tester,
      ) async {
        final feed = _AlertFeed()..server = _FeedServer.servingNoAlerts;
        await tester.runAsync(feed.repository.loadCurrent);
        feed.server = _FeedServer.unreachable;

        await open(tester, feed);

        expect(find.text(allClear), findsOneWidget);
        expect(find.text(incomplete), findsNothing);
      });

      testWidgets('a finding stays on screen when the all-clear is withheld', (
        tester,
      ) async {
        await _pumpConnectedScreen(
          tester,
          initialSection: null,
          settle: false,
          profiled: true,
          fitResult: cleanFit,
          realWarnings: true,
          stack: [
            UserStacksLocalData(
              id: 'warfarin',
              type: 'medication',
              name: 'Warfarin',
              rxcui: '11289',
              drugClassesCol: '["class:anticoagulants"]',
              addedAt: addedAt,
              clientUpdatedAt: addedAt,
            ),
          ],
          stackMedicationClassIds: const {'anticoagulants'},
          buildAlertFeed: () => _AlertFeed().repository,
          detailBlob: {
            ...blob,
            'warnings': [
              {
                'type': 'interaction',
                'severity': 'contraindicated',
                'alert_headline': 'Do not combine with warfarin',
                'alert_body': 'Catalog warning body.',
                'evidence_level': 'established',
                'drug_class_ids': ['anticoagulants'],
              },
            ],
          },
        );
        await settleFeed(tester);

        expect(find.text('Do not combine with warfarin'), findsOneWidget);
        expect(find.text(incomplete), findsOneWidget);
        expect(find.text(allClear), findsNothing);
      });

      // The server answered and has published nothing, which is the live state
      // until a first release. No bytes were verified, so it isn't a verified
      // empty feed; no fetch failed, so it isn't a feed that never loaded.
      testWidgets('no current release is not a failure', (tester) async {
        await open(tester, _AlertFeed()..server = _FeedServer.noCurrentRelease);

        expect(find.text(allClear), findsOneWidget);
        expect(find.text(incomplete), findsNothing);
      });

      testWidgets('no current release saves no copy, so a failed fetch after '
          'it is withheld', (tester) async {
        final feed = _AlertFeed()..server = _FeedServer.noCurrentRelease;
        await tester.runAsync(feed.repository.loadCurrent);
        feed.server = _FeedServer.unreachable;

        await open(tester, feed);

        expect(find.text(allClear), findsNothing);
        expect(find.text(incomplete), findsOneWidget);
      });

      testWidgets('a corrupt saved copy counts as no copy', (tester) async {
        final feed = _AlertFeed();
        await tester.runAsync(feed.saveACopyThenGoOffline);
        feed.saved.values['safety_alert_release_v1'] = '{corrupt';

        await open(tester, feed);

        expect(find.text(allClear), findsNothing);
        expect(find.text(incomplete), findsOneWidget);
      });

      testWidgets('a saved copy that can\'t be read counts as no copy', (
        tester,
      ) async {
        await open(
          tester,
          null,
          buildAlertFeed: () =>
              SafetyAlertRepository(preferences: _UnreadablePreferences()),
        );

        expect(find.text(allClear), findsNothing);
        expect(find.text(incomplete), findsOneWidget);
        expect(find.text('Retry'), findsOneWidget);
      });

      testWidgets('a feed that can\'t even be set up is withheld', (
        tester,
      ) async {
        await open(
          tester,
          null,
          buildAlertFeed: () => throw StateError('No storage on this phone'),
        );

        expect(find.text(allClear), findsNothing);
        expect(find.text(incomplete), findsOneWidget);
      });

      // Supabase failing to start on a phone is a failed fetch, not a lost copy.
      group('Supabase never started', () {
        testWidgets('no saved copy is withheld', (tester) async {
          final saved = _SavedPreferences();
          await open(
            tester,
            null,
            buildAlertFeed: () => SafetyAlertRepository(preferences: saved),
          );

          expect(find.text(allClear), findsNothing);
          expect(find.text(incomplete), findsOneWidget);
        });

        testWidgets('a saved copy keeps its result', (tester) async {
          final feed = _AlertFeed();
          await tester.runAsync(feed.saveACopyThenGoOffline);

          await open(
            tester,
            null,
            buildAlertFeed: () =>
                SafetyAlertRepository(preferences: feed.saved),
          );

          expect(find.text(allClear), findsOneWidget);
          expect(find.text(incomplete), findsNothing);
        });
      });

      testWidgets('reconnecting brings the all-clear back without a relaunch', (
        tester,
      ) async {
        final feed = _AlertFeed();
        final connection = StreamController<ConnectionStatus>.broadcast();
        addTearDown(connection.close);
        await open(tester, feed, connection: connection.stream);
        connection.add(ConnectionStatus.offline);
        await settleFeed(tester);
        expect(find.text(allClear), findsNothing);
        expect(find.text(incomplete), findsOneWidget);

        feed.server = _FeedServer.serving;
        connection.add(ConnectionStatus.online);
        await settleFeed(tester);

        expect(find.text(allClear), findsOneWidget);
        expect(find.text(incomplete), findsNothing);
      });

      testWidgets('Retry fetches the feed again', (tester) async {
        final feed = _AlertFeed();
        await open(tester, feed);
        expect(find.text(incomplete), findsOneWidget);

        feed.server = _FeedServer.serving;
        await tester.ensureVisible(find.text('Retry'));
        await tester.pump();
        await tester.tap(find.text('Retry'));
        await settleFeed(tester);

        await _scrollConnectedTowardTop(tester);
        expect(find.text(allClear), findsOneWidget);
        expect(find.text(incomplete), findsNothing);
      });

      testWidgets('a first fetch still running is not an all-clear', (
        tester,
      ) async {
        final feed = _AlertFeed()
          ..server = _FeedServer.serving
          ..gate = Completer<void>();
        await open(tester, feed);

        expect(find.text(allClear), findsNothing);
        expect(find.text('Checking this product for you'), findsOneWidget);

        feed.gate!.complete();
        await settleFeed(tester);

        expect(find.text(allClear), findsOneWidget);
      });
    });

    group('rules that are withheld or failed to open', () {
      const cleanFit = FitScoreResult(
        missingFields: [],
        state: FitAssessmentState.limitedFit,
        reasons: [],
        mappedCoverage: 1,
      );
      final blob = <String, dynamic>{
        'ingredients': const <Map<String, dynamic>>[],
        'display_ingredients': [_activeLedgerRow('Active row', 0)],
        'quality_pillars_v4': _connectedV4Pillars(),
      };
      final addedAt = DateTime.utc(2026, 11, 3);
      final supplementRow = UserStacksLocalData(
        id: 'other',
        type: 'supplement',
        name: 'Another supplement',
        addedAt: addedAt,
        clientUpdatedAt: addedAt,
      );

      for (final rules in [_Rules.unset, _Rules.failing]) {
        for (final (name, stack) in [
          ('an empty stack', const <UserStacksLocalData>[]),
          // The blob names no ingredients, so the provider returns before it
          // reads the rules.
          ('a stack and a product with no canonical ids', [supplementRow]),
        ]) {
          testWidgets('${rules.name}: $name is never an all-clear', (
            tester,
          ) async {
            await _pumpConnectedScreen(
              tester,
              initialSection: null,
              detailBlob: blob,
              profiled: true,
              fitResult: cleanFit,
              realWarnings: true,
              rules: rules,
              stack: stack,
            );

            expect(find.text('No known concerns'), findsNothing);
            expect(find.text(_rulesNotice), findsOneWidget);
            // Trying again can't bring withheld rules back.
            expect(find.text('Retry'), findsNothing);
          });
        }
      }

      testWidgets('a check that failed for its own reason can be retried', (
        tester,
      ) async {
        await _pumpConnectedScreen(
          tester,
          initialSection: null,
          detailBlob: blob,
          profiled: true,
          realWarnings: true,
          rules: _Rules.unset,
          stack: const [],
          fitFails: true,
        );

        expect(find.text(_rulesNotice), findsOneWidget);
        expect(find.text('Personalized checks are incomplete'), findsOneWidget);
        expect(find.text('Retry'), findsOneWidget);
        // Retrying can't bring the rules back, so the banner doesn't offer it.
        expect(find.textContaining('every profile check'), findsOneWidget);
        expect(find.textContaining('interaction and profile'), findsNothing);
        // The card has no result to show; the two lines above say why.
        expect(find.text('Profile assessment unavailable'), findsNothing);
        expect(find.text('No known concerns'), findsNothing);
      });

      testWidgets('a fit check the rules themselves stopped has no retry', (
        tester,
      ) async {
        await _pumpConnectedScreen(
          tester,
          initialSection: null,
          detailBlob: blob,
          profiled: true,
          realWarnings: true,
          rules: _Rules.unset,
          stack: const [],
          fitFails: true,
          classLookupFails: true,
        );

        expect(find.text(_rulesNotice), findsOneWidget);
        expect(find.text('Retry'), findsNothing);
      });

      // Offline is the detail blob not arriving.
      for (final (network, offlineBlob) in [
        ('online', blob),
        ('offline', null),
      ]) {
        for (final profiled in [true, false]) {
          for (final (stackName, stack) in [
            ('empty stack', const <UserStacksLocalData>[]),
            ('stack', [supplementRow]),
          ]) {
            testWidgets(
              '$network, ${profiled ? 'profile' : 'no profile'}, $stackName: '
              'says so, and is never an all-clear',
              (tester) async {
                await _pumpConnectedScreen(
                  tester,
                  initialSection: null,
                  detailBlob: offlineBlob,
                  profiled: profiled,
                  fitResult: cleanFit,
                  realWarnings: true,
                  rules: _Rules.unset,
                  stack: stack,
                );

                expect(find.text('No known concerns'), findsNothing);
                expect(find.text(_rulesNotice), findsOneWidget);
                expect(tester.takeException(), isNull);
              },
            );
          }
        }
      }

      testWidgets('control: with the rules, the same user gets the all-clear', (
        tester,
      ) async {
        for (final stack in [
          const <UserStacksLocalData>[],
          [supplementRow],
        ]) {
          await _pumpConnectedScreen(
            tester,
            initialSection: null,
            detailBlob: blob,
            profiled: true,
            fitResult: cleanFit,
            realWarnings: true,
            stack: stack,
          );

          expect(find.text('No known concerns'), findsOneWidget);
          expect(find.text(_rulesNotice), findsNothing);
          await tester.pumpWidget(const SizedBox.shrink());
        }
      });

      testWidgets(
        'no profile: invited to set one up, and told checks are off',
        (tester) async {
          await _pumpConnectedScreen(
            tester,
            initialSection: null,
            detailBlob: blob,
            realWarnings: true,
            rules: _Rules.unset,
            stack: const [],
          );

          expect(find.text('No known concerns'), findsNothing);
          expect(find.text('Check this product for you'), findsOneWidget);
          expect(find.text(_rulesNotice), findsOneWidget);
        },
      );

      testWidgets('a blob warning still shows, verbatim, ahead of the notice', (
        tester,
      ) async {
        await _pumpConnectedScreen(
          tester,
          initialSection: null,
          realWarnings: true,
          rules: _Rules.unset,
          stack: const [],
          profiled: true,
          fitResult: cleanFit,
          detailBlob: {
            ...blob,
            'warnings': [
              {
                'type': 'banned_substance',
                'severity': 'contraindicated',
                'alert_headline': 'Do not combine with warfarin',
                'alert_body': 'Catalog warning body.',
                'evidence_level': 'established',
              },
            ],
          },
        );

        expect(find.text('No known concerns'), findsNothing);
        expect(find.text('Do not combine with warfarin'), findsOneWidget);
        expect(find.text('Profile assessment unavailable'), findsNothing);
        expect(find.text(_rulesNotice), findsOneWidget);
      });

      testWidgets('a live recall still shows, verbatim', (tester) async {
        await _pumpConnectedScreen(
          tester,
          initialSection: null,
          detailBlob: blob,
          realWarnings: true,
          rules: _Rules.unset,
          stack: const [],
          profiled: true,
          fitResult: cleanFit,
          liveAlerts: [
            SafetyAlert(
              alertId: 'recall-1',
              revision: 1,
              eventType: SafetyAlertEventType.productRecall,
              sourceUrl: Uri.parse('https://www.fda.gov/recall-1'),
              headline: 'FDA recall: lot 42',
              body: 'Recall body.',
              action: 'Recall action.',
              disposition: SafetyAlertDisposition.block,
              resolvedDsldIds: const {_connectedDsldId},
              ingredientCanonicalIds: const {},
            ),
          ],
        );

        expect(find.text('FDA recall: lot 42'), findsOneWidget);
        expect(find.text('No known concerns'), findsNothing);
        expect(find.text(_rulesNotice), findsOneWidget);
      });

      testWidgets('a banned product keeps its block, verbatim', (tester) async {
        await _pumpConnectedScreen(
          tester,
          blocked: true,
          initialSection: null,
          detailBlob: blob,
          realWarnings: true,
          rules: _Rules.unset,
          stack: const [],
        );

        expect(
          find.text('Banned substance: organic Hemp Oil extract'),
          findsOneWidget,
        );
        expect(find.text('No known concerns'), findsNothing);
      });
    });

    group('a personal check that failed is never an all-clear', () {
      const cleanFit = FitScoreResult(
        missingFields: [],
        state: FitAssessmentState.limitedFit,
        reasons: [],
        mappedCoverage: 1,
      );
      final blob = <String, dynamic>{
        'ingredients': const <Map<String, dynamic>>[],
        'display_ingredients': [_activeLedgerRow('Active row', 0)],
        'quality_pillars_v4': _connectedV4Pillars(),
      };

      testWidgets('control: every check passing shows the all-clear', (
        tester,
      ) async {
        await _pumpConnectedScreen(
          tester,
          initialSection: null,
          detailBlob: blob,
          profiled: true,
          fitResult: cleanFit,
        );

        expect(find.text('No known concerns'), findsOneWidget);
      });

      for (final (name, warningsFail, profileRulesFail) in [
        ('interaction check', true, false),
        ('profile rule check', false, true),
      ]) {
        testWidgets('$name failed', (tester) async {
          await _pumpConnectedScreen(
            tester,
            initialSection: null,
            detailBlob: blob,
            profiled: true,
            fitResult: cleanFit,
            warningsFail: warningsFail,
            profileRulesFail: profileRulesFail,
          );

          expect(
            find.byKey(const Key('personalized-checks-error-banner')),
            findsOneWidget,
          );
          expect(find.text('No known concerns'), findsNothing);
        });
      }
    });

    // Critique 2026-09-29: checks still loading were reported as failed
    // ("incomplete… try again"), and the fit result is null while loading,
    // which a profiled user would otherwise see as "No known concerns".
    testWidgets('checks still running show a neutral checking state', (
      tester,
    ) async {
      final gate = Completer<void>();
      await _pumpConnectedScreen(
        tester,
        fitGate: gate,
        settle: false,
        initialSection: null,
        detailBlob: {
          'ingredients': const <Map<String, dynamic>>[],
          'display_ingredients': [_activeLedgerRow('Active row', 0)],
          'quality_pillars_v4': _connectedV4Pillars(),
        },
      );

      expect(
        find.byKey(const Key('personalized-checks-error-banner')),
        findsNothing,
      );
      expect(find.text('Checking this product for you'), findsOneWidget);
      expect(find.text('No known concerns'), findsNothing);

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Checking this product for you'), findsNothing);
    });

    // Critique 2026-09-29: the back button had no label, so VoiceOver read
    // only "button".
    testWidgets('the back button is labelled', (tester) async {
      await _pumpConnectedScreen(
        tester,
        initialSection: null,
        detailBlob: {
          'ingredients': const <Map<String, dynamic>>[],
          'display_ingredients': [_activeLedgerRow('Active row', 0)],
          'quality_pillars_v4': _connectedV4Pillars(),
        },
      );
      expect(find.byTooltip('Back'), findsOneWidget);
    });

    // Simulator walkthrough 2026-10-01: a blocked product showed "Personalized
    // checks are incomplete", "No comparable alternatives found" and a sticky
    // "See higher-quality options" together. The page hides personal results
    // on a blocked product, so a failed personal check has nothing to qualify,
    // and a button that leads to an empty section contradicts the card.
    testWidgets('blocked product: no checks banner, no empty alternatives', (
      tester,
    ) async {
      await _pumpConnectedScreen(
        tester,
        blocked: true,
        fitFails: true,
        initialSection: null,
        detailBlob: {
          'ingredients': const <Map<String, dynamic>>[],
          'display_ingredients': [_activeLedgerRow('Active row', 0)],
        },
      );

      expect(
        find.text('PharmaGuide does not recommend this product'),
        findsOneWidget,
      );
      expect(
        find.text('Banned substance: organic Hemp Oil extract'),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('personalized-checks-error-banner')),
        findsNothing,
      );
      await _scrollConnectedTowardBottomUntil(
        tester,
        find.text('No comparable alternatives found'),
      );
      expect(find.text('No comparable alternatives found'), findsNothing);
      expect(find.text('See higher-quality options'), findsNothing);
    });

    testWidgets('failed checks offer a Retry that runs them again', (
      tester,
    ) async {
      final calls = <int>[];
      await _pumpConnectedScreen(
        tester,
        fitFails: true,
        fitCalls: calls,
        initialSection: null,
        detailBlob: {
          'ingredients': const <Map<String, dynamic>>[],
          'display_ingredients': [_activeLedgerRow('Active row', 0)],
          'quality_pillars_v4': _connectedV4Pillars(),
        },
      );
      expect(calls, hasLength(1));

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(calls, hasLength(2));
      expect(
        find.byKey(const Key('personalized-checks-error-banner')),
        findsNothing,
      );
    });
  });

  testWidgets('status bar keeps an opaque backdrop over scrolled content', (
    tester,
  ) async {
    // 2026-09-16 walkthrough: once the floating app bar hid, card text
    // scrolled up under the clock with nothing behind it.
    tester.view.padding = const FakeViewPadding(top: 54 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await _pumpConnectedScreen(
      tester,
      initialSection: null,
      detailBlob: {
        'ingredients': const <Map<String, dynamic>>[],
        'display_ingredients': [_activeLedgerRow('Active row', 0)],
        'quality_pillars_v4': _connectedV4Pillars(),
      },
    );

    final backdrop = find.byKey(
      const Key('product-detail-status-bar-backdrop'),
    );
    expect(backdrop, findsOneWidget);
    expect(tester.getTopLeft(backdrop).dy, 0);
    expect(tester.getSize(backdrop).height, 54);
    final context = tester.element(backdrop);
    expect(
      tester.widget<ColoredBox>(backdrop).color,
      Theme.of(context).scaffoldBackgroundColor,
    );
  });

  // Critique 2026-09-29: tapping the iOS status bar did not scroll product
  // detail to the top. The page's own scroll controller was never the
  // primary one the Scaffold's status-bar handler animates.
  testWidgets('tapping the iOS status bar scrolls back to the top', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.padding = const FakeViewPadding(top: 54 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await _pumpConnectedScreen(
      tester,
      initialSection: null,
      detailBlob: {
        'ingredients': const <Map<String, dynamic>>[],
        'display_ingredients': [
          for (var i = 0; i < 30; i++) _activeLedgerRow('Active row $i', i),
        ],
        'quality_pillars_v4': _connectedV4Pillars(),
      },
    );
    ScrollPosition position() =>
        tester.state<ScrollableState>(find.byType(Scrollable).first).position;

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(position().pixels, greaterThan(0));

    tester.simulateStatusBarTap();
    await tester.pumpAndSettle();
    expect(position().pixels, 0);
    debugDefaultTargetPlatformOverride = null;
  });

  group('productDetailIngredientSourcesFromBlob', () {
    test('ledger key presence is authoritative and mixed rows fail closed', () {
      final absent = productDetailIngredientSourcesFromBlob(const {
        'ingredients': [
          {'display_label': 'Legacy score row'},
        ],
      });
      expect(absent.displayIngredients, isNull);
      expect(absent.ingredients.single['display_label'], 'Legacy score row');

      final presentEmpty = productDetailIngredientSourcesFromBlob(const {
        'display_ingredients': <Map<String, dynamic>>[],
        'ingredients': [
          {'display_label': 'Must not substitute for an empty ledger'},
        ],
      });
      expect(presentEmpty.displayIngredients, isEmpty);

      final mixed = productDetailIngredientSourcesFromBlob(const {
        'display_ingredients': [
          {'label_display_name': 'Valid-looking row'},
          'malformed row',
        ],
        'ingredients': [
          {'display_label': 'Must not replace a malformed ledger'},
        ],
      });
      expect(mixed.displayIngredients, isEmpty);
    });

    test('malformed legacy collections fail closed without throwing', () {
      late ProductDetailIngredientSources sources;

      expect(
        () => sources = productDetailIngredientSourcesFromBlob(const {
          'ingredients': [
            {'display_label': 'Valid-looking row'},
            7,
          ],
          'inactive_ingredients': 'not a list',
          'proprietary_blend_detail': {
            'blends': [
              {'name': 'Valid-looking blend'},
              false,
            ],
          },
        }),
        returnsNormally,
      );

      expect(sources.ingredients, isEmpty);
      expect(sources.inactiveIngredients, isEmpty);
      expect(sources.blends, isEmpty);
    });

    test('display rows never replace or mutate scoring inputs', () {
      final scoreRow = <String, dynamic>{
        'display_label': 'EPA',
        'quantity': 360,
        'unit': 'mg',
        'below_clinical_dose': true,
      };
      final displayRow = <String, dynamic>{
        'label_display_name': 'Total Omega-3 Fatty Acids',
        'exact_dose_text': '720 mg',
        'score_included': false,
        'display_disposition': 'label_context',
      };

      final sources = productDetailIngredientSourcesFromBlob({
        'ingredients': [scoreRow],
        'display_ingredients': [displayRow],
      });

      expect(sources.ingredients, hasLength(1));
      expect(sources.ingredients.single, {
        'display_label': 'EPA',
        'quantity': 360,
        'unit': 'mg',
        'below_clinical_dose': true,
      });
      expect(sources.displayIngredients, hasLength(1));
      expect(sources.displayIngredients!.single, {
        'label_display_name': 'Total Omega-3 Fatty Acids',
        'exact_dose_text': '720 mg',
        'score_included': false,
        'display_disposition': 'label_context',
      });
      expect(scoreRow.containsKey('score_included'), isFalse);
      expect(displayRow['score_included'], isFalse);
    });
  });

  group('connected blend metadata stays out of global coverage', () {
    final nonBooleanBlendFlags = <({String name, Object value})>[
      (name: 'numeric one', value: 1),
      (name: 'string one', value: '1'),
      (name: 'string true', value: 'true'),
    ];
    for (final flag in nonBooleanBlendFlags) {
      testWidgets('keeps bare ${flag.name} blend audit flag internal', (
        tester,
      ) async {
        await _pumpConnectedScreen(
          tester,
          initialSection: null,
          detailBlob: {
            'ingredients': const <Map<String, dynamic>>[],
            'display_ingredients': [_activeLedgerRow('Active row', 0)],
            'quality_pillars_v4': _connectedV4Pillars(),
            'proprietary_blend_detail': {'has_proprietary_blends': flag.value},
          },
        );

        final disclosure = find.text('Blend disclosure not verified');
        await _scrollConnectedTowardBottomUntil(tester, disclosure);
        expect(disclosure, findsNothing);
      });
    }

    testWidgets('keeps the authored boolean proprietary-blend signal local', (
      tester,
    ) async {
      await _pumpConnectedScreen(
        tester,
        initialSection: null,
        detailBlob: {
          'ingredients': const <Map<String, dynamic>>[],
          'display_ingredients': [_activeLedgerRow('Active row', 0)],
          'quality_pillars_v4': _connectedV4Pillars(),
          'proprietary_blend_detail': const {'has_proprietary_blends': true},
        },
      );

      final disclosure = find.text('Blend disclosure not verified');
      await _scrollConnectedTowardBottomUntil(tester, disclosure);
      expect(disclosure, findsNothing);
    });

    final falseBlendFlags = <({String name, Object value})>[
      (name: 'numeric zero', value: 0),
      (name: 'false-like string', value: 'false'),
    ];
    for (final flag in falseBlendFlags) {
      testWidgets('rejects ${flag.name} proprietary-blend flag', (
        tester,
      ) async {
        await _pumpConnectedScreen(
          tester,
          initialSection: null,
          detailBlob: {
            'ingredients': const <Map<String, dynamic>>[],
            'display_ingredients': [_activeLedgerRow('Active row', 0)],
            'quality_pillars_v4': _connectedV4Pillars(),
            'proprietary_blend_detail': {'has_proprietary_blends': flag.value},
          },
        );

        final disclosure = find.text('Blend disclosure not verified');
        await _scrollConnectedTowardBottomUntil(tester, disclosure);
        expect(disclosure, findsNothing);
      });
    }

    testWidgets(
      'transparency never repeats the visible label as a details action',
      (tester) async {
        await _pumpConnectedScreen(
          tester,
          initialSection: null,
          detailBlob: {
            'ingredients': const <Map<String, dynamic>>[],
            'display_ingredients': [_activeLedgerRow('Active row', 0)],
            'quality_pillars_v4': _zeroTransparencyPillars(),
          },
        );

        final transparency = find.text('Transparency');
        await _scrollConnectedTowardBottomUntil(tester, transparency);

        expect(find.text('Blend amounts not disclosed'), findsNothing);
        expect(transparency, findsOneWidget);
        expect(find.text('View label details'), findsNothing);
      },
    );

    final noTargetCases = <({String name, List<Map<String, dynamic>> rows})>[
      (name: 'present-empty', rows: const []),
      (
        name: 'nutrition-only',
        rows: [
          {
            ..._activeLedgerRow('Calories', 0),
            'display_type': 'nutrition_fact',
          },
        ],
      ),
      (
        name: 'inactive-only',
        rows: [
          {
            ..._activeLedgerRow('Gelatin', 0),
            'display_type': 'inactive_ingredient',
            'display_disposition': 'other_ingredient',
          },
        ],
      ),
    ];
    for (final targetCase in noTargetCases) {
      testWidgets('${targetCase.name} canonical ledger has no action', (
        tester,
      ) async {
        await _pumpConnectedScreen(
          tester,
          initialSection: null,
          detailBlob: {
            'ingredients': const <Map<String, dynamic>>[],
            'display_ingredients': targetCase.rows,
            'quality_pillars_v4': _zeroTransparencyPillars(),
          },
        );

        final transparency = find.text('Transparency');
        await _scrollConnectedTowardBottomUntil(tester, transparency);
        expect(transparency, findsOneWidget);
        expect(find.text('View label details'), findsNothing);
      });
    }
  });

  group('connected certification action', () {
    testWidgets('is hidden when no certification section can render', (
      tester,
    ) async {
      await _pumpConnectedScreen(
        tester,
        initialSection: null,
        detailBlob: {'quality_pillars_v4': _connectedV4Pillars()},
      );

      final testingBrand = find.text('Testing & Brand');
      await _scrollConnectedTowardBottomUntil(tester, testingBrand);
      expect(testingBrand, findsOneWidget);
      final scoreCard = tester.widget<PGScoreBreakdownCard>(
        find.byType(PGScoreBreakdownCard),
      );
      final verification = scoreCard.pillars.singleWhere(
        (pillar) => pillar.label == 'Testing & Brand',
      );
      expect(verification.actionLabel, isNull);
      expect(verification.onAction, isNull);
    });

    testWidgets('is shown when a verified certification can render', (
      tester,
    ) async {
      await _pumpConnectedScreen(
        tester,
        initialSection: null,
        detailBlob: {
          'quality_pillars_v4': _connectedV4Pillars(),
          'certification_detail': {
            'verified_programs': [
              {
                'name': 'USP Verified',
                'program': 'USP Verified',
                'record_id': 'USP_VERIFIED_1',
              },
            ],
          },
        },
      );

      final testingBrand = find.text('Testing & Brand');
      await _scrollConnectedTowardBottomUntil(tester, testingBrand);
      final scoreCard = tester.widget<PGScoreBreakdownCard>(
        find.byType(PGScoreBreakdownCard),
      );
      final verification = scoreCard.pillars.singleWhere(
        (pillar) => pillar.label == 'Testing & Brand',
      );
      expect(verification.actionLabel, 'View certifications');
      expect(verification.onAction, isNotNull);
    });
  });

  group('label ingredient ledger', () {
    testWidgets(
      'product data disclosure is a section card with a compact tail gap',
      (tester) async {
        await _pumpConnectedScreen(
          tester,
          initialSection: null,
          detailBlob: {
            'quality_pillars_v4': _connectedV4Pillars(),
            'label_record': _connectedLabelRecord(),
            'synergy_detail': {
              'clusters': [
                {
                  'name': 'Heart Health',
                  'evidence_tier': 1,
                  'match_count': 2,
                  'all_adequate': 1,
                },
              ],
            },
          },
        );

        final disclosureCard = find.byKey(
          const Key('product-data-sources-card'),
        );
        await _scrollConnectedTowardBottomUntil(tester, disclosureCard);
        expect(disclosureCard, findsOneWidget);

        final synergyCard = find.byKey(const Key('synergy-section-card'));
        expect(synergyCard, findsOneWidget);
        final decoration =
            tester.widget<Container>(disclosureCard).decoration
                as BoxDecoration;
        expect(decoration.color, V2Palette.light.surface);
        expect(decoration.border, isNotNull);
        expect(
          decoration.borderRadius,
          BorderRadius.circular(V2Spacing.radiusCard),
        );

        final gap =
            tester.getTopLeft(disclosureCard).dy -
            tester.getBottomLeft(synergyCard).dy;
        expect(gap, inInclusiveRange(8, V2Spacing.space24));
      },
    );

    testWidgets(
      'connected catalog keeps unsupported formula history UI removed',
      (tester) async {
        await _pumpConnectedScreen(
          tester,
          detailBlob: {
            'ingredients': const <Map<String, dynamic>>[],
            'display_ingredients': const [
              {
                'label_order': 0,
                'nested_depth': 0,
                'label_display_name': 'EPA',
                'exact_dose_text': '360 mg',
                'score_included': true,
                'display_disposition': 'scored',
                'form_display_state': 'not_disclosed',
              },
            ],
            'quality_pillars_v4': _connectedV4Pillars(),
            'label_record': _connectedLabelRecord(),
          },
        );

        final scrollView = find.byType(CustomScrollView);
        // Catalog details now live in the collapsed "Product data & sources"
        // section at the page bottom — scroll down to it and expand it.
        final disclosure = find.text('Product data & sources');
        for (
          var attempt = 0;
          attempt < 12 && disclosure.evaluate().isEmpty;
          attempt++
        ) {
          await tester.drag(scrollView, const Offset(0, -250));
          await tester.pumpAndSettle();
        }
        expect(disclosure, findsOneWidget);
        await tester.ensureVisible(disclosure);
        await tester.pumpAndSettle();
        await tester.tap(disclosure);
        await tester.pumpAndSettle();

        final action = find.byKey(const Key('formula-history-action'));
        expect(action, findsNothing);
        expect(find.text('Snapshot older-label'), findsNothing);
      },
    );

    testWidgets(
      'connected screen renders ledger identity while preserving pipeline score',
      (tester) async {
        final detailBlob = <String, dynamic>{
          'ingredients': [
            {
              'display_label': 'Scoring-only EPA identity',
              'standard_name': 'EPA',
              'quantity': 360,
              'unit': 'mg',
              'below_clinical_dose': true,
            },
          ],
          'display_ingredients': [
            {
              'label_display_name': 'Label Total Omega-3 Fatty Acids',
              'exact_dose_text': '720 mg',
              'label_order': 0,
              'nested_depth': 0,
              'raw_source_path': 'ingredientRows[0]',
              'score_included': false,
              'display_disposition': 'label_context',
              'form_display_state': 'not_applicable',
            },
          ],
          'quality_pillars_v4': _connectedV4Pillars(),
          'label_ledger_audit': {
            'support_status': 'supported',
            'source_structure': 'omega',
            'meaningful_source_rows': 1,
            'displayed_rows': 1,
            'omitted_rows': 0,
            'completeness_percentage': 100.0,
            'completeness_status': 'complete',
          },
        };

        await _pumpConnectedScreen(tester, detailBlob: detailBlob);

        expect(find.text('Label Total Omega-3 Fatty Acids'), findsOneWidget);
        expect(find.text('Scoring-only EPA identity'), findsNothing);

        await _scrollConnectedTowardTop(tester);
        // A 100%-complete label is now a silent success — no completeness row.
        expect(find.text('Label completeness: 100%'), findsNothing);
        expect(find.textContaining('Analysis coverage'), findsNothing);
        final scoreHeadline = find.text('Why this scored 88');
        await _scrollConnectedTowardBottomUntil(tester, scoreHeadline);
        expect(scoreHeadline, findsOneWidget);
        expect(find.text('12/20'), findsOneWidget);
      },
    );

    testWidgets(
      'connected screen renders the shipped category cap as explicit score math',
      (tester) async {
        final pillars = _connectedV4Pillars();
        pillars['formulation'] = {
          'score': 12.0,
          'max': 20,
          'reason': 'Pipeline formulation reason.',
          'components': {'score_before_public_cap': 13.0},
        };
        await _pumpConnectedScreen(
          tester,
          detailBlob: {
            'ingredients': const <Map<String, dynamic>>[],
            'display_ingredients': [_activeLedgerRow('Active row', 0)],
            'quality_pillars_v4': pillars,
            'quality_score_cap_v4': const {
              'applied': true,
              'score_before_cap': 89.0,
              'score_after_cap': 88.0,
            },
          },
        );

        final adjustment = find.text('Category calibration');
        await _scrollConnectedTowardBottomUntil(tester, adjustment);
        expect(find.text('Pillar subtotal'), findsOneWidget);
        expect(find.text('89/100'), findsOneWidget);
        expect(adjustment, findsOneWidget);
        expect(find.text('−1'), findsOneWidget);
        expect(find.text('Final score'), findsOneWidget);
        expect(find.text('88/100'), findsOneWidget);
      },
    );

    testWidgets(
      'probiotic research is embedded in clinical evidence and rendered once',
      (tester) async {
        tester.view.physicalSize = const Size(900, 1800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await _pumpConnectedScreen(
          tester,
          detailBlob: {
            'ingredients': const <Map<String, dynamic>>[],
            'display_ingredients': const [
              {
                'label_display_name': 'Lactobacillus acidophilus NCFM',
                'label_order': 0,
                'nested_depth': 0,
                'score_included': true,
                'display_disposition': 'scored',
                'form_display_state': 'not_disclosed',
              },
            ],
            'quality_pillars_v4': _connectedV4Pillars(),
            'evidence_data': const {
              'match_count': 1,
              'clinical_matches': [
                {
                  'ingredient': 'Lactobacillus acidophilus',
                  'evidence_level': 'ingredient-human',
                  'references_structured': [
                    {
                      'type': 'pubmed',
                      'pmid': '111',
                      'title': 'Lactobacillus human study',
                    },
                  ],
                },
              ],
            },
            'probiotic_detail': const {
              'total_cfu_label': '5 billion CFU',
              'probiotic_blends': [
                {
                  'strains': ['Lactobacillus acidophilus NCFM'],
                },
              ],
            },
          },
        );

        final ingredientsTitle = find.text('Active ingredients');
        final clinicalTitle = find.text('Clinical evidence');
        final probioticTitle = find.text('Probiotic label & research');
        expect(ingredientsTitle, findsOneWidget);
        expect(clinicalTitle, findsOneWidget);
        expect(probioticTitle, findsOneWidget);
        final clinicalToProbioticGap =
            tester.getTopLeft(probioticTitle).dy -
            tester.getTopLeft(clinicalTitle).dy;
        expect(clinicalToProbioticGap, greaterThan(0));
        expect(clinicalToProbioticGap, lessThan(500));
        final sectionGap =
            tester.getTopLeft(probioticTitle).dy -
            tester.getTopLeft(ingredientsTitle).dy;
        expect(sectionGap, greaterThan(0));
        // Since 2026-09-13 the clinical-evidence card (with the probiotic
        // context inside it) sits BELOW the quality breakdown: the score and
        // its reasons come first, the long cards after. Guard that order.
        final breakdown = find.byType(PGScoreBreakdownCard);
        expect(breakdown, findsOneWidget);
        expect(
          tester.getTopLeft(clinicalTitle).dy,
          greaterThan(tester.getTopLeft(breakdown).dy),
        );
      },
    );

    testWidgets('connected screen shows unsupported label audit honestly', (
      tester,
    ) async {
      await _pumpConnectedScreen(
        tester,
        detailBlob: {
          'ingredients': const <Map<String, dynamic>>[],
          'display_ingredients': const [
            {
              'label_display_name': 'Literal label row',
              'label_order': 0,
              'nested_depth': 0,
              'raw_source_path': 'ingredientRows[0]',
              'score_included': false,
              'display_disposition': 'needs_review',
              'form_display_state': 'needs_review',
            },
          ],
          'quality_pillars_v4': _connectedV4Pillars(),
          'label_ledger_audit': const {
            'support_status': 'unsupported',
            'source_structure': 'unsupported_source_structure',
            'meaningful_source_rows': 0,
            'displayed_rows': 0,
            'omitted_rows': 1,
            'completeness_percentage': null,
            'completeness_status': 'unavailable',
          },
        },
      );

      await _scrollConnectedTowardTop(tester);
      expect(find.text('Label completeness unavailable'), findsOneWidget);
      expect(find.textContaining('Label data unavailable'), findsOneWidget);
      expect(find.text('Label completeness: 100%'), findsNothing);
      expect(find.textContaining('Analysis coverage'), findsNothing);
    });

    final malformedAuditCases = <({String name, Object? value})>[
      (name: 'non-map', value: 'malformed audit payload'),
      (name: 'explicit-null', value: null),
      (name: 'empty-map', value: const <String, dynamic>{}),
    ];
    for (final auditCase in malformedAuditCases) {
      testWidgets(
        'connected screen shows present ${auditCase.name} audit as unavailable',
        (tester) async {
          await _pumpConnectedScreen(
            tester,
            detailBlob: {
              'ingredients': const <Map<String, dynamic>>[],
              'display_ingredients': const [
                {
                  'label_display_name': 'Literal label row',
                  'label_order': 0,
                  'nested_depth': 0,
                  'raw_source_path': 'ingredientRows[0]',
                  'score_included': false,
                  'display_disposition': 'needs_review',
                  'form_display_state': 'needs_review',
                },
              ],
              'quality_pillars_v4': _connectedV4Pillars(),
              'label_ledger_audit': auditCase.value,
            },
          );

          await _scrollConnectedTowardTop(tester);
          expect(find.text('Label completeness unavailable'), findsOneWidget);
          expect(find.textContaining('Label data unavailable'), findsOneWidget);
          expect(find.textContaining('Label completeness:'), findsNothing);
          expect(find.textContaining('Analysis coverage'), findsNothing);
        },
      );
    }

    testWidgets('absent audit key does not create an audit-only section', (
      tester,
    ) async {
      await _pumpConnectedScreen(
        tester,
        detailBlob: {
          'ingredients': const <Map<String, dynamic>>[],
          'display_ingredients': const [
            {
              'label_display_name': 'Legacy blob label row',
              'label_order': 0,
              'nested_depth': 0,
              'raw_source_path': 'ingredientRows[0]',
              'score_included': false,
              'display_disposition': 'label_context',
              'form_display_state': 'not_applicable',
            },
          ],
          'quality_pillars_v4': _connectedV4Pillars(),
        },
      );

      await _scrollConnectedTowardTop(tester);
      expect(find.text('Label completeness unavailable'), findsNothing);
      expect(find.textContaining('Label completeness:'), findsNothing);
      expect(find.text('Label data'), findsNothing);
      expect(find.textContaining('Analysis coverage'), findsNothing);
    });

    testWidgets(
      'display_ingredients wins and preserves omega source order and hierarchy',
      (tester) async {
        final ledger = <Map<String, dynamic>>[
          {
            'label_display_name': 'Fish Oil',
            'exact_dose_text': '2,400 mg',
            'label_order': 0,
            'nested_depth': 0,
            'raw_source_path': 'ingredientRows[0]',
            'score_included': true,
            'display_disposition': 'scored',
            'form_display_state': 'not_disclosed',
          },
          {
            'label_display_name': 'Total Omega-3 Fatty Acids',
            'exact_dose_text': '720 mg',
            'label_order': 1,
            'nested_depth': 1,
            'parent_label': 'Fish Oil',
            'raw_source_path': 'ingredientRows[0].nestedRows[0]',
            'score_included': false,
            'display_disposition': 'label_context',
            'form_display_state': 'not_applicable',
          },
          {
            'label_display_name': 'EPA',
            'exact_dose_text': '360 mg',
            'label_order': 2,
            'nested_depth': 2,
            'parent_label': 'Total Omega-3 Fatty Acids',
            'raw_source_path': 'ingredientRows[0].nestedRows[0].nestedRows[0]',
            'score_included': true,
            'display_disposition': 'scored',
            'form_display_state': 'not_disclosed',
          },
          {
            'label_display_name': 'DHA',
            'exact_dose_text': '240 mg',
            'label_order': 3,
            'nested_depth': 2,
            'parent_label': 'Total Omega-3 Fatty Acids',
            'raw_source_path': 'ingredientRows[0].nestedRows[0].nestedRows[1]',
            'score_included': true,
            'display_disposition': 'scored',
            'form_display_state': 'not_disclosed',
          },
          {
            'label_display_name': 'Other Omega-3 Fatty Acids',
            'exact_dose_text': '120 mg',
            'label_order': 4,
            'nested_depth': 2,
            'parent_label': 'Total Omega-3 Fatty Acids',
            'raw_source_path': 'ingredientRows[0].nestedRows[0].nestedRows[2]',
            'score_included': false,
            'display_disposition': 'label_context',
            'form_display_state': 'not_applicable',
          },
        ];

        await tester.pumpWidget(
          _ingredientsHarness(
            ingredients: const [
              {
                'display_label': 'Legacy scoring row must not render',
                'quantity': 999,
                'unit': 'mg',
              },
            ],
            displayIngredients: ledger,
            inactiveIngredients: const [
              {'name': 'Legacy inactive row must not render'},
            ],
          ),
        );
        await tester.pumpAndSettle();

        final rows = tester
            .widgetList<PGActiveIngredientTile>(
              find.byType(PGActiveIngredientTile),
            )
            .map((tile) => tile.ingredient)
            .toList(growable: false);

        expect(rows.map((row) => row.name), [
          'Fish Oil',
          'Total Omega-3 Fatty Acids',
          'EPA',
          'DHA',
          'Other Omega-3 Fatty Acids',
        ]);
        expect(rows.map((row) => row.labelOrder), [0, 1, 2, 3, 4]);
        expect(rows.map((row) => row.nestedDepth), [0, 1, 2, 2, 2]);
        expect(rows.map((row) => row.parentLabel), [
          null,
          'Fish Oil',
          'Total Omega-3 Fatty Acids',
          'Total Omega-3 Fatty Acids',
          'Total Omega-3 Fatty Acids',
        ]);
        expect(rows.map((row) => row.scoreIncluded), [
          true,
          false,
          true,
          true,
          false,
        ]);
        expect(find.text('Legacy scoring row must not render'), findsNothing);
        expect(find.text('Legacy inactive row must not render'), findsNothing);
      },
    );

    testWidgets(
      'canonical ledger renders one bottle-faithful label view (no toggle)',
      (tester) async {
        await tester.pumpWidget(
          _ingredientsHarness(
            ingredients: const [],
            displayIngredients: _analysisLedger(),
          ),
        );
        await tester.pumpAndSettle();

        // The consumer Analysis toggle is removed — one faithful label view.
        expect(
          find.byKey(const ValueKey('ingredient-view-analysis')),
          findsNothing,
        );
        expect(find.textContaining('Analysis '), findsNothing);
        // Every label row renders in source order (no score-only projection).
        expect(
          tester
              .widgetList<PGActiveIngredientTile>(
                find.byType(PGActiveIngredientTile),
              )
              .map((tile) => tile.ingredient.name),
          [
            'Fish Oil',
            'Total Omega-3 Fatty Acids',
            'EPA',
            'DHA',
            'Other Omega-3 Fatty Acids',
          ],
        );
      },
    );

    testWidgets('legacy blobs render a single ingredient list, no toggle', (
      tester,
    ) async {
      await tester.pumpWidget(
        _ingredientsHarness(
          ingredients: const [
            {
              'display_label': 'Legacy scored row',
              'quantity': 10,
              'unit': 'mg',
            },
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('ingredient-view-analysis')),
        findsNothing,
      );
      expect(find.textContaining('Analysis '), findsNothing);
      expect(find.text('Legacy scored row'), findsOneWidget);
    });

    testWidgets('logical Folate stays one row with its parenthetical amount', (
      tester,
    ) async {
      await tester.pumpWidget(
        _ingredientsHarness(
          ingredients: const [
            {'display_label': 'Folate', 'quantity': 665, 'unit': 'mcg DFE'},
            {'display_label': 'Folate', 'quantity': 400, 'unit': 'mcg'},
          ],
          displayIngredients: const [
            {
              'label_display_name': 'Folate',
              'exact_dose_text': '665 mcg DFE',
              'parenthetical_dose_text': '400 mcg folic acid',
              'label_order': 0,
              'nested_depth': 0,
              'raw_source_path': 'ingredientRows[0]',
              'score_included': true,
              'display_disposition': 'scored',
              'form_display_state': 'listed_not_assessed',
              'label_display_form': 'folic acid',
            },
          ],
        ),
      );
      await tester.pumpAndSettle();

      final rows = tester
          .widgetList<PGActiveIngredientTile>(
            find.byType(PGActiveIngredientTile),
          )
          .map((tile) => tile.ingredient)
          .toList(growable: false);
      expect(rows, hasLength(1));
      expect(rows.single.name, 'Folate');
      expect(rows.single.dose, '665 mcg DFE');
      expect(rows.single.parentheticalDoseText, '400 mcg folic acid');
    });

    testWidgets(
      'Other Ingredients stay visible through the same label ledger',
      (tester) async {
        await tester.pumpWidget(
          _ingredientsHarness(
            ingredients: const [],
            inactiveIngredients: const [
              {
                'name': 'Gelatin',
                'display_role_label': 'Gelatin capsule',
                'functional_roles': ['coating', 'gelling_agent'],
              },
            ],
            displayIngredients: const [
              {
                'label_display_name': 'Gelatin',
                'raw_source_text': 'Gelatin',
                'label_order': 8,
                'nested_depth': 0,
                'raw_source_path': 'otheringredients.ingredients[0]',
                'score_included': false,
                'display_disposition': 'other_ingredient',
                'form_display_state': 'not_applicable',
              },
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(PGActiveIngredientTile), findsNothing);
        expect(find.text('Other ingredients'), findsOneWidget);
        expect(find.text('Gelatin'), findsOneWidget);
        expect(find.text('Gelatin capsule'), findsOneWidget);
      },
    );

    testWidgets(
      'legacy scoring ingredients are used only when the ledger is absent',
      (tester) async {
        const legacy = [
          {'display_label': 'Undisclosed first on label'},
          {
            'display_label': 'Disclosed second on label',
            'quantity': 10,
            'unit': 'mg',
          },
        ];

        await tester.pumpWidget(_ingredientsHarness(ingredients: legacy));
        await tester.pumpAndSettle();
        final names = tester
            .widgetList<PGActiveIngredientTile>(
              find.byType(PGActiveIngredientTile),
            )
            .map((tile) => tile.ingredient.name)
            .toList(growable: false);
        expect(names, [
          'Disclosed second on label',
          'Undisclosed first on label',
        ]);

        await tester.pumpWidget(
          _ingredientsHarness(
            ingredients: legacy,
            displayIngredients: const [],
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(PGActiveIngredientTile), findsNothing);
        expect(find.text('Disclosed second on label'), findsNothing);
      },
    );
  });

  testWidgets('missing product id renders v2 unavailable state', (
    tester,
  ) async {
    final coreDb = CoreDatabase.memory();
    final router = GoRouter(
      initialLocation: Routes.productDetail('missing-product'),
      routes: [
        GoRoute(
          path: '${Routes.product}/:dsldId',
          builder: (_, state) => ProductDetailV2ConnectedScreen(
            dsldId: state.pathParameters['dsldId']!,
          ),
        ),
        GoRoute(
          path: Routes.search,
          builder: (_, __) => const Scaffold(body: Text('Search v2')),
        ),
        GoRoute(
          path: Routes.home,
          builder: (_, __) => const Scaffold(body: Text('Home v2')),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [coreDatabaseProvider.overrideWithValue(coreDb)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Product unavailable'), findsOneWidget);
    expect(find.textContaining('verified catalog'), findsOneWidget);

    await tester.tap(find.text('Search catalog'));
    await tester.pumpAndSettle();
    expect(find.text('Search v2'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await coreDb.close();
  });
}
