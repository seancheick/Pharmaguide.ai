import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/interaction_result.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/repositories/health_event_repository.dart';
import 'package:pharmaguide/services/signals/clinical_signal_envelope.dart';
import 'package:pharmaguide/services/signals/clinical_signal_lifecycle_service.dart';

ClinicalSignal _signal({String mechanism = 'May increase bleeding risk.'}) {
  return ClinicalSignal.fromInteraction(
    InteractionResult(
      id: 'RULE_WARFARIN_GINKGO',
      type: InteractionType.drugSupplement,
      severity: Severity.avoid,
      evidenceLevel: EvidenceLevel.established,
      agent1Name: 'Warfarin',
      agent2Name: 'Ginkgo',
      mechanism: mechanism,
      management: 'Discuss with your anticoagulation clinician.',
      doseDependant: false,
      doseThreshold: null,
      sourceUrls: const ['https://pubmed.ncbi.nlm.nih.gov/12345678/'],
      source: InteractionSource.pipeline,
    ),
  );
}

void main() {
  late UserDatabase database;
  late HealthEventRepository history;
  late ClinicalSignalLifecycleService lifecycle;
  var nextId = 0;
  final now = DateTime.utc(2026, 7, 30, 15);

  setUp(() {
    database = UserDatabase.memory();
    history = HealthEventRepository(
      database,
      idFactory: () => 'event-${nextId++}',
      clock: () => now.add(Duration(seconds: nextId)),
    );
    lifecycle = ClinicalSignalLifecycleService(history);
  });

  tearDown(() => database.close());

  test('records added, changed, unchanged, then resolved', () async {
    final added = await lifecycle.reconcile(
      currentSignals: [_signal()],
      analysisComplete: true,
      ruleVersion: 'interaction-1',
      catalogVersion: 'catalog-1',
      observedAt: now,
    );
    expect(added.added, 1);

    final unchanged = await lifecycle.reconcile(
      currentSignals: [_signal()],
      analysisComplete: true,
      ruleVersion: 'interaction-1',
      catalogVersion: 'catalog-1',
      observedAt: now.add(const Duration(minutes: 1)),
    );
    expect(unchanged.unchanged, 1);

    final changed = await lifecycle.reconcile(
      currentSignals: [_signal(mechanism: 'Updated reviewed wording.')],
      analysisComplete: true,
      ruleVersion: 'interaction-1',
      catalogVersion: 'catalog-1',
      observedAt: now.add(const Duration(minutes: 2)),
    );
    expect(changed.changed, 1);

    final resolved = await lifecycle.reconcile(
      currentSignals: const [],
      analysisComplete: true,
      ruleVersion: 'interaction-1',
      catalogVersion: 'catalog-1',
      observedAt: now.add(const Duration(minutes: 3)),
    );
    expect(resolved.resolved, 1);

    final events = await history.getTimeline();
    expect(events.map((event) => event.eventType).toSet(), {
      HealthEventTypes.clinicalSignalAdded,
      HealthEventTypes.clinicalSignalChanged,
      HealthEventTypes.clinicalSignalResolved,
    });
  });

  test('incomplete analysis never resolves an existing signal', () async {
    await lifecycle.reconcile(
      currentSignals: [_signal()],
      analysisComplete: true,
      observedAt: now,
    );

    final diff = await lifecycle.reconcile(
      currentSignals: const [],
      analysisComplete: false,
      observedAt: now.add(const Duration(minutes: 1)),
    );

    expect(diff.resolved, 0);
    expect(diff.resolutionDeferred, isTrue);
    final latest = await history.getLatestClinicalSignalLifecycleEvents();
    expect(latest.values.single.state, HealthEventState.occurred.name);
  });

  test('resolution records an explicit version-change reason', () async {
    await lifecycle.reconcile(
      currentSignals: [_signal()],
      analysisComplete: true,
      ruleVersion: 'interaction-1',
      catalogVersion: 'catalog-1',
      observedAt: now,
    );
    await lifecycle.reconcile(
      currentSignals: const [],
      analysisComplete: true,
      ruleVersion: 'interaction-2',
      catalogVersion: 'catalog-1',
      observedAt: now.add(const Duration(minutes: 1)),
    );

    final resolved = (await history.getTimeline()).first;
    final metadata = jsonDecode(resolved.metadataJson!) as Map<String, dynamic>;
    expect(metadata['resolution_reason'], 'catalog_or_rule_version_changed');
  });

  test(
    'viewed and acknowledged state is idempotent and non-lifecycle',
    () async {
      final signalId = _signal().signalId;
      await lifecycle.markViewed(signalId, at: now);
      await lifecycle.markViewed(signalId, at: now);
      await lifecycle.acknowledge(signalId, at: now);

      final events = await history.getTimeline();
      expect(events, hasLength(2));
      expect(await history.getLatestClinicalSignalLifecycleEvents(), isEmpty);
    },
  );
}
