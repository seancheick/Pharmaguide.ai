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
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/data/clinical_profile_schema.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/data/providers/detail_blob_provider.dart';
import 'package:pharmaguide/data/providers/reference_data_provider.dart';
import 'package:pharmaguide/data/supabase/detail_blob_service.dart';
import 'package:pharmaguide/features/product_detail/providers/fit_score_provider.dart';
import 'package:pharmaguide/features/product_detail/v2/product_detail_v2_connected.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';
import 'package:pharmaguide/services/fit_score/e1_dosage_calculator.dart';
import 'package:pharmaguide/services/fit_score/e2a_goal_calculator.dart';
import 'package:pharmaguide/services/fit_score/e2b_age_calculator.dart';
import 'package:pharmaguide/services/fit_score/fit_score_service.dart';

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
}
