import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

/// Label-declared microorganism. Research claims intentionally do not live on
/// this model until the pipeline has an authoritative strain-evidence producer.
class PGStrain {
  final String name;
  final String cfuLabel;
  final bool isInactivated;

  const PGStrain({
    required this.name,
    required this.cfuLabel,
    this.isInactivated = false,
  });
}

class PGProbioticSection extends StatelessWidget {
  final String? totalCfuLabel;
  final int? totalStrainCount;
  final bool hasSurvivabilityCoating;
  final String? survivabilityReason;
  final bool prebioticPresent;
  final bool hasPostbioticStrains;
  final String? prebioticName;
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
    this.title = 'Probiotic label details',
  });

  bool get _hasContent => totalCfuLabel != null || strains.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    if (!_hasContent) return const SizedBox.shrink();
    final namedCount = totalStrainCount ?? strains.length;
    final disclosure = _perStrainDisclosure(strains);
    final hasFormulaDetails =
        hasSurvivabilityCoating || prebioticPresent || hasPostbioticStrains;

    return Container(
      padding: const EdgeInsets.all(V2Spacing.space16),
      decoration: BoxDecoration(
        color: context.v2.surface,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        border: Border.all(color: context.v2.outline),
        boxShadow: V2Shadows.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: V2Typography.titleSm(color: context.v2.fg)),
          const SizedBox(height: V2Spacing.space4),
          Text(
            'Microorganisms and amounts declared on the product label.',
            style: V2Typography.bodySm(color: context.v2.fgMuted),
          ),
          if (totalCfuLabel != null) ...[
            const SizedBox(height: V2Spacing.space12),
            Text(
              '${totalCfuLabel!} total per serving',
              semanticsLabel: '${_expandCfu(totalCfuLabel!)} total per serving',
              style: V2Typography.bodyMedium(color: context.v2.fg),
            ),
          ],
          if (namedCount > 0) ...[
            const SizedBox(height: V2Spacing.space8),
            _InfoChip(
              icon: Icons.bubble_chart_outlined,
              label:
                  '$namedCount named microorganism${namedCount == 1 ? '' : 's'}',
              color: context.v2.accent,
            ),
          ],
          if (disclosure != null) ...[
            const SizedBox(height: V2Spacing.space8),
            Text(
              disclosure,
              style: V2Typography.caption(color: context.v2.fgMuted),
            ),
          ],
          if (strains.isNotEmpty) ...[
            const SizedBox(height: V2Spacing.space16),
            Divider(color: context.v2.outline, height: 1, thickness: 0.5),
            const SizedBox(height: V2Spacing.space8),
            for (var index = 0; index < strains.length; index++)
              _StrainRow(
                strain: strains[index],
                isLast: index == strains.length - 1,
              ),
          ],
          if (hasFormulaDetails) ...[
            const SizedBox(height: V2Spacing.space12),
            Divider(color: context.v2.outline, height: 1, thickness: 0.5),
            const SizedBox(height: V2Spacing.space12),
            Text(
              'Formula details',
              style: V2Typography.bodyMedium(color: context.v2.fg),
            ),
            const SizedBox(height: V2Spacing.space8),
            Wrap(
              spacing: V2Spacing.space8,
              runSpacing: V2Spacing.space8,
              children: [
                if (hasSurvivabilityCoating)
                  _InfoChip(
                    icon: Icons.shield_outlined,
                    label: survivabilityReason ?? 'Survivability coating',
                    color: context.v2.accent,
                  ),
                if (prebioticPresent)
                  _InfoChip(
                    icon: Icons.spa_outlined,
                    label: prebioticName != null && prebioticName!.isNotEmpty
                        ? 'Prebiotic · $prebioticName'
                        : 'Prebiotic included',
                    color: context.v2.accent,
                  ),
                if (hasPostbioticStrains)
                  _InfoChip(
                    icon: Icons.spa_outlined,
                    label: 'Postbiotic included',
                    color: context.v2.monitor,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

String? _perStrainDisclosure(List<PGStrain> strains) {
  if (strains.isEmpty) return null;
  final disclosed = strains
      .where((strain) => strain.cfuLabel.isNotEmpty)
      .length;
  if (disclosed == 0) return 'Per-strain amounts not disclosed';
  if (disclosed == strains.length) return 'Per-strain amounts disclosed';
  return 'Some per-strain amounts not disclosed';
}

String _expandCfu(String value) =>
    value.replaceAll(RegExp(r'\bCFU\b'), 'colony-forming units');

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
    final style = context.v2.tintedLabel(color);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: style.fill,
        borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: V2Spacing.space4),
          Flexible(
            child: Text(
              label,
              style: V2Typography.caption(
                color: style.foreground,
              ).copyWith(fontWeight: FontWeight.w600),
            ),
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
    final semanticParts = [
      strain.name,
      if (strain.cfuLabel.isNotEmpty)
        '${_expandCfu(strain.cfuLabel)} per serving',
      if (strain.isInactivated) 'Postbiotic or inactivated',
    ];
    return Semantics(
      container: true,
      label: semanticParts.join('. '),
      child: ExcludeSemantics(
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          decoration: BoxDecoration(
            border: isLast
                ? null
                : Border(
                    bottom: BorderSide(color: context.v2.outline, width: 0.4),
                  ),
          ),
          padding: const EdgeInsets.symmetric(vertical: V2Spacing.space12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strain.name,
                style: V2Typography.bodySm(color: context.v2.fg),
              ),
              if (strain.cfuLabel.isNotEmpty) ...[
                const SizedBox(height: V2Spacing.space4),
                Text(
                  '${strain.cfuLabel} per serving',
                  style: V2Typography.caption(color: context.v2.fgMuted),
                ),
              ],
              if (strain.isInactivated) ...[
                const SizedBox(height: V2Spacing.space4),
                Text(
                  'Postbiotic · inactivated microorganism',
                  style: V2Typography.caption(color: context.v2.fgMuted),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
