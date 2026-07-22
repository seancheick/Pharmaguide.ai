// Ingredients section adapter for Product Detail v2 — the canonical
// ingredients surface after the Phase 11.11 hygiene pass removed the
// v1 IngredientsCard. The canonical path renders the label ledger; stale
// blobs retain the earlier active + inactive compatibility layout.
//
// Composition:
//   • PGIngredientsCard wraps both active + inactive sub-sections
//   • Active sub-section: PGActiveIngredientsSection (auto-expand ≤5)
//   • Canonical ledger ordering: source order, without analysis regrouping
//   • Legacy active list ordering (FLTR-9 + T16.2f blend grouping):
//     1. Loose disclosed-dose actives (sorted)
//     2. Per-blend bucket: header row + indented children
//     3. Loose undisclosed-dose actives (sorted)
//   • Each tile taps to `showIngredientExplainSheet` (production sheet,
//     reused verbatim)
//   • Inactive sub-section: collapsible header, color-dot rows, role
//     helper line
//
// Sean's rules (2026-05-15):
//   • Active/inactive patterns preserved (Sean's specific call):
//     - Collapsible header with auto-expand ≤5
//     - Active sort: disclosed → blend → undisclosed (FLTR-9)
//     - Inactive color dots via inactiveColorRank
//     - Blend buckets with indented children (T16.2f)
//   • Provider helpers used verbatim: groupActivesByBlend,
//     sortActivesForDisplay, matchUlEntry.
//   • Active tile tap opens production's showIngredientExplainSheet
//     (same modal copy, same data path).
//   • Inactive tile tap opens the functional-roles sheet via the
//     public `showFunctionalRolesSheet` helper.
//
// Architecture note: this file IS larger than the 250-line target
// because of the blend-bucket header widget + composition logic.
// Sean approved slight overruns when structure is clean
// (helpers = pure mapping, section = widget composition).

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_ingredient_tile.dart';
import 'package:pharmaguide/core/components/pg_ingredients_card.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/features/product_detail/blend_grouping.dart';
import 'package:pharmaguide/features/product_detail/dose_safety.dart';
import 'package:pharmaguide/features/product_detail/ingredient_sort.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/ingredients_helpers.dart';
import 'package:pharmaguide/features/product_detail/widgets/functional_roles_sheet.dart';
import 'package:pharmaguide/features/product_detail/widgets/ingredient_explain_sheet.dart';
import 'package:pharmaguide/services/ingredients/elemental_form_dedupe.dart';
import 'package:pharmaguide/services/ingredients/ingredient_canonicalizer.dart';

/// Whether [buildIngredientsSection] can mount a meaningful active-label row
/// for disclosure navigation from the same builder inputs.
///
/// A present canonical ledger is authoritative, including when it is empty.
/// Legacy blend metadata alone is not a target: at least one deduped active
/// ingredient must render as an active tile.
bool hasIngredientDisclosureTarget({
  required List<Map<String, dynamic>> ingredients,
  required List<Map<String, dynamic>>? displayIngredients,
  required List<Map<String, dynamic>>? blends,
}) {
  if (displayIngredients != null) {
    final rowsBySourcePath = _rowsBySourcePath(displayIngredients);
    return _ledgerRowsForSection(
      displayIngredients,
      _LedgerSection.active,
      rowsBySourcePath,
    ).any(_isCanonicalDisclosureTargetRenderable);
  }

  final dedupedActives = dedupeElementalCompoundRows(ingredients);
  if (dedupedActives.isEmpty) return false;
  final grouped = groupActivesByBlend(
    ingredients: dedupedActives,
    blendsRaw: blends,
  );
  if (!grouped.hasBlends) return true;
  return grouped.looseDisclosed.isNotEmpty ||
      grouped.looseUndisclosed.isNotEmpty ||
      grouped.blends.any(_blendHasRenderedActiveTile);
}

Map<String, Map<String, dynamic>> _rowsBySourcePath(
  List<Map<String, dynamic>> rows,
) => <String, Map<String, dynamic>>{
  for (final row in rows)
    if (row['raw_source_path']?.toString().trim().isNotEmpty == true)
      row['raw_source_path'].toString(): row,
};

