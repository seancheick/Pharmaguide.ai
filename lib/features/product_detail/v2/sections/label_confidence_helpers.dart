// Phase 11.7c.4 — LabelConfidence helpers (pure logic).
//
// Owns analysis-coverage tier + row composition for the v2
// PGLabelConfidenceCard:
//   • tier classification → [LabelConfidenceTier]
//   • tier labels/header prefixes
//   • unmapped/product-status summaries
//   • row composition for 5 signals into PGLabelConfidenceItem list.
//
// Sean's rules (2026-05-15):
//   • Preserve production's tier rules verbatim (note vs partial vs limited).
//   • Preserve `hasAnySignal` gate semantics — caller passes the boolean.
//   • Preserve the row order: isNotScored → mappedCoverage → blends →
//     unmapped → productStatus.
//   • Never red. This card is a calm caveat block; recalled / banned
//     products go through the hero BlockedBanner instead.
//   • No invented copy — row body strings preserve the approved
//     production wording.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pharmaguide/core/components/pg_label_confidence_card.dart';
import 'package:pharmaguide/core/scoring/coverage.dart';

/// Three-tier classification for the label-confidence card. Verbatim
/// port of production's private `_Tier` enum.
enum LabelConfidenceTier {
  /// Informational note — e.g. discontinued status only, no data quality
  /// issue. Header reads "Product note".
  note,

  /// Some label data missing or proprietary blend obscures doses.
  /// Header reads "Label confidence: Partial".
  partial,

  /// NOT_SCORED or mappedCoverage < 0.3 — analysis cannot be trusted.
  /// Header reads "Analysis coverage: Limited".
  limited,
}

/// Compute the tier from the 5 signals. Verbatim port of production's
/// `_computeTier` (line 208).
LabelConfidenceTier computeLabelConfidenceTier({
  required double mappedCoverage,
  required bool hasProprietaryBlends,
  required bool isNotScored,
  Map<String, dynamic>? unmappedActives,
}) {
  if (isNotScored || isLowCoverage(mappedCoverage)) {
    return LabelConfidenceTier.limited;
  }
  if (mappedCoverage < 0.5) return LabelConfidenceTier.partial;
  if (hasProprietaryBlends) return LabelConfidenceTier.partial;
  if (unmappedTotal(unmappedActives) > 0) return LabelConfidenceTier.partial;
  // No data-quality issue — only signal is product_status. Status is
  // informational, not a label-confidence problem.
  return LabelConfidenceTier.note;
}

/// Tier display label. Verbatim from production line 225.
String tierLabel(LabelConfidenceTier tier) {
  switch (tier) {
    case LabelConfidenceTier.note:
      return 'Note';
    case LabelConfidenceTier.partial:
      return 'Partial';
    case LabelConfidenceTier.limited:
      return 'Limited';
  }
}

/// Header prefix — "Product" for note tier, "Analysis coverage:" for
/// data-quality tiers.
String headerPrefix(LabelConfidenceTier tier) {
  return tier == LabelConfidenceTier.note ? 'Product' : 'Analysis coverage:';
}

/// Full header text — "Product note" for note tier (no separate label
/// suffix), "Analysis coverage: Partial" / "Analysis coverage: Limited"
/// for data-quality tiers.
String composeHeader(LabelConfidenceTier tier) {
  if (tier == LabelConfidenceTier.note) return 'Product note';
  return '${headerPrefix(tier)} ${tierLabel(tier)}';
}

/// "isCaution" flag for the PGLabelConfidenceCard header tint. Note
/// tier renders in muted grey; partial/limited render in caution amber.
bool isCautionTier(LabelConfidenceTier tier) =>
    tier != LabelConfidenceTier.note;

// =========================================================================
// productStatus / unmappedActives blob helpers (verbatim ports).
// =========================================================================

/// Total unmapped active count from the blob. Verbatim port of
/// production's `_unmappedTotal` (line 246).
int unmappedTotal(Map<String, dynamic>? blob) {
  final raw = blob?['total'];
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  if (raw is String) return int.tryParse(raw) ?? 0;
  return 0;
}

/// Names list from unmapped actives, formatted as "X, Y, Z and N more".
/// Verbatim port of production's `_unmappedNames` (line 472).
String? unmappedNamesSummary(Map<String, dynamic>? blob) {
  final raw = blob?['names'];
  if (raw is! List) return null;
  final names = raw
      .map((e) => e.toString().trim())
      .where((s) => s.isNotEmpty)
      .toList(growable: false);
  if (names.isEmpty) return null;
  return names.length <= 4
      ? names.join(', ')
      : '${names.take(3).join(', ')} and ${names.length - 3} more';
}

