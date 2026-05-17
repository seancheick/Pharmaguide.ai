// Phase 11.7d.2 — Ingredients section adapter.
//
// V2 mirror of production's `_CollapsibleIngredients` + `IngredientsCard`
// composition (lines 2043-2061, 2190-2419 in).
//
// Composition preserved verbatim:
//   • PGIngredientsCard wraps both active + inactive sub-sections
//   • Active sub-section: PGActiveIngredientsSection (auto-expand ≤5)
//   • Active list ordering (FLTR-9 + T16.2f blend grouping):
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
//   • Inactive tile tap is DEFERRED to a v2 component enhancement —
//     production's _FunctionalRolesSheet is private; surfacing requires
//     extracting it to a public function. Tracked as S6.next-iteration
//     in parity doc.
//
// Architecture note: this file IS larger than the 250-line target
// because of the blend-bucket header widget + composition logic.
// Sean approved slight overruns when structure is clean
// (helpers = pure mapping, section = widget composition).

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
import 'package:pharmaguide/features/product_detail/widgets/ingredient_explain_sheet.dart';

/// Build the Ingredients section. Composes:
///   - Active list: PGActiveIngredientsSection wrapping tiles built from
///     `blob.ingredients` (sorted + blend-grouped)
///   - Inactive list: PGIngredientsCard's built-in inactive section
///     using PGInactiveIngredient list from `blob.inactive_ingredients`
///
/// Returns `SizedBox.shrink()` when both lists are empty. Production
/// has a legacy `ingredients_summary` free-text fallback for blobs
/// without structured lists — DEFERRED to a future v2 enhancement
/// (rare, pre-v1.5.0 pipeline blobs only).
Widget buildIngredientsSection({
  required BuildContext context,
  required List<Map<String, dynamic>> ingredients,
  required List<Map<String, dynamic>> inactiveIngredients,
  required List<Map<String, dynamic>>? ulAnalysis,
  required List<Map<String, dynamic>>? blends,
}) {
  final hasActive = ingredients.isNotEmpty;
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
      ingredients: ingredients,
      ulAnalysis: ulAnalysis,
      blends: blends,
    );
    if (tiles.isNotEmpty) {
      activeContent = PGActiveIngredientsSection(tiles: tiles);
    }
  }

  // -------------------------------------------------------------
  // Map inactive list — filter out rows missing both name and raw text.
  // -------------------------------------------------------------
  final inactiveMapped = inactiveIngredients
      .where(
        (m) =>
            (m['name']?.toString().isNotEmpty == true) ||
            (m['raw_source_text']?.toString().isNotEmpty == true),
      )
      .map(inactiveFromMap)
      .toList(growable: false);

  return PGIngredientsCard(
    activeContent: activeContent,
    inactiveIngredients: inactiveMapped,
    // onInactiveTap deferred — production's _FunctionalRolesSheet is
    // private. Tracked as S6.next-iteration in parity doc.
    onInactiveTap: null,
  );
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
        _tileFor(
          context: context,
          ingredient: sorted[i],
          ulAnalysis: ulAnalysis,
          showBottomDivider: i != sorted.length - 1,
        ),
    ];
  }

  // T16.2f — 3-section render order with blend buckets.
  final tiles = <Widget>[];

  for (final ing in grouped.looseDisclosed) {
    tiles.add(_tileFor(
      context: context,
      ingredient: ing,
      ulAnalysis: ulAnalysis,
    ));
  }

  for (final blend in grouped.blends) {
    tiles.add(_BlendHeaderRow(blend: blend));
    for (final child in blend.children) {
      tiles.add(
        Padding(
          padding: const EdgeInsets.only(left: V2Spacing.space16),
          child: _tileFor(
            context: context,
            ingredient: child,
            ulAnalysis: ulAnalysis,
          ),
        ),
      );
    }
  }

  for (final ing in grouped.looseUndisclosed) {
    tiles.add(_tileFor(
      context: context,
      ingredient: ing,
      ulAnalysis: ulAnalysis,
    ));
  }

  return tiles;
}

/// Build a single active tile. Wires tap → production's
/// `showIngredientExplainSheet` (verbatim port — same modal copy
/// production uses, opened via showModalBottomSheet).
Widget _tileFor({
  required BuildContext context,
  required Map<String, dynamic> ingredient,
  required List<Map<String, dynamic>>? ulAnalysis,
  bool showBottomDivider = true,
}) {
  final ulEntry = matchUlEntry(ingredient, ulAnalysis);
  final typed = activeFromMap(ingredient, ulEntry: ulEntry);
  return PGActiveIngredientTile(
    ingredient: typed,
    showBottomDivider: showBottomDivider,
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

  const _BlendHeaderRow({required this.blend});

  @override
  Widget build(BuildContext context) {
    final hasTotal = blend.totalAmount != null && blend.unit.isNotEmpty;
    final totalLabel = hasTotal
        ? '${blend.totalAmount} ${blend.unit}'
        : 'Amount not disclosed';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: V2Spacing.space8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(
            Icons.layers_outlined,
            size: 14,
            color: V2Colors.fgMuted,
          ),
          const SizedBox(width: V2Spacing.space8),
          Expanded(
            child: Text(
              blend.name,
              style: V2Typography.bodyMedium(color: V2Colors.fg),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            totalLabel,
            style: V2Typography.monoData(color: V2Colors.fgMuted),
          ),
        ],
      ),
    );
  }
}