/// Nutrition facts from the canonical label ledger, preserving source order
/// and nested macro rows while excluding nutrition-typed children whose root
/// belongs to an active ingredient (for example Total Omega-3 under Fish Oil).
List<Map<String, dynamic>> labelNutritionRowsForDisplayLedger(
  List<Map<String, dynamic>>? rows,
) {
  if (rows == null || rows.isEmpty) return const [];
  final rowsBySourcePath = _rowsBySourcePath(rows);
  return _ledgerRowsForSection(
    rows,
    _LedgerSection.nutrition,
    rowsBySourcePath,
  );
}

List<Map<String, dynamic>> _ledgerRowsForSection(
  List<Map<String, dynamic>> rows,
  _LedgerSection section,
  Map<String, Map<String, dynamic>> rowsBySourcePath,
) => rows
    .where((row) => _ledgerSectionForRow(row, rowsBySourcePath) == section)
    .toList(growable: false);

bool _blendHasRenderedActiveTile(BlendGroup blend) =>
    blend.children.any((child) => child['is_label_context'] != true);

int? _canonicalDisclosureTargetIndex(
  List<Map<String, dynamic>> activeRows,
  List<Map<String, dynamic>>? blends,
) {
  if (activeRows.isEmpty) return null;
  final blendNames = <String>{
    for (final blend in blends ?? const <Map<String, dynamic>>[])
      if (_normalizedDisclosureLabel(blend['name']).isNotEmpty)
        _normalizedDisclosureLabel(blend['name']),
  };
  final preferredIndex = activeRows.indexWhere((row) {
    if (!_isCanonicalDisclosureTargetRenderable(row)) return false;
    if (row['display_type']?.toString() == 'structural_container') {
      return true;
    }
    final label = _canonicalRowDisplayLabel(row);
    return blendNames.contains(label);
  });
  if (preferredIndex >= 0) return preferredIndex;
  final fallbackIndex = activeRows.indexWhere(
    _isCanonicalDisclosureTargetRenderable,
  );
  return fallbackIndex >= 0 ? fallbackIndex : null;
}

bool _isCanonicalDisclosureTargetRenderable(Map<String, dynamic> row) =>
    _canonicalRowDisplayLabel(row).isNotEmpty;

String _canonicalRowDisplayLabel(Map<String, dynamic> row) {
  for (final field in const [
    'label_display_name',
    'display_label',
    'display_name',
    'raw_source_text',
  ]) {
    final normalized = _normalizedDisclosureLabel(row[field]);
    if (normalized.isNotEmpty) return normalized;
  }
  return '';
}

String _normalizedDisclosureLabel(Object? value) {
  final withoutBrandMarks = value?.toString().replaceAll(RegExp(r'[™®©℠]'), '');
  return canonicalizeIngredientName(
    withoutBrandMarks ?? '',
    applyAliases: false,
  );
}

