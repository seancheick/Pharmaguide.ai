// StackSafetyBanner — top-of-stack-screen banner summarizing every
// safety signal the M1 nutrient engine and the M4 curated interaction
// checker produce for the user's current stack.
//
// Input: a [StackSafetyReport] already built by the stack-scoring layer
// (spec §8.3). The banner is intentionally pure — no Riverpod hooks, no
// I/O, no async. Rows are driven from [orderedSignalsFrom] (the typed
// clinical-signal aggregation), so tone, title, and body all come from the
// SAME headline signal — the disposition-first top of the list.
//
// Visual behavior:
//   - no signals            → hidden (SizedBox.shrink) so an all-clear stack
//                              doesn't push the product list down — UNLESS a
//                              check/coverage flag is set, in which case we
//                              hedge instead of implying "all clear".
//   - headline = block/avoid → red danger banner.
//   - caution / monitor     → amber caution banner.
//   - a "+N more" suffix summarizes the remaining signals.
//
// Suppress-disposition signals (e.g. a safe interaction) are excluded upstream
// by orderedSignalsFrom, so a safe-only stack collapses to the hedge/hidden
// path rather than a success banner — never a false all-clear.

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/scoring/coverage.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/widgets/pg_severity_banner.dart';
import 'package:pharmaguide/services/signals/clinical_signal_envelope.dart';
import 'package:pharmaguide/services/signals/stack_signal_aggregator.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';
import 'package:pharmaguide/services/stack/stack_safety_report.dart';

class StackSafetyBanner extends StatelessWidget {
  const StackSafetyBanner({
    super.key,
    required this.report,
    this.onTap,
    this.margin = EdgeInsets.zero,
  });

  /// Safety report driving the banner. Build once per stack mutation
  /// and pass in — the widget is pure w.r.t. [report].
  final StackSafetyReport report;

  /// Optional tap handler. When supplied the banner shows a "View
  /// details" action that opens the caller's target (usually the
  /// stack-safety detail screen). Omit to render a non-interactive
  /// summary — useful on screens where the banner is purely an alert.
  final VoidCallback? onTap;

  /// Outer margin for the banner. Matches the [PGSeverityBanner]
  /// contract so the caller can match the surrounding layout without
  /// wrapping in another [Padding].
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final signals = orderedSignalsFrom(report);

    // No renderable signal. Never imply "all clear" when a check or coverage
    // gap means we may not have seen everything.
    if (signals.isEmpty) {
      if (report.checksIncomplete) return _checksIncompleteBanner();
      if (report.coverageIncomplete) return _coverageHedgeBanner();
      return const SizedBox.shrink();
    }

    final headline = signals.first;
    final worst = headline.clinicalSeverity;
    final tone = _toneFor(worst);

    // A success-toned summary is only honest when every label was analyzed and
    // every check finished. (In practice the headline is never `safe`, since
    // suppress signals are excluded — this guards odd upstream data.)
    if (report.coverageIncomplete && tone == PGBannerTone.success) {
      return _coverageHedgeBanner();
    }
    if (report.checksIncomplete && tone == PGBannerTone.success) {
      return _checksIncompleteBanner();
    }

