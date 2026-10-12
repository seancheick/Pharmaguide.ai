import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/core/components/pg_pill_button.dart';
import 'package:pharmaguide/core/components/pg_segmented_control.dart';
import 'package:pharmaguide/core/components/pg_toast.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/features/ai_share/ai_connections_repository.dart';
import 'package:pharmaguide/features/ai_share/ai_share_providers.dart';
import 'package:pharmaguide/features/stack/widgets/ai_share_scope_switches.dart';
import 'package:pharmaguide/services/crash_reporting_service.dart';
import 'package:pharmaguide/services/sharing/ai_brief_builder.dart';
import 'package:pharmaguide/services/sharing/ai_share_scope.dart';
import 'package:pharmaguide/services/sharing/ai_share_snapshot_client.dart';
import 'package:pharmaguide/services/sharing/clinician_report_document_provider.dart';
import 'package:pharmaguide/services/sharing/report_text.dart';

/// Website page where every assistant connection can be revoked.
const aiConnectionsWebUrl = 'https://pharmaguide.io/account/connections';

/// Consent, preview and share for one connected assistant (ADR-009 S4).
///
/// The payload is the AI brief built on this device for the chosen scope.
/// The text in the preview is the exact text uploaded, so what the user
/// reviews is what the assistant can read. Medications and the health
/// profile stay off until switched on, and findings that would disclose
/// them stay out with them (enforced by [AiBriefBuilder]).
class AiShareConsentScreen extends ConsumerStatefulWidget {
  const AiShareConsentScreen({super.key, required this.connection});

  final AiConnection connection;

  @override
  ConsumerState<AiShareConsentScreen> createState() =>
      _AiShareConsentScreenState();
}

class _AiShareConsentScreenState extends ConsumerState<AiShareConsentScreen> {
  static const _durations = <int>[24, 168, 720];

  AiShareScope _scope = AiShareScope.detailedReport;
  int _durationIndex = 0;
  bool _sharing = false;

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
          'Share with this assistant',
          style: V2Typography.titleSm(color: context.v2.fg),
        ),
      ),
      body: SafeArea(
        child: switch (data) {
          AsyncData(:final value) => _body(context, value),
          AsyncError() => Center(
            child: Padding(
              padding: const EdgeInsets.all(V2Spacing.space24),
              child: Text(
                'The snapshot could not be prepared. Nothing was shared.',
                textAlign: TextAlign.center,
                style: V2Typography.body(color: context.v2.fgMuted),
              ),
            ),
          ),
          _ => Center(
            child: CircularProgressIndicator(color: context.v2.accent),
          ),
        },
      ),
    );
  }

  Widget _body(BuildContext context, ClinicianReportData data) {
    final text = const AiBriefBuilder().build(data, _scope);
    final clientId = widget.connection.clientId;
    return Column(
      children: [
        Expanded(
          // Not a lazy list: the preview is always in the tree, so the text
          // uploaded is the text rendered.
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
                _ConsentCard(
                  clientId: clientId,
                  connectedOn: widget.connection.createdAt,
                  scope: _scope,
                ),
                const SizedBox(height: V2Spacing.space16),
                Text(
                  'Available to the assistant for',
                  style: V2Typography.titleSm(color: context.v2.fg),
                ),
                const SizedBox(height: V2Spacing.space8),
                PGSegmentedControl(
                  segments: const ['24 hours', '7 days', '30 days'],
                  selectedIndex: _durationIndex,
                  onChanged: (i) => setState(() => _durationIndex = i),
                ),
                const SizedBox(height: V2Spacing.space16),
                AiShareScopeSwitches(scope: _scope, onScope: _update),
                const SizedBox(height: V2Spacing.space16),
                Text(
                  'Preview: the exact text the assistant can read',
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
                    key: const Key('ai_share_preview_text'),
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
          child: PGPillButton(
            key: const Key('ai_share_submit'),
            label: _sharing ? 'Sharing…' : 'Share',
            icon: Icons.ios_share_rounded,
            expand: true,
            onPressed: _sharing || _scope.isEmpty
                ? null
                : () => _share(data, text, _scope),
          ),
        ),
      ],
    );
  }

  /// [text] and [scope] come from the same build, so the upload is the
  /// rendered preview and the scope that produced it.
  Future<void> _share(
    ClinicianReportData data,
    String text,
    AiShareScope scope,
  ) async {
    final ttlHours = _durations[_durationIndex];
    setState(() => _sharing = true);
    try {
      final receipt = await ref
          .read(aiShareSnapshotClientProvider)
          .upload(
            connectionId: widget.connection.connectionId,
            scope: scope,
            stackRevision: AiShareSnapshotClient.stackRevisionForScope(
              data.stack,
              scope,
            ),
            ttlHours: ttlHours,
            payload: text,
          );
      try {
        await ref
            .read(aiSharePrefsStoreProvider)
            .recordShare(widget.connection.connectionId, scope, ttlHours);
        ref.invalidate(aiShareConnectionPrefsProvider);
      } on Object catch (error, stackTrace) {
        // The share succeeded; only the device-side record failed, which
        // just leaves "Keep updated" unavailable until the next share.
        CrashReportingService().recordError(
          error,
          stackTrace,
          hint: 'ai_share:record_share_failed',
        );
      }
      if (!mounted) return;
      PGToast.show(
        context,
        'Shared. Available to the assistant until '
        '${formatReportDate(receipt.expiresAt.toLocal())}.',
      );
      unawaited(Navigator.of(context).maybePop(true));
    } on AiShareNotSignedIn {
      _fail('Sign in to share with an assistant.');
    } on Object catch (error, stackTrace) {
      CrashReportingService().recordError(
        error,
        stackTrace,
        hint: 'ai_share:upload_failed',
      );
      _fail('The share did not complete. Try again.');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() => _sharing = false);
    PGToast.show(context, message, variant: PGToastVariant.error);
  }
}

