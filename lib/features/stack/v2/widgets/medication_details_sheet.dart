// MedicationDetailsSheet — the single consumer presentation of a saved
// medication entry. Opened from the Stack tab row; every surface that wants
// to explain a medication entry goes through [showMedicationDetailsSheet] so
// the copy and state logic cannot fork.
//
// Design constraints (2026-08-08 redesign):
//   - The identity match keeps its FIVE states. The four non-complete states
//     hedge ("checks may be incomplete") and stay caution-toned — they are the
//     user-visible face of the identity guard, and collapsing them into a
//     binary "identified" would hide real coverage gaps.
//   - The complete state is NEUTRAL (fgMuted), not safe-green: it confirms
//     system readiness, not medication safety.
//   - RxNorm concepts and group counts live under a collapsed "Technical
//     details" toggle. They keep their audit value without dominating the
//     sheet.
//   - No medication education is rendered unless it ships as reviewed
//     reference content. Do NOT add a runtime lookup here: which medication a
//     user takes must never leave the device just to explain what it is.
//   - [reminderLabel] is computed by the caller, which already applies the
//     notification-deliverability rule — this sheet must not re-derive it.

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_eyebrow.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/core/widgets/pg_modal.dart';
import 'package:pharmaguide/features/stack/providers/medication_identity_providers.dart';
import 'package:pharmaguide/services/medications/medication_identity_status.dart';

/// Opens the medication details sheet. [onEditTracking] is invoked AFTER the
/// sheet closes itself, so the caller can open the shared tracking editor on
/// its own (still-mounted) context.
Future<void> showMedicationDetailsSheet(
  BuildContext context, {
  required String name,
  String? dosage,
  String? frequency,
  String? reminderLabel,
  MedicationIdentitySnapshot? identity,
  MedicationIdentityAssessment? assessment,
  VoidCallback? onEditTracking,
}) {
  return PGModal.bottomSheet<void>(
    context: context,
    builder: (_) => MedicationDetailsSheet(
      name: name,
      dosage: dosage,
      frequency: frequency,
      reminderLabel: reminderLabel,
      identity: identity,
      assessment: assessment,
      onEditTracking: onEditTracking,
    ),
  );
}

class MedicationDetailsSheet extends StatelessWidget {
  const MedicationDetailsSheet({
    super.key,
    required this.name,
    this.dosage,
    this.frequency,
    this.reminderLabel,
    this.identity,
    this.assessment,
    this.onEditTracking,
  });

  final String name;
  final String? dosage;
  final String? frequency;

  /// Pre-formatted reminder line ("Daily reminder at 8:00 AM", or the
  /// notifications-off hedge). Computed by the caller — see header.
  final String? reminderLabel;
  final MedicationIdentitySnapshot? identity;
  final MedicationIdentityAssessment? assessment;

  /// When provided, "Your details" gains an Add/Edit action that closes the
  /// sheet and hands control back to the caller's tracking editor.
  final VoidCallback? onEditTracking;