/// Build the Ingredients section. Composes:
///   - Canonical label path: tiles built from `blob.display_ingredients` in
///     ledger order, without sorting, deduping, or analysis regrouping
///   - Legacy path: PGActiveIngredientsSection wrapping tiles built from
///     `blob.ingredients` (sorted + blend-grouped) only when the ledger is
///     absent
///   - Inactive list: PGIngredientsCard's built-in inactive section
///     using PGInactiveIngredient list from `blob.inactive_ingredients`
///
/// Returns `SizedBox.shrink()` when both lists are empty. Production
/// has a legacy `ingredients_summary` free-text fallback for blobs
/// without structured lists — DEFERRED to a future v2 enhancement
/// (rare, pre-v1.5.0 pipeline blobs only).
Widget buildIngredientsSection({
  Key? key,
  required BuildContext context,
  required List<Map<String, dynamic>> ingredients,
  List<Map<String, dynamic>>? displayIngredients,
  required List<Map<String, dynamic>> inactiveIngredients,
  required List<Map<String, dynamic>>? ulAnalysis,
  required List<Map<String, dynamic>>? blends,
  GlobalKey? disclosureTargetKey,
  ValueListenable<bool>? disclosureRevealSignal,
}) {
  // Null means the canonical ledger contract is absent (a stale blob), so the
  // legacy score-oriented lists remain the explicit compatibility fallback.
  // A present but empty ledger must stay empty: falling back in that case
  // would let scored rows masquerade as source-label rows.
  if (displayIngredients != null) {
    return _CanonicalLedgerIngredients(
      key: key,
      ingredients: displayIngredients,
      inactiveIngredients: inactiveIngredients,
      ulAnalysis: ulAnalysis,
      blends: blends,
      disclosureTargetKey: disclosureTargetKey,
      disclosureRevealSignal: disclosureRevealSignal,
    );
  }

  // Elemental vs compound dedupe (verified pipeline bug, dsld_id
  // 315678): the blob can carry both an elemental row ('Magnesium',
  // 60 mg — the true dose) and a compound-weight row ('Magnesium
  // Glycinate', 400 mg) for the same canonical_id. Render ONE row —
  // the elemental dose with the compound as form context ('Magnesium
  // (as Magnesium Glycinate)') and a single form-quality badge.
  // Genuine multi-form labels (no bare elemental sibling) pass through.
  final dedupedActives = dedupeElementalCompoundRows(ingredients);

  final hasBlendDisclosure = blends?.isNotEmpty == true;
  final hasActive = dedupedActives.isNotEmpty || hasBlendDisclosure;
  final hasInactive = inactiveIngredients.any(
    (m) =>
        (m['name']?.toString().isNotEmpty == true) ||
        (m['raw_source_text']?.toString().isNotEmpty == true),
  );

  if (!hasActive && !hasInactive) return const SizedBox.shrink();

  // -------------------------------------------------------------
  // Build active tiles — flat OR blend-grouped per T16.2f.
  // -------------------------------------------------------------
  Widget? activeContent;
  if (hasActive) {
    final tiles = _buildActiveTiles(
      context: context,
      ingredients: dedupedActives,
      ulAnalysis: ulAnalysis,
      blends: blends,
      disclosureTargetKey: disclosureTargetKey,
    );
    if (tiles.isNotEmpty) {
      activeContent = PGActiveIngredientsSection(
        tiles: tiles,
        revealSignal: disclosureRevealSignal,
      );
    }
  }

  // -------------------------------------------------------------
  // Map inactive list — filter out rows missing both name and raw
  // text. Keep the filtered raw maps so the tap handler can pass the
  // original pipeline shape (with `functional_roles[]`) into the
  // sheet — `inactiveFromMap` drops that field.
  // -------------------------------------------------------------
  final filteredRawInactive = inactiveIngredients
      .where(
        (m) =>
            (m['name']?.toString().isNotEmpty == true) ||
            (m['raw_source_text']?.toString().isNotEmpty == true),
      )
      .toList(growable: false);
  final inactiveMapped = filteredRawInactive
      .map(inactiveFromMap)
      .toList(growable: false);

  return PGIngredientsCard(
    activeContent: activeContent,
    inactiveIngredients: inactiveMapped,
    onInactiveTap: (index) =>
        showFunctionalRolesSheet(context, filteredRawInactive[index]),
  );
}

class _CanonicalLedgerIngredients extends StatelessWidget {
  final List<Map<String, dynamic>> ingredients;
  final List<Map<String, dynamic>> inactiveIngredients;
  final List<Map<String, dynamic>>? ulAnalysis;
  final List<Map<String, dynamic>>? blends;
  final GlobalKey? disclosureTargetKey;
  final ValueListenable<bool>? disclosureRevealSignal;

  const _CanonicalLedgerIngredients({
    super.key,
    required this.ingredients,
    required this.inactiveIngredients,
    required this.ulAnalysis,
    required this.blends,
    required this.disclosureTargetKey,
    required this.disclosureRevealSignal,
  });

