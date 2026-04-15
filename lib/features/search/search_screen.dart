import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_card.dart';
import 'package:pharmaguide/core/widgets/pg_empty_state.dart';
import 'package:pharmaguide/core/widgets/pg_filter_chip.dart';
import 'package:pharmaguide/core/widgets/pg_frosted_nav_bar.dart';
import 'package:pharmaguide/core/widgets/pg_search_field.dart';
import 'package:pharmaguide/core/widgets/pg_shimmer_box.dart';
import 'package:pharmaguide/core/widgets/product_list_item.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/services/recent_searches_service.dart';

/// Search screen — fully migrated to the PG design system.
///
/// Composition: PGSearchField in the app bar, recent-search rows as
/// PGCard rows, category results list via ProductListItem (already PG),
/// grid mode via ProductGridItem (already PG), and PGEmptyState for the
/// no-results and first-open states.
class SearchScreen extends ConsumerStatefulWidget {
  final String? initialCategory;
  const SearchScreen({super.key, this.initialCategory});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();

  String _query = '';
  String? _activeCategory;
  List<ProductsCoreData>? _results;
  bool _loading = false;
  bool _isGridView = false;
  List<String> _recentSearches = [];
  _SearchFilter _activeFilter = _SearchFilter.all;

  Timer? _debounce;
  int _searchVersion = 0;

  @override
  void initState() {
    super.initState();
    _activeCategory = widget.initialCategory;
    _loadRecentSearches();
    if (_activeCategory != null && _activeCategory!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadCategoryResults(_activeCategory!);
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
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    setState(() {
      _query = value;
      if (value.trim().isNotEmpty) _activeCategory = null;
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
      if (version != _searchVersion) return; // latest-query-wins
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
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mq = MediaQuery.paddingOf(context);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Top area with back button + search field
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.space8,
                AppTheme.space8,
                AppTheme.space16,
                AppTheme.space8,
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.arrow_back_rounded,
                      color: scheme.onSurface,
                    ),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  Expanded(
                    child: PGSearchField(
                      controller: _controller,
                      autofocus: true,
                      onChanged: _onQueryChanged,
                      trailing: _query.isNotEmpty
                          ? IconButton(
                              icon: Icon(
                                Icons.close_rounded,
                                size: 18,
                                color: scheme.onSurfaceVariant,
                              ),
                              onPressed: _clearSearch,
                              visualDensity: VisualDensity.compact,
                            )
                          : null,
                    ),
                  ),
                ],
              ),
            ),

