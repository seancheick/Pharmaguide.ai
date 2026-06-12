// StackSafetyBanner — top-of-stack-screen banner summarizing every
// safety signal the M1 nutrient engine and the M4 curated interaction
// checker produce for the user's current stack.
//
// Input: a [StackSafetyReport] already built by the stack-scoring layer
// (spec §8.3). The banner is intentionally pure — no Riverpod hooks, no
// I/O, no async. The provider wiring lives in G11; tests drive this
// widget directly with synthetic reports so we can exhaustively cover
// every severity / content combination without spinning up a database.
//
// Visual behavior:
//   - `report.isEmpty`      → hidden (SizedBox.shrink) so an all-clear
//                              stack doesn't push the product list down.
//   - non-empty, worst=safe → rendered as a success banner ("All clear")
//                              when the only signals are sub-warn
//                              nutrient entries that still made it into
//                              the report. In practice this branch is
//                              rare because `isEmpty` already filters
//                              most clean cases, but it protects
//                              against odd upstream data.
//   - monitor / caution     → amber caution banner with the top warning
//                              title + a "N more" suffix when there
//                              are additional signals.
//   - avoid / contraindicated → red danger banner. The highest-severity
//                                signal drives the title; the count
//                                line summarizes the rest.
//
// The banner renders the single most-severe signal verbatim and lets
// the caller tap through for the full list. We deliberately do NOT
// show every warning inline — the banner is a summary, not a panel.

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/interaction_result.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/widgets/pg_severity_banner.dart';
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
    if (report.isEmpty) {
      // Low label-mapping coverage means the interaction checks may
      // not have seen every ingredient — never imply "all clear".
      if (report.coverageIncomplete) return _coverageHedgeBanner();
      return const SizedBox.shrink();
    }

    final worst = report.overallSeverity;
    final ordered = report.orderedWarnings;
    // Defensive — the report claims isEmpty==false so there should be
    // at least one warning, but we guard anyway so a malformed report
    // can never tear down the stack screen.
    if (ordered.isEmpty) {
      if (report.coverageIncomplete) return _coverageHedgeBanner();
      return const SizedBox.shrink();
    }

    // A success-toned summary is only honest when every label was
    // analyzed. With low coverage in the stack, downgrade to the
    // caution-toned hedge instead.
    if (report.coverageIncomplete && _toneFor(worst) == PGBannerTone.success) {
      return _coverageHedgeBanner();
    }

    return PGSeverityBanner(
      key: const Key('stack-safety-banner'),
      tone: _toneFor(worst),
      title: _titleFor(ordered.first, worst),
      body: _bodyFor(ordered, worst),
      actionLabel: onTap == null ? null : 'View details',
      onAction: onTap,
      margin: margin,
    );
  }

  /// Caution-toned hedge rendered when at least one stack product has a
  /// label mapping coverage below the 0.3 trust floor. Copy is
  /// calm-advisory per the voice guide — no imperatives.
  Widget _coverageHedgeBanner() {
    return PGSeverityBanner(
      key: const Key('stack-safety-banner'),
      tone: PGBannerTone.caution,
      title: 'Some labels couldn\'t be fully analyzed',
      body:
          'One or more products in your stack have limited ingredient '
          'data — results may be incomplete.',
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

  /// Title is the top warning rendered as a short one-liner. We prefix
  /// with the severity label so the user can scan by color + text in
  /// one glance ("AVOID — Warfarin × Fish Oil").
  static String _titleFor(Object topWarning, Severity worst) {
    final prefix = worst.label;
    if (topWarning is InteractionResult) {
      if (topWarning.isFoodAdvisoryNote) {
        return 'Food note — ${topWarning.agent1Name} × ${topWarning.agent2Name}';
      }
      return '$prefix — ${topWarning.agent1Name} × ${topWarning.agent2Name}';
    }
    if (topWarning is NutrientStatus) {
      return '$prefix — ${topWarning.total.displayName}';
    }
    // Unknown payload — fall back to the severity label alone so we
    // never crash on an unexpected type.
    return prefix;
  }

  /// Body describes the top warning's management / mechanism and
  /// appends a "+N more" hint when the stack has additional signals.
  static String? _bodyFor(List<Object> ordered, Severity worst) {
    final first = ordered.first;
    String? primary;
    if (first is InteractionResult) {
      // Prefer management (what the user should do); fall back to the
      // mechanism summary if management is empty. Always append the
      // evidence level — safety rule: interaction warnings must show
      // their evidence tier (mirrors rowForWarning in
      // review_before_use_helpers.dart).
      final base = first.management.trim().isNotEmpty
          ? first.management
          : first.mechanism;
      primary = base.trim().isEmpty
          ? first.evidenceLevel.label
          : '$base · ${first.evidenceLevel.label}';
    } else if (first is NutrientStatus) {
      primary = _nutrientHint(first);
    }

    final extraCount = ordered.length - 1;
    if (extraCount <= 0) return primary;

    final extraLabel = extraCount == 1
        ? '1 more signal'
        : '$extraCount more signals';
    if (primary == null || primary.isEmpty) return extraLabel;
    return '$primary  ·  $extraLabel';
  }

  /// Short human-readable hint for a flagged nutrient status. Mirrors
  /// the wording used in the nutrient-accumulation panel so users see
  /// consistent language across the stack screen.
  static String _nutrientHint(NutrientStatus n) {
    final name = n.total.displayName;
    switch (n.tier) {
      case NutrientTier.exceedsUl:
        return '$name exceeds upper limit across your stack.';
      case NutrientTier.approachingUl:
        return '$name is near its upper limit across your stack.';
      case NutrientTier.aboveTypical:
      case NutrientTier.abundant:
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
