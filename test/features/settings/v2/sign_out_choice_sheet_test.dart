import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/settings/v2/settings_v2_screen.dart';
import 'package:pharmaguide/features/settings/v2/sign_out_choice_sheet.dart';

void main() {
  group('signOutWithChoice', () {
    late List<String> calls;
    String? session;

    Future<bool> run(
      SignOutChoice? choice, {
      Future<void> Function()? signOut,
    }) => signOutWithChoice(
      choose: () async => choice,
      signOut:
          signOut ??
          () async {
            calls.add('signOut');
            session = null;
          },
      currentUid: () => session,
      removeAccountData: (uid) async => calls.add('remove $uid'),
    );

    setUp(() {
      calls = [];
      session = 'account-a';
    });

    test('backing out signs no one out and removes nothing', () async {
      expect(await run(null), isFalse);
      expect(calls, isEmpty);
    });

    test('keep signs out and removes nothing', () async {
      expect(await run(SignOutChoice.keep), isTrue);
      expect(calls, ['signOut']);
    });

    test('remove signs out, then removes that account', () async {
      expect(await run(SignOutChoice.remove), isTrue);
      expect(calls, ['signOut', 'remove account-a']);
    });

    test('a server failure after the session ended still removes', () async {
      final finished = await run(
        SignOutChoice.remove,
        signOut: () async {
          session = null;
          throw StateError('offline');
        },
      );
      expect(finished, isTrue);
      expect(calls, ['remove account-a']);
    });

    test('a failure that leaves the session keeps the data', () async {
      await expectLater(
        run(
          SignOutChoice.remove,
          signOut: () async => throw StateError('offline'),
        ),
        throwsStateError,
      );
      expect(calls, isEmpty);
    });
  });

  testWidgets('the sheet offers keep first, and each button answers', (
    tester,
  ) async {
    Future<SignOutChoice?>? shown;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => shown = showModalBottomSheet<SignOutChoice>(
              context: context,
              builder: (_) => const SignOutChoiceSheet(),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    for (final (label, choice) in [
      ('Keep on this phone', SignOutChoice.keep),
      ('Remove from this phone', SignOutChoice.remove),
    ]) {
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.textContaining("isn't a cloud backup"), findsOneWidget);
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(await shown, choice);
    }
  });

  testWidgets('backing out of sign-out announces nothing', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsV2Screen(
          signedIn: true,
          accountEmail: 'user@example.com',
          onSignOut: () async => false,
        ),
      ),
    );

    await tester.tap(find.text('Sign out'));
    await tester.pump();

    expect(find.text('Signed out'), findsNothing);
  });
}
