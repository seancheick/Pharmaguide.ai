import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/core/widgets/pg_modal.dart';

enum PGProbioticResearchStatus { exactStrain, formulaOnly, speciesLevel, none }

extension PGProbioticResearchStatusMeta on PGProbioticResearchStatus {
  String get label => switch (this) {
    PGProbioticResearchStatus.exactStrain =>
      'Research found for this exact strain',
    PGProbioticResearchStatus.formulaOnly =>
      'Research applies to the formula, not necessarily each strain',
    PGProbioticResearchStatus.speciesLevel =>
      'Research is available for this species, but not this exact strain',
    PGProbioticResearchStatus.none =>
      'No verified strain-specific research found',
  };

  IconData get icon => switch (this) {
    PGProbioticResearchStatus.exactStrain => Icons.verified_outlined,
    PGProbioticResearchStatus.formulaOnly => Icons.groups_outlined,
    PGProbioticResearchStatus.speciesLevel ||
    PGProbioticResearchStatus.none => Icons.search_off_outlined,
  };

  Color color(V2Palette palette) => switch (this) {
    PGProbioticResearchStatus.exactStrain => palette.safe,
    PGProbioticResearchStatus.formulaOnly => palette.accent,
    PGProbioticResearchStatus.speciesLevel ||
    PGProbioticResearchStatus.none => palette.fgMuted,
  };
}

class PGStrain {
  final String name;
  final String cfuLabel;
  final String supportLevel;
  final String indication;
  final PGProbioticResearchStatus researchStatus;
  final List<String> sourceUrls;
  final bool isInactivated;

  const PGStrain({
    required this.name,
    required this.cfuLabel,
    this.supportLevel = '',
    this.indication = '',
    this.researchStatus = PGProbioticResearchStatus.none,
    this.sourceUrls = const [],
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
  final void Function(List<String> sourceUrls)? onTapSources;

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
    this.title = 'Probiotic label & research',
    this.onTapSources,
  });

  bool get _hasContent => totalCfuLabel != null || strains.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    if (!_hasContent) return const SizedBox.shrink();
    final verifiedCount = strains
        .where(
          (strain) =>
              strain.researchStatus == PGProbioticResearchStatus.exactStrain,
        )
        .length;
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
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: V2Typography.titleSm(color: context.v2.fg),
                ),
              ),
              Semantics(
                button: true,
                label: 'About probiotic label and research',
                excludeSemantics: true,
                child: IconButton(
                  tooltip: 'About probiotic label and research',
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                  icon: Icon(
                    Icons.info_outline,
                    size: 20,
                    color: context.v2.accent,
                  ),
                  onPressed: () => _showExplanation(context),
                ),
              ),
            ],
          ),
          Text(
            'Probiotic effects may depend on the named microorganism, '
            'dose, and intended use.',
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
            Wrap(
              spacing: V2Spacing.space8,
              runSpacing: V2Spacing.space8,
              children: [
                _InfoChip(
                  icon: Icons.bubble_chart_outlined,
                  label:
                      '$namedCount named microorganism${namedCount == 1 ? '' : 's'}',
                  color: context.v2.accent,
                ),
                _InfoChip(
                  icon: verifiedCount > 0
                      ? Icons.verified_outlined
                      : Icons.search_off_outlined,
                  label: verifiedCount > 0
                      ? '$verifiedCount of $namedCount matched to verified research'
                      : 'No verified strain-specific research matches',
                  color: verifiedCount > 0
                      ? context.v2.safe
                      : context.v2.fgMuted,
                ),
              ],
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
            for (var i = 0; i < strains.length; i++)
              _StrainRow(
                strain: strains[i],
                isLast: i == strains.length - 1,
                onTapSources: onTapSources,
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

  void _showExplanation(BuildContext context) {
    PGModal.bottomSheet<void>(
      context: context,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'What this card means',
              style: V2Typography.titleSm(color: sheetContext.v2.fg),
            ),
            const SizedBox(height: V2Spacing.space12),
            Text(
              'We compare microorganisms named on the label with curated '
              'human research. A research match does not mean this exact '
              'product, formula, dose, or intended use was studied.',
              style: V2Typography.body(color: sheetContext.v2.fgMuted),
            ),
            const SizedBox(height: V2Spacing.space12),
            Text(
              '“No verified strain-specific research found” does not prove '
              'that no research exists. It means PharmaGuide could not '
              'verify an exact-strain match in the evidence reviewed so far.',
              style: V2Typography.body(color: sheetContext.v2.fgMuted),
            ),
          ],
        ),
      ),
    );
  }
}

String? _perStrainDisclosure(List<PGStrain> strains) {
  if (strains.isEmpty) return null;
  final disclosed = strains.where((s) => s.cfuLabel.trim().isNotEmpty).length;
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
  final void Function(List<String> sourceUrls)? onTapSources;

  const _StrainRow({
    required this.strain,
    required this.isLast,
    required this.onTapSources,
  });

  @override
  Widget build(BuildContext context) {
    final supportLine = _supportLine(strain);
    final semanticParts = [
      strain.name,
      strain.researchStatus.label,
      if (supportLine.isNotEmpty) supportLine,
      if (strain.cfuLabel.isNotEmpty)
        '${_expandCfu(strain.cfuLabel)} per serving',
      if (strain.isInactivated) 'Postbiotic or inactivated',
    ];
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(bottom: BorderSide(color: context.v2.outline, width: 0.4)),
      ),
      padding: const EdgeInsets.symmetric(vertical: V2Spacing.space12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            container: true,
            label: semanticParts.join('. '),
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strain.name,
                    style: V2Typography.bodySm(color: context.v2.fg),
                  ),
                  const SizedBox(height: V2Spacing.space4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        strain.researchStatus.icon,
                        size: 18,
                        color: strain.researchStatus.color(context.v2),
                      ),
                      const SizedBox(width: V2Spacing.space8),
                      Expanded(
                        child: Text(
                          strain.researchStatus.label,
                          style: V2Typography.bodySm(
                            color: strain.researchStatus.color(context.v2),
                          ).copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  if (supportLine.isNotEmpty) ...[
                    const SizedBox(height: V2Spacing.space4),
                    Text(
                      supportLine,
                      style: V2Typography.caption(color: context.v2.fgMuted),
                    ),
                  ],
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
          if (strain.sourceUrls.isNotEmpty && onTapSources != null) ...[
            const SizedBox(height: V2Spacing.space4),
            TextButton.icon(
              onPressed: () => onTapSources!(strain.sourceUrls),
              icon: const Icon(Icons.menu_book_outlined, size: 16),
              label: Text(
                'View ${strain.sourceUrls.length} '
                '${strain.sourceUrls.length == 1 ? 'source' : 'sources'}',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _supportLine(PGStrain strain) {
  final support = _titleCase(strain.supportLevel);
  final indication = _sentenceCase(strain.indication);
  if (support.isEmpty) return indication;
  if (indication.isEmpty) return '$support support';
  return '$support support · $indication';
}

String _titleCase(String value) {
  final clean = value.trim().toLowerCase();
  if (clean.isEmpty) return '';
  return clean
      .split(RegExp(r'\s+'))
      .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
      .join(' ');
}

String _sentenceCase(String value) {
  final clean = value.trim();
  if (clean.isEmpty) return '';
  return '${clean[0].toUpperCase()}${clean.substring(1)}';
}
