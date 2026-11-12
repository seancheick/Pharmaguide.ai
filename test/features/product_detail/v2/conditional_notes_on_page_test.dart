// Dr. Pham G4 (2026-11-11): "Show both avoid and contraindicated findings as
// conditional notes when their applicability is unknown", with no personalized
// verdict. These cases run the real Product Detail composition: the real
// medication check against a seeded interaction database, the shipped SAMe
// pairs (DSI_TRANYLCYPROMINE_SAME, DSI_MAOI_SAME) and the shipped
// RULE_IQM_SAME MAOI row in the product's detail blob.

import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/schema_ids.dart';
import 'package:pharmaguide/core/data/drug_class_vocab.dart';
import 'package:pharmaguide/core/data/vocab_registry.dart';
import 'package:pharmaguide/core/models/fit_score_result.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/interaction_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/data/providers/reference_data_provider.dart';
import 'package:pharmaguide/features/product_detail/providers/detail_blob_provider.dart';
import 'package:pharmaguide/features/product_detail/providers/fit_score_provider.dart';
import 'package:pharmaguide/features/product_detail/v2/product_detail_v2_connected.dart';
import 'package:pharmaguide/features/safety_alerts/providers/safety_alert_providers.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';
import 'package:pharmaguide/features/stack/providers/stack_providers.dart';
import 'package:pharmaguide/services/safety_alerts/safety_alert.dart';
import 'package:pharmaguide/services/safety_alerts/safety_alert_repository.dart';

const _dsldId = 'dsld-same-page';
const _classHeadline = 'Avoid combining with MAOIs';
const _conditionalScope =
    'Relevant if you take: MAOIs. Add your medicines to check whether it '
    'applies to you.';
const _pharmacistScope =
    "Relevant if you take: MAOIs. We couldn't match your medicines to a "
    'group; ask your pharmacist whether this applies to you.';

