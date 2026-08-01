// Formulation section adapter.
//
// Production reads `formulation_detail` blob (delivery_form,
// delivery_tier, absorption_enhancers, standardized_botanicals) and
// `ingredient_quality_data.demoted_absorption_enhancers`. Section
// suppresses when all four are empty.
//
// V2 PGFormulationSection takes form + tier + enhancers + botanicals
// + demotedEnhancers (string lists).

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_formulation_section.dart';
import 'package:pharmaguide/core/extensions/json_helpers.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';

/// Extract display names from a pipeline list field that may ship in
/// legacy string-list shape or current map-list shape.
List<String> extractIngredientNames(dynamic raw) {
  if (raw is! List) return const <String>[];
  return raw
      .map<String>((e) {
        if (e is String) return e.trim();
        if (e is Map) return (e['name']?.toString() ?? '').trim();
        return '';
      })
      .where((s) => s.isNotEmpty)
      .toList(growable: false);
}

/// Build the Formulation section. Returns `SizedBox.shrink()` when
/// the blob is null or no formulation signals are present.
Widget buildFormulationSection({
  required BuildContext context,
  required Map<String, dynamic>? formulationDetail,
  required Map<String, dynamic>? ingredientQualityData,
}) {
  if (formulationDetail == null) return const SizedBox.shrink();

  final deliveryForm =
      formulationDetail['delivery_form']?.toString().trim() ?? '';
  final deliveryTier =
      formulationDetail['delivery_tier']?.toString().trim() ?? '';
  final enhancers = extractIngredientNames(
    formulationDetail['absorption_enhancers'],
  );
  final botanicals = extractIngredientNames(
    formulationDetail['standardized_botanicals'],
  );

  final demotedRaw = (ingredientQualityData ?? const <String, dynamic>{})
      .safeList('demoted_absorption_enhancers')
      .whereType<Map<dynamic, dynamic>>()
      .map(_demotedEnhancerLabel)
      .where((s) => s.isNotEmpty)
      .toList(growable: false);

  if (deliveryForm.isEmpty &&
      enhancers.isEmpty &&
      botanicals.isEmpty &&
      demotedRaw.isEmpty) {
    return const SizedBox.shrink();
  }

  return PGFormulationSection(
    form: deliveryForm.isNotEmpty ? deliveryForm : null,
    formTierLabel: deliveryTier.isNotEmpty ? deliveryTier : null,
    formTierColor: deliveryTier.toLowerCase() == 'premium'
        ? context.v2.safe
        : null,
    absorptionEnhancers: enhancers,
    botanicals: botanicals,
    demotedEnhancers: demotedRaw,
  );
}

String _demotedEnhancerLabel(Map<dynamic, dynamic> raw) {
  final name = raw['name']?.toString().trim() ?? '';
  if (name.isEmpty) return '';
  final quantity = raw['quantity'];
  final unit = raw['unit']?.toString().trim() ?? '';
  final quantityLabel = quantity is num
      ? unit.isEmpty
            ? quantity.toString()
            : '${quantity.toString()} $unit'
      : '';
  return quantityLabel.isEmpty ? name : '$name $quantityLabel';
}
