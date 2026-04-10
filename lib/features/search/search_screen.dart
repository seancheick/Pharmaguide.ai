import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/constants/app_colors.dart';
import 'package:pharmaguide/core/widgets/verdict_badge.dart';
import 'package:pharmaguide/core/constants/score_colors.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/services/recent_searches_service.dart';

class SearchScreen extends ConsumerStatefulWidget {
  final String? initialCategory;
  const SearchScreen({super.key, this.initialCategory});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  String _query = '';
  String? _activeCategory;
  List<ProductsCoreData>? _results;
  bool _loading = false;
  bool _isGridView = false;
  List<String> _recentSearches = [];

  Timer? _debounce;
  int _searchVersion = 0;

  @override
  void initState() {
    super.initState();
    _activeCategory = widget.initialCategory;
    _focusNode.requestFocus();
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
    _focusNode.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    setState(() {
      _query = value;
      if (value.trim().isNotEmpty) {
        _activeCategory = null;
      }
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

      // Latest-query-wins: discard if a newer search was issued.
      if (version != _searchVersion) return;

      if (!mounted) return;
      setState(() {
        _results = results;
        _loading = false;
      });

      // Save successful search to recent
      if (results.isNotEmpty) {
        await _recentService.addSearch(query);
        await _loadRecentSearches();
      }
    } on Exception {
      if (version != _searchVersion) return;
      if (!mounted) return;
      setState(() {
        _results = [];
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
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          focusNode: _focusNode,
          decoration: const InputDecoration(
            hintText: 'Search supplements...',
            border: InputBorder.none,
          ),
          onChanged: _onQueryChanged,
        ),
        actions: [
          if (_query.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: _clearSearch,
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_query.isEmpty && _activeCategory != null) {
      if (_loading) return _buildLoadingState();
      if (_results == null || _results!.isEmpty) return _buildNoResultsState();
      return _buildResultsList();
    }
    if (_query.isEmpty) return _buildEmptyState();
    if (_loading) return _buildLoadingState();
    if (_results == null || _results!.isEmpty) return _buildNoResultsState();
    return _buildResultsList();
  }

  Widget _buildEmptyState() {
    if (_recentSearches.isNotEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Recent Searches',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              TextButton(
                onPressed: () async {
                  await _recentService.clearAll();
                  await _loadRecentSearches();
                },
                child: const Text('Clear'),
              ),
            ],
          ),
          ..._recentSearches.map(
            (term) => ListTile(
              leading: const Icon(Icons.history, color: AppColors.textSecondary),
              title: Text(term),
              trailing: IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () async {
                  await _recentService.removeSearch(term);
                  await _loadRecentSearches();
                },
              ),
              onTap: () {
                _controller.text = term;
                _onQueryChanged(term);
              },
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      );
    }

    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search, size: 64, color: AppColors.textSecondary),
          SizedBox(height: 16),
          Text('Search by product name or brand',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 16)),
          SizedBox(height: 8),
          Text('Or scan a barcode for instant results',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(child: CircularProgressIndicator());
  }

  Widget _buildNoResultsState() {
    final title = _activeCategory != null && _query.isEmpty
        ? 'No products found in ${_activeCategory!.replaceAll('_', ' ')}'
        : 'No results for "$_query"';

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.search_off,
              size: 48, color: AppColors.textSecondary),
          const SizedBox(height: 16),
          Text(title,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 16)),
          const SizedBox(height: 8),
          const Text('Try a different spelling or brand name',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildResultsList() {
    return Column(
      children: [
        // Results header with count and view toggle
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _resultsHeaderText(),
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(Icons.view_list,
                        color: !_isGridView
                            ? AppTheme.brandTeal
                            : AppColors.textSecondary,
                        size: 22),
                    onPressed: () => setState(() => _isGridView = false),
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    icon: Icon(Icons.grid_view,
                        color: _isGridView
                            ? AppTheme.brandTeal
                            : AppColors.textSecondary,
                        size: 22),
                    onPressed: () => setState(() => _isGridView = true),
                    visualDensity: VisualDensity.compact,
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
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: _results!.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, color: AppColors.border),
      itemBuilder: (context, index) {
        final product = _results![index];
        return _SearchResultTile(
          product: product,
          onTap: () => context.push('/product/${product.dsldId}'),
        );
      },
    );
  }

  Widget _buildGridResults() {
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.85,
      ),
      itemCount: _results!.length,
      itemBuilder: (context, index) {
        final product = _results![index];
        return _SearchGridCard(product: product);
      },
    );
  }

  String _resultsHeaderText() {
    if (_activeCategory != null && _query.isEmpty) {
      final label = _activeCategory!.replaceAll('_', ' ');
      return '${_results!.length} $label result${_results!.length == 1 ? '' : 's'}';
    }
    return '${_results!.length} result${_results!.length == 1 ? '' : 's'}';
  }
}

class _SearchResultTile extends StatelessWidget {
  final ProductsCoreData product;
  final VoidCallback onTap;

  const _SearchResultTile({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final score = product.score100Equivalent;
    final verdict = product.verdict;

    return ListTile(
      onTap: onTap,
      title: Text(
        product.productName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
      subtitle: Text(
        product.brandName ?? '',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (score != null)
            Text(
              score.round().toString(),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: _scoreColor(score),
              ),
            ),
          if (verdict != null) ...[
            const SizedBox(width: 8),
            VerdictBadge(verdict: verdict),
          ],
        ],
      ),
    );
  }

  Color _scoreColor(double score) => scoreColor(score);
}


class _SearchGridCard extends StatelessWidget {
  final ProductsCoreData product;

  const _SearchGridCard({required this.product});

  Color _scoreColor(double? score) => scoreColor(score);

  @override
  Widget build(BuildContext context) {
    final score = product.score100Equivalent;
    final color = _scoreColor(score);

    return GestureDetector(
      onTap: () => context.push('/product/${product.dsldId}'),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Align(
              alignment: Alignment.topRight,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withAlpha(20),
                  border: Border.all(color: color.withAlpha(80)),
                ),
                alignment: Alignment.center,
                child: Text(
                  score?.toStringAsFixed(0) ?? '--',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
            ),
            const Spacer(),
            Text(
              product.productName,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            if (product.brandName != null && product.brandName!.isNotEmpty)
              Text(
                product.brandName!,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
    );
  }
}
