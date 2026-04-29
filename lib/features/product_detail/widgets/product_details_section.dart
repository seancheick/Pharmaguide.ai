// Product Details section (Section 10) — collapsed-by-default
// reference panel for low-priority identity facts.
//
// Spec: INITIATIVE_PRODUCT_TRUST_AND_IA.md, Sprint 1, T1.11.
//
// Surface area: serving size, servings per container, manufacturer.
// These are reference facts, not safety signals — most users don't
// need them. Default state is a single-line header with a chevron;
// tap to reveal the field rows.
//
// Acceptance: always rendered (when at least one field has data),
// always collapsed initially.

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_card.dart';
import 'package:pharmaguide/core/widgets/pg_pressable.dart';

/// One row in the expanded body — a label/value pair. Public so unit
/// tests can construct + assert against the same shape the section
/// uses internally.
class ProductDetailField {
  final String label;
  final String value;
  const ProductDetailField({required this.label, required this.value});
}

/// Pure helper — pick the available product-detail fields from raw
/// nullable inputs and return them in fixed display order. Empty /
/// blank values are dropped. Caller renders whatever comes back.
///
/// Display order is intentional and matches the spec's listing:
///   1. Serving size  (most actionable — dosing guidance)
///   2. Servings per container  (volume / refill horizon)
///   3. Manufacturer  (provenance, lowest action priority)
List<ProductDetailField> buildProductDetailFields({
  required String? servingSize,
  required int? servingsPerContainer,
  required String? manufacturer,
}) {
  final out = <ProductDetailField>[];
  final ss = servingSize?.trim();
  if (ss != null && ss.isNotEmpty) {
    out.add(ProductDetailField(label: 'Serving size', value: ss));
  }
  if (servingsPerContainer != null && servingsPerContainer > 0) {
    out.add(
      ProductDetailField(
        label: 'Servings per container',
        value: '$servingsPerContainer',
      ),
    );
  }
  final mf = manufacturer?.trim();
  if (mf != null && mf.isNotEmpty) {
    out.add(ProductDetailField(label: 'Manufacturer', value: mf));
  }
  return out;
}

/// Section 10 widget. Hides entirely when no fields have data — an
/// empty collapsed expander would be noise. Otherwise renders a
/// single-line tappable header that expands to reveal the field rows.
class ProductDetailsSection extends StatefulWidget {
  /// Human-readable serving size, e.g. "2 capsules daily". Pipeline
  /// emits this as `products_core.dosing_summary`.
  final String? servingSize;

  /// Whole-number servings count from `products_core.servings_per_container`.
  final int? servingsPerContainer;

  /// Manufacturer name from `detail_blob.manufacturer_info.name`.
  /// Distinct from brand name — the company that produces the
  /// product, not the marketing label.
  final String? manufacturer;

  const ProductDetailsSection({
    super.key,
    required this.servingSize,
    required this.servingsPerContainer,
    required this.manufacturer,
  });

  @override
  State<ProductDetailsSection> createState() =>
      _ProductDetailsSectionState();
}

class _ProductDetailsSectionState extends State<ProductDetailsSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final fields = buildProductDetailFields(
      servingSize: widget.servingSize,
      servingsPerContainer: widget.servingsPerContainer,
      manufacturer: widget.manufacturer,
    );
    if (fields.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return PGCard(
      // Plain (not elevated) — this is reference content, not signal.
      // Sits visually quiet alongside the louder safety / quality
      // sections above.
      variant: PGCardVariant.plain,
      padding: const EdgeInsets.all(AppTheme.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PGPressable(
            onTap: () => setState(() => _expanded = !_expanded),
            pressedScale: 0.98,
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  'Product details',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.1,
                  ),
                ),
                const Spacer(),
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _expanded
                ? Padding(
                    padding: const EdgeInsets.only(top: AppTheme.space8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (int i = 0; i < fields.length; i++) ...[
                          _DetailRow(field: fields[i]),
                          if (i != fields.length - 1)
                            const SizedBox(height: 6),
                        ],
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final ProductDetailField field;
  const _DetailRow({required this.field});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 140,
          child: Text(
            field.label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            field.value,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurface,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}
