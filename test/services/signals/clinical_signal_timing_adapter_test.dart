// Contract for ClinicalSignal.fromTimingSeparation.
//
// The adapter lands BEFORE the rule audit on purpose: the audit authors 31
// rules against a target shape, and if the adapter only appeared afterward, a
// shape mismatch would mean re-auditing rules that were already verified. This
// file is that shape, executable.
//
// It deliberately does NOT render anything. The aggregator is not wired until
// the unified Clinical Guidance work, and the last group here asserts that, so
// the "unreachable" cases added to the six payload switches cannot quietly
// become live.

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/timing_optimization.dart';
import 'package:pharmaguide/services/signals/clinical_signal_envelope.dart';
import 'package:pharmaguide/services/signals/stack_signal_aggregator.dart';
import 'package:pharmaguide/services/stack/stack_safety_report.dart';

TimingOptimization _optimization({
  String ruleId = 'timing_calcium_iron_thyroid_separate',
  TimingCategory category = TimingCategory.importantSeparation,
  TimingActionability actionability = TimingActionability.recommended,
  EvidenceLevel evidenceLevel = EvidenceLevel.established,
  SourceAuthority sourceAuthority = SourceAuthority.fdaLabel,
  String ingredient1 = 'levothyroxine',
  String? ingredient2 = 'calcium',
  String? product1Name = 'Levothyroxine',
  String? product1StackEntryId = 'row-levo',
  String? product2Name = 'Calcium K/D',
  String? product2StackEntryId = 'row-calcium',
  bool involvesMedication = true,
  bool medicationIsProduct1 = true,
  List<String> sourceUrls = const ['https://dailymed.nlm.nih.gov/x'],
}) {
  return TimingOptimization(
    ruleId: ruleId,
    ingredient1: ingredient1,
    ingredient2: ingredient2,
    advice: 'Keep calcium at least 4 hours away from levothyroxine.',
    relation: const TimingRelation(
      type: TimingRelationType.separateFrom,
      minimumHours: 4,
    ),
    category: category,
    actionability: actionability,
    evidenceLevel: evidenceLevel,
    sourceAuthority: sourceAuthority,
    scoreImpact: -2,
    sourceUrls: sourceUrls,
    product1Name: product1Name,
    product1StackEntryId: product1StackEntryId,
    product2Name: product2Name,
    product2StackEntryId: product2StackEntryId,
    involvesMedication: involvesMedication,
    medicationIsProduct1: medicationIsProduct1,
  );
}

