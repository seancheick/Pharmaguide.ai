import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/core/components/pg_pill_button.dart';
import 'package:pharmaguide/core/components/pg_segmented_control.dart';
import 'package:pharmaguide/core/components/pg_settings_tile.dart';
import 'package:pharmaguide/core/components/pg_toast.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/services/sharing/ai_brief_builder.dart';
import 'package:pharmaguide/services/sharing/ai_share_scope.dart';
import 'package:pharmaguide/services/sharing/clinician_report_document_provider.dart';
import 'package:pharmaguide/services/sharing/share_service.dart';

/// Preview of the text brief a user pastes into an AI assistant.
///
/// Everything is composed on this device from [clinicianReportDataProvider].
/// The user sees the exact text before it leaves, chooses what it includes,
/// and sensitive categories stay off until switched on. Copy and Share are
/// pass-throughs: the app never sends the brief anywhere itself.
class AiBriefPreviewScreen extends ConsumerStatefulWidget {
  const AiBriefPreviewScreen({super.key, this.shareService});

  final ShareService? shareService;

  @override
  ConsumerState<AiBriefPreviewScreen> createState() =>
      _AiBriefPreviewScreenState();
}

class _AiBriefPreviewScreenState extends ConsumerState<AiBriefPreviewScreen> {
  static const _presets = <AiShareScope>[
    AiShareScope.simpleList,
    AiShareScope.detailedReport,
  ];

  AiShareScope _scope = AiShareScope.detailedReport;
  int _preset = 1;

  void _applyPreset(int index) {
    setState(() {
      _preset = index;
      // A preset resets the derived switches but keeps the user's explicit
      // choice about medications and profile: switching presentation must
      // never silently widen what is shared.
      _scope = _presets[index].copyWith(
        medicationNames: _scope.medicationNames,
        medicationSchedule: _scope.medicationSchedule,
        profile: _scope.profile,
      );
    });
  }

  void _update(AiShareScope Function(AiShareScope) change) {
    setState(() => _scope = change(_scope).normalized);
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(clinicianReportDataProvider);

    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Share with an AI assistant',
          style: V2Typography.titleSm(color: context.v2.fg),
        ),
      ),
      body: SafeArea(
        child: switch (data) {
          AsyncData(:final value) => _Preview(
            text: const AiBriefBuilder().build(value, _scope),
            scope: _scope,
            preset: _preset,
            onPreset: _applyPreset,
            onScope: _update,
            onCopy: _copy,
            onShare: _share,
          ),
          AsyncError(:final error) => _BuildError(
            onRetry: () => ref.invalidate(clinicianReportDataProvider),
            error: error,
          ),
          _ => const _Loading(),
        },
      ),
    );
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    PGToast.show(context, 'Copied. Paste it into your assistant.');
  }

  Future<void> _share(String text) async {
    try {
      await (widget.shareService ?? ShareService()).shareAiBrief(text);
    } on Object {
      if (!mounted) return;
      PGToast.show(
        context,
        'Could not open the share sheet. Try again.',
        variant: PGToastVariant.error,
      );
    }
  }
}

class _Preview extends StatelessWidget {
  const _Preview({
    required this.text,
    required this.scope,
    required this.preset,
    required this.onPreset,
    required this.onScope,
    required this.onCopy,
    required this.onShare,
  });

  final String text;
  final AiShareScope scope;
  final int preset;
  final ValueChanged<int> onPreset;
  final void Function(AiShareScope Function(AiShareScope)) onScope;
  final Future<void> Function(String text) onCopy;
  final Future<void> Function(String text) onShare;

