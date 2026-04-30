// NutritionPanel — surfaces the v1.3.2 nutrition data on the product
// detail screen.
//
// Data sources (hybrid model from build_final_db.py v1.3.2):
//
//   1. caloriesPerServing — products_core.calories_per_serving column.
//      Hybrid promotion: calories is the highest-value user filter so it
//      lives as a queryable column. This is the canonical value.
//
//   2. nutritionDetail — detail_blob.nutrition_detail subkey, a JSON
//      object with five floats (one for each macro). Loaded from the
//      detail blob fetched by the product_detail_screen state. Includes
//      calories_per_serving as well, but the column wins on conflict.
//
//   Keys in nutritionDetail (all nullable):
//     calories_per_serving      (kcal — column wins)
//     total_carbohydrates_g     (g)
//     total_fat_g               (g)
//     protein_g                 (g)
//     dietary_fiber_g           (g)
//
// The widget renders nothing if neither caloriesPerServing nor any macro
// in nutritionDetail is present — products without a nutrition facts
// panel just don't show this section.

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/constants/app_colors.dart';

/// T18 (2026-04-30) — collapsed Nutrition Facts to a link that opens
/// a bottom-sheet containing the full panel. Pre-T18 the full panel
/// rendered inline in the Deep Dive section, dominating scroll for
/// products that ship a nutrition label (gummies, powders, RTD shakes).
/// Spec: INITIATIVE_PRODUCT_DETAIL_CLEANUP.md, Sprint S2.2, T18.
///
/// Hides itself when neither caloriesPerServing nor any macro is
/// present — same auto-hide rule as the embedded panel below.
class NutritionFactsLink extends StatelessWidget {
  final double? caloriesPerServing;
  final Map<String, dynamic>? nutritionDetail;

  const NutritionFactsLink({
    super.key,
    required this.caloriesPerServing,
    required this.nutritionDetail,
  });

  @override
  Widget build(BuildContext context) {
    // Reuse NutritionPanel's row-building logic to test for content.
    // Cheaper than duplicating the row checks here.
    final probe = NutritionPanel(
      caloriesPerServing: caloriesPerServing,
      nutritionDetail: nutritionDetail,
    );
    if (probe._buildRows().isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      onTap: () => _openSheet(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.space12,
          vertical: AppTheme.space12,
        ),
        child: Row(
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppTheme.space12),
            Expanded(
              child: Text(
                'View supplement facts',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  void _openSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetCtx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            AppTheme.space16,
            0,
            AppTheme.space16,
            MediaQuery.of(sheetCtx).viewPadding.bottom + AppTheme.space16,
          ),
          child: NutritionPanel(
            caloriesPerServing: caloriesPerServing,
            nutritionDetail: nutritionDetail,
          ),
        );
      },
    );
  }
}

class NutritionPanel extends StatelessWidget {
  final double? caloriesPerServing;
  final Map<String, dynamic>? nutritionDetail;

  const NutritionPanel({
    super.key,
    required this.caloriesPerServing,
    required this.nutritionDetail,
  });

  @override
  Widget build(BuildContext context) {
    final rows = _buildRows();
    if (rows.isEmpty) {
      return const SizedBox.shrink();
    }

    final resolved = AppColors.of(context);
    return Card(
      key: const Key('nutrition-panel-card'),
      color: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant,
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.space16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Nutrition Facts',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: resolved.textPrimary,
              ),
            ),
            const SizedBox(height: AppTheme.space4),
            Text(
              'Per serving',
              style: TextStyle(fontSize: 12, color: resolved.textSecondary),
            ),
            const SizedBox(height: AppTheme.space12),
            ...rows,
          ],
        ),
      ),
    );
  }

  /// Build the visible rows. Row order is fixed: Calories first, then
  /// macros in nutrition-label convention.
  List<_NutritionRow> _buildRows() {
    final rows = <_NutritionRow>[];

    // Calories: column is canonical. Falls back to blob value only if
    // the column is null AND the blob value is non-null.
    final calories =
        caloriesPerServing ??
        _readNumber(nutritionDetail, 'calories_per_serving');
    if (calories != null) {
      rows.add(_NutritionRow(label: 'Calories', value: _formatWhole(calories)));
    }

    // Macros in nutrition-label order: total fat, total carbs, dietary
    // fiber, protein. Each only renders when its blob value is non-null
    // (so a missing macro doesn't pretend to be 0g).
    if (nutritionDetail == null) {
      return rows;
    }

    final fat = _readNumber(nutritionDetail, 'total_fat_g');
    if (fat != null) {
      rows.add(
        _NutritionRow(label: 'Total Fat', value: '${_formatGrams(fat)} g'),
      );
    }

    final carbs = _readNumber(nutritionDetail, 'total_carbohydrates_g');
    if (carbs != null) {
      rows.add(
        _NutritionRow(label: 'Total Carbs', value: '${_formatGrams(carbs)} g'),
      );
    }

    final fiber = _readNumber(nutritionDetail, 'dietary_fiber_g');
    if (fiber != null) {
      rows.add(
        _NutritionRow(
          label: 'Dietary Fiber',
          value: '${_formatGrams(fiber)} g',
        ),
      );
    }

    final protein = _readNumber(nutritionDetail, 'protein_g');
    if (protein != null) {
      rows.add(
        _NutritionRow(label: 'Protein', value: '${_formatGrams(protein)} g'),
      );
    }

    return rows;
  }

  /// Read a numeric field from the blob, accepting both `int` and
  /// `double` (jsonDecode produces either depending on the source).
  /// Returns null if the key is missing or the value is not numeric.
  static double? _readNumber(Map<String, dynamic>? blob, String key) {
    if (blob == null) return null;
    final raw = blob[key];
    if (raw is num) return raw.toDouble();
    return null;
  }

  /// Format a calories value: whole number, no trailing ".0".
  static String _formatWhole(double value) {
    if (value == value.truncateToDouble()) {
      return value.toInt().toString();
    }
    return value.toString();
  }

  /// Format a macro value: whole number with no ".0", otherwise keep one
  /// decimal place. We don't trail more than one decimal — that's noisy.
  static String _formatGrams(double value) {
    if (value == value.truncateToDouble()) {
      return value.toInt().toString();
    }
    // Strip trailing zeroes from the decimal but keep at least one digit.
    final formatted = value.toStringAsFixed(1);
    return formatted;
  }
}

/// Single label/value row in the nutrition panel.
class _NutritionRow extends StatelessWidget {
  final String label;
  final String value;

  const _NutritionRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final resolved = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 14, color: resolved.textPrimary),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: resolved.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
