// Excipient density section adapter for Product Detail v2.
//
// Closes the v2 gap — v1 surfaced "Minimal fillers / Moderate fillers
// / High filler load" as a quality signal alongside the ingredient
// lists. v2 dropped it during the reskin. Per Sean's mandate (v2 was
// a reskin, leave nothing behind), this adapter reuses the v1
// `ExcipientDensityCard` widget verbatim — same dose-form-aware
// thresholds, same whitelist-aware suppression, same severity tone.
//
// Data source: `detailBlob['ingredients']` (active list) +
// `detailBlob['inactive_ingredients']` (inactive list) +
// `product.deliveryForm` (capsule / tablet / powder / gummy).

import 'package:flutter/material.dart';
import 'package:pharmaguide/features/product_detail/widgets/excipient_density_card.dart';

/// Build the Excipient density section. Returns `SizedBox.shrink()`
/// when both ingredient lists are empty OR when every excipient is a
/// whitelisted standard manufacturing material within the form's
/// allowance (the card's own guard at `excipient_density_card.dart`
/// handles this — the section is hidden, not shown empty).
Widget buildExcipientDensitySection({
  required List<Map<String, dynamic>> activeIngredients,
  required List<Map<String, dynamic>> inactiveIngredients,
  required String? dosageForm,
}) {
  if (activeIngredients.isEmpty && inactiveIngredients.isEmpty) {
    return const SizedBox.shrink();
  }
  return ExcipientDensityCard(
    activeIngredients: activeIngredients,
    inactiveIngredients: inactiveIngredients,
    dosageForm: dosageForm,
  );
}
