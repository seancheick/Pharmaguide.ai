// Phase 11.7d.5 — Nutrition section adapter.
//
// V2 mirror of production's `NutritionPanel`. Composes the v2 PGNutritionPanel
// from `_product.caloriesPerServing` (Drift column) + `blob['nutrition_detail']`
// (Supabase blob field).
//
// Production data path (verbatim port from nutrition_panel.dart:178+):
//   caloriesPerServing column OR blob['nutrition_detail']['calories_per_serving']
//   Macros in FDA nutrition-label order:
//     1. total_fat_g           → "Total Fat"
//     2. total_carbohydrates_g → "Total Carbs"
//     3. dietary_fiber_g       → "Dietary Fiber"
//     4. protein_g             → "Protein"
//   Each row only renders when its blob value is non-null (a missing
//   macro doesn't pretend to be 0g).
//
// Sean's rules (2026-05-15):
//   • Preserve production gates: section hides when no rows have data.
//   • Use FDA nutrition-label ordering verbatim.
//   • No invented copy — Calories / Total Fat / Total Carbs / Dietary
//     Fiber / Protein are FDA-standard labels.
//   • Formatting verbatim: integers when whole, one decimal otherwise.
//
// Deferred to S9.next-iteration:
//   • %DV column — production NutritionPanel doesn't render %DV either,
//     so this matches behavior. PGNutritionFact supports dailyValue
//     if we later expose it from the pipeline.
//   • Vitamins/minerals (Sodium, Potassium, etc.) — production currently
//     omits these per FDA-style simplification.

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_nutrition_panel.dart';

/// Build the Nutrition section. Returns `SizedBox.shrink()` when no
/// row has data (matches production's `rows.isEmpty` gate).
Widget buildNutritionSection({
  required double? caloriesPerServing,
  required Map<String, dynamic>? nutritionDetail,
}) {
  // Calories: column is canonical. Falls back to blob value when null.
  final calories = caloriesPerServing ??
      _readNumber(nutritionDetail, 'calories_per_serving');

  // Macros: FDA-order, each only rendered when value is non-null.
  final facts = <PGNutritionFact>[];
  if (nutritionDetail != null) {
    final fat = _readNumber(nutritionDetail, 'total_fat_g');
    if (fat != null) {
      facts.add(PGNutritionFact(
        label: 'Total Fat',
        value: '${_formatGrams(fat)} g',
      ));
    }

    final carbs = _readNumber(nutritionDetail, 'total_carbohydrates_g');
    if (carbs != null) {
      facts.add(PGNutritionFact(
        label: 'Total Carbs',
        value: '${_formatGrams(carbs)} g',
      ));
    }

    final fiber = _readNumber(nutritionDetail, 'dietary_fiber_g');
    if (fiber != null) {
      facts.add(PGNutritionFact(
        label: 'Dietary Fiber',
        value: '${_formatGrams(fiber)} g',
      ));
    }

    final protein = _readNumber(nutritionDetail, 'protein_g');
    if (protein != null) {
      facts.add(PGNutritionFact(
        label: 'Protein',
        value: '${_formatGrams(protein)} g',
      ));
    }
  }

  if (calories == null && facts.isEmpty) {
    return const SizedBox.shrink();
  }

  return PGNutritionPanel(
    caloriesPerServing: calories?.round(),
    facts: facts,
    // Production title — verbatim "Nutrition Facts" (FDA label vocabulary).
    title: 'Nutrition Facts',
  );
}

/// Read a numeric field from the blob, accepting both `int` and `double`.
/// Verbatim port of production's `_readNumber` (nutrition_panel.dart:234).
double? _readNumber(Map<String, dynamic>? blob, String key) {
  if (blob == null) return null;
  final raw = blob[key];
  if (raw is num) return raw.toDouble();
  return null;
}

/// Format a macro value: whole-number when integer, one decimal otherwise.
/// Verbatim port of production's `_formatGrams` (nutrition_panel.dart:251).
String _formatGrams(double value) {
  if (value == value.truncateToDouble()) {
    return value.toInt().toString();
  }
  return value.toStringAsFixed(1);
}