const _kTypeLabels = <String, String>{
  'discontinued': 'Product discontinued',
  'off_market': 'Off market',
  'reformulated': 'Reformulated',
  'limited_availability': 'Limited availability',
  'seasonal': 'Seasonal product',
};

/// Compose the product-status row label ("Product discontinued · May 5,
/// 2024" or the pipeline-provided display string). Verbatim port of
/// production's `_productStatusLabel` (line 262).
String? productStatusLabel(Map<String, dynamic>? blob) {
  if (blob == null) return null;
  final display = blob['display']?.toString().trim();
  final type = blob['type']?.toString().trim().toLowerCase();
  final rawDate = blob['date']?.toString().trim();
  final leadIn = type == null ? null : _kTypeLabels[type];
  if (leadIn != null && rawDate != null && rawDate.isNotEmpty) {
    final parsed = DateTime.tryParse(rawDate);
    if (parsed != null) {
      return '$leadIn · ${DateFormat.yMMMd().format(parsed)}';
    }
  }
  if (display != null && display.isNotEmpty) return display;
  return null;
}

/// Pluralize helper. Verbatim port of production line 469.
String pluralize(int n, String singular, String plural) =>
    n == 1 ? singular : plural;

/// Production status-type code extracted from the blob — drives the
/// product-status explanation sheet copy. Returns null when the type
/// field is missing or empty.
String? productStatusType(Map<String, dynamic>? blob) {
  final type = blob?['type']?.toString().trim().toLowerCase();
  if (type == null || type.isEmpty) return null;
  return type;
}

// =========================================================================
// Row composition — build the list of PGLabelConfidenceItem entries
// from the 5 signals. Order + copy preserved verbatim from production
// lines 148–191.
// =========================================================================

/// Build the row list for the PGLabelConfidenceCard. Each rendered row
/// corresponds 1:1 to production's `_Row` / `_StatusRow` calls.
List<PGLabelConfidenceItem> buildLabelConfidenceItems({
  required double mappedCoverage,
  required bool hasProprietaryBlends,
  required bool isNotScored,
  Map<String, dynamic>? productStatus,
  Map<String, dynamic>? unmappedActives,
  Map<String, dynamic>? labelLedgerAudit,
  bool labelLedgerAuditPresent = false,
  VoidCallback? onTapProductStatus,
}) {
  final items = <PGLabelConfidenceItem>[];

  final completeness = labelCompletenessPresentation(
    labelLedgerAudit,
    auditPresent: labelLedgerAuditPresent,
  );
  // Only surface completeness when it materially limits the analysis; a clean
  // 100% audit is a silent success (no consumer row).
  if (completeness != null && completeness.isException) {
    items.add(
      PGLabelConfidenceItem(
        icon: completeness.icon,
        title: completeness.title,
        body: completeness.body,
      ),
    );
  }

  if (isNotScored) {
    items.add(
      const PGLabelConfidenceItem(
        icon: Icons.help_outline_rounded,
        title: 'Not enough verified data to score',
        body:
            'The analysis data we have is too incomplete to produce a '
            'reliable score for this product.',
      ),
    );
  }

  if (mappedCoverage < 0.5) {
    final lowCoverage = isLowCoverage(mappedCoverage);
    items.add(
      PGLabelConfidenceItem(
        icon: Icons.warning_amber_rounded,
        title: lowCoverage
            ? 'Limited analysis coverage'
            : 'Analysis coverage is incomplete',
        body: lowCoverage
            ? 'We could not match enough label entries to our reference '
                  'data for a confident analysis. This does not mean rows '
                  'are missing from What the label lists.'
            : 'Some label entries did not match our reference data, so the '
                  'analysis may miss context. This does not mean those rows '
                  'are missing from What the label lists.',
      ),
    );
  }

  if (hasProprietaryBlends) {
    items.add(
      const PGLabelConfidenceItem(
        icon: Icons.visibility_off_outlined,
        title: 'Blend amounts not disclosed',
        body:
            'This product lists a proprietary blend, so individual '
            'ingredient doses are hidden. Our analysis cannot evaluate '
            'per-ingredient amounts.',
      ),
    );
  }

  final unmapped = unmappedTotal(unmappedActives);
  if (unmapped > 0) {
    items.add(
      PGLabelConfidenceItem(
        icon: Icons.help_center_outlined,
        title:
            '$unmapped ${pluralize(unmapped, "ingredient", "ingredients")} '
            'could not be mapped',
        body:
            'These appear on the label but were not in our reference '
            'data, so they did not affect the score.',
        detail: unmappedNamesSummary(unmappedActives),
      ),
    );
  }

  final statusLabel = productStatusLabel(productStatus);
  if (statusLabel != null) {
    items.add(
      PGLabelConfidenceItem(
        icon: Icons.event_busy_outlined,
        title: statusLabel,
        body: 'Tap for details about this product status.',
        onTap: onTapProductStatus,
      ),
    );
  }

  return items;
}

