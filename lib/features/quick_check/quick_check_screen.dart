import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/core/models/interaction_result.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_card.dart';
import 'package:pharmaguide/core/widgets/pg_severity_banner.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/quick_check/quick_check_logic.dart';

/// "Safe to Take Together?" quick pair interaction check.
///
/// Standalone screen — no stack required. User searches for two products,
/// taps "Check", and sees instant pair interaction results from the
/// bundled [InteractionDatabase].
class QuickCheckScreen extends ConsumerStatefulWidget {
  const QuickCheckScreen({super.key});

  @override
  ConsumerState<QuickCheckScreen> createState() => _QuickCheckScreenState();
}

class _QuickCheckScreenState extends ConsumerState<QuickCheckScreen> {
  final _controller1 = TextEditingController();
  final _controller2 = TextEditingController();

  List<ProductsCoreData> _suggestions1 = const [];
  List<ProductsCoreData> _suggestions2 = const [];
  ProductsCoreData? _product1;
  ProductsCoreData? _product2;

  List<InteractionResult>? _results;
  bool _checking = false;
  bool _checkError = false;
  bool _insufficientData = false;
  Timer? _debounce1;
  Timer? _debounce2;

  @override
  void dispose() {
    _controller1.dispose();
    _controller2.dispose();
    _debounce1?.cancel();
    _debounce2?.cancel();
    super.dispose();
  }

  void _onQuery1Changed(String query) {
    _debounce1?.cancel();
    if (query.trim().length < 2) {
      setState(() => _suggestions1 = const []);
      return;
    }
    _debounce1 = Timer(const Duration(milliseconds: 300), () async {
      final db = ref.read(coreDatabaseProvider);
      final results = await db.searchProducts(query.trim(), limit: 8);
      if (mounted) setState(() => _suggestions1 = results);
    });
  }

  void _onQuery2Changed(String query) {
    _debounce2?.cancel();
    if (query.trim().length < 2) {
      setState(() => _suggestions2 = const []);
      return;
    }
    _debounce2 = Timer(const Duration(milliseconds: 300), () async {
      final db = ref.read(coreDatabaseProvider);
      final results = await db.searchProducts(query.trim(), limit: 8);
      if (mounted) setState(() => _suggestions2 = results);
    });
  }

  void _selectProduct1(ProductsCoreData product) {
    setState(() {
      _product1 = product;
      _suggestions1 = const [];
      _results = null;
    });
    _controller1.text = product.productName;
  }

  void _selectProduct2(ProductsCoreData product) {
    setState(() {
      _product2 = product;
      _suggestions2 = const [];
      _results = null;
    });
    _controller2.text = product.productName;
  }

  Future<void> _checkInteractions() async {
    if (_product1 == null || _product2 == null) return;
    setState(() {
      _checking = true;
      _results = null;
      _checkError = false;
      _insufficientData = false;
    });

    try {
      final interactionDb = ref.read(interactionDatabaseProvider);

      // Check if both products have ingredient data to check against.
      final idsA = extractCanonicalIds(_product1!.ingredientFingerprint);
      final idsB = extractCanonicalIds(_product2!.ingredientFingerprint);
      if (idsA.isEmpty || idsB.isEmpty) {
        if (mounted) {
          setState(() {
            _insufficientData = true;
            _checking = false;
          });
        }
        return;
      }

      final results = await runPairCheck(
        _product1!,
        _product2!,
        interactionDb,
      );
      if (mounted) {
        setState(() {
          _results = results;
          _checking = false;
        });
      }
    } on UnimplementedError {
      // Provider stub not overridden (test environment).
      if (mounted) setState(() { _checkError = true; _checking = false; });
    } on Exception {
      if (mounted) setState(() { _checkError = true; _checking = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final canCheck = _product1 != null && _product2 != null && !_checking;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Safe to Take Together?'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppTheme.space20),
          children: [
            // Intro text
            Text(
              'Check if two supplements or medications interact '
              'before you take them together.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppTheme.space20),

            // Product 1 search
            _ProductSearchField(
              controller: _controller1,
              label: 'First product',
              selected: _product1,
              suggestions: _suggestions1,
              onChanged: _onQuery1Changed,
              onSelect: _selectProduct1,
              onClear: () => setState(() {
                _product1 = null;
                _controller1.clear();
                _suggestions1 = const [];
                _results = null;
              }),
            ),
            const SizedBox(height: AppTheme.space16),

            // Product 2 search
            _ProductSearchField(
              controller: _controller2,
              label: 'Second product',
              selected: _product2,
              suggestions: _suggestions2,
              onChanged: _onQuery2Changed,
              onSelect: _selectProduct2,
              onClear: () => setState(() {
                _product2 = null;
                _controller2.clear();
                _suggestions2 = const [];
                _results = null;
              }),
            ),
            const SizedBox(height: AppTheme.space24),

            // Check button
            FilledButton.icon(
              onPressed: canCheck ? _checkInteractions : null,
              icon: _checking
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.health_and_safety_outlined),
              label: Text(_checking ? 'Checking...' : 'Check Interactions'),
            ),
            const SizedBox(height: AppTheme.space24),

            // Results — distinguish clean check vs error vs insufficient data
            if (_checkError)
              PGCard(
                padding: const EdgeInsets.all(AppTheme.space20),
                child: Column(
                  children: [
                    const Icon(Icons.error_outline, color: AppTheme.severityAvoid, size: 48),
                    const SizedBox(height: AppTheme.space12),
                    Text('Interaction check unavailable',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: AppTheme.space8),
                    Text('The interaction database could not be loaded. Please try again later.',
                        style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                        textAlign: TextAlign.center),
                  ],
                ),
              )
            else if (_insufficientData)
              PGCard(
                padding: const EdgeInsets.all(AppTheme.space20),
                child: Column(
                  children: [
                    const Icon(Icons.info_outline, color: AppTheme.severityCaution, size: 48),
                    const SizedBox(height: AppTheme.space12),
                    Text('Insufficient ingredient data',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: AppTheme.space8),
                    Text('One or both products lack detailed ingredient data. '
                        'We cannot reliably check for interactions.',
                        style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                        textAlign: TextAlign.center),
                  ],
                ),
              )
            else if (_results != null)
              _buildResults(theme, scheme),
          ],
        ),
      ),
    );
  }

