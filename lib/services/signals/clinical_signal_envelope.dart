// Unified clinical-signal envelope (Workstream A, increment 2).
//
// One shape that all four heterogeneous producers map into, so lifecycle,
// ranking, and rendering work uniformly — WITHOUT flattening clinical domains
// together (each keeps its typed payload). This does NOT yet replace the
// List<Object> aggregation in StackSafetyReport (increment 3).
//
// Two axes are deliberately separate (PM directive):
//   - clinicalSeverity  → drives SAFETY RANKING only.
//   - consumerDisposition → drives PLACEMENT only.
// A medication–nutrient relationship must never be made to look like an avoid /
// contraindicated interaction, so its severity is capped and its raw importance
// is preserved in the payload for a future authored disposition to upgrade.

import 'package:flutter/foundation.dart';

import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/clinical_signal.dart';
import 'package:pharmaguide/core/models/interaction_result.dart';
import 'package:pharmaguide/core/models/timing_optimization.dart';
import 'package:pharmaguide/services/stack/depletion_checker.dart';
import 'package:pharmaguide/services/stack/medication_profile_gate_evaluator.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';
import 'package:pharmaguide/services/stack/stack_safety_report.dart';

export 'package:pharmaguide/core/models/clinical_signal.dart';

/// How a signal should be PLACED for the consumer — separate from
/// [ClinicalSignal.clinicalSeverity], which drives safety ranking. Authored
/// dispositions (Workstream B) will override these adapter fallbacks.
enum ConsumerDisposition { block, review, goodToKnow, suppress }

extension ConsumerDispositionRank on ConsumerDisposition {
  /// Higher = more prominent. Primary selection ranks by this BEFORE clinical
  /// severity, so a good_to_know food advisory never displaces a review concern,
  /// and a medication–nutrient monitor never overrides an interaction caution.
  int get rank => switch (this) {
    ConsumerDisposition.block => 3,
    ConsumerDisposition.review => 2,
    ConsumerDisposition.goodToKnow => 1,
    ConsumerDisposition.suppress => 0,
  };
}

/// Whether / how the underlying rule was actually evaluated. Lets the lifecycle
/// layer represent "the check could not complete" ([checkFailed]) separately
/// from "checked, no concern". Adapters over a producer result always emit
/// [applicable]; [checkFailed] is set by the aggregation layer (increment 3).
enum EvaluationStatus {
  applicable,
  aboveThreshold,
  belowThreshold,
  amountUnknown,
  formUnknown,
  checkFailed,
  notApplicable,
}

/// Typed domain detail — never flattened into the envelope's common fields.
/// Sealed so consumers switch exhaustively.
sealed class SignalPayload {
  const SignalPayload();
}

final class InteractionPayload extends SignalPayload {
  final InteractionResult result;
  const InteractionPayload(this.result);
}

final class TimingSeparationPayload extends SignalPayload {
  final TimingOptimization optimization;

  /// The stack row the guidance attaches to — always the supplement when a
  /// medication is involved, because the app constrains the supplement around
  /// the prescription and never the other way round.
  final String? anchorStackEntryId;

  const TimingSeparationPayload(this.optimization, {this.anchorStackEntryId});
}

final class MedicationProfilePayload extends SignalPayload {
  final MedicationProfileWarning warning;
  const MedicationProfilePayload(this.warning);
}

final class MedicationNutrientPayload extends SignalPayload {
  final DepletionMatch match;

  /// Raw source importance (critical / significant / moderate / mild) —
  /// PRESERVED, not flattened into clinicalSeverity. A future authored
  /// consumer_disposition can upgrade individual relationships; until then all
  /// map to monitor + good_to_know.
  final String relationshipImportance;

  /// The relationship kind (depletion / functional_antagonism / …).
  final String relationshipType;

  const MedicationNutrientPayload(
    this.match, {
    required this.relationshipImportance,
    required this.relationshipType,
  });
}

final class CumulativeExposurePayload extends SignalPayload {
  final NutrientStatus status;
  const CumulativeExposurePayload(this.status);
}

@immutable
class ClinicalSignal {
  final String signalId; // sha256 of [signalIdCanonical]
  final String signalIdCanonical; // debug-readable pg_signal:v1:...
  final SignalFamily family;
  final String? sourceRuleId; // permanent rule identity (null for cumulative)
  final List<String> subjectIds; // normalized, sorted
  final Severity clinicalSeverity; // RANKING only
  final ConsumerDisposition consumerDisposition; // PLACEMENT only
  final EvaluationStatus evaluationStatus;
  final String title;
  final String body;
  final String copyId; // stable identity for the authored copy
  final List<String> sourceUrls;
  final String? ruleVersion; // populated when the producer carries it
  final String? catalogVersion;
  final SignalPayload payload;

