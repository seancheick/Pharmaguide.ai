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
import 'package:pharmaguide/core/data/functional_roles_vocab.dart';
import 'package:pharmaguide/core/widgets/pg_card.dart';
import 'package:pharmaguide/core/widgets/pg_modal.dart';
import 'package:pharmaguide/core/widgets/pg_pressable.dart';
import 'package:pharmaguide/features/product_detail/widgets/inactive_color.dart';

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

  /// Inactive ingredient rows from the pipeline blob (label order).
  /// Each entry carries `name`, `severity_level` (drives color dot —
  /// see [inactiveColorRank]) and `functional_roles[]` (drives the
  /// tap modal — looked up against the bundled
  /// `functional_roles_vocab.json`). Other pipeline fields ride
  /// along untouched so future enrichment doesn't break the API.
  final List<Map<String, dynamic>> inactiveIngredients;

  /// Auto-expand threshold. Lists at-or-below this size start expanded;
  /// longer lists start collapsed and reveal on tap. Mirrors
  /// `_CollapsibleIngredientsState.initState` behavior on the actives
  /// side so users get the same "short list = visible by default" feel.
  final int autoExpandThreshold;

  const IngredientsCard({
    super.key,
    required this.activeContent,
    required this.inactiveIngredients,
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
    _expanded = widget.inactiveIngredients.length <= widget.autoExpandThreshold;
  }

  @override
  Widget build(BuildContext context) {
    final hasActive = widget.activeContent != null;
    final hasInactive = widget.inactiveIngredients.isNotEmpty;
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
            Divider(color: scheme.outlineVariant, height: 1, thickness: 0.5),
            const SizedBox(height: AppTheme.space16),
          ],
          if (hasInactive) _buildInactiveSection(theme, scheme),
        ],
      ),
    );
  }

  Widget _buildInactiveSection(ThemeData theme, ColorScheme scheme) {
    final ingredients = widget.inactiveIngredients;

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
                    '${ingredients.length}',
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
        // (per `inactiveColorRank`, driven by pipeline severity_level)
        // + name + 1-line role helper + bottom divider. Tap a row to
        // open the vocab-driven functional-roles explanation modal.
        //
        // T4D (sprint product_detail_page_sprint.md) — vocab is loaded
        // once at this level via FutureBuilder and passed down as a
        // snapshot. Cold cache / vocab miss → row falls back to
        // name-only. Tap behavior unchanged.
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: _expanded
              ? Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: FutureBuilder<Map<String, FunctionalRoleEntry>>(
                    future: loadFunctionalRolesVocab(),
                    builder: (context, snapshot) {
                      final vocab = snapshot.data;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < ingredients.length; i++)
                            _InactiveRow(
                              ingredient: ingredients[i],
                              isLast: i == ingredients.length - 1,
                              vocab: vocab,
                            ),
                        ],
                      );
                    },
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

/// Single inactive ingredient row: color dot + name + (optional)
/// 12sp gray role helper + bottom divider. Tap → vocab-driven
/// functional-roles modal (see [_showFunctionalRolesSheet]).
class _InactiveRow extends StatelessWidget {
  final Map<String, dynamic> ingredient;
  final bool isLast;

  /// Pre-loaded functional-roles vocab from the parent
  /// [IngredientsCard]. Null when the cache is still cold OR the
  /// asset failed to load — the row falls back to name-only render.
  final Map<String, FunctionalRoleEntry>? vocab;

  const _InactiveRow({
    required this.ingredient,
    required this.isLast,
    this.vocab,
  });

