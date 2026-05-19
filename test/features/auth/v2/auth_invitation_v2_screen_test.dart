import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/features/auth/v2/auth_invitation_v2_screen.dart';

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
}
