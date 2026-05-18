// Phase 11.7c.4 — LabelConfidence helpers (pure logic).
//
// Owns production's tier + row composition for the v2
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
  /// Header reads "Label confidence: Limited".
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
  if (isNotScored || mappedCoverage < 0.3) return LabelConfidenceTier.limited;
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

/// Header prefix — "Product" for note tier, "Label confidence:" for
/// data-quality tiers. Verbatim from production line 236.
String headerPrefix(LabelConfidenceTier tier) {
  return tier == LabelConfidenceTier.note ? 'Product' : 'Label confidence:';
}

/// Full header text — "Product note" for note tier (no separate label
/// suffix), "Label confidence: Partial" / "Label confidence: Limited"
/// for the data-quality tiers. Matches production line 93.
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
  VoidCallback? onTapProductStatus,
}) {
  final items = <PGLabelConfidenceItem>[];

  if (isNotScored) {
    items.add(
      const PGLabelConfidenceItem(
        icon: Icons.help_outline_rounded,
        title: 'Not enough verified data to score',
        body:
            'The label data we have is too incomplete to produce a '
            'reliable score for this product.',
      ),
    );
  }

  if (mappedCoverage < 0.5) {
    final lowCoverage = mappedCoverage < 0.3;
    items.add(
      PGLabelConfidenceItem(
        icon: Icons.warning_amber_rounded,
        title: lowCoverage
            ? 'Limited label data available'
            : 'Some ingredients could not be fully verified',
        body: lowCoverage
            ? 'We could not match enough of this label to our reference '
                  'data to assess it confidently.'
            : 'A portion of this label did not match our reference data, '
                  'so the analysis may miss some context.',
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
