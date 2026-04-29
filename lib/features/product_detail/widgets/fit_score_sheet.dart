import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/models/fit_score_result.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_card.dart';
import 'package:pharmaguide/core/widgets/pg_frosted_nav_bar.dart';
import 'package:pharmaguide/core/widgets/pg_modal.dart';

/// Bottom sheet that explains the personal-fit assessment — shows the
/// state, top reasons, and the internal sub-signals used to derive it.
///
/// Reachable from the For You section's tier-label row. (The previous
/// `PGFitScoreBadge` widget that used to mount this sheet was retired
/// when the Fit display switched to tier-only — Sprint 27.21 / G follow-up.)
void showFitScoreSheet(BuildContext context, FitScoreResult result) {
  PGModal.bottomSheet<void>(
    context: context,
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
              const SizedBox(height: AppTheme.space4),
              Text(
                'How this product lines up with your profile.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppTheme.space20),

              // State summary
              _CombinedScoreCard(result: result),

              const SizedBox(height: AppTheme.space20),

              // Internal signals
              Text(
                'Signals considered',
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
                            const SizedBox(height: AppTheme.space2),
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
                'Personal fit is computed fresh every time from your current profile. '
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
    Color signalColor;
    IconData signalIcon;
    switch (result.state) {
      case FitAssessmentState.strongMatch:
        signalColor = AppTheme.severitySafe;
        signalIcon = Icons.check_circle_outline_rounded;
        break;
      case FitAssessmentState.goodFit:
        signalColor = scheme.primary;
        signalIcon = Icons.thumb_up_off_alt_rounded;
        break;
      case FitAssessmentState.limitedFit:
        signalColor = AppTheme.severityCaution;
        signalIcon = Icons.warning_amber_rounded;
        break;
      case FitAssessmentState.notRecommended:
        signalColor = AppTheme.severityContraindicated;
        signalIcon = Icons.error_outline_rounded;
        break;
      case FitAssessmentState.incompleteProfile:
        signalColor = AppTheme.insufficientData;
        signalIcon = Icons.person_add_alt_1_rounded;
        break;
    }

    return PGCard(
      padding: const EdgeInsets.all(AppTheme.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(signalIcon, color: signalColor, size: 20),
              const SizedBox(width: AppTheme.space8),
              Expanded(
                child: Text(
                  result.fitLabel,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: signalColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.space8),
          ...result.reasons.take(3).map((reason) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '• $reason',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              )),
          if (result.maxRelevantSeverity != null) ...[
            const SizedBox(height: AppTheme.space8),
            Text(
              'Relevant risk: ${result.maxRelevantSeverity}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
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
                const SizedBox(height: AppTheme.space4),
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
                const SizedBox(height: AppTheme.space4),
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
