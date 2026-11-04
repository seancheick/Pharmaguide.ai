import 'dart:convert';
import 'dart:io';
import 'package:pharmaguide/core/constants/consumer_disposition.dart';
import 'package:pharmaguide/features/product_detail/providers/profile_warning_rule_provider.dart';
import 'package:pharmaguide/services/warnings/interaction_warning.dart';
import 'package:pharmaguide/services/stack/stack_dose_summer.dart';
import 'package:pharmaguide/services/stack/stack_intelligence_engine.dart';
import 'package:pharmaguide/services/stack/recalled_ingredient_result.dart';
import 'package:pharmaguide/services/stack/synergy_result.dart';
import 'package:pharmaguide/services/signals/stack_signal_aggregator.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/interaction_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/data/providers/detail_blob_provider.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';
import 'package:pharmaguide/features/stack/providers/active_stack_provider.dart';
import 'package:pharmaguide/features/stack/providers/stack_nutrient_providers.dart';
import 'package:pharmaguide/features/stack/providers/stack_safety_providers.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';
import 'package:pharmaguide/services/stack/stack_safety_report.dart';

Future<StackSafetyReport> reportFor(
  Map<String, dynamic>? blob, {
  ProfileState profile = const ProfileState(conditions: ['pregnancy']),
  bool secondBlobFails = false,
  String safetyAssessmentStatus = 'complete',
  List<InteractionWarning>? resolvedRules,
  bool resolutionFails = false,
  bool flagsFail = false,
  bool classesFail = false,
  Future<void> Function(ProviderContainer, StackSafetyReport)? inspect,
}) async {
  final user = UserDatabase.memory();
  addTearDown(user.close);
  final core = CoreDatabase.memory();
  final interactions = InteractionDatabase.memory();
  addTearDown(core.close);
  addTearDown(interactions.close);
  final rows = <UserStacksLocalData>[];
  for (final id in ['18219', if (secondBlobFails) 'missing']) {
    await user.addToStack(
      UserStacksLocalCompanion.insert(
        id: 'stack_$id',
        name: id,
        dsldId: Value(id),
      ),
    );
    await core
        .into(core.productsCore)
        .insert(
          ProductsCoreCompanion.insert(
            dsldId: id,
            productName: id,
            exportVersion: 'test',
            exportedAt: '2026-11-03',
            mappedCoverage: const Value(1),
            productStatus: const Value('active'),
            productSafetyStatus: const Value('no_known_catalog_concern'),
            safetyAssessmentStatus: Value(safetyAssessmentStatus),
            keyIngredientTags: const Value('["st_johns_wort"]'),
          ),
        );
    rows.add(
      UserStacksLocalData(
        id: 'stack_$id',
        type: 'supplement',
        name: id,
        dsldId: id,
        addedAt: DateTime(2026),
        clientUpdatedAt: DateTime(2026),
      ),
    );
  }
  final container = ProviderContainer(
    overrides: [
      if (resolutionFails)
        profileWarningRuleWarningsProvider.overrideWith(
          (ref, id) async => throw StateError("reference unavailable"),
        ),
      if (resolvedRules != null)
        profileWarningRuleWarningsProvider.overrideWith(
          (ref, id) async => resolvedRules,
        ),
      userDatabaseProvider.overrideWithValue(user),
      coreDatabaseProvider.overrideWithValue(core),
      interactionDatabaseProvider.overrideWithValue(interactions),
      activeStackProvider.overrideWith((ref) async => rows),
      loadedProfileProvider.overrideWith((ref) async => profile),
      if (classesFail)
        currentStackMedicationClassIdsProvider.overrideWith(
          (ref) async => throw StateError('classes unavailable'),
        ),
      evaluatorProfileFlagsProvider.overrideWith(
        (ref) async => flagsFail
            ? throw StateError('flags unavailable')
            : profile.conditions.contains('pregnancy')
            ? {'pregnant'}
            : <String>{},
      ),
      stackNutrientStatusesProvider.overrideWith(
        (ref) async => const StackNutrientStatuses.empty(),
      ),
      detailBlobProvider.overrideWith((ref, id) async {
        if (id == 'missing') throw StateError('blob unavailable');
        return blob;
      }),
    ],
  );
  addTearDown(container.dispose);
  final report = await container.read(stackSafetyReportProvider.future);
  await inspect?.call(container, report);
  return report;
}

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
  test('catalog safety incompleteness carries into Stack', () async {
    final report = await reportFor(
      sjw,
      resolvedRules: const [],
      safetyAssessmentStatus: 'incomplete',
    );
    expect(report.checksIncomplete, isTrue);
    expect(report.stackInteractions, isNotEmpty);
  });
  group('a dose rule this product has no number for', () {
    Map<String, dynamic> blobWith(String status, String disposition) {
      final rule = Map<String, dynamic>.from(
        (sjw['warnings'] as List).cast<Map<String, dynamic>>().firstWhere(
          (w) => (w['condition_ids'] as List?)?.contains('pregnancy') ?? false,
        ),
      );
      return {
        ...sjw,
        'warnings': [
          {
            ...rule,
            'title': 'Probe rule',
            'ingredient_canonical_id': 'beta_carotene',
            'severity': 'caution',
            'display_mode_default': disposition == 'suppress'
                ? 'suppress'
                : 'informational',
            'dose_decision': {
              'clinical_severity': 'caution',
              'consumer_disposition': disposition,
              'evaluation_status': status,
              'decision_rule': {
                'basis': 'per_day',
                'comparator': '>=',
                'threshold': 7500.0,
                'threshold_unit': 'mcg RAE',
                'consumer_disposition_if_met': 'review',
                'consumer_disposition_if_not_met': 'suppress',
              },
            },
          },
        ],
        'warnings_profile_gated': const <Map<String, dynamic>>[],
      };
    }

    for (final (status, disposition, unread) in const [
      ('excluded_form', 'suppress', false),
      ('amount_unknown', 'suppress', false),
      ('form_unknown', 'suppress', true),
      ('amount_unknown', 'review', true),
      ('form_unknown', 'review', true),
    ]) {
      test('$status $disposition is no Stack finding', () async {
        await reportFor(
          blobWith(status, disposition),
          inspect: (container, report) async {
            expect(
              report.stackInteractions.where(
                (w) => w.agent2Name == 'Probe rule',
              ),
              isEmpty,
            );
            expect(
              await container.read(stackDoseRulesUnreadProvider.future),
              unread,
            );
          },
        );
      });
    }
  });
  test(
    '249741: an avoid answer on an open caffeine range reaches Stack, once',
    () async {
      final caffeine =
          jsonDecode(
                File(
                  'test/fixtures/pipeline/caffeine_estimate_249741.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final body = caffeine['alert_body'] as String;
      Map<String, dynamic> blob() => {
        ...sjw,
        'warnings': [caffeine],
        'warnings_profile_gated': const <Map<String, dynamic>>[],
      };
      final pregnant = await reportFor(blob());
      final card = pregnant.stackInteractions.where((w) => w.mechanism == body);
      expect(card, hasLength(1));
      expect(card.single.severity, Severity.avoid);
      expect(card.single.evidenceLevel, EvidenceLevel.established);
      const aggregate = StackDoseThresholdAlert(
        conditionId: 'pregnancy',
        canonicalId: 'caffeine',
        displayName: 'Caffeine',
        totalValue: 230,
        unit: 'mg',
        thresholdValue: 200,
        thresholdUnit: 'mg',
        contributions: [],
        isIncomplete: true,
        clinicalSeverity: Severity.avoid,
      );
      final signals = allClinicalSignalsFrom(
        report: pregnant,
        doseThresholdAlerts: [aggregate],
      );
      expect(signals, hasLength(1));
      expect(signals.single.clinicalSeverity, Severity.avoid);
      expect(signals.single.body, body);
      expect(
        allClinicalSignalsFrom(
          report: const StackSafetyReport(),
          doseThresholdAlerts: [aggregate],
        ),
        hasLength(1),
      );

      final nursing = await reportFor(
        blob(),
        profile: const ProfileState(conditions: ['lactation']),
      );
      expect(
        nursing.stackInteractions.where((w) => w.mechanism == body),
        isEmpty,
      );
    },
  );
  test('frozen SJW pregnancy warning reaches combined Stack', () async {
    final report = await reportFor(sjw);
    final warnings = report.stackInteractions.where(
      (w) => w.mechanism.toLowerCase().contains('birth-defect'),
    );
    expect(warnings, hasLength(1));
    expect(warnings.single.severity, Severity.avoid);
    expect(
      warnings.single.sourceUrls,
      contains('https://www.nccih.nih.gov/health/st-johns-wort'),
    );
  });
  test(
    'schema-3 resolved condition warning reaches shared Home/Stack snapshot once',
    () async {
      final warning = InteractionWarning.fromJson({
        'type': 'interaction',
        'severity': 'avoid',
        'evidence_level': 'established',
        'title': 'Fixture condition warning',
        'mechanism': 'Existing authored concern',
        'condition_ids': ['pregnancy'],
        'source_urls': ['https://example.org/fixture'],
      });
      final report = await reportFor({}, resolvedRules: [warning, warning]);
      final snapshot = const StackIntelligenceEngine().summarizeFromReports(
        stackSize: 1,
        safetyReport: report,
        recalledReport: const RecalledIngredientsReport(violations: []),
        synergyReport: SynergyReport.empty(),
      );
      expect(snapshot.reviewSignals, hasLength(1));
      expect(
        snapshot.reviewSignals.single.consumerDisposition.requiresReview,
        isTrue,
      );
      expect(
        clinicalSignalKindLabel(snapshot.reviewSignals.single),
        'Health-context guidance',
      );
      expect(snapshot.intelligence.interactionCount, 0);
    },
  );
  test(
    'genuine cumulative rule stays with dose owner; metadata alone does not remove ordinary warning',
    () async {
      final warnings = [
        {
          'type': 'interaction',
          'severity': 'caution',
          'evidence_level': 'established',
          'title': 'Caffeine',
          'mechanism': 'Dose concern',
          'condition_ids': ['pregnancy'],
          'ingredient_name': 'Caffeine',
          'dose_threshold_evaluation': {
            'thresholds_checked': [
              {'threshold_value': 200, 'threshold_unit': 'mg'},
            ],
          },
        },
        {
          'type': 'interaction',
          'severity': 'avoid',
          'evidence_level': 'established',
          'title': 'Ordinary',
          'mechanism': 'Ordinary concern',
          'condition_ids': ['pregnancy'],
          'ingredient_name': 'St Johns Wort',
          'dose_threshold_evaluation': {'evaluated': false},
        },
      ];
      final report = await reportFor(
        {
          'warnings': warnings,
          'ingredients': [
            {
              'name': 'Caffeine',
              'standard_name': 'Caffeine',
              'quantity': 240,
              'unit': 'mg',
            },
          ],
        },
        inspect: (container, report) async {
          final alerts = await container.read(
            stackDoseThresholdAlertsProvider.future,
          );
          expect(alerts, hasLength(1));
          expect(alerts.single.canonicalId, 'caffeine');
          expect(alerts.single.totalValue, 240);
          final snapshot = const StackIntelligenceEngine().summarizeFromReports(
            stackSize: 1,
            safetyReport: report,
            recalledReport: const RecalledIngredientsReport(violations: []),
            synergyReport: SynergyReport.empty(),
            doseThresholdAlerts: alerts,
          );
          expect(snapshot.reviewSignals, hasLength(2));
        },
      );
      expect(report.stackInteractions.map((w) => w.mechanism), [
        'Ordinary concern',
      ]);
    },
  );
  test(
    'strict caffeine bound reaches shared Stack once with honest copy',
    () async {
      final warning = {
        'type': 'interaction',
        'severity': 'avoid',
        'evidence_level': 'established',
        'title': 'Caffeine / pregnancy',
        'mechanism': 'Authored dose concern',
        'ingredient_name': 'Caffeine',
        'ingredient_canonical_id': 'caffeine',
        'condition_ids': ['pregnancy'],
        'dose_decision': {
          'evaluation_status': 'above_threshold',
          'consumer_disposition': 'review',
          'clinical_severity': 'avoid',
          'evaluated_daily_amount': 200,
          'evaluated_unit': 'mg',
          'threshold': 200,
          'threshold_unit': 'mg',
          'comparator': '>',
          'decision_rule': {
            'threshold': 200,
            'threshold_unit': 'mg',
            'comparator': '>',
            'consumer_disposition_if_met': 'review',
            'consumer_disposition_if_not_met': 'suppress',
          },
        },
      };
      await reportFor(
        {
          'warnings': [warning, warning],
        },
        resolvedRules: [],
        inspect: (container, report) async {
          final alerts = await container.read(
            stackDoseThresholdAlertsProvider.future,
          );
          expect(alerts, hasLength(1));
          final snapshot = const StackIntelligenceEngine().summarizeFromReports(
            stackSize: 1,
            safetyReport: report,
            recalledReport: const RecalledIngredientsReport(violations: []),
            synergyReport: SynergyReport.empty(),
            doseThresholdAlerts: alerts,
          );
          expect(snapshot.reviewSignals, hasLength(1));
          expect(
            snapshot.reviewSignals.single.body,
            contains('more than 200 mg'),
          );
          expect(
            report.stackInteractions,
            isEmpty,
            reason: 'dose owner prevents a duplicate warning',
          );
        },
      );
    },
  );

  test(
    'shared Product Detail suppression keeps benefits and no-data notes out',
    () async {
      final report = await reportFor({
        'warnings': [
          {
            'type': 'interaction',
            'severity': 'monitor',
            'evidence_level': 'established',
            'title': 'Benefit fixture',
            'mechanism': 'Beneficial fixture',
            'condition_ids': ['pregnancy'],
            'direction': 'beneficial',
          },
          {
            'type': 'interaction',
            'severity': 'caution',
            'evidence_level': 'no_data',
            'title': 'No data fixture',
            'mechanism': 'No data fixture',
            'condition_ids': ['pregnancy'],
          },
        ],
      });
      expect(report.stackInteractions, isEmpty);
    },
  );
  test('printed label statement appears once with unchanged text', () async {
    const text = 'Do not use if pregnant.';
    final warning = {
      'type': 'label_statement',
      'severity': 'avoid',
      'evidence_level': 'ungraded',
      'title': 'Label warning',
      'alert_body': text,
      'condition_ids': ['pregnancy'],
    };
    final report = await reportFor({
      'warnings': [warning],
      'warnings_profile_gated': [warning],
    });
    expect(report.stackInteractions, hasLength(1));
    expect(report.stackInteractions.single.mechanism, text);
  });
  test('unmatched flag-only hard warning remains absent', () async {
    final report = await reportFor({
      'warnings': [
        {
          'type': 'label_statement',
          'severity': 'avoid',
          'title': 'Label warning',
          'mechanism': 'Printed warning',
          'profile_gate': {
            'gate_type': 'profile_flag',
            'requires': {
              'profile_flags_any': ['breastfeeding'],
            },
          },
        },
      ],
    });
    expect(report.stackInteractions, isEmpty);
  });
  test('unmatched allergen remains absent', () async {
    final report = await reportFor({
      'allergens': [
        {'allergen_id': 'ALLERGEN_SOY', 'presence_type': 'contains'},
      ],
    }, profile: const ProfileState(allergens: ['ALLERGEN_MILK']));
    expect(report.stackInteractions, isEmpty);
  });
  test(
    'unavailable schema-3 reference retains readable static warning',
    () async {
      final report = await reportFor(sjw, resolutionFails: true);
      expect(
        report.stackInteractions.where(
          (w) => w.mechanism.toLowerCase().contains('birth-defect'),
        ),
        hasLength(1),
      );
      expect(report.checksIncomplete, isTrue);
    },
  );
  for (final flagsFail in [true, false]) {
    test(
      'condition-only warning survives missing ${flagsFail ? "flags" : "classes"}',
      () async {
        final warnings = [
          {
            'type': 'interaction',
            'severity': 'caution',
            'evidence_level': 'established',
            'title': 'Known condition',
            'mechanism': 'Known condition concern',
            'condition_ids': ['pregnancy'],
          },
          {
            'type': 'interaction',
            'severity': 'avoid',
            'title': 'Excluded context',
            'mechanism': 'Cannot evaluate absent inputs',
            'condition_ids': ['pregnancy'],
            'profile_gate': {
              'gate_type': 'condition',
              'requires': {
                'conditions_any': ['pregnancy'],
              },
              'excludes': {
                flagsFail ? 'profile_flags_any' : 'drug_classes_any': [
                  'fixture',
                ],
              },
            },
          },
        ];
        final report = await reportFor(
          {'warnings': warnings},
          flagsFail: flagsFail,
          classesFail: !flagsFail,
        );
        expect(report.stackInteractions.map((w) => w.mechanism), [
          'Known condition concern',
        ]);
        expect(report.checksIncomplete, isTrue);
      },
    );
  }
  test(
    'distinct visible warning headlines keep distinct Stack identities',
    () async {
      final warnings = [
        for (final headline in ['First concern', 'Second concern'])
          {
            'type': 'interaction',
            'severity': 'caution',
            'evidence_level': 'established',
            'title': 'Same internal title',
            'alert_headline': headline,
            'mechanism': 'Shared body',
            'condition_ids': ['pregnancy'],
          },
      ];
      final report = await reportFor({'warnings': warnings});
      expect(report.stackInteractions, hasLength(2));
      expect(report.stackInteractions.map((w) => w.id).toSet(), hasLength(2));
    },
  );
  test('unmatched profile does not receive SJW pregnancy warning', () async {
    final report = await reportFor(sjw, profile: const ProfileState());
    expect(
      report.stackInteractions.where(
        (w) => w.mechanism.toLowerCase().contains('birth-defect'),
      ),
      isEmpty,
    );
  });
  test(
    'another failed blob retains known warning and marks incomplete',
    () async {
      final report = await reportFor(sjw, secondBlobFails: true);
      expect(
        report.stackInteractions.where(
          (w) => w.mechanism.toLowerCase().contains('birth-defect'),
        ),
        hasLength(1),
      );
      expect(report.checksIncomplete, isTrue);
    },
  );
  for (final presence in [
    'contains',
    'may_contain',
    'manufactured_in_facility',
  ]) {
    test(
      'matched allergen $presence retains existing product meaning',
      () async {
        final report = await reportFor({
          'allergens': [
            {
              'allergen_id': 'ALLERGEN_SOY',
              'display_name': 'Soy',
              'presence_type': presence,
              'severity_level': 'high',
              'evidence': 'Label soy statement',
            },
          ],
        }, profile: const ProfileState(allergens: ['ALLERGEN_SOY']));
        expect(report.stackInteractions, hasLength(1));
        final snapshot = const StackIntelligenceEngine().summarizeFromReports(
          stackSize: 1,
          safetyReport: report,
          recalledReport: const RecalledIngredientsReport(violations: []),
          synergyReport: SynergyReport.empty(),
        );
        expect(snapshot.reviewSignals, hasLength(1));
        expect(
          snapshot.actionableSignals,
          hasLength(presence == 'manufactured_in_facility' ? 0 : 1),
        );

        expect(report.stackInteractions.single.severity, switch (presence) {
          'contains' => Severity.avoid,
          'may_contain' => Severity.caution,
          _ => Severity.informational,
        });
        expect(
          report.stackInteractions.single.mechanism,
          contains('Label soy statement'),
        );
      },
    );
  }
}
