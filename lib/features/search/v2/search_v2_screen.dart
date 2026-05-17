// Search v2 — Phase 11.7L.E.2.
//
// Visual mirror of `SearchScreen` against the v2 design system, plus
// the smartness Sean asked for: **on-market results render first,
// off-market falls to a labeled section at the bottom of the list.**
//
// Same providers (`coreDatabaseProvider`,
// `recentSearchesServiceProvider`), same `searchProducts` /
// `filterProducts` calls, same 300ms debounce + latest-query-wins
// semantics, same quality + category chip vocabulary, same recent-
// search persistence, same deep-link initial query handling. The
// only behavior delta is the partition + ordering of results.
//
// What changed visually:
//
//   * Cream `V2Colors.bg` Scaffold, no Material AppBar.
//   * Top row: back chip + v2 search field (cream surface, accent
//     focus, search icon, inline clear chip — same shape as the
//     MedicationEntry v2 search field).
//   * Filter chips are `PGGoalChip` so chip styling matches the
//     rest of v2 (ProfileSetup goals, MedicationEntry schedule).
//   * Recent searches render as cream pressable rows with a clock
//     leading icon and an inline remove control. "Clear all" is a
//     mono-caps ghost chip on the right of the section eyebrow.
//   * Loading state is a calm cream skeleton — six placeholder
//     rows that hold the layout shape so the user sees structure
//     before content.
//   * Result body splits into `_OnMarketSection` + (optional)
//     `_OffMarketSection`. The off-market section sits below the
//     on-market list with a hairline divider + mono-caps eyebrow
//     "OFF MARKET · OLDER OR DISCONTINUED" and a calm helper line
//     that explains why those items appear (so the user doesn't
//     wonder if PharmaGuide is silently filtering).
//   * Empty states use the v2 `PGEmptyState` API (icon / headline /
//     body) instead of the legacy `title / description` shape.
//   * Sticky empty hint about MedicationEntry uses
//     `PGPillButton.ghost`.
//
// What did NOT change:
//
//   * The `searchProducts` / `filterProducts` queries.
//   * The `RecentSearchesService` add/remove/clear contract.
//   * The four `_SearchFilter` values (All / High Quality 80+ /
//     Needs Review / Blocked / Unsafe).
//   * Category chip derivation from the result set.
//   * List vs grid toggle — keep, render `ProductListItem` /
//     `ProductGridItem`. Those widgets read the active theme so
//     they sit cleanly on the v2 cream surface without changes.
//   * Deep-link `initialQuery` and `initialCategory` arguments.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/components/pg_empty_state.dart';
import 'package:pharmaguide/core/components/pg_eyebrow.dart';
import 'package:pharmaguide/core/components/pg_goal_chip.dart';
import 'package:pharmaguide/core/components/pg_pill_button.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_motion.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/core/widgets/product_list_item.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/services/recent_searches_service.dart';

class SearchV2Screen extends ConsumerStatefulWidget {
  final String? initialCategory;
  final String? initialQuery;

  const SearchV2Screen({super.key, this.initialCategory, this.initialQuery});

  @override
  ConsumerState<SearchV2Screen> createState() => _SearchV2ScreenState();
}

class _SearchV2ScreenState extends ConsumerState<SearchV2Screen> {
  // ───────── controllers + ephemeral state (1:1 with legacy) ─────────
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  String _query = '';
  String? _activeCategory;
  List<ProductsCoreData>? _results;
  bool _loading = false;
  bool _isGridView = false;
  List<String> _recentSearches = [];
  _SearchFilter _activeFilter = _SearchFilter.all;
  String? _activeCategoryChip;

