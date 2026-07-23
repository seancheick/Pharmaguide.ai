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
//   (Ordering for rendering now lives in the signals layer —
//    orderedSignalsFrom() builds the typed ClinicalSignal collection.)
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
import 'package:pharmaguide/services/stack/medication_profile_gate_evaluator.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';

@immutable
class StackSafetyReport {
  const StackSafetyReport({
    this.nutrientStatuses = const <NutrientStatus>[],
    this.stackInteractions = const <InteractionResult>[],
    this.medicationInteractions = const <InteractionResult>[],
    this.medicationPairInteractions = const <InteractionResult>[],
    this.medicationProfileWarnings = const <MedicationProfileWarning>[],
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
  /// counted toward [overallSeverity]; the rest are kept here so the
  /// detail screen can render the full
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

  /// Profile-specific medication warnings evaluated through the shared
  /// profile_gate engine (for example, pregnant profile × NSAID medication).
  /// These are PHI-bound and local-only.
  final List<MedicationProfileWarning> medicationProfileWarnings;

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
      medicationProfileWarnings.isEmpty &&
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
      // effectiveSeverity: a food advisory keeps an informational DISPLAY tone
      // but must be WEIGHTED by its real curated severity (grapefruit x statin
      // = avoid), so it isn't silently ignored in the banner color.
      if (r.effectiveSeverity.weight > worst.weight) {
        worst = r.effectiveSeverity;
      }
    }
    for (final w in medicationProfileWarnings) {
      if (w.severity.weight > worst.weight) worst = w.severity;
    }
    for (final n in _flaggedNutrients) {
      final ns = severityForNutrient(n);
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
      // Weight by effectiveSeverity (see overallSeverity) so a serious food
      // advisory buckets under its real severity, not informational.
      counts[r.effectiveSeverity] = (counts[r.effectiveSeverity] ?? 0) + 1;
    }
    for (final w in medicationProfileWarnings) {
      counts[w.severity] = (counts[w.severity] ?? 0) + 1;
    }
    for (final n in _flaggedNutrients) {
      final s = severityForNutrient(n);
      counts[s] = (counts[s] ?? 0) + 1;
    }
    return counts;
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
  /// A modest overage needs an explicit upper-limit alert, but is not an
  /// interaction-style "Not recommended" event. At twice the UL, retain the
  /// stronger tier so high-magnitude breaches stay prominent.
  static Severity severityForNutrient(NutrientStatus n) {
    switch (n.tier) {
      case NutrientTier.exceedsUl:
        // A legacy/partial status without a percentage cannot be safely
        // down-ranked. Fresh statuses always carry pctOfUl.
        return n.pctOfUl != null && n.pctOfUl! < 200
            ? Severity.caution
            : Severity.avoid;
      case NutrientTier.approachingUl:
        return Severity.caution;
      case NutrientTier.noRda:
      case NutrientTier.underFifty:
      case NutrientTier.adequate:
      case NutrientTier.aboveAdequateNoUl:
      case NutrientTier.abundant:
      case NutrientTier.aboveTypical:
        return Severity.safe;
    }
  }

  /// Factual copy for an upper-limit event. Stack totals represent the
  /// labeled daily supplement amount, never the person's full dietary intake.
  static String nutrientUpperLimitSummary(NutrientStatus status) {
    final total = status.total;
    final amount = _formatAmount(total.totalAmount);
    final unit = total.unit;
    final ul = status.ul == null ? null : _formatAmount(status.ul!);
    final pct = status.pctOfUl?.round().toString();
    final limit = switch ((pct, ul)) {
      (final String pct, final String ul) =>
        '$pct% of the $ul $unit upper limit',
      (_, final String ul) => 'above the $ul $unit upper limit',
      _ => 'above its upper limit',
    };
    final contributors = total.contributions
        .map(
          (contribution) =>
              '${contribution.productName} (${_formatAmount(contribution.amount)} '
              '${contribution.unit}/day)',
        )
        .join(', ');
    final source = contributors.isEmpty ? '' : ' From $contributors.';
    final basis = status.ulIsFallback
        ? ' This uses a standard adult upper limit because a matched profile limit is unavailable.'
        : ' This uses the upper limit for your profile.';
    return 'Your supplements provide $amount $unit/day of ${total.displayName} '
        '- $limit.$source Dietary intake is not included here.$basis';
  }

  static String _formatAmount(double amount) {
    if (amount == amount.roundToDouble()) return amount.toStringAsFixed(0);
    return amount.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
  }
}
