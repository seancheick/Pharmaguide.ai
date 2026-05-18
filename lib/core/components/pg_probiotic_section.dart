import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

/// One probiotic strain — name + CFU + evidence level + flags.
class PGStrain {
  final String name;

  /// Per-strain CFU label, e.g. "5 billion CFU".
  final String cfuLabel;

  /// Evidence level for this strain ("ESTABLISHED" / "MODERATE" / "LIMITED").
  final String evidence;

  /// True when the strain is inactivated (postbiotic) rather than live.
  final bool isInactivated;

  /// True when the strain has documented clinical-trial support.
  final bool isClinical;

  const PGStrain({
    required this.name,
    required this.cfuLabel,
    required this.evidence,
    this.isInactivated = false,
    this.isClinical = false,
  });
}

/// v2 mirror of `ProbioticDetailSection`
/// (lib/features/product_detail/widgets/pipeline_sections/
/// probiotic_detail_section.dart).
///
/// Total CFU + strain count summary row at top, then per-strain rows
/// with name + CFU + evidence chip. Survivability coating + prebiotic
/// signals appear as inline info chips above the strain list.
class PGProbioticSection extends StatelessWidget {
  /// Total CFU label ("12 billion CFU"). Null hides the headline.
  final String? totalCfuLabel;

  /// Total strain count. Null hides the strain count chip.
  final int? totalStrainCount;

  /// True when the product uses a survivability coating
  /// (delayed-release / spore form).
  final bool hasSurvivabilityCoating;

  /// Optional reason explaining the coating ("Delayed-release capsule",
  /// "Spore-forming Bacillus").
  final String? survivabilityReason;

  /// True when the product includes prebiotic fiber.
  final bool prebioticPresent;

  /// True when the product includes inactivated/postbiotic strains.
  final bool hasPostbioticStrains;

  /// Prebiotic name when present ("Inulin", "FOS").
  final String? prebioticName;

  /// Strains in pipeline order. First 8 visible; the rest collapsed
  /// behind "View N more" — caller controls the slicing if needed.
  final List<PGStrain> strains;

  final String title;

  const PGProbioticSection({
    super.key,
    this.totalCfuLabel,
    this.totalStrainCount,
    this.hasSurvivabilityCoating = false,
    this.survivabilityReason,
    this.prebioticPresent = false,
    this.hasPostbioticStrains = false,
    this.prebioticName,
    this.strains = const [],
    this.title = 'Probiotic strains',
  });

