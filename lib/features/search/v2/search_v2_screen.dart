// Search v2 — production catalog search surface.
//
// Catalog behavior is preserved while v2 owns the production route:
// **on-market results render first, off-market falls to a labeled
// section at the bottom of the list.**
//
// Same providers (`coreDatabaseProvider`,
// `recentSearchesServiceProvider`), same `searchProducts` /
// `filterProducts` calls, same 300ms debounce + latest-query-wins
// semantics, same quality + category chip vocabulary, same recent-
// search persistence, same deep-link initial query handling. The
// only behavior delta is the partition + ordering of results.
//
// Visual contract:
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
//     body).
//   * Sticky empty hint about MedicationEntry uses
//     `PGPillButton.ghost`.
//
// Behavior contract:
//
//   * The `searchProducts` / `filterProducts` queries.
//   * The `RecentSearchesService` add/remove/clear contract.
//   * The four `_SearchFilter` values (All / High Quality 80+ /
//     Needs Review / Blocked / Unsafe).
//   * Category chip derivation from the result set.
//   * List vs grid toggle — keep, render local v2 product rows/cards.
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
import 'package:pharmaguide/core/presentation/package_identity.dart';
import 'package:pharmaguide/core/scoring/coverage.dart';
import 'package:pharmaguide/core/scoring/score_tier.dart';
import 'package:pharmaguide/core/widgets/verdict_badge.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_motion.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/core/widgets/pg_haptics.dart';
import 'package:pharmaguide/core/widgets/product_image.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/services/recent_searches_service.dart';

const _searchGridChildAspectRatio = 0.54;

class SearchV2Screen extends ConsumerStatefulWidget {
  final String? initialCategory;
  final String? initialQuery;

  const SearchV2Screen({super.key, this.initialCategory, this.initialQuery});

  @override
  ConsumerState<SearchV2Screen> createState() => _SearchV2ScreenState();
}

class _SearchV2ScreenState extends ConsumerState<SearchV2Screen> {
  static const _searchPageSize = 20;

  // ───────── controllers + ephemeral state ─────────
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _resultsScrollController = ScrollController();

  String _query = '';
  String? _activeCategory;
  List<ProductsCoreData>? _results;
  List<ProductsCoreData> _featuredProducts = const [];
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMoreResults = false;
  bool _isGridView = false;

  /// True once the current query has been committed — keyboard submit,
  /// a Suggested Search tap, or opening a result. While committed the
  /// Suggested Searches block stays hidden; editing the query text
  /// flips back to exploring and brings suggestions back.
  bool _committed = false;
  List<String> _recentSearches = [];
  _SearchFilter _activeFilter = _SearchFilter.all;
  String? _activeCategoryChip;

