// v2 modal bottom sheet that explains a single active ingredient.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_ingredient_data.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/core/widgets/pg_modal.dart';
import 'package:pharmaguide/features/product_detail/widgets/ingredient_explain_model.dart';
import 'package:url_launcher/url_launcher.dart';

typedef OpenFormEvidenceSource =
    Future<void> Function(PGFormEvidenceSource source);

/// Opens the explain sheet for [ingredient]. Returns when the sheet is
/// dismissed.
Future<void> showIngredientExplainSheet(
  BuildContext context, {
  required Map<String, dynamic> ingredient,
  Map<String, dynamic>? ulEntry,
  OpenFormEvidenceSource? openEvidenceSource,
}) {
  final explain = buildIngredientExplain(
    ingredient: ingredient,
    ulEntry: ulEntry,
  );
  return PGModal.bottomSheet<void>(
    context: context,
    builder: (_) => _Sheet(
      explain: explain,
      openEvidenceSource: openEvidenceSource ?? _openEvidenceSource,
    ),
  );
}

Future<void> _openEvidenceSource(PGFormEvidenceSource source) async {
  final uri = Uri.tryParse(source.url);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

class _Sheet extends StatelessWidget {
  final IngredientExplain explain;
  final OpenFormEvidenceSource openEvidenceSource;

  const _Sheet({required this.explain, required this.openEvidenceSource});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.46,
      minChildSize: 0.34,
      maxChildSize: 0.85,
      expand: false,
      builder: (_, scrollController) {
        return _SheetBody(
          explain: explain,
          scrollController: scrollController,
          openEvidenceSource: openEvidenceSource,
        );
      },
    );
  }
}

class _SheetBody extends StatelessWidget {
  final IngredientExplain explain;
  final ScrollController scrollController;
  final OpenFormEvidenceSource openEvidenceSource;

  const _SheetBody({
    required this.explain,
    required this.scrollController,
    required this.openEvidenceSource,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(
        V2Spacing.space24,
        V2Spacing.space8,
        V2Spacing.space24,
        V2Spacing.space24,
      ),
      children: [
        Text(explain.title, style: V2Typography.titleSm(color: context.v2.fg)),
        const SizedBox(height: V2Spacing.space16),
        if (explain.formName != null)
          _FactTile(
            icon: Icons.science_outlined,
            label: 'Form',
            value: explain.formName!,
          ),
        if (explain.doseLabel != null)
          _FactTile(
            icon: Icons.straighten_rounded,
            label: 'Dose',
            value: _doseFactValue(explain),
          ),
        if (explain.evidenceLabel != null)
          _FactTile(
            icon: Icons.science_outlined,
            label: 'Evidence',
            value: explain.evidenceLabel!,
          ),
        const SizedBox(height: V2Spacing.space16),
        Divider(color: context.v2.outline, height: 1, thickness: 0.4),
        const SizedBox(height: V2Spacing.space16),
        // Assessed forms render only reviewed, form-specific pipeline copy.
        // formExplanation is reserved for material non-quality states such as
        // a missing disclosure; it is never a tier-based fallback.
        if (explain.formHeading != null &&
            (explain.formNote != null || explain.formExplanation != null))
          _Block(
            accent: _formAccent(context.v2, explain.formQuality),
            tint: _formTint(context.v2, explain.formQuality),
            heading: explain.formHeading!,
            body:
                explain.formNotePreview ??
                explain.formNote ??
                explain.formExplanation!,
            expandedBody: explain.formNote,
          ),
        if (explain.formEvidenceSources.isNotEmpty) ...[
          const SizedBox(height: V2Spacing.space12),
          _FormEvidenceSources(
            level: explain.formEvidenceLevel!,
            sources: explain.formEvidenceSources,
            onOpen: openEvidenceSource,
          ),
        ],
        if (explain.doseExplanation.isNotEmpty) ...[
          const SizedBox(height: V2Spacing.space12),
          _Block(
            accent: _doseAccent(context.v2, explain.doseCallOut),
            tint: _doseTint(context.v2, explain.doseCallOut),
            heading: doseBlockHeading(explain.doseCallOut),
            body: explain.doseExplanation,
          ),
        ],
        const SizedBox(height: V2Spacing.space24),
        Text(
          'Educational use only — not medical advice.',
          style: V2Typography.caption(color: context.v2.fgSubtle),
        ),
      ],
    );
  }

  static String _doseFactValue(IngredientExplain explain) {
    final parenthetical = explain.parentheticalDoseText;
    if (parenthetical == null) return explain.doseLabel!;
    return '${explain.doseLabel!} ($parenthetical)';
  }
}

class _FormEvidenceSources extends StatelessWidget {
  const _FormEvidenceSources({
    required this.level,
    required this.sources,
    required this.onOpen,
  });

  final String level;
  final List<PGFormEvidenceSource> sources;
  final OpenFormEvidenceSource onOpen;

