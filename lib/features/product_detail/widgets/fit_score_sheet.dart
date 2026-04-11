import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/models/fit_score_result.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_card.dart';
import 'package:pharmaguide/core/widgets/pg_frosted_nav_bar.dart';

/// Bottom sheet that explains a FitScore result — shows the 4 sub-scores
/// (E1 Dosage, E2a Goals, E2b Age, E2c Medical) with context, plus a
/// "complete your profile" nudge if any fields are missing.
///
/// Called from [PGFitScoreBadge]'s onTap on the product detail screen.
void showFitScoreSheet(BuildContext context, FitScoreResult result) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (ctx) => _FitScoreSheet(result: result),
  );
}

class _FitScoreSheet extends StatelessWidget {
  final FitScoreResult result;
  const _FitScoreSheet({required this.result});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final missing = result.missingFields;

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return SingleChildScrollView(
          controller: scrollController,
          // Bottom padding clears the frosted nav bar (extendBody: true
          // means the scaffold body flows under it).
          padding: const EdgeInsets.fromLTRB(
            AppTheme.space20,
            AppTheme.space8,
            AppTheme.space20,
            AppTheme.space32 + kPGNavBarHeight,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Text(
                'Personalized for you',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'How this product scored against your profile.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppTheme.space20),

              // Combined score summary
              _CombinedScoreCard(result: result),

              const SizedBox(height: AppTheme.space20),

              // 4 sub-score rows
              Text(
                'Score breakdown',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppTheme.space12),
              _ScoreRow(
                label: 'Dosage match',
                description: 'How close dosing is to your age/sex RDA',
                score: result.e1,
                maxScore: 7,
                icon: Icons.medication_liquid_rounded,
              ),
              const SizedBox(height: AppTheme.space8),
              _ScoreRow(
                label: 'Goal alignment',
                description: 'Matches your selected health goals',
                score: result.e2a,
                maxScore: 2,
                icon: Icons.flag_outlined,
              ),
              const SizedBox(height: AppTheme.space8),
              _ScoreRow(
                label: 'Age appropriateness',
                description: 'Nutrient needs for your age bracket',
                score: result.e2b,
                maxScore: 3,
                icon: Icons.cake_outlined,
              ),
              const SizedBox(height: AppTheme.space8),
              _ScoreRow(
                label: 'Medical compatibility',
                description:
                    'Conditions + medications you have on file',
                score: result.e2c,
                maxScore: 8,
                icon: Icons.medical_information_outlined,
              ),

              // Missing fields nudge
              if (missing.isNotEmpty) ...[
                const SizedBox(height: AppTheme.space20),
                PGCard(
                  variant: PGCardVariant.highlighted,
                  tintColor: AppTheme.insufficientData,
                  padding: const EdgeInsets.all(AppTheme.space16),
                  onTap: () {
                    Navigator.of(context).pop();
                    GoRouter.of(context).push(Routes.profileSetup);
                  },
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppTheme.insufficientData.withValues(
                            alpha: 0.14,
                          ),
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusFull,
                          ),
                        ),
                        child: const Icon(
                          Icons.person_add_alt_1_rounded,
                          color: AppTheme.insufficientData,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: AppTheme.space12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Missing: ${missing.join(', ')}',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Complete your profile for a fully personalized score.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
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
              ],

              const SizedBox(height: AppTheme.space20),

              // Privacy note
              Text(
                'FitScore is computed fresh every time from your current profile. '
                'It is never stored on our servers.',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CombinedScoreCard extends StatelessWidget {
  final FitScoreResult result;
  const _CombinedScoreCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final adjustment = result.scoreFit20;
    final pct = result.maxPossible > 0
        ? (result.scoreCombined100 / result.maxPossible * 100)
        : 0.0;

    // Adjustment signal color
    Color signalColor;
    IconData signalIcon;
    String signalLabel;
    if (adjustment >= 2) {
      signalColor = AppTheme.severitySafe;
      signalIcon = Icons.trending_up_rounded;
      signalLabel = 'Well-suited for you';
    } else if (adjustment >= -2) {
      signalColor = scheme.primary;
      signalIcon = Icons.horizontal_rule_rounded;
      signalLabel = 'Average match';
    } else if (adjustment >= -5) {
      signalColor = AppTheme.severityCaution;
      signalIcon = Icons.trending_down_rounded;
      signalLabel = 'Some concerns';
    } else {
      signalColor = AppTheme.severityContraindicated;
      signalIcon = Icons.error_outline_rounded;
      signalLabel = 'Poor fit for your profile';
    }

    return PGCard(
      padding: const EdgeInsets.all(AppTheme.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(signalIcon, color: signalColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  signalLabel,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: signalColor,
                  ),
                ),
              ),
              Text(
                '${adjustment >= 0 ? '+' : ''}${adjustment.toStringAsFixed(1)}',
                style: AppTheme.numeric(
                  theme.textTheme.titleLarge!.copyWith(
                    fontWeight: FontWeight.w700,
                    color: signalColor,
                    fontSize: 22,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.space8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Combined score',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              Text(
                '${result.scoreCombined100.toStringAsFixed(0)}'
                ' / ${result.maxPossible.toStringAsFixed(0)}'
                '  ·  ${pct.toStringAsFixed(0)}%',
                style: AppTheme.numeric(
                  theme.textTheme.bodySmall!.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ScoreRow extends StatelessWidget {
  final String label;
  final String description;
  final double score;
  final double maxScore;
  final IconData icon;

  const _ScoreRow({
    required this.label,
    required this.description,
    required this.score,
    required this.maxScore,
    required this.icon,
  });

  Color _colorFor(double pct, ColorScheme scheme) {
    if (pct >= 0.85) return AppTheme.severitySafe;
    if (pct >= 0.5) return scheme.primary;
    if (pct >= 0.25) return AppTheme.severityCaution;
    return AppTheme.severityContraindicated;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final pct = maxScore > 0 ? (score / maxScore).clamp(0.0, 1.0) : 0.0;
    final color = _colorFor(pct, scheme);

    return PGCard(
      variant: PGCardVariant.recessed,
      padding: const EdgeInsets.all(AppTheme.space12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: AppTheme.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      '${score.toStringAsFixed(1)} / ${maxScore.toStringAsFixed(0)}',
                      style: AppTheme.numeric(
                        theme.textTheme.labelSmall!.copyWith(
                          fontSize: 11.5,
                          color: color,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // Mini progress bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 4,
                    backgroundColor: scheme.surfaceContainerHigh,
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontSize: 11.5,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
