// Premium stack health widget — compact status card with one-line insight,
// micro metrics, top issue callout, and action CTA. Reactively watches the
// active stack, stack safety report, and synergy report.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/interaction_result.dart';
import 'package:pharmaguide/core/models/stack_intelligence.dart';
import 'package:pharmaguide/core/models/stack_safety_score.dart';
import 'package:pharmaguide/core/models/synergy_result.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_card.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/features/stack/providers/stack_providers.dart';
import 'package:pharmaguide/services/stack/stack_intelligence_engine.dart';
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
                const SizedBox(height: AppTheme.space2),
                Text(
                  'Add supplements to review interactions, overlap, and coverage.',
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
    final recallAsync = ref.watch(recalledIngredientsReportProvider);

    // Compute the internal stack score from report signals. The user-facing
    // surface renders a health label derived from this score + severity caps.
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

    final serious = safetyScore?.seriousCount ?? 0;
    final moderate = safetyScore?.moderateCount ?? 0;
    final supplementCount =
        stack.where((e) => e.type == 'supplement').length;
    final medicationCount =
        stack.where((e) => e.type == 'medication').length;
    final interactionCount = serious + moderate;

    // Diagnostic verdict: lets recalled/banned ingredients dominate the
    // headline regardless of the numeric score. Falls back to the
    // score-derived label while any input is still loading so the UI
    // does not flicker.
    final StackIntelligence? intelligence =
        (reportAsync.hasValue && synergyAsync.hasValue && recallAsync.hasValue)
            ? const StackIntelligenceEngine().diagnose(
                stackSize: stack.length,
                safetyReport: reportAsync.value!,
                recalledReport: recallAsync.value!,
                synergyReport: synergyAsync.value!,
                qualityScore: safetyScore?.score,
              )
            : null;
    final status = intelligence?.tier.healthLabel ?? safetyScore?.healthLabel;

    // Top issue — recall first (when present), else most severe interaction.
    final topIssue = (intelligence != null && intelligence.issues.isNotEmpty)
        ? intelligence.issues.first.headline
        : reportAsync.whenOrNull(
            data: (report) {
              final ordered = report.orderedWarnings;
              if (ordered.isEmpty) return null;
              final first = ordered.first;
              if (first is InteractionResult) return first.mechanism;
              return null;
            },
          );

    final insight = _insight(status, serious, moderate);
    final tone = status?.color ?? scheme.primary;

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
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                          const SizedBox(height: AppTheme.space2),
                          Text(
                            _contextLine(supplementCount, medicationCount),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTheme.space12,
                        vertical: AppTheme.space8,
                      ),
                      decoration: BoxDecoration(
                        color: tone.withValues(alpha: 0.1),
                        borderRadius:
                            BorderRadius.circular(AppTheme.radiusFull),
                        border: Border.all(
                          color: tone.withValues(alpha: 0.2),
                          width: 0.8,
                        ),
                      ),
                      child: Text(
                        status?.label ?? 'Analyzing',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: tone,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.1,
                        ),
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
                    color: tone.withValues(alpha: 0.08),
                    borderRadius:
                        BorderRadius.circular(AppTheme.radiusSmall),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _insightIcon(status, serious),
                        size: 14,
                        color: tone,
                      ),
                      const SizedBox(width: AppTheme.space6),
                      Expanded(
                        child: Text(
                          insight,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: tone,
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
                  label: _countLabel(supplementCount, 'supplement'),
                  color: scheme.primary,
                ),
                const SizedBox(width: AppTheme.space16),
                _MicroMetric(
                  icon: Icons.local_pharmacy_outlined,
                  label: _countLabel(medicationCount, 'medication'),
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
                  const SizedBox(width: AppTheme.space8),
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
                const SizedBox(width: AppTheme.space4),
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

  String _contextLine(int supplementCount, int medicationCount) {
    return '${_countLabel(supplementCount, 'supplement')} · '
        '${_countLabel(medicationCount, 'medication')}';
  }

  String _countLabel(int count, String noun) {
    return '$count ${count == 1 ? noun : '${noun}s'}';
  }

  String _insight(
    StackHealthLabel? status,
    int serious,
    int moderate,
  ) {
    if (status == null) {
      return 'Checking your current stack for interactions and overlap';
    }
    if (status == StackHealthLabel.unsafe) {
      return '$serious high-risk interaction${serious == 1 ? '' : 's'} needs attention';
    }
    if (status == StackHealthLabel.concerning) {
      return 'This stack needs closer review for interactions and overlap';
    }
    if (serious > 0) {
      return '$serious high-risk interaction${serious == 1 ? '' : 's'} needs attention';
    }
    if (moderate > 0) {
      return '$moderate potential conflict${moderate == 1 ? '' : 's'} to review';
    }
    return 'No major interactions detected';
  }

  IconData _insightIcon(StackHealthLabel? status, int serious) {
    if (status == StackHealthLabel.unsafe || serious > 0) {
      return Icons.error_outline_rounded;
    }
    if (status == StackHealthLabel.concerning) {
      return Icons.warning_amber_rounded;
    }
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
          const SizedBox(width: AppTheme.space4),
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
