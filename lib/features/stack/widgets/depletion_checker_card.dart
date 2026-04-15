// Depletion Checker Card — shows nutrients depleted by user's medications.
//
// Rendered below the timing advice on the stack screen. Each depletion
// shows the medication, depleted nutrient, severity, and whether the
// user already covers it with a supplement in their stack.

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_card.dart';
import 'package:pharmaguide/services/stack/depletion_checker.dart';

class DepletionCheckerCard extends StatelessWidget {
  final List<DepletionMatch> depletions;
  final EdgeInsetsGeometry margin;

  const DepletionCheckerCard({
    super.key,
    required this.depletions,
    this.margin = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    if (depletions.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final uncovered = depletions.where((d) => !d.isCovered).length;

    return Padding(
      padding: margin,
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          side: BorderSide(
            color: AppTheme.severityCaution.withValues(alpha: 0.3),
          ),
        ),
        color: AppTheme.severityCaution.withValues(alpha: 0.04),
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.space16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  const Icon(
                    Icons.science_outlined,
                    size: 20,
                    color: AppTheme.severityCaution,
                  ),
                  const SizedBox(width: AppTheme.space8),
                  Text(
                    'Nutrient Depletions',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: AppTheme.severityCaution,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  if (uncovered > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTheme.space8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.severityCaution.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                      ),
                      child: Text(
                        '$uncovered uncovered',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppTheme.severityCaution,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Your medications may reduce levels of these nutrients.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppTheme.space12),

              // Depletion items
              ...depletions.map(
                (dep) => _DepletionItem(depletion: dep),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DepletionItem extends StatelessWidget {
  final DepletionMatch depletion;
  const _DepletionItem({required this.depletion});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isCovered = depletion.isCovered;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.space8),
      child: PGCard(
        variant: PGCardVariant.recessed,
        padding: const EdgeInsets.all(AppTheme.space12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Status icon
                Icon(
                  isCovered
                      ? Icons.check_circle_rounded
                      : Icons.warning_amber_rounded,
                  size: 18,
                  color: isCovered
                      ? AppTheme.severitySafe
                      : AppTheme.severityCaution,
                ),
                const SizedBox(width: AppTheme.space8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Nutrient name
                      Text(
                        depletion.nutrientName,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      // Drug cause
                      Text(
                        'Depleted by ${depletion.drugDisplayName}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                // Severity + coverage badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: isCovered
                        ? AppTheme.severitySafe.withValues(alpha: 0.1)
                        : _severityColor(depletion.severity)
                            .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isCovered ? 'COVERED' : depletion.severity.toUpperCase(),
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: isCovered
                          ? AppTheme.severitySafe
                          : _severityColor(depletion.severity),
                    ),
                  ),
                ),
              ],
            ),
            if (depletion.recommendation.isNotEmpty && !isCovered) ...[
              const SizedBox(height: 6),
              Text(
                depletion.recommendation,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _severityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'critical':
        return AppTheme.severityContraindicated;
      case 'significant':
        return AppTheme.severityAvoid;
      case 'moderate':
        return AppTheme.severityCaution;
      default:
        return AppTheme.severityMonitor;
    }
  }
}
