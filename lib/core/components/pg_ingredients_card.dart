import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_inactive_row.dart';
import 'package:pharmaguide/core/components/pg_ingredient_data.dart';
import 'package:pharmaguide/core/components/pg_ingredient_tile.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
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
/// Surface: context.v2.surface + outline + sm shadow. Header title in
/// Geist Sans 500. Count badge bg context.v2.accentTint.
class PGIngredientsCard extends StatefulWidget {
  /// Pre-built active-ingredients content. Caller composes the list of
  /// [PGActiveIngredientTile] (with its own collapse header if the active
  /// list is long). Null hides the active sub-section.
  final Widget? activeContent;

  /// Inactive ingredient rows (label order — pipeline-shaped). Empty
  /// hides the inactive sub-section.
  final List<PGInactiveIngredient> inactiveIngredients;

  /// Optional label-adjacent content, such as the collapsed Nutrition Facts
  /// panel. It shares this card so bottle identity reads as one system.
  final Widget? additionalContent;

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
    this.additionalContent,
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

  void _toggleExpanded() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    final hasActive = widget.activeContent != null;
    final hasInactive = widget.inactiveIngredients.isNotEmpty;
    final additional = widget.additionalContent;
    final hasAdditional =
        additional != null &&
        !(additional is SizedBox &&
            additional.width == 0 &&
            additional.height == 0);
    if (!hasActive && !hasInactive && !hasAdditional) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(V2Spacing.space16),
      decoration: BoxDecoration(
        color: context.v2.surface,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        border: Border.all(color: context.v2.outline),
        boxShadow: V2Shadows.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What’s inside',
            style: V2Typography.titleSm(color: context.v2.fg),
          ),
          const SizedBox(height: V2Spacing.space12),
          Divider(color: context.v2.outline, height: 1, thickness: 0.5),
          const SizedBox(height: V2Spacing.space8),
          if (hasActive) widget.activeContent!,
          if (hasActive && hasInactive) ...[
            const SizedBox(height: V2Spacing.space16),
            Divider(color: context.v2.outline, height: 1, thickness: 0.5),
            const SizedBox(height: V2Spacing.space16),
          ],
          if (hasInactive) _buildInactiveSection(),
          if (hasAdditional) ...[
            if (hasActive || hasInactive) ...[
              const SizedBox(height: V2Spacing.space16),
              Divider(color: context.v2.outline, height: 1, thickness: 0.5),
              const SizedBox(height: V2Spacing.space8),
            ],
            additional,
          ],
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
        Semantics(
          button: true,
          expanded: _expanded,
          label:
              'Other ingredients, ${ingredients.length} '
              '${ingredients.length == 1 ? 'ingredient' : 'ingredients'}',
          onTap: _toggleExpanded,
          excludeSemantics: true,
          child: InkWell(
            onTap: _toggleExpanded,
            borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: V2Spacing.space4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Other ingredients',
                        style: V2Typography.bodyMedium(
                          color: context.v2.fg,
                        ).copyWith(fontSize: 16),
                        softWrap: true,
                      ),
                    ),
                    const SizedBox(width: V2Spacing.space8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: context.v2.accentTint,
                        borderRadius: BorderRadius.circular(
                          V2Spacing.radiusPill,
                        ),
                      ),
                      child: Text(
                        '${ingredients.length}',
                        style: V2Typography.overline(color: context.v2.accent)
                            .copyWith(
                              fontSize: 11,
                              letterSpacing: 0.2,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                      ),
                    ),
                    const SizedBox(width: V2Spacing.space4),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: Icon(
                        Icons.expand_more_rounded,
                        size: 22,
                        color: context.v2.fgMuted,
                      ),
                    ),
                  ],
                ),
              ),
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
/// Header: "What the label lists [N] ⌄" — tappable to expand/collapse.
/// The badge and auto-expand threshold count logical ingredient tiles, not
/// blend/header widgets or parenthetical continuation lines.
class PGActiveIngredientsSection extends StatefulWidget {
  /// Pre-built tile widgets. Caller wires each row to its tap handler
  /// (e.g. `() => showIngredientExplainSheet(...)`). Decoupled from the
  /// data model so blends + indented children can render mid-list per
  /// the production T16.2f flow.
  final List<Widget> tiles;

  /// Consumer-facing label for this projection of the canonical ledger.
  /// Legacy callers keep the historical umbrella heading.
  final String title;

  /// Optional navigation signal that expands and mounts every tile before a
  /// caller scrolls to a disclosure target inside this section.
  final ValueListenable<bool>? revealSignal;

  const PGActiveIngredientsSection({
    super.key,
    required this.tiles,
    this.title = 'What the label lists',
    this.revealSignal,
  });

  @override
  State<PGActiveIngredientsSection> createState() =>
      _PGActiveIngredientsSectionState();
}

