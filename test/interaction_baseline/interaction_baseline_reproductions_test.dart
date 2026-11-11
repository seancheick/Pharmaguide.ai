// Interaction audit (2026-11-11): reproductions of verified runtime failures.
// Each test states the intended behaviour and was seen to fail on main before
// its Stage 2 fix (Stack delivery here; medication classes in the pipeline).
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/interaction_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/data/providers/detail_blob_provider.dart';
import 'package:pharmaguide/features/product_detail/providers/profile_warning_rule_provider.dart';
import 'package:pharmaguide/features/product_detail/v2/warnings_pipeline.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';
import 'package:pharmaguide/features/stack/providers/active_stack_provider.dart';
import 'package:pharmaguide/features/stack/providers/stack_nutrient_providers.dart';
import 'package:pharmaguide/features/stack/providers/stack_safety_providers.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';
import 'package:pharmaguide/services/stack/stack_safety_report.dart';

// Real export from blob 251796 (Senna Leaves 1,350 mg), build 2026.11.02.
final Map<String, dynamic> _sennaDigoxinWarning = {
  'type': 'drug_interaction',
  'severity': 'avoid',
  'severity_contextual': 'informational',
  'display_mode_default': 'informational',
  'title': 'Senna / cardiac_glycosides',
  'detail':
      'Prolonged or excessive stimulant-laxative use can cause potassium loss, which can increase digoxin toxicity risk. This is not evidence that every ordinary brief exposure causes a direct drug interaction.',
  'action':
      'Avoid senna with digoxin or other cardiac glycosides. If a laxative is required, use an osmotic agent and monitor serum potassium and digoxin levels.',
  'alert_headline': 'Can increase digoxin toxicity',
  'alert_body':
      'Prolonged or excessive laxative use can lower potassium and increase digoxin risk. If you take digoxin, ask your prescriber before using this laxative and avoid unsupervised prolonged use.',
  'informational_note':
      'Senna can lower potassium — relevant to people on digoxin or other cardiac glycosides.',
  'ingredient_name': 'Senna',
  'ingredient_canonical_id': 'senna',
  'evidence_level': 'theoretical',
  'sources': [
    'https://dailymed.nlm.nih.gov/dailymed/drugInfo.cfm?setid=d91e3646-4c63-4512-ab22-db39c085c4dc',
  ],
  'dose_threshold_evaluation': null,
  'dose_decision': {
    'clinical_severity': 'avoid',
    'evaluation_status': null,
    'consumer_disposition': 'block',
    'release_blocking': false,
  },
  'direction': 'harmful',
  'materiality': 'presence',
  'min_effective_dose': null,
  'dose_floor_status': null,
  'source': 'interaction_rules',
  'source_rule_id': 'RULE_IQM_SENNA_PREGNANCY',
  'profile_gate': {
    'gate_type': 'drug_class',
    'requires': {
      'conditions_any': <String>[],
      'drug_classes_any': ['cardiac_glycosides'],
      'profile_flags_any': <String>[],
    },
    'excludes': {
      'conditions_any': <String>[],
      'drug_classes_any': <String>[],
      'profile_flags_any': <String>[],
      'product_forms_any': <String>[],
      'nutrient_forms_any': <String>[],
    },
    'dose': null,
  },
  'source_producers': ['interaction_rules'],
  'condition_ids': <String>[],
  'drug_class_ids': ['cardiac_glycosides'],
};

UserStacksLocalData _row(
  String id, {
  required String type,
  String? dsldId,
  String? rxcui,
  String? drugClassesCol,
}) => UserStacksLocalData(
  id: id,
  type: type,
  name: id,
  dsldId: dsldId,
  rxcui: rxcui,
  drugClassesCol: drugClassesCol,
  addedAt: DateTime(2026),
  clientUpdatedAt: DateTime(2026),
);

/// Digoxin as the medication-entry flow stores it: ingredient RxCUI 3407 and
/// the runtime slugs from live RxNav (ATC "Digitalis glycosides", MED-RT MoA).
UserStacksLocalData get _digoxin => _row(
  'digoxin',
  type: 'medication',
  rxcui: '3407',
  drugClassesCol: jsonEncode([
    'class:digitalis_glycosides',
    'class:sodium_potassium_exchanging_atpase_interactions',
  ]),
);

