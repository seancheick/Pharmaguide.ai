// Typed aggregation of a StackSafetyReport into ClinicalSignals (Workstream A,
// increment 3). This is the typed replacement for
// StackSafetyReport.orderedWarnings (List<Object>): the SAME six buckets, in the
// same bucket priority, adapted into ClinicalSignal.
//
// Deliberate differences from orderedWarnings (both intentional behavior
// changes, separately tested): (1) ranking is by consumer_disposition FIRST,
// then clinical severity — so a good_to_know food advisory / medication–nutrient
// monitor never displaces a review concern, even when its underlying severity is
// higher; (2) suppress-disposition signals are excluded. Membership is otherwise
// identical — depletions are NOT folded in here (a separate behavior change).
//
// Lives in the signals layer and CONSUMES StackSafetyReport (one direction) so
// there is no circular import with the envelope, which depends on the report for
// severityForNutrient. All stack-safety UI consumers now read this; the legacy
// orderedWarnings / List<Object> path has been removed.

import 'package:pharmaguide/core/models/interaction_result.dart';
import 'package:pharmaguide/services/signals/clinical_signal_envelope.dart';
import 'package:pharmaguide/services/stack/stack_safety_report.dart';

List<ClinicalSignal> orderedSignalsFrom(StackSafetyReport report) {
  final entries = <({ClinicalSignal signal, int bucket, int ordinal})>[];

  void addInteractions(List<InteractionResult> rs, int bucket) {
    for (var i = 0; i < rs.length; i++) {
      entries.add((
        signal: ClinicalSignal.fromInteraction(rs[i]),
        bucket: bucket,
        ordinal: i,
      ));
    }
  }

  // Same bucket priority as StackSafetyReport.orderedWarnings.
  addInteractions(report.medicationPairInteractions, 0);
  for (var i = 0; i < report.medicationProfileWarnings.length; i++) {
    entries.add((
      signal: ClinicalSignal.fromMedicationProfile(
        report.medicationProfileWarnings[i],
      ),
      bucket: 1,
      ordinal: i,
    ));
  }
  addInteractions(report.medicationInteractions, 2);
  addInteractions(report.stackInteractions, 3);
  addInteractions(report.categoryWarnings, 4);

  // Only warn-worthy nutrients surface (matches orderedWarnings' _flaggedNutrients).
  final flagged = report.nutrientStatuses.where((n) => n.shouldWarn).toList();
  for (var i = 0; i < flagged.length; i++) {
    entries.add((
      signal: ClinicalSignal.fromNutrientStatus(flagged[i]),
      bucket: 5,
      ordinal: i,
    ));
  }

  // Suppressed signals do not surface.
  entries.removeWhere(
    (e) => e.signal.consumerDisposition == ConsumerDisposition.suppress,
  );

  // Rank by consumer disposition FIRST (block > review > good_to_know), then by
  // clinical severity within a disposition, then bucket priority, then stable
  // source order. Disposition-first keeps a good_to_know food advisory /
  // medication–nutrient monitor from displacing a genuine review concern even
  // when its underlying clinical severity is higher.
  entries.sort((a, b) {
    final d = b.signal.consumerDisposition.rank.compareTo(
      a.signal.consumerDisposition.rank,
    );
    if (d != 0) return d;
    final s = b.signal.clinicalSeverity.weight.compareTo(
      a.signal.clinicalSeverity.weight,
    );
    if (s != 0) return s;
    final bk = a.bucket.compareTo(b.bucket);
    if (bk != 0) return bk;
    return a.ordinal.compareTo(b.ordinal);
  });

  return entries.map((e) => e.signal).toList(growable: false);
}
