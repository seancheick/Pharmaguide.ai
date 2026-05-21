import 'package:flutter/material.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';

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
          bg: V2Colors.contraindicated.withValues(alpha: isDark ? 0.22 : 0.10),
          fg: V2Colors.contraindicated,
          icon: Icons.block_rounded,
          label: 'Do not use',
        );
      case Severity.avoid:
        return (
          bg: V2Colors.avoid.withValues(alpha: isDark ? 0.22 : 0.10),
          fg: V2Colors.avoid,
          icon: Icons.error_outline_rounded,
          // Sean 2026-04-30 — see severity.dart for the softer-tone
          // vocab rationale. The word "Avoid" is reserved for
          // contraindicated (banned/recalled).
          label: 'Not recommended',
        );
      case Severity.caution:
        return (
          bg: V2Colors.caution.withValues(alpha: isDark ? 0.22 : 0.12),
          fg: V2Colors.caution,
          icon: Icons.warning_amber_rounded,
          label: 'Use caution',
        );
      case Severity.monitor:
        return (
          bg: V2Colors.monitor.withValues(alpha: isDark ? 0.22 : 0.14),
          fg: V2Colors.monitor,
          icon: Icons.visibility_outlined,
          label: 'Monitor',
        );
      case Severity.informational:
        // Neutral informational note — no alarm. Used when a rule is
        // material but the user's profile hasn't declared the triggering
        // condition/drug class.
        return (
          bg: V2Colors.fgMuted.withValues(alpha: isDark ? 0.22 : 0.12),
          fg: V2Colors.fgMuted,
          icon: Icons.info_outline_rounded,
          label: 'Info',
        );
      case Severity.safe:
        return (
          bg: V2Colors.safe.withValues(alpha: isDark ? 0.22 : 0.10),
          fg: V2Colors.safe,
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
        borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(s.icon, size: iconSize, color: s.fg),
          SizedBox(width: compact ? 4 : 5),
          Text(
            // Sean 2026-04-30 — sentence case (no .toUpperCase) so the
            // pill matches the softer-tone vocabulary in severity.dart
            // ("Not recommended" reads softer than "NOT RECOMMENDED").
            s.label,
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