  @override
  Widget build(BuildContext context) {
    final labelRows = ingredients;
    if (labelRows.isEmpty) return const SizedBox.shrink();

    // One bottle-faithful label view: Nutrition facts / Active / Other. The
    // scoring engine keeps its own score_included representation internally;
    // there is no consumer-facing "Analysis" projection.
    final rowsBySourcePath = _rowsBySourcePath(labelRows);
    List<Map<String, dynamic>> rowsFor(_LedgerSection section) =>
        _ledgerRowsForSection(labelRows, section, rowsBySourcePath);
    final otherRows = rowsFor(_LedgerSection.other);
    final activeRows = rowsFor(_LedgerSection.active);
    final canonicalInactiveRows = _canonicalInactiveRows(
      otherRows,
      inactiveIngredients,
    );
    final canonicalInactiveIngredients = canonicalInactiveRows
        .map(inactiveFromMap)
        .toList(growable: false);
    final disclosureTargetIndex = _canonicalDisclosureTargetIndex(
      activeRows,
      blends,
    );

    Widget ledgerSection(
      String title,
      List<Map<String, dynamic>> rows, {
      bool navigableDisclosure = false,
    }) {
      return PGActiveIngredientsSection(
        title: title,
        tiles: _buildLabelLedgerTiles(
          context: context,
          ingredients: rows,
          ulAnalysis: ulAnalysis,
          disclosureTargetKey: navigableDisclosure ? disclosureTargetKey : null,
          disclosureTargetIndex: navigableDisclosure
              ? disclosureTargetIndex
              : null,
        ),
        revealSignal: navigableDisclosure ? disclosureRevealSignal : null,
      );
    }

    final sections = [
      if (activeRows.isNotEmpty)
        ledgerSection(
          'Active ingredients',
          activeRows,
          navigableDisclosure: true,
        ),
    ];

    return PGIngredientsCard(
      activeContent: sections.isEmpty
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var index = 0; index < sections.length; index++) ...[
                  sections[index],
                  if (index != sections.length - 1)
                    const Padding(
                      padding: EdgeInsets.symmetric(
                        vertical: V2Spacing.space12,
                      ),
                      child: Divider(
                        height: 0.5,
                        thickness: 0.5,
                        color: V2Colors.outline,
                      ),
                    ),
                ],
              ],
            ),
      inactiveIngredients: canonicalInactiveIngredients,
      onInactiveTap: (index) =>
          showFunctionalRolesSheet(context, canonicalInactiveRows[index]),
    );
  }
}

List<Map<String, dynamic>> _canonicalInactiveRows(
  List<Map<String, dynamic>> labelRows,
  List<Map<String, dynamic>> inactiveRows,
) {
  final consumed = <int>{};
  return labelRows
      .map((labelRow) {
        final labelKey = _canonicalRowDisplayLabel(labelRow);
        var matchIndex = -1;
        for (var index = 0; index < inactiveRows.length; index++) {
          if (!consumed.contains(index) &&
              _inactiveRowDisplayLabel(inactiveRows[index]) == labelKey) {
            matchIndex = index;
            break;
          }
        }
        final merged = matchIndex < 0
            ? <String, dynamic>{}
            : Map<String, dynamic>.from(inactiveRows[matchIndex]);
        if (matchIndex >= 0) consumed.add(matchIndex);

        final literalLabel = _canonicalRowLiteralLabel(labelRow);
        merged['name'] = literalLabel;
        merged['label_display'] = literalLabel;
        merged['raw_source_text'] ??= labelRow['raw_source_text'];
        return merged;
      })
      .toList(growable: false);
}

String _inactiveRowDisplayLabel(Map<String, dynamic> row) {
  for (final field in const [
    'label_display',
    'name',
    'raw_source_text',
    'display_label',
  ]) {
    final normalized = _normalizedDisclosureLabel(row[field]);
    if (normalized.isNotEmpty) return normalized;
  }
  return '';
}

String _canonicalRowLiteralLabel(Map<String, dynamic> row) {
  for (final field in const [
    'label_display_name',
    'display_label',
    'display_name',
    'raw_source_text',
  ]) {
    final value = row[field]?.toString().trim();
    if (value != null && value.isNotEmpty) return value;
  }
  return 'Other ingredient';
}

enum _LedgerSection { nutrition, active, other }

_LedgerSection _ledgerSectionForRow(
  Map<String, dynamic> row,
  Map<String, Map<String, dynamic>> rowsBySourcePath,
) {
  final visitedPaths = <String>{};
  var root = row;
  while (true) {
    final parentPath = root['parent_source_path']?.toString().trim() ?? '';
    if (parentPath.isEmpty || !visitedPaths.add(parentPath)) break;
    final parent = rowsBySourcePath[parentPath];
    if (parent == null) break;
    root = parent;
  }

  final displayType = root['display_type']?.toString();
  final disposition = root['display_disposition']?.toString();
  if (displayType == 'inactive_ingredient' ||
      disposition == 'other_ingredient') {
    return _LedgerSection.other;
  }
  if (displayType == 'nutrition_fact') return _LedgerSection.nutrition;
  return _LedgerSection.active;
}