  Widget _buildResults(ThemeData theme, ColorScheme scheme) {
    if (_results!.isEmpty) {
      return PGCard(
        padding: const EdgeInsets.all(AppTheme.space20),
        child: Column(
          children: [
            const Icon(
              Icons.check_circle_outline,
              color: AppTheme.severitySafe,
              size: 48,
            ),
            const SizedBox(height: AppTheme.space12),
            Text(
              'No known interactions',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppTheme.space8),
            Text(
              'Based on our database, these products appear safe to take '
              'together. Always consult your healthcare provider.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${_results!.length} interaction${_results!.length == 1 ? '' : 's'} found',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppTheme.space12),
        ..._results!.map((result) => Padding(
              padding: const EdgeInsets.only(bottom: AppTheme.space12),
              child: PGSeverityBanner(
                tone: toneForSeverity(result.severity),
                title: result.severity.name.toUpperCase(),
                body: result.mechanism,
              ),
            )),
        const SizedBox(height: AppTheme.space8),
        Text(
          'This is educational information, not medical advice. '
          'Always consult your healthcare provider.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
            fontStyle: FontStyle.italic,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

}

// ---------------------------------------------------------------------------
// Product search field with inline suggestions
// ---------------------------------------------------------------------------

class _ProductSearchField extends StatelessWidget {
  const _ProductSearchField({
    required this.controller,
    required this.label,
    required this.selected,
    required this.suggestions,
    required this.onChanged,
    required this.onSelect,
    required this.onClear,
  });

  final TextEditingController controller;
  final String label;
  final ProductsCoreData? selected;
  final List<ProductsCoreData> suggestions;
  final ValueChanged<String> onChanged;
  final ValueChanged<ProductsCoreData> onSelect;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: controller,
          onChanged: (v) {
            if (selected != null) onClear();
            onChanged(v);
          },
          decoration: InputDecoration(
            labelText: label,
            hintText: 'Search by name...',
            prefixIcon: Icon(
              selected != null
                  ? Icons.check_circle
                  : Icons.search_rounded,
              color: selected != null ? AppTheme.severitySafe : null,
            ),
            suffixIcon: selected != null
                ? IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: onClear,
                  )
                : null,
            border: const OutlineInputBorder(),
          ),
        ),
        if (suggestions.isNotEmpty && selected == null)
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            decoration: BoxDecoration(
              color: scheme.surface,
              border: Border.all(color: scheme.outlineVariant),
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(AppTheme.radiusSmall),
              ),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: suggestions.length,
              separatorBuilder: (_, __) => Divider(
                height: 0.5,
                color: scheme.outlineVariant,
              ),
              itemBuilder: (context, index) {
                final product = suggestions[index];
                return ListTile(
                  key: ValueKey(product.dsldId),
                  dense: true,
                  title: Text(
                    product.productName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                  subtitle: product.brandName != null
                      ? Text(
                          product.brandName!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        )
                      : null,
                  trailing: product.score100Equivalent != null
                      ? Text(
                          '${product.score100Equivalent!.round()}',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        )
                      : null,
                  onTap: () => onSelect(product),
                );
              },
            ),
          ),
      ],
    );
  }
}