  const ClinicalSignal({
    required this.signalId,
    required this.signalIdCanonical,
    required this.family,
    required this.sourceRuleId,
    required this.subjectIds,
    required this.clinicalSeverity,
    required this.consumerDisposition,
    required this.evaluationStatus,
    required this.title,
    required this.body,
    required this.copyId,
    required this.payload,
    this.sourceUrls = const [],
    this.ruleVersion,
    this.catalogVersion,
  });

  // --- Adapters ---

  factory ClinicalSignal.fromInteraction(InteractionResult r) {
    // Heuristic ids carry a stack-position index (STACK_BT_3); strip it so the
    // same pair collapses to one stable rule identity. Curated ids are opaque
    // and must NOT be stripped.
    final ruleId = r.source == InteractionSource.stackEngine
        ? r.id.replaceFirst(RegExp(r'_\d+$'), '')
        : r.id;
    final subjects = [r.agent1Name, r.agent2Name];
    // Rank on the TRUE severity, undoing the food-advisory display downgrade.
    final severity = r.effectiveSeverity;
    return ClinicalSignal(
      signalId: deriveSignalId(
        family: SignalFamily.pairwiseInteraction,
        sourceRuleId: ruleId,
        subjectIds: subjects,
      ),
      signalIdCanonical: canonicalSignalId(
        family: SignalFamily.pairwiseInteraction,
        sourceRuleId: ruleId,
        subjectIds: subjects,
      ),
      family: SignalFamily.pairwiseInteraction,
      sourceRuleId: ruleId,
      subjectIds: _sortedSubjects(subjects),
      clinicalSeverity: severity,
      // A food advisory keeps its true severity (for the record and for ordering
      // within good_to_know) but is PLACED as good_to_know: the app can't confirm
      // the food exposure, so it must never become the primary safety headline.
      consumerDisposition: r.isFoodAdvisoryNote
          ? ConsumerDisposition.goodToKnow
          : _dispositionForSeverity(severity),
      evaluationStatus: EvaluationStatus.applicable,
      title: '${r.agent1Name} × ${r.agent2Name}',
      body: r.mechanism,
      copyId: ruleId,
      sourceUrls: r.sourceUrls,
      payload: InteractionPayload(r),
    );
  }

  /// A verified `important_separation` timing rule, as a clinical signal.
  ///
  /// Returns null for anything else. The gate is deliberately
  /// (category == importantSeparation), NOT (relation is a separation): a rule
  /// that has not been through source verification and category assignment must
  /// not reach a more prominent surface just because its relation type looks
  /// severe. `TimingEvaluationService` already withholds unverified rules, so
  /// this is the second of two independent gates.
  ///
  /// Severity is CAPPED at caution, mirroring the medication–nutrient rule: a
  /// spacing instruction is manageable by the user and must never be presented
  /// with the weight of an avoid / contraindicated interaction.
  static ClinicalSignal? fromTimingSeparation(TimingOptimization o) {
    if (o.category != TimingCategory.importantSeparation) return null;

    final subjects = <String>[
      o.product1Name ?? o.ingredient1,
      ?(o.product2Name ?? o.ingredient2),
    ];
    final severity = o.involvesMedication ? Severity.caution : Severity.monitor;

    return ClinicalSignal(
      signalId: deriveSignalId(
        family: SignalFamily.timingSeparation,
        sourceRuleId: o.ruleId,
        subjectIds: subjects,
      ),
      signalIdCanonical: canonicalSignalId(
        family: SignalFamily.timingSeparation,
        sourceRuleId: o.ruleId,
        subjectIds: subjects,
      ),
      family: SignalFamily.timingSeparation,
      sourceRuleId: o.ruleId,
      subjectIds: _sortedSubjects(subjects),
      clinicalSeverity: severity,
      consumerDisposition: _dispositionForSeverity(severity),
      evaluationStatus: EvaluationStatus.applicable,
      title: subjects.length > 1
          ? '${subjects[0]} \u00d7 ${subjects[1]}'
          : subjects[0],
      body: o.advice,
      copyId: o.ruleId,
      sourceUrls: o.sourceUrls,
      payload: TimingSeparationPayload(
        o,
        anchorStackEntryId: o.involvesMedication && o.medicationIsProduct1
            ? o.product2StackEntryId
            : o.product1StackEntryId,
      ),
    );
  }

