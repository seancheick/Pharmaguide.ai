import 'package:flutter/material.dart';
import 'package:pharmaguide/core/scoring/score_tier.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

/// Same data shape (`ScoreTier` + `tierForScore`), same semantics
/// (locked color + label + description per tier), same layout (row of
/// dot + `90/100` + tier label, then description line). Only the
/// typography + spacing tokens shift to v2:
/// - Geist Sans 500 for `90/100` and tier label (was titleMedium w800/w700)
/// - Geist Sans body for the description (was bodySmall)
/// - 8pt gaps from V2Spacing
///
/// Tier dots retain the brighter chart token; tier-colored text uses the
/// darker `ScoreTier.textColor` companion so it remains readable on cream and
/// white surfaces.
///
/// Use anywhere production uses `ScoreLine` — in the hero card under the
/// product name, on alternative-product cards, etc.
class PGScoreLine extends StatelessWidget {
  /// 0–100 product score. Out-of-range values clamp gracefully via
  /// [tierForScore]: ≥100 → Exceptional, <0 → Poor.
  final int score;

  /// Optional override for the locked tier description. Almost always
  /// keep null and let `ScoreTierMeta.description` provide the locked
  /// clinician copy — same escape-hatch contract as production.
  final String? descriptionOverride;

  /// Diameter of the leading tier dot. Defaults to 10pt to match
  /// production exactly.
  final double dotSize;

  /// Compact mode for list / alternative cards. Drops the score +
  /// tier label from 18pt → 14pt and hides the description line so
  /// the line fits a single tight row. Hero usage keeps the default
  /// expansive layout.
  final bool compact;

  /// Product-detail hero treatment. Keeps the concise one-line layout while
  /// restoring decision-level emphasis and coloring the numeric score by its
  /// tier. The adjacent tier label preserves meaning beyond color alone.
  final bool prominent;

  const PGScoreLine({
    super.key,
    required this.score,
    this.descriptionOverride,
    this.dotSize = 10,
    this.compact = false,
    this.prominent = false,
  }) : assert(!compact || !prominent);

  @override
  Widget build(BuildContext context) {
    final tier = tierForScore(score);
    // Production displays the score AS-GIVEN even if out of range — keeps
    // a "105/100" UI as a clear data-quality signal. Mirror that.
    final displayScore = score;
    final headlineSize = prominent ? 22.0 : (compact ? 14.0 : 18.0);
    final dot = compact ? 8.0 : dotSize;
    final headlineWeight = prominent ? FontWeight.w600 : FontWeight.w500;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: dot,
              height: dot,
              decoration: BoxDecoration(
                color: tier.color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: V2Spacing.space8),
            // Score numeric + tier label kept as separate Text widgets
            // (matches production — `find.text('Exceptional')` matches
            // in widget tests this way).
            Text(
              '$displayScore/100',
              style:
                  V2Typography.bodyMedium(
                    color: prominent ? tier.textColor : V2Colors.fg,
                  ).copyWith(
                    fontSize: headlineSize,
                    fontWeight: headlineWeight,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
            ),
            const SizedBox(width: V2Spacing.space8),
            // Tier label wraps in Flexible + ellipsis so the row
            // can survive tight column widths (e.g. 130pt slot
            // in Home's Recent-scans carousel). Long labels like
            // "Exceptional" overflow otherwise.
            Flexible(
              child: Text(
                tier.label,
                style: V2Typography.bodyMedium(
                  color: tier.textColor,
                ).copyWith(fontSize: headlineSize, fontWeight: headlineWeight),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        if (!compact && !prominent) ...[
          const SizedBox(height: V2Spacing.space4),
          Text(
            descriptionOverride ?? tier.description,
            style: V2Typography.bodySm(color: V2Colors.fgMuted),
          ),
        ],
      ],
    );
  }
}
