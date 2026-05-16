// Phase 11.7e — Formulation section adapter (S13).
//
// V2 mirror of production's `FormulationDetailSection`
// (lib/features/product_detail/widgets/pipeline_sections/
// formulation_detail_section.dart).
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
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/features/product_detail/widgets/pipeline_sections/formulation_detail_section.dart'
    show extractIngredientNames;

/// Build the Formulation section. Returns `SizedBox.shrink()` when
/// the blob is null or no formulation signals are present.
Widget buildFormulationSection({
  required Map<String, dynamic>? formulationDetail,
  required Map<String, dynamic>? ingredientQualityData,
}) {
  if (formulationDetail == null) return const SizedBox.shrink();

  final deliveryForm = formulationDetail['delivery_form']?.toString().trim() ??
      '';
  final deliveryTier =
      formulationDetail['delivery_tier']?.toString().trim() ?? '';
  final enhancers = extractIngredientNames(
    formulationDetail['absorption_enhancers'],
  );
  final botanicals = extractIngredientNames(
    formulationDetail['standardized_botanicals'],
  );

  // demoted_absorption_enhancers ships as `[{name, quantity, unit}, ...]`.
  // Production extracts a richer `_BioavailabilityAid` value object — for
  // v2 we just need names (chip labels).
  final demotedRaw = (ingredientQualityData ?? const <String, dynamic>{})
      .safeList('demoted_absorption_enhancers')
      .whereType<Map<dynamic, dynamic>>()
      .map((m) => (m['name']?.toString() ?? '').trim())
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
        ? AppTheme.severitySafe
        : null,
    absorptionEnhancers: enhancers,
    botanicals: botanicals,
    demotedEnhancers: demotedRaw,
  );
}
