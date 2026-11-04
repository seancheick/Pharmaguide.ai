import 'package:pharmaguide/features/stack/providers/synergy_report_provider.dart';
import 'package:pharmaguide/services/stack/recalled_ingredient_result.dart';
import 'package:pharmaguide/services/stack/synergy_result.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/interaction_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/data/repositories/reference_data_repository.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';
import 'package:pharmaguide/features/safety_alerts/providers/safety_alert_providers.dart';
import 'package:pharmaguide/features/stack/providers/active_stack_provider.dart';
import 'package:pharmaguide/features/stack/providers/stack_nutrient_providers.dart';
import 'package:pharmaguide/features/stack/providers/stack_safety_providers.dart';
import 'package:pharmaguide/services/signals/clinical_signal_envelope.dart';
import 'package:pharmaguide/services/stack/stack_dose_summer.dart';
import 'package:pharmaguide/services/stack/stack_safety_report.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';
import 'package:pharmaguide/services/signals/stack_signal_aggregator.dart';

/// Forces the medication-profile-gate rule asset to fail loading so the
/// fail-open path (report still returns, flagged incomplete) can be exercised.
class _ThrowingMedicationRulesRepository extends ReferenceDataRepository {
  @override
  Future<Map<String, dynamic>> loadMedicationProfileGateRules() async {
    throw StateError('medication profile gate rules unavailable');
  }
}

UserStacksLocalData _medication({
  required String name,
  required String? rxcui,
  String? drugClasses,
  String? medicationContext,
}) {
  final now = DateTime.utc(2026, 6, 27);
  return UserStacksLocalData(
    id: 'med_$rxcui',
    type: 'medication',
    name: name,
    rxcui: rxcui,
    drugClassesCol: drugClasses,
    medicationContextCol: medicationContext,
    addedAt: now,
    clientUpdatedAt: now,
  );
}

UserStacksLocalData _supplement({required String id, required String name}) {
  final now = DateTime.utc(2026, 6, 27);
  return UserStacksLocalData(
    id: 'stack_$id',
    type: 'supplement',
    name: name,
    dsldId: id,
    addedAt: now,
    clientUpdatedAt: now,
  );
}

