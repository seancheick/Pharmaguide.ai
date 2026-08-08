import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/widgets/pg_frosted_nav_bar.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/settings/v2/settings_v2_connected.dart';
import 'package:pharmaguide/features/settings/v2/settings_v2_screen.dart';
import 'package:pharmaguide/features/settings/providers/notification_settings_provider.dart';
import 'package:pharmaguide/services/notifications/notification_authorization_service.dart';
import 'package:pharmaguide/services/auth_state_service.dart';
import 'package:pharmaguide/services/scan_limit_service.dart';
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

    expect(find.text('Save stack, profile, and history'), findsOneWidget);
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

  testWidgets('signed-in profile clears the persistent navigation bar', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: SettingsV2Screen(signedIn: true)),
    );

    final list = tester.widget<ListView>(find.byType(ListView));
    final padding = list.padding!.resolve(TextDirection.ltr);

    expect(padding.bottom, greaterThanOrEqualTo(kPGNavBarHeight));
  });

  testWidgets('signed-in account can sign out from settings', (tester) async {
    var signedOut = false;
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsV2Screen(
          signedIn: true,
          accountEmail: 'user@example.com',
          onSignOut: () async {
            signedOut = true;
          },
        ),
      ),
    );

    await tester.tap(find.text('Sign out'));
    await tester.pump();

    expect(signedOut, isTrue);
    expect(find.text('Signed out'), findsOneWidget);
  });

  testWidgets('Profile exposes the canonical clinician report entry point', (
    tester,
  ) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsV2Screen(onOpenClinicianReport: () => opened = true),
      ),
    );

    await tester.scrollUntilVisible(
      find.text('Clinician report'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await Scrollable.ensureVisible(
      tester.element(find.text('Clinician report')),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clinician report'));

    expect(opened, isTrue);
    expect(find.text('Preview, print, or share a private PDF'), findsOneWidget);
  });

  testWidgets('Profile exposes the unified Health History entry point', (
    tester,
  ) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsV2Screen(onOpenHealthHistory: () => opened = true),
      ),
    );

    await tester.scrollUntilVisible(
      find.text('Health History'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Health History'));
    await tester.tap(find.text('Health History'));

    expect(opened, isTrue);
    expect(
      find.text('Timeline, appointments, tests, and reminders'),
      findsOneWidget,
    );
  });

  testWidgets('signed-in profile exposes private product submission status', (
    tester,
  ) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsV2Screen(
          signedIn: true,
          onOpenProductSubmissions: () => opened = true,
        ),
      ),
    );

    await tester.scrollUntilVisible(
      find.text('Product submissions'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Product submissions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Product submissions'));

    expect(opened, isTrue);
    expect(
      find.text('Track label corrections and missing products'),
      findsOneWidget,
    );
  });

  testWidgets('connected settings reacts when auth state becomes guest', (
    tester,
  ) async {
    final userDb = UserDatabase.memory();
    final authState = AuthStateService()..onSignedIn();
    final container = ProviderContainer(
      overrides: [
        userDatabaseProvider.overrideWithValue(userDb),
        authStateProvider.overrideWith((ref) => authState),
        notificationAuthorizationServiceProvider.overrideWithValue(
          const _AllowedNotificationService(),
        ),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(userDb.close);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsV2Connected()),
      ),
    );
    await tester.pump();

    expect(find.text('Sign out'), findsOneWidget);

    authState.onSignedOut();
    await tester.pump();

    expect(find.text('Sign out'), findsNothing);
    expect(find.text('Sign in'), findsOneWidget);
  });

  test(
    'scan limits keep guests capped and signed-in users unlimited',
    () async {
      final today = DateTime.now().toUtc().toIso8601String().split('T').first;
      SharedPreferences.setMockInitialValues({
        'guest_daily_scan_count': 2,
        'guest_daily_scan_date': today,
      });
      final prefs = await SharedPreferences.getInstance();

      final guest = ScanLimitService(prefs: prefs, isSignedIn: false);
      expect(guest.scanLimit, 3);
      expect(guest.scansRemaining, 1);
      expect(guest.canScan, isTrue);
      expect(await guest.recordScan(), isTrue);
      expect(guest.scansRemaining, 0);
      expect(guest.canScan, isFalse);
      expect(await guest.recordScan(), isFalse);

      final signedIn = ScanLimitService(prefs: prefs, isSignedIn: true);
      expect(signedIn.hasUnlimitedScans, isTrue);
      expect(signedIn.scanLimit, isNull);
      expect(signedIn.scansRemaining, isNull);
      expect(signedIn.canScan, isTrue);
      expect(await signedIn.recordScan(), isTrue);
      expect(signedIn.usageLabel, 'Unlimited scans');
      expect(prefs.getInt('guest_daily_scan_count'), 3);
    },
  );

  test('guest scan count resets across UTC days', () async {
    SharedPreferences.setMockInitialValues({
      'guest_daily_scan_count': 3,
      'guest_daily_scan_date': '2026-01-01',
    });
    final prefs = await SharedPreferences.getInstance();
    final guest = ScanLimitService(prefs: prefs, isSignedIn: false);

    expect(guest.guestScansUsed, 0);
    expect(guest.scansRemaining, 3);
    expect(await guest.recordScan(), isTrue);
    expect(guest.guestScansUsed, 1);
  });

  testWidgets('privacy dashboard opens a real v2 sheet', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsV2Screen()));

    await tester.scrollUntilVisible(
      find.text('Privacy dashboard'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Privacy dashboard'));
    await tester.pumpAndSettle();

    expect(find.text('Health profile: on device'), findsOneWidget);
    expect(find.text('Account email: Supabase auth'), findsOneWidget);
  });

  testWidgets('about legal and support rows open release-safe destinations', (
    tester,
  ) async {
    final opened = <Uri>[];
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsV2Screen(
          onOpenExternal: (uri) async {
            opened.add(uri);
            return true;
          },
        ),
      ),
    );

    await tester.scrollUntilVisible(
      find.text('Terms of service'),
      320,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();

    await tester.tap(find.text('Terms of service'));
    await tester.pump();
    await tester.tap(find.text('Privacy policy'));
    await tester.pump();
    await tester.tap(find.text('Contact support'));
    await tester.pump();

    expect(opened[0].toString(), 'https://pharmaguide.io/terms');
    expect(opened[1].toString(), 'https://pharmaguide.io/privacy');
    expect(opened[2].scheme, 'mailto');
    expect(opened[2].path, 'support@pharmaguide.io');
  });

  testWidgets('rate row explains TestFlight feedback instead of dead tapping', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsV2Screen()));

    await tester.scrollUntilVisible(
      find.text('Rate PharmaGuide'),
      320,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Rate PharmaGuide'));
    await tester.pump();
    await tester.tap(find.text('Rate PharmaGuide'));
    await tester.pumpAndSettle();

    expect(find.textContaining('TestFlight builds'), findsOneWidget);
  });
}

class _AllowedNotificationService implements NotificationAuthorizationService {
  const _AllowedNotificationService();

  @override
  Future<NotificationAuthorizationStatus> readStatus() async =>
      NotificationAuthorizationStatus.allowed;

  @override
  Future<NotificationAuthorizationStatus> requestPermission() async =>
      NotificationAuthorizationStatus.allowed;

  @override
  Future<void> openNotificationSettings() async {}
}
