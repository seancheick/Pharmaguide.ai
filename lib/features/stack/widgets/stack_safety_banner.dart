// StackSafetyBanner — top-of-stack-screen banner summarizing every
// safety signal the M1 nutrient engine and the M4 curated interaction
// checker produce for the user's current stack.
//
// Input: the shared [StackHealthSnapshot]. The banner is intentionally pure —
// no Riverpod hooks, I/O, async work, or independent signal reconstruction.
// Tone, title, body, and count all come from the SAME ordered signal list.
//
// Visual behavior:
//   - no signals            → hidden (SizedBox.shrink) so an all-clear stack
//                              doesn't push the product list down — UNLESS a
//                              check/coverage flag is set, in which case we
//                              hedge instead of implying "all clear".
//   - headline = block/avoid → red danger tone.
//   - caution / monitor     → amber caution tone.
//   - interactive (onTap)   → a compact overview card that PREVIEWS every
//                              finding, not just the headline (see below).
//   - non-interactive       → single-headline banner with a "+N more" suffix.
//
// Why the interactive form previews the whole set: the Stack Health header
// counts the stack ("3 safety signals to review") while a headline-only card
// spotlights one pair, so the screen read as "there is one issue" until the
// user opened the sheet. Summary and detail must not contradict each other.
// Consequently the stack-wide count lives in the header and the action label
// only — never fused onto one finding's metadata line — and the long clinical
// copy stays in the sheet.
//
// Suppress-disposition signals (e.g. a safe interaction) are excluded upstream
// by the shared snapshot, so a safe-only stack collapses to the hedge/hidden
// path rather than a success banner — never a false all-clear.

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_eyebrow.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/scoring/coverage.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/core/widgets/pg_severity_banner.dart';
import 'package:pharmaguide/features/stack/widgets/clinical_signal_visuals.dart';
import 'package:pharmaguide/services/signals/clinical_signal_envelope.dart';
import 'package:pharmaguide/services/signals/stack_signal_aggregator.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';
import 'package:pharmaguide/services/stack/stack_safety_report.dart';
import 'package:pharmaguide/services/stack/stack_intelligence_engine.dart';

class StackSafetyBanner extends StatelessWidget {
  const StackSafetyBanner({
    super.key,
    required this.snapshot,
    this.onTap,
    this.margin = EdgeInsets.zero,
  });

  /// Shared Stack Health interpretation. The widget never rebuilds findings.
  final StackHealthSnapshot snapshot;

  /// Optional tap handler. When supplied the banner becomes the multi-signal
  /// overview card, whose "Review all N" action opens the caller's target
  /// (usually the stack-safety detail sheet). Omit to render a
  /// non-interactive single-headline summary — useful on screens where the
  /// banner is purely an alert and there is nothing to open.
  final VoidCallback? onTap;

  /// Outer margin for the banner. Matches the [PGSeverityBanner]
  /// contract so the caller can match the surrounding layout without
  /// wrapping in another [Padding].
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final signals = snapshot.reviewSignals;
    final analysisIncomplete = snapshot.intelligence.analysisIncomplete;

    // No renderable signal. Never imply "all clear" when a check or coverage
    // gap means we may not have seen everything.
    if (signals.isEmpty) {
      if (snapshot.coverageIncomplete) return _coverageHedgeBanner();
      if (analysisIncomplete) return _checksIncompleteBanner();
      return const SizedBox.shrink();
    }

    final headline = signals.first;
    final worst = headline.clinicalSeverity;
    final tone = _toneFor(worst);

    // A success-toned summary is only honest when every label was analyzed and
    // every check finished. (In practice the headline is never `safe`, since
    // suppress signals are excluded — this guards odd upstream data.)
    if (analysisIncomplete && tone == PGBannerTone.success) {
      return _checksIncompleteBanner();
    }

    if (onTap case final openSheet?) {
      return _SignalOverviewCard(
        signals: signals,
        tone: tone,
        analysisIncomplete: analysisIncomplete,
        onTap: openSheet,
        margin: margin,
      );
    }