  /// Comma-joined list of all matched roles for this ingredient,
  /// capped at 2. Prefers the pipeline's pre-formatted
  /// `display_role_label` (v1.5.0 canonical contract — single source
  /// of truth, the cleaner already prettified the role from
  /// snake_case). Falls back to the vocab lookup against the legacy
  /// `functional_roles[]` array for blobs built before v1.5.0.
  String? _roleHelper() {
    final pipelineLabel = ingredient['display_role_label']?.toString().trim();
    if (pipelineLabel != null && pipelineLabel.isNotEmpty) {
      return pipelineLabel;
    }
    if (vocab == null) return null;
    final raw = ingredient['functional_roles'];
    if (raw is! List) return null;
    final names = <String>[];
    for (final r in raw) {
      final id = r?.toString();
      if (id == null || id.isEmpty) continue;
      final hit = vocab![id];
      if (hit != null && !names.contains(hit.name)) {
        names.add(hit.name);
        if (names.length >= 2) break;
      }
    }
    return names.isEmpty ? null : names.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tone = inactiveColorRank(ingredient);
    // v1.5.0 contract — display_label is the prettified canonical name.
    // Falls back to legacy `name` / `raw_source_text` for stale blobs.
    final name =
        ingredient['display_label']?.toString().trim().isNotEmpty == true
        ? ingredient['display_label']!.toString().trim()
        : (ingredient['name']?.toString() ??
              ingredient['raw_source_text']?.toString() ??
              '');
    final roleHelper = _roleHelper();

    return PGPressable(
      onTap: () => _showFunctionalRolesSheet(context, ingredient),
      pressedScale: 0.98,
      child: Container(
        decoration: BoxDecoration(
          border: isLast
              ? null
              : Border(
                  bottom: BorderSide(color: scheme.outlineVariant, width: 0.4),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                    if (roleHelper != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        roleHelper,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Open the tap-modal for this ingredient. Looks up each entry of
  /// `ingredient['functional_roles']: string[]` against the bundled
  /// vocab and renders one section per matched role (name + verbatim
  /// notes + examples + regulatory deep-links).
  ///
  /// Empty / null `functional_roles` → generic fallback. The sheet
  /// itself handles vocab loading / lookup misses.
  void _showFunctionalRolesSheet(
    BuildContext context,
    Map<String, dynamic> ingredient,
  ) {
    PGModal.bottomSheet<void>(
      context: context,
      builder: (sheetCtx) => _FunctionalRolesSheet(ingredient: ingredient),
    );
  }
}

/// Bottom-sheet body explaining an inactive ingredient via the
/// functional-roles vocab. One stacked section per role on the
/// ingredient row. Reads vocab via the cached
/// `loadFunctionalRolesVocab()` so the first open does the asset
/// fetch; subsequent opens are sync-fast.
class _FunctionalRolesSheet extends StatelessWidget {
  final Map<String, dynamic> ingredient;
  const _FunctionalRolesSheet({required this.ingredient});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final name =
        ingredient['name']?.toString() ??
        ingredient['raw_source_text']?.toString() ??
        '';
    final roles =
        (ingredient['functional_roles'] as List?)
            ?.map((e) => e.toString())
            .where((id) => id.isNotEmpty)
            .toList(growable: false) ??
        const <String>[];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppTheme.space20,
          AppTheme.space12,
          AppTheme.space20,
          AppTheme.space20,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Ingredient name (the row the user tapped) — in the
              // sheet header so they have anchor context.
              Text(
                name.isEmpty ? 'Inactive ingredient' : name,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: AppTheme.space12),
              if (roles.isEmpty)
                _GenericFallback(scheme: scheme, theme: theme)
              else
                FutureBuilder<Map<String, FunctionalRoleEntry>>(
                  future: loadFunctionalRolesVocab(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const SizedBox(
                        height: 80,
                        child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    }
                    final vocab = snapshot.data!;
                    final matched = roles
                        .map((id) => vocab[id])
                        .whereType<FunctionalRoleEntry>()
                        .toList(growable: false);
                    if (matched.isEmpty) {
                      // All ids unknown — fall back so the user gets
                      // something. Could happen during a vocab/data
                      // version skew.
                      return _GenericFallback(scheme: scheme, theme: theme);
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < matched.length; i++) ...[
                          if (i > 0) const SizedBox(height: AppTheme.space20),
                          _RoleSection(role: matched[i]),
                        ],
                      ],
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One vocab role rendered as a stacked section in the modal:
/// title, body (verbatim — clinician-locked), examples chip row,
/// regulatory deep-link row.
class _RoleSection extends StatelessWidget {
  final FunctionalRoleEntry role;
  const _RoleSection({required this.role});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          role.name,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppTheme.space6),
        // Notes — verbatim, no paraphrase. Clinician-locked copy.
        Text(
          role.notes,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
        if (role.examples.isNotEmpty) ...[
          const SizedBox(height: AppTheme.space12),
          Text(
            'Common examples',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppTheme.space6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final ex in role.examples)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                  ),
                  child: Text(
                    ex,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ],
        if (role.regulatoryReferences.isNotEmpty) ...[
          const SizedBox(height: AppTheme.space12),
          Text(
            'Learn more',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppTheme.space6),
          for (final ref in role.regulatoryReferences)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                '${ref.jurisdiction} · ${ref.code}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _GenericFallback extends StatelessWidget {
  final ColorScheme scheme;
  final ThemeData theme;
  const _GenericFallback({required this.scheme, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Text(
      'Inactive ingredient — added during manufacturing.',
      style: theme.textTheme.bodyMedium?.copyWith(
        color: scheme.onSurfaceVariant,
        height: 1.4,
      ),
    );
  }
}