/// RULE_IQM_SAME's MAOI row as build_final_db exports it (G4 display mode).
const _sameMaoiRow = <String, dynamic>{
  'type': 'drug_interaction',
  'severity': 'avoid',
  'severity_contextual': 'informational',
  'display_mode_default': 'informational',
  'title': 'SAMe / maois',
  'alert_headline': _classHeadline,
  'alert_body':
      'If you take an MAO inhibitor, avoid this product. SAMe raises serotonin '
      'activity; the tranylcypromine (Parnate) label lists it as '
      'contraindicated because of serotonin syndrome.',
  'drug_class_id': 'maois',
  'ingredient_name': 'SAMe',
  'ingredient_canonical_id': 'same',
  'evidence_level': 'moderate',
  'direction': 'harmful',
  'materiality': 'presence',
  'source': 'interaction_rules',
  'source_rule_id': 'RULE_IQM_SAME',
  'sources': [
    'https://dailymed.nlm.nih.gov/dailymed/drugInfo.cfm?setid=3c14a558-2df4-4d93-97dd-640dec6ee785',
  ],
  'profile_gate': {
    'gate_type': 'drug_class',
    'requires': {
      'conditions_any': <String>[],
      'drug_classes_any': ['maois'],
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
};

const _blob = <String, dynamic>{
  'ingredients': <Map<String, dynamic>>[],
  'warnings': [_sameMaoiRow],
  'warnings_profile_gated': [_sameMaoiRow],
};

UserStacksLocalData _medication(
  String id,
  String name,
  String rxcui, {
  String drugClassesCol = '["class:maois"]',
}) {
  final ts = DateTime.utc(2026, 11, 11, 12);
  return UserStacksLocalData(
    id: id,
    type: 'medication',
    name: name,
    rxcui: rxcui,
    genericRxcui: rxcui,
    drugClassesCol: drugClassesCol,
    addedAt: ts,
    clientUpdatedAt: ts,
  );
}

InteractionsCompanion _samePair({
  required String id,
  String agent1Type = 'drug',
  required String agent1Name,
  required String agent1Id,
  required String mechanism,
  required String management,
  required String evidenceLevel,
}) => InteractionsCompanion.insert(
  id: id,
  agent1Type: agent1Type,
  agent1Name: agent1Name,
  agent1Id: agent1Id,
  agent1CanonicalId: const Value(null),
  agent2Type: 'supplement',
  agent2Name: 'SAMe',
  agent2Id: 'C0036002',
  agent2CanonicalId: const Value('same'),
  severity: 'contraindicated',
  effectType: const Value('additive'),
  mechanism: mechanism,
  management: management,
  evidenceLevel: Value(evidenceLevel),
  sourceUrlsJson:
      '["https://dailymed.nlm.nih.gov/dailymed/drugInfo.cfm?setid=3c14a558-2df4-4d93-97dd-640dec6ee785"]',
  sourcePmidsJson: '[]',
  doseDependent: const Value(0),
  direction: const Value('harmful'),
  materiality: const Value('presence'),
  typeAuthored: 'Med-Sup',
  source: 'curated',
  provenance: 'drug_label',
  versionAdded: 'test',
  versionLastModified: 'test',
  lastUpdated: '2026-11-11',
);

Future<void> _pumpPage(
  WidgetTester tester, {
  List<UserStacksLocalData> stack = const [],
  Map<String, dynamic> blob = _blob,
  bool seedPairs = true,
  bool stackClassesLoading = false,
  bool stackReadFails = false,
  List<String> profileDrugClasses = const [],
}) async {
  final coreDb = CoreDatabase.memory();
  final userDb = UserDatabase.memory();
  final interactionDb = InteractionDatabase.memory();
  await coreDb
      .into(coreDb.productsCore)
      .insert(
        ProductsCoreCompanion.insert(
          dsldId: _dsldId,
          productName: 'SAMe 400',
          exportVersion: 'test',
          exportedAt: '2026-11-11T00:00:00Z',
          keyIngredientTags: const Value('["same"]'),
          mappedCoverage: const Value(1),
        ),
      );
  if (seedPairs) await _seedSamePairs(interactionDb);
  // The shipped class map holds both medicines in class:maois.
  await interactionDb
      .into(interactionDb.drugClassMap)
      .insert(
        DrugClassMapCompanion.insert(
          classId: 'class:maois',
          className: 'MAOIs',
          drugRxcuisJson: '["10734","8123"]',
          source: 'fixture',
          lastUpdated: '2026-11-11',
        ),
      );
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
        interactionDatabaseProvider.overrideWithValue(interactionDb),
        safetyAlertRepositoryProvider.overrideWithValue(_VerifiedNoAlerts()),
        activeStackProvider.overrideWith(
          (ref) async =>
              stackReadFails ? throw StateError('stack read failed') : stack,
        ),
        detailBlobProvider.overrideWith((ref, dsldId) async => blob),
        detailBlobForRowProvider.overrideWith((ref, key) async => blob),
        if (stackClassesLoading)
          currentStackMedicationClassIdsProvider.overrideWith(
            (ref) => Completer<Set<String>>().future,
          ),
        profileProvider.overrideWith(
          (ref) => ProfileNotifier()..setDrugClasses(profileDrugClasses),
        ),
        fitScoreForProductProvider.overrideWith(
          (ref, dsldId) async => const FitScoreResult(
            missingFields: [],
            state: FitAssessmentState.limitedFit,
            reasons: [],
            mappedCoverage: 1,
          ),
        ),
        evaluatorProfileFlagsProvider.overrideWith(
          (ref) async => const <String>{},
        ),
        rdaOptimalUlsProvider.overrideWith((ref) async => const {}),
      ],
      child: const MaterialApp(
        home: ProductDetailV2ConnectedScreen(dsldId: _dsldId),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _seedSamePairs(InteractionDatabase interactionDb) async {
  await interactionDb
      .into(interactionDb.interactions)
      .insert(
        _samePair(
          id: 'DSI_TRANYLCYPROMINE_SAME',
          agent1Name: 'Tranylcypromine',
          agent1Id: '10734',
          mechanism:
              'The tranylcypromine label lists SAMe among contraindicated '
              'combinations because of serotonin syndrome.',
          management: 'Do not take SAMe with tranylcypromine.',
          evidenceLevel: 'established',
        ),
      );
  await interactionDb
      .into(interactionDb.interactions)
      .insert(
        _samePair(
          id: 'DSI_MAOI_SAME',
          agent1Type: 'drug_class',
          agent1Name: 'MAOIs (class)',
          agent1Id: 'class:maois',
          mechanism: 'Class inference from the tranylcypromine label.',
          management: 'Do not combine SAMe with an MAOI.',
          evidenceLevel: 'moderate',
        ),
      );
}

void main() {
  setUpAll(() async {
    VocabRegistry.instance.debugSeed(drugClasses: await loadDrugClassVocab());
  });
  tearDownAll(VocabRegistry.instance.debugReset);

  testWidgets(
    'no medicines: SAMe shows a conditional MAOI note, not a warning',
    (tester) async {
      await _pumpPage(tester);

      expect(find.text('Good to know'), findsOneWidget);
      await tester.tap(find.text('Good to know'));
      await tester.pumpAndSettle();
      expect(find.text(_classHeadline, skipOffstage: false), findsOneWidget);
      expect(
        find.textContaining(_conditionalScope, skipOffstage: false),
        findsOneWidget,
      );
      expect(find.text('Review for your profile'), findsNothing);
      expect(find.textContaining("Because you're taking"), findsNothing);
    },
  );

  testWidgets(
    'an MAOI on the list: the actionable warning, no conditional note',
    (tester) async {
      await _pumpPage(
        tester,
        stack: [_medication('med-phenelzine', 'Phenelzine', '8123')],
      );

      expect(
        find.textContaining(_conditionalScope, skipOffstage: false),
        findsNothing,
      );
      // The contraindicated class pair is the medication check's answer for
      // phenelzine; the avoid class rule for the same hazard does not repeat it.
      expect(
        find.textContaining(
          "Because you're taking Phenelzine",
          skipOffstage: false,
        ),
        findsWidgets,
      );
      // The inferred class pair carries its own (moderate) evidence grade.
      expect(
        find.textContaining(
          RegExp(
            r'Class inference from the tranylcypromine label\..*'
            'Moderate supporting evidence',
          ),
          skipOffstage: false,
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Strong supporting evidence', skipOffstage: false),
        findsNothing,
      );
      expect(find.text(_classHeadline, skipOffstage: false), findsNothing);
      expect(find.text('No known concerns'), findsNothing);
    },
  );

  testWidgets(
    'tranylcypromine: the exact contraindication once, with no conditional note',
    (tester) async {
      await _pumpPage(
        tester,
        stack: [_medication('med-tranylcypromine', 'Tranylcypromine', '10734')],
      );

      expect(
        find.textContaining(_conditionalScope, skipOffstage: false),
        findsNothing,
      );
      expect(
        find.textContaining(
          'The tranylcypromine label lists SAMe',
          skipOffstage: false,
        ),
        findsOneWidget,
      );
      // The exact label pair carries its own (established) evidence grade.
      expect(
        find.textContaining(
          RegExp(
            'The tranylcypromine label lists SAMe.*Strong supporting evidence',
          ),
          skipOffstage: false,
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'Moderate supporting evidence',
          skipOffstage: false,
        ),
        findsNothing,
      );
      // Neither the class pair nor the class rule repeats it.
      expect(
        find.textContaining(
          'Class inference from the tranylcypromine label.',
          skipOffstage: false,
        ),
        findsNothing,
      );
      expect(find.text(_classHeadline, skipOffstage: false), findsNothing);
      expect(find.text('No known concerns'), findsNothing);
    },
  );

  testWidgets(
    'a contraindicated finding still reaches a matched user as a warning',
    (tester) async {
      // G4 ships contraindicated profile rows as informational; a match must
      // still promote the full warning. No pairs, so the rule row is the answer.
      final row = <String, dynamic>{
        ..._sameMaoiRow,
        'severity': 'contraindicated',
        'severity_contextual': 'contraindicated',
      };
      await _pumpPage(
        tester,
        seedPairs: false,
        blob: {
          'ingredients': <Map<String, dynamic>>[],
          'warnings': [row],
          'warnings_profile_gated': [row],
        },
        stack: [_medication('med-phenelzine', 'Phenelzine', '8123')],
      );

      expect(find.text(_classHeadline, skipOffstage: false), findsWidgets);
      expect(
        find.textContaining('Relevant if you take', skipOffstage: false),
        findsNothing,
      );
      expect(find.text('No known concerns'), findsNothing);
    },
  );

  testWidgets(
    'a medicine the app could not classify: the note asks the pharmacist',
    (tester) async {
      await _pumpPage(
        tester,
        stack: [
          _medication(
            'med-unknown',
            'Unlisted medicine',
            '999999',
            drugClassesCol: '[]',
          ),
        ],
      );

      await tester.tap(find.text('Good to know'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(_pharmacistScope, skipOffstage: false),
        findsOneWidget,
      );
      expect(
        find.textContaining('Add your medicines', skipOffstage: false),
        findsNothing,
      );
    },
  );

  testWidgets(
    'a stack that could not be read is not "no medicines": ask the pharmacist',
    (tester) async {
      await _pumpPage(tester, stackReadFails: true);

      // The incomplete-checks banner pushes the card below the fold.
      await tester.ensureVisible(
        find.text('Good to know', skipOffstage: false),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Good to know'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(_pharmacistScope, skipOffstage: false),
        findsOneWidget,
      );
      expect(
        find.textContaining('Add your medicines', skipOffstage: false),
        findsNothing,
      );
    },
  );

  testWidgets('medicines answered "none" and none on the list: no note', (
    tester,
  ) async {
    await _pumpPage(tester, profileDrugClasses: [SchemaIds.drugClassNone]);

    expect(find.text('Good to know'), findsNothing);
    expect(
      find.textContaining('Relevant if you take', skipOffstage: false),
      findsNothing,
    );
  });

  testWidgets(
    'a stale "none" beside an unclassified medicine: the note asks the '
    'pharmacist',
    (tester) async {
      await _pumpPage(
        tester,
        profileDrugClasses: [SchemaIds.drugClassNone],
        stack: [
          _medication(
            'med-unknown',
            'Unlisted medicine',
            '999999',
            drugClassesCol: '[]',
          ),
        ],
      );

      await tester.tap(find.text('Good to know'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(_pharmacistScope, skipOffstage: false),
        findsOneWidget,
      );
    },
  );

  testWidgets('no conditional note while medicine classes are loading', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      stackClassesLoading: true,
      stack: [_medication('med-phenelzine', 'Phenelzine', '8123')],
    );

    expect(
      find.textContaining('Relevant if you take', skipOffstage: false),
      findsNothing,
    );
  });
}

/// A feed that loaded and has nothing to say.
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