/// `class:cardiac_glycosides` as the pipeline exports it to drug_class_map
/// (dsld_clean drug_classes.json, ATC C01AA, interaction audit Stage 2).
const _cardiacGlycosidesRow = (
  classId: 'class:cardiac_glycosides',
  name: 'Cardiac glycosides (digoxin, digitoxin)',
  rxcuis: ['199', '132871', '3248', '235219', '3403', '3407', '27929', '6686'],
);

Future<ProviderContainer> _container({
  required Map<String, dynamic> blob,
  required String dsldId,
  List<UserStacksLocalData> medications = const [],
  Set<String>? medicationClassesOverride,
  bool medicationsFirst = false,
  List<String> keyIngredientTags = const [],
  String? curatedAnticoagulantPairSeverity,
  bool seedCardiacGlycosides = false,
}) async {
  final user = UserDatabase.memory();
  final core = CoreDatabase.memory();
  final interactions = InteractionDatabase.memory();
  addTearDown(user.close);
  addTearDown(core.close);
  addTearDown(interactions.close);
  await core
      .into(core.productsCore)
      .insert(
        ProductsCoreCompanion.insert(
          dsldId: dsldId,
          productName: dsldId,
          exportVersion: 'test',
          exportedAt: '2026-11-11',
          mappedCoverage: const Value(1),
          productStatus: const Value('active'),
          productSafetyStatus: const Value('no_known_catalog_concern'),
          safetyAssessmentStatus: const Value('complete'),
          keyIngredientTags: Value(jsonEncode(keyIngredientTags)),
        ),
      );
  if (curatedAnticoagulantPairSeverity != null) {
    await interactions
        .into(interactions.interactions)
        .insert(
          InteractionsCompanion.insert(
            id: 'DSI_FIXTURE_ANTICOAG_SJW',
            agent1Type: 'drug_class',
            agent1Name: 'Anticoagulants',
            agent1Id: 'class:anticoagulants',
            agent2Type: 'supplement',
            agent2Name: "St. John's Wort",
            agent2Id: 'C0813171',
            agent2CanonicalId: const Value('st_john_s_wort'),
            severity: curatedAnticoagulantPairSeverity,
            mechanism: 'Curated pair mechanism',
            management: 'Curated pair management',
            sourceUrlsJson: '["https://example.org/curated"]',
            sourcePmidsJson: '[]',
            versionAdded: '1.0.0',
            versionLastModified: '1.0.0',
            lastUpdated: '2026-11-11',
            typeAuthored: 'curated',
            source: 'curated',
            provenance: 'fixture',
          ),
        );
  }
  if (seedCardiacGlycosides) {
    await interactions
        .into(interactions.drugClassMap)
        .insert(
          DrugClassMapCompanion.insert(
            classId: _cardiacGlycosidesRow.classId,
            className: _cardiacGlycosidesRow.name,
            drugRxcuisJson: jsonEncode(_cardiacGlycosidesRow.rxcuis),
            source: 'rxclass',
            lastUpdated: '2026-11-11',
          ),
        );
  }
  final supplement = _row('stack_$dsldId', type: 'supplement', dsldId: dsldId);
  final rows = medicationsFirst
      ? [...medications, supplement]
      : [supplement, ...medications];
  final container = ProviderContainer(
    overrides: [
      userDatabaseProvider.overrideWithValue(user),
      coreDatabaseProvider.overrideWithValue(core),
      interactionDatabaseProvider.overrideWithValue(interactions),
      activeStackProvider.overrideWith((ref) async => rows),
      loadedProfileProvider.overrideWith(
        (ref) async => const ProfileState(conditions: []),
      ),
      evaluatorProfileFlagsProvider.overrideWith((ref) async => <String>{}),
      profileWarningRuleWarningsProvider.overrideWith((ref, id) async => []),
      stackNutrientStatusesProvider.overrideWith(
        (ref) async => const StackNutrientStatuses.empty(),
      ),
      detailBlobProvider.overrideWith((ref, id) async => blob),
      if (medicationClassesOverride != null)
        currentStackMedicationClassIdsProvider.overrideWith(
          (ref) async => medicationClassesOverride,
        ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// The product page's own composition (product_detail_v2_connected.dart).
List<String> _productPageTitles(
  Map<String, dynamic> blob,
  Set<String> drugClasses,
) {
  final guarded = composeGuardedWarnings(
    detailBlob: blob,
    personalizedWarnings: const [],
    userConditions: const {},
    userDrugClasses: drugClasses,
    userProfileFlags: const {},
  );
  return partitionProfileWarnings(
    warnings: guarded,
    userConditions: const {},
    userDrugClasses: drugClasses,
    userProfileFlags: const {},
  ).profile.map((w) => w.title).toList();
}

bool _stackHas(StackSafetyReport report, String title) =>
    report.stackInteractions.any((r) => r.agent2Name == title);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, dynamic> sjw;
  setUpAll(() {
    final fixture =
        jsonDecode(
              File(
                'test/fixtures/pipeline/prebeta_real_products_20261021.json',
              ).readAsStringSync(),
            )
            as Map;
    sjw = Map<String, dynamic>.from(
      (fixture['products'] as List).cast<Map<String, dynamic>>().singleWhere(
            (p) => p['dsld_id'].toString() == '18219',
          )['blob']
          as Map,
    );
  });

  test(
    'a drug-class-only rule warning shown on the product page also reaches the Stack',
    () async {
      const title = "St. John's Wort Herb Extract / anticoagulants";
      // Control: the product page shows it for an anticoagulant user.
      expect(_productPageTitles(sjw, {'anticoagulants'}), contains(title));
      final container = await _container(
        blob: sjw,
        dsldId: '18219',
        medicationClassesOverride: {'anticoagulants'},
      );
      final report = await container.read(stackSafetyReportProvider.future);
      expect(
        _stackHas(report, title),
        isTrue,
        reason: 'Stack drops warnings without a condition scope',
      );
    },
  );

  group('a class rule and a curated pair for the same hazard', () {
    const ruleTitle = "St. John's Wort Herb Extract / anticoagulants";
    UserStacksLocalData warfarin() => _row(
      'warfarin',
      type: 'medication',
      rxcui: '11289',
      drugClassesCol: '["class:anticoagulants"]',
    );
    Future<StackSafetyReport> report(String pairSeverity) async {
      final container = await _container(
        blob: sjw,
        dsldId: '18219',
        medications: [warfarin()],
        keyIngredientTags: const ['st_john_s_wort'],
        curatedAnticoagulantPairSeverity: pairSeverity,
      );
      return container.read(stackSafetyReportProvider.future);
    }

    test('an equally hard curated pair shows once, as the pair', () async {
      final r = await report('contraindicated');
      expect(_stackHas(r, ruleTitle), isFalse);
      expect(
        r.medicationInteractions.map((i) => i.id),
        contains('DSI_FIXTURE_ANTICOAG_SJW'),
      );
    });

    test(
      'a curated pair removed by a harder rule never hides a softer rule '
      'for another class of the same medicine',
      () async {
        // Pair (avoid) sits between the anticoagulant rule (contraindicated)
        // and the statin rule (caution). The pair is dropped, so the statin
        // rule must show; before the fix neither the pair nor it appeared.
        final container = await _container(
          blob: sjw,
          dsldId: '18219',
          medications: [
            _row(
              'warfarin',
              type: 'medication',
              rxcui: '11289',
              drugClassesCol: '["class:anticoagulants","class:statins"]',
            ),
          ],
          keyIngredientTags: const ['st_john_s_wort'],
          curatedAnticoagulantPairSeverity: 'avoid',
        );
        final r = await container.read(stackSafetyReportProvider.future);
        expect(_stackHas(r, ruleTitle), isTrue);
        expect(
          r.medicationInteractions.map((i) => i.id),
          isNot(contains('DSI_FIXTURE_ANTICOAG_SJW')),
        );
        expect(
          _stackHas(r, "St. John's Wort Herb Extract / statins"),
          isTrue,
        );
      },
    );

    test('a harder class rule replaces a softer curated pair', () async {
      final r = await report('caution');
      expect(_stackHas(r, ruleTitle), isTrue);
      expect(
        r.medicationInteractions.map((i) => i.id),
        isNot(contains('DSI_FIXTURE_ANTICOAG_SJW')),
      );
    });

    test(
      'other medication classes on the same product stay distinct',
      () async {
        final r = await report('contraindicated');
        final container = await _container(
          blob: sjw,
          dsldId: '18219',
          medicationClassesOverride: {'anticoagulants', 'statins'},
        );
        final both = await container.read(stackSafetyReportProvider.future);
        expect(
          _stackHas(both, "St. John's Wort Herb Extract / statins"),
          isTrue,
        );
        expect(_stackHas(r, "St. John's Wort Herb Extract / statins"), isFalse);
      },
    );
  });

  group('digoxin + senna', () {
    late Map<String, dynamic> senna;
    setUp(() {
      senna = {
        ...sjw,
        'dsld_id': '251796',
        'product_name': 'Senna Leaves 1,350 mg',
        'warnings': [_sennaDigoxinWarning],
        'warnings_profile_gated': const <Map<String, dynamic>>[],
      };
    });

    test('control: the senna rule fires for the cardiac_glycosides class', () {
      expect(
        _productPageTitles(senna, {'cardiac_glycosides'}),
        contains('Senna / cardiac_glycosides'),
      );
    });

    test('digoxin resolves to the cardiac_glycosides rule class', () async {
      final container = await _container(
        blob: senna,
        dsldId: '251796',
        medications: [_digoxin],
        seedCardiacGlycosides: true,
      );
      final classes = await container.read(
        currentStackMedicationClassIdsProvider.future,
      );
      expect(classes, contains('cardiac_glycosides'));
    });

    test(
      'product page (medication already saved, or pre-add check) warns',
      () async {
        final container = await _container(
          blob: senna,
          dsldId: '251796',
          medications: [_digoxin],
          seedCardiacGlycosides: true,
        );
        final classes = await container.read(
          currentStackMedicationClassIdsProvider.future,
        );
        expect(
          _productPageTitles(senna, classes),
          contains('Senna / cardiac_glycosides'),
        );
      },
    );

    for (final medicationsFirst in [false, true]) {
      test(
        'saved Stack (medication added ${medicationsFirst ? 'first' : 'last'}) '
        'warns',
        () async {
          final container = await _container(
            blob: senna,
            dsldId: '251796',
            medications: [_digoxin],
            medicationsFirst: medicationsFirst,
            seedCardiacGlycosides: true,
          );
          final report = await container.read(stackSafetyReportProvider.future);
          final warned =
              _stackHas(report, 'Senna / cardiac_glycosides') ||
              report.medicationInteractions.any(
                (r) =>
                    r.matchedSupplementCanonicalId == 'senna' &&
                    r.severity.weight >= Severity.caution.weight,
              );
          expect(
            warned,
            isTrue,
            reason: 'silent all-clear for digoxin + senna',
          );
        },
      );
    }
  });

  group('medication completeness', () {
    test(
      'a medicine with no RxCUI and no recognised class is not reported as checked',
      () async {
        // A class-only entry whose stored RxClass slug is not in the bundled
        // class map: nothing in the interaction data can be matched to it.
        final container = await _container(
          blob: sjw,
          dsldId: '18219',
          medications: [
            _row(
              'unmatched',
              type: 'medication',
              drugClassesCol: jsonEncode(['class:digitalis_glycosides']),
            ),
          ],
        );
        final report = await container.read(stackSafetyReportProvider.future);
        expect(report.checksIncomplete, isTrue);
      },
    );

    test(
      'control: an identified medicine in no tracked group stays checked',
      () async {
        // Amoxicillin by RxCUI: its pairs were checked, it simply belongs to no
        // group the rules name. Flagging it would be noise, not truth.
        final container = await _container(
          blob: sjw,
          dsldId: '18219',
          medications: [
            _row(
              'amoxicillin',
              type: 'medication',
              rxcui: '723',
              drugClassesCol: jsonEncode([
                'class:penicillins_with_extended_spectrum',
              ]),
            ),
          ],
        );
        final report = await container.read(stackSafetyReportProvider.future);
        expect(report.checksIncomplete, isFalse);
      },
    );
  });
}
