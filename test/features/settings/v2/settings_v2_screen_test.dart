import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/features/settings/v2/settings_v2_screen.dart';
import 'package:pharmaguide/services/analytics_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  testWidgets('privacy dashboard opens a real v2 sheet', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsV2Screen()));

    await tester.tap(find.text('Privacy dashboard'));
    await tester.pumpAndSettle();

    expect(find.text('Health profile: on device'), findsOneWidget);
    expect(find.text('Account email: Supabase auth'), findsOneWidget);
  });

  testWidgets('analytics toggle persists local opt-in', (tester) async {
    SharedPreferences.setMockInitialValues({
      'settings.analyticsCollectionEnabled': false,
    });
    final analytics = AnalyticsService()..resetForTest();
    await analytics.initialize();

    analytics.trackEvent('before_opt_in');
    expect(analytics.bufferedEvents, isEmpty);

    await tester.pumpWidget(const MaterialApp(home: SettingsV2Screen()));

    final toggle = find.byKey(const Key('settings-analytics-toggle'));
    await tester.scrollUntilVisible(
      toggle,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.tap(toggle);
    await tester.pump();
    await tester.pump();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('settings.analyticsCollectionEnabled'), isTrue);
    expect(analytics.collectionEnabled, isTrue);

    analytics.trackEvent('after_opt_in');
    expect(
      analytics.bufferedEvents.map((e) => e.name),
      contains('after_opt_in'),
    );

    analytics.resetForTest();
  });

  testWidgets('unsupported legal/store rows are static, not dead taps', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsV2Screen()));

    await tester.scrollUntilVisible(
      find.text('Terms of service'),
      320,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();

    final termsTile = find.ancestor(
      of: find.text('Terms of service'),
      matching: find.byType(InkWell),
    );
    expect(tester.widget<InkWell>(termsTile).onTap, isNull);
    expect(find.text('Available before public release'), findsNWidgets(2));
  });
}
