import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_settings_tile.dart';
import 'package:pharmaguide/services/sharing/ai_share_scope.dart';

/// The "Include" switches for any AI-assistant share (the pasted brief and
/// the consented connector snapshot). One widget so both surfaces describe
/// and gate the same categories the same way.
class AiShareScopeSwitches extends StatelessWidget {
  const AiShareScopeSwitches({
    super.key,
    required this.scope,
    required this.onScope,
    this.showDetailedSwitches = true,
  });

  final AiShareScope scope;
  final void Function(AiShareScope Function(AiShareScope)) onScope;

  /// Label amounts and findings switches; hidden for the simple list preset.
  final bool showDetailedSwitches;

  @override
  Widget build(BuildContext context) {
    return PGSettingsGroup(
      eyebrow: 'Include',
      children: [
        if (showDetailedSwitches)
          PGSettingsTile(
            icon: Icons.scale_outlined,
            title: 'Supplement label amounts',
            caption: 'Verified amounts as nutrient totals.',
            trailing: Switch.adaptive(
              value: scope.supplementAmounts,
              onChanged: (v) =>
                  onScope((s) => s.copyWith(supplementAmounts: v)),
            ),
          ),
        PGSettingsTile(
          icon: Icons.medication_outlined,
          title: 'Medications',
          caption: 'Names. Findings that involve them come along.',
          trailing: Switch.adaptive(
            value: scope.medicationNames,
            onChanged: (v) => onScope((s) => s.copyWith(medicationNames: v)),
          ),
        ),
        PGSettingsTile(
          icon: Icons.schedule_outlined,
          title: 'Medication dose and frequency',
          caption: scope.medicationNames
              ? 'As you entered them.'
              : 'Switch on Medications first.',
          trailing: Switch.adaptive(
            value: scope.medicationSchedule,
            onChanged: scope.medicationNames
                ? (v) => onScope((s) => s.copyWith(medicationSchedule: v))
                : null,
          ),
        ),
        PGSettingsTile(
          icon: Icons.person_outline_rounded,
          title: 'Health profile',
          caption: 'Age, sex, conditions, pregnancy, allergies, goals.',
          trailing: Switch.adaptive(
            value: scope.profile,
            onChanged: (v) => onScope((s) => s.copyWith(profile: v)),
          ),
        ),
        if (showDetailedSwitches)
          PGSettingsTile(
            icon: Icons.fact_check_outlined,
            title: 'PharmaGuide findings',
            caption: 'With severity, evidence level and sources.',
            trailing: Switch.adaptive(
              value: scope.findings,
              onChanged: (v) => onScope((s) => s.copyWith(findings: v)),
            ),
          ),
      ],
    );
  }
}
