// Tradeoffs section adapter.
//
// Composes PGTradeoffsSection from blob['score_bonuses'] (positive)
// and blob['score_penalties'] (negative), with verified UL exceedances
// from blob['rda_ul_data'] appended to the consideration column.
//
// Production data path (verbatim port):
//   blob['score_bonuses']  → isPositive=true  → "What's good" column
//   blob['score_penalties'] → isPositive=false → "What to consider" column
//   blob['rda_ul_data']     → UL flags       → "What to consider" column
//
// Each item: label || reason (headline) + detail || description (caption).
// Empty-label items are filtered out defensively. `sanitizeWhyDetail`
// drops noise patterns from the detail field.
//
// Sean's rules (2026-05-15):
//   • Preserve production gates: section hides when both lists are empty.
//   • Use production's sanitizeWhyDetail helper verbatim (publicly exposed).
//   • No invented copy — every headline/caption string comes from the
//     pipeline blob.
//   • Suppress cleanly on null/empty blob.
//
import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_tradeoffs_section.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/core/utils/num_parse.dart';
import 'package:pharmaguide/features/product_detail/product_detail_helpers.dart'
    show sanitizeWhyDetail;
import 'package:pharmaguide/features/product_detail/widgets/inactive_color.dart';
import 'package:pharmaguide/services/health/dose_safety.dart';
import 'package:pharmaguide/services/health/product_health_facts.dart';
import 'package:pharmaguide/services/health/rda_reference_contract.dart';

/// Build the Tradeoffs section. Returns `SizedBox.shrink()` when there
/// are no bonuses, penalties, or inactive-ingredient safety summary.
Widget buildTradeoffsSection({
  required Map<String, dynamic>? detailBlob,
  Map<String, dynamic>? appReferenceData,
}) {
  if (detailBlob == null) return const SizedBox.shrink();
  final healthFacts = ProductHealthFacts.fromDetailBlob(detailBlob);
  final productRdaData = _mapValue(detailBlob['rda_ul_data']);
  final rdaReferenceIsCurrent = hasCurrentRdaReference(
    appReferenceData: appReferenceData,
    productRdaUlData: productRdaData,
  );

  final bonuses =
      (detailBlob['score_bonuses'] as List?)
          ?.whereType<Map<String, dynamic>>()
          .toList(growable: false) ??
      const [];
  final penalties =
      (detailBlob['score_penalties'] as List?)
          ?.whereType<Map<String, dynamic>>()
          .toList(growable: false) ??
      const [];

  final safetySummary = _buildSafetySummary(
    detailBlob['inactive_ingredients'] as List?,
  );
  final pros = bonuses
      .map(_toTradeoff)
      .where((t) => t.headline.trim().isNotEmpty)
      .toList(growable: false);
  final penaltyConsiderations = penalties
      .map(_toTradeoff)
      .where((t) => t.headline.trim().isNotEmpty)
      .toList(growable: false);
  final considerations = _collapseAllergenSources(
    _collapseAdditiveConcerns([
      ...penaltyConsiderations,
      ..._buildUlConsiderations(
        safetyFlags: rdaReferenceIsCurrent
            ? healthFacts.ulSafetyFlags
            : const [],
        ulAnalysis: rdaReferenceIsCurrent ? healthFacts.ulAnalysis : const [],
        existing: penaltyConsiderations,
      ),
    ]),
  );
  if (pros.isEmpty && considerations.isEmpty && safetySummary == null) {
    return const SizedBox.shrink();
  }

  return PGTradeoffsSection(
    pros: pros,
    considerations: considerations,
    considerationLeading: safetySummary,
  );
}

Map<String, dynamic>? _mapValue(Object? raw) {
  if (raw is! Map) return null;
  return Map<String, dynamic>.from(raw);
}

List<PGTradeoff> _buildUlConsiderations({
  required List<Map<String, dynamic>> safetyFlags,
  required List<Map<String, dynamic>> ulAnalysis,
  required List<PGTradeoff> existing,
}) {
  final out = <PGTradeoff>[];
  final seen = <String>{};

  void addFromFlag(Map<Object?, Object?> flag) {
    // Skip flags the pipeline itself marks as not a real UL breach (e.g.
    // `compound_mass_not_elemental` false positives). Mirrors the stack
    // aggregator + dose_safety structured-UL defense.
    if (!isUlEvaluationEligible(flag)) return;
    final nutrient = _stringValue(
      flag['nutrient'] ?? flag['standard_name'] ?? flag['ingredient'],
    );
    if (nutrient == null) return;
    final key = _ulKey(nutrient);
    if (!seen.add(key) || _alreadyHasUlConsideration(existing, key)) return;

    final caption = _formatUlCaption(
      amount: asFiniteDouble(flag['amount'] ?? flag['quantity']),
      unit: _stringValue(flag['unit']),
      ul: asFiniteDouble(flag['ul'] ?? flag['highest_ul']),
      pctUl: asFiniteDouble(flag['pct_ul']),
      fallback: _stringValue(flag['warning']),
    );
    out.add(
      PGTradeoff(
        headline: '$nutrient exceeds the upper limit',
        caption: caption,
      ),
    );
  }

  for (final flag in safetyFlags) {
    addFromFlag(flag);
  }

  for (final row in ulAnalysis) {
    if (!isUlEvaluationEligible(row)) continue;
    // Require the pipeline's structured over-UL verdict — stale prose
    // `warnings` alone must not surface a tradeoff (matches
    // extractUlExceedances / dose_safety).
    if (row['over_ul'] != true) continue;
    addFromFlag(row);
  }

  return out;
}

