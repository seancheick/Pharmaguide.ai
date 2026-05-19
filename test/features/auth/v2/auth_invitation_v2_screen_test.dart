import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/features/auth/v2/auth_invitation_v2_screen.dart';
import 'package:pharmaguide/features/auth/v2/magic_link_sheet.dart';

void main() {
  testWidgets('Skip for now routes guest users straight home', (tester) async {
    final router = GoRouter(
      initialLocation: Routes.authInvitation,
      routes: [
        GoRoute(
          path: Routes.authInvitation,
          builder: (context, __) =>
              AuthInvitationV2Screen(onSkip: () => context.go(Routes.home)),
        ),
        GoRoute(
          path: Routes.home,
          builder: (_, __) => const Scaffold(body: Text('Home v2')),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump(const Duration(milliseconds: 1500));

    final skip = find.text('Skip for now');
    await tester.ensureVisible(skip);
    await tester.tap(skip);
    await tester.pumpAndSettle();

    expect(find.text('Home v2'), findsOneWidget);
  });

  testWidgets('guest limitation copy states current access policy', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: AuthInvitationV2Screen(onSkip: () {})),
    );
    await tester.pump(const Duration(milliseconds: 1500));

    expect(find.textContaining('3 scans per day'), findsOneWidget);
    expect(
      find.textContaining('no AI, saved stack, or cloud sync'),
      findsOneWidget,
    );
  });

  testWidgets('provider buttons call supplied auth callbacks', (tester) async {
    var appleCalls = 0;
    var googleCalls = 0;
    var emailCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: AuthInvitationV2Screen(
          onApple: () => appleCalls++,
          onGoogle: () => googleCalls++,
          onEmail: () => emailCalls++,
          onSkip: () {},
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1500));

    final apple = find.text('Continue with Apple');
    await tester.ensureVisible(apple);
    await tester.tap(apple);
    await tester.pump();

    final google = find.text('Continue with Google');
    await tester.ensureVisible(google);
    await tester.tap(google);
    await tester.pump();

    final email = find.text('Continue with email');
    await tester.ensureVisible(email);
    await tester.tap(email);
    await tester.pump();

    expect(appleCalls, 1);
    expect(googleCalls, 1);
    expect(emailCalls, 1);
  });

  test('magic link redirect uses app auth callback scheme', () {
    expect(kAuthRedirectUrl, 'pharmaguide://auth/callback');
  });

  testWidgets('magic link sheet surfaces placeholder Supabase config', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: MagicLinkSheet())),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'user@example.com');
    await tester.pump();
    await tester.tap(find.text('Send magic link'));
    await tester.pump();

    expect(find.textContaining('Supabase is not configured'), findsOneWidget);
  });
}
