// Merged Ingredients card — single 3D card combining the active +
// inactive ingredient sub-sections.
//
// Spec: INITIATIVE_PRODUCT_DETAIL_CLEANUP.md, Sprint S2.2, T16 +
// follow-up 2026-04-30.
//
// **2026-04-30 follow-up — symmetry with Active Ingredients.**
// Pre-follow-up the inactive section had TWO surfaces stacked: a chip
// wrap (top 8) AND a "See all N ⌄" toggle that revealed a separate
// full color-dot list. Sean's call: "the drop down for inactive
// ingredient don't make sense, there are chips and then drop down,
// it's either or, not both. Make other ingredients just like active
// ingredients then — tag showing how many, drop down to see them all,
// show the first x number just like active ingredients if more drop
// down to see all, same horizontal line separating each ingredient."
//
//   ┌──────────────────────────────────────┐
//   │ Active Ingredients [44]           ⌄ │
//   │  Magnesium Bisglycinate 135 mg       │
//   │  Vitamin D3            1000 IU       │
//   │ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─  │
//   │ Other ingredients [8]             ⌄ │
//   │  🟢 Cellulose                        │
//   │  ─────────────────────────────────  │
//   │  🟡 Magnesium stearate               │
//   │  ─────────────────────────────────  │
//   │  🟠 Palm oil                         │
//   │  ─────────────────────────────────  │
//   │  🔴 Sugar syrup                      │
//   └──────────────────────────────────────┘
//
// Color rubric: green = whitelisted excipient, yellow = acceptable,
// orange = watchlist, red = penalty. Each row taps to a bottom-sheet
// explanation (preserves the prior chip's tap-to-explain UX).

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

  /// Inactive ingredient names in label order. Renders inline with
  /// color-dot tone per [inactiveColorRank], matching the Active
  /// Ingredients collapsible pattern.
  final List<String> inactiveNames;

  /// Auto-expand threshold. Lists at-or-below this size start expanded;
  /// longer lists start collapsed and reveal on tap. Mirrors
  /// `_CollapsibleIngredientsState.initState` behavior on the actives
  /// side so users get the same "short list = visible by default" feel.
  final int autoExpandThreshold;

  const IngredientsCard({
    super.key,
    required this.activeContent,
    required this.inactiveNames,
    this.autoExpandThreshold = 5,
  });

  @override
  State<IngredientsCard> createState() => _IngredientsCardState();
}

class _IngredientsCardState extends State<IngredientsCard> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.inactiveNames.length <= widget.autoExpandThreshold;
  }

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Tappable header — title + count badge + chevron. Mirrors the
        // Active Ingredients section header (see `_CollapsibleIngredients`
        // in product_detail_screen.dart).
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Text(
                  'Other ingredients',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                  ),
                  child: Text(
                    '${names.length}',
                    style: AppTheme.numeric(
                      theme.textTheme.labelSmall!.copyWith(
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(
                    Icons.expand_more_rounded,
                    size: 22,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        // Animated expand/collapse of the inactive rows. Color-dot
        // (per `inactiveColorRank`) + name + bottom divider. Tap a row
        // to open the existing bottom-sheet explanation (the prior
        // chip's UX).
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: _expanded
              ? Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < names.length; i++)
                        _InactiveRow(
                          name: names[i],
                          isLast: i == names.length - 1,
                        ),
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

/// Single inactive ingredient row: color dot (per [inactiveColorRank])
/// + name + bottom divider. Tappable to open the existing bottom-sheet
/// explanation (preserves the prior `InactiveIngredientChip` UX).
class _InactiveRow extends StatelessWidget {
  final String name;
  final bool isLast;

  const _InactiveRow({required this.name, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tone = inactiveColorRank(name);

    return PGPressable(
      onTap: () => _showExplanationSheet(context, name),
      pressedScale: 0.98,
      child: Container(
        decoration: BoxDecoration(
          border: isLast
              ? null
              : Border(
                  bottom: BorderSide(
                    color: scheme.outlineVariant,
                    width: 0.4,
                  ),
                ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppTheme.space8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  color: tone.color,
                  shape: BoxShape.circle,
                ),
              ),
              Expanded(
                child: Text(
                  name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showExplanationSheet(BuildContext context, String ingredientName) {
    showInactiveExplanationSheet(context, ingredientName);
  }
}
