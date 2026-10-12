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