/// Build canonical label-ledger tiles exactly in the order emitted by the
/// pipeline. This path intentionally does not call elemental dedupe, dose
/// sorting, or blend grouping: hierarchy/context rows are part of the label
/// identity even when they do not participate in analysis.
List<Widget> _buildLabelLedgerTiles({
  required BuildContext context,
  required List<Map<String, dynamic>> ingredients,
  required List<Map<String, dynamic>>? ulAnalysis,
  GlobalKey? disclosureTargetKey,
  int? disclosureTargetIndex,
}) {
  final tiles = <Widget>[];
  for (var index = 0; index < ingredients.length; index++) {
    final ingredient = ingredients[index];
    final rawDepth = ingredient['nested_depth'];
    final depth = rawDepth is num
        ? rawDepth.toInt()
        : int.tryParse(rawDepth?.toString() ?? '') ?? 0;
    final parent = ingredient['parent_label']?.toString().trim();
    final hasParent = depth > 0 && parent != null && parent.isNotEmpty;
    final rowKey = index == disclosureTargetIndex ? disclosureTargetKey : null;
    if (!hasParent &&
        ingredient['display_type']?.toString() == 'structural_container') {
      final total = ingredient['quantity'];
      final childNames = ingredient['children'];
      tiles.add(
        _BlendHeaderRow(
          key: rowKey,
          blend: BlendGroup(
            name:
                (ingredient['label_display_name'] ??
                        ingredient['display_name'] ??
                        ingredient['raw_source_text'])
                    ?.toString() ??
                'Proprietary Blend',
            totalAmount: total is num ? total : null,
            unit: ingredient['unit']?.toString() ?? '',
            children: const [],
            childCount: childNames is List ? childNames.length : 0,
          ),
          exactAmountLabel: ingredient['exact_dose_text']?.toString(),
        ),
      );
      final rawVariants = ingredient['serving_variants'];
      if (rawVariants is List && rawVariants.length > 1) {
        final variants = rawVariants.whereType<Map<String, dynamic>>().toList(
          growable: false,
        );
        if (variants.length > 1) {
          tiles.add(_ServingVariantList(variants: variants));
        }
      }
      continue;
    }
    final tile = _tileFor(
      key: rowKey,
      context: context,
      ingredient: ingredient,
      ulAnalysis: ulAnalysis,
      showBottomDivider: index != ingredients.length - 1,
      showNestedIndent: !hasParent,
    );
    tiles.add(hasParent ? _HierarchyChild(child: tile) : tile);
  }
  return tiles;
}

/// Build the active tile widget list. T16.2f flow:
///   1. Group via groupActivesByBlend (uses pipeline blends data)
///   2. If no blends matched → flat list sorted by FLTR-9
///   3. If blends matched → loose-disclosed → blend buckets → loose-
///      undisclosed (each bucket has a label header + indented children)
List<Widget> _buildActiveTiles({
  required BuildContext context,
  required List<Map<String, dynamic>> ingredients,
  required List<Map<String, dynamic>>? ulAnalysis,
  required List<Map<String, dynamic>>? blends,
  GlobalKey? disclosureTargetKey,
}) {
  final grouped = groupActivesByBlend(
    ingredients: ingredients,
    blendsRaw: blends,
  );

  // No blends → pre-T16.2f flat layout.
  if (!grouped.hasBlends) {
    final sorted = sortActivesForDisplay(ingredients);
    return [
      for (var i = 0; i < sorted.length; i++)
        _ingredientEntry(
          context: context,
          ingredient: sorted[i],
          ulAnalysis: ulAnalysis,
          showBottomDivider: i != sorted.length - 1,
          key: i == 0 ? disclosureTargetKey : null,
        ),
    ];
  }

  // T16.2f — 3-section render order with blend buckets.
  final tiles = <Widget>[];
  final targetBlendIndex = disclosureTargetKey == null
      ? -1
      : grouped.blends.indexWhere(_blendHasRenderedActiveTile);
  var attachedFallbackTarget = false;

  Key? fallbackActiveTileKey() {
    if (disclosureTargetKey == null ||
        targetBlendIndex >= 0 ||
        attachedFallbackTarget) {
      return null;
    }
    attachedFallbackTarget = true;
    return disclosureTargetKey;
  }

  for (final ing in grouped.looseDisclosed) {
    tiles.add(
      _ingredientEntry(
        key: fallbackActiveTileKey(),
        context: context,
        ingredient: ing,
        ulAnalysis: ulAnalysis,
      ),
    );
  }

  for (var blendIndex = 0; blendIndex < grouped.blends.length; blendIndex++) {
    final blend = grouped.blends[blendIndex];
    tiles.add(
      _BlendHeaderRow(
        key: blendIndex == targetBlendIndex ? disclosureTargetKey : null,
        blend: blend,
      ),
    );
    for (final child in blend.children) {
      tiles.add(
        _HierarchyChild(
          child: child['is_label_context'] == true
              ? _LabelChildRow(component: child)
              : _tileFor(
                  key: fallbackActiveTileKey(),
                  context: context,
                  ingredient: child,
                  ulAnalysis: ulAnalysis,
                  showNestedIndent: false,
                ),
        ),
      );
    }
  }

  for (final ing in grouped.looseUndisclosed) {
    tiles.add(
      _ingredientEntry(
        key: fallbackActiveTileKey(),
        context: context,
        ingredient: ing,
        ulAnalysis: ulAnalysis,
      ),
    );
  }

  return tiles;
}

