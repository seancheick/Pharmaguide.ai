// Phase 11.7c.3 — ReviewBeforeUse helpers (pure logic).
//
// Mirrors production's tone/row composition in
// `lib/features/product_detail/widgets/review_before_use_card.dart`:
//   • `_parseHint(raw)`        (line 1177) → [parseInteractionHint]
//   • `_computeTone({...})`    (line 1074) → [computeReviewTone]
//   • `_allergenTone(presence)`(line 1118) → [toneForAllergen]
//   • `_severityColor(sev)`    (line 913)  → severity → PGReviewTone
//   • `_countCopy(count)`      (line 331)  → [countCopy]
//   • `_affirmativeCopy(n)`    (line 336)  → [affirmativeCopy]
//   • `_humanLabel(id)`        (line 1201) → [humanLabelForCondition]
//   • `_humanConcern(concern)` (line 751)  → [humanConcernLabel]
//
// Sean's rules (2026-05-15):
//   • Preserve provider logic — no new clinical language.
//   • Preserve dedup + filter pipelines (composeGuardedWarnings already
//     used upstream).
//   • Preserve all severity rules. Allergen `contains` ALWAYS wins to
//     danger even with a free-from claim (matches production line 170).
//   • PGReviewBeforeUseCard's row model is flatter than production's
//     (no chips, no evidence-pill). The v2 adapter packs management +
//     evidence + citations COUNT into the caption so users still see
//     the same information density. The Citations bottom sheet is
//     surfaced via the row's `onTap`.

import 'dart:convert';

import 'package:pharmaguide/core/components/pg_review_before_use_card.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/features/product_detail/allergen_match.dart';
import 'package:pharmaguide/features/product_detail/free_from_match.dart';
import 'package:pharmaguide/features/product_detail/widgets/interaction_warnings.dart';

// =========================================================================
// Hint parsing (verbatim port of production's _parseHint + _listOfStrings).
// =========================================================================

/// Decoded `_product.interactionSummaryHint` structure.
class ParsedInteractionHint {
  final bool hasAny;
  final List<String> conditionIds;
  final List<String> drugClassIds;

  const ParsedInteractionHint({
    required this.hasAny,
    required this.conditionIds,
    required this.drugClassIds,
  });
}

/// Decode the `interaction_summary_hint` JSON string. Returns null when
/// empty, not a Map, or malformed. Verbatim port of production's
/// `_parseHint` (line 1177).
ParsedInteractionHint? parseInteractionHint(String raw) {
  if (raw.isEmpty) return null;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    final map = Map<String, dynamic>.from(decoded);
    return ParsedInteractionHint(
      hasAny: map['has_any'] == true,
      conditionIds: _stringList(map['condition_ids']),
      drugClassIds: _stringList(map['drug_class_ids']),
    );
  } on FormatException {
    return null;
  }
}

List<String> _stringList(Object? raw) {
  if (raw is List) {
    return raw.map((e) => e.toString()).toList(growable: false);
  }
  return const [];
}

// =========================================================================
// Tone computation (verbatim port of production's _computeTone +
// _allergenTone; mapped from PGBannerTone → PGReviewTone).
// =========================================================================

/// Compute the overall card tone from the combined inputs. Mirrors
/// production line 174 — allergen `contains` ALWAYS bumps to danger
/// even with a free-from claim present.
///
/// `hasOnlyAffirmatives` flips the card to a calm tone — `safe` when
/// any claim is certified, otherwise `info` (matches production's
/// PGBannerTone.success → safe / neutral → info mapping).
PGReviewTone computeReviewTone({
  required List<InteractionWarning> warnings,
  required List<MatchedAllergen> allergens,
  required bool hasOnlyAffirmatives,
  required bool hasFreeFromCertified,
}) {
  if (hasOnlyAffirmatives) {
    return hasFreeFromCertified ? PGReviewTone.safe : PGReviewTone.info;
  }
  var hasDanger = false;
  var hasCaution = false;
  for (final w in warnings) {
    switch (w.severity) {
      case Severity.contraindicated:
      case Severity.avoid:
        hasDanger = true;
      case Severity.caution:
        hasCaution = true;
      case Severity.monitor:
      case Severity.informational:
      case Severity.safe:
        // Info-tier severities fall through to the default `info` tone.
        break;
    }
  }
  for (final m in allergens) {
    switch (m.presenceType) {
      case 'contains':
        hasDanger = true;
      case 'may_contain':
        hasCaution = true;
      case 'manufactured_in_facility':
        // Facility tier → info (default fallback).
        break;
    }
  }
  if (hasDanger) return PGReviewTone.danger;
  if (hasCaution) return PGReviewTone.caution;
  return PGReviewTone.info;
}

