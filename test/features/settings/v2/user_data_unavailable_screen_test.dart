// The lost-key screen and its confirmation. The wording is Sean's approved text
// (2026-11-03), and a tap in the wrong place must never erase anything.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/theme/v2/v2_theme.dart';
import 'package:pharmaguide/features/settings/v2/user_data_unavailable_screen.dart';

const _startOver = 'Start over on this device';
const _erase = 'Erase and start over';
const _understand = "I understand this can't be undone";

const _lostBody =
    "PharmaGuide can't find the key that unlocks your health data on this "
    "device, so it stays locked. Until it opens, PharmaGuide can't check your "
    "medications. Try again first. If it still doesn't open, you can start "
    'over on this device.';

const _alwaysShown = [
  'Start over on this device?',
  "This permanently erases your locked health data from this device. It can't "
      'be brought back.',
  "What's erased",
  'Your medications, supplements and reminders',
  'Your profile, including conditions, allergies and goals',
  'Your health history and its attachments',
  'Your scans, favorites and recent searches',
  'Your product submission drafts and their photos',
  'What stays',
  'Data for any other account or guest on this device',
  'The product catalog and your app settings',
  "Afterward, PharmaGuide can't check products against your medications, "
      'conditions or allergies until you add them again.',
  _understand,
  'Not now',
];

const _signedInOnly = [
  "Findings you shared with an AI assistant. If you're offline, they stay "
      'until they expire.',
  'Your PharmaGuide account and sign-in',
  "A copy of your supplement list, saved with your account. PharmaGuide can't "
      "bring it back to this device, so you'd add your supplements again.",
];

const _failure =
    "That didn't finish. Your health data is still locked and nothing new was "
    'created. Please try again.';

