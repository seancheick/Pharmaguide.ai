import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_eyebrow.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/core/widgets/pg_modal.dart';
import 'package:pharmaguide/services/signals/clinical_signal_envelope.dart';
import 'package:pharmaguide/services/signals/stack_signal_aggregator.dart';
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

/// Rows are driven from [orderedSignalsFrom] — the typed clinical-signal
/// aggregation — grouped by consumer disposition (Needs attention = block /
/// review; Good to know = good_to_know; suppress is excluded upstream). Check
/// completeness is a SEPARATE concern (report flags), never mixed in with
/// clinical findings, so "couldn't check" never reads as "we found a concern".
class StackSafetyDetailsSheet extends StatelessWidget {
  const StackSafetyDetailsSheet({super.key, required this.report});

  final StackSafetyReport report;

  @override
  Widget build(BuildContext context) {
    final signals = orderedSignalsFrom(report);
    final needsAttention = signals
        .where(
          (s) =>
              s.consumerDisposition == ConsumerDisposition.block ||
              s.consumerDisposition == ConsumerDisposition.review,
        )
        .toList();
    final goodToKnow = signals
        .where((s) => s.consumerDisposition == ConsumerDisposition.goodToKnow)
        .toList();
    final checkIncomplete =
        report.checksIncomplete || report.coverageIncomplete;

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
              'Review ${signals.length} signals',
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
              child: ListView(
                shrinkWrap: true,
                children: [
                  if (needsAttention.isNotEmpty)
                    ..._section('Needs attention', needsAttention),
                  if (goodToKnow.isNotEmpty)
                    ..._section('Good to know', goodToKnow),
                  if (checkIncomplete) const _CheckStatusNotice(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _section(String heading, List<ClinicalSignal> signals) {
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: V2Spacing.space8),
        child: PGEyebrow(heading, color: V2Colors.fgMuted),
      ),
      for (var i = 0; i < signals.length; i++) ...[
        if (i > 0)
          const Divider(height: V2Spacing.space24, color: V2Colors.outline),
        _SafetySignalRow(
          key: Key('stack-safety-signal-${signals[i].signalId}'),
          signal: signals[i],
        ),
      ],
      const SizedBox(height: V2Spacing.space16),
    ];
  }
}

/// Assessment-completeness notice. NOT a clinical finding — kept separate so an
/// incomplete check can never read as an all-clear, and never displaces or
/// mixes with a known concern.
class _CheckStatusNotice extends StatelessWidget {
  const _CheckStatusNotice();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Check status: some checks could not be completed',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PGEyebrow('Check status', color: V2Colors.fgMuted),
          const SizedBox(height: V2Spacing.space8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.help_outline, color: V2Colors.fgMuted, size: 20),
              const SizedBox(width: V2Spacing.space12),
              Expanded(
                child: Text(
                  'Some checks could not be completed. This is not an all-clear '
                  '— review your stack with your clinician.',
                  style: V2Typography.bodySm(
                    color: V2Colors.fgMuted,
                  ).copyWith(height: 1.35),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SafetySignalRow extends StatelessWidget {
  const _SafetySignalRow({super.key, required this.signal});

  final ClinicalSignal signal;

  @override
  Widget build(BuildContext context) {
    final model = _SignalPresentation.from(signal);
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

/// Row presentation. Text is sourced from the typed payload so it stays BYTE-FOR-
/// BYTE identical to the pre-migration rendering (no clinical copy is regenerated
/// here); severity comes from the envelope's clinical_severity.
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

  static _SignalPresentation from(ClinicalSignal signal) {
    final severity = signal.clinicalSeverity;
    switch (signal.payload) {
      case InteractionPayload(:final result):
        final body = result.management.trim().isNotEmpty
            ? result.management
            : result.mechanism;
        return _SignalPresentation(
          severity: severity,
          title: '${result.agent1Name} x ${result.agent2Name}',
          body: body.trim().isEmpty ? result.evidenceLevel.label : body,
          icon: Icons.warning_amber_rounded,
        );
      case MedicationProfilePayload(:final warning):
        final body = warning.body.trim().isNotEmpty
            ? warning.body
            : warning.management;
        return _SignalPresentation(
          severity: severity,
          title: warning.medicationName,
          body: body.trim().isEmpty ? warning.headline : body,
          icon: Icons.medical_information_outlined,
        );
      case CumulativeExposurePayload(:final status):
        final exceeds = status.tier == NutrientTier.exceedsUl;
        return _SignalPresentation(
          severity: severity,
          title: exceeds
              ? 'Upper limit - ${status.total.displayName}'
              : '${status.total.displayName} is near its upper limit',
          body: exceeds
              ? StackSafetyReport.nutrientUpperLimitSummary(status)
              : '${status.total.displayName} is nearing its upper limit across your stack.',
          icon: Icons.health_and_safety_outlined,
        );
      case MedicationNutrientPayload(:final match):
        // Not in this sheet's data source today (depletions come from a separate
        // provider); reserved for when they are folded into the unified list.
        return _SignalPresentation(
          severity: severity,
          title: '${match.drugDisplayName} - ${match.nutrientName}',
          body: match.clinicalImpact ?? match.mechanism,
          icon: Icons.medical_information_outlined,
        );
    }
  }
}
