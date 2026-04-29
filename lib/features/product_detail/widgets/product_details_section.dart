// Product Details section (Section 10) — collapsed-by-default
// reference panel for low-priority identity facts.
//
// Spec: INITIATIVE_PRODUCT_TRUST_AND_IA.md, Sprint 1, T1.11.
//
// Spec calls for serving size, servings, manufacturer. The section
// also surfaces three additional fields that the pipeline already
// ships and that round out the reference panel without scope creep:
// net contents (e.g. "60 capsules"), form factor, and country of
// origin. All optional — the section hides any row whose data is
// missing.
//
// Default state is a single-line header with a chevron; tap to
// reveal the field rows. Acceptance: always rendered (when at least
// one field has data), always collapsed initially.

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_card.dart';
import 'package:pharmaguide/core/widgets/pg_pressable.dart';

/// Below this width the label/value rows stack vertically instead of
/// rendering side-by-side. Matches the breakpoint used by T1.6
/// (TradeoffsSection) — iPhone SE (320pt) hits this; small standard
/// devices (375pt+) keep the two-column layout.
const double _narrowBreakpoint = 380.0;

/// Fixed width for the label column on standard-width screens. Picked
/// to fit "Servings per container" + "Net contents" without wrap.
const double _labelColumnWidth = 140.0;

/// One row in the expanded body — a label/value pair. Public so unit
/// tests can construct + assert against the same shape the section
/// uses internally.
class ProductDetailField {
  final String label;
  final String value;
  const ProductDetailField({required this.label, required this.value});
}

/// Format a net-contents tuple as "60 capsules" / "240 ml" / "1.5 kg".
/// Whole-number quantities drop the decimal; fractional ones keep it.
/// Returns `null` when either piece is missing — caller drops the row.
String? formatNetContents(double? quantity, String? unit) {
  if (quantity == null) return null;
  final trimmedUnit = unit?.trim();
  if (trimmedUnit == null || trimmedUnit.isEmpty) return null;
  final qtyText = quantity == quantity.truncateToDouble()
      ? quantity.toInt().toString()
      : quantity.toString();
  return '$qtyText $trimmedUnit';
}

/// snake_case / lowercase token → "Snake Case". Keeps single-word
/// inputs cheap (`'capsule'` → `'Capsule'`).
String _humanize(String raw) {
  if (raw.isEmpty) return raw;
  return raw
      .replaceAll('_', ' ')
      .split(' ')
      .where((w) => w.isNotEmpty)
      .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}

/// Pure helper — pick the available product-detail fields from raw
/// nullable inputs and return them in fixed display order. Empty /
/// blank values are dropped. Caller renders whatever comes back.
///
/// Display order (most actionable → least):
///   1. Serving size            (dosing guidance)
///   2. Servings per container  (volume / refill horizon)
///   3. Net contents            (e.g. "60 capsules" — concrete count)
///   4. Form factor             (capsule / tablet / powder / ...)
///   5. Manufacturer            (provenance — company)
///   6. Country                 (provenance — geography)
List<ProductDetailField> buildProductDetailFields({
  required String? servingSize,
  required int? servingsPerContainer,
  required String? manufacturer,
  double? netContentsQuantity,
  String? netContentsUnit,
  String? formFactor,
  String? country,
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

  final netContents = formatNetContents(netContentsQuantity, netContentsUnit);
  if (netContents != null) {
    out.add(ProductDetailField(label: 'Net contents', value: netContents));
  }

  final form = formFactor?.trim();
  if (form != null && form.isNotEmpty) {
    out.add(
      ProductDetailField(label: 'Form', value: _humanize(form.toLowerCase())),
    );
  }

  final mf = manufacturer?.trim();
  if (mf != null && mf.isNotEmpty) {
    out.add(ProductDetailField(label: 'Manufacturer', value: mf));
  }

  final ct = country?.trim();
  if (ct != null && ct.isNotEmpty) {
    out.add(ProductDetailField(label: 'Country', value: ct));
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

  /// Net-contents quantity from `products_core.net_contents_quantity`.
  /// Combined with [netContentsUnit] to produce e.g. "60 capsules".
  final double? netContentsQuantity;

  /// Net-contents unit from `products_core.net_contents_unit`.
  final String? netContentsUnit;

  /// Form factor — `capsule`, `tablet`, `softgel`, `gummy`, `powder`,
  /// `liquid`, etc. From `products_core.form_factor`.
  final String? formFactor;

  /// Country of origin from `detail_blob.manufacturer_info.country`.
  final String? country;

  const ProductDetailsSection({
    super.key,
    required this.servingSize,
    required this.servingsPerContainer,
    required this.manufacturer,
    this.netContentsQuantity,
    this.netContentsUnit,
    this.formFactor,
    this.country,
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
      netContentsQuantity: widget.netContentsQuantity,
      netContentsUnit: widget.netContentsUnit,
      formFactor: widget.formFactor,
      country: widget.country,
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
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final stack =
                            constraints.maxWidth < _narrowBreakpoint;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (int i = 0; i < fields.length; i++) ...[
                              _DetailRow(field: fields[i], stack: stack),
                              if (i != fields.length - 1)
                                SizedBox(height: stack ? 10 : 6),
                            ],
                          ],
                        );
                      },
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

  /// When true, render label above value (full-width each) instead of
  /// the side-by-side label/value split. Used on iPhone SE-class
  /// screens where the 140pt label column squeezes long values.
  final bool stack;

  const _DetailRow({required this.field, required this.stack});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final labelStyle = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );
    final valueStyle = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurface,
      height: 1.35,
    );

    if (stack) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(field.label, style: labelStyle),
          const SizedBox(height: 2),
          Text(field.value, style: valueStyle),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: _labelColumnWidth,
          child: Text(field.label, style: labelStyle),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(field.value, style: valueStyle)),
      ],
    );
  }
}
