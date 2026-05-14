import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_eyebrow.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

/// Five severity tiers mirroring the website's clinical hierarchy.
///
/// Order is meaningful: contraindicated > avoid > caution > monitor > safe.
/// Severity is communicated through hierarchy and spacing, NOT aggressive
/// color saturation. Never brighten these tints (v2 plan anti-goal).
enum PGSeverity {
  contraindicated,
  avoid,
  caution,
  monitor,
  safe,
}

extension PGSeverityX on PGSeverity {
  /// Foreground / accent tone for the tier.
  Color get color => switch (this) {
    PGSeverity.contraindicated => V2Colors.contraindicated,
    PGSeverity.avoid => V2Colors.avoid,
    PGSeverity.caution => V2Colors.caution,
    PGSeverity.monitor => V2Colors.monitor,
    PGSeverity.safe => V2Colors.safe,
  };

  /// Background tint for the tier (10% opacity of [color]).
  Color get tint => switch (this) {
    PGSeverity.contraindicated => V2Colors.contraindicatedTint,
    PGSeverity.avoid => V2Colors.avoidTint,
    PGSeverity.caution => V2Colors.cautionTint,
    PGSeverity.monitor => V2Colors.monitorTint,
    PGSeverity.safe => V2Colors.safeTint,
  };

  /// Default display label. Caller may override at the badge level.
  String get label => switch (this) {
    PGSeverity.contraindicated => 'Contraindicated',
    PGSeverity.avoid => 'Avoid',
    PGSeverity.caution => 'Caution',
    PGSeverity.monitor => 'Monitor',
    PGSeverity.safe => 'Safe',
  };
}

/// Compact severity badge. Tint background + colored dot + label.
///
/// Pair with [evidence] overline below for clinical context, or leave it
/// off when severity is the only signal.
class PGSeverityBadge extends StatelessWidget {
  final PGSeverity severity;

  /// Override the default label (e.g. "High risk", "Monitor closely").
  final String? label;

  /// Optional evidence overline (ESTABLISHED / PROBABLE / MODERATE / etc.).
  /// Renders as a [PGOverline] below the badge.
  final String? evidence;

  /// When true, badge fills its parent's horizontal space (left-aligned).
  /// Default false (intrinsic width).
  final bool expand;

  const PGSeverityBadge({
    super.key,
    required this.severity,
    this.label,
    this.evidence,
    this.expand = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = severity.color;
    final tint = severity.tint;
    final displayLabel = label ?? severity.label;

    final badge = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: V2Spacing.space12,
        vertical: V2Spacing.space8,
      ),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
      ),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: V2Spacing.space8),
          Flexible(
            child: Text(
              displayLabel,
              style: V2Typography.bodyMedium(color: color),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );

    if (evidence == null) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        widthFactor: expand ? null : 1.0,
        child: badge,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        badge,
        const SizedBox(height: V2Spacing.space4),
        PGOverline(evidence!, color: color),
      ],
    );
  }
}
