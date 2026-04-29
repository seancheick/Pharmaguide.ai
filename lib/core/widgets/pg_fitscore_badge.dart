import 'package:flutter/material.dart';
import 'package:pharmaguide/core/models/fit_score_result.dart';
import 'package:pharmaguide/core/theme/app_motion.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';

/// "Personalized for you" FitScore badge — sits next to the product score
/// ring on the detail screen to show how the score adjusts for the user's
/// profile (age, sex, goals, conditions, drug classes).
///
/// States:
/// - `Strong match`
/// - `Good fit`
/// - `Limited fit`
/// - `Not recommended`
/// - `Incomplete profile`
///
/// ```dart
/// PGFitScoreBadge(
///   result: fitScoreAsync.value,
///   onTap: () => showFitScoreSheet(context, result),
/// )
/// ```
class PGFitScoreBadge extends StatelessWidget {
  final FitScoreResult? result;
  final VoidCallback? onTap;
  final bool compact;

  const PGFitScoreBadge({
    super.key,
    required this.result,
    this.onTap,
    this.compact = false,
  });

  /// VoiceOver label for the current state. Read to users in place of
  /// the visual pill.
  String _semanticLabel(FitScoreResult r) {
    final reasons = r.reasons.isEmpty ? '' : ' ${r.reasons.join(' ')}';
    switch (r.state) {
      case FitAssessmentState.notRecommended:
        return 'Personal fit: not recommended.$reasons';
      case FitAssessmentState.limitedFit:
        return 'Personal fit: limited fit.$reasons';
      case FitAssessmentState.goodFit:
        return 'Personal fit: good fit.$reasons';
      case FitAssessmentState.strongMatch:
        return 'Personal fit: strong match.$reasons';
      case FitAssessmentState.incompleteProfile:
        return 'Personal fit: incomplete profile.$reasons';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final r = result;

    // Loading / unavailable — show nothing (or a shimmer in a parent).
    if (r == null) return const SizedBox.shrink();

    // Decide appearance from the stateful fit assessment, not the raw score.
    late final Color accent;
    late final IconData icon;
    late final String label;

    switch (r.state) {
      case FitAssessmentState.incompleteProfile:
        accent = AppTheme.insufficientData;
        icon = Icons.person_add_alt_1_rounded;
        label = 'Complete profile';
        break;
      case FitAssessmentState.notRecommended:
        accent = AppTheme.severityContraindicated;
        icon = Icons.error_outline_rounded;
        label = 'Not recommended';
        break;
      case FitAssessmentState.limitedFit:
        accent = AppTheme.severityCaution;
        icon = Icons.warning_amber_rounded;
        label = 'Limited fit';
        break;
      case FitAssessmentState.goodFit:
        accent = scheme.primary;
        icon = Icons.person_outline_rounded;
        label = 'Good fit';
        break;
      case FitAssessmentState.strongMatch:
        accent = AppTheme.severitySafe;
        icon = Icons.check_circle_outline_rounded;
        label = 'Strong match';
        break;
    }

    final hPad = compact ? 8.0 : 10.0;
    final vPad = compact ? 4.0 : 6.0;
    final iconSize = compact ? 12.0 : 14.0;
    final textSize = compact ? 11.0 : 12.0;

    final pill = AnimatedContainer(
      duration: AppMotion.medium,
      curve: AppMotion.standard,
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppTheme.radiusFull),
        border: Border.all(
          color: accent.withValues(alpha: 0.22),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: iconSize, color: accent),
          SizedBox(width: compact ? 4 : 5),
          Text(
            label,
            style: AppTheme.numeric(
              TextStyle(
                fontSize: textSize,
                fontWeight: FontWeight.w700,
                color: accent,
                letterSpacing: 0.1,
                height: 1.2,
              ),
            ),
          ),
          if (onTap != null) ...[
            SizedBox(width: compact ? 2 : 3),
            Icon(
              Icons.chevron_right_rounded,
              size: iconSize + 2,
              color: accent,
            ),
          ],
        ],
      ),
    );

    if (onTap == null) {
      return Semantics(
        label: _semanticLabel(r),
        child: ExcludeSemantics(child: pill),
      );
    }

    return Semantics(
      button: true,
      label: _semanticLabel(r),
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppTheme.radiusFull),
          clipBehavior: Clip.antiAlias,
          child: InkWell(onTap: onTap, child: pill),
        ),
      ),
    );
  }
}
