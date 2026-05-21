import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

/// One nutrition-facts row — typically a single macro/micro with its
/// per-serving amount + %DV. Mirrors production's `NutritionPanel`
/// row shape.
class PGNutritionFact {
  final String label;
  final String value;

  /// %DV string ("12% DV" / null when unknown).
  final String? dailyValue;

  /// True for headline rows (Calories, Total Fat, Total Carbs) that
  /// production renders with bold weight + heavier divider.
  final bool isHeadline;

  const PGNutritionFact({
    required this.label,
    required this.value,
    this.dailyValue,
    this.isHeadline = false,
  });
}

/// v2 nutrition facts panel.
///
/// Compact supplement-facts panel — name + amount + %DV. Hidden when
/// there's no nutrition data.
class PGNutritionPanel extends StatelessWidget {
  /// Optional kcal per serving — production renders this as the first
  /// row in bold.
  final int? caloriesPerServing;

  /// Nutrition fact rows in label order (caller respects the FDA
  /// nutrition-facts ordering convention).
  final List<PGNutritionFact> facts;

  final String title;
  final String? servingSize;

  const PGNutritionPanel({
    super.key,
    this.caloriesPerServing,
    this.facts = const [],
    this.title = 'Nutrition facts',
    this.servingSize,
  });

  @override
  Widget build(BuildContext context) {
    if (facts.isEmpty && caloriesPerServing == null) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.all(V2Spacing.space16),
      decoration: BoxDecoration(
        color: V2Colors.surface,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        border: Border.all(color: V2Colors.outline),
        boxShadow: V2Shadows.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: V2Typography.titleSm(color: V2Colors.fg)),
          if (servingSize != null) ...[
            const SizedBox(height: 2),
            Text(
              'Serving size · $servingSize',
              style: V2Typography.caption(color: V2Colors.fgMuted),
            ),
          ],
          const SizedBox(height: V2Spacing.space12),
          if (caloriesPerServing != null) ...[
            _NutritionRow(
              fact: PGNutritionFact(
                label: 'Calories',
                value: '$caloriesPerServing',
                isHeadline: true,
              ),
              isLast: facts.isEmpty,
            ),
          ],
          for (var i = 0; i < facts.length; i++)
            _NutritionRow(fact: facts[i], isLast: i == facts.length - 1),
        ],
      ),
    );
  }
}

class _NutritionRow extends StatelessWidget {
  final PGNutritionFact fact;
  final bool isLast;

  const _NutritionRow({required this.fact, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final labelStyle = fact.isHeadline
        ? V2Typography.bodyMedium(color: V2Colors.fg)
        : V2Typography.bodySm(color: V2Colors.fg);
    return Container(
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(
                bottom: BorderSide(color: V2Colors.outline, width: 0.4),
              ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: V2Spacing.space8),
        child: Row(
          children: [
            Expanded(child: Text(fact.label, style: labelStyle)),
            Text(fact.value, style: V2Typography.monoData(color: V2Colors.fg)),
            if (fact.dailyValue != null) ...[
              const SizedBox(width: V2Spacing.space12),
              SizedBox(
                width: 56,
                child: Text(
                  fact.dailyValue!,
                  textAlign: TextAlign.right,
                  style: V2Typography.monoData(color: V2Colors.fgMuted),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
