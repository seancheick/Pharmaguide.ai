import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/constants/app_colors.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/features/stack/widgets/nutrient_accumulation_panel.dart';

/// My Stack screen — shows all products in the user's supplement stack
/// with Stack Safety Score and interaction alerts.
class StackScreen extends ConsumerWidget {
  const StackScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // TODO: Wire to real stack data via Riverpod provider
    // For now, show empty state
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My Stack'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'My Stack'),
              Tab(text: 'Wishlist'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _StackTab(),
            _WishlistTab(),
          ],
        ),
      ),
    );
  }
}

class _StackTab extends StatelessWidget {
  const _StackTab();

  @override
  Widget build(BuildContext context) {
    // The nutrient accumulation panel renders only when the user has
    // products in their stack (it auto-collapses to SizedBox.shrink
    // for empty stacks). The empty-state CTA below is the only thing
    // visible until the first product is added.
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const NutrientAccumulationPanel(),
          Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.layers_outlined,
                    size: 64, color: AppColors.textSecondary),
                const SizedBox(height: 16),
                const Text(
                  'Your stack is empty',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Scan a supplement barcode or search to add products to your stack',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => context.go('/scan'),
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Scan a Product'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.brandTeal,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WishlistTab extends StatelessWidget {
  const _WishlistTab();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bookmark_border,
                size: 64, color: AppColors.textSecondary),
            SizedBox(height: 16),
            Text(
              'No saved products',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 8),
            Text(
              'Save products from search results to compare later',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