bool _alreadyHasUlConsideration(List<PGTradeoff> existing, String nutrientKey) {
  for (final item in existing) {
    final text = '${item.headline} ${item.caption ?? ''}'.toLowerCase();
    if (!text.contains(nutrientKey)) continue;
    if (text.contains(' ul') ||
        text.contains('upper limit') ||
        text.contains('safe dose limit')) {
      return true;
    }
  }
  return false;
}

String _ulKey(String nutrient) {
  final normalized = nutrient.trim().toLowerCase();
  final compact = normalized.replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
  if (RegExp(
    r'\b(vitamin d2|vitamin d3|vitamin d|cholecalciferol|ergocalciferol)\b',
  ).hasMatch(compact)) {
    return 'vitamin d';
  }
  return compact.trim();
}

String? _formatUlCaption({
  required double? amount,
  required String? unit,
  required double? ul,
  required double? pctUl,
  required String? fallback,
}) {
  final displayUnit = unit == null || unit.isEmpty ? null : unit;
  final pct =
      pctUl ??
      (amount != null && ul != null && ul > 0 ? amount / ul * 100 : null);
  if (amount != null && ul != null && displayUnit != null) {
    final base =
        '${_formatNumber(amount)} $displayUnit vs ${_formatNumber(ul)} '
        '$displayUnit UL';
    if (pct != null) return '$base (${_formatPercent(pct)}% of UL)';
    return base;
  }
  return sanitizeWhyDetail(fallback);
}

String _formatPercent(double value) {
  if (!value.isFinite) return '';
  return value.round().toString();
}

String _formatNumber(double value) {
  if (!value.isFinite) return '';
  if ((value - value.round()).abs() < 0.05) return value.round().toString();
  return value.toStringAsFixed(1);
}

String? _stringValue(Object? raw) {
  final value = raw?.toString().trim();
  return value == null || value.isEmpty ? null : value;
}

/// Map a raw bonus/penalty entry to a PGTradeoff. Verbatim port of
/// production's `_extractWhyItems` field resolution:
///   headline = label || reason
///   caption  = sanitizeWhyDetail(detail || description)
///
/// **2026-08-07 — the "future cleanup" the note below anticipated:**
/// The pipeline now authors `Additive: ITEM` directly (build_final_db.py),
/// so the copy has one owner instead of being rewritten downstream. This
/// normalizer stays only to absorb the migration window: a catalog built
/// before that change still ships `Harmful additive: ITEM`, and the app
/// updates independently of the catalog. Both forms normalize to
/// `Additive: ITEM`. Drop the legacy branch once no shipped catalog
/// carries the old string.
///
/// Original note (Sean 2026-05-16): avoid "harmful" language in
/// user-facing copy; the penalty column already implies concern.
PGTradeoff _toTradeoff(Map<String, dynamic> entry) {
  final rawHeadline =
      (entry['label']?.toString() ?? entry['reason']?.toString() ?? '').trim();
  final headline = _softenAdditiveLanguage(rawHeadline);
  final rawDetail =
      entry['detail']?.toString() ?? entry['description']?.toString();
  final caption = sanitizeWhyDetail(rawDetail);
  return PGTradeoff(
    headline: headline,
    caption: caption.isEmpty ? null : caption,
  );
}

/// Matches the current pipeline form (`Additive: X`), the pre-2026-08-07 form
/// (`Harmful additive: X`) still present in already-built catalogs, and the
/// `Additive concern: X` string this function used to produce.
final RegExp _harmfulAdditivePrefix = RegExp(
  r'^\s*(?:harmful\s+)?additive(?:\s+concern)?[:\s]\s*',
  caseSensitive: false,
);

String _softenAdditiveLanguage(String headline) {
  final match = _harmfulAdditivePrefix.firstMatch(headline);
  if (match == null) return headline;
  final remainder = headline.substring(match.end).trim();
  if (remainder.isEmpty) return 'Additive';
  return 'Additive: $remainder';
}

List<PGTradeoff> _collapseAdditiveConcerns(List<PGTradeoff> items) {
  final additiveNames = <String>[];
  final seen = <String>{};
  final remaining = <PGTradeoff>[];

  for (final item in items) {
    final label = item.headline.trim();
    // Headlines reach here already normalized by _softenAdditiveLanguage.
    final match = RegExp(
      r'^\s*additive[:\s]\s*',
      caseSensitive: false,
    ).firstMatch(label);
    if (match == null) {
      remaining.add(item);
      continue;
    }
    final name = label.substring(match.end).trim();
    if (name.isEmpty) continue;
    if (seen.add(name.toLowerCase())) {
      additiveNames.add(name);
    }
  }

  if (additiveNames.isEmpty) return items;
  return [
    PGTradeoff(
      headline: additiveNames.length == 1
          ? 'Additive: ${additiveNames.first}'
          : 'Additives: ${additiveNames.join(", ")}',
    ),
    ...remaining,
  ];
}