  Timer? _debounce;
  int _searchVersion = 0;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() => setState(() {}));
    _activeCategory = widget.initialCategory;
    _loadRecentSearches();
    if (_activeCategory != null && _activeCategory!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadCategoryResults(_activeCategory!);
      });
    } else if (widget.initialQuery != null &&
        widget.initialQuery!.trim().isNotEmpty) {
      final q = widget.initialQuery!.trim();
      _controller.text = q;
      _query = q;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _onQueryChanged(q);
      });
    }
  }

  RecentSearchesService get _recentService =>
      ref.read(recentSearchesServiceProvider);

  Future<void> _loadRecentSearches() async {
    final recent = await _recentService.getRecent();
    if (mounted) setState(() => _recentSearches = recent);
  }

  Future<void> _loadCategoryResults(String category) async {
    setState(() => _loading = true);
    final db = ref.read(coreDatabaseProvider);
    final results = await db.filterProducts(
      category: category,
      limit: 50,
      sortBy: 'score',
    );
    if (!mounted) return;
    setState(() {
      _results = results;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    setState(() {
      _query = value;
      if (value.trim().isNotEmpty) _activeCategory = null;
      _activeCategoryChip = null;
    });

    if (value.trim().isEmpty) {
      setState(() {
        _results = _activeCategory == null ? null : _results;
        _loading = false;
      });
      if (_activeCategory != null && _activeCategory!.isNotEmpty) {
        _loadCategoryResults(_activeCategory!);
      }
      return;
    }

    setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _executeSearch(value.trim());
    });
  }

  Future<void> _executeSearch(String query) async {
    final version = ++_searchVersion;
    final db = ref.read(coreDatabaseProvider);
    try {
      final results = await db.searchProducts(query, limit: 50);
      if (version != _searchVersion) return;
      if (!mounted) return;
      setState(() {
        _results = results;
        _loading = false;
      });
      if (results.isNotEmpty) {
        await _recentService.addSearch(query);
        await _loadRecentSearches();
      }
    } on Exception {
      if (version != _searchVersion) return;
      if (!mounted) return;
      setState(() {
        _results = <ProductsCoreData>[];
        _loading = false;
      });
    }
  }

  void _clearSearch() {
    _debounce?.cancel();
    _controller.clear();
    setState(() {
      _query = '';
      _results = null;
      _loading = false;
      _activeCategory = null;
      _activeFilter = _SearchFilter.all;
      _activeCategoryChip = null;
    });
    _focusNode.requestFocus();
  }

  // ───────── build ─────────

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.paddingOf(context);
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Scaffold(
      backgroundColor: V2Colors.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _TopRow(
              controller: _controller,
              focusNode: _focusNode,
              query: _query,
              onChanged: _onQueryChanged,
              onClear: _clearSearch,
              onBack: () {
                if (Navigator.of(context).canPop()) {
                  Navigator.of(context).maybePop();
                } else {
                  context.go(Routes.home);
                }
              },
            ),
            if (_showFilterChips) ...[
              const SizedBox(height: V2Spacing.space8),
              _FilterRow(
                activeFilter: _activeFilter,
                onFilterTap: (filter) => setState(() {
                  if (_activeFilter == filter && _activeCategoryChip == null) {
                    _activeFilter = _SearchFilter.all;
                  } else {
                    _activeFilter = filter;
                    _activeCategoryChip = null;
                  }
                }),
                categories: _resultCategories,
                activeCategoryChip: _activeCategoryChip,
                onCategoryTap: (category) => setState(() {
                  if (_activeCategoryChip == category) {
                    _activeCategoryChip = null;
                  } else {
                    _activeCategoryChip = category;
                    _activeFilter = _SearchFilter.all;
                  }
                }),
              ),
            ],
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: keyboardOpen
                      ? V2Spacing.space8
                      : mq.bottom + V2Spacing.space24,
                ),
                child: _buildBody(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_query.isEmpty && _activeCategory != null) {
      if (_loading) return const _LoadingList();
      if (_results == null || _results!.isEmpty) return _buildNoResultsState();
      return _buildResultsList();
    }
    if (_query.isEmpty) return _buildIdleState();
    if (_loading) return const _LoadingList();
    if (_results == null || _results!.isEmpty) return _buildNoResultsState();
    return _buildResultsList();
  }

  // ───────── states ─────────

  Widget _buildIdleState() {
    if (_recentSearches.isNotEmpty) {
      return ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          V2Spacing.space24,
          V2Spacing.space12,
          V2Spacing.space24,
          V2Spacing.space24,
        ),
        children: [
          Row(
            children: [
              const PGEyebrow('Recent searches', color: V2Colors.fgMuted),
              const Spacer(),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () async {
                  await _recentService.clearAll();
                  await _loadRecentSearches();
                },
                child: Text(
                  'Clear all',
                  style: V2Typography.label(color: V2Colors.accent),
                ),
              ),
            ],
          ),
          const SizedBox(height: V2Spacing.space12),
          ..._recentSearches.map(
            (term) => Padding(
              padding: const EdgeInsets.only(bottom: V2Spacing.space8),
              child: _RecentSearchRow(
                term: term,
                onTap: () {
                  _controller.text = term;
                  _onQueryChanged(term);
                },
                onRemove: () async {
                  await _recentService.removeSearch(term);
                  await _loadRecentSearches();
                },
              ),
            ),
          ),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.all(V2Spacing.space24),
      child: Column(
        children: [
          const PGEmptyState(
            icon: Icons.search_rounded,
            headline: 'Search supplements',
            body:
                'Search by product name, brand, or ingredient. '
                "We'll show on-market matches first.",
          ),
          const SizedBox(height: V2Spacing.space16),
          PGPillButton(
            label: 'Looking for a medication?',
            variant: PGPillVariant.ghost,
            icon: Icons.medication_outlined,
            onPressed: () => context.push(Routes.medicationEntry),
          ),
        ],
      ),
    );
  }

  Widget _buildNoResultsState() {
    final headline = _activeCategory != null && _query.isEmpty
        ? 'Nothing in ${_activeCategory!.replaceAll('_', ' ')} yet'
        : 'No match for "$_query"';
    return Padding(
      padding: const EdgeInsets.all(V2Spacing.space24),
      child: Column(
        children: [
          PGEmptyState(
            icon: Icons.search_off_rounded,
            headline: headline,
            body:
                'Try a different spelling or brand name. If you still '
                "can't find it, the medication entry flow can add a "
                'class-level match.',
          ),
          const SizedBox(height: V2Spacing.space16),
          PGPillButton(
            label: 'Add a medication',
            variant: PGPillVariant.ghost,
            icon: Icons.medication_outlined,
            onPressed: () => context.push(Routes.medicationEntry),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsList() {
    final filtered = _filteredResults;
    final partition = _partition(filtered);

    return Column(
      children: [
        // Header: count + view toggle (cream chips).
        Padding(
          padding: const EdgeInsets.fromLTRB(
            V2Spacing.space24,
            V2Spacing.space12,
            V2Spacing.space16,
            V2Spacing.space8,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _resultsHeaderText(partition),
                  style: V2Typography.caption(color: V2Colors.fgMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _ViewToggleChip(
                isGrid: false,
                selected: !_isGridView,
                onTap: () => setState(() => _isGridView = false),
              ),
              const SizedBox(width: V2Spacing.space8),
              _ViewToggleChip(
                isGrid: true,
                selected: _isGridView,
                onTap: () => setState(() => _isGridView = true),
              ),
            ],
          ),
        ),
        Expanded(
          child: _isGridView
              ? _buildGridSections(partition)
              : _buildListSections(partition),
        ),
      ],
    );
  }

  Widget _buildListSections(_PartitionedResults partition) {
    final children = <Widget>[];
    if (partition.onMarket.isNotEmpty) {
      children.add(
        _SectionEyebrow(
          label: 'On market',
          count: partition.onMarket.length,
          muted: false,
        ),
      );
      for (final p in partition.onMarket) {
        children.add(ProductListItem(product: p));
        children.add(const _HairlineDivider());
      }
    }
    if (partition.offMarket.isNotEmpty) {
      children.add(const SizedBox(height: V2Spacing.space16));
      children.add(
        _SectionEyebrow(
          label: 'Off market · older or discontinued',
          count: partition.offMarket.length,
          muted: true,
        ),
      );
      children.add(
        const Padding(
          padding: EdgeInsets.fromLTRB(
            V2Spacing.space24,
            V2Spacing.space4,
            V2Spacing.space24,
            V2Spacing.space12,
          ),
          child: Text(
            'Shown below the on-market matches so you can still find '
            'a product that was reformulated, renamed, or pulled. '
            'Tap to see the timeline.',
            style: TextStyle(
              fontSize: 12,
              color: V2Colors.fgMuted,
              height: 1.5,
            ),
          ),
        ),
      );
      for (final p in partition.offMarket) {
        children.add(Opacity(opacity: 0.7, child: ProductListItem(product: p)));
        children.add(const _HairlineDivider());
      }
    }
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(top: V2Spacing.space4),
      children: children,
    );
  }

  Widget _buildGridSections(_PartitionedResults partition) {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        if (partition.onMarket.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: _SectionEyebrow(
              label: 'On market',
              count: partition.onMarket.length,
              muted: false,
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(
              horizontal: V2Spacing.space24,
              vertical: V2Spacing.space8,
            ),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: V2Spacing.space12,
                mainAxisSpacing: V2Spacing.space12,
                childAspectRatio: 0.85,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) => ProductGridItem(product: partition.onMarket[i]),
                childCount: partition.onMarket.length,
              ),
            ),
          ),
        ],
        if (partition.offMarket.isNotEmpty) ...[
          const SliverToBoxAdapter(child: SizedBox(height: V2Spacing.space16)),
          SliverToBoxAdapter(
            child: _SectionEyebrow(
              label: 'Off market · older or discontinued',
              count: partition.offMarket.length,
              muted: true,
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(
              horizontal: V2Spacing.space24,
              vertical: V2Spacing.space8,
            ),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: V2Spacing.space12,
                mainAxisSpacing: V2Spacing.space12,
                childAspectRatio: 0.85,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) => Opacity(
                  opacity: 0.7,
                  child: ProductGridItem(product: partition.offMarket[i]),
                ),
                childCount: partition.offMarket.length,
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ───────── derived state ─────────

  List<ProductsCoreData> get _filteredResults {
    final results = _results;
    if (results == null) return const [];
    if (_activeCategoryChip != null) {
      return results
          .where((p) => p.primaryCategory == _activeCategoryChip)
          .toList();
    }
    if (_activeFilter == _SearchFilter.all) return results;
    return results.where(_activeFilter.matches).toList();
  }

  /// Partition the filtered results into on-market vs off-market.
  /// `discontinuedDate != null` → off-market. Sean 2026-05-16:
  /// on-market always renders first; off-market drops to the
  /// bottom of the page with a labeled section + helper line.
  _PartitionedResults _partition(List<ProductsCoreData> items) {
    final onMarket = <ProductsCoreData>[];
    final offMarket = <ProductsCoreData>[];
    for (final p in items) {
      final date = p.discontinuedDate;
      if (date != null && date.trim().isNotEmpty) {
        offMarket.add(p);
      } else {
        onMarket.add(p);
      }
    }
    return _PartitionedResults(onMarket: onMarket, offMarket: offMarket);
  }

  bool get _showFilterChips {
    if (_query.trim().isNotEmpty) return true;
    if (_loading) return true;
    if (_activeCategory != null && _activeCategory!.isNotEmpty) return true;
    return _results != null && _results!.isNotEmpty;
  }

  List<String> get _resultCategories {
    final results = _results;
    if (results == null || results.isEmpty) return const [];
    final seen = <String>{};
    final ordered = <String>[];
    for (final product in results) {
      final category = product.primaryCategory?.trim();
      if (category == null || category.isEmpty) continue;
      if (seen.add(category)) ordered.add(category);
    }
    return ordered;
  }

  String _resultsHeaderText(_PartitionedResults partition) {
    final total = _results?.length ?? 0;
    final visible = partition.onMarket.length + partition.offMarket.length;
    final on = partition.onMarket.length;
    final off = partition.offMarket.length;
    final filterActive =
        _activeFilter != _SearchFilter.all || _activeCategoryChip != null;
    if (filterActive) {
      return 'Showing $visible of $total — $on on market · $off off market';
    }
    if (off == 0) {
      return 'Showing $on result${on == 1 ? '' : 's'}';
    }
    return 'Showing $on on market · $off off market';
  }
}

// =============================================================================
// Top row — back chip + search field
// =============================================================================

class _TopRow extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String query;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final VoidCallback onBack;

  const _TopRow({
    required this.controller,
    required this.focusNode,
    required this.query,
    required this.onChanged,
    required this.onClear,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final focused = focusNode.hasFocus;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        V2Spacing.space8,
        V2Spacing.space12,
        V2Spacing.space16,
        V2Spacing.space4,
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: V2Colors.fg),
            onPressed: onBack,
            splashRadius: 22,
          ),
          Expanded(
            child: AnimatedContainer(
              duration: V2Motion.fast,
              curve: V2Motion.smooth,
              padding: const EdgeInsets.symmetric(
                horizontal: V2Spacing.space12,
              ),
              decoration: BoxDecoration(
                color: V2Colors.surface,
                borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
                border: Border.all(
                  color: focused ? V2Colors.accent : V2Colors.outline,
                  width: focused ? 1.5 : 1.0,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.search_rounded,
                    size: 18,
                    color: focused ? V2Colors.accent : V2Colors.fgSubtle,
                  ),
                  const SizedBox(width: V2Spacing.space8),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      autofocus: true,
                      maxLines: 1,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: 'Search supplements',
                        hintStyle: V2Typography.body(color: V2Colors.fgSubtle),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: V2Spacing.space12,
                        ),
                        isCollapsed: true,
                        isDense: true,
                      ),
                      style: V2Typography.body(color: V2Colors.fg),
                      cursorColor: V2Colors.accent,
                      cursorWidth: 1.5,
                      onChanged: onChanged,
                    ),
                  ),
                  if (query.isNotEmpty)
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: const Icon(
                        Icons.close_rounded,
                        size: 16,
                        color: V2Colors.fgSubtle,
                      ),
                      onPressed: onClear,
                      splashRadius: 16,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Filter row — quality filters + category chips.
// =============================================================================

class _FilterRow extends StatelessWidget {
  final _SearchFilter activeFilter;
  final ValueChanged<_SearchFilter> onFilterTap;
  final List<String> categories;
  final String? activeCategoryChip;
  final ValueChanged<String> onCategoryTap;

  const _FilterRow({
    required this.activeFilter,
    required this.onFilterTap,
    required this.categories,
    required this.activeCategoryChip,
    required this.onCategoryTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: V2Spacing.space24),
        children: [
          for (final f in _SearchFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: V2Spacing.space8),
              child: PGGoalChip(
                label: f.label,
                selected: activeFilter == f && activeCategoryChip == null,
                onTap: () => onFilterTap(f),
              ),
            ),
          for (final c in categories)
            Padding(
              padding: const EdgeInsets.only(right: V2Spacing.space8),
              child: PGGoalChip(
                label: _formatCategoryLabel(c),
                selected: activeCategoryChip == c,
                onTap: () => onCategoryTap(c),
              ),
            ),
        ],
      ),
    );
  }
}