Widget _ingredientEntry({
  Key? key,
  required BuildContext context,
  required Map<String, dynamic> ingredient,
  required List<Map<String, dynamic>>? ulAnalysis,
  bool showBottomDivider = true,
}) {
  final rawComponents = ingredient['label_components'];
  final components = rawComponents is List
      ? rawComponents
            .whereType<Map<String, dynamic>>()
            .map(Map<String, dynamic>.from)
            .toList(growable: false)
      : const <Map<String, dynamic>>[];
  if (components.isEmpty) {
    return _tileFor(
      key: key,
      context: context,
      ingredient: ingredient,
      ulAnalysis: ulAnalysis,
      showBottomDivider: showBottomDivider,
    );
  }

  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _tileFor(
        key: key,
        context: context,
        ingredient: ingredient,
        ulAnalysis: ulAnalysis,
        showBottomDivider: false,
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: V2Spacing.space4),
        child: Text(
          'Forms on label',
          style: V2Typography.caption(
            color: V2Colors.fgSubtle,
          ).copyWith(fontWeight: FontWeight.w500, letterSpacing: 0.4),
        ),
      ),
      for (final component in components)
        _HierarchyChild(child: _LabelChildRow(component: component)),
      if (showBottomDivider)
        const Divider(height: 0.5, thickness: 0.5, color: V2Colors.outline),
    ],
  );
}

/// Build a single active tile. Wires tap → production's
/// `showIngredientExplainSheet` (verbatim port — same modal copy
/// production uses, opened via showModalBottomSheet).
Widget _tileFor({
  Key? key,
  required BuildContext context,
  required Map<String, dynamic> ingredient,
  required List<Map<String, dynamic>>? ulAnalysis,
  bool showBottomDivider = true,
  bool showNestedIndent = true,
}) {
  final ulEntry = matchUlEntry(ingredient, ulAnalysis);
  final typed = activeFromMap(ingredient, ulEntry: ulEntry);
  return PGActiveIngredientTile(
    key: key,
    ingredient: typed,
    showBottomDivider: showBottomDivider,
    showNestedIndent: showNestedIndent,
    onTap: () => showIngredientExplainSheet(
      context,
      ingredient: ingredient,
      ulEntry: ulEntry,
    ),
  );
}

/// v2 blend-bucket header row. Mirrors production's `_BlendHeaderTile`
/// (line 2374) — supplement-facts label format: bold blend name +
/// total dose ("Amount not disclosed" when missing).
class _BlendHeaderRow extends StatelessWidget {
  final BlendGroup blend;
  final String? exactAmountLabel;

  const _BlendHeaderRow({
    super.key,
    required this.blend,
    this.exactAmountLabel,
  });

