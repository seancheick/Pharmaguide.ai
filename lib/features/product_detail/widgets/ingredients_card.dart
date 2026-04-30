// Merged Ingredients card — single 3D card combining the active +
// inactive ingredient sub-sections.
//
// Spec: INITIATIVE_PRODUCT_DETAIL_CLEANUP.md, Sprint S2.2, T16.
//
// Pre-T16 the screen rendered active ingredients (collapsible list
// of name + dose + form chips) and inactive ingredients (chip wrap
// with top-8 cap + "+N more" pill) as TWO independent sections,
// stacked with a 20pt gap. Sean's design contract collapses them
// into ONE elevated card with an internal divider:
//
//   ┌──────────────────────────────────────┐
//   │ Active ingredients                   │
//   │  Magnesium Bisglycinate 135 mg [chip]│
//   │  Vitamin D3            1000 IU [chip]│
//   │ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─  │
//   │ Other ingredients                    │
//   │  [Cellulose] [Silica] [Mag stearate] │
//   │  See all 14 ingredients ⌄            │
//   │   🟢 Cellulose                       │
//   │   🟡 Magnesium stearate              │
//   │   🟠 Palm oil                        │
//   │   🔴 Sugar syrup                     │
//   └──────────────────────────────────────┘
//
// The inactive expander on tap reveals the FULL list with color dots
// (T16's `inactiveColorRank` rubric — green/yellow/orange/red).
// Active rendering reuses `CollapsibleIngredients` from the screen
// file (promoted from `_CollapsibleIngredients` for cross-file use).

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_card.dart';
import 'package:pharmaguide/core/widgets/pg_pressable.dart';
import 'package:pharmaguide/features/product_detail/widgets/inactive_color.dart';
import 'package:pharmaguide/features/product_detail/widgets/ingredients_section.dart';

/// Merged Ingredients card — Section 6 of the product detail page.
///
/// Inputs are pipeline-shaped raw maps (the screen passes them
/// straight through from `detailBlob['ingredients']` and
/// `detailBlob['inactive_ingredients']`). Card hides when both
/// lists are empty.
class IngredientsCard extends StatefulWidget {
  /// Pre-rendered active-ingredient block. Caller passes a built
  /// widget (typically `CollapsibleIngredients(...)` from the
  /// screen) so this card stays decoupled from the screen-side
  /// active-row rendering. Null means no actives → top sub-section
  /// hidden.
  final Widget? activeContent;

  /// Inactive ingredient names in label order. Cards renders the
  /// top 8 as small chips; tapping "See all N ⌄" expands to the
  /// full list with color-dot tone per [inactiveColorRank].
  final List<String> inactiveNames;

  /// Number of inactive chips shown before the "See all N" toggle
  /// fires. Default matches the spec.
  final int inactiveChipCap;

  const IngredientsCard({
    super.key,
    required this.activeContent,
    required this.inactiveNames,
    this.inactiveChipCap = 8,
  });

  @override
  State<IngredientsCard> createState() => _IngredientsCardState();
}

class _IngredientsCardState extends State<IngredientsCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final hasActive = widget.activeContent != null;
    final hasInactive = widget.inactiveNames.isNotEmpty;
    if (!hasActive && !hasInactive) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return PGCard(
      variant: PGCardVariant.elevated,
      padding: const EdgeInsets.all(AppTheme.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasActive) widget.activeContent!,
          if (hasActive && hasInactive) ...[
            const SizedBox(height: AppTheme.space16),
            Divider(
              color: scheme.outlineVariant,
              height: 1,
              thickness: 0.5,
            ),
            const SizedBox(height: AppTheme.space16),
          ],
          if (hasInactive) _buildInactiveSection(theme, scheme),
        ],
      ),
    );
  }

  Widget _buildInactiveSection(ThemeData theme, ColorScheme scheme) {
    final names = widget.inactiveNames;
    final visibleChips = names.take(widget.inactiveChipCap).toList();
    final hasOverflow = names.length > widget.inactiveChipCap;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Other ingredients',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.1,
          ),
        ),
        const SizedBox(height: AppTheme.space8),
        // Top-N chip wrap — quick scan of the most prominent inactives
        // without overwhelming the card. Reuses InactiveIngredientChip
        // for the existing tap-to-explain bottom-sheet UX.
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final name in visibleChips) InactiveIngredientChip(name: name),
          ],
        ),
        if (hasOverflow || _expanded) ...[
          const SizedBox(height: AppTheme.space12),
          // T16 — "See all N" toggle. Reveals the FULL list (label
          // order) with color dots per `inactiveColorRank`. Default
          // collapsed; tap expands inline. Color rubric: 🟢 green
          // (whitelisted excipients), 🟡 yellow (acceptable),
          // 🟠 orange (watchlist), 🔴 red (penalty). Sean's call:
          // "we need to know which ingredient had a penalty, red,
          // orange or green in front of them could help on the full
          // list."
          PGPressable(
            onTap: () => setState(() => _expanded = !_expanded),
            pressedScale: 0.98,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _expanded
                        ? 'Show less'
                        : 'See all ${names.length} ingredients',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const SizedBox(height: AppTheme.space8),
            for (final name in names)
              _InactiveDotRow(name: name, theme: theme, scheme: scheme),
          ],
        ],
      ],
    );
  }
}

/// Single full-list row in the expanded inactive section: color dot
/// (per [inactiveColorRank]) + ingredient name.
class _InactiveDotRow extends StatelessWidget {
  final String name;
  final ThemeData theme;
  final ColorScheme scheme;

  const _InactiveDotRow({
    required this.name,
    required this.theme,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    final tone = inactiveColorRank(name);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: tone.color,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: AppTheme.space8),
          Expanded(
            child: Text(
              name,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurface,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
