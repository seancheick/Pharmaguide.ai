// Material 3 modal bottom sheet that explains a single ingredient.
//
// Sprint: docs/sprints/product_detail_page_sprint.md — T4C.
//
// Opened by tapping anywhere on the active-ingredient row (or either
// of its chips). Light, scrollable, drag-handle native, draggable to
// 85% height — the future-data section at the bottom is a placeholder
// for upcoming additions (interaction context, evidence excerpts).

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/features/product_detail/widgets/ingredient_explain_model.dart';

/// Opens the explain sheet for [ingredient]. Returns when the sheet is
/// dismissed. Uses M3 defaults: drag handle, scroll control,
/// surface-tinted background, safe-area honored.
Future<void> showIngredientExplainSheet(
  BuildContext context, {
  required Map<String, dynamic> ingredient,
  Map<String, dynamic>? ulEntry,
}) {
  final explain = buildIngredientExplain(
    ingredient: ingredient,
    ulEntry: ulEntry,
  );
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
    builder: (_) => _Sheet(explain: explain),
  );
}

class _Sheet extends StatelessWidget {
  final IngredientExplain explain;

  const _Sheet({required this.explain});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.4,
      maxChildSize: 0.85,
      expand: false,
      builder: (_, scrollController) {
        return _SheetBody(
          explain: explain,
          scrollController: scrollController,
        );
      },
    );
  }
}

class _SheetBody extends StatelessWidget {
  final IngredientExplain explain;
  final ScrollController scrollController;

  const _SheetBody({
    required this.explain,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(
        AppTheme.space20,
        AppTheme.space8,
        AppTheme.space20,
        AppTheme.space24,
      ),
      children: [
        // Header — ingredient display name.
        Text(
          explain.title,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: AppTheme.space12),
        // Quick facts row.
        if (explain.formName != null)
          _FactTile(
            icon: Icons.science_outlined,
            label: 'Form',
            value: _capitalize(explain.formName!),
          ),
        if (explain.doseLabel != null)
          _FactTile(
            icon: Icons.straighten_rounded,
            label: 'Dose',
            value: explain.doseLabel!,
          ),
        if (explain.evidenceLabel != null)
          _FactTile(
            icon: Icons.science_outlined,
            label: 'Evidence',
            value: explain.evidenceLabel!,
          ),
        const SizedBox(height: AppTheme.space16),
        Divider(
          height: 1,
          thickness: 0.6,
          color: scheme.outlineVariant.withValues(alpha: 0.5),
        ),
        const SizedBox(height: AppTheme.space16),
        // Form quality block.
        _Block(
          accent: _formAccent(explain.formQuality),
          heading: formBlockHeading(explain.formQuality),
          body: explain.formExplanation,
        ),
        // Dose call-out block (when relevant).
        if (explain.doseExplanation.isNotEmpty) ...[
          const SizedBox(height: AppTheme.space12),
          _Block(
            accent: _doseAccent(explain.doseCallOut),
            heading: doseBlockHeading(explain.doseCallOut),
            body: explain.doseExplanation,
          ),
        ],
        const SizedBox(height: AppTheme.space24),
        // Footer disclaimer.
        Text(
          'Educational use only — not medical advice.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }

  static String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.space8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: AppTheme.space12),
          Text(
            '$label  ',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Block extends StatelessWidget {
  final Color accent;
  final String heading;
  final String body;

  const _Block({
    required this.accent,
    required this.heading,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppTheme.space12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            heading,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurface,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

Color _formAccent(FormQuality q) {
  switch (q) {
    case FormQuality.excellent:
      return AppTheme.severitySafe;
    case FormQuality.good:
      return AppTheme.scoreGood;
    case FormQuality.fair:
      return AppTheme.severityCaution;
    case FormQuality.poor:
      // Per Sean: bottom tier is amber, not red. Bioavailability is a
      // form-quality signal, not a safety signal.
      return AppTheme.severityCaution;
    case FormQuality.unknown:
      return AppTheme.insufficientData;
  }
}

Color _doseAccent(DoseCallOut d) {
  switch (d) {
    case DoseCallOut.high:
      return AppTheme.severityAvoid; // Red — actual safety signal.
    case DoseCallOut.low:
      return AppTheme.severityCaution;
    case DoseCallOut.notDisclosed:
      return AppTheme.insufficientData;
    case DoseCallOut.withinLimits:
      return AppTheme.severitySafe;
  }
}