// =============================================================================
// View toggle — cream pressable chip with a list / grid icon.
// =============================================================================

class _ViewToggleChip extends StatelessWidget {
  final bool isGrid;
  final bool selected;
  final VoidCallback onTap;

  const _ViewToggleChip({
    required this.isGrid,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected ? V2Colors.accentTint : V2Colors.surface;
    final border = selected ? V2Colors.accent : V2Colors.outline;
    final fg = selected ? V2Colors.accent : V2Colors.fgMuted;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: V2Motion.fast,
        curve: V2Motion.smooth,
        padding: const EdgeInsets.all(V2Spacing.space8),
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.rectangle,
          borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
          border: Border.all(color: border, width: selected ? 1.5 : 1.0),
        ),
        child: Icon(
          isGrid ? Icons.grid_view_rounded : Icons.view_list_rounded,
          size: 16,
          color: fg,
        ),
      ),
    );
  }
}

// =============================================================================
// Section eyebrow — mono caps + result count badge.
// =============================================================================

class _SectionEyebrow extends StatelessWidget {
  final String label;
  final int count;
  final bool muted;

  const _SectionEyebrow({
    required this.label,
    required this.count,
    required this.muted,
  });

  @override
  Widget build(BuildContext context) {
    final color = muted ? V2Colors.fgMuted : V2Colors.accent;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        V2Spacing.space24,
        V2Spacing.space12,
        V2Spacing.space24,
        V2Spacing.space8,
      ),
      child: Row(
        children: [
          PGEyebrow(label, color: color),
          const SizedBox(width: V2Spacing.space8),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: V2Spacing.space8,
              vertical: 2,
            ),
            decoration: BoxDecoration(
              color: muted ? V2Colors.outline : V2Colors.accentTint,
              borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
            ),
            child: Text('$count', style: V2Typography.eyebrow(color: color)),
          ),
        ],
      ),
    );
  }
}