  @override
  Widget build(BuildContext context) {
    final hasTotal = blend.totalAmount != null && blend.unit.isNotEmpty;
    final childCount = blend.childCount;
    final countLabel = childCount > 0
        ? '$childCount ${childCount == 1 ? 'ingredient' : 'ingredients'}'
        : null;
    final exactAmount = exactAmountLabel?.trim() ?? '';
    final amountLabel = exactAmount.isNotEmpty
        ? exactAmount
        : hasTotal
        ? '${blend.totalAmount} ${blend.unit}'
        : null;
    final totalLabel = amountLabel ?? 'Amount not disclosed';
    final hasUndisclosedChildren = blend.children.any((child) {
      final quantity = child['quantity'];
      return quantity is! num || quantity <= 0;
    });
    final helperLabel = [
      if (countLabel != null) countLabel,
      if (hasUndisclosedChildren) 'individual amounts not disclosed',
    ].join(' · ');

    return Semantics(
      container: true,
      header: true,
      label: 'Proprietary blend, ${blend.name}, $totalLabel, $helperLabel',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: V2Spacing.space8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.layers_outlined,
                  size: 14,
                  color: V2Colors.fgMuted,
                ),
                const SizedBox(width: V2Spacing.space8),
                Text(
                  'Proprietary blend',
                  style: V2Typography.caption(
                    color: V2Colors.fgSubtle,
                  ).copyWith(fontWeight: FontWeight.w500),
                ),
              ],
            ),
            const SizedBox(height: V2Spacing.space4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    blend.name,
                    style: V2Typography.bodyMedium(color: V2Colors.fg),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: V2Spacing.space8),
                Flexible(
                  child: Text(
                    totalLabel,
                    textAlign: TextAlign.end,
                    style: V2Typography.monoData(color: V2Colors.fgMuted),
                  ),
                ),
              ],
            ),
            if (helperLabel.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                helperLabel,
                style: V2Typography.caption(color: V2Colors.fgMuted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ServingVariantList extends StatelessWidget {
  final List<Map<String, dynamic>> variants;

  const _ServingVariantList({required this.variants});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Serving amounts on label',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          V2Spacing.space16,
          0,
          V2Spacing.space16,
          V2Spacing.space12,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: V2Colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Padding(
            padding: const EdgeInsets.all(V2Spacing.space12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Serving amounts on label',
                  style: V2Typography.caption(
                    color: V2Colors.fgMuted,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: V2Spacing.space8),
                for (var index = 0; index < variants.length; index++) ...[
                  _ServingVariantRow(variant: variants[index]),
                  if (index != variants.length - 1)
                    const SizedBox(height: V2Spacing.space8),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ServingVariantRow extends StatelessWidget {
  final Map<String, dynamic> variant;

  const _ServingVariantRow({required this.variant});

  @override
  Widget build(BuildContext context) {
    final note = variant['serving_note']?.toString().trim() ?? '';
    final dose = variant['exact_dose_text']?.toString().trim() ?? '';
    final isCanonical = variant['is_canonical'] == true;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (note.isNotEmpty)
                Text(note, style: V2Typography.bodySm(color: V2Colors.fg)),
              if (isCanonical)
                Text(
                  'Selected serving',
                  style: V2Typography.caption(color: V2Colors.accent),
                ),
            ],
          ),
        ),
        if (dose.isNotEmpty) ...[
          const SizedBox(width: V2Spacing.space12),
          Flexible(
            child: Text(
              dose,
              textAlign: TextAlign.end,
              style: V2Typography.bodySm(color: V2Colors.fgMuted),
            ),
          ),
        ],
      ],
    );
  }
}

class _HierarchyChild extends StatelessWidget {
  final Widget child;

  const _HierarchyChild({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: V2Spacing.space8),
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: V2Colors.outline, width: 1)),
      ),
      child: child,
    );
  }
}

class _LabelChildRow extends StatelessWidget {
  final Map<String, dynamic> component;

  const _LabelChildRow({required this.component});

  @override
  Widget build(BuildContext context) {
    final label =
        (component['label'] ?? component['display_label'] ?? component['name'])
            ?.toString()
            .trim() ??
        '';
    final form = component['form']?.toString().trim() ?? '';
    final dose = component['display_dose_label']?.toString().trim() ?? '';
    final showForm =
        form.isNotEmpty && form.toLowerCase() != label.toLowerCase();
    return Semantics(
      container: true,
      label: [
        label,
        if (showForm) form,
        if (dose.isNotEmpty) dose,
        'listed under parent ingredient',
      ].join(', '),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: V2Spacing.space8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: V2Typography.bodyMedium(color: V2Colors.fg),
                  ),
                  if (showForm) ...[
                    const SizedBox(height: 2),
                    Text(
                      form,
                      style: V2Typography.caption(color: V2Colors.fgMuted),
                    ),
                  ],
                ],
              ),
            ),
            if (dose.isNotEmpty) ...[
              const SizedBox(width: V2Spacing.space8),
              Flexible(
                child: Text(
                  dose,
                  textAlign: TextAlign.end,
                  style: V2Typography.monoData(
                    color: V2Colors.fgMuted,
                  ).copyWith(fontSize: 12),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
