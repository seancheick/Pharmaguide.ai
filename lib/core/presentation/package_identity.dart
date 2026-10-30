/// Shared consumer-facing package identity derived from label net contents.
String? packageSizeLabel({
  required double? quantity,
  required String? unit,
  String fallbackFormFactor = '',
}) {
  if (quantity == null || quantity <= 0) return null;
  final quantityLabel = quantity == quantity.roundToDouble()
      ? quantity.toInt().toString()
      : quantity
            .toStringAsFixed(2)
            .replaceFirst(RegExp(r'0+$'), '')
            .replaceFirst(RegExp(r'\.$'), '');
  final rawUnit = (unit ?? '').trim().toLowerCase();
  final normalizedUnit = switch (rawUnit) {
    'softgel(s)' || 'softgel' || 'softgels' => 'softgels',
    'capsule(s)' || 'capsule' || 'capsules' => 'capsules',
    'tablet(s)' || 'tablet' || 'tablets' => 'tablets',
    'gummy(ies)' || 'gummy' || 'gummies' => 'gummies',
    'ounce(s)' || 'ounce' || 'ounces' || 'oz' => 'oz',
    'fluid ounce(s)' || 'fluid ounce' || 'fluid ounces' || 'fl oz' => 'fl oz',
    'gram(s)' || 'gram' || 'grams' || 'g' => 'g',
    'milliliter(s)' || 'milliliter' || 'milliliters' || 'ml' => 'mL',
    _ when rawUnit.isNotEmpty => rawUnit,
    _ => _pluralizedFormFactor(fallbackFormFactor, quantity),
  };
  return normalizedUnit.isEmpty
      ? quantityLabel
      : '$quantityLabel $normalizedUnit';
}

/// [printedText] is the label's own approximation ("about 17", from
/// `detail_blob.serving_info.servings_per_container_text`); when present it
/// replaces the bare count so an approximate count never reads as exact.
String? packageServingCountLabel(
  int? servingsPerContainer, {
  String? printedText,
}) {
  if (servingsPerContainer == null || servingsPerContainer <= 0) return null;
  final printed = printedText?.trim();
  final count = printed == null || printed.isEmpty
      ? '$servingsPerContainer'
      : printed;
  return '$count ${servingsPerContainer == 1 ? 'serving' : 'servings'}';
}

String _pluralizedFormFactor(String value, double quantity) {
  final form = value.trim().toLowerCase();
  if (form.isEmpty) return '';
  if (quantity == 1 || form.endsWith('s')) return form;
  if (form.endsWith('y')) return '${form.substring(0, form.length - 1)}ies';
  return '${form}s';
}