  @override
  Widget build(BuildContext context) {
    final supportLabel = switch (level) {
      'strong' => 'Strong supporting evidence',
      _ => 'Moderate supporting evidence',
    };
    return Container(
      padding: const EdgeInsets.all(V2Spacing.space12),
      decoration: BoxDecoration(
        color: context.v2.surface,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        border: Border.all(color: context.v2.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sources for this form rating',
            style: V2Typography.label(color: context.v2.fg),
          ),
          const SizedBox(height: V2Spacing.space4),
          Text(
            supportLabel,
            style: V2Typography.caption(color: context.v2.fgMuted),
          ),
          const SizedBox(height: V2Spacing.space8),
          for (var index = 0; index < sources.length; index++) ...[
            _FormEvidenceSourceRow(source: sources[index], onOpen: onOpen),
            if (index != sources.length - 1)
              Divider(color: context.v2.outline, height: 1, thickness: 0.4),
          ],
        ],
      ),
    );
  }
}

class _FormEvidenceSourceRow extends StatelessWidget {
  const _FormEvidenceSourceRow({required this.source, required this.onOpen});

  final PGFormEvidenceSource source;
  final OpenFormEvidenceSource onOpen;

  @override
  Widget build(BuildContext context) {
    final sourceLabel = source.pmid == null
        ? source.authority
        : 'PMID ${source.pmid}';
    return Semantics(
      button: true,
      label: 'Open source: ${source.title}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => unawaited(onOpen(source)),
          borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: V2Spacing.space8),
              child: Row(
                children: [
                  Icon(
                    Icons.menu_book_outlined,
                    size: 18,
                    color: context.v2.accent,
                  ),
                  const SizedBox(width: V2Spacing.space8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          source.title,
                          style: V2Typography.bodySm(color: context.v2.fg),
                        ),
                        const SizedBox(height: V2Spacing.space4),
                        Text(
                          sourceLabel,
                          style: V2Typography.caption(
                            color: context.v2.fgMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: V2Spacing.space8),
                  Icon(
                    Icons.open_in_new_rounded,
                    size: 18,
                    color: context.v2.fgMuted,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FactTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _FactTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: V2Spacing.space8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: context.v2.fgMuted),
          const SizedBox(width: V2Spacing.space12),
          Text(
            '$label  ',
            style: V2Typography.caption(color: context.v2.fgMuted),
          ),
          Expanded(
            child: Text(
              value,
              style: V2Typography.bodySm(color: context.v2.fg),
            ),
          ),
        ],
      ),
    );
  }
}

class _Block extends StatefulWidget {
  final Color accent;
  final Color tint;
  final String heading;
  final String body;

  /// Longer text revealed by a "More" toggle. When null the block is a plain
  /// heading + body, exactly as before. Both strings arrive pre-split from the
  /// pipeline — the sheet never decides where a sentence ends.
  final String? expandedBody;

  const _Block({
    required this.accent,
    required this.tint,
    required this.heading,
    required this.body,
    this.expandedBody,
  });

  @override
  State<_Block> createState() => _BlockState();
}

class _BlockState extends State<_Block> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final style = context.v2.tintedLabel(widget.accent, borderAlpha: 0.18);
    // Nothing to reveal when the fuller text is absent or adds nothing.
    final expandable =
        widget.expandedBody != null && widget.expandedBody != widget.body;
    final body = expandable && _expanded ? widget.expandedBody! : widget.body;

    return Container(
      padding: const EdgeInsets.all(V2Spacing.space12),
      decoration: BoxDecoration(
        color: widget.tint,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        border: Border.all(color: style.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.heading,
            style: V2Typography.label(color: style.foreground),
          ),
          const SizedBox(height: V2Spacing.space4),
          Text(body, style: V2Typography.bodySm(color: context.v2.fg)),
          if (expandable) ...[
            const SizedBox(height: V2Spacing.space4),
            Semantics(
              button: true,
              label: _expanded
                  ? 'Show less about ${widget.heading}'
                  : 'Show more about ${widget.heading}',
              onTap: _toggle,
              excludeSemantics: true,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _toggle,
                  borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 44),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _expanded ? 'Less' : 'More',
                        style: V2Typography.bodyMedium(
                          color: context.v2.accent,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _toggle() => setState(() => _expanded = !_expanded);
}

Color _formAccent(V2Palette p, FormQuality q) {
  switch (q) {
    case FormQuality.excellent:
    case FormQuality.good:
      return p.safe;
    case FormQuality.fair:
    case FormQuality.poor:
      // Per Sean: bottom tier is amber, not red. Bioavailability is a
      // form-quality signal, not a safety signal.
      return p.caution;
    case FormQuality.unknown:
      return p.monitor;
  }
}

Color _doseAccent(V2Palette p, DoseCallOut d) {
  switch (d) {
    case DoseCallOut.high:
      return p.avoid;
    case DoseCallOut.low:
      return p.caution;
    case DoseCallOut.notDisclosed:
      return p.monitor;
    case DoseCallOut.withinLimits:
      return p.safe;
  }
}

Color _formTint(V2Palette p, FormQuality q) {
  switch (q) {
    case FormQuality.excellent:
    case FormQuality.good:
      return p.safeTint;
    case FormQuality.fair:
    case FormQuality.poor:
      return p.cautionTint;
    case FormQuality.unknown:
      return p.monitorTint;
  }
}

Color _doseTint(V2Palette p, DoseCallOut d) {
  switch (d) {
    case DoseCallOut.high:
      return p.avoidTint;
    case DoseCallOut.low:
      return p.cautionTint;
    case DoseCallOut.notDisclosed:
      return p.monitorTint;
    case DoseCallOut.withinLimits:
      return p.safeTint;
  }
}
