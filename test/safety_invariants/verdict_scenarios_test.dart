// The A7 verdict scenarios, driven through the real product page.
//
// Only what sits outside this repo's logic is replaced: the two databases run
// in memory, the blob network is a fake, and reference data is read from the
// shipped asset files because widget tests cannot load the asset bundle.
// Warnings, fit, profile and catalog semantics are all the real owners, so a
// regression in any of them changes what these tests see on screen.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pharmaguide/core/data/clinical_profile_schema.dart';
import 'package:pharmaguide/core/models/fit_score_result.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/data/providers/detail_blob_provider.dart';
import 'package:pharmaguide/data/providers/reference_data_provider.dart';
import 'package:pharmaguide/data/supabase/detail_blob_service.dart';
import 'package:pharmaguide/features/product_detail/providers/fit_score_provider.dart';
import 'package:pharmaguide/features/product_detail/v2/product_detail_v2_connected.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';
import 'package:pharmaguide/services/auth/account_storage.dart';
import 'package:pharmaguide/services/auth/pg_auth_service.dart';
import 'package:pharmaguide/services/fit_score/e1_dosage_calculator.dart';
import 'package:pharmaguide/services/fit_score/e2a_goal_calculator.dart';
import 'package:pharmaguide/services/fit_score/e2b_age_calculator.dart';
import 'package:pharmaguide/services/fit_score/fit_score_service.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent;

const _stJohnsWort = '18219';
const _allClear = 'No known concerns';
const _notRecommended = 'Not recommended for your profile';
const _warfarinWarning = 'Do not combine with warfarin';

const _onWarfarin = ProfileState(
  ageBracket: '31-50',
  sex: 'Female',
  drugClasses: ['anticoagulants'],
);
const _noMatch = ProfileState(ageBracket: '31-50', sex: 'Female');

