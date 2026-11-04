// The A7 verdict scenarios, driven through the real product page.
//
// Only what sits outside this repo's logic is replaced: the page tests run both
// databases in memory (the account-switch tests use real files, because file
// ownership is the behavior there), the blob network is a fake, and reference
// data is read from the shipped asset files because widget tests cannot load
// the asset bundle.
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
import 'package:pharmaguide/data/database/interaction_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/data/providers/detail_blob_provider.dart';
import 'package:pharmaguide/data/providers/reference_data_provider.dart';
import 'package:pharmaguide/data/supabase/detail_blob_service.dart';
import 'package:pharmaguide/features/product_detail/providers/fit_score_provider.dart';
import 'package:pharmaguide/features/product_detail/providers/personalized_warnings_provider.dart';
import 'package:pharmaguide/features/product_detail/v2/product_detail_v2_connected.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/review_before_use_section.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';
import 'package:pharmaguide/features/safety_alerts/providers/safety_alert_providers.dart';
import 'package:pharmaguide/services/auth/account_storage.dart';
import 'package:pharmaguide/services/auth/pg_auth_service.dart';
import 'package:pharmaguide/services/fit_score/e1_dosage_calculator.dart';
import 'package:pharmaguide/services/fit_score/e2a_goal_calculator.dart';
import 'package:pharmaguide/services/fit_score/e2b_age_calculator.dart';
import 'package:pharmaguide/services/fit_score/fit_score_service.dart';
import 'package:pharmaguide/services/safety_alerts/safety_alert.dart';
import 'package:pharmaguide/services/safety_alerts/safety_alert_repository.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent;

const _stJohnsWort = '18219';
const _allClear = 'No known concerns';
const _notRecommended = 'Not recommended for your profile';
const _qualifiedClear = 'Nothing specific to your profile';
const _qualityTitle = 'Quality assessment incomplete';
const _qualityBody =
    "We haven't finished assessing this product's quality yet.";
const _safetyTitle = 'Safety checks incomplete';
const _safetyBody = "We haven't finished this product's safety checks yet.";
const _upperLimitBody =
    'Dose safety could not be fully assessed. This product contains a '
    'nutrient with an established upper intake limit, but the label does not '
    'disclose enough information to evaluate the amount. This does not '
    'establish that the product exceeds the limit.';
const _noScore = 'Product quality score unavailable.';
const _warfarinWarning = 'Do not combine with warfarin';

const _onWarfarin = ProfileState(
  ageBracket: '31-50',
  sex: 'Female',
  drugClasses: ['anticoagulants'],
);
const _noMatch = ProfileState(ageBracket: '31-50', sex: 'Female');
const _pregnant = ProfileState(
  ageBracket: '31-50',
  sex: 'Female',
  conditions: ['pregnancy'],
);

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

/// [blob] with a substance note the pipeline marks critical, the shape it gives
/// FD&C Red No. 40 on 207398. It renders the Product Safety card.
Map<String, dynamic> _withMaterialAdditiveNote(Map<String, dynamic> blob) => {
  ...blob,
  'warnings': [
    ...blob['warnings'] as List<dynamic>,
    {
      'type': 'harmful_additive',
      'severity': 'moderate',
      'display_mode_default': 'critical',
      'title': 'Contains FD&C Red No. 40',
      'detail': 'Synthetic azo dye used for coloration.',
      'source': 'harmful_additives',
    },
  ],
};

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
Future<CoreDatabase> _catalog({
  String dsldId = _stJohnsWort,
  String? sha = 'blob-sha',
  double? score = 95,
  String? scoreStatus = 'scored',
  String? assessment = 'complete',
  String? safetyAssessment,
  String? safetyReason,
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
          safetyAssessmentStatus: Value(safetyAssessment),
          safetyAssessmentReason: Value(safetyReason),
          productSafetyStatus: Value(safety),
          verdict: Value(verdict),
          mappedCoverage: Value(coverage),
        ),
      );
  return db;
}

