// Allergen summary banner — compact warning row when allergens are present.

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';

class AllergenSummaryBanner extends StatelessWidget {
  final String? allergenSummary;
  const AllergenSummaryBanner({super.key, this.allergenSummary});

  @override
  Widget build(BuildContext context) {
    if (allergenSummary == null || allergenSummary!.isEmpty) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.space12,
        vertical: AppTheme.space8,
      ),
      decoration: BoxDecoration(
        color: AppTheme.severityCaution.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(
          color: AppTheme.severityCaution.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 16,
            color: AppTheme.severityCaution,
          ),
          const SizedBox(width: AppTheme.space8),
          Expanded(
            child: Text(
              allergenSummary!,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: AppTheme.severityCaution,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
