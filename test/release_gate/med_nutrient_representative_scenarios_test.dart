import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pharmaguide/data/database/interaction_database.dart';
import 'package:pharmaguide/services/medications/medication_class_bridge.dart';
import 'package:pharmaguide/services/stack/depletion_checker.dart';

typedef _Scenario = ({
  String label,
  String medication,
  String rxcui,
  Set<String> expectedClasses,
  Set<String> expectedVisible,
  Set<String> expectedSuppressed,
});

const _scenarios = <_Scenario>[
  (
    label: 'metformin + B12',
    medication: 'metformin',
    rxcui: '6809',
    expectedClasses: {'class:diabetes_meds'},
    expectedVisible: {'DEP_METFORMIN_VITAMINB12'},
    expectedSuppressed: {'DEP_METFORMIN_FOLATE'},
  ),
  (
    label: 'warfarin + vitamin K',
    medication: 'warfarin',
    rxcui: '11289',
    expectedClasses: {'class:anticoagulants', 'class:vitamin_k_antagonists'},
    expectedVisible: {'DEP_ANTICOAGULANTS_VITAMINK'},
    expectedSuppressed: {},
  ),
  (
    label: 'levothyroxine + calcium/iron',
    medication: 'levothyroxine',
    rxcui: '10582',
    expectedClasses: {},
    expectedVisible: {'DEP_LEVOTHYROXINE_CALCIUM', 'DEP_LEVOTHYROXINE_IRON'},
    expectedSuppressed: {},
  ),
  (
    label: 'PPI + B12/magnesium',
    medication: 'omeprazole',
    rxcui: '7646',
    expectedClasses: {
      'class:acid_suppressants',
      'class:proton_pump_inhibitors',
    },
    expectedVisible: {'DEP_ANTACIDS_CALCIUM', 'DEP_ANTACIDS_IRON'},
    expectedSuppressed: {
      'DEP_ANTACIDS_VITAMINB12',
      'DEP_ANTACIDS_MAGNESIUM',
      'DEP_ANTACIDS_VITAMINC',
      'DEP_ANTACIDS_ZINC',
    },
  ),
  (
    label: 'statin + CoQ10',
    medication: 'atorvastatin',
    rxcui: '83367',
    expectedClasses: {'class:statins'},
    expectedVisible: {'DEP_STATINS_COQ10'},
    expectedSuppressed: {'DEP_STATINS_VITAMIND'},
  ),
  (
    label: 'corticosteroid + calcium',
    medication: 'prednisone',
    rxcui: '8640',
    expectedClasses: {'class:corticosteroids'},
    expectedVisible: {
      'DEP_CORTICOSTEROIDS_CALCIUM',
      'DEP_CORTICOSTEROIDS_VITAMIND',
    },
    expectedSuppressed: {
      'DEP_CORTICOSTEROIDS_POTASSIUM',
      'DEP_CORTICOSTEROIDS_MAGNESIUM',
      'DEP_CORTICOSTEROIDS_VITAMINC',
      'DEP_CORTICOSTEROIDS_ZINC',
      'DEP_CORTICOSTEROIDS_VITAMINB6',
    },
  ),
  (
    label: 'phenytoin case',
    medication: 'phenytoin',
    rxcui: '8183',
    expectedClasses: {
      'class:anticonvulsants',
      'class:enzyme_inducing_antiseizure_medications',
    },
    expectedVisible: {
      'DEP_ANTICONVULSANTS_CALCIUM',
      'DEP_ANTICONVULSANTS_FOLATE',
      'DEP_ANTICONVULSANTS_VITAMINB12',
      'DEP_ANTICONVULSANTS_VITAMINK',
    },
    expectedSuppressed: {'DEP_ANTICONVULSANTS_BIOTIN'},
  ),
  (
    label: 'carbamazepine case',
    medication: 'carbamazepine',
    rxcui: '2002',
    expectedClasses: {
      'class:anticonvulsants',
      'class:enzyme_inducing_antiseizure_medications',
    },
    expectedVisible: {
      'DEP_ANTICONVULSANTS_VITAMIND',
      'DEP_ANTICONVULSANTS_CALCIUM',
      'DEP_ANTICONVULSANTS_VITAMINK',
    },
    expectedSuppressed: {'DEP_ANTICONVULSANTS_BIOTIN'},
  ),
  (
    label: 'valproate case',
    medication: 'valproate',
    rxcui: '40254',
    expectedClasses: {'class:valproate'},
    expectedVisible: {'DEP_ANTICONVULSANTS_LCARNITINE'},
    expectedSuppressed: {'DEP_ANTICONVULSANTS_BIOTIN'},
  ),
  (
    label: 'no-match case',
    medication: 'unmapped medication',
    rxcui: '99999999',
    expectedClasses: {},
    expectedVisible: {},
    expectedSuppressed: {},
  ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late InteractionDatabase db;
  late MedicationClassBridge bridge;
  late Map<String, dynamic> artifact;

  setUpAll(() async {
    artifact =
        jsonDecode(
              File(
                'assets/reference_data/medication_depletions.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;

    final data = await rootBundle.load('assets/db/interaction_db.sqlite');
    tempDir = await Directory.systemTemp.createTemp('med-nutrient-matrix');
    final dbFile = File(p.join(tempDir.path, 'interaction_db.sqlite'));
    await dbFile.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
    db = InteractionDatabase.open(dbFile.path);
    bridge = MedicationClassBridge(db: db);
  });

  tearDownAll(() async {
    await db.close();
    await tempDir.delete(recursive: true);
  });

  for (final scenario in _scenarios) {
    test(
      '${scenario.label}: real normalization, taxonomy, and publication',
      () async {
        final resolution = await bridge.resolve(selectedRxcui: scenario.rxcui);
        expect(
          resolution.curatedInteractionClassIds.toSet(),
          containsAll(scenario.expectedClasses),
          reason:
              '${scenario.medication} (${scenario.rxcui}) did not resolve to '
              'the required packaged class membership',
        );

        final matches = DepletionChecker().check(
          medications: const [],
          medicationIdentities: [
            DepletionMedicationIdentity(
              name: scenario.medication,
              rxcui: scenario.rxcui,
              drugClassIds: resolution.mergedInteractionClassIds,
            ),
          ],
          depletionsData: artifact,
        );
        final visibleIds = matches.map((match) => match.depletionId).toSet();

        expect(visibleIds, scenario.expectedVisible);
        expect(
          visibleIds.intersection(scenario.expectedSuppressed),
          isEmpty,
          reason: 'suppressed/rejected records must never appear',
        );
        expect(
          matches.every((match) => match.citationReviewStatus == 'verified'),
          isTrue,
          reason: 'only citation-verified records may reach consumers',
        );

        for (final match in matches) {
          final body = medNutrientBodyCopy(
            relationshipType: match.depletionType,
            nutrient: match.nutrientName,
            subject: match.drugDisplayName,
            supplyState: MedNutrientSupplyState.noDetectedSource,
          );
          expect(
            body,
            isNot(
              contains(RegExp(r'\bmust supplement\b', caseSensitive: false)),
            ),
          );
          expect(
            body,
            isNot(
              contains(RegExp(r'\beveryone should\b', caseSensitive: false)),
            ),
          );
          expect(
            body,
            isNot(contains(RegExp(r'\bstart taking\b', caseSensitive: false))),
          );
          expect(
            '${match.alertBody ?? ''} ${match.recommendation}',
            isNot(
              contains(
                RegExp(
                  r'\b(everyone|all users) (needs?|should|must) supplement\b',
                  caseSensitive: false,
                ),
              ),
            ),
          );
        }
      },
    );
  }

  test(
    'incompatible artifact remains unavailable, never a false all-clear',
    () {
      final activated = activateMedicationDepletionsArtifact({
        '_metadata': {
          'minimum_runtime_contract': kMedNutrientRuntimeContract + 1,
        },
        'depletions': const <dynamic>[],
      });
      final report = (
        status: activated.status,
        matches: const <DepletionMatch>[],
      );

      expect(report.status, MedNutrientLoadStatus.unavailable);
      expect(report.status, isNot(MedNutrientLoadStatus.loaded));
    },
  );
}
