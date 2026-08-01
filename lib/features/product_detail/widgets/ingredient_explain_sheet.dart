// v2 modal bottom sheet that explains a single active ingredient.

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/core/widgets/pg_modal.dart';
import 'package:pharmaguide/features/product_detail/widgets/ingredient_explain_model.dart';

/// Opens the explain sheet for [ingredient]. Returns when the sheet is
/// dismissed.
Future<void> showIngredientExplainSheet(
  BuildContext context, {
  required Map<String, dynamic> ingredient,
  Map<String, dynamic>? ulEntry,
}) {
  final explain = buildIngredientExplain(
    ingredient: ingredient,
    ulEntry: ulEntry,
  );
  return PGModal.bottomSheet<void>(
    context: context,
    builder: (_) => _Sheet(explain: explain),
  );
}

class _Sheet extends StatelessWidget {
  final IngredientExplain explain;

  const _Sheet({required this.explain});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.46,
      minChildSize: 0.34,
      maxChildSize: 0.85,
      expand: false,
      builder: (_, scrollController) {
        return _SheetBody(explain: explain, scrollController: scrollController);
      },
    );
  }
}

class _SheetBody extends StatelessWidget {
  final IngredientExplain explain;
  final ScrollController scrollController;

  const _SheetBody({required this.explain, required this.scrollController});

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
        if (explain.formHeading != null && explain.formExplanation != null)
          _Block(
            accent: _formAccent(context.v2, explain.formQuality),
            tint: _formTint(context.v2, explain.formQuality),
            heading: explain.formHeading!,
            body: explain.formExplanation!,
          ),
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

class _Block extends StatelessWidget {
  final Color accent;
  final Color tint;
  final String heading;
  final String body;

  const _Block({
    required this.accent,
    required this.tint,
    required this.heading,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final style = context.v2.tintedLabel(accent, borderAlpha: 0.18);
    return Container(
      padding: const EdgeInsets.all(V2Spacing.space12),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        border: Border.all(color: style.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(heading, style: V2Typography.label(color: style.foreground)),
          const SizedBox(height: V2Spacing.space4),
          Text(body, style: V2Typography.bodySm(color: context.v2.fg)),
        ],
      ),
    );
  }
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
