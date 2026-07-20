// Proprietary blend grouping for the active-ingredient list.
//
// Spec: INITIATIVE_PRODUCT_DETAIL_CLEANUP.md, Sprint S2.2, T16.2f.
//
// Sean's PureLean live walkthrough caught the gap: the pipeline emits
// `proprietary_blend_detail.blends[]` with named blends + child-
// ingredient lists, but the active-ingredients renderer rendered every
// active flat. Visually, Lutein / Lycopene / Zeaxanthin / Orleans
// Strawberry / Cranberry all read as standalone undisclosed-dose actives
// — there's no signal they share a parent blend or that the blend has a
// disclosed total. The supplement label renders these label-style:
//
//   Eye Health Blend            100 mg
//     Lutein
//     Lycopene
//     Zeaxanthin
//     Orleans Strawberry
//     Cranberry
//
// This module groups the flat active list into:
//   1. Loose disclosed-dose actives (preserves existing FLTR-9 sort)
//   2. Per-blend buckets (header + child rows in pipeline order)
//   3. Loose undisclosed actives (preserves existing FLTR-9 sort)
//
// Pure / framework-free → unit-testable. Renderer composes the result.
//
// Match rule: an ingredient is a blend member when its name (after
// the same canonicalization the threshold table uses) matches any
// `child_ingredients[].name` of a blend. We use the existing
// `canonicalizeIngredientName` so display drift (`Lutein` vs
// `Lutein, Free Form` vs `Lutein (FloraGLO)`) all resolve to the same
// match key after T16.2e's punctuation strip.

library;

import 'package:pharmaguide/services/ingredients/ingredient_canonicalizer.dart';

/// One proprietary blend extracted from the pipeline.
class BlendGroup {
  /// Display name from the supplement label, e.g. "Eye Health Blend".
  final String name;

  /// Total disclosed dose, e.g. `100`. Null when the pipeline didn't
  /// emit a total (rare — almost all blends disclose at least the
  /// total even when child amounts are hidden).
  final num? totalAmount;

  /// Unit for [totalAmount], e.g. `"mg"`. Empty string when no total.
  final String unit;

  /// Children in pipeline order (same order as the supplement-facts
  /// label). Each entry is the raw ingredient map from the actives
  /// list — renderer can pass it directly to its tile widget.
  final List<Map<String, dynamic>> children;

  /// Number of child ingredients listed in the blend disclosure. This
  /// can be greater than [children.length] when the active list uses the
  /// strict scoring contract and blend members are no longer exported as
  /// primary active rows.
  final int childCount;

  const BlendGroup({
    required this.name,
    required this.totalAmount,
    required this.unit,
    required this.children,
    this.childCount = 0,
  });
}

/// Result of grouping the active list against the blend metadata.
class GroupedActives {
  /// Loose disclosed-dose actives (sorted by FLTR-9). Renders first.
  final List<Map<String, dynamic>> looseDisclosed;

  /// Blends with at least one matched child. Renders after [looseDisclosed].
  final List<BlendGroup> blends;

  /// Loose undisclosed actives (sorted by FLTR-9). Renders last.
  final List<Map<String, dynamic>> looseUndisclosed;

  const GroupedActives({
    required this.looseDisclosed,
    required this.blends,
    required this.looseUndisclosed,
  });

  /// True iff there's at least one blend bucket or disclosure summary.
  /// When false, the renderer can fall through to flat rendering for
  /// back-compat / lighter widget trees.
  bool get hasBlends => blends.isNotEmpty;
}

