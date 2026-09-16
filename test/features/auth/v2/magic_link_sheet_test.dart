import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/auth/v2/magic_link_sheet.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// The sign-in email carries both a link and a one-time code. When the email
// is opened on another device (a laptop, or a simulator's host Mac) the link
// cannot reach this app, so the sheet must also accept the code.
void main() {
  Future<void> pumpSentSheet(
    WidgetTester tester, {
    required Future<void> Function(String email, String code) verifyCode,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MagicLinkSheet(sendLink: (_) async {}, verifyCode: verifyCode),
        ),
      ),
    );
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'user@example.com');
    await tester.pump();
    await tester.tap(find.text('Send magic link'));
    await tester.pumpAndSettle();
  }

  testWidgets('sent state accepts the emailed code and verifies it', (
    tester,
  ) async {
    final calls = <List<String>>[];
    await pumpSentSheet(
      tester,
      verifyCode: (email, code) async => calls.add([email, code]),
    );

    expect(find.text('Check your email'), findsOneWidget);
    expect(find.text('Verify code'), findsOneWidget);

    await tester.enterText(find.byType(TextField), ' 123 456 ');
    await tester.pump();
    await tester.ensureVisible(find.text('Verify code'));
    await tester.tap(find.text('Verify code'));
    await tester.pumpAndSettle();

    expect(calls, [
      ['user@example.com', '123456'],
    ]);
  });

  testWidgets('a rejected code shows a calm retry message', (tester) async {
    await pumpSentSheet(
      tester,
      verifyCode: (_, __) async =>
          throw const AuthException('Token has expired or is invalid'),
    );

    await tester.enterText(find.byType(TextField), '654321');
    await tester.pump();
    await tester.ensureVisible(find.text('Verify code'));
    await tester.tap(find.text('Verify code'));
    await tester.pumpAndSettle();

    expect(
      find.text('That code is wrong or has expired. Check the latest email.'),
      findsOneWidget,
    );
  });

  testWidgets('Verify code stays disabled until a full code is typed', (
    tester,
  ) async {
    var calls = 0;
    await pumpSentSheet(tester, verifyCode: (_, __) async => calls++);

    await tester.enterText(find.byType(TextField), '123');
    await tester.pump();
    await tester.ensureVisible(find.text('Verify code'));
    await tester.tap(find.text('Verify code'));
    await tester.pumpAndSettle();

    expect(calls, 0);
  });
}