final RegExp _allergenSourcePrefix = RegExp(
  r'^\s*declared allergen sources?[:\s]\s*',
  caseSensitive: false,
);

/// Collapse the per-allergen "Declared allergen source: X" penalty rows the
/// pipeline emits one-per-allergen into a single line:
///   "Declared allergen sources: Eggs, Fish, Tree Nuts".
/// Parallels [_collapseAdditiveConcerns]. Keeps the combined line at the
/// position of the first allergen row; preserves all non-allergen rows.
List<PGTradeoff> _collapseAllergenSources(List<PGTradeoff> items) {
  final names = <String>[];
  final seen = <String>{};
  final remaining = <PGTradeoff>[];
  var insertAt = -1;

  for (final item in items) {
    final label = item.headline.trim();
    final match = _allergenSourcePrefix.firstMatch(label);
    if (match == null) {
      remaining.add(item);
      continue;
    }
    if (insertAt < 0) insertAt = remaining.length;
    final name = label.substring(match.end).trim();
    if (name.isEmpty) continue;
    if (seen.add(name.toLowerCase())) names.add(name);
  }

  if (names.isEmpty) return items;
  final combined = PGTradeoff(
    headline: names.length == 1
        ? 'Declared allergen source: ${names.first}'
        : 'Declared allergen sources: ${names.join(", ")}',
  );
  remaining.insert(insertAt.clamp(0, remaining.length), combined);
  return remaining;
}

Widget? _buildSafetySummary(List<dynamic>? inactiveIngredients) {
  final severity = countInactiveSeverity(inactiveIngredients);
  if (!severity.shouldShowSummary) return null;
  return _SafetySummaryBullet(
    count: severity.total,
    names: severity.names,
    isHighSeverity: severity.high >= 1,
  );
}

class InactiveSeverityCount {
  final int high;
  final int moderate;

  /// Names of the flagged ingredients, in list order, so the summary can
  /// say *which* ingredient was flagged instead of a bare count.
  final List<String> names;

  const InactiveSeverityCount({
    required this.high,
    required this.moderate,
    required this.names,
  });

  int get total => high + moderate;

  bool get shouldShowSummary => high >= 1 || moderate >= 3 || total >= 2;
}

@visibleForTesting
InactiveSeverityCount countInactiveSeverity(
  List<dynamic>? inactiveIngredients,
) {
  var high = 0;
  var moderate = 0;
  final names = <String>[];

  void recordName(Map<String, dynamic> ing) {
    final name = _stringValue(ing['name'] ?? ing['raw_source_text']);
    if (name != null) names.add(name);
  }

  for (final raw in inactiveIngredients ?? const []) {
    if (raw is! Map) continue;
    final ing = Map<String, dynamic>.from(raw);
    // Classify via the SAME canonical tone the color dot uses
    // ([inactiveColorRank]: display_tone-first, then severity_status, then
    // harmful_severity). Reading severity_status directly over-elevated every
    // moderate additive: the pipeline maps high/moderate additives to
    // severity_status=critical (a coarse conservative value for the CI audit /
    // stash-less fallback), so a moderate additive like polysorbate 80 —
    // display_tone=dark_orange, i.e. an orange dot — was miscounted as HIGH in
    // the summary bullet. Going through the shared tone keeps the bullet and
    // the dot in agreement while preserving the conservative fallback for
    // display_tone-less (stale-cache) blobs.
    switch (inactiveColorRank(ing)) {
      case InactiveTone.red:
        high++;
        recordName(ing);
        break;
      case InactiveTone.orange:
        moderate++;
        recordName(ing);
        break;
      case InactiveTone.yellow:
      case InactiveTone.green:
        // low-penalty (amber) / benign (green) — not a summary-worthy flag.
        break;
    }
  }
  return InactiveSeverityCount(high: high, moderate: moderate, names: names);
}

class _SafetySummaryBullet extends StatelessWidget {
  final int count;
  final List<String> names;
  final bool isHighSeverity;

  const _SafetySummaryBullet({
    required this.count,
    required this.names,
    required this.isHighSeverity,
  });

  /// Name the flagged ingredient(s) when we have names; fall back to a bare
  /// count otherwise. Pluralize on the real count, not a hardcoded "s".
  String _label() {
    final noun = count == 1 ? 'ingredient' : 'ingredients';
    if (names.isEmpty) {
      return '$count $noun flagged for safety — review the list';
    }
    return '${names.join(', ')} flagged for safety — review the list';
  }

  @override
  Widget build(BuildContext context) {
    final dotColor = isHighSeverity ? context.v2.contraindicated : context.v2.avoid;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6, right: V2Spacing.space8),
          child: Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
        ),
        Expanded(
          child: Text(
            _label(),
            style: V2Typography.bodySm(
              color: context.v2.fg,
            ).copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
