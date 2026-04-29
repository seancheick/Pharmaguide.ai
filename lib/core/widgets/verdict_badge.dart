import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';

/// Returns true when a verdict string represents a hard-stop
/// ban — BLOCKED only. Drives the FLTR-10 full-screen override:
/// banned/illegal products replace the product detail surface
/// entirely. UNSAFE is deliberately NOT included here — those
/// products still render the full detail screen with strong alerts.
bool isBlockedVerdict(String? verdict) {
  return (verdict ?? '').trim().toUpperCase() == 'BLOCKED';
}

/// Returns true when a verdict string is BLOCKED or legacy UNSAFE — i.e.
/// unsafe to add to a supplement stack under any circumstances.
/// Drives the FLTR-16 stack-add guard (domain + UI), which is
/// stricter than the BlockedProductView override: we still show
/// detail for UNSAFE products but never let them be tracked.
bool isUnsafeVerdict(String? verdict) {
  final v = (verdict ?? '').trim().toUpperCase();
  return v == 'BLOCKED' || v == 'UNSAFE';
}

/// Shared verdict badge used across search results and product detail.
///
/// A "verdict" is the final single-word rating from the scoring pipeline
/// (SAFE / CAUTION / POOR / BLOCKED / NOT_SCORED / NUTRITION_ONLY).
/// Retired labels are still accepted for old fixtures / cached rows.
/// Distinct from an interaction severity, which uses [PGSeverityPill].
class VerdictBadge extends StatelessWidget {
  final String verdict;

  const VerdictBadge({super.key, required this.verdict});

  /// Brightness-aware color for a verdict string. Used externally by
  /// consumers that need to color text or icons to match.
  static Color colorFor(String verdict) {
    switch (verdict.trim().toUpperCase()) {
      case 'RECOMMENDED':
        return AppTheme.scoreExceptional;
      case 'SAFE':
      case 'GOOD':
        return AppTheme.scoreExcellent;
      case 'CAUTION':
      case 'REVIEW':
        return AppTheme.scoreFair;
      case 'POOR':
      case 'MODERATE':
        return AppTheme.scoreLow;
      case 'UNSAFE':
      case 'BLOCKED':
        return AppTheme.severityContraindicated;
      case 'NOT_SCORED':
      case 'NUTRITION_ONLY':
        return AppTheme.insufficientData;
      default:
        return AppTheme.insufficientData;
    }
  }

  /// Human-friendly label. Avoids all-caps for verdicts longer than 12 chars.
  static String labelFor(String verdict) {
    switch (verdict.trim().toUpperCase()) {
      case 'RECOMMENDED':
        return 'Recommended';
      case 'SAFE':
        return 'Safe';
      case 'GOOD':
        return 'Good';
      case 'CAUTION':
        return 'Caution';
      case 'POOR':
        return 'Poor';
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
      case 'NUTRITION_ONLY':
        return 'Nutrition only';
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
