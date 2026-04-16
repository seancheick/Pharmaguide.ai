// Premium stack health widget — Oura-style card with animated score, one-line
// insight, micro metrics, top issue callout, and action CTA. Reactively
// watches the active stack, stack safety report, and synergy report.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/interaction_result.dart';
import 'package:pharmaguide/core/models/synergy_result.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_card.dart';
import 'package:pharmaguide/core/widgets/pg_score_ring.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/features/stack/providers/stack_providers.dart';
import 'package:pharmaguide/services/stack/stack_safety_scorer.dart';

/// Premium stack health widget. Shows empty-state card when the stack is
/// empty, otherwise delegates to [_StackHealthCard] for the populated view.
class HomeStackHealthWidget extends ConsumerWidget {
  const HomeStackHealthWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final stackAsync = ref.watch(activeStackProvider);

    return stackAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (stack) {
        if (stack.isEmpty) return _buildEmptyState(context, theme, scheme);
        return _StackHealthCard(stack: stack);
      },
    );
  }

  Widget _buildEmptyState(
    BuildContext context,
    ThemeData theme,
    ColorScheme scheme,
  ) {
    return PGCard(
      onTap: () => GoRouter.of(context).go(Routes.scan),
      variant: PGCardVariant.elevated,
      padding: const EdgeInsets.all(AppTheme.space20),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            ),
            child: Icon(
              Icons.layers_outlined,
              size: 24,
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: AppTheme.space16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Build your stack',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Add supplements to see safety scores & interactions.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            size: 22,
            color: scheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

/// The actual populated stack health card — only rendered when stack is non-empty.
class _StackHealthCard extends ConsumerWidget {
  final List<UserStacksLocalData> stack;
  const _StackHealthCard({required this.stack});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final reportAsync = ref.watch(stackSafetyReportProvider);
    final synergyAsync = ref.watch(synergyReportProvider);

    // Compute safety score from report
    final safetyScore = reportAsync.whenOrNull(
      data: (report) {
        final allIssues = <InteractionResult>[
          ...report.medicationPairInteractions,
          ...report.medicationInteractions,
          ...report.stackInteractions,
          ...report.categoryWarnings,
        ];
        final synergies = synergyAsync.whenOrNull(
              data: (synergyReport) => synergyReport.matches
                  .map((m) => SynergyResult(
                        ingredient1: m.matchedIngredients.isNotEmpty
                            ? m.matchedIngredients.first
                            : m.clusterId,
                        ingredient2: m.matchedIngredients.length > 1
                            ? m.matchedIngredients[1]
                            : m.clusterName,
                        description: m.mechanism,
                        evidenceLevel: EvidenceLevel.established,
                        bonus: m.bonusPoints,
                      ))
                  .toList(),
            ) ??
            const <SynergyResult>[];
        return const StackSafetyScorer().compute(
          issues: allIssues,
          synergies: synergies,
        );
      },
    );

    final score = safetyScore?.score;
    final serious = safetyScore?.seriousCount ?? 0;
    final moderate = safetyScore?.moderateCount ?? 0;
    final supplementCount =
        stack.where((e) => e.type == 'supplement').length;
    final medicationCount =
        stack.where((e) => e.type == 'medication').length;
    final interactionCount = serious + moderate;

    // Top issue — most severe interaction
    final topIssue = reportAsync.whenOrNull(
      data: (report) {
        final ordered = report.orderedWarnings;
        if (ordered.isEmpty) return null;
        final first = ordered.first;
        if (first is InteractionResult) return first.mechanism;
        return null;
      },
    );

    // Dynamic subtitle
    final subtitle = _subtitle(serious, moderate, interactionCount);
    // One-line insight
    final insight = _insight(serious, moderate, interactionCount);
    // Score glow color
    final glowColor = _glowColor(score);

    return PGCard(
      variant: PGCardVariant.elevated,
      onTap: () => GoRouter.of(context).go(Routes.stack),
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          // ---- Header + Score + Insight ----
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.space20,
              AppTheme.space20,
              AppTheme.space20,
              AppTheme.space16,
            ),
            child: Column(
              children: [
                // Title row
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Stack Health',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: glowColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Animated score ring with glow
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: score != null
                            ? [
                                BoxShadow(
                                  color: glowColor.withValues(alpha: 0.22),
                                  blurRadius: 20,
                                  spreadRadius: 2,
                                ),
                              ]
                            : null,
                      ),
                      child: PGScoreRing(
                        score: score?.toDouble(),
                        size: 64,
                        strokeWidth: 5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppTheme.space12),
                // One-line insight
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.space12,
                    vertical: AppTheme.space8,
                  ),
                  decoration: BoxDecoration(
                    color: glowColor.withValues(alpha: 0.08),
                    borderRadius:
                        BorderRadius.circular(AppTheme.radiusSmall),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _insightIcon(serious),
                        size: 14,
                        color: glowColor,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          insight,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: glowColor,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ---- Micro metrics row ----
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.space20,
              vertical: AppTheme.space12,
            ),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              border: Border(
                top: BorderSide(
                  color: scheme.outlineVariant,
                  width: 0.5,
                ),
              ),
            ),
            child: Row(
              children: [
                _MicroMetric(
                  icon: Icons.medication_outlined,
                  label: '$supplementCount supplements',
                  color: scheme.primary,
                ),
                const SizedBox(width: AppTheme.space16),
                _MicroMetric(
                  icon: Icons.local_pharmacy_outlined,
                  label: '$medicationCount medications',
                  color: AppTheme.info,
                ),
                const SizedBox(width: AppTheme.space16),
                _MicroMetric(
                  icon: interactionCount > 0
                      ? Icons.warning_amber_rounded
                      : Icons.check_circle_outline,
                  label: interactionCount > 0
                      ? '$interactionCount interaction${interactionCount == 1 ? '' : 's'}'
                      : 'No conflicts',
                  color: interactionCount > 0
                      ? AppTheme.severityCaution
                      : AppTheme.severitySafe,
                ),
              ],
            ),
          ),

          // ---- Top issue callout (conditional) ----
          if (topIssue != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(
                AppTheme.space20,
                AppTheme.space12,
                AppTheme.space20,
                AppTheme.space12,
              ),
              decoration: BoxDecoration(
                color: (serious > 0
                        ? AppTheme.severityContraindicated
                        : AppTheme.severityCaution)
                    .withValues(alpha: 0.06),
                border: Border(
                  top: BorderSide(
                    color: scheme.outlineVariant,
                    width: 0.5,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 14,
                    color: serious > 0
                        ? AppTheme.severityContraindicated
                        : AppTheme.severityCaution,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      topIssue,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

          // ---- CTA footer ----
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.space20,
              AppTheme.space12,
              AppTheme.space20,
              AppTheme.space16,
            ),
            child: Row(
              children: [
                Text(
                  interactionCount > 0 ? 'Review stack' : 'View stack',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 16,
                  color: scheme.primary,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _subtitle(int serious, int moderate, int total) {
    if (serious > 0) return 'Your stack needs attention';
    if (moderate > 0) return 'Minor optimizations available';
    return 'Your stack is well optimized';
  }

  String _insight(int serious, int moderate, int total) {
    if (serious > 0) {
      return '$serious high-risk interaction${serious == 1 ? '' : 's'} needs attention';
    }
    if (moderate > 0) {
      return '$moderate potential conflict${moderate == 1 ? '' : 's'} to review';
    }
    return 'No major interactions detected';
  }

  Color _glowColor(int? score) {
    if (score == null) return AppTheme.insufficientData;
    if (score >= 85) return AppTheme.scoreExceptional;
    if (score >= 70) return AppTheme.scoreExcellent;
    if (score >= 55) return AppTheme.scoreFair;
    return AppTheme.severityContraindicated;
  }

  IconData _insightIcon(int serious) {
    if (serious > 0) return Icons.error_outline_rounded;
    return Icons.check_circle_outline;
  }
}

/// Compact icon + label metric for the micro metrics row.
class _MicroMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _MicroMetric({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                    fontSize: 10.5,
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
