import 'dart:convert';
import 'dart:io';
import 'package:pharmaguide/services/stack/medication_profile_gate_evaluator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/interaction_database.dart';
import 'package:pharmaguide/services/medications/medication_class_bridge.dart';

void main() {
  late InteractionDatabase db;
  late MedicationClassBridge bridge;

  setUp(() async {
    db = InteractionDatabase.memory();
    bridge = MedicationClassBridge(db: db);

    await db
        .into(db.drugClassMap)
        .insert(
          DrugClassMapCompanion.insert(
            classId: 'class:nsaids',
            className: 'NSAIDs',
            drugRxcuisJson: '["5640","7258"]',
            source: 'fixture',
            lastUpdated: '2026-06-27',
          ),
        );
    await db
        .into(db.drugClassMap)
        .insert(
          DrugClassMapCompanion.insert(
            classId: 'class:antiplatelet_agents',
            className: 'Antiplatelet agents',
            drugRxcuisJson: '["1191"]',
            source: 'fixture',
            lastUpdated: '2026-06-27',
          ),
        );
  });

  test(
    'authored class exclusions survive SQL and block only matching fallback',
    () async {
      await db.customStatement(
        "UPDATE drug_class_map SET excluded_drug_rxcuis_json='[\"2473\",\"4845\"]' WHERE class_id='class:nsaids'",
      );
      final rules = MedicationProfileGateRule.listFromJson(
        jsonDecode(
              File(
                'assets/reference_data/medication_profile_gate_rules.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>,
      );
      List<String> gateIds(MedicationClassResolution resolution) =>
          const MedicationProfileGateEvaluator()
              .evaluate(
                rules: rules,
                medicationName: 'test',
                medicationProfileGateClassIds: resolution.profileGateClassIds
                    .toSet(),
                userProfileFlags: {'pregnant', 'pregnancy'},
                userConditions: {'kidney_disease'},
              )
              .map((warning) => warning.ruleId)
              .toList();
      for (final id in ['2473', '4845']) {
        final result = await bridge.resolve(
          selectedRxcui: id,
          runtimeClassIds: ['class:anti_inflammatory_agents_non_steroidal'],
        );
        expect(
          result.curatedInteractionClassIds,
          isNot(contains('class:nsaids')),
        );
        expect(result.profileGateClassIds, isNot(contains('nsaids')));
        expect(
          result.runtimeClassIds,
          contains('class:anti_inflammatory_agents_non_steroidal'),
        );
        expect(
          result.mergedInteractionClassIds,
          isNot(contains('class:anti_inflammatory_agents_non_steroidal')),
        );
        final cached = await bridge.resolve(
          selectedRxcui: id,
          runtimeClassIds: ['class:nsaids'],
        );
        expect(
          cached.mergedInteractionClassIds,
          isNot(contains('class:nsaids')),
        );
        expect(gateIds(result), isNot(contains('MCR_PREGNANCY_NSAIDS')));
        expect(gateIds(result), isNot(contains('MCR_KIDNEY_DISEASE_NSAIDS')));
      }
      final unknown = await bridge.resolve(
        selectedRxcui: '999999',
        runtimeClassIds: ['class:anti_inflammatory_agents_non_steroidal'],
      );
      expect(unknown.profileGateClassIds, contains('nsaids'));
      expect(
        gateIds(unknown),
        containsAll(['MCR_PREGNANCY_NSAIDS', 'MCR_KIDNEY_DISEASE_NSAIDS']),
      );
      final positive = await bridge.resolve(selectedRxcui: '5640');
      expect(positive.profileGateClassIds, contains('nsaids'));
      expect(gateIds(positive), contains('MCR_PREGNANCY_NSAIDS'));
    },
  );

  test(
    'combination positive membership survives another ingredient exclusion',
    () async {
      await db.customStatement(
        "UPDATE drug_class_map SET excluded_drug_rxcuis_json='[\"4845\"]' WHERE class_id='class:nsaids'",
      );
      final result = await bridge.resolve(
        genericRxcui: '4845',
        ingredientRxcuis: ['4845', '5640'],
        runtimeClassIds: [
          'class:nsaids',
          'class:anti_inflammatory_agents_non_steroidal',
        ],
      );
      expect(
        result.mergedInteractionClassIds,
        containsAll([
          'class:nsaids',
          'class:anti_inflammatory_agents_non_steroidal',
        ]),
      );
      expect(result.profileGateClassIds, contains('nsaids'));
    },
  );

  test(
    'exact IV ibandronate exclusion wins over its oral ingredient class',
    () async {
      await db
          .into(db.drugClassMap)
          .insert(
            DrugClassMapCompanion.insert(
              classId: 'class:bisphosphonates',
              className: 'Bisphosphonates',
              drugRxcuisJson: '["46041","115264","73056"]',
              source: 'pipeline batch 6',
              lastUpdated: '2026-11-12',
            ),
          );
      await db.customStatement(
        "UPDATE drug_class_map SET excluded_drug_rxcuis_json='[\"77655\",\"904952\",\"904954\",\"904955\"]' WHERE class_id='class:bisphosphonates'",
      );
      for (final product in ['904952', '904954', '904955']) {
        final result = await bridge.resolve(
          selectedRxcui: product,
          ingredientRxcuis: ['115264'],
          runtimeClassIds: ['class:bisphosphonates'],
        );
        expect(
          result.curatedInteractionClassIds,
          isNot(contains('class:bisphosphonates')),
        );
        expect(
          result.mergedInteractionClassIds,
          isNot(contains('class:bisphosphonates')),
        );
        expect(result.profileGateClassIds, isNot(contains('bisphosphonates')));
        expect(result.runtimeClassIds, contains('class:bisphosphonates'));
      }
      final genericInjection = await bridge.resolve(
        selectedRxcui: 'unresolved-brand',
        genericRxcui: '904952',
        ingredientRxcuis: ['115264'],
        runtimeClassIds: ['class:bisphosphonates'],
      );
      expect(
        genericInjection.profileGateClassIds,
        isNot(contains('bisphosphonates')),
      );
      for (final product in [
        '904932',
        '904934',
        '904936',
        '904946',
        '115264',
      ]) {
        final oralOrUnspecified = await bridge.resolve(
          selectedRxcui: product,
          ingredientRxcuis: ['115264'],
        );
        expect(
          oralOrUnspecified.profileGateClassIds,
          contains('bisphosphonates'),
        );
      }
    },
  );

  // Interaction audit 3b (Dr. Pham D2, 2026-11-11): diphenhydramine is an
  // anticholinergic member, and combination sleep/cold products must reach it
  // through their ingredient list. RxCUIs are the real RxNorm SCDs and the
  // ingredients RxNav returns for them (related.json?tty=IN).
  for (final combination in [
    (
      scd: '1092189',
      name: 'acetaminophen / diphenhydramine',
      ingredients: ['161', '3498'],
    ),
    (
      scd: '895664',
      name: 'diphenhydramine citrate / ibuprofen',
      ingredients: ['3498', '5640'],
    ),
    (
      scd: '1052928',
      name: 'diphenhydramine / phenylephrine',
      ingredients: ['3498', '8163'],
    ),
    (
      scd: '1046751',
      name: 'acetaminophen / diphenhydramine / phenylephrine',
      ingredients: ['161', '3498', '8163'],
    ),
  ]) {
    test(
      'combination sleep/cold product ${combination.name} reaches anticholinergic rules',
      () async {
        await db
            .into(db.drugClassMap)
            .insert(
              DrugClassMapCompanion.insert(
                classId: 'class:anticholinergics',
                className: 'Anticholinergic medicines',
                drugRxcuisJson: '["3498","32675"]',
                source: 'fixture',
                lastUpdated: '2026-11-11',
              ),
            );
        final result = await bridge.resolve(
          selectedRxcui: combination.scd,
          ingredientRxcuis: combination.ingredients,
        );
        expect(result.profileGateClassIds, contains('anticholinergics'));

        final unlisted = await bridge.resolve(
          selectedRxcui: combination.scd,
          ingredientRxcuis: combination.ingredients
              .where((r) => r != '3498')
              .toList(),
        );
        expect(
          unlisted.profileGateClassIds,
          isNot(contains('anticholinergics')),
        );
      },
    );
  }

  test('verified class-only entries reach existing profile rules', () async {
    final result = await bridge.resolve(runtimeClassIds: ['class:nsaids']);
    expect(result.rxcuis, isEmpty);
    expect(result.curatedInteractionClassIds, ['class:nsaids']);
    expect(result.mergedInteractionClassIds, ['class:nsaids']);
    expect(result.profileGateClassIds, ['nsaids']);
    final rules = MedicationProfileGateRule.listFromJson(
      jsonDecode(
            File(
              'assets/reference_data/medication_profile_gate_rules.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>,
    );
    final warnings = const MedicationProfileGateEvaluator().evaluate(
      rules: rules,
      medicationName: 'NSAID class entry',
      medicationProfileGateClassIds: result.profileGateClassIds.toSet(),
      userProfileFlags: {'pregnant'},
      userConditions: {'kidney_disease'},
    );
    expect(
      warnings.map((w) => w.ruleId),
      containsAll(['MCR_PREGNANCY_NSAIDS', 'MCR_KIDNEY_DISEASE_NSAIDS']),
    );
  });

  test(
    'class-only recognition does not trust an unknown class or override an identity',
    () async {
      final unknownClass = await bridge.resolve(
        runtimeClassIds: ['class:unreviewed_class'],
      );
      expect(unknownClass.curatedInteractionClassIds, isEmpty);
      expect(unknownClass.profileGateClassIds, isEmpty);
      final unresolvedIdentity = await bridge.resolve(
        selectedRxcui: '999999',
        runtimeClassIds: ['class:nsaids'],
      );
      expect(unresolvedIdentity.curatedInteractionClassIds, isEmpty);
      expect(unresolvedIdentity.profileGateClassIds, isEmpty);
    },
  );

  tearDown(() => db.close());

  test('ibuprofen RxCUI resolves to curated NSAID ids', () async {
    final result = await bridge.resolve(
      selectedRxcui: '5640',
      runtimeClassIds: const ['class:anti_inflammatory_agents_non_steroidal'],
    );

    expect(result.curatedInteractionClassIds, contains('class:nsaids'));
    expect(result.profileGateClassIds, contains('nsaids'));
    expect(
      result.mergedInteractionClassIds,
      containsAll([
        'class:anti_inflammatory_agents_non_steroidal',
        'class:nsaids',
      ]),
    );
  });

  test(
    'Motrin brand RxCUI resolves to NSAIDs without runtime classes',
    () async {
      final result = await bridge.resolve(selectedRxcui: '202488');

      expect(result.curatedInteractionClassIds, ['class:nsaids']);
      expect(result.profileGateClassIds, ['nsaids']);
      expect(result.mergedInteractionClassIds, ['class:nsaids']);
    },
  );

  test(
    'Motrin product RxCUI resolves to NSAIDs without network hydration',
    () async {
      final result = await bridge.resolve(selectedRxcui: '93358');

      expect(result.curatedInteractionClassIds, ['class:nsaids']);
      expect(result.profileGateClassIds, ['nsaids']);
    },
  );

  test('naproxen RxCUI resolves to NSAIDs', () async {
    final result = await bridge.resolve(selectedRxcui: '7258');

    expect(result.curatedInteractionClassIds, ['class:nsaids']);
    expect(result.profileGateClassIds, ['nsaids']);
  });

  test('acetaminophen does not resolve to NSAIDs', () async {
    final result = await bridge.resolve(
      selectedRxcui: '161',
      runtimeClassIds: const ['class:analgesics_non_narcotic'],
    );

    expect(result.curatedInteractionClassIds, isNot(contains('class:nsaids')));
    expect(result.profileGateClassIds, isNot(contains('nsaids')));
    expect(result.mergedInteractionClassIds, ['class:analgesics_non_narcotic']);
  });

  test(
    'aspirin retains antiplatelet and NSAID context for authored dose rules',
    () async {
      final result = await bridge.resolve(
        selectedRxcui: '1191',
        runtimeClassIds: const ['class:anti_inflammatory_agents_non_steroidal'],
      );

      expect(
        result.curatedInteractionClassIds,
        contains('class:antiplatelet_agents'),
      );
      expect(result.curatedInteractionClassIds, contains('class:nsaids'));
      expect(
        result.profileGateClassIds,
        containsAll(['antiplatelets', 'nsaids']),
      );
      expect(
        result.mergedInteractionClassIds,
        containsAll([
          'class:anti_inflammatory_agents_non_steroidal',
          'class:antiplatelet_agents',
        ]),
      );
    },
  );

  test('aspirin product dose alone does not suppress NSAID context', () async {
    for (final rxcui in const ['243670', '315431']) {
      final result = await bridge.resolve(
        selectedRxcui: rxcui,
        runtimeClassIds: const ['class:anti_inflammatory_agents_non_steroidal'],
      );

      expect(
        result.curatedInteractionClassIds,
        contains('class:nsaids'),
        reason:
            'RxCUI $rxcui retains context for authored dose and use evaluation',
      );
      expect(result.profileGateClassIds, contains('nsaids'));
      expect(
        result.mergedInteractionClassIds,
        contains('class:anti_inflammatory_agents_non_steroidal'),
      );
    }
  });

  test('uses RxClass fallback for unmapped runtime NSAID slugs', () async {
    final result = await bridge.resolve(
      runtimeClassIds: const ['class:cyclooxygenase_inhibitors'],
    );

    expect(result.curatedInteractionClassIds, ['class:nsaids']);
    expect(result.profileGateClassIds, ['nsaids']);
    expect(result.mergedInteractionClassIds, [
      'class:cyclooxygenase_inhibitors',
      'class:nsaids',
    ]);
  });
}