void main() {
  late int erases;
  late int retries;

  setUp(() {
    erases = 0;
    retries = 0;
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    bool keyLost = true,
    bool signedIn = true,
    Future<void> Function()? erase,
  }) async {
    tester.view.physicalSize = const Size(1179, 3200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: V2Theme.light,
        home: UserDataUnavailableScreen(
          onRetry: () => retries++,
          signedIn: signedIn,
          onStartOver: keyLost
              ? erase ??
                    () async {
                      erases++;
                    }
              : null,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.text(_startOver));
    await tester.pumpAndSettle();
  }

  /// A tap that lands whether or not the control is enabled.
  Future<void> tapErase(WidgetTester tester) async {
    await tester.tap(find.text(_erase), warnIfMissed: false);
    await tester.pumpAndSettle();
  }

  testWidgets('any other failure only offers a retry, as it did before', (
    tester,
  ) async {
    await pumpScreen(tester, keyLost: false);

    expect(find.text(_startOver), findsNothing);
    expect(find.text(_lostBody), findsNothing);
    expect(
      find.text(
        "Please try again. Until it opens, PharmaGuide can't check your "
        'medications.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Try again'));
    expect(retries, 1);
    expect(erases, 0);
  });

  testWidgets('a lost key explains itself and offers both ways forward', (
    tester,
  ) async {
    await pumpScreen(tester);

    expect(find.text("Your health data didn't open"), findsOneWidget);
    expect(find.text(_lostBody), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text(_startOver), findsOneWidget);
    await tester.tap(find.text('Try again'));
    expect(retries, 1);
    expect(erases, 0);
  });

  testWidgets('the signed-in confirmation says all of it, word for word', (
    tester,
  ) async {
    await pumpScreen(tester);
    await openSheet(tester);

    for (final line in [..._alwaysShown, ..._signedInOnly, _erase]) {
      expect(find.text(line), findsOneWidget, reason: line);
    }
  });

  testWidgets('a guest never sees the lines about an account', (tester) async {
    await pumpScreen(tester, signedIn: false);
    await openSheet(tester);

    for (final line in [..._alwaysShown, _erase]) {
      expect(find.text(line), findsOneWidget, reason: line);
    }
    for (final line in _signedInOnly) {
      expect(find.text(line), findsNothing, reason: line);
    }
  });

  testWidgets('opening the confirmation erases nothing', (tester) async {
    await pumpScreen(tester);
    await openSheet(tester);

    expect(erases, 0);
  });

  testWidgets('erase does nothing until the box is ticked', (tester) async {
    await pumpScreen(tester);
    await openSheet(tester);

    await tapErase(tester);
    expect(erases, 0);
    expect(find.text(_erase), findsOneWidget, reason: 'the sheet stays open');

    await tester.tap(find.text(_understand));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_understand));
    await tester.pumpAndSettle();
    await tapErase(tester);
    expect(erases, 0, reason: 'unticking takes the permission back');
  });

  testWidgets('not now closes it and erases nothing', (tester) async {
    await pumpScreen(tester);
    await openSheet(tester);
    await tester.tap(find.text(_understand));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();

    expect(erases, 0);
    expect(find.text(_erase), findsNothing);
    expect(find.text(_startOver), findsOneWidget);
  });

  testWidgets('only a deliberate tap closes it: not a stray tap or a drag', (
    tester,
  ) async {
    await pumpScreen(tester);
    await openSheet(tester);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text(_erase), findsOneWidget, reason: 'tap outside');

    // The list takes a drag on its text, so ask the sheet itself as well.
    expect(
      tester.widget<BottomSheet>(find.byType(BottomSheet)).enableDrag,
      isFalse,
    );
    await tester.drag(find.text('What stays'), const Offset(0, 700));
    await tester.pumpAndSettle();
    expect(find.text(_erase), findsOneWidget, reason: 'drag down');

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text(_erase), findsNothing, reason: 'back still works idle');
    expect(erases, 0);
  });

  testWidgets('ticking the box and erasing runs it once, and closes', (
    tester,
  ) async {
    await pumpScreen(tester);
    await openSheet(tester);
    await tester.tap(find.text(_understand));
    await tester.pumpAndSettle();

    await tapErase(tester);

    expect(erases, 1);
    expect(find.text(_erase), findsNothing);
  });

  testWidgets('a second tap while it runs does not run it again', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      erase: () async {
        erases++;
        await Future<void>.delayed(const Duration(seconds: 1));
      },
    );
    await openSheet(tester);
    await tester.tap(find.text(_understand));
    await tester.pumpAndSettle();

    await tester.tap(find.text(_erase));
    await tester.pump();
    await tester.tap(find.byType(FilledButton), warnIfMissed: false);
    await tester.pump();
    await tester.tap(find.text('Not now'), warnIfMissed: false);
    await tester.pump();
    await tester.binding.handlePopRoute();
    // Long enough for a dismissal to finish, with the erase still running.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 600));
    expect(erases, 1);
    expect(find.byType(FilledButton), findsOneWidget, reason: 'stays open');

    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.byType(FilledButton), findsNothing);
  });

  test('the message after starting over is the approved wording', () {
    expect(
      startedOverMessage,
      "You're starting fresh on this device. Add your medications and profile "
      'again so PharmaGuide can check products against them.',
    );
  });

  testWidgets('the message waits for the first page of the reopened app', (
    tester,
  ) async {
    final messenger = GlobalKey<ScaffoldMessengerState>();
    Widget app(Widget home) => MaterialApp(
      theme: V2Theme.light,
      scaffoldMessengerKey: messenger,
      home: home,
    );
    // The app's tree is up, and its router hasn't built a page yet.
    await tester.pumpWidget(app(const SizedBox()));

    unawaited(showStartedOverMessage(messenger));
    await tester.pump();
    await tester.pumpWidget(app(const Scaffold()));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    expect(find.text(startedOverMessage), findsOneWidget);
    await tester.pump(const Duration(seconds: 9));
    await tester.pumpAndSettle();
  });

  testWidgets('a failed erase says so and lets the person try again', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      erase: () async {
        erases++;
        if (erases == 1) throw StateError('the file would not delete');
      },
    );
    await openSheet(tester);
    await tester.tap(find.text(_understand));
    await tester.pumpAndSettle();

    await tapErase(tester);

    expect(find.text(_failure), findsOneWidget);
    expect(find.text(_erase), findsOneWidget, reason: 'the sheet stays open');

    await tapErase(tester);
    expect(erases, 2);
    expect(find.text(_erase), findsNothing);
  });
}
