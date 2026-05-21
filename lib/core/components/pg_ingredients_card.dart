import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_inactive_row.dart';
import 'package:pharmaguide/core/components/pg_ingredient_data.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

/// Canonical ingredients card for Product Detail.
///
/// Single elevated card containing the active + inactive sub-sections:
/// - Active content is passed in pre-built (the screen composes the
///   active list and its collapse header)
/// - Hairline divider (0.5pt) between active + inactive
/// - Inactive section has its own header: "Other ingredients" + count
///   pill badge + chevron
/// - Tappable header toggles inactive expand/collapse
/// - Auto-expand threshold ≤5 (Sean's rule: "show first x, drop down
///   to see all if more")
/// - Card hides entirely when both lists are empty
///
/// Surface: V2Colors.surface + outline + sm shadow. Header title in
/// Geist Sans 500. Count badge bg V2Colors.accentTint.
class PGIngredientsCard extends StatefulWidget {
  /// Pre-built active-ingredients content. Caller composes the list of
  /// [PGActiveIngredientTile] (with its own collapse header if the active
  /// list is long). Null hides the active sub-section.
  final Widget? activeContent;

  /// Inactive ingredient rows (label order — pipeline-shaped). Empty
  /// hides the inactive sub-section.
  final List<PGInactiveIngredient> inactiveIngredients;

  /// Auto-expand threshold. Lists ≤ this size start expanded; longer
  /// lists start collapsed.
  final int autoExpandThreshold;

  /// Tap handler for each inactive row — opens the functional-roles
  /// sheet (`showFunctionalRolesSheet`). Receives the ingredient
  /// index so the parent can resolve which row was tapped.
  final void Function(int index)? onInactiveTap;

  const PGIngredientsCard({
    super.key,
    required this.activeContent,
    required this.inactiveIngredients,
    this.autoExpandThreshold = 5,
    this.onInactiveTap,
  });

  @override
  State<PGIngredientsCard> createState() => _PGIngredientsCardState();
}

class _PGIngredientsCardState extends State<PGIngredientsCard> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.inactiveIngredients.length <= widget.autoExpandThreshold;
  }

  @override
  Widget build(BuildContext context) {
    final hasActive = widget.activeContent != null;
    final hasInactive = widget.inactiveIngredients.isNotEmpty;
    if (!hasActive && !hasInactive) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(V2Spacing.space16),
      decoration: BoxDecoration(
        color: V2Colors.surface,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        border: Border.all(color: V2Colors.outline),
        boxShadow: V2Shadows.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasActive) widget.activeContent!,
          if (hasActive && hasInactive) ...[
            const SizedBox(height: V2Spacing.space16),
            const Divider(color: V2Colors.outline, height: 1, thickness: 0.5),
            const SizedBox(height: V2Spacing.space16),
          ],
          if (hasInactive) _buildInactiveSection(),
        ],
      ),
    );
  }

  Widget _buildInactiveSection() {
    final ingredients = widget.inactiveIngredients;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Tappable "Other ingredients [N] ⌄" header.
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: V2Spacing.space4),
            child: Row(
              children: [
                Text(
                  'Other ingredients',
                  style: V2Typography.bodyMedium(
                    color: V2Colors.fg,
                  ).copyWith(fontSize: 16),
                ),
                const SizedBox(width: V2Spacing.space8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: V2Colors.accentTint,
                    borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
                  ),
                  child: Text(
                    '${ingredients.length}',
                    style: V2Typography.overline(color: V2Colors.accent)
                        .copyWith(
                          fontSize: 11,
                          letterSpacing: 0.2,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                  ),
                ),
                const Spacer(),
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: const Icon(
                    Icons.expand_more_rounded,
                    size: 22,
                    color: V2Colors.fgMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: _expanded
              ? Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < ingredients.length; i++)
                        PGInactiveRow(
                          ingredient: ingredients[i],
                          isLast: i == ingredients.length - 1,
                          onTap: widget.onInactiveTap == null
                              ? null
                              : () => widget.onInactiveTap!(i),
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

/// Convenience widget that pairs with [PGIngredientsCard.activeContent].
///
/// Header: "Active Ingredients [N] ⌄" — tappable to expand/collapse.
/// Auto-expands when length ≤ 5.
class PGActiveIngredientsSection extends StatefulWidget {
  /// Pre-built tile widgets. Caller wires each row to its tap handler
  /// (e.g. `() => showIngredientExplainSheet(...)`). Decoupled from the
  /// data model so blends + indented children can render mid-list per
  /// the production T16.2f flow.
  final List<Widget> tiles;

  const PGActiveIngredientsSection({super.key, required this.tiles});

  @override
  State<PGActiveIngredientsSection> createState() =>
      _PGActiveIngredientsSectionState();
}

class _PGActiveIngredientsSectionState
    extends State<PGActiveIngredientsSection> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.tiles.length <= 5;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: V2Spacing.space4),
            child: Row(
              children: [
                Text(
                  'Active Ingredients',
                  style: V2Typography.bodyMedium(
                    color: V2Colors.fg,
                  ).copyWith(fontSize: 16),
                ),
                const SizedBox(width: V2Spacing.space8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: V2Colors.accentTint,
                    borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
                  ),
                  child: Text(
                    '${widget.tiles.length}',
                    style: V2Typography.overline(color: V2Colors.accent)
                        .copyWith(
                          fontSize: 11,
                          letterSpacing: 0.2,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                  ),
                ),
                const Spacer(),
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: const Icon(
                    Icons.expand_more_rounded,
                    size: 22,
                    color: V2Colors.fgMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: _expanded
              ? Padding(
                  padding: const EdgeInsets.only(top: V2Spacing.space8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: widget.tiles,
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}
