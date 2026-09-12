import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/widgets/pg_modal.dart';
import 'package:pharmaguide/core/widgets/product_image.dart';
import 'package:pharmaguide/data/database/core_database.dart';

/// What the person said their bottle is.
///
/// "None of these" is a real answer, not a dismissal: a barcode can be reused
/// for a formula the catalog has never seen, and treating that silence as
/// "cancelled" loses both the scan and the chance to add the product.
sealed class ProductVersionChoice {
  const ProductVersionChoice();
}

/// This bottle is that catalog record.
class ProductVersionSelected extends ProductVersionChoice {
  const ProductVersionSelected(this.product);

  final ProductsCoreData product;
}

/// None of the candidates is the bottle in the person's hand.
class ProductVersionUnmatched extends ProductVersionChoice {
  const ProductVersionUnmatched();
}

Future<ProductVersionChoice?> showProductVersionPickerSheet(
  BuildContext context, {
  required List<ProductsCoreData> candidates,
}) {
  assert(
    candidates.length > 1,
    'Bottle confirmation requires multiple matches.',
  );
  return PGModal.bottomSheet<ProductVersionChoice>(
    context: context,
    builder: (_) => ProductVersionPickerSheet(candidates: candidates),
  );
}

class ProductVersionPickerSheet extends StatelessWidget {
  const ProductVersionPickerSheet({super.key, required this.candidates});

  final List<ProductsCoreData> candidates;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        V2Spacing.space24,
        0,
        V2Spacing.space24,
        V2Spacing.space24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Which bottle matches yours?',
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: V2Spacing.space8),
          Text(
            'This barcode is on more than one label. Check the serving count \n'
            'and what is in it against your bottle, not just the picture.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: V2Spacing.space16),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: candidates.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final product = candidates[index];
                final details = _bottleDetails(product);
                return Semantics(
                  button: true,
                  label: [
                    product.productName,
                    details,
                  ].where((v) => v.isNotEmpty).join(', '),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: V2Spacing.space8,
                    ),
                    leading: ProductImage(
                      dsldId: product.dsldId,
                      upc: product.upcSku,
                      dsldImagePath:
                          product.imageThumbnailUrl ?? product.imageUrl,
                      productName: product.productName,
                      brandName: product.brandName ?? '',
                      formFactor: product.formFactor,
                      size: 56,
                      compact: true,
                    ),
                    title: Text(product.productName),
                    subtitle: details.isEmpty ? null : Text(details),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context)
                        .pop(ProductVersionSelected(product)),
                  ),
                );
              },
            ),
          ),
          const Divider(height: 1),
          Semantics(
            button: true,
            label: 'None of these match',
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                vertical: V2Spacing.space8,
              ),
              leading: const Icon(Icons.help_outline),
              title: const Text('None of these match'),
              subtitle: const Text(
                'My bottle has a different label.',
              ),
              onTap: () => Navigator.of(context)
                  .pop(const ProductVersionUnmatched()),
            ),
          ),
        ],
      ),
    );
  }
}

String _bottleDetails(ProductsCoreData product) {
  final details = <String>[];
  final brand = product.brandName?.trim();
  if (brand != null && brand.isNotEmpty) details.add(brand);

  final quantity = product.netContentsQuantity;
  final unit = product.netContentsUnit?.trim();
  if (quantity != null && unit != null && unit.isNotEmpty) {
    final value = quantity == quantity.roundToDouble()
        ? quantity.toInt().toString()
        : quantity.toString();
    details.add('$value $unit');
  }

  final form = product.formFactor?.trim();
  if (form != null && form.isNotEmpty) details.add(form);

  // What is printed on the Facts panel, which is what actually separates two
  // editions of the same product. Two bottles can look identical and share a
  // barcode while their panels do not.
  final servings = product.servingsPerContainer;
  if (servings != null && servings > 0) details.add('$servings servings');

  final tags = product.keyIngredientTags?.trim();
  if (tags != null && tags.isNotEmpty) {
    final named = tags
        .split(RegExp(r'[,|]'))
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .take(3)
        .join(', ');
    if (named.isNotEmpty) details.add(named);
  }
  return details.join(' · ');
}