            // Quality filter chips — only visible when results exist
            if (_results != null && _results!.isNotEmpty)
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.space16,
                  ),
                  children: _SearchFilter.values.map((filter) {
                    final selected = _activeFilter == filter;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(filter.label),
                        selected: selected,
                        onSelected: (_) => setState(() {
                          _activeFilter = selected
                              ? _SearchFilter.all
                              : filter;
                        }),
                        visualDensity: VisualDensity.compact,
                        showCheckmark: false,
                      ),
                    );
                  }).toList(),
                ),
              ),

            // Body content
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: mq.bottom + kPGNavBarHeight,
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
      if (_loading) return const _SearchLoadingList();
      if (_results == null || _results!.isEmpty) return _buildNoResultsState();
      return _buildResultsList();
    }
    if (_query.isEmpty) return _buildEmptyState();
    if (_loading) return const _SearchLoadingList();
    if (_results == null || _results!.isEmpty) return _buildNoResultsState();
    return _buildResultsList();
  }

  Widget _buildEmptyState() {
    if (_recentSearches.isNotEmpty) {
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      return ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppTheme.space20,
          AppTheme.space8,
          AppTheme.space20,
          AppTheme.space16,
        ),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recent searches',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.15,
                ),
              ),
              TextButton(
                onPressed: () async {
                  await _recentService.clearAll();
                  await _loadRecentSearches();
                },
                child: const Text('Clear'),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.space8),
          ..._recentSearches.map(
            (term) => Padding(
              padding: const EdgeInsets.only(bottom: AppTheme.space8),
              child: PGCard(
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.space12,
                  AppTheme.space12,
                  AppTheme.space8,
                  AppTheme.space12,
                ),
                onTap: () {
                  _controller.text = term;
                  _onQueryChanged(term);
                },
                child: Row(
                  children: [
                    Icon(
                      Icons.history_rounded,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: AppTheme.space12),
                    Expanded(
                      child: Text(
                        term,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.close_rounded,
                        size: 16,
                        color: scheme.onSurfaceVariant,
                      ),
                      visualDensity: VisualDensity.compact,
                      onPressed: () async {
                        await _recentService.removeSearch(term);
                        await _loadRecentSearches();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    return const Padding(
      padding: EdgeInsets.all(AppTheme.space20),
      child: PGEmptyState(
        icon: Icons.search_rounded,
        title: 'Search supplements',
        description:
            'Type a product name or brand to find instantly — or scan a '
            'barcode from the scan tab for the fastest lookup.',
        variant: PGEmptyStateVariant.info,
      ),
    );
  }

  Widget _buildNoResultsState() {
    final title = _activeCategory != null && _query.isEmpty
        ? 'No products in ${_activeCategory!.replaceAll('_', ' ')}'
        : 'No results for "$_query"';

    return Padding(
      padding: const EdgeInsets.all(AppTheme.space20),
      child: PGEmptyState(
        icon: Icons.search_off_rounded,
        title: title,
        description: 'Try a different spelling or brand name.',
      ),
    );
  }

  // (const-construct helper removed; empty state now const-built)

  Widget _buildResultsList() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      children: [
        // Header: count + view toggle
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTheme.space20,
            AppTheme.space8,
            AppTheme.space12,
            AppTheme.space8,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _resultsHeaderText(),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PGFilterChip(
                    label: 'List',
                    icon: Icons.view_list_rounded,
                    selected: !_isGridView,
                    onTap: () => setState(() => _isGridView = false),
                  ),
                  const SizedBox(width: 6),
                  PGFilterChip(
                    label: 'Grid',
                    icon: Icons.grid_view_rounded,
                    selected: _isGridView,
                    onTap: () => setState(() => _isGridView = true),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Results content
        Expanded(
          child: _isGridView ? _buildGridResults() : _buildListResults(),
        ),
      ],
    );
  }

  Widget _buildListResults() {
    final scheme = Theme.of(context).colorScheme;
    final items = _filteredResults;
    return ListView.separated(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(top: AppTheme.space4),
      itemCount: items.length,
      separatorBuilder: (_, __) => Divider(
        height: 0.5,
        thickness: 0.5,
        indent: 84,
        endIndent: AppTheme.space16,
        color: scheme.outlineVariant,
      ),
      itemBuilder: (context, index) => ProductListItem(
        product: items[index],
      ),
    );
  }

  Widget _buildGridResults() {
    final items = _filteredResults;
    return GridView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.space20,
        vertical: AppTheme.space8,
      ),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: AppTheme.space12,
        mainAxisSpacing: AppTheme.space12,
        childAspectRatio: 0.85,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) => ProductGridItem(
        product: items[index],
      ),
    );
  }

  List<ProductsCoreData> get _filteredResults {
    final results = _results;
    if (results == null) return [];
    if (_activeFilter == _SearchFilter.all) return results;
    return results.where(_activeFilter.matches).toList();
  }

  String _resultsHeaderText() {
    final filtered = _filteredResults;
    final total = _results!.length;
    final count = filtered.length;
    if (_activeFilter != _SearchFilter.all) {
      return '$count of $total result${total == 1 ? '' : 's'}';
    }
    if (_activeCategory != null && _query.isEmpty) {
      final label = _activeCategory!.replaceAll('_', ' ');
      return '$count $label result${count == 1 ? '' : 's'}';
    }
    return '$count result${count == 1 ? '' : 's'}';
  }
}

// ---------------------------------------------------------------------------
// Loading state — skeleton list
// ---------------------------------------------------------------------------

class _SearchLoadingList extends StatelessWidget {
  const _SearchLoadingList();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      padding: const EdgeInsets.only(top: AppTheme.space8),
      children: const [
        PGShimmerListRow(),
        PGShimmerListRow(),
        PGShimmerListRow(),
        PGShimmerListRow(),
        PGShimmerListRow(),
        PGShimmerListRow(),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Search quality filter
// ---------------------------------------------------------------------------

enum _SearchFilter {
  all('All'),
  highQuality('High Quality (80+)'),
  needsCaution('Needs Caution'),
  thirdPartyTested('Third-Party Tested'),
  organic('Organic');

  const _SearchFilter(this.label);
  final String label;

  bool matches(ProductsCoreData p) {
    switch (this) {
      case _SearchFilter.all:
        return true;
      case _SearchFilter.highQuality:
        return (p.score100Equivalent ?? 0) >= 80;
      case _SearchFilter.needsCaution:
        final v = (p.verdict ?? '').toLowerCase();
        return v == 'caution' || v == 'avoid' || v == 'contraindicated';
      case _SearchFilter.thirdPartyTested:
        return p.hasThirdPartyTesting == 1;
      case _SearchFilter.organic:
        return p.isOrganic == 1;
    }
  }
}