  factory ClinicalSignal.fromMedicationProfile(MedicationProfileWarning w) {
    final subjects = [w.medicationName];
    final severity = w.severity;
    return ClinicalSignal(
      signalId: deriveSignalId(
        family: SignalFamily.medicationProfile,
        sourceRuleId: w.ruleId,
        subjectIds: subjects,
      ),
      signalIdCanonical: canonicalSignalId(
        family: SignalFamily.medicationProfile,
        sourceRuleId: w.ruleId,
        subjectIds: subjects,
      ),
      family: SignalFamily.medicationProfile,
      sourceRuleId: w.ruleId,
      subjectIds: _sortedSubjects(subjects),
      clinicalSeverity: severity,
      consumerDisposition: _dispositionForSeverity(severity),
      evaluationStatus: EvaluationStatus.applicable,
      title: w.headline,
      body: w.body,
      copyId: w.ruleId,
      sourceUrls: w.sourceUrls,
      payload: MedicationProfilePayload(w),
    );
  }

  factory ClinicalSignal.fromDepletion(DepletionMatch m) {
    // Identity comes from the checker's stable, validated id — never a
    // synthesized drugClass+nutrient fallback (B1.1). The checker drops
    // empty/duplicate ids, so a non-empty id here is an invariant.
    assert(
      m.depletionId.isNotEmpty,
      'fromDepletion requires a non-empty depletionId (checker drops empty ids)',
    );
    final importance = m.severity.trim().toLowerCase();
    final ruleId = m.depletionId;
    final drugSubject = m.drugClassId.isNotEmpty
        ? m.drugClassId
        : m.drugDisplayName;
    final subjects = [drugSubject, m.nutrientCanonicalId];
    return ClinicalSignal(
      signalId: deriveSignalId(
        family: SignalFamily.medicationNutrient,
        sourceRuleId: ruleId,
        subjectIds: subjects,
      ),
      signalIdCanonical: canonicalSignalId(
        family: SignalFamily.medicationNutrient,
        sourceRuleId: ruleId,
        subjectIds: subjects,
      ),
      family: SignalFamily.medicationNutrient,
      sourceRuleId: ruleId,
      subjectIds: _sortedSubjects(subjects),
      // PM-locked v1 policy: a monitoring relationship never becomes an avoid /
      // contraindicated interaction. All importances → monitor + good_to_know;
      // the raw importance is preserved in the payload for a future authored
      // consumer_disposition to upgrade individual relationships.
      clinicalSeverity: Severity.monitor,
      consumerDisposition: ConsumerDisposition.goodToKnow,
      evaluationStatus: EvaluationStatus.applicable,
      title: '${m.drugDisplayName} → ${m.nutrientName}',
      body: m.clinicalImpact ?? m.mechanism,
      copyId: ruleId,
      sourceUrls: m.sourceUrls,
      payload: MedicationNutrientPayload(
        m,
        relationshipImportance: importance,
        relationshipType: m.depletionType,
      ),
    );
  }

  factory ClinicalSignal.fromNutrientStatus(NutrientStatus n) {
    final nutrientId = n.total.canonicalId;
    final severity = StackSafetyReport.severityForNutrient(n);
    return ClinicalSignal(
      signalId: deriveSignalId(
        family: SignalFamily.cumulativeExposure,
        nutrientId: nutrientId,
      ),
      signalIdCanonical: canonicalSignalId(
        family: SignalFamily.cumulativeExposure,
        nutrientId: nutrientId,
      ),
      family: SignalFamily.cumulativeExposure,
      sourceRuleId: null,
      subjectIds: [normalizeSignalSubject(nutrientId)],
      clinicalSeverity: severity,
      consumerDisposition: _dispositionForSeverity(severity),
      evaluationStatus: EvaluationStatus.applicable,
      title: n.total.displayName,
      body: n.warning ?? '',
      copyId: 'cumulative_exposure:$nutrientId',
      sourceUrls: const [],
      payload: CumulativeExposurePayload(n),
    );
  }
}

List<String> _sortedSubjects(List<String> xs) =>
    xs.map(normalizeSignalSubject).where((s) => s.isNotEmpty).toList()..sort();

/// Disposition fallback from ranking severity. Depletions and food advisories do
/// NOT use this (they are pinned to good_to_know). Authored dispositions
/// (Workstream B) override.
ConsumerDisposition _dispositionForSeverity(Severity s) => switch (s) {
  Severity.contraindicated => ConsumerDisposition.block,
  Severity.avoid ||
  Severity.caution ||
  Severity.monitor => ConsumerDisposition.review,
  Severity.informational => ConsumerDisposition.goodToKnow,
  Severity.safe => ConsumerDisposition.suppress,
};