/// Group the flat active list into loose + blend buckets.
///
/// [ingredients] — pipeline's `detail_blob.ingredients` (active list).
/// [blendsRaw] — pipeline's `detail_blob.proprietary_blend_detail.blends[]`,
/// or null when the product has no blends. Each entry should have
/// `name`, `total_weight`, `unit`, and `child_ingredients` keys.
///
/// Returns a [GroupedActives] partitioning the input.
///
/// Edge cases:
///   - [blendsRaw] null/empty → all ingredients fall into loose buckets.
///   - Blend with no matching children → omitted from result (would
///     render as an empty bucket, which is noise).
///   - An ingredient matches multiple blends → first match wins
///     (defensive — the pipeline doesn't currently emit overlap).
///   - Blend `total_weight` is null but children list is present → still
///     render the bucket, just without a total in the header.
GroupedActives groupActivesByBlend({
  required List<Map<String, dynamic>> ingredients,
  required List<Map<String, dynamic>>? blendsRaw,
}) {
  if (blendsRaw == null || blendsRaw.isEmpty) {
    return GroupedActives(
      looseDisclosed: _disclosed(ingredients),
      blends: const [],
      looseUndisclosed: _undisclosed(ingredients),
    );
  }

  // Build (canonical_name, hasAmount) → blend-index lookup. First
  // write wins on overlap (rare).
  //
  // T16.2f revision (2026-04-30, post-pipeline-confirmation) — the
  // disclosure-status flag is part of the match key. Pipeline ships
  // 95.3% blends as `disclosure_level: none` (children all `amount:
  // null`), 2.9% partial (some disclosed), 1.9% full (all disclosed) —
  // 214/32,736 child rows ship a real amount + unit. Without the
  // hasAmount flag we'd either:
  //   (a) bucket disclosed standalone ingredients into a same-name
  //       blend's undisclosed slot (PureLean Zeaxanthin bug, 1% of
  //       products), OR
  //   (b) miss bucketing disclosed actives entries that ARE blend
  //       members in partial/full blends (CLA 770 mg in Tonalin
  //       Complex, etc — 4.7% of blends).
  //
  // Match key (canonical, hasAmount) handles both:
  //   - blend child Zeaxanthin/null → ('zeaxanthin', false). Actives
  //     Zeaxanthin/0 → key ('zeaxanthin', false) → match. Actives
  //     Zeaxanthin/500mcg → key ('zeaxanthin', true) → no match → loose.
  //   - blend child CLA/770mg → ('cla', true). Actives CLA/770mg → key
  //     ('cla', true) → match. Standalone CLA at a different dose still
  //     matches the same key — pipeline shouldn't emit conflicting
  //     amounts; if it does, first-wins on the actives side.
  final ingredientToBlend = <(String, bool), int>{};
  for (var i = 0; i < blendsRaw.length; i++) {
    final blend = blendsRaw[i];
    final children = blend['child_ingredients'];
    if (children is! List) continue;
    for (final c in children) {
      if (c is! Map) continue;
      final name = c['name']?.toString();
      if (name == null || name.trim().isEmpty) continue;
      final canonical = canonicalizeIngredientName(name);
      if (canonical.isEmpty) continue;
      final amount = c['amount'];
      final hasAmount = amount is num && amount > 0;
      ingredientToBlend.putIfAbsent((canonical, hasAmount), () => i);
    }
  }

  // Buckets: per-blend list of matched children, plus loose ingredients.
  final blendBuckets = List<List<Map<String, dynamic>>>.generate(
    blendsRaw.length,
    (_) => <Map<String, dynamic>>[],
  );
  final activeIngredientKeys = <(String, bool)>{};
  final loose = <Map<String, dynamic>>[];

  for (final ing in ingredients) {
    final rawName =
        (ing['name'] ?? ing['standard_name'] ?? ing['raw_source_text'])
            ?.toString();
    final canonical = rawName == null || rawName.isEmpty
        ? ''
        : canonicalizeIngredientName(rawName);

    final qty = ing['quantity'];
    final isDisclosed = qty is num && qty > 0;
    if (canonical.isNotEmpty) {
      activeIngredientKeys.add((canonical, isDisclosed));
    }

    final blendIdx = canonical.isEmpty
        ? null
        : ingredientToBlend[(canonical, isDisclosed)];

    if (blendIdx == null) {
      loose.add(ing);
    } else {
      blendBuckets[blendIdx].add(ing);
    }
  }

  // Materialize blend groups. When a blend has disclosed children but
  // none are present in `ingredients`, keep a summary row so strict
  // primary-active exports do not hide blend disclosure.
  final blends = <BlendGroup>[];
  for (var i = 0; i < blendsRaw.length; i++) {
    final children = blendBuckets[i];
    final blend = blendsRaw[i];
    final rawChildCount = _blendChildCount(blend);
    if (children.isEmpty &&
        (rawChildCount == 0 ||
            _blendHasAnyPresentChild(blend, activeIngredientKeys))) {
      continue;
    }
    final displayChildren = _orderedBlendChildren(blend, children);
    blends.add(
      BlendGroup(
        name: blend['name']?.toString() ?? 'Proprietary Blend',
        totalAmount: blend['total_weight'] is num
            ? blend['total_weight'] as num
            : null,
        unit: blend['unit']?.toString() ?? '',
        children: displayChildren,
        childCount: rawChildCount > 0 ? rawChildCount : displayChildren.length,
      ),
    );
  }

  return GroupedActives(
    looseDisclosed: _disclosed(loose),
    blends: blends,
    looseUndisclosed: _undisclosed(loose),
  );
}