class _HairlineDivider extends StatelessWidget {
  const _HairlineDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(left: 84, right: V2Spacing.space16),
      child: Divider(height: 0.5, thickness: 0.5, color: V2Colors.outline),
    );
  }
}

// =============================================================================
// Recent search row.
// =============================================================================

class _RecentSearchRow extends StatelessWidget {
  final String term;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _RecentSearchRow({
    required this.term,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: V2Colors.surface,
      borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
            border: Border.all(color: V2Colors.outline),
          ),
          padding: const EdgeInsets.fromLTRB(
            V2Spacing.space16,
            V2Spacing.space12,
            V2Spacing.space8,
            V2Spacing.space12,
          ),
          child: Row(
            children: [
              const Icon(
                Icons.history_rounded,
                size: 18,
                color: V2Colors.fgMuted,
              ),
              const SizedBox(width: V2Spacing.space12),
              Expanded(
                child: Text(
                  term,
                  style: V2Typography.bodyMedium(color: V2Colors.fg),
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: V2Colors.fgSubtle,
                ),
                onPressed: onRemove,
                splashRadius: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Loading list — six cream skeleton rows.
// =============================================================================

class _LoadingList extends StatelessWidget {
  const _LoadingList();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        V2Spacing.space24,
        V2Spacing.space12,
        V2Spacing.space24,
        V2Spacing.space24,
      ),
      children: [
        for (var i = 0; i < 6; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: V2Spacing.space8),
            child: Container(
              padding: const EdgeInsets.all(V2Spacing.space12),
              decoration: BoxDecoration(
                color: V2Colors.surface,
                borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
                border: Border.all(color: V2Colors.outline),
              ),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: V2Colors.outline,
                      borderRadius: BorderRadius.circular(V2Spacing.space8),
                    ),
                  ),
                  const SizedBox(width: V2Spacing.space16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 180,
                          height: 12,
                          decoration: BoxDecoration(
                            color: V2Colors.outline,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(height: V2Spacing.space8),
                        Container(
                          width: 110,
                          height: 10,
                          decoration: BoxDecoration(
                            color: V2Colors.outline,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// =============================================================================
// Helpers
// =============================================================================

class _PartitionedResults {
  final List<ProductsCoreData> onMarket;
  final List<ProductsCoreData> offMarket;
  const _PartitionedResults({required this.onMarket, required this.offMarket});
}

enum _SearchFilter {
  all('All'),
  highQuality('High quality (80+)'),
  needsReview('Needs review'),
  blockedUnsafe('Blocked / Unsafe');

  const _SearchFilter(this.label);
  final String label;

  bool matches(ProductsCoreData p) {
    switch (this) {
      case _SearchFilter.all:
        return true;
      case _SearchFilter.highQuality:
        return (p.score100Equivalent ?? 0) >= 80;
      case _SearchFilter.needsReview:
        final v = (p.verdict ?? '').toUpperCase();
        return v == 'CAUTION' ||
            v == 'POOR' ||
            v == 'MODERATE' ||
            v == 'REVIEW';
      case _SearchFilter.blockedUnsafe:
        final v = (p.verdict ?? '').toUpperCase();
        return v == 'BLOCKED' || v == 'UNSAFE';
    }
  }
}

String _formatCategoryLabel(String category) {
  final parts = category.split('_').where((part) => part.trim().isNotEmpty).map(
    (part) {
      final lower = part.toLowerCase();
      return '${lower[0].toUpperCase()}${lower.substring(1)}';
    },
  ).toList();
  return parts.join(' ');
}
