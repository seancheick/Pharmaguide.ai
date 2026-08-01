import 'package:flutter/material.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
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

  /// Dark mode fills with a NEUTRAL elevated surface rather than a tint of the
  /// severity hue.
  ///
  /// A same-hue tint lifts the background toward its own text: at the previous
  /// 22% alpha the "Do not use" pill measured 2.11:1, and even with the dark
  /// severity ramp it only reached 3.38:1. The label is 11.5–12.5pt bold, below
  /// WCAG's 14pt-bold large-text threshold, so 4.5:1 is required and 3:1 is not
  /// available. A neutral fill clears 5.06–5.11:1 while leaving the muted
  /// palette untouched — the severity signal moves to the icon and label, which
  /// is also where a screen reader finds it.
  ({Color bg, Color fg, IconData icon, String label}) _style(
    V2Palette p,
    bool isDark,
  ) {
    switch (severity) {
      case Severity.contraindicated:
        return (
          bg: isDark
              ? p.surfaceHigh
              : p.contraindicated.withValues(alpha: 0.10),
          fg: p.contraindicated,
          icon: Icons.block_rounded,
          label: 'Do not use',
        );
      case Severity.avoid:
        return (
          bg: isDark
              ? p.surfaceHigh
              : p.avoid.withValues(alpha: 0.10),
          fg: p.avoid,
          icon: Icons.error_outline_rounded,
          // Sean 2026-04-30 — see severity.dart for the softer-tone
          // vocab rationale. The word "Avoid" is reserved for
          // contraindicated (banned/recalled).
          label: 'Not recommended',
        );
      case Severity.caution:
        return (
          bg: isDark
              ? p.surfaceHigh
              : p.caution.withValues(alpha: 0.12),
          fg: p.caution,
          icon: Icons.warning_amber_rounded,
          label: 'Use caution',
        );
      case Severity.monitor:
        return (
          bg: isDark
              ? p.surfaceHigh
              : p.monitor.withValues(alpha: 0.14),
          fg: p.monitor,
          icon: Icons.visibility_outlined,
          label: 'Monitor',
        );
      case Severity.informational:
        // Neutral informational note — no alarm. Used when a rule is
        // material but the user's profile hasn't declared the triggering
        // condition/drug class.
        return (
          bg: isDark
              ? p.surfaceHigh
              : p.fgMuted.withValues(alpha: 0.12),
          fg: p.fgMuted,
          icon: Icons.info_outline_rounded,
          label: 'Info',
        );
      case Severity.safe:
        return (
          bg: isDark
              ? p.surfaceHigh
              : p.safe.withValues(alpha: 0.10),
          fg: p.safe,
          icon: Icons.check_circle_outline_rounded,
          label: 'Safe',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final s = _style(context.v2, isDark);

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