    return PGSeverityBanner(
      key: const Key('stack-safety-banner'),
      tone: tone,
      title: _titleFor(headline, worst),
      body: _bodyWithCompleteness(
        _bodyFor(signals, headline),
        checksIncomplete: report.checksIncomplete,
        coverageIncomplete: report.coverageIncomplete,
      ),
      actionLabel: onTap == null ? null : 'View details',
      onAction: onTap,
      margin: margin,
    );
  }

  /// Keep a non-empty finding list honest when another subsystem or product
  /// could not be analyzed. Without this suffix, the banner labels only the
  /// known findings and incorrectly implies the list is exhaustive.
  static String? _bodyWithCompleteness(
    String? body, {
    required bool checksIncomplete,
    required bool coverageIncomplete,
  }) {
    if (!checksIncomplete && !coverageIncomplete) return body;
    const hedge =
        'Some checks or product labels could not be fully analyzed, so '
        'results may be incomplete.';
    final value = body?.trim() ?? '';
    return value.isEmpty ? hedge : '$value $hedge';
  }

  /// Caution-toned hedge rendered when at least one stack product has a
  /// label mapping coverage below the 0.3 trust floor. Copy is
  /// calm-advisory per the voice guide — no imperatives.
  Widget _coverageHedgeBanner() {
    return PGSeverityBanner(
      key: const Key('stack-safety-banner'),
      tone: PGBannerTone.caution,
      title: kCoverageHedgeBase,
      body:
          'One or more products in your stack have limited ingredient '
          'data — results may be incomplete.',
      actionLabel: onTap == null ? null : 'View details',
      onAction: onTap,
      margin: margin,
    );
  }

  Widget _checksIncompleteBanner() {
    return PGSeverityBanner(
      key: const Key('stack-safety-banner'),
      tone: PGBannerTone.caution,
      title: "Interactions couldn't be checked",
      body:
          'One or more stack safety checks could not finish — results may be '
          'incomplete.',
      actionLabel: onTap == null ? null : 'View details',
      onAction: onTap,
      margin: margin,
    );
  }

  // ---------------------------------------------------------------------------
  // presentation helpers
  // ---------------------------------------------------------------------------

  static PGBannerTone _toneFor(Severity s) {
    switch (s) {
      case Severity.contraindicated:
      case Severity.avoid:
        return PGBannerTone.danger;
      case Severity.caution:
      case Severity.monitor:
        return PGBannerTone.caution;
      case Severity.informational:
        return PGBannerTone.info;
      case Severity.safe:
        return PGBannerTone.success;
    }
  }

  /// Title is the headline signal rendered as a short one-liner, prefixed with
  /// the severity label so the user can scan by color + text in one glance
  /// ("Not recommended — Warfarin × Fish Oil"). Text comes from the typed
  /// payload, so it is identical to the pre-migration rendering.
  static String _titleFor(ClinicalSignal signal, Severity worst) {
    final prefix = worst.label;
    switch (signal.payload) {
      case InteractionPayload(:final result):
        if (result.isFoodAdvisoryNote) {
          return 'Food note — ${result.agent1Name} × ${result.agent2Name}';
        }
        return '$prefix — ${result.agent1Name} × ${result.agent2Name}';
      case MedicationProfilePayload(:final warning):
        return '$prefix — ${warning.medicationName}';
      case CumulativeExposurePayload(:final status):
        if (status.tier == NutrientTier.exceedsUl) {
          return 'Upper limit - ${status.total.displayName}';
        }
        return '$prefix — ${status.total.displayName}';
      case MedicationNutrientPayload(:final match):
        // Not in the banner's data source today (depletions come from a
        // separate provider); reserved for when they are folded in.
        return '$prefix — ${match.drugDisplayName}';
      case TimingSeparationPayload(:final optimization):
        // Timing separations are not wired into the aggregator until the unified Clinical Guidance work lands, so this cannot arrive yet. The adapter exists now on purpose: it is the shape the rule audit is written against. Asserted unreachable by clinical_signal_timing_adapter_test.dart.
        return '$prefix — ${optimization.product1Name ?? optimization.ingredient1}';
    }
  }

  /// Body describes the headline signal's management / mechanism and appends a
  /// "+N more" hint when the stack has additional signals.
  static String? _bodyFor(
    List<ClinicalSignal> signals,
    ClinicalSignal headline,
  ) {
    String? primary;
    switch (headline.payload) {
      case InteractionPayload(:final result):
        // Prefer management (what the user should do); fall back to the
        // mechanism summary if management is empty. Always append the evidence
        // level — safety rule: interaction warnings must show their tier.
        final base = result.management.trim().isNotEmpty
            ? result.management
            : result.mechanism;
        primary = base.trim().isEmpty
            ? result.evidenceLevel.label
            : '$base · ${result.evidenceLevel.label}';
      case MedicationProfilePayload(:final warning):
        final base = warning.body.trim().isNotEmpty
            ? warning.body
            : warning.management;
        primary = base.trim().isEmpty
            ? warning.evidenceLevel.label
            : '$base · ${warning.evidenceLevel.label}';
      case CumulativeExposurePayload(:final status):
        primary = _nutrientHint(status);
      case MedicationNutrientPayload(:final match):
        primary = match.clinicalImpact ?? match.mechanism;
      case TimingSeparationPayload(:final optimization):
        // Timing separations are not wired into the aggregator until the unified Clinical Guidance work lands, so this cannot arrive yet. The adapter exists now on purpose: it is the shape the rule audit is written against. Asserted unreachable by clinical_signal_timing_adapter_test.dart.
        primary = optimization.advice;
    }

    final extraCount = signals.length - 1;
    if (extraCount <= 0) return primary;

    final extraLabel = extraCount == 1
        ? '1 more signal'
        : '$extraCount more signals';
    if (primary.isEmpty) return extraLabel;
    return '$primary  ·  $extraLabel';
  }

  /// Short human-readable hint for a flagged nutrient status. Mirrors
  /// the wording used in the nutrient-accumulation panel so users see
  /// consistent language across the stack screen.
  static String _nutrientHint(NutrientStatus n) {
    final name = n.total.displayName;
    switch (n.tier) {
      case NutrientTier.exceedsUl:
        return StackSafetyReport.nutrientUpperLimitSummary(n);
      case NutrientTier.approachingUl:
        return '$name is near its upper limit across your stack.';
      case NutrientTier.aboveTypical:
      case NutrientTier.abundant:
      case NutrientTier.aboveAdequateNoUl:
      case NutrientTier.adequate:
      case NutrientTier.underFifty:
      case NutrientTier.noRda:
        return name;
    }
  }
}

/// Margin preset matching the v2 stack-screen card spacing. Expose it
/// as a const so stack wiring and tests can re-use the same gutter.
const EdgeInsets kStackSafetyBannerMargin = EdgeInsets.fromLTRB(
  V2Spacing.space24,
  V2Spacing.space12,
  V2Spacing.space24,
  0,
);