Map<String, dynamic> _json(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

/// The pipeline's own blob for a real St. John's wort label, unedited.
Map<String, dynamic> _stJohnsWortBlob() {
  final fixture = _json(
    'test/fixtures/pipeline/prebeta_real_products_20261021.json',
  );
  final product = (fixture['products'] as List<dynamic>)
      .cast<Map<String, dynamic>>()
      .singleWhere((p) => p['dsld_id'].toString() == _stJohnsWort);
  return Map<String, dynamic>.from(product['blob'] as Map);
}

/// The same label before the warfarin rule was published: no warning row and
/// no interaction summary entry for the class.
Map<String, dynamic> _stJohnsWortBlobWithoutWarfarinRule() {
  final blob = _stJohnsWortBlob();
  blob['warnings'] = (blob['warnings'] as List<dynamic>)
      .cast<Map<String, dynamic>>()
      .where((w) => !(w['drug_class_ids'] as List).contains('anticoagulants'))
      .toList();
  final summary = Map<String, dynamic>.from(blob['interaction_summary'] as Map);
  summary['drug_class_summary'] = Map<String, dynamic>.from(
    summary['drug_class_summary'] as Map,
  )..remove('anticoagulants');
  blob['interaction_summary'] = summary;
  return blob;
}

/// 900 mg sits under the adult upper limit and over the one for a pregnant
/// 14-18 year old, so only the profile decides which result is right.
Map<String, dynamic> _vitaminEBlob() => {
  'rda_ul_data': {
    'analyzed_ingredients': [
      {
        'canonical_id': 'vitamin_e',
        'standard_name': 'Vitamin E',
        'quantity': 900,
        'per_day_min': 900,
        'per_day_max': 900,
        'unit': 'mg alpha-tocopherol',
        'converted_unit': 'mg alpha-tocopherol',
        'safety_exposure': {'per_day': 900, 'unit': 'mg alpha-tocopherol'},
        'over_ul': false,
        'ul': 1000,
        'pct_ul': 90,
        'ul_gate_eligible': true,
        'skip_ul_check': false,
      },
    ],
  },
};

class _Blobs extends DetailBlobService {
  _Blobs(this.fetch);
  final Future<Map<String, dynamic>?> Function(String sha) fetch;

  @override
  Future<Map<String, dynamic>?> fetchDetailBlobByHash(String sha256) =>
      fetch(sha256);
}

_Blobs _offline() =>
    _Blobs((_) => throw const DetailBlobUnavailableException('offline'));

/// One installed catalog row. Defaults are a finished assessment that found
/// nothing, with a high quality score.
Future<CoreDatabase> _catalog(
  WidgetTester tester, {
  String dsldId = _stJohnsWort,
  String? sha = 'blob-sha',
  double? score = 95,
  String? scoreStatus = 'scored',
  String? assessment = 'complete',
  String? safety = 'no_known_catalog_concern',
  String? verdict = 'SAFE',
  double coverage = 1,
}) async {
  final db = CoreDatabase.memory();
  addTearDown(db.close);
  await db
      .into(db.productsCore)
      .insert(
        ProductsCoreCompanion.insert(
          dsldId: dsldId,
          productName: "St. John's Wort",
          exportVersion: 'test',
          exportedAt: '2026-10-21T00:00:00Z',
          detailBlobSha256: Value(sha),
          qualityScoreV4100: Value(score),
          qualityScoreStatus: Value(scoreStatus),
          qualityAssessmentStatus: Value(assessment),
          productSafetyStatus: Value(safety),
          verdict: Value(verdict),
          mappedCoverage: Value(coverage),
        ),
      );
  return db;
}

/// A user's phone: the saved profile, and the product's blob already cached
/// under [cachedSha] when one is given.
Future<UserDatabase> _phone(
  WidgetTester tester, {
  required ProfileState profile,
  Map<String, dynamic>? cachedBlob,
  String cachedSha = 'blob-sha',
  String dsldId = _stJohnsWort,
}) async {
  final db = UserDatabase.memory();
  addTearDown(db.close);
  await db.saveProfile(profile.toCompanion());
  if (cachedBlob != null) {
    await db.cacheDetail(dsldId, jsonEncode(cachedBlob), cachedSha);
  }
  return db;
}

void main() {
  late FitScoreService fitService;
  late ClinicalProfileSchema schema;
  late Map<String, dynamic> rda;

  setUpAll(() {
    rda = _json('assets/reference_data/rda_optimal_uls.json');
    schema = ClinicalProfileSchema.fromJson(
      _json('assets/reference_data/clinical_risk_taxonomy.json'),
    );
    fitService = FitScoreService(
      e1: E1DosageCalculator(rda),
      e2a: E2aGoalCalculator(
        _json('assets/reference_data/user_goals_to_clusters.json'),
      ),
      e2b: E2bAgeCalculator(rda),
    );
  });

  Future<void> pumpPage(
    WidgetTester tester, {
    required CoreDatabase catalog,
    required UserDatabase phone,
    DetailBlobService? blobs,
    String dsldId = _stJohnsWort,
    Key? scope,
    bool settle = true,
  }) async {
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    await tester.pumpWidget(
      ProviderScope(
        key: scope,
        overrides: [
          coreDatabaseProvider.overrideWithValue(catalog),
          userDatabaseProvider.overrideWithValue(phone),
          detailBlobServiceProvider.overrideWithValue(blobs ?? _offline()),
          fitScoreServiceProvider.overrideWith((ref) async => fitService),
          clinicalProfileSchemaProvider.overrideWith((ref) async => schema),
          rdaOptimalUlsProvider.overrideWith((ref) async => rda),
        ],
        child: MaterialApp(
          home: ProductDetailV2ConnectedScreen(
            dsldId: dsldId,
            initialSection: null,
          ),
        ),
      ),
    );
    if (settle) await tester.pumpAndSettle();
  }

  group('contraindication with a high quality score', () {
    testWidgets('the contraindication leads and the score stays beside it', (
      tester,
    ) async {
      await pumpPage(
        tester,
        catalog: await _catalog(tester),
        phone: await _phone(
          tester,
          profile: _onWarfarin,
          cachedBlob: _stJohnsWortBlob(),
        ),
      );

      expect(find.text('95/100'), findsOneWidget);
      expect(find.text(_notRecommended), findsOneWidget);
      expect(find.text(_warfarinWarning), findsWidgets);
      expect(find.text(_allClear), findsNothing);
    });

    testWidgets('control: the same label for a user it does not touch', (
      tester,
    ) async {
      await pumpPage(
        tester,
        catalog: await _catalog(tester),
        phone: await _phone(
          tester,
          profile: _noMatch,
          cachedBlob: _stJohnsWortBlob(),
        ),
      );

      expect(find.text('95/100'), findsOneWidget);
      expect(find.text(_notRecommended), findsNothing);
      expect(find.text(_allClear), findsOneWidget);
    });
  });

  group('incomplete data never shows "no known concerns"', () {
    // What each state shows instead. Null: the row carries no finished safety
    // status and the page has no copy for that yet; none are in the catalog.
    const notScored = 'Not enough verified data to score';
    for (final (name, score, scoreStatus, assessment, safety, coverage, shown)
        in <(String, double?, String, String, String?, double, String?)>[
          (
            'held by the completeness gate, full coverage',
            null,
            'not_scored',
            'partial',
            'no_known_catalog_concern',
            1,
            notScored,
          ),
          (
            'a number exists but the assessment is unfinished',
            60,
            'scored',
            'partial',
            'no_known_catalog_concern',
            1,
            'Assessment incomplete',
          ),
          (
            'the assessment failed',
            60,
            'scored',
            'failed',
            'no_known_catalog_concern',
            1,
            notScored,
          ),
          (
            'catalog safety not assessed',
            95,
            'scored',
            'complete',
            'not_assessed',
            1,
            null,
          ),
          ('no catalog safety status', 95, 'scored', 'complete', null, 1, null),
          (
            'a safety status this build has never seen',
            95,
            'scored',
            'complete',
            'something_new',
            1,
            null,
          ),
          (
            'coverage below the floor',
            95,
            'scored',
            'complete',
            'no_known_catalog_concern',
            0.29,
            'Limited analysis coverage',
          ),
        ]) {
      testWidgets(name, (tester) async {
        await pumpPage(
          tester,
          catalog: await _catalog(
            tester,
            score: score,
            scoreStatus: scoreStatus,
            assessment: assessment,
            safety: safety,
            coverage: coverage,
          ),
          phone: await _phone(
            tester,
            profile: _noMatch,
            cachedBlob: _stJohnsWortBlob(),
          ),
        );

        expect(find.text(_allClear), findsNothing);
        if (shown != null) expect(find.text(shown), findsOneWidget);
      });
    }

    testWidgets('a declared blob that is not on the phone, offline', (
      tester,
    ) async {
      await pumpPage(
        tester,
        catalog: await _catalog(tester),
        phone: await _phone(tester, profile: _noMatch),
      );

      expect(find.text(_allClear), findsNothing);
      expect(find.text('Personalized checks are incomplete'), findsOneWidget);
    });

    testWidgets('a row that declares no blob at all', (tester) async {
      await pumpPage(
        tester,
        catalog: await _catalog(tester, sha: null),
        phone: await _phone(tester, profile: _noMatch),
      );

      expect(find.text(_allClear), findsNothing);
    });

    testWidgets('a concern still shows when the rest is incomplete', (
      tester,
    ) async {
      await pumpPage(
        tester,
        catalog: await _catalog(
          tester,
          score: null,
          scoreStatus: 'not_scored',
          assessment: 'partial',
        ),
        phone: await _phone(
          tester,
          profile: _onWarfarin,
          cachedBlob: _stJohnsWortBlob(),
        ),
      );

      expect(find.text(_notRecommended), findsOneWidget);
      expect(find.text(_allClear), findsNothing);
    });
  });

  group('unknown product', () {
    testWidgets('a product the catalog does not hold gets no verdict', (
      tester,
    ) async {
      await pumpPage(
        tester,
        catalog: await _catalog(tester),
        phone: await _phone(tester, profile: _onWarfarin),
        dsldId: 'not-in-catalog',
      );

      expect(find.text('Product unavailable'), findsOneWidget);
      expect(find.text(_allClear), findsNothing);
      expect(find.text(_notRecommended), findsNothing);
      expect(find.textContaining('/100'), findsNothing);
    });
  });

  group('new contraindication reaches the user', () {
    testWidgets('a catalog update with a new rule changes the verdict', (
      tester,
    ) async {
      final phone = await _phone(
        tester,
        profile: _onWarfarin,
        cachedBlob: _stJohnsWortBlobWithoutWarfarinRule(),
        cachedSha: 'before',
      );
      await pumpPage(
        tester,
        catalog: await _catalog(tester, sha: 'before'),
        phone: phone,
        scope: const ValueKey('catalog-before'),
      );
      expect(find.text(_allClear), findsOneWidget);

      final fetched = <String>[];
      await pumpPage(
        tester,
        catalog: await _catalog(tester, sha: 'after'),
        phone: phone,
        scope: const ValueKey('catalog-after'),
        blobs: _Blobs((sha) async {
          fetched.add(sha);
          return _stJohnsWortBlob();
        }),
      );

      expect(fetched, ['after']);
      expect(find.text(_notRecommended), findsOneWidget);
      expect(find.text(_warfarinWarning), findsWidgets);
      expect(find.textContaining('citation'), findsWidgets);
      expect(find.text(_allClear), findsNothing);
      expect((await phone.getCachedDetail(_stJohnsWort))?.sha256, 'after');
    });

    testWidgets('offline, the update never falls back to the old all-clear', (
      tester,
    ) async {
      final phone = await _phone(
        tester,
        profile: _onWarfarin,
        cachedBlob: _stJohnsWortBlobWithoutWarfarinRule(),
        cachedSha: 'before',
      );
      await pumpPage(
        tester,
        catalog: await _catalog(tester, sha: 'after'),
        phone: phone,
      );

      expect(find.text(_allClear), findsNothing);
      expect(find.text('Personalized checks are incomplete'), findsOneWidget);
    });

    testWidgets(
      'a hard interaction with no warning row is never an all-clear',
      (tester) async {
        final blob = _stJohnsWortBlob();
        blob['warnings'] = const <Object>[];
        blob['warnings_profile_gated'] = const <Object>[];
        await pumpPage(
          tester,
          catalog: await _catalog(tester),
          phone: await _phone(tester, profile: _onWarfarin, cachedBlob: blob),
        );

        expect(find.text(_allClear), findsNothing);
        expect(find.text(_notRecommended), findsOneWidget);
      },
    );
  });

  group('profile change during a scan', () {
    testWidgets('the edit wins over the check in flight, and undoing it '
        'recalculates', (tester) async {
      final network = Completer<Map<String, dynamic>?>();
      await pumpPage(
        tester,
        catalog: await _catalog(tester),
        phone: await _phone(tester, profile: _noMatch),
        blobs: _Blobs((_) => network.future),
        settle: false,
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text(_allClear), findsNothing);

      final scope = ProviderScope.containerOf(
        tester.element(find.byType(ProductDetailV2ConnectedScreen)),
      );
      scope.read(profileProvider.notifier)
        ..setAgeBracket('14-18')
        ..setConditions(const ['pregnancy']);
      await tester.pump();
      network.complete(_vitaminEBlob());
      await tester.pumpAndSettle();

      expect(find.text('Vitamin E above the upper limit'), findsWidgets);
      expect(find.text(_allClear), findsNothing);

      scope.read(profileProvider.notifier)
        ..setAgeBracket('31-50')
        ..setConditions(const []);
      await tester.pumpAndSettle();

      expect(find.text('Vitamin E above the upper limit'), findsNothing);
      expect(find.text(_allClear), findsOneWidget);
    });
  });

  group('account switch mid-request', () {
    const accountA = 'account-a';
    const accountB = 'account-b';
    const productId = 'vitamin-e';
    late AccountSwitchGuard guard;
    late ProviderContainer scope;
    late Completer<Map<String, dynamic>?> network;

    Future<FitScoreResult?> fitNow() async {
      // The provider is autoDispose: a listener keeps it alive across awaits.
      final listener = scope.listen(
        fitScoreForProductProvider(productId).future,
        (_, _) {},
      );
      try {
        return await listener.read();
      } finally {
        listener.close();
      }
    }

    Future<void> switchTo(String uid) =>
        guard.onAuthEvent(event: AuthChangeEvent.signedIn, uid: uid);

    /// Account A is signed in with a pregnancy profile and a scan is waiting
    /// on the network. Same lifecycle as the app's root: the provider tree
    /// comes down before the handle closes, and a new tree opens on the new
    /// account's database. [overrides] replaces how the blob arrives.
    Future<List<FitScoreResult?>> scanInFlightForA({
      List<Override> Function()? overrides,
    }) async {
      SharedPreferences.setMockInitialValues({});
      final root = await Directory.systemTemp.createTemp('a7_switch');
      addTearDown(() => root.delete(recursive: true));
      final support = await Directory(p.join(root.path, 'support')).create();
      final documents = await Directory(
        p.join(root.path, 'documents'),
      ).create();
      guard = AccountSwitchGuard(
        ownerStore: AccountOwnerStore(),
        storage: AccountStorage(
          supportDirectory: () async => support,
          documentsDirectory: () async => documents,
        ),
        openDatabase: (path) async => UserDatabase.open(path),
      );
      addTearDown(guard.close);
      final catalog = CoreDatabase.memory();
      addTearDown(catalog.close);
      await catalog
          .into(catalog.productsCore)
          .insert(
            ProductsCoreCompanion.insert(
              dsldId: productId,
              productName: 'Vitamin E',
              exportVersion: 'test',
              exportedAt: '2026-10-21T00:00:00Z',
              detailBlobSha256: const Value('blob-sha'),
              mappedCoverage: const Value(1),
            ),
          );
      network = Completer<Map<String, dynamic>?>();

      await guard.boot(sessionUid: accountA);
      await guard.database!.saveProfile(
        const ProfileState(
          ageBracket: '14-18',
          sex: 'Female',
          conditions: ['pregnancy'],
        ).toCompanion(),
      );

      ProviderContainer openScope() => ProviderContainer(
        overrides: [
          coreDatabaseProvider.overrideWithValue(catalog),
          userDatabaseProvider.overrideWithValue(guard.database!),
          detailBlobServiceProvider.overrideWithValue(
            _Blobs((_) => network.future),
          ),
          fitScoreServiceProvider.overrideWith((ref) async => fitService),
          clinicalProfileSchemaProvider.overrideWith((ref) async => schema),
          ...?overrides?.call(),
        ],
      );
      scope = openScope();
      addTearDown(() => scope.dispose());
      guard
        ..releaseConsumers = () async {
          scope.dispose();
        }
        ..onChanged = () => scope = openScope();

      final resultsForA = <FitScoreResult?>[];
      scope.listen(fitScoreForProductProvider(productId), (_, next) {
        if (next.hasValue && !next.isLoading) resultsForA.add(next.value);
      });
      await pumpEventQueue();
      return resultsForA;
    }

    test("the old account's fetch writes into no one's database", () async {
      final resultsForA = await scanInFlightForA();

      await switchTo(accountB);
      network.complete(_vitaminEBlob());
      await pumpEventQueue();

      expect(resultsForA, isEmpty, reason: 'A left before the result arrived');
      expect(await guard.database!.getProfile(), isNull);
      expect(await guard.database!.getCachedDetail(productId), isNull);
      await switchTo(accountA);
      expect(
        await guard.database!.getCachedDetail(productId),
        isNull,
        reason: "the old handle closed, so A's late write landed nowhere",
      );
    });

    test("the old account's result never reaches the new account", () async {
      // The blob arrives without touching a database, so only the provider
      // tree coming down can stop A's result.
      final resultsForA = await scanInFlightForA(
        overrides: () => [
          detailBlobProvider.overrideWith((ref, id) => network.future),
        ],
      );

      await switchTo(accountB);
      network.complete(_vitaminEBlob());
      await pumpEventQueue();
      expect(resultsForA, isEmpty, reason: 'A left before the result arrived');

      final forB = await fitNow();
      expect(forB!.nutrientStatuses.single.tier, isNot(NutrientTier.exceedsUl));

      await switchTo(accountA);
      final forA = await fitNow();
      expect(forA!.nutrientStatuses.single.tier, NutrientTier.exceedsUl);
    });
  });
}
