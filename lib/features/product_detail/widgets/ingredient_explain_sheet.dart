// v2 modal bottom sheet that explains a single active ingredient.

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
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
    backgroundColor: V2Colors.surface,
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
        Text(explain.title, style: V2Typography.titleSm(color: V2Colors.fg)),
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
        const Divider(color: V2Colors.outline, height: 1, thickness: 0.4),
        const SizedBox(height: V2Spacing.space16),
        _Block(
          accent: _formAccent(explain.formQuality),
          tint: _formTint(explain.formQuality),
          heading: explain.formHeading,
          body: explain.formExplanation,
        ),
        if (explain.doseExplanation.isNotEmpty) ...[
          const SizedBox(height: V2Spacing.space12),
          _Block(
            accent: _doseAccent(explain.doseCallOut),
            tint: _doseTint(explain.doseCallOut),
            heading: doseBlockHeading(explain.doseCallOut),
            body: explain.doseExplanation,
          ),
        ],
        const SizedBox(height: V2Spacing.space24),
        Text(
          'Educational use only — not medical advice.',
          style: V2Typography.caption(color: V2Colors.fgSubtle),
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
          Icon(icon, size: 18, color: V2Colors.fgMuted),
          const SizedBox(width: V2Spacing.space12),
          Text(
            '$label  ',
            style: V2Typography.caption(color: V2Colors.fgMuted),
          ),
          Expanded(
            child: Text(value, style: V2Typography.bodySm(color: V2Colors.fg)),
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
    return Container(
      padding: const EdgeInsets.all(V2Spacing.space12),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(heading, style: V2Typography.label(color: accent)),
          const SizedBox(height: V2Spacing.space4),
          Text(body, style: V2Typography.bodySm(color: V2Colors.fg)),
        ],
      ),
    );
  }
}

Color _formAccent(FormQuality q) {
  switch (q) {
    case FormQuality.excellent:
    case FormQuality.good:
      return V2Colors.safe;
    case FormQuality.fair:
    case FormQuality.poor:
      // Per Sean: bottom tier is amber, not red. Bioavailability is a
      // form-quality signal, not a safety signal.
      return V2Colors.caution;
    case FormQuality.unknown:
      return V2Colors.monitor;
  }
}

Color _doseAccent(DoseCallOut d) {
  switch (d) {
    case DoseCallOut.high:
      return V2Colors.avoid;
    case DoseCallOut.low:
      return V2Colors.caution;
    case DoseCallOut.notDisclosed:
      return V2Colors.monitor;
    case DoseCallOut.withinLimits:
      return V2Colors.safe;
  }
}

Color _formTint(FormQuality q) {
  switch (q) {
    case FormQuality.excellent:
    case FormQuality.good:
      return V2Colors.safeTint;
    case FormQuality.fair:
    case FormQuality.poor:
      return V2Colors.cautionTint;
    case FormQuality.unknown:
      return V2Colors.monitorTint;
  }
}

Color _doseTint(DoseCallOut d) {
  switch (d) {
    case DoseCallOut.high:
      return V2Colors.avoidTint;
    case DoseCallOut.low:
      return V2Colors.cautionTint;
    case DoseCallOut.notDisclosed:
      return V2Colors.monitorTint;
    case DoseCallOut.withinLimits:
      return V2Colors.safeTint;
  }
}