Future<ProviderContainer> _container({
  required ProfileState profile,
  required UserStacksLocalData medication,
  ReferenceDataRepository? referenceDataRepo,
}) async {
  final coreDb = CoreDatabase.memory();
  final interactionDb = InteractionDatabase.memory();
  addTearDown(coreDb.close);
  addTearDown(interactionDb.close);

  await interactionDb
      .into(interactionDb.drugClassMap)
      .insert(
        DrugClassMapCompanion.insert(
          classId: 'class:nsaids',
          className: 'NSAIDs',
          drugRxcuisJson: '["5640"]',
          source: 'fixture',
          lastUpdated: '2026-06-27',
        ),
      );

  final container = ProviderContainer(
    overrides: [
      coreDatabaseProvider.overrideWithValue(coreDb),
      interactionDatabaseProvider.overrideWithValue(interactionDb),
      activeStackProvider.overrideWith((ref) async => [medication]),
      loadedProfileProvider.overrideWith((ref) async => profile),
      stackNutrientStatusesProvider.overrideWith(
        (ref) async => const StackNutrientStatuses.empty(),
      ),
      if (referenceDataRepo != null)
        referenceDataRepositoryProvider.overrideWith(
          (ref) => referenceDataRepo,
        ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<ProviderContainer> _containerWithSupplementAndMedication({
  required ProfileState profile,
  required UserStacksLocalData medication,
  required UserStacksLocalData supplement,
  bool profileFails = false,
}) async {
  final coreDb = CoreDatabase.memory();
  final interactionDb = InteractionDatabase.memory();
  addTearDown(coreDb.close);
  addTearDown(interactionDb.close);

  await interactionDb
      .into(interactionDb.drugClassMap)
      .insert(
        DrugClassMapCompanion.insert(
          classId: 'class:nsaids',
          className: 'NSAIDs',
          drugRxcuisJson: '["5640"]',
          source: 'fixture',
          lastUpdated: '2026-06-27',
        ),
      );
  await interactionDb
      .into(interactionDb.interactions)
      .insert(
        InteractionsCompanion.insert(
          id: 'DSI_NSAID_TURMERIC',
          agent1Type: 'drug_class',
          agent1Name: 'NSAIDs',
          agent1Id: 'class:nsaids',
          agent2Type: 'supplement',
          agent2Name: 'Turmeric',
          agent2Id: 'umls:turmeric',
          agent2CanonicalId: const Value('turmeric'),
          severity: 'caution',
          mechanism: 'NSAIDs and turmeric may add bleeding-risk context.',
          management: 'Review with your clinician before combining.',
          evidenceLevel: const Value('established'),
          sourceUrlsJson: '[]',
          sourcePmidsJson: '[]',
          typeAuthored: 'drug_supplement',
          source: 'curated',
          provenance: 'fixture',
          versionAdded: 'test',
          versionLastModified: 'test',
          lastUpdated: '2026-06-27',
        ),
      );
  await coreDb
      .into(coreDb.productsCore)
      .insert(
        ProductsCoreCompanion.insert(
          dsldId: supplement.dsldId!,
          productName: supplement.name,
          productStatus: const Value('active'),
          keyIngredientTags: const Value('["turmeric"]'),
          exportVersion: 'test',
          exportedAt: '2026-06-27T00:00:00Z',
        ),
      );

  final container = ProviderContainer(
    overrides: [
      coreDatabaseProvider.overrideWithValue(coreDb),
      interactionDatabaseProvider.overrideWithValue(interactionDb),
      activeStackProvider.overrideWith((ref) async => [medication, supplement]),
      loadedProfileProvider.overrideWith((ref) async {
        if (profileFails) throw StateError('profile unreadable');
        return profile;
      }),
      if (profileFails) ...[
        stackDoseThresholdAlertsProvider.overrideWith(
          (ref) async => throw StateError('profile unreadable'),
        ),
        synergyReportProvider.overrideWith(
          (ref) async => SynergyReport.empty(),
        ),
        recalledIngredientsReportProvider.overrideWith(
          (ref) async => RecalledIngredientsReport(
            violations: [
              RecalledIngredientViolation(
                productDsldId: supplement.dsldId!,
                productName: supplement.name,
                brandName: '',
                recalledIngredients: [],
                pipelineRecalledProduct: true,
              ),
            ],
          ),
        ),
      ],
      stackNutrientStatusesProvider.overrideWith(
        (ref) async => const StackNutrientStatuses.empty(),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test(
    'profile failure retains known interaction and recall in shared snapshot',
    () async {
      final container = await _containerWithSupplementAndMedication(
        profile: const ProfileState(conditions: ['pregnancy']),
        profileFails: true,
        medication: _medication(name: 'Motrin', rxcui: '5640'),
        supplement: _supplement(id: 'TURMERIC_1', name: 'Turmeric Complex'),
      );
      final report = await container.read(stackSafetyReportProvider.future);
      expect(
        report.medicationInteractions.map((w) => w.id),
        contains('DSI_NSAID_TURMERIC'),
      );
      expect(report.checksIncomplete, isTrue);
      expect(report.medicationProfileWarnings, isEmpty);
      final snapshot = await container.read(stackHealthSnapshotProvider.future);
      expect(snapshot.intelligence.hasRecalledIngredient, isTrue);
      expect(snapshot.intelligence.analysisIncomplete, isTrue);
      expect(
        snapshot.reviewSignals.any(
          (s) => s.sourceRuleId == 'DSI_NSAID_TURMERIC',
        ),
        isTrue,
      );
    },
  );

  group('a failed unread dose rule read', () {
    ProviderContainer snapshotContainer(Future<bool> Function() unreadRules) {
      final supplement = _supplement(id: 'TURMERIC_1', name: 'Turmeric');
      final container = ProviderContainer(
        overrides: [
          activeStackProvider.overrideWith((ref) async => [supplement]),
          safetyAlertMatchesProvider.overrideWith(
            (ref) async => SafetyAlertMatchSet(
              matches: const [],
              baselineSignalKeys: const {},
              isComplete: true,
              neverVerified: false,
            ),
          ),
          stackSafetyReportProvider.overrideWith(
            (ref) async => const StackSafetyReport(),
          ),
          synergyReportProvider.overrideWith(
            (ref) async => SynergyReport.empty(),
          ),
          recalledIngredientsReportProvider.overrideWith(
            (ref) async => RecalledIngredientsReport(
              violations: [
                RecalledIngredientViolation(
                  productDsldId: supplement.dsldId!,
                  productName: supplement.name,
                  brandName: '',
                  recalledIngredients: [],
                  pipelineRecalledProduct: true,
                ),
              ],
            ),
          ),
          stackDoseThresholdAlertsProvider.overrideWith(
            (ref) async => const <StackDoseThresholdAlert>[],
          ),
          stackDoseRulesUnreadProvider.overrideWith((ref) => unreadRules()),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('nothing else is incomplete when the read succeeds', () async {
      final container = snapshotContainer(() async => false);
      await container.read(safetyAlertMatchesProvider.future);
      final snapshot = await container.read(stackHealthSnapshotProvider.future);
      expect(snapshot.intelligence.analysisIncomplete, isFalse);
    });

    test('is incomplete at once and keeps the recall', () async {
      final container = snapshotContainer(
        () async => throw Exception('rule unreadable'),
      );
      await container.read(safetyAlertMatchesProvider.future);
      final snapshot = await container
          .read(stackHealthSnapshotProvider.future)
          .timeout(const Duration(seconds: 2));
      expect(snapshot.intelligence.analysisIncomplete, isTrue);
      expect(snapshot.intelligence.hasRecalledIngredient, isTrue);
    });
  });

  for (final entry in {
    'pregnancy': 'MCR_PREGNANCY_NSAIDS',
    'kidney_disease': 'MCR_KIDNEY_DISEASE_NSAIDS',
    '': null,
  }.entries) {
    test(
      'saved class-only NSAID entry respects profile ${entry.key}',
      () async {
        final container = await _container(
          profile: ProfileState(
            conditions: [if (entry.key.isNotEmpty) entry.key],
          ),
          medication: _medication(
            name: 'NSAIDs',
            rxcui: null,
            drugClasses: '["class:nsaids"]',
          ),
        );
        final report = await container.read(stackSafetyReportProvider.future);
        if (entry.value == null) {
          expect(report.medicationProfileWarnings, isEmpty);
        } else {
          expect(
            report.medicationProfileWarnings.map((w) => w.ruleId),
            contains(entry.value),
          );
          expect(
            orderedSignalsFrom(
              report,
            ).where((s) => s.family == SignalFamily.medicationProfile),
            isNotEmpty,
          );
        }
      },
    );
  }

  test(
    'actual stack consumer uses confirmed context and unknown legacy aspirin warns',
    () async {
      for (final context in [
        null,
        '{"daily_dose_mg":81}',
        '{"daily_dose_mg":81,"use_context":"clinician_directed_pregnancy_condition"}',
      ]) {
        final container = await _container(
          profile: const ProfileState(conditions: ['pregnancy']),
          medication: _medication(
            name: 'Aspirin',
            rxcui: '1191',
            medicationContext: context,
          ),
        );
        final report = await container.read(stackSafetyReportProvider.future);
        if (context?.contains('clinician_directed_pregnancy_condition') ??
            false) {
          expect(report.medicationProfileWarnings, isEmpty);
        } else {
          expect(
            report.medicationProfileWarnings.map((w) => w.ruleId),
            contains('MCR_PREGNANCY_NSAIDS'),
          );
        }
      }
    },
  );

  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'pregnant profile plus Motrin brand RxCUI produces profile warning offline',
    () async {
      final container = await _container(
        profile: const ProfileState(conditions: ['pregnancy']),
        medication: _medication(name: 'Motrin', rxcui: '202488'),
      );

      final report = await container.read(stackSafetyReportProvider.future);

      expect(report.medicationProfileWarnings, hasLength(1));
      expect(
        report.medicationProfileWarnings.single.ruleId,
        'MCR_PREGNANCY_NSAIDS',
      );
      final signal = orderedSignalsFrom(report).first;
      expect(signal.family, SignalFamily.medicationProfile);
      expect(
        (signal.payload as MedicationProfilePayload).warning,
        report.medicationProfileWarnings.single,
      );
    },
  );

  test(
    'kidney disease profile plus ibuprofen produces profile warning',
    () async {
      final container = await _container(
        profile: const ProfileState(conditions: ['kidney_disease']),
        medication: _medication(name: 'ibuprofen', rxcui: '5640'),
      );

      final report = await container.read(stackSafetyReportProvider.future);

      expect(report.medicationProfileWarnings, hasLength(1));
      expect(
        report.medicationProfileWarnings.single.ruleId,
        'MCR_KIDNEY_DISEASE_NSAIDS',
      );
      expect(
        report.medicationProfileWarnings.single.headline,
        'Review systemic NSAID use with kidney disease',
      );
      final signal = orderedSignalsFrom(report).first;
      expect(signal.family, SignalFamily.medicationProfile);
      expect(
        (signal.payload as MedicationProfilePayload).warning,
        report.medicationProfileWarnings.single,
      );
    },
  );

  test(
    'medication whose drug class cannot be resolved marks checks incomplete',
    () async {
      // A brand/product RxCUI (here Advil 153010) saved before its ingredient
      // + classes hydrated, then evaluated offline: the bridge resolves no
      // drug class, so no class-level NSAID/condition check can run for it.
      // The report must hedge ("checks may be incomplete") rather than render
      // a false clean result — under-warning is the worse failure here, and
      // this is the generic safety net for every unresolvable brand, not just
      // the Motrin alias special-case.
      final container = await _container(
        profile: const ProfileState(),
        medication: _medication(name: 'Advil', rxcui: '153010'),
      );

      final report = await container.read(stackSafetyReportProvider.future);

      expect(report.checksIncomplete, isTrue);
    },
  );

  test('medication that resolves a drug class keeps checks complete', () async {
    // Control: ibuprofen ingredient RxCUI resolves class:nsaids from the
    // bundled membership, so the result is NOT flagged incomplete.
    final container = await _container(
      profile: const ProfileState(),
      medication: _medication(name: 'ibuprofen', rxcui: '5640'),
    );

    final report = await container.read(stackSafetyReportProvider.future);

    expect(report.checksIncomplete, isFalse);
  });

  test(
    'medication-profile rule load failure fails open as checks incomplete',
    () async {
      // If the rule asset cannot be loaded, the stack safety pass must still
      // return a report — degraded (checksIncomplete) — never throw or drop
      // the whole result. ibuprofen 5640 resolves cleanly, so the only reason
      // checks are incomplete here is the rule-load failure itself.
      final container = await _container(
        profile: const ProfileState(),
        medication: _medication(name: 'ibuprofen', rxcui: '5640'),
        referenceDataRepo: _ThrowingMedicationRulesRepository(),
      );

      final report = await container.read(stackSafetyReportProvider.future);

      expect(report.checksIncomplete, isTrue);
      expect(report.medicationProfileWarnings, isEmpty);
    },
  );

  test(
    'non-pregnant profile plus Motrin does not produce pregnancy warning',
    () async {
      final container = await _container(
        profile: const ProfileState(),
        medication: _medication(
          name: 'Motrin',
          rxcui: '5640',
          drugClasses: '["class:anti_inflammatory_agents_non_steroidal"]',
        ),
      );

      final report = await container.read(stackSafetyReportProvider.future);

      expect(report.medicationProfileWarnings, isEmpty);
    },
  );

  test(
    'old Motrin row with only runtime RxClass slug still triggers class interactions',
    () async {
      final container = await _containerWithSupplementAndMedication(
        profile: const ProfileState(),
        medication: _medication(
          name: 'Motrin',
          rxcui: '5640',
          drugClasses: '["class:anti_inflammatory_agents_non_steroidal"]',
        ),
        supplement: _supplement(id: 'TURMERIC_1', name: 'Turmeric Complex'),
      );

      final report = await container.read(stackSafetyReportProvider.future);

      expect(report.medicationInteractions, hasLength(1));
      expect(report.medicationInteractions.single.id, 'DSI_NSAID_TURMERIC');
      expect(report.medicationInteractions.single.agent1Name, 'Motrin');
    },
  );

  test(
    'old Motrin brand row with no classes still triggers class interactions',
    () async {
      final container = await _containerWithSupplementAndMedication(
        profile: const ProfileState(),
        medication: _medication(name: 'Motrin', rxcui: '202488'),
        supplement: _supplement(id: 'TURMERIC_1', name: 'Turmeric Complex'),
      );

      final report = await container.read(stackSafetyReportProvider.future);

      expect(report.medicationInteractions, hasLength(1));
      expect(report.medicationInteractions.single.id, 'DSI_NSAID_TURMERIC');
      expect(report.medicationInteractions.single.agent1Name, 'Motrin');
    },
  );
}
