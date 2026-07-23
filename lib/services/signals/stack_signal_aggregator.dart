// Typed aggregation of a StackSafetyReport into ClinicalSignals (Workstream A,
// increment 3). This is the typed replacement for
// StackSafetyReport.orderedWarnings (List<Object>): the SAME six buckets, in the
// same bucket priority, adapted into ClinicalSignal.
//
// One deliberate difference from orderedWarnings: ranking is on
// clinical_severity (= effectiveSeverity for interactions), which corrects the
// seam where a food advisory was ranked by its INFORMATIONAL display severity
// instead of its true weight. Membership is otherwise identical — depletions are
// NOT folded in here (that is a separate, deliberate behavior change).
//
// Lives in the signals layer and CONSUMES StackSafetyReport (one direction) so
// there is no circular import with the envelope, which depends on the report for
// severityForNutrient. The UI consumers still read orderedWarnings today; they
// migrate onto this in the next slice, after which orderedWarnings is removed.

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

  // Rank on clinical_severity (effectiveSeverity for interactions), then bucket
  // priority, then stable source order. This is the ONE intentional difference
  // from orderedWarnings, which ranked on display severity.
  entries.sort((a, b) {
    final s = b.signal.clinicalSeverity.weight
        .compareTo(a.signal.clinicalSeverity.weight);
    if (s != 0) return s;
    final bk = a.bucket.compareTo(b.bucket);
    if (bk != 0) return bk;
    return a.ordinal.compareTo(b.ordinal);
  });

  return entries.map((e) => e.signal).toList(growable: false);
}
