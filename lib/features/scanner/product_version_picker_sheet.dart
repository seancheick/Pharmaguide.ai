import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/widgets/pg_modal.dart';
import 'package:pharmaguide/core/widgets/product_image.dart';
import 'package:pharmaguide/data/database/core_database.dart';

Future<ProductsCoreData?> showProductVersionPickerSheet(
  BuildContext context, {
  required List<ProductsCoreData> candidates,
}) {
  assert(
    candidates.length > 1,
    'Bottle confirmation requires multiple matches.',
  );
  return PGModal.bottomSheet<ProductsCoreData>(
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
            'This barcode appears on more than one label. Compare the name, bottle size, and photo.',
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
                    onTap: () => Navigator.of(context).pop(product),
                  ),
                );
              },
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
  return details.join(' · ');
}
