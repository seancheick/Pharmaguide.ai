import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/data/providers/detail_blob_provider.dart';
import 'package:pharmaguide/features/product_detail/v2/product_detail_v2_connected.dart'
    show productDetailIngredientSourcesFromBlob;
import 'package:pharmaguide/features/product_detail/v2/sections/nutrition_section.dart'
    show dailyValueLabelForCanonicalRow;
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/widgets/pg_modal.dart';
import 'package:pharmaguide/core/widgets/product_image.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/features/scanner/product_version_label_sheet.dart';

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
  bool forComparison = false,
}) {
  assert(
    candidates.length > 1,
    'Bottle confirmation requires multiple matches.',
  );
  return PGModal.bottomSheet<ProductVersionChoice>(
    context: context,
    builder: (_) => ProductVersionPickerSheet(
      candidates: candidates,
      forComparison: forComparison,
    ),
  );
}

class ProductVersionPickerSheet extends ConsumerWidget {
  const ProductVersionPickerSheet({
    super.key,
    required this.candidates,
    this.forComparison = false,
  });

  final List<ProductsCoreData> candidates;
  final bool forComparison;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final detailsById = {
      for (final product in candidates)
        product.dsldId: ref.watch(detailBlobProvider(product.dsldId)),
    };
    // One scroll for the header and the candidates: at large text sizes the
    // header alone can be taller than a small phone's sheet.
    return SingleChildScrollView(
      child: Padding(
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
              forComparison
                  ? 'Which catalog label should we compare?'
                  : 'Which bottle matches yours?',
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: V2Spacing.space8),
            Text(
              forComparison
                  ? 'Choose the record you want to report. This does not confirm it matches your bottle.'
                  : 'This barcode is on more than one label. Compare the printed amounts and % Daily Values below, then open the Facts panel to confirm your bottle.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: V2Spacing.space16),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
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
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (details.isNotEmpty) Text(details),
                        const SizedBox(height: 8),
                        ..._labelPreview(
                          detailsById[product.dsldId]!,
                          peers: [
                            for (final other in candidates)
                              if (other.dsldId != product.dsldId)
                                detailsById[other.dsldId]!.asData?.value,
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text('Open Facts panel to compare'),
                      ],
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      if (forComparison) {
                        Navigator.of(
                          context,
                        ).pop(ProductVersionSelected(product));
                        return;
                      }
                      final confirmed = await showProductVersionLabelSheet(
                        context,
                        product: product,
                      );
                      if (confirmed == true && context.mounted) {
                        Navigator.of(
                          context,
                        ).pop(ProductVersionSelected(product));
                      }
                    },
                  ),
                );
              },
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
                subtitle: const Text('My bottle has a different label.'),
                onTap: () =>
                    Navigator.of(context).pop(const ProductVersionUnmatched()),
              ),
            ),
          ],
        ),
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

  // Package details help locate a candidate, but cannot confirm a formula.
  // Its source-label ingredient ledger is shown before selection is accepted.
  final servings = product.servingsPerContainer;
  if (servings != null && servings > 0) details.add('$servings servings');

  return details.join(' · ');
}

// Preview only recorded label facts; the full canonical renderer remains the
// confirmation authority. Identical doses do not establish identical labels.
List<Widget> _labelPreview(
  AsyncValue<Map<String, dynamic>?> detail, {
  required List<Map<String, dynamic>?> peers,
}) {
  final rows = productDetailIngredientSourcesFromBlob(
    detail.asData?.value,
  ).displayIngredients;
  final active =
      rows
          ?.where(
            (row) =>
                row['source_section'] != 'inactiveIngredients' &&
                row['display_disposition'] != 'other_ingredient',
          )
          .toList() ??
      [];
  if (active.isEmpty) {
    return [
      Text(
        detail.isLoading
            ? 'Loading label facts…'
            : 'Label facts unavailable; open to retry',
      ),
    ];
  }
  final otherNames =
      rows
          ?.where((row) => row['display_disposition'] == 'other_ingredient')
          .map((row) => row['label_display_name'])
          .whereType<String>()
          .where((name) => name.trim().isNotEmpty)
          .toList() ??
      <String>[];
  final peerRows = peers
      .map(
        (blob) =>
            productDetailIngredientSourcesFromBlob(blob).displayIngredients,
      )
      .toList();
  final canCompare =
      peerRows.isNotEmpty &&
      peerRows.every((rows) => rows != null && rows.isNotEmpty);
  final peerOtherNames = peerRows
      .expand((rows) => rows ?? <Map<String, dynamic>>[])
      .where((row) => row['display_disposition'] == 'other_ingredient')
      .map((row) => row['label_display_name'])
      .whereType<String>()
      .toSet();
  final differingOtherNames = canCompare
      ? otherNames.where((name) => !peerOtherNames.contains(name)).toList()
      : <String>[];
  return [
    for (final row in active.take(3))
      Text(
        [
              row['label_display_name'],
              row['label_display_form'],
              row['exact_dose_text'],
              dailyValueLabelForCanonicalRow(row),
            ]
            .whereType<String>()
            .where((value) => value.trim().isNotEmpty)
            .join(' · '),
      ),
    if (active.length > 3) const Text('More ingredients in the Facts panel'),
    if (differingOtherNames.isNotEmpty)
      Text('Other ingredients to compare: ${differingOtherNames.join(', ')}'),
  ];
}