  Timer? _debounce;
  int _searchVersion = 0;
  DateTime? _lastTypingHapticAt;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() => setState(() {}));
    _resultsScrollController.addListener(_maybeLoadMoreResults);
    _activeCategory = widget.initialCategory;
    _loadRecentSearches();
    _loadFeaturedProducts();
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

  Future<void> _loadFeaturedProducts() async {
    try {
      final db = ref.read(coreDatabaseProvider);
      final products = await db.filterProducts(sortBy: 'score', limit: 24);
      if (mounted) {
        setState(
          () => _featuredProducts = _selectWorthCheckingProducts(products),
        );
      }
    } on Exception {
      if (mounted) setState(() => _featuredProducts = const []);
    }
  }

  Future<void> _loadCategoryResults(String category) async {
    // Share the monotonic search token with _executeSearch: tapping a category
    // then quickly typing (or vice-versa) must let the LATEST request win.
    // Without this, a slow category load lands after a newer query search and
    // clobbers _results with stale category rows.
    final version = ++_searchVersion;
    setState(() => _loading = true);
    final db = ref.read(coreDatabaseProvider);
    try {
      final results = await db.filterProducts(
        category: category,
        limit: 50,
        sortBy: 'score',
      );
      if (version != _searchVersion) return;
      if (!mounted) return;
      setState(() {
        _results = results;
        _loading = false;
        _loadingMore = false;
        _hasMoreResults = false;
      });
    } on Exception {
      if (version != _searchVersion) return;
      if (!mounted) return;
      setState(() {
        _results = <ProductsCoreData>[];
        _loading = false;
        _loadingMore = false;
        _hasMoreResults = false;
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    _resultsScrollController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _maybeTypingHaptic(value);
    setState(() {
      _query = value;
      _committed = false;
      if (value.trim().isNotEmpty) _activeCategory = null;
      _activeCategoryChip = null;
      _loadingMore = false;
      _hasMoreResults = false;
    });

    if (value.trim().isEmpty) {
      setState(() {
        _results = _activeCategory == null ? null : _results;
        _loading = false;
        _loadingMore = false;
        _hasMoreResults = false;
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

  void _maybeTypingHaptic(String value) {
    final trimmedLength = value.trim().length;
    if (trimmedLength < 2) return;
    final now = DateTime.now();
    final previous = _lastTypingHapticAt;
    if (previous != null &&
        now.difference(previous) < const Duration(milliseconds: 140)) {
      return;
    }
    _lastTypingHapticAt = now;
    unawaited(PGHaptics.tap(context));
  }

  Future<void> _executeSearch(String query, {bool recordRecent = false}) async {
    final version = ++_searchVersion;
    final db = ref.read(coreDatabaseProvider);
    try {
      final results = await db.searchProducts(query, limit: _searchPageSize);
      if (version != _searchVersion) return;
      if (!mounted) return;
      setState(() {
        _results = results;
        _loading = false;
        _loadingMore = false;
        _hasMoreResults = results.length == _searchPageSize;
      });
      if (_resultsScrollController.hasClients) {
        _resultsScrollController.jumpTo(
          _resultsScrollController.position.minScrollExtent,
        );
      }
      // Recents are recorded only on commit (submit / suggestion tap /
      // result open) — never on debounce ticks while typing.
      if (recordRecent && results.isNotEmpty) {
        await _recentService.addSearch(query);
        await _loadRecentSearches();
      }
    } on Exception {
      if (version != _searchVersion) return;
      if (!mounted) return;
      setState(() {
        _results = <ProductsCoreData>[];
        _loading = false;
        _loadingMore = false;
        _hasMoreResults = false;
      });
    }
  }

  void _maybeLoadMoreResults() {
    if (!_resultsScrollController.hasClients) return;
    if (_resultsScrollController.position.extentAfter > 520) return;
    unawaited(_loadMoreSearchResults());
  }

  Future<void> _loadMoreSearchResults() async {
    final q = _query.trim();
    if (q.isEmpty || _loading || _loadingMore || !_hasMoreResults) return;
    final currentResults = _results;
    if (currentResults == null || currentResults.isEmpty) return;

    final version = _searchVersion;
    setState(() => _loadingMore = true);
    final db = ref.read(coreDatabaseProvider);
    try {
      final next = await db.searchProducts(
        q,
        limit: _searchPageSize,
        offset: currentResults.length,
      );
      if (version != _searchVersion || q != _query.trim()) return;
      if (!mounted) return;
      setState(() {
        _results = [...currentResults, ...next];
        _loadingMore = false;
        _hasMoreResults = next.length == _searchPageSize;
      });
    } on Exception {
      if (version != _searchVersion) return;
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _hasMoreResults = false;
      });
    }
  }

  /// Commit a search: run it immediately (no debounce) and record it
  /// in recent searches. Used by keyboard submit, Suggested Search
  /// taps, and Recent Search taps.
  void _commitSearch(String query) {
    final q = query.trim();
    if (q.isEmpty) return;
    _debounce?.cancel();
    setState(() {
      _query = q;
      _committed = true;
      _activeCategory = null;
      _activeCategoryChip = null;
      _loading = true;
    });
    _executeSearch(q, recordRecent: true);
  }

  /// Opening a product result counts as committing the query that led
  /// there — record it once, without re-running the search.
  void _recordResultOpen() {
    final q = _query.trim();
    if (q.isEmpty) return;
    setState(() => _committed = true);
    unawaited(_recentService.addSearch(q).then((_) => _loadRecentSearches()));
  }

  void _clearSearch() {
    unawaited(PGHaptics.tap(context));
    _debounce?.cancel();
    _controller.clear();
    setState(() {
      _query = '';
      _committed = false;
      _results = null;
      _loading = false;
      _activeCategory = null;
      _activeFilter = _SearchFilter.all;
      _activeCategoryChip = null;
      _loadingMore = false;
      _hasMoreResults = false;
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
              onSubmitted: _commitSearch,
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
    final children = <Widget>[];
    if (_recentSearches.isNotEmpty) {
      children.addAll([
        Row(
          children: [
            const _SearchSectionTitle('Recent Searches'),
            const Spacer(),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () async {
                await _recentService.clearAll();
                await _loadRecentSearches();
              },
              child: Text(
                'Clear All',
                style: V2Typography.body(color: V2Colors.fgMuted),
              ),
            ),
          ],
        ),
        const SizedBox(height: V2Spacing.space16),
        ..._recentSearches.map(
          (term) => Padding(
            padding: const EdgeInsets.only(bottom: V2Spacing.space12),
            child: _RecentSearchRow(
              term: term,
              onTap: () {
                _controller.text = term;
                _commitSearch(term);
              },
              onRemove: () async {
                await _recentService.removeSearch(term);
                await _loadRecentSearches();
              },
            ),
          ),
        ),
      ]);
    }

    if (_featuredProducts.isNotEmpty) {
      if (children.isNotEmpty) {
        children.add(const SizedBox(height: V2Spacing.space24));
      }
      children.add(const _SearchSectionTitle('Worth checking'));
      children.add(const SizedBox(height: V2Spacing.space16));
      children.add(_ProductPreviewGrid(products: _featuredProducts));
    }

    if (children.isNotEmpty) {
      children.add(const SizedBox(height: V2Spacing.space24));
    }
    children.add(
      _CommonSearchesSection(
        onTap: (query) {
          _controller.text = query;
          _commitSearch(query);
        },
      ),
    );

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        V2Spacing.space24,
        V2Spacing.space32,
        V2Spacing.space24,
        V2Spacing.space24,
      ),
      children: children,
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
    if (_query.trim().isNotEmpty) {
      return _buildDiscoveryResults(partition);
    }

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

  Widget _buildDiscoveryResults(_PartitionedResults partition) {
    // Once a search is committed, suggestions hide and results lead.
    // Editing the query (exploring) brings them back.
    final suggestions = _committed
        ? const <_SearchSuggestion>[]
        : _buildSuggestions(_query, partition.onMarket);
    final products = partition.onMarket.isNotEmpty
        ? partition.onMarket
        : partition.offMarket;
    return ListView(
      controller: _resultsScrollController,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        V2Spacing.space24,
        V2Spacing.space32,
        V2Spacing.space24,
        V2Spacing.space24,
      ),
      children: [
        if (suggestions.isNotEmpty) ...[
          const _SearchSectionTitle('Suggested Searches'),
          const SizedBox(height: V2Spacing.space16),
          for (final suggestion in suggestions)
            Padding(
              padding: const EdgeInsets.only(bottom: V2Spacing.space24),
              child: _SuggestedSearchRow(
                suggestion: suggestion,
                onTap: () {
                  _controller.text = suggestion.query;
                  _commitSearch(suggestion.query);
                },
              ),
            ),
          const SizedBox(height: V2Spacing.space12),
        ],
        const _SearchSectionTitle('Suggested Products'),
        const SizedBox(height: V2Spacing.space16),
        _ProductPreviewGrid(
          products: products,
          onProductOpen: _recordResultOpen,
        ),
        if (partition.offMarket.isNotEmpty &&
            partition.onMarket.isNotEmpty) ...[
          const SizedBox(height: V2Spacing.space24),
          _SectionEyebrow(
            label: 'Off market · older or discontinued',
            count: partition.offMarket.length,
            muted: true,
          ),
          _ProductPreviewGrid(
            products: partition.offMarket.take(4),
            onProductOpen: _recordResultOpen,
          ),
        ],
        if (_hasMoreResults || _loadingMore)
          _LoadingMoreFooter(loading: _loadingMore),
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
        children.add(_SearchProductListTile(product: p));
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
        children.add(
          Opacity(opacity: 0.7, child: _SearchProductListTile(product: p)),
        );
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
                childAspectRatio: _searchGridChildAspectRatio,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) =>
                    _SearchProductGridTile(product: partition.onMarket[i]),
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
                childAspectRatio: _searchGridChildAspectRatio,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) => Opacity(
                  opacity: 0.7,
                  child: _SearchProductGridTile(
                    product: partition.offMarket[i],
                  ),
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
    if (_query.trim().isNotEmpty) return false;
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

List<ProductsCoreData> _selectWorthCheckingProducts(
  List<ProductsCoreData> products,
) {
  final selected = <ProductsCoreData>[];
  final seenCategories = <String>{};
  final seenBrands = <String>{};

  bool eligible(ProductsCoreData product) {
    final discontinued = product.discontinuedDate?.trim();
    if (discontinued != null && discontinued.isNotEmpty) return false;
    final verdict = product.verdict?.trim().toUpperCase();
    if (verdict == 'BLOCKED' || verdict == 'UNSAFE') return false;
    final blockingReason = product.blockingReason?.trim();
    return blockingReason == null || blockingReason.isEmpty;
  }

  for (final product in products.where(eligible)) {
    final category = product.primaryCategory?.trim().toLowerCase() ?? '';
    final brand = product.brandName?.trim().toLowerCase() ?? '';
    if (category.isNotEmpty && seenCategories.contains(category)) continue;
    if (brand.isNotEmpty && seenBrands.contains(brand)) continue;
    selected.add(product);
    if (category.isNotEmpty) seenCategories.add(category);
    if (brand.isNotEmpty) seenBrands.add(brand);
    if (selected.length == 4) return selected;
  }

  if (selected.length == 4) return selected;
  final selectedIds = selected.map((p) => p.dsldId).toSet();
  for (final product in products.where(eligible)) {
    if (!selectedIds.add(product.dsldId)) continue;
    selected.add(product);
    if (selected.length == 4) break;
  }
  return selected;
}

// =============================================================================
// Top row — back chip + search field
// =============================================================================

class _TopRow extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String query;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;
  final VoidCallback onBack;

  const _TopRow({
    required this.controller,
    required this.focusNode,
    required this.query,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final focused = focusNode.hasFocus;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        V2Spacing.space24,
        V2Spacing.space16,
        V2Spacing.space24,
        V2Spacing.space8,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: Material(
              color: V2Colors.surface,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () {
                  unawaited(PGHaptics.tap(context));
                  onBack();
                },
                child: const Icon(
                  Icons.arrow_back_rounded,
                  color: V2Colors.fg,
                  size: 27,
                ),
              ),
            ),
          ),
          const SizedBox(width: V2Spacing.space16),
          Expanded(
            child: AnimatedContainer(
              duration: V2Motion.fast,
              curve: V2Motion.smooth,
              height: 56,
              padding: const EdgeInsets.symmetric(
                horizontal: V2Spacing.space16,
              ),
              decoration: BoxDecoration(
                color: V2Colors.surface,
                borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
                border: Border.all(
                  color: focused
                      ? V2Colors.safe.withValues(alpha: 0.26)
                      : Colors.transparent,
                  width: 1.0,
                ),
                boxShadow: focused ? V2Shadows.sm : null,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.search_rounded,
                    size: 30,
                    color: focused ? V2Colors.safe : V2Colors.fgMuted,
                  ),
                  const SizedBox(width: V2Spacing.space12),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      autofocus: true,
                      maxLines: 1,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: 'Search supplements',
                        hintStyle: V2Typography.bodyXl(
                          color: V2Colors.fgSubtle,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: V2Spacing.space16,
                        ),
                        isCollapsed: true,
                        isDense: true,
                      ),
                      style: V2Typography.bodyXl(color: V2Colors.fg),
                      cursorColor: V2Colors.safe,
                      cursorWidth: 2,
                      onChanged: onChanged,
                      onSubmitted: onSubmitted,
                    ),
                  ),
                  if (query.isNotEmpty)
                    Material(
                      color: V2Colors.fgMuted,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: onClear,
                        child: const SizedBox(
                          width: 26,
                          height: 26,
                          child: Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: V2Colors.surface,
                          ),
                        ),
                      ),
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
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          unawaited(PGHaptics.tap(context));
          onTap();
        },
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: V2Spacing.space4),
          child: Row(
            children: [
              const Icon(Icons.search_rounded, size: 26, color: V2Colors.safe),
              const SizedBox(width: V2Spacing.space16),
              Expanded(
                child: Text(
                  term,
                  style: V2Typography.bodyXl(color: V2Colors.fgMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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

class _CommonSearchesSection extends StatelessWidget {
  final ValueChanged<String> onTap;

  const _CommonSearchesSection({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SearchSectionTitle('Common searches'),
        const SizedBox(height: V2Spacing.space16),
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: _commonSearches.length,
            separatorBuilder: (_, _) => const SizedBox(width: V2Spacing.space8),
            itemBuilder: (context, index) {
              final item = _commonSearches[index];
              return PGGoalChip(
                label: item.label,
                selected: false,
                onTap: () {
                  unawaited(PGHaptics.tap(context));
                  onTap(item.query);
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SearchSectionTitle extends StatelessWidget {
  final String label;

  const _SearchSectionTitle(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: V2Typography.displayXs(
        color: V2Colors.fgMuted,
      ).copyWith(letterSpacing: 0),
    );
  }
}

class _SuggestedSearchRow extends StatelessWidget {
  final _SearchSuggestion suggestion;
  final VoidCallback onTap;

  const _SuggestedSearchRow({required this.suggestion, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: suggestion.semanticLabel,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            unawaited(PGHaptics.tap(context));
            onTap();
          },
          borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: V2Spacing.space4),
            child: Row(
              children: [
                _SuggestionGlyph(
                  kind: suggestion.iconKind,
                  color: suggestion.iconColor,
                ),
                const SizedBox(width: V2Spacing.space16),
                Expanded(
                  child: RichText(
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      style: V2Typography.bodyXl(color: V2Colors.fgMuted),
                      children: [
                        TextSpan(
                          text: suggestion.label,
                          style: V2Typography.bodyXl(
                            color: V2Colors.fg,
                          ).copyWith(fontWeight: FontWeight.w500),
                        ),
                        if (suggestion.scopeLabel != null)
                          TextSpan(text: ' in ${suggestion.scopeLabel}'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductPreviewGrid extends StatelessWidget {
  final List<ProductsCoreData> products;
  final VoidCallback? onProductOpen;

  _ProductPreviewGrid({
    required Iterable<ProductsCoreData> products,
    this.onProductOpen,
  }) : products = products.toList(growable: false);

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) return const SizedBox.shrink();
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: products.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: V2Spacing.space12,
        mainAxisSpacing: V2Spacing.space12,
        childAspectRatio: _searchGridChildAspectRatio,
      ),
      itemBuilder: (context, index) => _SearchProductGridTile(
        product: products[index],
        onOpen: onProductOpen,
      ),
    );
  }
}

class _SuggestionGlyph extends StatelessWidget {
  final _SuggestionIconKind kind;
  final Color color;

  const _SuggestionGlyph({required this.kind, required this.color});

  @override
  Widget build(BuildContext context) {
    if (kind == _SuggestionIconKind.search) {
      return Icon(Icons.search_rounded, size: 28, color: color);
    }
    return SizedBox(
      width: 28,
      height: 28,
      child: CustomPaint(
        painter: switch (kind) {
          _SuggestionIconKind.brand => _BrandGlyphPainter(color),
          _SuggestionIconKind.ingredient => _IngredientGlyphPainter(color),
          _SuggestionIconKind.search => null,
        },
      ),
    );
  }
}

class _BrandGlyphPainter extends CustomPainter {
  final Color color;

  const _BrandGlyphPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final w = size.width;
    final h = size.height;
    for (final y in [h * 0.22, h * 0.40, h * 0.58]) {
      final path = Path()
        ..moveTo(w * 0.16, y)
        ..lineTo(w * 0.50, y - h * 0.13)
        ..lineTo(w * 0.84, y)
        ..lineTo(w * 0.50, y + h * 0.13)
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BrandGlyphPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _IngredientGlyphPainter extends CustomPainter {
  final Color color;

  const _IngredientGlyphPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final w = size.width;
    final h = size.height;
    final bowl = Path()
      ..moveTo(w * 0.18, h * 0.46)
      ..lineTo(w * 0.82, h * 0.46)
      ..quadraticBezierTo(w * 0.72, h * 0.78, w * 0.50, h * 0.78)
      ..quadraticBezierTo(w * 0.28, h * 0.78, w * 0.18, h * 0.46);
    canvas.drawPath(bowl, paint);
    canvas.drawLine(
      Offset(w * 0.34, h * 0.84),
      Offset(w * 0.66, h * 0.84),
      paint,
    );
    canvas.drawLine(
      Offset(w * 0.58, h * 0.34),
      Offset(w * 0.78, h * 0.16),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _IngredientGlyphPainter oldDelegate) {
    return oldDelegate.color != color;
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

class _LoadingMoreFooter extends StatelessWidget {
  final bool loading;

  const _LoadingMoreFooter({required this.loading});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: V2Spacing.space24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (loading)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: V2Colors.fgSubtle,
              ),
            )
          else
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                border: Border.all(color: V2Colors.fgSubtle, width: 1.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          const SizedBox(width: V2Spacing.space12),
          Text(
            'Loading more',
            style: V2Typography.bodySm(color: V2Colors.fgMuted),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Search result cards — local v2 surfaces, same product-detail route contract.
// =============================================================================

class _SearchProductListTile extends StatelessWidget {
  final ProductsCoreData product;

  const _SearchProductListTile({required this.product});

  @override
  Widget build(BuildContext context) {
    final score = product.qualityScoreV4100;
    // Verdict/coverage-gated chip decisions (FIX 3) — a low-coverage or
    // blocked product must never surface a confident tier-colored score.
    final scoreChip = searchScoreChipDisplayFor(
      score: score,
      verdict: product.verdict,
      mappedCoverage: product.mappedCoverage,
      v4Confidence: product.v4Confidence,
    );
    final showVerdictChip = searchShowsVerdictChip(
      verdict: product.verdict,
      mappedCoverage: product.mappedCoverage,
    );
    // Announce the numeric score only when the visual chip shows it —
    // screen-reader users must not hear a score the coverage/verdict
    // gates suppressed.
    final scoreLabel =
        scoreChip == SearchScoreChipDisplay.tierScore ||
            scoreChip == SearchScoreChipDisplay.limitedAssessment
        ? ', score ${score!.round()} out of 100'
        : '';
    final brandLabel = product.brandName?.trim().isNotEmpty == true
        ? ' by ${product.brandName}'
        : '';
    final packSizeLabel = _packSizeLabel(product);
    final packSemantics = packSizeLabel == null ? '' : ', $packSizeLabel';

    return Semantics(
      button: true,
      label:
          '${product.productName}$brandLabel$packSemantics$scoreLabel. Tap to view details.',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => context.push('${Routes.product}/${product.dsldId}'),
          splashColor: V2Colors.accent.withValues(alpha: 0.08),
          highlightColor: V2Colors.accent.withValues(alpha: 0.04),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: V2Spacing.space24,
              vertical: V2Spacing.space12,
            ),
            child: Row(
              children: [
                _SearchProductImage(product: product, size: 56),
                const SizedBox(width: V2Spacing.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        product.productName,
                        style: V2Typography.bodyMedium(color: V2Colors.fg),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (product.brandName?.trim().isNotEmpty == true) ...[
                        const SizedBox(height: V2Spacing.space4),
                        Text(
                          product.brandName!,
                          style: V2Typography.caption(color: V2Colors.fgMuted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (packSizeLabel != null) ...[
                        const SizedBox(height: V2Spacing.space4),
                        Text(
                          packSizeLabel,
                          style: V2Typography.caption(color: V2Colors.fgMuted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: V2Spacing.space8),
                      Wrap(
                        spacing: V2Spacing.space8,
                        runSpacing: V2Spacing.space4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (scoreChip == SearchScoreChipDisplay.tierScore)
                            _ScoreChip(score: score!),
                          if (scoreChip ==
                              SearchScoreChipDisplay.limitedAssessment)
                            _LimitedAssessmentChip(score: score!),
                          if (scoreChip == SearchScoreChipDisplay.limitedData)
                            const _LimitedDataChip(),
                          if (showVerdictChip)
                            _VerdictChip(label: product.verdict!),
                          if (product.primaryCategory?.trim().isNotEmpty ==
                              true)
                            _CategoryText(product.primaryCategory!),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: V2Spacing.space8),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: V2Colors.fgSubtle,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchProductGridTile extends StatelessWidget {
  final ProductsCoreData product;
  final VoidCallback? onOpen;

  const _SearchProductGridTile({required this.product, this.onOpen});

  @override
  Widget build(BuildContext context) {
    final score = product.qualityScoreV4100;
    // Same verdict/coverage chip gating as the list tile (FIX 3).
    final scoreChip = searchScoreChipDisplayFor(
      score: score,
      verdict: product.verdict,
      mappedCoverage: product.mappedCoverage,
      v4Confidence: product.v4Confidence,
    );
    final showVerdictChip = searchShowsVerdictChip(
      verdict: product.verdict,
      mappedCoverage: product.mappedCoverage,
    );
    final scoreLabel =
        scoreChip == SearchScoreChipDisplay.tierScore ||
            scoreChip == SearchScoreChipDisplay.limitedAssessment
        ? ', score ${score!.round()} out of 100'
        : '';
    final brandLabel = product.brandName?.trim().isNotEmpty == true
        ? ' by ${product.brandName}'
        : '';
    final packSizeLabel = _packSizeLabel(product);
    final packSemantics = packSizeLabel == null ? '' : ', $packSizeLabel';

    return Semantics(
      button: true,
      label:
          '${product.productName}$brandLabel$packSemantics$scoreLabel. Tap to view details.',
      child: Container(
        decoration: BoxDecoration(
          color: V2Colors.surface,
          borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
          border: Border.all(color: V2Colors.outline),
          boxShadow: V2Shadows.sm,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
          child: InkWell(
            onTap: () {
              onOpen?.call();
              context.push('${Routes.product}/${product.dsldId}');
            },
            borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AspectRatio(
                  aspectRatio: 1.18,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: V2Colors.surfaceContainerHighest.withValues(
                              alpha: 0.42,
                            ),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(V2Spacing.radiusCard),
                            ),
                          ),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final imageSize =
                                  (constraints.biggest.shortestSide -
                                          V2Spacing.space24)
                                      .clamp(76.0, 132.0)
                                      .toDouble();
                              return Center(
                                child: _SearchProductImage(
                                  product: product,
                                  size: imageSize,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      Positioned(
                        top: V2Spacing.space8,
                        right: V2Spacing.space8,
                        child: switch (scoreChip) {
                          SearchScoreChipDisplay.tierScore => _ScoreChip(
                            score: score!,
                          ),
                          SearchScoreChipDisplay.limitedData =>
                            const _LimitedDataChip(),
                          SearchScoreChipDisplay.limitedAssessment =>
                            _LimitedAssessmentChip(score: score!),
                          SearchScoreChipDisplay.hidden =>
                            const SizedBox.shrink(),
                        },
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      V2Spacing.space12,
                      V2Spacing.space12,
                      V2Spacing.space12,
                      V2Spacing.space12,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (product.brandName?.trim().isNotEmpty == true) ...[
                          Text(
                            product.brandName!,
                            style: V2Typography.caption(
                              color: V2Colors.fgMuted,
                            ).copyWith(letterSpacing: 0),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: V2Spacing.space4),
                        ],
                        Text(
                          product.productName,
                          style: V2Typography.label(
                            color: V2Colors.fg,
                          ).copyWith(letterSpacing: 0),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (packSizeLabel != null) ...[
                          const SizedBox(height: V2Spacing.space8),
                          Text(
                            packSizeLabel,
                            style: V2Typography.bodySm(
                              color: V2Colors.fgMuted,
                            ).copyWith(letterSpacing: 0),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        if (showVerdictChip) ...[
                          const Spacer(),
                          _VerdictChip(label: product.verdict!),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchProductImage extends StatelessWidget {
  final ProductsCoreData product;
  final double size;

  const _SearchProductImage({required this.product, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(V2Spacing.space4),
      decoration: BoxDecoration(
        color: V2Colors.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        border: Border.all(color: V2Colors.outline),
      ),
      child: ProductImage(
        dsldId: product.dsldId,
        upc: product.upcSku,
        dsldImagePath: product.imageThumbnailUrl,
        productName: product.productName,
        brandName: product.brandName ?? '',
        formFactor: product.formFactor,
        score: product.qualityScoreV4100,
        size: size - (V2Spacing.space4 * 2),
        compact: true,
      ),
    );
  }
}

class _ScoreChip extends StatelessWidget {
  final double score;

  const _ScoreChip({required this.score});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: V2Spacing.space8,
        vertical: V2Spacing.space4,
      ),
      decoration: BoxDecoration(
        // Background keeps the brighter chart token (tinted at 0.12).
        color: _scoreTone(score).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
      ),
      child: Text(
        '${score.round()}',
        // Text uses the accessible tier token (>=4.5:1 on the tinted chip).
        style: V2Typography.monoData(
          color: tierForScore(score.round()).textColor,
        ),
      ),
    );
  }
}

/// Neutral chip for scored-but-low-coverage products — same pill shape as
/// [_ScoreChip] but muted tone and no number, so "we can't confidently
/// score this" never reads as a quality tier.
class _LimitedDataChip extends StatelessWidget {
  const _LimitedDataChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: V2Spacing.space8,
        vertical: V2Spacing.space4,
      ),
      decoration: BoxDecoration(
        color: V2Colors.fgMuted.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
      ),
      child: Text(
        'Limited data',
        style: V2Typography.caption(color: V2Colors.fgMuted),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _LimitedAssessmentChip extends StatelessWidget {
  final double score;

  const _LimitedAssessmentChip({required this.score});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: V2Spacing.space8,
        vertical: V2Spacing.space4,
      ),
      decoration: BoxDecoration(
        color: V2Colors.fgMuted.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
      ),
      child: Text(
        '${score.round()} · Limited assessment',
        style: V2Typography.caption(color: V2Colors.fgMuted),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _VerdictChip extends StatelessWidget {
  final String label;

  const _VerdictChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final tone = searchVerdictTone(label);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: V2Spacing.space8,
        vertical: V2Spacing.space4,
      ),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
      ),
      child: Text(
        label.toUpperCase(),
        style: V2Typography.overline(color: tone),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _CategoryText extends StatelessWidget {
  final String category;

  const _CategoryText(this.category);

  @override
  Widget build(BuildContext context) {
    return Text(
      _formatCategoryLabel(category),
      style: V2Typography.caption(color: V2Colors.fgMuted),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

// =============================================================================
// Helpers
// =============================================================================

class _SearchSuggestion {
  final String label;
  final String query;
  final String? scopeLabel;
  final _SuggestionIconKind iconKind;
  final Color iconColor;

  const _SearchSuggestion({
    required this.label,
    required this.query,
    required this.iconKind,
    required this.iconColor,
    this.scopeLabel,
  });

  String get semanticLabel =>
      scopeLabel == null ? label : '$label in $scopeLabel';
}

class _PartitionedResults {
  final List<ProductsCoreData> onMarket;
  final List<ProductsCoreData> offMarket;
  const _PartitionedResults({required this.onMarket, required this.offMarket});
}

class _CommonSearch {
  final String label;
  final String query;

  const _CommonSearch(this.label, this.query);
}

const _commonSearches = <_CommonSearch>[
  _CommonSearch('Magnesium', 'Magnesium'),
  _CommonSearch('Vitamin D + K', 'Vitamin D K'),
  _CommonSearch('Iron', 'Iron'),
  _CommonSearch('EPA/DHA', 'EPA DHA'),
  _CommonSearch('Creatine', 'Creatine'),
  _CommonSearch('Probiotics', 'Probiotics'),
  _CommonSearch('CoQ10', 'CoQ10'),
  _CommonSearch('Ashwagandha', 'Ashwagandha'),
];

enum _SuggestionIconKind { brand, ingredient, search }

List<_SearchSuggestion> _buildSuggestions(
  String query,
  List<ProductsCoreData> products,
) {
  final q = query.trim();
  if (q.length < 2 || products.isEmpty) return const [];

  final normalizedQuery = q.toLowerCase();
  final out = <_SearchSuggestion>[];
  final seen = <String>{};

  void add(_SearchSuggestion suggestion) {
    final key = '${suggestion.scopeLabel ?? 'search'}:${suggestion.label}'
        .toLowerCase();
    if (seen.add(key)) out.add(suggestion);
  }

  for (final product in products) {
    final brand = product.brandName?.trim();
    if (brand != null &&
        brand.isNotEmpty &&
        brand.toLowerCase().contains(normalizedQuery)) {
      add(
        _SearchSuggestion(
          label: brand,
          query: brand,
          scopeLabel: 'Brand',
          iconKind: _SuggestionIconKind.brand,
          iconColor: V2Colors.accentStrong,
        ),
      );
      break;
    }
  }

  for (final term in _candidateIngredientTerms(normalizedQuery, products)) {
    add(
      _SearchSuggestion(
        label: term,
        query: term,
        scopeLabel: 'Ingredient',
        iconKind: _SuggestionIconKind.ingredient,
        iconColor: V2Colors.accentStrong,
      ),
    );
    if (out.length >= 4) return out;
  }

  for (final product in products) {
    final name = product.productName.trim();
    if (name.isEmpty) continue;
    if (!name.toLowerCase().contains(normalizedQuery)) continue;
    add(
      _SearchSuggestion(
        label: _compactProductQuery(name, normalizedQuery),
        query: _compactProductQuery(name, normalizedQuery),
        iconKind: _SuggestionIconKind.search,
        iconColor: V2Colors.safe,
      ),
    );
    if (out.length >= 4) return out;
  }

  if (out.isEmpty) {
    add(
      _SearchSuggestion(
        label: q,
        query: q,
        iconKind: _SuggestionIconKind.search,
        iconColor: V2Colors.safe,
      ),
    );
  }
  return out.take(4).toList(growable: false);
}

List<String> _candidateIngredientTerms(
  String normalizedQuery,
  List<ProductsCoreData> products,
) {
  final out = <String>[];
  final seen = <String>{};

  void add(String? raw) {
    final value = raw?.trim();
    if (value == null || value.length < 2) return;
    if (!value.toLowerCase().contains(normalizedQuery)) return;
    final label = _formatSuggestionLabel(value);
    if (seen.add(label.toLowerCase())) out.add(label);
  }

  for (final product in products) {
    add(
      product.primaryCategory == null
          ? null
          : _formatCategoryLabel(product.primaryCategory!),
    );
    add(_compactProductQuery(product.productName, normalizedQuery));
    if (out.length >= 4) return out;
  }
  return out;
}

String _compactProductQuery(String name, String normalizedQuery) {
  final cleaned = name
      .replaceAll(RegExp(r'\([^)]*\)'), ' ')
      .replaceAll(RegExp(r'[^A-Za-z0-9 +&-]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (cleaned.isEmpty) return name.trim();

  final words = cleaned.split(' ');
  final matchIndex = words.indexWhere(
    (word) => word.toLowerCase().contains(normalizedQuery),
  );
  if (matchIndex < 0) return _formatSuggestionLabel(cleaned);
  final end = matchIndex + 3 > words.length ? words.length : matchIndex + 3;
  final start = matchIndex == 0 ? 0 : matchIndex - 1;
  return _formatSuggestionLabel(words.sublist(start, end).join(' '));
}

String _formatSuggestionLabel(String raw) {
  final cleaned = raw
      .replaceAll('_', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (cleaned.isEmpty) return raw;
  return cleaned
      .split(' ')
      .map((word) {
        if (word.length <= 2 && word == word.toUpperCase()) return word;
        final lower = word.toLowerCase();
        return '${lower[0].toUpperCase()}${lower.substring(1)}';
      })
      .join(' ');
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
        return (p.qualityScoreV4100 ?? 0) >= 80 &&
            !hasLimitedAssessmentConfidence(p.v4Confidence);
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

String? _packSizeLabel(ProductsCoreData product) {
  return packageSizeLabel(
    quantity: product.netContentsQuantity,
    unit: product.netContentsUnit,
    fallbackFormFactor: product.formFactor ?? '',
  );
}

// Score-chip color uses the canonical quality-tier palette from
// score_tier.dart so search and product detail never render a different
// color for the same score. The locked boundaries (90/80/70/60/50) live in
// tierForScore — this must never reintroduce its own bands.
Color _scoreTone(double score) => tierForScore(score.round()).color;

/// Verdict → chip tone. Public + @visibleForTesting so the SAFE-case
/// regression (SAFE used to fall through to the gray NOT_SCORED fallback)
/// stays locked in test/features/search/v2/search_chip_decision_test.dart.
@visibleForTesting
Color searchVerdictTone(String verdict) {
  switch (verdict.trim().toUpperCase()) {
    case 'SAFE':
    case 'RECOMMENDED':
    case 'GOOD':
      return V2Colors.safe;
    case 'CAUTION':
    case 'MODERATE':
    case 'REVIEW':
      return V2Colors.caution;
    case 'POOR':
    case 'AVOID':
      return V2Colors.avoid;
    case 'BLOCKED':
    case 'UNSAFE':
      return V2Colors.contraindicated;
    default:
      return V2Colors.fgMuted;
  }
}

/// What a search result renders in its score-chip slot.
enum SearchScoreChipDisplay {
  /// Scored + trustworthy coverage → tier-colored numeric chip.
  tierScore,

  /// Scored, but mapped_coverage is below the 0.3 trust floor → neutral
  /// "Limited data" chip (SAFETY RULE: low coverage never renders as a
  /// confident tier-colored result).
  limitedData,

  /// Score is available, but v4 formula confidence is low. Keep the number in
  /// a neutral chip and suppress the quality-tier color.
  limitedAssessment,

  /// No chip: score is null, or the verdict is BLOCKED/UNSAFE — the red
  /// verdict chip is the block indicator and must not compete with a
  /// positive-looking number.
  hidden,
}

/// Pure render decision for the search score chip. Precedence: unsafe
/// verdict > missing score > low coverage > tier score.
@visibleForTesting
SearchScoreChipDisplay searchScoreChipDisplayFor({
  required double? score,
  required String? verdict,
  required double? mappedCoverage,
  String? v4Confidence,
}) {
  if (isUnsafeVerdict(verdict)) return SearchScoreChipDisplay.hidden;
  if (score == null) return SearchScoreChipDisplay.hidden;
  if (isLowCoverage(mappedCoverage)) return SearchScoreChipDisplay.limitedData;
  if (hasLimitedAssessmentConfidence(v4Confidence)) {
    return SearchScoreChipDisplay.limitedAssessment;
  }
  return SearchScoreChipDisplay.tierScore;
}

/// Whether the verdict chip renders. Under low coverage the positive
/// (green SAFE-family) verdicts are suppressed — a green "SAFE" chip on a
/// product whose label mostly failed to map implies confidence the data
/// can't support. Warning verdicts (CAUTION/POOR/BLOCKED/UNSAFE/...)
/// always render: under-warning is the bigger clinical risk.
@visibleForTesting
bool searchShowsVerdictChip({
  required String? verdict,
  required double? mappedCoverage,
}) {
  final v = (verdict ?? '').trim();
  if (v.isEmpty) return false;
  if (!isLowCoverage(mappedCoverage)) return true;
  switch (v.toUpperCase()) {
    case 'SAFE':
    case 'GOOD':
    case 'RECOMMENDED':
      return false;
    default:
      return true;
  }
}
