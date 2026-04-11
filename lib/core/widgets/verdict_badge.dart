import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';

/// Shared verdict badge used across search results and product detail.
///
/// A "verdict" is the final single-word rating from the scoring pipeline
/// (RECOMMENDED / GOOD / MODERATE / REVIEW / UNSAFE / BLOCKED / NOT_SCORED).
/// Distinct from an interaction severity, which uses [PGSeverityPill].
class VerdictBadge extends StatelessWidget {
  final String verdict;

  const VerdictBadge({super.key, required this.verdict});

  /// Brightness-aware color for a verdict string. Used externally by
  /// consumers that need to color text or icons to match.
  static Color colorFor(String verdict) {
    switch (verdict.toUpperCase()) {
      case 'RECOMMENDED':
        return AppTheme.scoreExceptional;
      case 'GOOD':
        return AppTheme.scoreExcellent;
      case 'MODERATE':
        return AppTheme.scoreBelowAvg;
      case 'REVIEW':
        return AppTheme.scoreFair;
      case 'UNSAFE':
      case 'BLOCKED':
        return AppTheme.severityContraindicated;
      case 'NOT_SCORED':
        return AppTheme.insufficientData;
      default:
        return AppTheme.insufficientData;
    }
  }

  /// Human-friendly label. Avoids all-caps for verdicts longer than 12 chars.
  static String labelFor(String verdict) {
    switch (verdict.toUpperCase()) {
      case 'RECOMMENDED':
        return 'Recommended';
      case 'GOOD':
        return 'Good';
      case 'MODERATE':
        return 'Moderate';
      case 'REVIEW':
        return 'Review';
      case 'UNSAFE':
        return 'Unsafe';
      case 'BLOCKED':
        return 'Blocked';
      case 'NOT_SCORED':
        return 'Not scored';
      default:
        return verdict;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (verdict.isEmpty) return const SizedBox.shrink();
    final color = colorFor(verdict);
    final label = labelFor(verdict);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.22 : 0.10),
        borderRadius: BorderRadius.circular(AppTheme.radiusFull),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.4,
          height: 1.2,
        ),
      ),
    );
  }
}
