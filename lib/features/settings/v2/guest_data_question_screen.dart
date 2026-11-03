import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

/// Asked once at sign-in when the phone holds items added without signing in,
/// because whoever added them may not be the person signing in (ADR-013). It is
/// a whole screen and not a sheet: the app's tree is down while it waits, so it
/// can't be dismissed, and only an answer finishes the sign-in.
class GuestDataQuestionScreen extends StatelessWidget {
  const GuestDataQuestionScreen({required this.onAnswer, super.key});

  final ValueChanged<bool> onAnswer;

  @override
  Widget build(BuildContext context) {
    final palette = context.v2;
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(V2Spacing.space24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Add the items already on this phone to your account?',
                    style: V2Typography.title(color: palette.fg),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: V2Spacing.space8),
                  Text(
                    'They were added without signing in. If you leave them '
                    'out, they stay on this phone, outside your account.',
                    style: V2Typography.bodySm(color: palette.fgMuted),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: V2Spacing.space24),
                  SizedBox(
                    height: 48,
                    child: FilledButton(
                      onPressed: () => onAnswer(true),
                      child: const Text('Yes, add them'),
                    ),
                  ),
                  const SizedBox(height: V2Spacing.space8),
                  SizedBox(
                    height: 48,
                    child: TextButton(
                      onPressed: () => onAnswer(false),
                      child: const Text('No, leave them out'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
