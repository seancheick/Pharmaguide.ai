// Stack Safety Report — the single object the safety UI renders from.
//
// Aggregates every safety signal the stack engine produces (M1 nutrient
// totals + M4 curated interaction lookups + the legacy heuristic
// category checks) into one immutable struct with the computed views
// the banners and detail screens need:
//
//   - overallSeverity: the worst severity any single signal reports.
//                       Drives the top-level banner color.
//   - severityCounts:   how many signals fall in each severity bucket.
//                       Drives the small badge ("3 cautions, 1 avoid").
//   - orderedWarnings:  every flagged item ordered most-severe-first
//                       so the UI can render them as a list without
//                       re-sorting.
//
// The class is intentionally pure: no I/O, no Riverpod hooks, no
// mutation after construction. Build it once per stack-update and pass
// it down the widget tree.
//
// Spec §8.3.

import 'package:flutter/foundation.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/interaction_result.dart';
import 'package:pharmaguide/core/models/timing_optimization.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';

@immutable
class StackSafetyReport {
  const StackSafetyReport({
    this.nutrientStatuses = const <NutrientStatus>[],
    this.stackInteractions = const <InteractionResult>[],
    this.medicationInteractions = const <InteractionResult>[],
    this.medicationPairInteractions = const <InteractionResult>[],
    this.categoryWarnings = const <InteractionResult>[],
    this.timingOptimizations = const <TimingOptimization>[],
    this.coverageIncomplete = false,
    this.checksIncomplete = false,
  });

  /// True when at least one product in the stack has a label mapping
  /// coverage below the 0.3 trust floor — its ingredients may not have
  /// fired the interaction checks. The banner must hedge ("results may
  /// be incomplete") instead of rendering a success tone.
  final bool coverageIncomplete;

  /// True when one or more safety subsystems failed while building the report.
  /// The UI must hedge instead of rendering an all-clear, because an empty
  /// warning list may mean "not checked" rather than "no warnings found".
  final bool checksIncomplete;

  /// M1 per-nutrient classifications. Only those with `shouldWarn` are
  /// counted toward [overallSeverity] and surfaced in [orderedWarnings];
  /// the rest are kept here so the detail screen can render the full
  /// nutrient table.
  final List<NutrientStatus> nutrientStatuses;

  /// M4 curated supplement-pair interactions
  /// (`StackInteractionChecker.checkSupplementPairInteractions`).
  final List<InteractionResult> stackInteractions;

  /// M4 curated medication interactions
  /// (`StackInteractionChecker.checkMedicationInteractions`). Always
  /// PHI-bound — must never be persisted outside the device.
  final List<InteractionResult> medicationInteractions;

  /// M4 §0.2 medication-pair interactions
  /// (`StackInteractionChecker.checkMedicationPairInteractions`).
  /// Drug × drug pairs from the curated interaction DB. PHI-bound.
  final List<InteractionResult> medicationPairInteractions;

  /// Heuristic category warnings from the legacy
  /// `StackInteractionChecker.checkSafety` path (stim/sed antagonism,
  /// blood-thinner stacking, duplicate active ingredients).
  final List<InteractionResult> categoryWarnings;

  /// Timing optimization advice for the user's stack. Produced by
  /// [TimingEvaluationService] when two items match a timing rule.
  /// These are positive guidance ("take iron and calcium 2h apart"),
  /// not safety warnings — they don't count toward [overallSeverity]
  /// but are surfaced in a dedicated "Optimize Your Timing" section.
  final List<TimingOptimization> timingOptimizations;

  /// True when nothing fired — useful for "all clear" empty states.
  bool get isEmpty =>
      _flaggedNutrients.isEmpty &&
      stackInteractions.isEmpty &&
      medicationInteractions.isEmpty &&
      medicationPairInteractions.isEmpty &&
      categoryWarnings.isEmpty;

  /// True when timing advice is available.
  bool get hasTimingAdvice => timingOptimizations.isNotEmpty;

  /// Number of timing separation rules that fired (most actionable).
  int get separationCount =>
      timingOptimizations.where((t) => t.isSeparation).length;

