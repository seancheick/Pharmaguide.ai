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
    'aspirin is antiplatelet and is not promoted into NSAIDs by fallback',
    () async {
      final result = await bridge.resolve(
        selectedRxcui: '1191',
        runtimeClassIds: const ['class:anti_inflammatory_agents_non_steroidal'],
      );

      expect(
        result.curatedInteractionClassIds,
        contains('class:antiplatelet_agents'),
      );
      expect(
        result.curatedInteractionClassIds,
        isNot(contains('class:nsaids')),
      );
      expect(result.profileGateClassIds, ['antiplatelets']);
      expect(
        result.mergedInteractionClassIds,
        containsAll([
          'class:anti_inflammatory_agents_non_steroidal',
          'class:antiplatelet_agents',
        ]),
      );
    },
  );

  test(
    'product-level low-dose aspirin RxCUIs are not promoted into NSAIDs',
    () async {
      for (final rxcui in const ['243670', '315431']) {
        final result = await bridge.resolve(
          selectedRxcui: rxcui,
          runtimeClassIds: const [
            'class:anti_inflammatory_agents_non_steroidal',
          ],
        );

        expect(
          result.curatedInteractionClassIds,
          isNot(contains('class:nsaids')),
          reason: 'RxCUI $rxcui should not fall through to generic NSAID',
        );
        expect(result.profileGateClassIds, isNot(contains('nsaids')));
        expect(
          result.mergedInteractionClassIds,
          contains('class:anti_inflammatory_agents_non_steroidal'),
        );
      }
    },
  );

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
