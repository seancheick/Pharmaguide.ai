import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

/// What happens to this account's health data on this phone at sign-out.
enum SignOutChoice { keep, remove }

/// Runs a sign-out with the user's [SignOutChoice]. Returns false when they backed
/// out. A completed sign-out replaces the provider tree, so every dependency is
/// passed in and nothing here reaches back into it.
Future<bool> signOutWithChoice({
  required Future<SignOutChoice?> Function() choose,
  required Future<void> Function() signOut,
  required String? Function() currentUid,
  required Future<void> Function(String uid) removeAccountData,
}) async {
  final choice = await choose();
  if (choice == null) return false;
  final uid = currentUid();
  try {
    await signOut();
  } on Object {
    // The session is removed before the server call. If that call is what
    // failed, this person is signed out on this phone all the same.
    if (currentUid() != null) rethrow;
  }
  if (choice == SignOutChoice.remove && uid != null) {
    await removeAccountData(uid);
  }
  return true;
}

/// Keep is the default. Dismissing the sheet cancels the sign-out (ADR-013).
class SignOutChoiceSheet extends StatelessWidget {
  const SignOutChoiceSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.v2;
    return SafeArea(
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
            'Keep your health data on this phone?',
            style: V2Typography.title(color: palette.fg),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: V2Spacing.space8),
          Text(
            'It stays locked to your account, and only you can open it by '
            "signing in again. It isn't a cloud backup, so it stays only on "
            'this phone. Removing it deletes it from this phone.',
            style: V2Typography.bodySm(color: palette.fgMuted),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: V2Spacing.space24),
          SizedBox(
            height: 48,
            child: FilledButton(
              onPressed: () => Navigator.pop(context, SignOutChoice.keep),
              child: const Text('Keep on this phone'),
            ),
          ),
          const SizedBox(height: V2Spacing.space8),
          SizedBox(
            height: 48,
            child: TextButton(
              onPressed: () => Navigator.pop(context, SignOutChoice.remove),
              child: const Text('Remove from this phone'),
            ),
          ),
        ],
      ),
    );
  }
}