List<Map<String, dynamic>> _orderedBlendChildren(
  Map<String, dynamic> blend,
  List<Map<String, dynamic>> matchedChildren,
) {
  final rawChildren = blend['child_ingredients'];
  if (rawChildren is! List) return matchedChildren;

  final ordered = List<Map<String, dynamic>>.from(matchedChildren);
  final matchedCounts = <(String, bool), int>{};
  for (final child in matchedChildren) {
    final candidateName =
        (child['name'] ?? child['standard_name'] ?? child['raw_source_text'])
            ?.toString() ??
        '';
    final quantity = child['quantity'];
    final key = (
      canonicalizeIngredientName(candidateName),
      quantity is num && quantity > 0,
    );
    matchedCounts[key] = (matchedCounts[key] ?? 0) + 1;
  }
  for (final raw in rawChildren) {
    if (raw is! Map) continue;
    final name = raw['name']?.toString().trim() ?? '';
    if (name.isEmpty) continue;
    final canonical = canonicalizeIngredientName(name);
    final amount = raw['amount'];
    final hasAmount = amount is num && amount > 0;
    final key = (canonical, hasAmount);
    final matchedCount = matchedCounts[key] ?? 0;
    if (matchedCount > 0) {
      matchedCounts[key] = matchedCount - 1;
      continue;
    }

    final unit = raw['unit']?.toString().trim() ?? '';
    final doseLabel = hasAmount && unit.isNotEmpty
        ? '$amount $unit'
        : 'Amount not disclosed';
    ordered.add({
      'name': name,
      'raw_source_text': name,
      'display_label': name,
      'quantity': hasAmount ? amount : null,
      'unit': unit,
      'display_dose_label': doseLabel,
      'dose_status': hasAmount ? 'disclosed' : 'not_disclosed_blend',
      'score_included': false,
      'is_label_context': true,
      'is_blend_child': true,
    });
  }
  return ordered;
}

int _blendChildCount(Map<String, dynamic> blend) {
  final children = blend['child_ingredients'];
  if (children is! List) return 0;
  var count = 0;
  for (final child in children) {
    if (child is! Map) continue;
    final name = child['name']?.toString().trim() ?? '';
    if (name.isNotEmpty) count++;
  }
  return count;
}

bool _blendHasAnyPresentChild(
  Map<String, dynamic> blend,
  Set<(String, bool)> activeIngredientKeys,
) {
  final children = blend['child_ingredients'];
  if (children is! List) return false;
  for (final child in children) {
    if (child is! Map) continue;
    final name = child['name']?.toString().trim() ?? '';
    if (name.isEmpty) continue;
    final canonical = canonicalizeIngredientName(name);
    if (canonical.isEmpty) continue;
    final amount = child['amount'];
    final hasAmount = amount is num && amount > 0;
    if (activeIngredientKeys.contains((canonical, hasAmount))) return true;
  }
  return false;
}

List<Map<String, dynamic>> _disclosed(List<Map<String, dynamic>> ings) {
  return ings
      .where((ing) {
        final qty = ing['quantity'];
        return qty is num && qty > 0;
      })
      .toList(growable: false);
}

List<Map<String, dynamic>> _undisclosed(List<Map<String, dynamic>> ings) {
  return ings
      .where((ing) {
        final qty = ing['quantity'];
        return !(qty is num && qty > 0);
      })
      .toList(growable: false);
}