  bool get _hasContent => totalCfuLabel != null || strains.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    if (!_hasContent) return const SizedBox.shrink();
    final clinicalCount = strains.where((s) => s.isClinical).length;
    final hasSummaryChips =
        totalStrainCount != null ||
        clinicalCount > 0 ||
        hasSurvivabilityCoating ||
        prebioticPresent ||
        hasPostbioticStrains;
    return Container(
      padding: const EdgeInsets.all(V2Spacing.space16),
      decoration: BoxDecoration(
        color: V2Colors.surface,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        border: Border.all(color: V2Colors.outline),
        boxShadow: V2Shadows.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: V2Typography.titleSm(color: V2Colors.fg)),
          if (totalCfuLabel != null) ...[
            const SizedBox(height: V2Spacing.space4),
            Text(
              totalCfuLabel!,
              style: V2Typography.bodyMedium(color: V2Colors.fg),
            ),
          ],
          if (hasSummaryChips) ...[
            const SizedBox(height: V2Spacing.space12),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (totalStrainCount != null)
                  _InfoChip(
                    icon: Icons.bubble_chart_outlined,
                    label:
                        '$totalStrainCount strain${totalStrainCount == 1 ? '' : 's'}',
                    color: V2Colors.accent,
                  ),
                if (clinicalCount > 0)
                  _InfoChip(
                    icon: Icons.verified_outlined,
                    label: '$clinicalCount clinically studied',
                    color: V2Colors.safe,
                  ),
                if (hasSurvivabilityCoating)
                  _InfoChip(
                    icon: Icons.shield_outlined,
                    label: survivabilityReason ?? 'Survivability coating',
                    color: V2Colors.safe,
                  ),
                if (prebioticPresent)
                  _InfoChip(
                    icon: Icons.spa_outlined,
                    label: prebioticName != null
                        ? 'Prebiotic · $prebioticName'
                        : 'Prebiotic included',
                    color: V2Colors.safe,
                  ),
                if (hasPostbioticStrains)
                  const _InfoChip(
                    icon: Icons.spa_outlined,
                    label: 'Postbiotic included',
                    color: V2Colors.monitor,
                  ),
              ],
            ),
          ],
          if (strains.isNotEmpty) ...[
            const SizedBox(height: V2Spacing.space16),
            const Divider(color: V2Colors.outline, height: 1, thickness: 0.5),
            const SizedBox(height: V2Spacing.space12),
            for (var i = 0; i < strains.length; i++)
              _StrainRow(strain: strains[i], isLast: i == strains.length - 1),
          ],
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: V2Typography.caption(
              color: color,
            ).copyWith(fontSize: 11, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

class _StrainRow extends StatelessWidget {
  final PGStrain strain;
  final bool isLast;

  const _StrainRow({required this.strain, required this.isLast});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(
                bottom: BorderSide(color: V2Colors.outline, width: 0.4),
              ),
      ),
      padding: const EdgeInsets.symmetric(vertical: V2Spacing.space8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            strain.isClinical
                ? Icons.check_circle_outline
                : Icons.circle_outlined,
            size: 14,
            color: strain.isClinical ? V2Colors.safe : V2Colors.fgSubtle,
          ),
          const SizedBox(width: V2Spacing.space8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strain.name,
                  style: V2Typography.bodySm(color: V2Colors.fg),
                ),
                const SizedBox(height: 2),
                // **Phase 11.7h.5 — Sean 2026-05-16 dose transparency:**
                // When per-strain CFU is missing, say so explicitly
                // instead of silently leaving the strain as a decorative
                // chip with no meaning. "CFU not disclosed" reads as a
                // calm transparency note, not an alarm.
                _StrainMetaLine(
                  cfuLabel: strain.cfuLabel,
                  evidence: strain.evidence,
                  isInactivated: strain.isInactivated,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Sub-line beneath a strain name: per-strain CFU + evidence level +
/// inactivated/postbiotic flag. Explicit about missing data — when
/// cfuLabel is empty, surfaces "CFU not disclosed" so users know the
/// strain isn't decorative (Sean 2026-05-16 polish).
class _StrainMetaLine extends StatelessWidget {
  final String cfuLabel;
  final String evidence;
  final bool isInactivated;

  const _StrainMetaLine({
    required this.cfuLabel,
    required this.evidence,
    required this.isInactivated,
  });

  @override
  Widget build(BuildContext context) {
    final parts = <Widget>[];

    if (cfuLabel.trim().isNotEmpty) {
      parts.add(
        Text(cfuLabel, style: V2Typography.caption(color: V2Colors.fgMuted)),
      );
    } else {
      parts.add(
        Text(
          'CFU not disclosed',
          style: V2Typography.caption(color: V2Colors.fgSubtle),
        ),
      );
    }

    if (evidence.trim().isNotEmpty) {
      parts.add(const SizedBox(width: V2Spacing.space8));
      parts.add(
        Text(
          '· $evidence evidence',
          style: V2Typography.caption(color: V2Colors.fgSubtle),
        ),
      );
    }

    if (isInactivated) {
      parts.add(const SizedBox(width: V2Spacing.space8));
      parts.add(
        Text(
          '· postbiotic',
          style: V2Typography.caption(color: V2Colors.fgSubtle),
        ),
      );
    }

    return Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: parts);
  }
}