/// A label-ledger result derived only from pipeline reconciliation metadata.
/// It never interprets [mappedCoverage] and never implies clinical analysis.
class LabelCompletenessPresentation {
  final IconData icon;
  final String title;
  final String body;
  final String semanticsLabel;

  /// True when the audit materially LIMITS the analysis (incomplete /
  /// unavailable / unsupported). A clean 100%-complete audit is NOT an
  /// exception — success stays invisible to the consumer; only exceptions
  /// surface. Consumers gate the completeness row + the signal on this.
  final bool isException;

  const LabelCompletenessPresentation({
    required this.icon,
    required this.title,
    required this.body,
    required this.semanticsLabel,
    this.isException = true,
  });
}

/// Parse the closed `label_ledger_audit` contract for display.
///
/// A non-null malformed or unsupported audit fails closed to unavailable and
/// never exposes a percentage or a completeness claim. A null audit means the
/// legacy product has no ledger result to present.
LabelCompletenessPresentation? labelCompletenessPresentation(
  Map<String, dynamic>? audit, {
  bool auditPresent = false,
}) {
  if (audit == null && !auditPresent) return null;
  if (audit == null) {
    return const LabelCompletenessPresentation(
      icon: Icons.error_outline_rounded,
      title: 'Label completeness unavailable',
      body:
          'Label data unavailable because the completeness record needs '
          'review. No completeness percentage is shown.',
      semanticsLabel:
          'Label completeness unavailable. Label data unavailable because '
          'the completeness record needs review.',
    );
  }

  final supportStatus = audit['support_status'];
  final sourceStructure = audit['source_structure'];
  final completenessStatus = audit['completeness_status'];
  final meaningfulRows = audit['meaningful_source_rows'];
  final displayedRows = audit['displayed_rows'];
  final omittedRows = audit['omitted_rows'];
  final percentage = audit['completeness_percentage'];

  final countsAreValid =
      _isNonNegativeInt(meaningfulRows) &&
      _isNonNegativeInt(displayedRows) &&
      _isNonNegativeInt(omittedRows);
  final isUnsupported =
      supportStatus == 'unsupported' &&
      sourceStructure == 'unsupported_source_structure' &&
      countsAreValid &&
      percentage == null &&
      completenessStatus == 'unavailable';
  if (isUnsupported) {
    return const LabelCompletenessPresentation(
      icon: Icons.help_outline_rounded,
      title: 'Label completeness unavailable',
      body:
          'Label data unavailable: this label structure has not been '
          'verified for completeness yet. No completeness percentage is shown.',
      semanticsLabel:
          'Label completeness unavailable. Label data unavailable because '
          'this label structure has not been verified.',
    );
  }

  final supportedPercentage = _validSupportedPercentage(
    supportStatus: supportStatus,
    sourceStructure: sourceStructure,
    completenessStatus: completenessStatus,
    meaningfulRows: meaningfulRows,
    displayedRows: displayedRows,
    omittedRows: omittedRows,
    percentage: percentage,
  );
  if (supportedPercentage == null) {
    return const LabelCompletenessPresentation(
      icon: Icons.error_outline_rounded,
      title: 'Label completeness unavailable',
      body:
          'Label data unavailable because the completeness record needs '
          'review. No completeness percentage is shown.',
      semanticsLabel:
          'Label completeness unavailable. Label data unavailable because '
          'the completeness record needs review.',
    );
  }

  final displayPercentage = _formatPercentage(supportedPercentage);
  final isComplete = completenessStatus == 'complete';
  final body = isComplete
      ? 'Every meaningful source-label row is represented in What the label '
            'lists. This does not mean every row is clinically analyzed.'
      : 'Only $displayedRows of $meaningfulRows meaningful source-label rows '
            'are represented in What the label lists. This does not indicate '
            'how many rows were clinically analyzed.';
  return LabelCompletenessPresentation(
    icon: isComplete ? Icons.fact_check_outlined : Icons.warning_amber_rounded,
    title: 'Label completeness: $displayPercentage%',
    body: body,
    semanticsLabel: 'Label completeness, $displayPercentage percent. $body',
    // A fully-represented label is a silent success, not a consumer signal.
    isException: !isComplete,
  );
}

