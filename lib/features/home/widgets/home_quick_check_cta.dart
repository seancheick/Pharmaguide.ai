// Quick Check CTA — "Safe to take together?" — opens the quick-check screen.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_card.dart';

class HomeQuickCheckCta extends StatelessWidget {
  const HomeQuickCheckCta({super.key});

  @override
  Widget build(BuildContext context) {
    return PGCard(
      onTap: () => GoRouter.of(context).push(Routes.quickCheck),
      padding: const EdgeInsets.all(AppTheme.space16),
      child: Semantics(
        button: true,
        label:
            'Check if two supplements or medications are safe to take together',
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.severityCaution.withValues(alpha: 0.12),
                borderRadius:
                    BorderRadius.circular(AppTheme.radiusMedium),
              ),
              child: const Icon(
                Icons.compare_arrows_rounded,
                color: AppTheme.severityCaution,
                size: 20,
              ),
            ),
            const SizedBox(width: AppTheme.space12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Safe to take together?',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Check any two products for interactions',
                    style:
                        Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