/// S4: destination, categories, the three data locations and how to stop.
class _ConsentCard extends StatelessWidget {
  const _ConsentCard({
    required this.clientId,
    required this.connectedOn,
    required this.scope,
  });

  final String clientId;
  final DateTime connectedOn;
  final AiShareScope scope;

  @override
  Widget build(BuildContext context) {
    final s = scope.normalized;
    final included = <String>[
      if (s.supplementNames) 'supplements',
      if (s.medicationNames) 'medications',
      if (s.profile) 'health profile',
      if (s.findings) 'PharmaGuide findings',
    ];
    final left = <String>[
      if (!s.medicationNames) 'medications',
      if (!s.profile) 'health profile',
    ];
    Widget line(IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(top: V2Spacing.space8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: context.v2.accent),
          const SizedBox(width: V2Spacing.space8),
          Expanded(
            child: Text(text, style: V2Typography.bodySm(color: context.v2.fg)),
          ),
        ],
      ),
    );

    return Container(
      key: const Key('ai_share_consent_card'),
      width: double.infinity,
      padding: const EdgeInsets.all(V2Spacing.space16),
      decoration: BoxDecoration(
        color: context.v2.accentTint,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sharing with',
            style: V2Typography.caption(color: context.v2.fgMuted),
          ),
          Text(clientId, style: V2Typography.titleSm(color: context.v2.fg)),
          Text(
            'Connected ${formatReportDate(connectedOn.toLocal())}',
            style: V2Typography.caption(color: context.v2.fgMuted),
          ),
          line(
            Icons.checklist_rounded,
            included.isEmpty
                ? 'Nothing is switched on yet.'
                : 'Included: ${included.join(', ')}.'
                      '${left.isEmpty ? '' : ' Not included: ${left.join(', ')}.'}',
          ),
          line(
            Icons.cloud_outlined,
            'PharmaGuide stores this snapshot encrypted until it expires or '
            'you disconnect. Our server can read it while the share is '
            'live; it is not end-to-end encrypted.',
          ),
          line(
            Icons.forum_outlined,
            'The assistant receives it when it asks, and may keep it in your '
            'chat history. Disconnecting cannot erase what the assistant '
            'already kept.',
          ),
          line(
            Icons.link_off_rounded,
            'Stop anytime: Settings, then Connected AI assistants, then '
            'Disconnect, or at pharmaguide.io/account/connections.',
          ),
        ],
      ),
    );
  }
}
