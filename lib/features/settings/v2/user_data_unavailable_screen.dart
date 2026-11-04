import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_empty_state.dart';
import 'package:pharmaguide/core/widgets/pg_modal.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

/// Said once the app reopens with nothing in it, so an empty stack never reads
/// as having no medications.
const startedOverMessage =
    "You're starting fresh on this device. Add your medications and profile "
    'again so PharmaGuide can check products against them.';

/// Shown when the account's database can't open. Nothing else can be: without
/// it the app would read as having no medications.
class UserDataUnavailableScreen extends StatelessWidget {
  const UserDataUnavailableScreen({
    super.key,
    required this.onRetry,
    this.onStartOver,
    this.signedIn = false,
  });

  final VoidCallback onRetry;

  /// Set only when the key is gone for good. Every other failure just retries.
  final Future<void> Function()? onStartOver;

  final bool signedIn;

  @override
  Widget build(BuildContext context) {
    final startOver = onStartOver;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: PGEmptyState(
            icon: Icons.lock_outline_rounded,
            eyebrow: 'Your health data',
            headline: "Your health data didn't open",
            body: startOver == null
                ? 'Please try again. Until it opens, PharmaGuide can\'t check '
                      'your medications.'
                : "PharmaGuide can't find the key that unlocks your health "
                      'data on this device, so it stays locked. Until it '
                      "opens, PharmaGuide can't check your medications. Try "
                      "again first. If it still doesn't open, you can start "
                      'over on this device.',
            primaryLabel: 'Try again',
            primaryIcon: Icons.refresh_rounded,
            onPrimaryTap: onRetry,
            secondaryLabel: startOver == null
                ? null
                : 'Start over on this device',
            onSecondaryTap: startOver == null
                ? null
                : () => unawaited(
                    PGModal.bottomSheet<void>(
                      context: context,
                      builder: (_) => _StartOverSheet(
                        signedIn: signedIn,
                        onStartOver: startOver,
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _StartOverSheet extends StatefulWidget {
  const _StartOverSheet({required this.signedIn, required this.onStartOver});

  final bool signedIn;
  final Future<void> Function() onStartOver;

  @override
  State<_StartOverSheet> createState() => _StartOverSheetState();
}

class _StartOverSheetState extends State<_StartOverSheet> {
  bool _understands = false;
  bool _erasing = false;
  bool _failed = false;

  Future<void> _erase() async {
    setState(() {
      _erasing = true;
      _failed = false;
    });
    try {
      await widget.onStartOver();
    } on Object {
      // The guard reports it. Its detail means nothing to the person here.
      if (mounted) {
        setState(() {
          _erasing = false;
          _failed = true;
        });
      }
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.v2;
    return PopScope(
      canPop: !_erasing,
      child: SafeArea(
        top: false,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(
            V2Spacing.space24,
            V2Spacing.space8,
            V2Spacing.space24,
            V2Spacing.space24,
          ),
          children: [
            Text(
              'Start over on this device?',
              style: V2Typography.title(color: palette.fg),
            ),
            const SizedBox(height: V2Spacing.space8),
            Text(
              'This permanently erases your locked health data from this '
              "device. It can't be brought back.",
              style: V2Typography.bodySm(color: palette.fgMuted),
            ),
            const SizedBox(height: V2Spacing.space16),
            const _Heading("What's erased"),
            const _Line(
              'Your medications, supplements and reminders',
              erased: true,
            ),
            const _Line(
              'Your profile, including conditions, allergies and goals',
              erased: true,
            ),
            const _Line(
              'Your health history and its attachments',
              erased: true,
            ),
            const _Line(
              'Your scans, favorites and recent searches',
              erased: true,
            ),
            const _Line(
              'Your product submission drafts and their photos',
              erased: true,
            ),
            if (widget.signedIn)
              const _Line(
                "Findings you shared with an AI assistant. If you're offline, "
                'they stay until they expire.',
                erased: true,
              ),
            const SizedBox(height: V2Spacing.space8),
            const _Heading('What stays'),
            if (widget.signedIn) ...const [
              _Line('Your PharmaGuide account and sign-in'),
              _Line(
                'A copy of your supplement list, saved with your account. '
                "PharmaGuide can't bring it back to this device, so you'd add "
                'your supplements again.',
              ),
            ],
            const _Line('Data for any other account or guest on this device'),
            const _Line('The product catalog and your app settings'),
            const SizedBox(height: V2Spacing.space8),
            Text(
              "Afterward, PharmaGuide can't check products against your "
              'medications, conditions or allergies until you add them again.',
              style: V2Typography.bodySm(color: palette.fg),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _understands,
              onChanged: _erasing
                  ? null
                  : (value) => setState(() => _understands = value ?? false),
              title: Text(
                "I understand this can't be undone",
                style: V2Typography.bodySm(color: palette.fg),
              ),
            ),
            if (_failed) ...[
              Semantics(
                liveRegion: true,
                child: Text(
                  "That didn't finish. Your health data is still locked and "
                  'nothing new was created. Please try again.',
                  style: V2Typography.bodySm(color: palette.contraindicated),
                ),
              ),
              const SizedBox(height: V2Spacing.space12),
            ],
            SizedBox(
              height: 48,
              child: FilledButton(
                onPressed: _understands && !_erasing ? _erase : null,
                style: FilledButton.styleFrom(
                  backgroundColor: palette.contraindicated,
                  foregroundColor: palette.onContraindicated,
                ),
                child: _erasing
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Erase and start over'),
              ),
            ),
            const SizedBox(height: V2Spacing.space8),
            SizedBox(
              height: 48,
              child: TextButton(
                onPressed: _erasing ? null : () => Navigator.of(context).pop(),
                child: const Text('Not now'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: V2Spacing.space8),
    child: Semantics(
      header: true,
      child: Text(
        text,
        style: V2Typography.bodySm(
          color: context.v2.fg,
        ).copyWith(fontWeight: FontWeight.w600),
      ),
    ),
  );
}

class _Line extends StatelessWidget {
  const _Line(this.text, {this.erased = false});

  final String text;
  final bool erased;

  @override
  Widget build(BuildContext context) {
    final palette = context.v2;
    return Padding(
      padding: const EdgeInsets.only(bottom: V2Spacing.space8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              erased ? Icons.remove_circle_outline : Icons.check_circle_outline,
              size: 18,
              color: erased ? palette.contraindicated : palette.accent,
            ),
          ),
          const SizedBox(width: V2Spacing.space8),
          Expanded(
            child: Text(text, style: V2Typography.bodySm(color: palette.fg)),
          ),
        ],
      ),
    );
  }
}