  @override
  Widget build(BuildContext context) {
    final details = [dosage, frequency, reminderLabel]
        .whereType<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    final technicalLines = _identityLines(identity, assessment);

    return Semantics(
      label: 'Medication details for $name',
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
            PGEyebrow('Medication details', color: context.v2.fgMuted),
            const SizedBox(height: V2Spacing.space8),
            Text(name, style: V2Typography.title(color: context.v2.fg)),
            const SizedBox(height: V2Spacing.space16),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  _MedicationMatchStatus(name: name, assessment: assessment),
                  Divider(height: V2Spacing.space32, color: context.v2.outline),
                  PGEyebrow('Your details', color: context.v2.fgMuted),
                  const SizedBox(height: V2Spacing.space4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          details.isEmpty
                              ? 'No dose or schedule saved.'
                              : details.join(' · '),
                          style: V2Typography.bodyMedium(color: context.v2.fg),
                        ),
                      ),
                      if (onEditTracking != null)
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            onEditTracking!();
                          },
                          child: Text(details.isEmpty ? 'Add' : 'Edit'),
                        ),
                    ],
                  ),
                  if (technicalLines.isNotEmpty) ...[
                    Divider(
                      height: V2Spacing.space32,
                      color: context.v2.outline,
                    ),
                    _TechnicalDetailsSection(lines: technicalLines),
                  ],
                  Divider(height: V2Spacing.space32, color: context.v2.outline),
                  Text(
                    "PharmaGuide doesn't provide prescribing, side-effect, "
                    'or dosing advice.',
                    style: V2Typography.caption(color: context.v2.fgMuted),
                  ),
                  const SizedBox(height: V2Spacing.space12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.lock_outline_rounded,
                        size: 16,
                        color: context.v2.fgMuted,
                      ),
                      const SizedBox(width: V2Spacing.space8),
                      Expanded(
                        child: Text(
                          'Saved only on this device.',
                          style: V2Typography.caption(
                            color: context.v2.fgMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static List<String> _identityLines(
    MedicationIdentitySnapshot? identity,
    MedicationIdentityAssessment? assessment,
  ) {
    if (identity == null) return const [];
    return [
      if (identity.rxcui != null) 'RxNorm concept ${identity.rxcui}',
      if (identity.genericRxcui != null)
        'Generic ingredient concept ${identity.genericRxcui}',
      if (identity.ingredientRxcuis.isNotEmpty)
        '${identity.ingredientRxcuis.length} ingredient '
            '${identity.ingredientRxcuis.length == 1 ? 'concept' : 'concepts'}',
      if (identity.drugClassIds.isNotEmpty)
        '${identity.drugClassIds.length} saved medication-group '
            '${identity.drugClassIds.length == 1 ? 'identifier' : 'identifiers'}',
      if (assessment != null && assessment.curatedClassIds.isNotEmpty)
        '${assessment.curatedClassIds.length} reviewed interaction '
            '${assessment.curatedClassIds.length == 1 ? 'group' : 'groups'}',
    ];
  }
}

class _MedicationMatchStatus extends StatelessWidget {
  const _MedicationMatchStatus({required this.name, required this.assessment});

  final String name;
  final MedicationIdentityAssessment? assessment;

  @override
  Widget build(BuildContext context) {
    final status = assessment?.status ?? MedicationIdentityStatus.unresolved;
    final (label, body, icon, color) = switch (status) {
      MedicationIdentityStatus.complete => (
        'Ready for supplement checks',
        'PharmaGuide can include $name in reviewed supplement and nutrient '
            'checks.',
        Icons.verified_outlined,
        context.v2.fgMuted,
      ),
      MedicationIdentityStatus.partial => (
        'Partially matched',
        'Some reviewed checks are available, but other medication-specific '
            'checks may be unavailable.',
        Icons.info_outline_rounded,
        context.v2.caution,
      ),
      MedicationIdentityStatus.classOnly => (
        'Medication-group matching available',
        'A reviewed medication-group match is available; product-specific '
            'checks may be limited.',
        Icons.info_outline_rounded,
        context.v2.caution,
      ),
      MedicationIdentityStatus.exactOnly => (
        'Identity saved; coverage limited',
        'The RxNorm identity is saved, but no reviewed direct or medication-'
            'group coverage was found. Interaction checks may be incomplete.',
        Icons.info_outline_rounded,
        context.v2.caution,
      ),
      MedicationIdentityStatus.unresolved => (
        'Matching incomplete',
        'Reviewed interaction coverage could not be confirmed for this entry, '
            'so medication checks may be incomplete.',
        Icons.error_outline_rounded,
        context.v2.caution,
      ),
    };

    return Semantics(
      label: '$label. $body',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: V2Spacing.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PGEyebrow(label, color: color),
                const SizedBox(height: V2Spacing.space4),
                Text(
                  body,
                  style: V2Typography.bodySm(color: context.v2.fgMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Collapsed-by-default holder for RxNorm concepts and group counts. A plain
/// toggle rather than ExpansionTile so no ListTile theme defaults leak into
/// the sheet in either appearance.
class _TechnicalDetailsSection extends StatefulWidget {
  const _TechnicalDetailsSection({required this.lines});

  final List<String> lines;

  @override
  State<_TechnicalDetailsSection> createState() =>
      _TechnicalDetailsSectionState();
}

class _TechnicalDetailsSectionState extends State<_TechnicalDetailsSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: V2Spacing.space4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Technical details',
                    style: V2Typography.bodySm(color: context.v2.fg),
                  ),
                ),
                Icon(
                  _expanded
                      ? Icons.expand_less_rounded
                      : Icons.chevron_right_rounded,
                  size: 18,
                  color: context.v2.fgMuted,
                ),
              ],
            ),
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: V2Spacing.space8),
          for (final line in widget.lines) _TechnicalDetailLine(text: line),
        ],
      ],
    );
  }
}

class _TechnicalDetailLine extends StatelessWidget {
  const _TechnicalDetailLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: V2Spacing.space8),
      child: Row(
        children: [
          Icon(
            Icons.check_circle_outline_rounded,
            size: 16,
            color: context.v2.fgMuted,
          ),
          const SizedBox(width: V2Spacing.space8),
          Expanded(
            child: Text(text, style: V2Typography.bodySm(color: context.v2.fg)),
          ),
        ],
      ),
    );
  }
}
