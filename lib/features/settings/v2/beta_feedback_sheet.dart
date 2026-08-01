import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_goal_chip.dart';
import 'package:pharmaguide/core/components/pg_pill_button.dart';
import 'package:pharmaguide/core/components/pg_toast.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/core/widgets/pg_modal.dart';
import 'package:pharmaguide/services/crash_reporting_service.dart';

const kSupportEmail = 'support@pharmaguide.io';

/// Opens the beta-feedback bottom sheet.
///
/// Structured feedback (category + impact) goes to Sentry via
/// [CrashReportingService.captureBetaFeedback]; prose is routed to the
/// support mailto through [openExternal] so health details (if any) land in
/// the user's own inbox rather than a third-party processor. No free-text
/// field is shown here — that is the whole point.
Future<void> showBetaFeedbackSheet(
  BuildContext context, {
  required Future<bool> Function(Uri uri) openExternal,
}) {
  return PGModal.bottomSheet<void>(
    context: context,
    builder: (_) => BetaFeedbackSheet(openExternal: openExternal),
  );
}

typedef SubmitBetaFeedback =
    Future<PgFeedbackSubmissionResult> Function({
      required PgFeedbackCategory category,
      required PgFeedbackImpact impact,
    });

@visibleForTesting
class BetaFeedbackSheet extends StatefulWidget {
  final Future<bool> Function(Uri uri) openExternal;
  final SubmitBetaFeedback submitFeedback;

  BetaFeedbackSheet({
    super.key,
    required this.openExternal,
    SubmitBetaFeedback? submitFeedback,
  }) : submitFeedback =
           submitFeedback ?? CrashReportingService().captureBetaFeedback;

  @override
  State<BetaFeedbackSheet> createState() => _BetaFeedbackSheetState();
}

class _BetaFeedbackSheetState extends State<BetaFeedbackSheet> {
  PgFeedbackCategory? _category;
  PgFeedbackImpact? _impact;
  bool _sending = false;

  bool get _canSend => _category != null && _impact != null && !_sending;

  Future<void> _send() async {
    final category = _category;
    final impact = _impact;
    if (category == null || impact == null || _sending) return;

    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final result = await widget.submitFeedback(
      category: category,
      impact: impact,
    );
    if (!mounted) return;
    if (result == PgFeedbackSubmissionResult.sent) {
      navigator.pop();
      PGToast.showWith(
        messenger,
        'Thanks — your feedback was sent.',
        variant: PGToastVariant.success,
      );
      return;
    }

    setState(() => _sending = false);
    final message = switch (result) {
      PgFeedbackSubmissionResult.disabled =>
        'Feedback is not enabled in this build. Add detail by email instead.',
      PgFeedbackSubmissionResult.failed =>
        'Could not send feedback. Add detail by email instead.',
      PgFeedbackSubmissionResult.sent => 'Thanks — your feedback was sent.',
    };
    PGToast.showWith(messenger, message, variant: PGToastVariant.error);
  }

  Future<void> _emailDetail() async {
    final messenger = ScaffoldMessenger.of(context);
    final opened = await widget.openExternal(_mailto(_category, _impact));
    if (opened || !mounted) return;
    PGToast.showWith(
      messenger,
      'Could not open email. Try again.',
      variant: PGToastVariant.error,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
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
            Text(
              'Send beta feedback',
              style: V2Typography.titleSm(color: context.v2.fg),
            ),
            const SizedBox(height: V2Spacing.space8),
            Text(
              'A quick, anonymous note — just the category and how much it '
              'affects you. No health details are attached. To add detail, the '
              'email option keeps it in your own inbox.',
              style: V2Typography.body(color: context.v2.fgMuted),
            ),
            const SizedBox(height: V2Spacing.space24),
            _label('What is it about?'),
            const SizedBox(height: V2Spacing.space8),
            Wrap(
              spacing: V2Spacing.space8,
              runSpacing: V2Spacing.space8,
              children: [
                for (final c in PgFeedbackCategory.values)
                  PGGoalChip(
                    label: c.label,
                    selected: _category == c,
                    onTap: () => setState(() => _category = c),
                  ),
              ],
            ),
            const SizedBox(height: V2Spacing.space16),
            _label('How much does it affect you?'),
            const SizedBox(height: V2Spacing.space8),
            Wrap(
              spacing: V2Spacing.space8,
              runSpacing: V2Spacing.space8,
              children: [
                for (final i in PgFeedbackImpact.values)
                  PGGoalChip(
                    label: i.label,
                    selected: _impact == i,
                    onTap: () => setState(() => _impact = i),
                  ),
              ],
            ),
            const SizedBox(height: V2Spacing.space24),
            PGPillButton(
              label: _sending ? 'Sending…' : 'Send feedback',
              variant: PGPillVariant.primary,
              expand: true,
              onPressed: _canSend ? _send : null,
            ),
            const SizedBox(height: V2Spacing.space8),
            PGPillButton(
              label: 'Add detail by email',
              icon: Icons.mail_outline_rounded,
              variant: PGPillVariant.secondary,
              expand: true,
              onPressed: _emailDetail,
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) =>
      Text(text, style: V2Typography.bodySm(color: context.v2.fgMuted));
}

/// Builds the support mailto, pre-filling the chosen category/impact in the
/// subject and a calm reminder not to include health details in the body.
Uri _mailto(PgFeedbackCategory? category, PgFeedbackImpact? impact) {
  final subject = StringBuffer('PharmaGuide beta feedback');
  if (category != null) subject.write(' — ${category.label}');
  if (impact != null) subject.write(' (${impact.label})');
  return Uri(
    scheme: 'mailto',
    path: kSupportEmail,
    queryParameters: {
      'subject': subject.toString(),
      'body':
          'Please describe what happened. No need to include any health '
          'details (medications, conditions, or doses).\n\n',
    },
  );
}