class _PGActiveIngredientsSectionState
    extends State<PGActiveIngredientsSection> {
  static const _revealChunkSize = 20;

  late bool _expanded;
  late int _visibleTileCount;

  int get _logicalIngredientCount => widget.tiles.fold<int>(
    0,
    (count, tile) => count + _logicalIngredientRowsIn(tile),
  );

  @override
  void initState() {
    super.initState();
    final revealRequested = widget.revealSignal?.value == true;
    _expanded = revealRequested || _logicalIngredientCount <= 5;
    _visibleTileCount = revealRequested
        ? widget.tiles.length
        : _initialVisibleCount(widget.tiles.length);
    widget.revealSignal?.addListener(_handleRevealSignal);
  }

  @override
  void didUpdateWidget(covariant PGActiveIngredientsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final revealSignalChanged = !identical(
      oldWidget.revealSignal,
      widget.revealSignal,
    );
    if (revealSignalChanged) {
      oldWidget.revealSignal?.removeListener(_handleRevealSignal);
      widget.revealSignal?.addListener(_handleRevealSignal);
    }
    if (oldWidget.tiles.length != widget.tiles.length) {
      final preserveLatchedReveal =
          _expanded && widget.revealSignal?.value == true;
      if (preserveLatchedReveal) {
        _visibleTileCount = widget.tiles.length;
      } else {
        final wasFullyRevealed = _visibleTileCount >= oldWidget.tiles.length;
        if (wasFullyRevealed) {
          _visibleTileCount = _initialVisibleCount(widget.tiles.length);
        } else if (_visibleTileCount > widget.tiles.length) {
          _visibleTileCount = widget.tiles.length;
        }
      }
    }
    if (revealSignalChanged && widget.revealSignal?.value == true) {
      _expanded = true;
      _visibleTileCount = widget.tiles.length;
    }
  }

  void _toggleExpanded() => setState(() => _expanded = !_expanded);

  void _handleRevealSignal() {
    if (widget.revealSignal?.value != true) return;
    _revealAll();
  }

  void _revealAll() {
    if (_expanded && _visibleTileCount >= widget.tiles.length) return;
    setState(() {
      _expanded = true;
      _visibleTileCount = widget.tiles.length;
    });
  }

  void _showMore() {
    setState(() {
      final next = _visibleTileCount + _revealChunkSize;
      _visibleTileCount = next < widget.tiles.length
          ? next
          : widget.tiles.length;
    });
  }

  @override
  void dispose() {
    widget.revealSignal?.removeListener(_handleRevealSignal);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          expanded: _expanded,
          label:
              '${widget.title}, $_logicalIngredientCount '
              '${_logicalIngredientCount == 1 ? 'ingredient' : 'ingredients'}',
          onTap: _toggleExpanded,
          excludeSemantics: true,
          child: InkWell(
            onTap: _toggleExpanded,
            borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: V2Spacing.space4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        style: V2Typography.bodyMedium(
                          color: context.v2.fg,
                        ).copyWith(fontSize: 16),
                        softWrap: true,
                      ),
                    ),
                    const SizedBox(width: V2Spacing.space8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: context.v2.accentTint,
                        borderRadius: BorderRadius.circular(
                          V2Spacing.radiusPill,
                        ),
                      ),
                      child: Text(
                        '$_logicalIngredientCount',
                        style: V2Typography.overline(color: context.v2.accent)
                            .copyWith(
                              fontSize: 11,
                              letterSpacing: 0.2,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                      ),
                    ),
                    const SizedBox(width: V2Spacing.space4),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: Icon(
                        Icons.expand_more_rounded,
                        size: 22,
                        color: context.v2.fgMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: _expanded
              ? Padding(
                  padding: const EdgeInsets.only(top: V2Spacing.space8),
                  child: _buildExpandedTiles(),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  Widget _buildExpandedTiles() {
    final visibleCount = _visibleTileCount < widget.tiles.length
        ? _visibleTileCount
        : widget.tiles.length;
    final visibleLogicalCount = widget.tiles
        .take(visibleCount)
        .fold<int>(0, (count, tile) => count + _logicalIngredientRowsIn(tile));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < visibleCount; index++) widget.tiles[index],
        if (visibleCount < widget.tiles.length)
          Semantics(
            button: true,
            label:
                'Show more label ingredients, $visibleLogicalCount of '
                '$_logicalIngredientCount shown',
            onTap: _showMore,
            excludeSemantics: true,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _showMore,
                borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Center(
                    child: Text(
                      'Show more',
                      style: V2Typography.bodyMedium(color: context.v2.accent),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  static int _initialVisibleCount(int total) =>
      total < _revealChunkSize ? total : _revealChunkSize;
}

int _logicalIngredientRowsIn(Widget widget) {
  if (widget is PGActiveIngredientTile) return 1;
  if (widget is Padding && widget.child != null) {
    return _logicalIngredientRowsIn(widget.child!);
  }
  return 0;
}