  /// Highest severity across every flagged signal. [Severity.safe] when
  /// nothing fired (the report is clean).
  Severity get overallSeverity {
    Severity worst = Severity.safe;
    for (final r in _allInteractions) {
      if (r.severity.weight > worst.weight) worst = r.severity;
    }
    for (final n in _flaggedNutrients) {
      final ns = _severityForNutrient(n);
      if (ns.weight > worst.weight) worst = ns;
    }
    return worst;
  }

  /// Count of signals in each severity bucket. Useful for compact
  /// summary chips ("2 caution, 1 avoid"). Buckets with zero signals
  /// are still present so callers can iterate the enum without
  /// branching.
  Map<Severity, int> get severityCounts {
    final counts = <Severity, int>{for (final s in Severity.values) s: 0};
    for (final r in _allInteractions) {
      counts[r.severity] = (counts[r.severity] ?? 0) + 1;
    }
    for (final n in _flaggedNutrients) {
      final s = _severityForNutrient(n);
      counts[s] = (counts[s] ?? 0) + 1;
    }
    return counts;
  }

  /// Every flagged signal ordered most-severe-first. The list mixes
  /// [InteractionResult] and [NutrientStatus] entries — the UI is
  /// expected to runtime-switch on type when rendering.
  ///
  /// Within the same severity tier the order is:
  ///   1. medication-pair interactions (highest stakes — drug-drug)
  ///   2. medication interactions (drug-supp)
  ///   3. stack supplement-pair interactions
  ///   4. category heuristics
  ///   5. nutrient UL warnings
  ///
  /// Inside each bucket the relative order from the source list is
  /// preserved so callers passing pre-sorted inputs see deterministic
  /// output.
  List<Object> get orderedWarnings {
    final entries = <_RankedEntry>[];

    void addInteractions(List<InteractionResult> rs, int bucket) {
      for (var i = 0; i < rs.length; i++) {
        entries.add(
          _RankedEntry(
            severity: rs[i].severity,
            bucket: bucket,
            ordinal: i,
            payload: rs[i],
          ),
        );
      }
    }

    addInteractions(medicationPairInteractions, 0);
    addInteractions(medicationInteractions, 1);
    addInteractions(stackInteractions, 2);
    addInteractions(categoryWarnings, 3);

    final flagged = _flaggedNutrients;
    for (var i = 0; i < flagged.length; i++) {
      entries.add(
        _RankedEntry(
          severity: _severityForNutrient(flagged[i]),
          bucket: 4,
          ordinal: i,
          payload: flagged[i],
        ),
      );
    }

    entries.sort((a, b) {
      final s = b.severity.weight.compareTo(a.severity.weight);
      if (s != 0) return s;
      final bk = a.bucket.compareTo(b.bucket);
      if (bk != 0) return bk;
      return a.ordinal.compareTo(b.ordinal);
    });

    return entries.map((e) => e.payload).toList(growable: false);
  }

  // ---------------------------------------------------------------------------
  // internals
  // ---------------------------------------------------------------------------

  Iterable<InteractionResult> get _allInteractions sync* {
    yield* medicationPairInteractions;
    yield* medicationInteractions;
    yield* stackInteractions;
    yield* categoryWarnings;
  }

  List<NutrientStatus> get _flaggedNutrients =>
      nutrientStatuses.where((n) => n.shouldWarn).toList(growable: false);

  /// Map an M1 nutrient tier to a [Severity] for cross-signal ranking.
  ///
  /// We deliberately stop at [Severity.avoid] for `exceedsUl` — a UL
  /// violation is serious but not "do not use" until clinical review.
  /// The product detail screen can still show the full numeric overage
  /// for users who care about specifics.
  static Severity _severityForNutrient(NutrientStatus n) {
    switch (n.tier) {
      case NutrientTier.exceedsUl:
        return Severity.avoid;
      case NutrientTier.approachingUl:
        return Severity.caution;
      case NutrientTier.noRda:
      case NutrientTier.underFifty:
      case NutrientTier.adequate:
      case NutrientTier.abundant:
      case NutrientTier.aboveTypical:
        return Severity.safe;
    }
  }
}

class _RankedEntry {
  const _RankedEntry({
    required this.severity,
    required this.bucket,
    required this.ordinal,
    required this.payload,
  });

  final Severity severity;
  final int bucket;
  final int ordinal;
  final Object payload;
}
