import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_eyebrow.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/interaction_result.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/core/widgets/pg_modal.dart';
import 'package:pharmaguide/services/stack/medication_profile_gate_evaluator.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';
import 'package:pharmaguide/services/stack/stack_safety_report.dart';

/// Opens the unified stack-safety review. Timing stays in its own sheet,
/// because timing guidance is optimization advice rather than a safety signal.
Future<void> showStackSafetyDetailsSheet(
  BuildContext context,
  StackSafetyReport report,
) {
  return PGModal.bottomSheet<void>(
    context: context,
    builder: (_) => StackSafetyDetailsSheet(report: report),
  );
}

/// Every row is driven directly from [StackSafetyReport.orderedWarnings], so
/// the sheet and its triggering banner cannot disagree on signal count.
class StackSafetyDetailsSheet extends StatelessWidget {
  const StackSafetyDetailsSheet({super.key, required this.report});

  final StackSafetyReport report;

  @override
  Widget build(BuildContext context) {
    final warnings = report.orderedWarnings;
    return Semantics(
      label: 'Stack safety signals',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          V2Spacing.space24,
          V2Spacing.space8,
          V2Spacing.space24,
          V2Spacing.space24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PGEyebrow(
              'Review ${warnings.length} signals',
              color: V2Colors.caution,
            ),
            const SizedBox(height: V2Spacing.space8),
            Text(
              'Stack safety',
              style: V2Typography.titleSm(color: V2Colors.fg),
            ),
            const SizedBox(height: V2Spacing.space4),
            Text(
              'Review supplement totals and interactions found in your stack.',
              style: V2Typography.bodySm(color: V2Colors.fgMuted),
            ),
            const SizedBox(height: V2Spacing.space16),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: warnings.length,
                separatorBuilder: (_, __) => const Divider(
                  height: V2Spacing.space24,
                  color: V2Colors.outline,
                ),
                itemBuilder: (context, index) => _SafetySignalRow(
                  key: Key('stack-safety-signal-$index'),
                  warning: warnings[index],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SafetySignalRow extends StatelessWidget {
  const _SafetySignalRow({super.key, required this.warning});

  final Object warning;

  @override
  Widget build(BuildContext context) {
    final model = _SignalPresentation.from(warning);
    return Semantics(
      label: '${model.severity.label}: ${model.title}. ${model.body}',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(model.icon, color: _colorFor(model.severity), size: 20),
          const SizedBox(width: V2Spacing.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  model.title,
                  style: V2Typography.label(color: V2Colors.fg),
                ),
                const SizedBox(height: V2Spacing.space4),
                Text(
                  model.body,
                  style: V2Typography.bodySm(
                    color: V2Colors.fgMuted,
                  ).copyWith(height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Color _colorFor(Severity severity) {
    switch (severity) {
      case Severity.contraindicated:
      case Severity.avoid:
        return V2Colors.contraindicated;
      case Severity.caution:
      case Severity.monitor:
        return V2Colors.caution;
      case Severity.informational:
        return V2Colors.accent;
      case Severity.safe:
        return V2Colors.safe;
    }
  }
}

class _SignalPresentation {
  const _SignalPresentation({
    required this.severity,
    required this.title,
    required this.body,
    required this.icon,
  });

  final Severity severity;
  final String title;
  final String body;
  final IconData icon;

  static _SignalPresentation from(Object warning) {
    if (warning is InteractionResult) {
      final body = warning.management.trim().isNotEmpty
          ? warning.management
          : warning.mechanism;
      return _SignalPresentation(
        severity: warning.effectiveSeverity,
        title: '${warning.agent1Name} x ${warning.agent2Name}',
        body: body.trim().isEmpty ? warning.evidenceLevel.label : body,
        icon: Icons.warning_amber_rounded,
      );
    }
    if (warning is MedicationProfileWarning) {
      final body = warning.body.trim().isNotEmpty
          ? warning.body
          : warning.management;
      return _SignalPresentation(
        severity: warning.severity,
        title: warning.medicationName,
        body: body.trim().isEmpty ? warning.headline : body,
        icon: Icons.medical_information_outlined,
      );
    }
    if (warning is NutrientStatus) {
      final exceeds = warning.tier == NutrientTier.exceedsUl;
      return _SignalPresentation(
        severity: StackSafetyReport.severityForNutrient(warning),
        title: exceeds
            ? 'Upper limit - ${warning.total.displayName}'
            : '${warning.total.displayName} is near its upper limit',
        body: exceeds
            ? StackSafetyReport.nutrientUpperLimitSummary(warning)
            : '${warning.total.displayName} is nearing its upper limit across your stack.',
        icon: Icons.health_and_safety_outlined,
      );
    }
    return const _SignalPresentation(
      severity: Severity.caution,
      title: 'Safety signal',
      body: 'Review this item in your stack.',
      icon: Icons.warning_amber_rounded,
    );
  }
}
