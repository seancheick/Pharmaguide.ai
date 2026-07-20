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
}) {
  // Null means the canonical ledger contract is absent (a stale blob), so the
  // legacy score-oriented lists remain the explicit compatibility fallback.
  // A present but empty ledger must stay empty: falling back in that case
  // would let scored rows masquerade as source-label rows.
  if (displayIngredients != null) {
    return _CanonicalLedgerIngredients(
      key: key,
      ingredients: displayIngredients,
      ulAnalysis: ulAnalysis,
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

  final hasActive = dedupedActives.isNotEmpty;
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
    );
    if (tiles.isNotEmpty) {
      activeContent = PGActiveIngredientsSection(tiles: tiles);
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

/// The two truthful projections available only when the canonical label ledger
/// contract is present.
enum IngredientLedgerView { label, analysis }

class _CanonicalLedgerIngredients extends StatefulWidget {
  final List<Map<String, dynamic>> ingredients;
  final List<Map<String, dynamic>>? ulAnalysis;

  const _CanonicalLedgerIngredients({
    super.key,
    required this.ingredients,
    required this.ulAnalysis,
  });

  @override
  State<_CanonicalLedgerIngredients> createState() =>
      _CanonicalLedgerIngredientsState();
}

class _CanonicalLedgerIngredientsState
    extends State<_CanonicalLedgerIngredients> {
  IngredientLedgerView _selectedView = IngredientLedgerView.label;

  @override
  Widget build(BuildContext context) {
    final labelRows = widget.ingredients;
    if (labelRows.isEmpty) return const SizedBox.shrink();

    final analysisRows = labelRows
        .where((row) => row['score_included'] == true)
        .toList(growable: false);
    final visibleRows = _selectedView == IngredientLedgerView.label
        ? labelRows
        : analysisRows;

    return PGIngredientsCard(
      activeContent: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _IngredientLedgerViewControl(
            selectedView: _selectedView,
            labelCount: labelRows.length,
            analysisCount: analysisRows.length,
            onChanged: (view) => setState(() => _selectedView = view),
          ),
          const SizedBox(height: V2Spacing.space12),
          if (visibleRows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: V2Spacing.space8),
              child: Text(
                'No label rows are included in the product analysis.',
                style: V2Typography.bodySm(color: V2Colors.fgMuted),
              ),
            )
          else
            PGActiveIngredientsSection(
              key: ValueKey(_selectedView),
              tiles: _buildLabelLedgerTiles(
                context: context,
                ingredients: visibleRows,
                ulAnalysis: widget.ulAnalysis,
              ),
            ),
        ],
      ),
      // Other Ingredients are already represented in the canonical ledger.
      // Reusing the legacy inactive list here would duplicate label content.
      inactiveIngredients: const [],
    );
  }
}

class _IngredientLedgerViewControl extends StatelessWidget {
  final IngredientLedgerView selectedView;
  final int labelCount;
  final int analysisCount;
  final ValueChanged<IngredientLedgerView> onChanged;

  const _IngredientLedgerViewControl({
    required this.selectedView,
    required this.labelCount,
    required this.analysisCount,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Ingredient view',
      child: SegmentedButton<IngredientLedgerView>(
        segments: [
          ButtonSegment(
            value: IngredientLedgerView.label,
            label: Semantics(
              key: const ValueKey('ingredient-view-label'),
              label:
                  'Label view, $labelCount '
                  '${labelCount == 1 ? 'ingredient' : 'ingredients'}',
              excludeSemantics: true,
              child: Text('Label $labelCount'),
            ),
          ),
          ButtonSegment(
            value: IngredientLedgerView.analysis,
            label: Semantics(
              key: const ValueKey('ingredient-view-analysis'),
              label:
                  'Analysis view, $analysisCount '
                  '${analysisCount == 1 ? 'ingredient' : 'ingredients'}',
              excludeSemantics: true,
              child: Text('Analysis $analysisCount'),
            ),
          ),
        ],
        selected: {selectedView},
        onSelectionChanged: (selection) {
          if (selection.isNotEmpty) onChanged(selection.single);
        },
        showSelectedIcon: false,
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
          textStyle: WidgetStatePropertyAll(
            V2Typography.label(color: V2Colors.fg),
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? V2Colors.accent
                : V2Colors.fg,
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? V2Colors.accentTint
                : Colors.transparent,
          ),
        ),
      ),
    );
  }
}

/// Build canonical label-ledger tiles exactly in the order emitted by the
/// pipeline. This path intentionally does not call elemental dedupe, dose
/// sorting, or blend grouping: hierarchy/context rows are part of the label
/// identity even when they do not participate in analysis.
List<Widget> _buildLabelLedgerTiles({
  required BuildContext context,
  required List<Map<String, dynamic>> ingredients,
  required List<Map<String, dynamic>>? ulAnalysis,
}) {
  return [
    for (var index = 0; index < ingredients.length; index++)
      _tileFor(
        context: context,
        ingredient: ingredients[index],
        ulAnalysis: ulAnalysis,
        showBottomDivider: index != ingredients.length - 1,
      ),
  ];
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
    tiles.add(
      _tileFor(context: context, ingredient: ing, ulAnalysis: ulAnalysis),
    );
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
    tiles.add(
      _tileFor(context: context, ingredient: ing, ulAnalysis: ulAnalysis),
    );
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
    final childCount = blend.childCount;
    final countLabel = childCount > 0
        ? '$childCount ${childCount == 1 ? 'ingredient' : 'ingredients'}'
        : null;
    final amountLabel = hasTotal ? '${blend.totalAmount} ${blend.unit}' : null;
    final totalLabel = amountLabel != null && countLabel != null
        ? '$amountLabel · $countLabel'
        : amountLabel ?? countLabel ?? 'Amount not disclosed';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: V2Spacing.space8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(Icons.layers_outlined, size: 14, color: V2Colors.fgMuted),
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
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