/// Per-row tone for an allergen match. Verbatim port of production's
/// `_allergenTone`.
PGReviewTone toneForAllergen(String presenceType) {
  switch (presenceType) {
    case 'contains':
      return PGReviewTone.danger;
    case 'may_contain':
      return PGReviewTone.caution;
    case 'manufactured_in_facility':
      return PGReviewTone.info;
    default:
      return PGReviewTone.caution;
  }
}

/// Per-row tone for an interaction warning. Verbatim port of
/// production's `_severityColor` (line 913) — same severity → color
/// mapping, expressed as PGReviewTone.
PGReviewTone toneForWarning(Severity severity) {
  switch (severity) {
    case Severity.contraindicated:
    case Severity.avoid:
      return PGReviewTone.danger;
    case Severity.caution:
      return PGReviewTone.caution;
    case Severity.monitor:
    case Severity.informational:
    case Severity.safe:
      // Production maps monitor/info/safe to caution as a fallback —
      // these severities never reach this widget after the profile
      // gate, but the mapping is preserved verbatim for safety.
      return PGReviewTone.caution;
  }
}

// =========================================================================
// Header copy (verbatim port of production's _countCopy + _affirmativeCopy).
// =========================================================================

/// "N things to review before use" / "1 thing to review before use".
/// Verbatim port of production's `_countCopy` (line 331).
String countCopy(int count) {
  if (count == 1) return '1 thing to review before use';
  return '$count things to review before use';
}

/// "N allergen claims verified" / "1 allergen claim verified". Verbatim
/// port of production's `_affirmativeCopy` (line 336).
String affirmativeCopy(int count) {
  if (count == 1) return '1 allergen claim verified';
  return '$count allergen claims verified';
}

// =========================================================================
// Row composition (allergen / free-from / warning → PGReviewRow).
// =========================================================================

/// Build a PGReviewRow for a matched allergen. Caption captures the
/// presence type + display name + optional evidence verbatim from the
/// pipeline so users still see the source quote.
PGReviewRow rowForAllergen(MatchedAllergen match) {
  final tag = _allergenTag(match.presenceType);
  final captionParts = <String>[
    tag,
    if (match.presenceType == 'contains' && match.severityLevel == 'high')
      'severe',
    if (match.evidence != null && match.evidence!.isNotEmpty)
      '"${match.evidence}"',
  ];
  return PGReviewRow(
    headline: match.displayName,
    caption: captionParts.join(' · '),
    rowTone: toneForAllergen(match.presenceType),
  );
}

/// Build a PGReviewRow for a free-from claim. `notClaimed` rows are
/// already filtered upstream (matches production line 134); this helper
/// handles `certified` and `unknown` only.
PGReviewRow rowForFreeFromClaim(FreeFromClaim claim) {
  switch (claim.status) {
    case FreeFromStatus.certified:
      return PGReviewRow(
        headline: claim.label,
        caption: 'Verified · matches your allergen profile',
        rowTone: PGReviewTone.safe,
      );
    case FreeFromStatus.unknown:
      return PGReviewRow(
        headline: claim.label,
        caption: 'Unverified · we couldn\'t confirm this claim',
        rowTone: PGReviewTone.info,
      );
    case FreeFromStatus.notClaimed:
      // Defensive — caller should have filtered these out.
      return PGReviewRow(
        headline: claim.label,
        caption: 'No claim on this label',
        rowTone: PGReviewTone.info,
      );
  }
}

