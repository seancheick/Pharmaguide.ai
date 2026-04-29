import 'package:flutter/material.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';

/// Pill badge for a [Severity] value — icon + label + tinted background.
///
/// This is the single source of truth for how severity is *visually*
/// rendered in PharmaGuide. If a pharmacist opens the app, they should know
/// at a glance whether something is contraindicated, cautionable, or safe.
///
/// Use [compact] = true inside cards or lists; false for standalone.
class PGSeverityPill extends StatelessWidget {
  final Severity severity;
  final bool compact;

  const PGSeverityPill({
    super.key,
    required this.severity,
    this.compact = false,
  });

  ({Color bg, Color fg, IconData icon, String label}) _style(bool isDark) {
    switch (severity) {
      case Severity.contraindicated:
        return (
          bg: AppTheme.severityContraindicated.withValues(
              alpha: isDark ? 0.22 : 0.10),
          fg: AppTheme.severityContraindicated,
          icon: Icons.block_rounded,
          label: 'Do not use',
        );
      case Severity.avoid:
        return (
          bg: AppTheme.severityAvoid.withValues(alpha: isDark ? 0.22 : 0.10),
          fg: AppTheme.severityAvoid,
          icon: Icons.error_outline_rounded,
          label: 'Avoid',
        );
      case Severity.caution:
        return (
          bg: AppTheme.severityCaution.withValues(alpha: isDark ? 0.22 : 0.12),
          fg: AppTheme.severityCaution,
          icon: Icons.warning_amber_rounded,
          label: 'Caution',
        );
      case Severity.monitor:
        return (
          bg: AppTheme.severityMonitor.withValues(alpha: isDark ? 0.22 : 0.14),
          fg: AppTheme.severityMonitor,
          icon: Icons.visibility_outlined,
          label: 'Monitor',
        );
      case Severity.informational:
        // Neutral informational note — no alarm. Used when a rule is
        // material but the user's profile hasn't declared the triggering
        // condition/drug class.
        return (
          bg: AppTheme.severityInformational.withValues(
              alpha: isDark ? 0.22 : 0.12),
          fg: AppTheme.severityInformational,
          icon: Icons.info_outline_rounded,
          label: 'Info',
        );
      case Severity.safe:
        return (
          bg: AppTheme.severitySafe.withValues(alpha: isDark ? 0.22 : 0.10),
          fg: AppTheme.severitySafe,
          icon: Icons.check_circle_outline_rounded,
          label: 'Safe',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final s = _style(isDark);

    final iconSize = compact ? 13.0 : 15.0;
    final textSize = compact ? 11.5 : 12.5;
    final hPad = compact ? 8.0 : 10.0;
    final vPad = compact ? 4.0 : 5.0;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
      decoration: BoxDecoration(
        color: s.bg,
        borderRadius: BorderRadius.circular(AppTheme.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(s.icon, size: iconSize, color: s.fg),
          SizedBox(width: compact ? 4 : 5),
          Text(
            s.label.toUpperCase(),
            style: TextStyle(
              fontSize: textSize,
              fontWeight: FontWeight.w700,
              color: s.fg,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}