bool _isNonNegativeInt(Object? value) => value is int && value >= 0;

double? _validSupportedPercentage({
  required Object? supportStatus,
  required Object? sourceStructure,
  required Object? completenessStatus,
  required Object? meaningfulRows,
  required Object? displayedRows,
  required Object? omittedRows,
  required Object? percentage,
}) {
  if (supportStatus != 'supported' ||
      sourceStructure is! String ||
      sourceStructure.trim().isEmpty ||
      sourceStructure == 'unsupported_source_structure' ||
      !_isNonNegativeInt(meaningfulRows) ||
      !_isNonNegativeInt(displayedRows) ||
      !_isNonNegativeInt(omittedRows) ||
      displayedRows as int > (meaningfulRows as int) ||
      percentage is! num ||
      percentage is bool) {
    return null;
  }

  final expected = meaningfulRows == 0
      ? (sourceStructure == 'empty_panel' && displayedRows == 0 ? 100.0 : null)
      : double.parse((displayedRows / meaningfulRows * 100).toStringAsFixed(2));
  if (expected == null || (percentage.toDouble() - expected).abs() > 0.001) {
    return null;
  }
  if ((expected == 100.0 && completenessStatus != 'complete') ||
      (expected < 100.0 && completenessStatus != 'incomplete')) {
    return null;
  }
  return expected;
}

String _formatPercentage(double value) {
  final fixed = value.toStringAsFixed(2);
  return fixed
      .replaceFirst(RegExp(r'\.0+$'), '')
      .replaceFirst(RegExp(r'(\.\d*?)0+$'), r'$1');
}

/// Screen-reader summary for the two independent coverage concepts.
String coverageSemanticsLabel({
  required LabelConfidenceTier tier,
  required double mappedCoverage,
  required bool hasProprietaryBlends,
  required bool isNotScored,
  Map<String, dynamic>? unmappedActives,
  Map<String, dynamic>? labelLedgerAudit,
  bool labelLedgerAuditPresent = false,
}) {
  final parts = <String>[];
  final completeness = labelCompletenessPresentation(
    labelLedgerAudit,
    auditPresent: labelLedgerAuditPresent,
  );
  if (completeness != null) parts.add(completeness.semanticsLabel);

  final hasAnalysisSignal =
      isNotScored ||
      mappedCoverage < 0.5 ||
      hasProprietaryBlends ||
      unmappedTotal(unmappedActives) > 0;
  if (hasAnalysisSignal) {
    final coverageBody = isLowCoverage(mappedCoverage)
        ? 'We could not match enough label entries to our reference data for '
              'a confident analysis.'
        : 'Some label entries could not be fully evaluated by the analysis.';
    parts.add(
      'Analysis coverage, ${tierLabel(tier).toLowerCase()}. $coverageBody',
    );
  }
  return parts.join(' ');
}

/// Body copy for the product-status explanation bottom sheet. Verbatim
/// port of production's `_ProductStatusExplanationSheet._bodyCopy`
/// (line 407).
String productStatusExplanationBody(String? type) {
  switch (type) {
    case 'reformulated':
      return 'This product has been reformulated. Ingredients, doses, '
          'or inactive components may differ from older bottles, so '
          'rescan the exact version you have in hand.';
    case 'off_market':
      return 'This product appears to be off market or no longer broadly '
          'available. That does not automatically mean it is unsafe, but '
          'availability and listing details may be outdated.';
    case 'limited_availability':
      return 'This product has limited availability. Listing, stock, or '
          'distribution details may change faster than usual.';
    case 'seasonal':
      return 'This product appears to be seasonal. Availability may vary '
          'throughout the year, and newer lots may differ from older ones.';
    case 'discontinued':
    default:
      return 'This product is no longer manufactured. Formulas may have '
          'changed or been replaced in newer versions.';
  }
}