void main() {
  group('the mapping is total and lossless for what a signal needs', () {
    test('an important separation produces a signal', () {
      final signal = ClinicalSignal.fromTimingSeparation(_optimization());

      expect(signal, isNotNull);
      expect(signal!.family, SignalFamily.timingSeparation);
      expect(signal.sourceRuleId, 'timing_calcium_iron_thyroid_separate');
      expect(signal.copyId, 'timing_calcium_iron_thyroid_separate');
      expect(signal.evaluationStatus, EvaluationStatus.applicable);
      expect(
        signal.body,
        'Keep calcium at least 4 hours away from levothyroxine.',
        reason: 'the adapter never rewrites reviewed advice',
      );
      expect(signal.sourceUrls, ['https://dailymed.nlm.nih.gov/x']);
    });

    test('both bottles survive as subjects, sorted for stable identity', () {
      final signal = ClinicalSignal.fromTimingSeparation(_optimization())!;
      expect(signal.subjectIds, hasLength(2));
      expect(signal.subjectIds, equals([...signal.subjectIds]..sort()));
    });

    test('the anchor row is the supplement, never the prescription', () {
      final signal = ClinicalSignal.fromTimingSeparation(_optimization())!;
      final payload = signal.payload as TimingSeparationPayload;
      expect(
        payload.anchorStackEntryId,
        'row-calcium',
        reason:
            'the app constrains the supplement around the prescription, never '
            'the other way round',
      );
    });

    test('a supplement-only separation anchors on product one', () {
      final signal = ClinicalSignal.fromTimingSeparation(
        _optimization(
          ruleId: 'timing_iron_calcium_separate',
          ingredient1: 'iron',
          product1Name: 'Gentle Iron',
          product1StackEntryId: 'row-iron',
          involvesMedication: false,
          medicationIsProduct1: false,
        ),
      )!;
      final payload = signal.payload as TimingSeparationPayload;
      expect(payload.anchorStackEntryId, 'row-iron');
    });

    test('the full optimization is preserved in the payload', () {
      final optimization = _optimization();
      final signal = ClinicalSignal.fromTimingSeparation(optimization)!;
      final payload = signal.payload as TimingSeparationPayload;

      // Evidence, authority and actionability stay independent and intact —
      // nothing is flattened into clinicalSeverity on the way through.
      expect(payload.optimization.evidenceLevel, EvidenceLevel.established);
      expect(payload.optimization.sourceAuthority, SourceAuthority.fdaLabel);
      expect(
        payload.optimization.actionability,
        TimingActionability.recommended,
      );
      expect(payload.optimization.relation.minimumHours, 4);
    });

    test('the signal id is deterministic across identical inputs', () {
      final a = ClinicalSignal.fromTimingSeparation(_optimization())!;
      final b = ClinicalSignal.fromTimingSeparation(_optimization())!;
      expect(a.signalId, b.signalId);
      expect(a.signalIdCanonical, contains('timingSeparation'));
    });
  });

  group('severity is capped and never inflated', () {
    test('a medication separation is caution, not avoid', () {
      final signal = ClinicalSignal.fromTimingSeparation(_optimization())!;
      expect(signal.clinicalSeverity, Severity.caution);
      expect(signal.consumerDisposition, ConsumerDisposition.review);
    });

    test('a supplement-only separation ranks below a medication one', () {
      final medication = ClinicalSignal.fromTimingSeparation(_optimization())!;
      final supplement = ClinicalSignal.fromTimingSeparation(
        _optimization(involvesMedication: false, medicationIsProduct1: false),
      )!;
      expect(supplement.clinicalSeverity, Severity.monitor);
      expect(
        medication.clinicalSeverity.index,
        lessThan(supplement.clinicalSeverity.index),
        reason: 'severity order is contraindicated > avoid > caution > monitor',
      );
    });

    test('strong evidence never pushes a timing signal above caution', () {
      for (final level in EvidenceLevel.values) {
        final signal = ClinicalSignal.fromTimingSeparation(
          _optimization(evidenceLevel: level),
        )!;
        expect(
          signal.clinicalSeverity,
          anyOf(Severity.caution, Severity.monitor),
          reason:
              'a spacing instruction is manageable by the user; it must never '
              'carry the weight of an avoid or contraindicated interaction',
        );
      }
    });
  });

  group('only a verified important separation can become a signal', () {
    test('how-to-take and optional categories produce nothing', () {
      for (final category in [
        TimingCategory.howToTake,
        TimingCategory.optional,
      ]) {
        expect(
          ClinicalSignal.fromTimingSeparation(_optimization(category: category)),
          isNull,
          reason: '$category is guidance, not a safety signal',
        );
      }
    });

    test('the gate is the category, not the relation type', () {
      // A rule whose relation looks severe but which has not been through
      // category assignment must not reach a more prominent surface.
      const unreviewed = TimingOptimization(
        ruleId: 'timing_unreviewed',
        ingredient1: 'iron',
        ingredient2: 'calcium',
        advice: 'x',
        relation: TimingRelation(
          type: TimingRelationType.separateFrom,
          minimumHours: 4,
        ),
        category: TimingCategory.howToTake,
        actionability: TimingActionability.recommended,
        evidenceLevel: EvidenceLevel.established,
        sourceAuthority: SourceAuthority.fdaLabel,
        scoreImpact: -2,
        product1Name: 'Iron',
        product1StackEntryId: 'row-iron',
      );
      expect(ClinicalSignal.fromTimingSeparation(unreviewed), isNull);
    });
  });

  group('the adapter is not wired yet', () {
    test('the aggregator emits no timing signals', () {
      final report = StackSafetyReport(
        timingOptimizations: [_optimization()],
      );
      final signals = allClinicalSignalsFrom(report: report);
      expect(
        signals.where((s) => s.family == SignalFamily.timingSeparation),
        isEmpty,
        reason:
            'wiring happens in the unified Clinical Guidance work, only after '
            'the rule audit. Until then the payload cases added to the six '
            'switches are genuinely unreachable — this test is what keeps that '
            'true.',
      );
    });
  });
}
