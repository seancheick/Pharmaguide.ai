import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/core/widgets/pg_modal.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/providers/detail_blob_provider.dart';
import 'package:pharmaguide/features/product_detail/v2/product_detail_v2_connected.dart'
    show productDetailIngredientSourcesFromBlob;
import 'package:pharmaguide/features/product_detail/v2/sections/ingredients_section.dart';

Future<bool?> showProductVersionLabelSheet(
  BuildContext context, {
  required ProductsCoreData product,
}) => PGModal.bottomSheet<bool>(
  context: context,
  builder: (_) => _ProductVersionLabelSheet(product: product),
);

/// Reuses the product page's checksum-verified data and label renderer. Search
/// tags are analysis identifiers, not a substitute for the bottle's Facts.
class _ProductVersionLabelSheet extends ConsumerWidget {
  const _ProductVersionLabelSheet({required this.product});
  final ProductsCoreData product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(detailBlobProvider(product.dsldId));
    final sources = productDetailIngredientSourcesFromBlob(
      detail.asData?.value,
    );
    final hasLabel = hasIngredientDisclosureTarget(
      ingredients: const [],
      displayIngredients: sources.displayIngredients,
      blends: sources.blends,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Match the Facts panel',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(product.productName),
          const Text(
            'Compare ingredient names, forms and amounts with your bottle.',
          ),
          const SizedBox(height: 16),
          if (detail.isLoading)
            const LinearProgressIndicator()
          else if (!hasLabel)
            const Text(
              'Label details are unavailable. Don’t guess the version. '
              'Go back and try again when connected, or choose None of these match to report your label.',
            ),
          if (hasLabel)
            Flexible(
              child: SingleChildScrollView(
                child: buildIngredientsSection(
                  context: context,
                  ingredients: const [],
                  displayIngredients: sources.displayIngredients,
                  inactiveIngredients: sources.inactiveIngredients,
                  ulAnalysis: null,
                  blends: sources.blends,
                ),
              ),
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: hasLabel ? () => Navigator.of(context).pop(true) : null,
            child: const Text('This matches my label'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Back to other versions'),
          ),
        ],
      ),
    );
  }
}