/// Build a PGReviewRow for an interaction warning. Caption packs
/// mechanism + management + evidence level + citation count so the
/// v2 card retains the information production surfaces via chips.
/// Tap surfacing of citations is deferred to the section adapter.
PGReviewRow rowForWarning(
  InteractionWarning warning, {
  void Function(List<String> sourceUrls)? onTapCitations,
}) {
  final captionParts = <String>[];
  if (warning.mechanism.isNotEmpty) captionParts.add(warning.mechanism);
  if (warning.management.isNotEmpty) captionParts.add(warning.management);
  captionParts.add(warning.evidenceLevel.label);
  final citationCount = warning.sourceUrls.length;
  if (citationCount > 0) {
    captionParts.add(
      '$citationCount citation${citationCount == 1 ? '' : 's'}',
    );
  }
  return PGReviewRow(
    headline: warning.title,
    caption: captionParts.join(' · '),
    rowTone: toneForWarning(warning.severity),
    onTap: citationCount > 0 && onTapCitations != null
        ? () => onTapCitations(warning.sourceUrls)
        : null,
  );
}

/// Sort warnings by severity desc, matching production's `_sortedBySeverity`
/// (line 440).
List<InteractionWarning> sortWarningsBySeverity(
  List<InteractionWarning> input,
) {
  final sorted = List<InteractionWarning>.from(input);
  sorted.sort((a, b) => b.severity.weight.compareTo(a.severity.weight));
  return sorted;
}

// =========================================================================
// Conditions / drug-class context line (verbatim port of production's
// _ContextLine + _humanLabel).
// =========================================================================

/// Build the "Your conditions: X · Your medications: Y" caption used
/// in the card header body when interaction context is present.
/// Returns null when both lists are empty.
String? buildInteractionContextLine({
  required List<String> matchedConditions,
  required List<String> matchedDrugClasses,
}) {
  final lines = <String>[];
  if (matchedConditions.isNotEmpty) {
    lines.add(
      'Your conditions: '
      '${matchedConditions.map(humanLabelForCondition).join(', ')}',
    );
  }
  if (matchedDrugClasses.isNotEmpty) {
    lines.add(
      'Your medications: '
      '${matchedDrugClasses.map(humanLabelForCondition).join(', ')}',
    );
  }
  if (lines.isEmpty) return null;
  return lines.join(' · ');
}

/// snake_case → human label, with overrides for medical acronyms.
/// Verbatim port of production's `_humanLabel` (line 1201).
String humanLabelForCondition(String id) {
  const overrides = {
    'ttc': 'Trying to conceive',
    'nsaids': 'NSAIDs',
    'ssris': 'SSRIs',
    'snris': 'SNRIs',
    'maois': 'MAOIs',
    'gi_disorders': 'GI disorders',
    'gerd': 'GERD',
    'ibs': 'IBS',
    'ibd': 'IBD',
    'copd': 'COPD',
    'pcos': 'PCOS',
    'adhd': 'ADHD',
    'hiv_aids': 'HIV/AIDS',
  };
  final lower = id.toLowerCase();
  if (overrides.containsKey(lower)) return overrides[lower]!;
  return lower
      .split('_')
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');
}

/// Human-readable concern label for free-from conflict footer. Verbatim
/// port of production's `_humanConcern` (line 751).
String humanConcernLabel(String concern) {
  switch (concern) {
    case 'gluten':
      return 'gluten';
    case 'dairy':
      return 'dairy';
    case 'soy':
      return 'soy';
    default:
      return concern;
  }
}

/// Build the "Label disagreement" footer body. Returns null when there
/// are no conflicts. Mirrors production's `_ConflictFooter` body copy
/// (line 734).
String? buildConflictFooterBody(List<String> conflicts) {
  if (conflicts.isEmpty) return null;
  final labels = conflicts.map(humanConcernLabel).join(', ');
  return 'Marked $labels-free but our allergen scan also flagged '
      '$labels. Please read the actual label.';
}

// =========================================================================
// Private helpers.
// =========================================================================

String _allergenTag(String presenceType) {
  switch (presenceType) {
    case 'contains':
      return 'Contains';
    case 'may_contain':
      return 'May contain';
    case 'manufactured_in_facility':
      return 'Facility';
    default:
      return 'Allergen';
  }
}
