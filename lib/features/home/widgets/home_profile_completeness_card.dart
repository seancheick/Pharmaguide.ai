// Profile completeness prompt — shown on home while the user's profile is
// below 60% complete. Taps route to the profile setup screen.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_card.dart';

class HomeProfileCompletenessCard extends StatelessWidget {
  final int completeness;
  const HomeProfileCompletenessCard({super.key, required this.completeness});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return PGCard(
      variant: PGCardVariant.highlighted,
      onTap: () => GoRouter.of(context).push(Routes.profileSetup),
      padding: const EdgeInsets.all(AppTheme.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                ),
                child: Icon(
                  Icons.person_add_alt_1_rounded,
                  color: scheme.primary,
                  size: 18,
                ),
              ),
              const SizedBox(width: AppTheme.space12),
              Expanded(
                child: Text(
                  'Complete your health profile',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '$completeness%',
                style: AppTheme.numeric(
                  theme.textTheme.titleMedium!.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.space12),
          // Progress bar — rounded, 6pt tall
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusFull),
            child: LinearProgressIndicator(
              value: completeness / 100,
              minHeight: 6,
              backgroundColor: scheme.primary.withValues(alpha: 0.14),
              valueColor: AlwaysStoppedAnimation(scheme.primary),
            ),
          ),
          const SizedBox(height: AppTheme.space12),
          Text(
            'Add your meds, conditions, and allergies for more personal stack guidance.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