/// A user's phone: the saved profile, and the product's blob already cached
/// under [cachedSha] when one is given.
Future<UserDatabase> _phone({
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
    List<Override> extraOverrides = const [],
  }) async {
    final rules = InteractionDatabase.memory();
    addTearDown(rules.close);
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    await tester.pumpWidget(
      ProviderScope(
        key: scope,
        overrides: [
          coreDatabaseProvider.overrideWithValue(catalog),
          userDatabaseProvider.overrideWithValue(phone),
          interactionDatabaseProvider.overrideWithValue(rules),
          detailBlobServiceProvider.overrideWithValue(blobs ?? _offline()),
          fitScoreServiceProvider.overrideWith((ref) async => fitService),
          clinicalProfileSchemaProvider.overrideWith((ref) async => schema),
          rdaOptimalUlsProvider.overrideWith((ref) async => rda),
          safetyAlertRepositoryProvider.overrideWithValue(_VerifiedNoAlerts()),
          ...extraOverrides,
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
        catalog: await _catalog(),
        phone: await _phone(
          profile: _onWarfarin,
          cachedBlob: _stJohnsWortBlob(),
        ),
      );

      expect(find.text('95/100'), findsOneWidget);
      expect(find.text(_notRecommended), findsOneWidget);
      expect(find.text(_warfarinWarning), findsWidgets);
      expect(find.text(_allClear), findsNothing);
    });

    // No chip on the profile: the class comes only from the stack row.
    testWidgets('warfarin added to the stack leads the same way', (
      tester,
    ) async {
      final phone = await _phone(
        profile: _noMatch,
        cachedBlob: _stJohnsWortBlob(),
      );
      await phone.addToStack(
        const UserStacksLocalCompanion(
          id: Value('warfarin'),
          name: Value('Warfarin'),
          type: Value('medication'),
          drugClassesCol: Value('["class:anticoagulants"]'),
        ),
      );

      await pumpPage(tester, catalog: await _catalog(), phone: phone);

      expect(find.text('95/100'), findsOneWidget);
      expect(find.text(_warfarinWarning), findsWidgets);
      expect(find.text(_allClear), findsNothing);
    });

    testWidgets('control: the same label for a user it does not touch', (
      tester,
    ) async {
      await pumpPage(
        tester,
        catalog: await _catalog(),
        phone: await _phone(profile: _noMatch, cachedBlob: _stJohnsWortBlob()),
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
            _qualityTitle,
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
            score: score,
            scoreStatus: scoreStatus,
            assessment: assessment,
            safety: safety,
            coverage: coverage,
          ),
          phone: await _phone(
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
        catalog: await _catalog(),
        phone: await _phone(profile: _noMatch),
      );

      expect(find.text(_allClear), findsNothing);
      expect(find.text('Personalized checks are incomplete'), findsOneWidget);
    });

    testWidgets('a row that declares no blob at all', (tester) async {
      await pumpPage(
        tester,
        catalog: await _catalog(sha: null),
        phone: await _phone(profile: _noMatch),
      );

      expect(find.text(_allClear), findsNothing);
    });

    for (final (name, profile, shown) in [
      ('a pregnant user keeps the clinician line', _pregnant, findsOneWidget),
      ('other users get no clinician line', _noMatch, findsNothing),
    ]) {
      testWidgets('all-clear withheld: $name', (tester) async {
        await pumpPage(
          tester,
          catalog: await _catalog(
            score: 60,
            scoreStatus: 'scored',
            assessment: 'partial',
          ),
          phone: await _phone(profile: profile, cachedBlob: _vitaminEBlob()),
        );

        expect(find.text(_allClear), findsNothing);
        expect(find.text(kLifeStageClinicianNote), shown);
      });
    }

    testWidgets('a concern still shows when the rest is incomplete', (
      tester,
    ) async {
      await pumpPage(
        tester,
        catalog: await _catalog(
          score: null,
          scoreStatus: 'not_scored',
          assessment: 'partial',
        ),
        phone: await _phone(
          profile: _onWarfarin,
          cachedBlob: _stJohnsWortBlob(),
        ),
      );

      expect(find.text(_notRecommended), findsOneWidget);
      expect(find.text(_allClear), findsNothing);
    });
  });

  group('safety checks decide the all-clear (ADR-016)', () {
    // Sean, 2026-11-03: "A quality evidence gap alone must not imply that safety
    // checks failed; genuinely unavailable or incomplete required safety checks
    // must still withhold an all-clear." Each message shows only when its own
    // assessment is incomplete.
    testWidgets('evidence review alone missing: the quality message and the '
        'all-clear both show', (tester) async {
      await pumpPage(
        tester,
        catalog: await _catalog(
          score: 60,
          assessment: 'partial',
          safetyAssessment: 'complete',
        ),
        phone: await _phone(profile: _noMatch, cachedBlob: _stJohnsWortBlob()),
      );

      expect(find.text(_allClear), findsOneWidget);
      expect(find.text(_qualityTitle), findsOneWidget);
      expect(find.text(_qualityBody), findsOneWidget);
      expect(find.text(_safetyTitle), findsNothing);
      expect(find.text('60/100'), findsNothing);
    });

    testWidgets('evidence review alone missing: a real concern still leads', (
      tester,
    ) async {
      await pumpPage(
        tester,
        catalog: await _catalog(
          score: 60,
          assessment: 'partial',
          safetyAssessment: 'complete',
        ),
        phone: await _phone(
          profile: _onWarfarin,
          cachedBlob: _stJohnsWortBlob(),
        ),
      );

      expect(find.text(_notRecommended), findsOneWidget);
      expect(find.text(_allClear), findsNothing);
    });

    testWidgets('evidence review alone missing: a pregnant user keeps the '
        'clinician line', (tester) async {
      await pumpPage(
        tester,
        catalog: await _catalog(
          score: 60,
          assessment: 'partial',
          safetyAssessment: 'complete',
        ),
        phone: await _phone(profile: _pregnant, cachedBlob: _vitaminEBlob()),
      );

      expect(find.text(_allClear), findsOneWidget);
      await tester.ensureVisible(find.text(_allClear));
      await tester.tap(find.text(_allClear));
      await tester.pumpAndSettle();
      expect(find.text(kLifeStageClinicianNote), findsOneWidget);
    });

    testWidgets('finished assessment and finished safety checks: the '
        'all-clear shows, with neither message', (tester) async {
      await pumpPage(
        tester,
        catalog: await _catalog(safetyAssessment: 'complete'),
        phone: await _phone(profile: _noMatch, cachedBlob: _stJohnsWortBlob()),
      );

      expect(find.text(_allClear), findsOneWidget);
      expect(find.text(_qualityTitle), findsNothing);
      expect(find.text(_safetyTitle), findsNothing);
    });

    testWidgets('older catalog: a finished product keeps the all-clear', (
      tester,
    ) async {
      await pumpPage(
        tester,
        catalog: await _catalog(),
        phone: await _phone(profile: _noMatch, cachedBlob: _stJohnsWortBlob()),
      );

      expect(find.text(_allClear), findsOneWidget);
      expect(find.text(_safetyTitle), findsNothing);
    });

    // A null status means an older catalog. With no finished score to stand on,
    // the missing all-clear still needs an explanation (Sean, 2026-11-03).
    for (final (
          name,
          score,
          scoreStatus,
          assessment,
          safetyChecks,
          clear,
          quality,
          safetyNote,
          scoreLine,
        )
        in <
          (String, double?, String, String, String?, bool, bool, bool, String?)
        >[
          (
            'finished score, checks unfinished',
            95,
            'scored',
            'complete',
            'incomplete',
            false,
            false,
            true,
            '95/100',
          ),
          (
            'finished score, a status this build has never seen',
            95,
            'scored',
            'complete',
            'something_new',
            false,
            false,
            true,
            '95/100',
          ),
          (
            'finished score, an empty status',
            95,
            'scored',
            'complete',
            '',
            false,
            false,
            true,
            '95/100',
          ),
          (
            'partial quality, checks unfinished',
            60,
            'scored',
            'partial',
            'incomplete',
            false,
            true,
            true,
            null,
          ),
          (
            'partial quality, a status this build has never seen',
            60,
            'scored',
            'partial',
            'something_new',
            false,
            true,
            true,
            null,
          ),
          (
            'partial quality, older catalog',
            60,
            'scored',
            'partial',
            null,
            false,
            true,
            true,
            null,
          ),
          (
            'no score, checks unfinished',
            null,
            'not_scored',
            'partial',
            'incomplete',
            false,
            false,
            true,
            _noScore,
          ),
          (
            'no score, checks finished',
            null,
            'not_scored',
            'partial',
            'complete',
            true,
            false,
            false,
            _noScore,
          ),
          (
            'no score, older catalog',
            null,
            'not_scored',
            'partial',
            null,
            false,
            false,
            true,
            _noScore,
          ),
        ]) {
      testWidgets(name, (tester) async {
        await pumpPage(
          tester,
          catalog: await _catalog(
            score: score,
            scoreStatus: scoreStatus,
            assessment: assessment,
            safetyAssessment: safetyChecks,
          ),
          phone: await _phone(
            profile: _noMatch,
            cachedBlob: _stJohnsWortBlob(),
          ),
        );

        expect(find.text(_allClear), clear ? findsOneWidget : findsNothing);
        expect(find.text(_qualifiedClear), findsNothing);
        expect(
          find.text(_qualityTitle),
          quality ? findsOneWidget : findsNothing,
        );
        expect(
          find.text(_qualityBody),
          quality ? findsOneWidget : findsNothing,
        );
        expect(
          find.text(_safetyTitle),
          safetyNote ? findsOneWidget : findsNothing,
        );
        expect(
          find.text(_safetyBody),
          safetyNote ? findsOneWidget : findsNothing,
        );
        if (scoreLine != null) expect(find.text(scoreLine), findsOneWidget);
      });
    }

    testWidgets('no score, checks unfinished: a real concern stays beside the '
        'note', (tester) async {
      await pumpPage(
        tester,
        catalog: await _catalog(
          score: null,
          scoreStatus: 'not_scored',
          assessment: 'partial',
          safetyAssessment: 'incomplete',
        ),
        phone: await _phone(
          profile: _onWarfarin,
          cachedBlob: _stJohnsWortBlob(),
        ),
      );

      expect(find.text(_notRecommended), findsOneWidget);
      expect(find.text(_safetyTitle), findsOneWidget);
      expect(find.text(_allClear), findsNothing);
    });

    // Decision 6: an unknown catalog safety status withholds without a claim,
    // and a null status doesn't change that.
    for (final (name, score, scoreStatus) in <(String, double?, String)>[
      ('partial quality', 60, 'scored'),
      ('no score', null, 'not_scored'),
    ]) {
      testWidgets('unknown catalog safety, older catalog, $name: no note', (
        tester,
      ) async {
        await pumpPage(
          tester,
          catalog: await _catalog(
            score: score,
            scoreStatus: scoreStatus,
            assessment: 'partial',
            safety: 'something_new',
          ),
          phone: await _phone(
            profile: _noMatch,
            cachedBlob: _stJohnsWortBlob(),
          ),
        );

        expect(find.text(_allClear), findsNothing);
        expect(find.text(_safetyTitle), findsNothing);
      });
    }

    // The older rule needs a finished score, and suppression is no number.
    testWidgets('older catalog, a suppressed score with no number, nothing '
        'blocking it: no all-clear, and the note explains why', (tester) async {
      await pumpPage(
        tester,
        catalog: await _catalog(
          score: null,
          scoreStatus: 'suppressed_safety',
          assessment: 'complete',
        ),
        phone: await _phone(profile: _noMatch, cachedBlob: _stJohnsWortBlob()),
      );

      expect(find.text(_allClear), findsNothing);
      expect(find.text(_qualifiedClear), findsNothing);
      expect(find.text(_safetyTitle), findsOneWidget);
    });

    testWidgets('catalog safety not assessed: the note explains the missing '
        'all-clear, whatever the status says', (tester) async {
      await pumpPage(
        tester,
        catalog: await _catalog(
          safety: 'not_assessed',
          safetyAssessment: 'complete',
        ),
        phone: await _phone(profile: _noMatch, cachedBlob: _stJohnsWortBlob()),
      );

      expect(find.text(_allClear), findsNothing);
      expect(find.text(_safetyTitle), findsOneWidget);
    });

    testWidgets('withheld: coverage below the floor', (tester) async {
      await pumpPage(
        tester,
        catalog: await _catalog(safetyAssessment: 'complete', coverage: 0.29),
        phone: await _phone(profile: _noMatch, cachedBlob: _stJohnsWortBlob()),
      );

      expect(find.text(_allClear), findsNothing);
      expect(find.text(_qualifiedClear), findsNothing);
    });

    // Unknown never reads as reassurance, with or without the status column,
    // and a legacy SAFE verdict doesn't change that (decision 6).
    for (final (safety, verdict) in <(String?, String?)>[
      ('not_assessed', 'SAFE'),
      (null, 'SAFE'),
      (null, 'POOR'),
      (null, null),
      ('', 'SAFE'),
      ('something_new', 'SAFE'),
    ]) {
      for (final safetyAssessment in <String?>['complete', null]) {
        testWidgets('withheld: catalog safety "$safety", verdict "$verdict", '
            'safety checks "$safetyAssessment"', (tester) async {
          await pumpPage(
            tester,
            catalog: await _catalog(
              safety: safety,
              verdict: verdict,
              safetyAssessment: safetyAssessment,
            ),
            phone: await _phone(
              profile: _noMatch,
              cachedBlob: _stJohnsWortBlob(),
            ),
          );

          expect(find.text(_allClear), findsNothing);
          expect(find.text(_qualifiedClear), findsNothing);
          // Only the catalog saying `not_assessed` is a claim the note can
          // repeat. Anything else unknown withholds without one (decision 6).
          expect(
            find.text(_safetyTitle),
            safety == 'not_assessed' ? findsOneWidget : findsNothing,
          );
        });
      }
    }

    testWidgets('withheld: personal check failed, and the page says so', (
      tester,
    ) async {
      await pumpPage(
        tester,
        catalog: await _catalog(safetyAssessment: 'complete'),
        phone: await _phone(profile: _noMatch, cachedBlob: _stJohnsWortBlob()),
        extraOverrides: [
          personalizedInteractionWarningsProvider(_stJohnsWort).overrideWith(
            (ref) => throw StateError('interaction lookup failed'),
          ),
        ],
      );

      expect(find.text(_allClear), findsNothing);
      expect(find.text('Personalized checks are incomplete'), findsOneWidget);
    });

    testWidgets('withheld: the blob is not on the phone, and the page says '
        'so', (tester) async {
      await pumpPage(
        tester,
        catalog: await _catalog(safetyAssessment: 'complete'),
        phone: await _phone(profile: _noMatch),
      );

      expect(find.text(_allClear), findsNothing);
      expect(find.text('Personalized checks are incomplete'), findsOneWidget);
    });

    // 19 blocked products in the 2026.11.02 build read `incomplete`, 232887 for
    // one. The block comes from the safety status alone, so this field can't
    // lift it.
    for (final safety in ['blocked', 'unsafe']) {
      testWidgets('$safety with unfinished safety checks keeps the block', (
        tester,
      ) async {
        await pumpPage(
          tester,
          catalog: await _catalog(
            score: null,
            scoreStatus: 'suppressed_safety',
            safetyAssessment: 'incomplete',
            safety: safety,
            verdict: 'BLOCKED',
          ),
          phone: await _phone(
            profile: _noMatch,
            cachedBlob: _stJohnsWortBlob(),
          ),
        );

        expect(
          find.text('PharmaGuide does not recommend this product'),
          findsWidgets,
        );
        expect(find.text(_allClear), findsNothing);
        expect(find.text(_qualityTitle), findsNothing);
        expect(find.text(_safetyTitle), findsNothing);
      });
    }

    testWidgets('blocked with finished safety checks keeps the block', (
      tester,
    ) async {
      await pumpPage(
        tester,
        catalog: await _catalog(
          score: null,
          scoreStatus: 'suppressed_safety',
          safetyAssessment: 'complete',
          safety: 'blocked',
          verdict: 'BLOCKED',
        ),
        phone: await _phone(profile: _noMatch, cachedBlob: _stJohnsWortBlob()),
      );

      expect(
        find.text('PharmaGuide does not recommend this product'),
        findsWidgets,
      );
      expect(find.text(_allClear), findsNothing);
    });
  });

  group('a dose rule nobody could read is no all-clear', () {
    const onCholesterolCare = ProfileState(
      ageBracket: '31-50',
      sex: 'Female',
      conditions: ['high_cholesterol'],
    );

    // The shape the pipeline gives a suppressed niacin threshold whose amount it
    // could not read.
    Map<String, dynamic> withUnreadRule(Map<String, dynamic> blob) => {
      ...blob,
      'warnings': [
        ...blob['warnings'] as List<dynamic>,
        {
          'type': 'interaction',
          'severity': 'caution',
          'title': 'Niacin / dose',
          'ingredient_name': 'Niacin',
          'condition_ids': const ['high_cholesterol'],
          'drug_class_ids': const <String>[],
          'profile_gate': {
            'gate_type': 'condition',
            'requires': {
              'conditions_any': const ['high_cholesterol'],
              'drug_classes_any': const <String>[],
              'profile_flags_any': const <String>[],
            },
            'excludes': {
              'conditions_any': const <String>[],
              'drug_classes_any': const <String>[],
              'profile_flags_any': const <String>[],
              'product_forms_any': const <String>[],
              'nutrient_forms_any': const <String>[],
            },
            'dose': {
              'basis': 'per_day',
              'comparator': '>=',
              'value': 1500,
              'unit': 'mg',
              'severity_if_met': 'caution',
              'severity_if_not_met': 'informational',
            },
          },
          'dose_decision': {
            'clinical_severity': 'caution',
            'evaluation_status': 'amount_unknown',
            'consumer_disposition': 'suppress',
          },
        },
      ],
    };

    testWidgets('it applies to this person: no all-clear, and the suppressed '
        'rule stays hidden', (tester) async {
      await pumpPage(
        tester,
        catalog: await _catalog(safetyAssessment: 'complete'),
        phone: await _phone(
          profile: onCholesterolCare,
          cachedBlob: withUnreadRule(_stJohnsWortBlob()),
        ),
      );

      expect(find.text(_allClear), findsNothing);
      expect(find.text(_qualifiedClear), findsNothing);
      expect(find.text('Niacin / dose'), findsNothing);
    });

    testWidgets('it applies to someone else: the all-clear stays', (
      tester,
    ) async {
      await pumpPage(
        tester,
        catalog: await _catalog(safetyAssessment: 'complete'),
        phone: await _phone(
          profile: _noMatch,
          cachedBlob: withUnreadRule(_stJohnsWortBlob()),
        ),
      );

      expect(find.text(_allClear), findsOneWidget);
    });

    testWidgets('the same person with no such rule keeps the all-clear', (
      tester,
    ) async {
      await pumpPage(
        tester,
        catalog: await _catalog(safetyAssessment: 'complete'),
        phone: await _phone(
          profile: onCholesterolCare,
          cachedBlob: _stJohnsWortBlob(),
        ),
      );

      expect(find.text(_allClear), findsOneWidget);
    });
  });

  group('the catalog can name why safety checks are unfinished (ADR-016)', () {
    const reason = 'upper_limit_amount_undisclosed';

    for (final (name, safetyChecks, safetyReason, body, clear)
        in <(String, String?, String?, String?, bool)>[
          ('reason set', 'incomplete', reason, _upperLimitBody, false),
          ('incomplete, no reason', 'incomplete', null, _safetyBody, false),
          ('complete, no reason', 'complete', null, null, true),
          (
            'a value this build has never seen',
            'incomplete',
            'new_reason',
            _safetyBody,
            false,
          ),
          ('an empty value', 'incomplete', '', _safetyBody, false),
          (
            'the reason beside a finished status',
            'complete',
            reason,
            null,
            true,
          ),
          (
            'the reason beside an unknown status',
            'new_status',
            reason,
            _safetyBody,
            false,
          ),
        ]) {
      testWidgets(name, (tester) async {
        await pumpPage(
          tester,
          catalog: await _catalog(
            safetyAssessment: safetyChecks,
            safetyReason: safetyReason,
          ),
          phone: await _phone(
            profile: _noMatch,
            cachedBlob: _stJohnsWortBlob(),
          ),
        );

        expect(
          find.text(_safetyBody),
          body == _safetyBody ? findsOneWidget : findsNothing,
        );
        expect(
          find.text(_upperLimitBody),
          body == _upperLimitBody ? findsOneWidget : findsNothing,
        );
        expect(
          find.text(_safetyTitle),
          body == null ? findsNothing : findsOneWidget,
        );
        expect(find.text(_allClear), clear ? findsOneWidget : findsNothing);
        // It never touches quality.
        expect(find.text(_qualityTitle), findsNothing);
        expect(find.textContaining('95/100', findRichText: true), findsWidgets);
      });
    }

    testWidgets('an older catalog with no status keeps the generic text', (
      tester,
    ) async {
      await pumpPage(
        tester,
        catalog: await _catalog(
          score: 60,
          assessment: 'partial',
          safetyReason: reason,
        ),
        phone: await _phone(profile: _noMatch, cachedBlob: _stJohnsWortBlob()),
      );

      expect(find.text(_safetyBody), findsOneWidget);
      expect(find.text(_upperLimitBody), findsNothing);
    });

    testWidgets('a quality gap keeps its own message beside the reason', (
      tester,
    ) async {
      await pumpPage(
        tester,
        catalog: await _catalog(
          score: 60,
          assessment: 'partial',
          safetyAssessment: 'incomplete',
          safetyReason: reason,
        ),
        phone: await _phone(profile: _noMatch, cachedBlob: _stJohnsWortBlob()),
      );

      expect(find.text(_qualityTitle), findsOneWidget);
      expect(find.text(_upperLimitBody), findsOneWidget);
    });

    testWidgets('a real concern stays beside the reason', (tester) async {
      await pumpPage(
        tester,
        catalog: await _catalog(
          safetyAssessment: 'incomplete',
          safetyReason: reason,
        ),
        phone: await _phone(
          profile: _onWarfarin,
          cachedBlob: _stJohnsWortBlob(),
        ),
      );

      expect(find.text(_notRecommended), findsOneWidget);
      expect(find.text(_upperLimitBody), findsOneWidget);
    });

    testWidgets('a catalog caution stays beside the reason', (tester) async {
      await pumpPage(
        tester,
        catalog: await _catalog(
          safety: 'caution',
          verdict: 'CAUTION',
          safetyAssessment: 'incomplete',
          safetyReason: reason,
        ),
        phone: await _phone(profile: _noMatch, cachedBlob: _stJohnsWortBlob()),
      );

      expect(find.text(_upperLimitBody), findsOneWidget);
      expect(find.text(_allClear), findsNothing);
    });

    testWidgets('a block is its own answer', (tester) async {
      await pumpPage(
        tester,
        catalog: await _catalog(
          score: null,
          scoreStatus: 'suppressed_safety',
          safety: 'blocked',
          verdict: 'BLOCKED',
          safetyAssessment: 'incomplete',
          safetyReason: reason,
        ),
        phone: await _phone(profile: _noMatch, cachedBlob: _stJohnsWortBlob()),
      );

      expect(
        find.text('PharmaGuide does not recommend this product'),
        findsWidgets,
      );
      expect(find.text(_upperLimitBody), findsNothing);
      expect(find.text(_safetyTitle), findsNothing);
    });
  });

  group('a catalog caution with nothing personal (ADR-016)', () {
    testWidgets('general notes on the page: the qualified wording points to '
        'them, with no all-clear', (tester) async {
      await pumpPage(
        tester,
        catalog: await _catalog(
          safetyAssessment: 'complete',
          safety: 'caution',
        ),
        phone: await _phone(
          profile: _noMatch,
          cachedBlob: _withMaterialAdditiveNote(_stJohnsWortBlob()),
        ),
      );

      expect(find.text(_allClear), findsNothing);
      expect(find.text(_qualifiedClear), findsOneWidget);
      expect(
        find.text(
          'This product has general safety notes. '
          'See Product Safety below.',
        ),
        findsOneWidget,
      );
      expect(find.text('PRODUCT SAFETY'), findsOneWidget);
    });

    // A watchlist-only caution such as 232718 renders no Product Safety card,
    // so the pointer would lead nowhere.
    testWidgets('no Product Safety card: the wording does not point to one', (
      tester,
    ) async {
      await pumpPage(
        tester,
        catalog: await _catalog(
          safetyAssessment: 'complete',
          safety: 'caution',
        ),
        phone: await _phone(profile: _noMatch, cachedBlob: _stJohnsWortBlob()),
      );

      expect(find.text(_allClear), findsNothing);
      expect(find.text(_qualifiedClear), findsOneWidget);
      expect(
        find.text('The catalog flags this product for caution.'),
        findsOneWidget,
      );
      expect(find.text('PRODUCT SAFETY'), findsNothing);
    });

    testWidgets('older catalog with no status gets the same wording', (
      tester,
    ) async {
      await pumpPage(
        tester,
        catalog: await _catalog(safety: 'caution'),
        phone: await _phone(profile: _noMatch, cachedBlob: _stJohnsWortBlob()),
      );

      expect(find.text(_allClear), findsNothing);
      expect(find.text(_qualifiedClear), findsOneWidget);
    });

    testWidgets('a pregnant user keeps the clinician line', (tester) async {
      await pumpPage(
        tester,
        catalog: await _catalog(
          safetyAssessment: 'complete',
          safety: 'caution',
        ),
        phone: await _phone(profile: _pregnant, cachedBlob: _vitaminEBlob()),
      );

      expect(find.text(_qualifiedClear), findsOneWidget);
      expect(find.text(kLifeStageClinicianNote), findsOneWidget);
    });

    testWidgets('a matching concern still leads', (tester) async {
      await pumpPage(
        tester,
        catalog: await _catalog(
          safetyAssessment: 'complete',
          safety: 'caution',
        ),
        phone: await _phone(
          profile: _onWarfarin,
          cachedBlob: _stJohnsWortBlob(),
        ),
      );

      expect(find.text(_notRecommended), findsOneWidget);
      expect(find.text(_qualifiedClear), findsNothing);
    });

    testWidgets('evidence review open, checks finished: the qualified wording '
        'stays beside the quality message', (tester) async {
      await pumpPage(
        tester,
        catalog: await _catalog(
          score: 60,
          assessment: 'partial',
          safetyAssessment: 'complete',
          safety: 'caution',
        ),
        phone: await _phone(profile: _noMatch, cachedBlob: _stJohnsWortBlob()),
      );

      expect(find.text(_allClear), findsNothing);
      expect(find.text(_qualifiedClear), findsOneWidget);
      expect(find.text(_qualityTitle), findsOneWidget);
      expect(find.text(_safetyTitle), findsNothing);
    });

    for (final (name, score, assessment, scoreStatus, safetyChecks, quality)
        in <(String, double?, String, String, String, bool)>[
          ('finished score', 95, 'complete', 'scored', 'incomplete', false),
          ('partial quality', 60, 'partial', 'scored', 'incomplete', true),
          ('no score', null, 'partial', 'not_scored', 'incomplete', false),
        ]) {
      testWidgets('$name, checks unfinished: no qualified wording, and the '
          'note says why', (tester) async {
        await pumpPage(
          tester,
          catalog: await _catalog(
            score: score,
            scoreStatus: scoreStatus,
            assessment: assessment,
            safetyAssessment: safetyChecks,
            safety: 'caution',
          ),
          phone: await _phone(
            profile: _noMatch,
            cachedBlob: _stJohnsWortBlob(),
          ),
        );

        expect(find.text(_allClear), findsNothing);
        expect(find.text(_qualifiedClear), findsNothing);
        expect(find.text(_safetyTitle), findsOneWidget);
        expect(
          find.text(_qualityTitle),
          quality ? findsOneWidget : findsNothing,
        );
      });
    }
  });

  group('unknown product', () {
    testWidgets('a product the catalog does not hold gets no verdict', (
      tester,
    ) async {
      await pumpPage(
        tester,
        catalog: await _catalog(),
        phone: await _phone(profile: _onWarfarin),
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
        profile: _onWarfarin,
        cachedBlob: _stJohnsWortBlobWithoutWarfarinRule(),
        cachedSha: 'before',
      );
      await pumpPage(
        tester,
        catalog: await _catalog(sha: 'before'),
        phone: phone,
        scope: const ValueKey('catalog-before'),
      );
      expect(find.text(_allClear), findsOneWidget);

      final fetched = <String>[];
      await pumpPage(
        tester,
        catalog: await _catalog(sha: 'after'),
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
        profile: _onWarfarin,
        cachedBlob: _stJohnsWortBlobWithoutWarfarinRule(),
        cachedSha: 'before',
      );
      await pumpPage(
        tester,
        catalog: await _catalog(sha: 'after'),
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
          catalog: await _catalog(),
          phone: await _phone(profile: _onWarfarin, cachedBlob: blob),
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
        catalog: await _catalog(),
        phone: await _phone(profile: _noMatch),
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
    late Completer<void> scanReachedNetwork;

    Future<Map<String, dynamic>?> awaitNetwork() {
      if (!scanReachedNetwork.isCompleted) scanReachedNetwork.complete();
      return network.future;
    }

    // The database runs on its own isolate, so a late write takes real time.
    Future<void> letLateWorkFinish() =>
        Future<void>.delayed(const Duration(milliseconds: 200));

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
      scanReachedNetwork = Completer<void>();

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
            _Blobs((_) => awaitNetwork()),
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
      await scanReachedNetwork.future;
      return resultsForA;
    }

    test("the old account's fetch writes into no one's database", () async {
      final resultsForA = await scanInFlightForA();

      await switchTo(accountB);
      network.complete(_vitaminEBlob());
      await letLateWorkFinish();

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
          detailBlobProvider.overrideWith((ref, id) => awaitNetwork()),
        ],
      );

      await switchTo(accountB);
      await guard.database!.saveProfile(
        const ProfileState(
          ageBracket: '31-50',
          sex: 'Female',
          conditions: ['pregnancy'],
        ).toCompanion(),
      );
      network.complete(_vitaminEBlob());
      await letLateWorkFinish();
      expect(resultsForA, isEmpty, reason: 'A left before the result arrived');

      final forB = await fitNow();
      expect(forB!.nutrientStatuses.single.tier, NutrientTier.approachingUl);

      await switchTo(accountA);
      final forA = await fitNow();
      expect(forA!.nutrientStatuses.single.tier, NutrientTier.exceedsUl);
    });
  });
}