    return PGSeverityBanner(
      key: const Key('stack-safety-banner'),
      tone: tone,
      title: _titleFor(headline, worst),
      body: _bodyWithCompleteness(
        _bodyFor(signals, headline),
        checksIncomplete: snapshot.checksIncomplete,
        coverageIncomplete: snapshot.coverageIncomplete,
      ),
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

  static String _subjectFor(ClinicalSignal signal) {
    switch (signal.payload) {
      case InteractionPayload(:final result):
        return '${result.agent1Name} × ${result.agent2Name}';
      case MedicationProfilePayload(:final warning):
        return warning.headline.trim().isEmpty
            ? warning.medicationName
            : warning.headline;
      case CumulativeExposurePayload(:final status):
        return status.tier == NutrientTier.exceedsUl
            ? '${status.total.displayName} above upper limit'
            : '${status.total.displayName} near its upper limit';
      case DoseThresholdPayload(:final alert):
        return '${alert.displayName} dose threshold';
      case RegulatorySafetyPayload(:final alert):
        return alert.headline;
      case MedicationNutrientPayload(:final match):
        return '${match.drugDisplayName} & ${match.nutrientName}';
      case TimingSeparationPayload(:final optimization):
        return optimization.product1Name ?? optimization.ingredient1;
    }
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
      title: 'More info needed',
      body:
          'Some stack safety checks could not finish, so results may be '
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
          // "Vitamin D above upper limit", not "Upper limit - Vitamin D".
          // The old form named the concept before the nutrient and left the
          // user to infer what happened; this states the finding. It also
          // parallels the near-limit variant below, which already reads
          // "<nutrient> is near its upper limit".
          return '${status.total.displayName} above upper limit';
        }
        return '$prefix — ${status.total.displayName}';
      case DoseThresholdPayload(:final alert):
        return '${alert.displayName} dose threshold';
      case RegulatorySafetyPayload(:final alert):
        return alert.headline;
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
      case DoseThresholdPayload():
        primary = headline.body;
      case RegulatorySafetyPayload():
        primary = headline.body;
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

/// Compact overview of the findings behind the Stack Health count.
///
/// Previews up to [_maxPreviewRows] findings — each with its OWN metadata
/// line — and defers every paragraph of clinical copy to the detail sheet.
/// Three rules keep the preview honest:
///
///   1. The stack-wide count appears only in the action label ("Review all 3"),
///      never welded onto a single finding's metadata. Mixing the two is what
///      made the old headline card read as one issue out of three.
///   2. Every previewed row belongs to the group named by the eyebrow, so a
///      "Good to know" food note is never listed under "Needs attention".
///      Signals arrive disposition-ranked, so the leading run is that group.
///   3. Truncation is stated ("+2 more"), never silent.
class _SignalOverviewCard extends StatelessWidget {
  const _SignalOverviewCard({
    required this.signals,
    required this.tone,
    required this.analysisIncomplete,
    required this.onTap,
    required this.margin,
  });

  /// Enough to prove the summary is plural without turning the Stack screen
  /// into a second copy of the sheet.
  static const int _maxPreviewRows = 3;

  final List<ClinicalSignal> signals;
  final PGBannerTone tone;
  final bool analysisIncomplete;
  final VoidCallback onTap;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final palette = context.v2;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = PGSeverityBanner.accentFor(palette, tone);

    final leadRequiresReview = signals.first.consumerDisposition.requiresReview;
    final group = signals
        .takeWhile(
          (s) => s.consumerDisposition.requiresReview == leadRequiresReview,
        )
        .toList(growable: false);
    final preview = group.take(_maxPreviewRows).toList(growable: false);
    final hidden = signals.length - preview.length;

    return Container(
      key: const Key('stack-safety-banner'),
      margin: margin,
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        border: Border.all(color: palette.outline, width: 0.8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Severity wash + left accent strip: same chrome as PGSeverityBanner
          // so this card stays in the family it replaced.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    accent.withValues(
                      alpha: PGSeverityBanner.washAlpha(isDark: isDark),
                    ),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.5],
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(width: 3, color: accent),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  V2Spacing.space16 + 3,
                  V2Spacing.space12,
                  V2Spacing.space16,
                  V2Spacing.space12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PGEyebrow(
                      leadRequiresReview ? 'Needs attention' : 'Good to know',
                      color: accent,
                    ),
                    const SizedBox(height: V2Spacing.space12),
                    for (var i = 0; i < preview.length; i++) ...[
                      if (i > 0) const SizedBox(height: V2Spacing.space12),
                      _SignalPreviewRow(signal: preview[i]),
                    ],
                    if (hidden > 0) ...[
                      const SizedBox(height: V2Spacing.space8),
                      Text(
                        '+$hidden more',
                        style: V2Typography.bodySm(color: palette.fgMuted),
                      ),
                    ],
                    // Completeness is a separate concern from the findings —
                    // an unfinished check must never read as an all-clear, and
                    // must never be mistaken for one of the listed concerns.
                    // `analysisIncomplete` covers label coverage as well as
                    // checks, so the copy names both causes.
                    if (analysisIncomplete) ...[
                      const SizedBox(height: V2Spacing.space8),
                      Text(
                        'Some checks or product labels could not be fully '
                        'analyzed, so results may be incomplete.',
                        style: V2Typography.bodySm(color: palette.fgMuted),
                      ),
                    ],
                    const SizedBox(height: V2Spacing.space12),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _actionLabel(signals.length),
                          style: V2Typography.label(color: palette.fg),
                        ),
                        const SizedBox(width: 2),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 16,
                          color: palette.fg,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// "Review all 3" carries the total so the card never shows three rows while
  /// implying three is all there is. "Review all 1" would be nonsense, so the
  /// single-finding case keeps the plain label.
  static String _actionLabel(int total) =>
      total == 1 ? 'Review details' : 'Review all $total';
}

/// One previewed finding: subject line plus its own kind/evidence metadata.
/// Icon and colour come from the shared vocabulary the detail sheet uses, so a
/// row cannot change appearance between the preview and the sheet it opens.
class _SignalPreviewRow extends StatelessWidget {
  const _SignalPreviewRow({required this.signal});

  final ClinicalSignal signal;

  @override
  Widget build(BuildContext context) {
    final palette = context.v2;
    final subject = StackSafetyBanner._subjectFor(signal);
    final metadata = clinicalSignalContextLabel(signal);
    return Semantics(
      // Severity is carried by icon colour alone, which is lost to a screen
      // reader; state it. excludeSemantics stops the same row being read twice.
      label: '${signal.clinicalSeverity.label}: $subject. $metadata',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            clinicalSignalIcon(signal),
            size: 18,
            color: clinicalSignalSeverityColor(
              palette,
              signal.clinicalSeverity,
            ),
          ),
          const SizedBox(width: V2Spacing.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(subject, style: V2Typography.label(color: palette.fg)),
                const SizedBox(height: 2),
                Text(
                  metadata,
                  style: V2Typography.caption(color: palette.fgMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
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