  @override
  Widget build(BuildContext context) {
    final detailed = preset == 1;
    return Column(
      children: [
        Expanded(
          // Not a lazy list: the preview must be in the tree whenever the
          // screen is, so what the user shares is always what was rendered.
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              V2Spacing.space24,
              V2Spacing.space12,
              V2Spacing.space24,
              V2Spacing.space16,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(V2Spacing.space16),
                  decoration: BoxDecoration(
                    color: context.v2.accentTint,
                    borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.lock_outline_rounded,
                        color: context.v2.accent,
                        size: 20,
                      ),
                      const SizedBox(width: V2Spacing.space12),
                      Expanded(
                        child: Text(
                          'This text goes to whichever AI assistant you paste '
                          'it into, and that assistant keeps it in your chat. '
                          'Medications and your health profile stay out until '
                          'you switch them on. Review the text before sharing.',
                          style: V2Typography.bodySm(color: context.v2.fg),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: V2Spacing.space16),
                PGSegmentedControl(
                  segments: const ['Simple list', 'Detailed report'],
                  selectedIndex: preset,
                  onChanged: onPreset,
                ),
                const SizedBox(height: V2Spacing.space16),
                PGSettingsGroup(
                  eyebrow: 'Include',
                  children: [
                    if (detailed)
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
                      icon: Icons.edit_calendar_outlined,
                      title: 'Supplement dose as you entered it',
                      caption: 'Free text, not verified against the label.',
                      trailing: Switch.adaptive(
                        value: scope.supplementSchedule,
                        onChanged: (v) =>
                            onScope((s) => s.copyWith(supplementSchedule: v)),
                      ),
                    ),
                    PGSettingsTile(
                      icon: Icons.medication_outlined,
                      title: 'Medications',
                      caption: 'Names. Findings that involve them come along.',
                      trailing: Switch.adaptive(
                        value: scope.medicationNames,
                        onChanged: (v) =>
                            onScope((s) => s.copyWith(medicationNames: v)),
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
                            ? (v) => onScope(
                                (s) => s.copyWith(medicationSchedule: v),
                              )
                            : null,
                      ),
                    ),
                    PGSettingsTile(
                      icon: Icons.person_outline_rounded,
                      title: 'Health profile',
                      caption:
                          'Age, sex, conditions, pregnancy, allergies, goals.',
                      trailing: Switch.adaptive(
                        value: scope.profile,
                        onChanged: (v) =>
                            onScope((s) => s.copyWith(profile: v)),
                      ),
                    ),
                    if (detailed)
                      PGSettingsTile(
                        icon: Icons.fact_check_outlined,
                        title: 'PharmaGuide findings',
                        caption: 'With severity, evidence level and sources.',
                        trailing: Switch.adaptive(
                          value: scope.findings,
                          onChanged: (v) =>
                              onScope((s) => s.copyWith(findings: v)),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: V2Spacing.space16),
                Text(
                  'Preview',
                  style: V2Typography.titleSm(color: context.v2.fg),
                ),
                const SizedBox(height: V2Spacing.space8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(V2Spacing.space16),
                  decoration: BoxDecoration(
                    color: context.v2.surface,
                    borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
                    border: Border.all(color: context.v2.outline),
                  ),
                  child: SelectableText(
                    text,
                    key: const Key('ai_brief_preview_text'),
                    style: V2Typography.bodySm(color: context.v2.fg),
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            V2Spacing.space24,
            V2Spacing.space8,
            V2Spacing.space24,
            V2Spacing.space16,
          ),
          child: Row(
            children: [
              Expanded(
                child: PGPillButton(
                  label: 'Copy',
                  icon: Icons.copy_rounded,
                  variant: PGPillVariant.secondary,
                  expand: true,
                  onPressed: () => onCopy(text),
                ),
              ),
              const SizedBox(width: V2Spacing.space12),
              Expanded(
                child: PGPillButton(
                  label: 'Share',
                  icon: Icons.ios_share_rounded,
                  expand: true,
                  onPressed: () => onShare(text),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: context.v2.accent),
          const SizedBox(height: V2Spacing.space16),
          Text(
            'Preparing your brief on this device…',
            style: V2Typography.body(color: context.v2.fgMuted),
          ),
        ],
      ),
    );
  }
}

class _BuildError extends StatelessWidget {
  const _BuildError({required this.onRetry, required this.error});

  final VoidCallback onRetry;
  final Object error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(V2Spacing.space24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              color: context.v2.contraindicated,
              size: 36,
            ),
            const SizedBox(height: V2Spacing.space16),
            Text(
              'The brief could not be prepared.',
              textAlign: TextAlign.center,
              style: V2Typography.titleSm(color: context.v2.fg),
            ),
            const SizedBox(height: V2Spacing.space8),
            Text(
              'No partial brief was created. Try again in a moment.',
              textAlign: TextAlign.center,
              style: V2Typography.body(color: context.v2.fgMuted),
            ),
            const SizedBox(height: V2Spacing.space24),
            PGPillButton(
              label: 'Try again',
              icon: Icons.refresh_rounded,
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}
