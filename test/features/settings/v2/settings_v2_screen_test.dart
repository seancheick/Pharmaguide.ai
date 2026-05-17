import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/features/settings/v2/settings_v2_screen.dart';

void main() {
  testWidgets('guest sign-in tile opens auth invitation', (tester) async {
    final router = GoRouter(
      initialLocation: Routes.profile,
      routes: [
        GoRoute(
          path: Routes.profile,
          builder: (_, __) => const SettingsV2Screen(
            nickname: '',
            stackCount: 0,
            medicationCount: 0,
            scanCount: 0,
            signedIn: false,
          ),
        ),
        GoRoute(
          path: Routes.authInvitation,
          builder: (_, __) => const Scaffold(body: Text('Auth invitation')),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Auth invitation'), findsOneWidget);
  });

  testWidgets('signed-in email tile shows provided account email', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SettingsV2Screen(
          signedIn: true,
          accountEmail: 'user@example.com',
        ),
      ),
    );

    expect(find.text('Email'), findsOneWidget);
    expect(find.text('user@example.com'), findsOneWidget);
    expect(find.text('sean@example.com'), findsNothing);
  });
}
