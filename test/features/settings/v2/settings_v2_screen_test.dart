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
import 'package:pharmaguide/features/contributions/providers/product_submission_providers.dart';
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

    // Guests keep their stack on the device; an account adds backup + sync.
    expect(find.text('Back up and sync your stack'), findsOneWidget);
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

  // The app has no biometric lock (no local_auth), so a switch that reads
  // "Biometric unlock · Face ID" told people their health data was locked
  // behind Face ID when nothing was.
  for (final signedIn in [false, true]) {
    testWidgets(
      'Profile shows no biometric lock control (signedIn: $signedIn)',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(home: SettingsV2Screen(signedIn: signedIn)),
        );

        expect(find.text('Biometric unlock'), findsNothing);
        expect(find.text('Face ID'), findsNothing);
        expect(find.byType(Switch), findsNothing);
      },
    );
  }

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
          pendingProductSubmissionCount: 3,
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
    expect(
      find.byKey(const Key('product-submissions-pending-badge')),
      findsOneWidget,
    );
    expect(find.text('3'), findsOneWidget);
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
        pendingSubmissionCountProvider.overrideWithValue(2),
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
    expect(
      find.byKey(const Key('product-submissions-pending-badge')),
      findsOneWidget,
    );

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

  testWidgets('privacy dashboard discloses signed-in supplement sync', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsV2Screen()));

    await tester.scrollUntilVisible(
      find.text('Privacy dashboard'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Privacy dashboard'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'When you sign in, PharmaGuide syncs the supplements in your stack '
        '— their product identity, ingredients, and added, removed, or '
        'updated state — to your account. Your health profile, medication '
        'list, scan history, and supplement dosage and schedule stay on '
        'this device.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Supplement stack: product identity, ingredients, and state sync '
        'when signed in',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Supplement dosage and schedule: on device'),
      findsOneWidget,
    );
    expect(find.text('Medication list: on device'), findsOneWidget);
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

  // Four rows open explanations for features that are not wired yet. Each
  // must say what is true today and point at something that works now,
  // instead of promising an action ("Download catalog for travel").
  for (final (row, caption, mustSay) in [
    (
      'Accessibility',
      'Text size and motion follow your device',
      'Send beta feedback',
    ),
    ('Offline mode', 'Scan, search and checks work offline', 'Works offline'),
    (
      'Rate PharmaGuide',
      'Available after App Store release',
      'Send beta feedback',
    ),
    (
      'Export my data',
      'Coming soon · clinician PDF available now',
      'Clinician report',
    ),
  ]) {
    testWidgets('$row explains what works today', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SettingsV2Screen()));

      await tester.scrollUntilVisible(
        find.text(row),
        320,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text(row));
      expect(find.text(caption), findsOneWidget);
      await tester.pump();
      await tester.tap(find.text(row));
      await tester.pumpAndSettle();

      expect(find.textContaining(mustSay), findsWidgets);
      expect(find.textContaining('Download catalog for travel'), findsNothing);
      expect(find.textContaining('clamp extreme'), findsNothing);
    });
  }

  // Chat is a roadmap item (V2.0), not a tab (App Review 2.1(a)). Sean
  // 2026-09-28: stack-aware, personal, answered on the device. The copy
  // never calls it a pharmacist (a protected title), never claims to be the
  // first, and never says "safe".
  testWidgets('Ask PharmaGuide previews a private, stack-aware guide', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsV2Screen()));

    await tester.scrollUntilVisible(
      find.text('Ask PharmaGuide'),
      320,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Ask PharmaGuide'));
    expect(find.text('COMING LATER'), findsOneWidget);
    expect(find.text('A private guide to everything you take'), findsOneWidget);
    await tester.pump();
    await tester.tap(find.text('Ask PharmaGuide'));
    await tester.pumpAndSettle();

    for (final promise in [
      'every supplement and medication you’ve added',
      'your medications, conditions, allergies, sex and age',
      'showing where it came from',
      'answered on this device',
      'no substitute for your doctor or pharmacist',
      'Check two together',
    ]) {
      expect(find.textContaining(promise), findsOneWidget, reason: promise);
    }
    for (final claim in [
      'your pharmacist',
      'private pharmacist',
      'first',
      'safe',
      'Safe',
    ]) {
      expect(find.textContaining(claim), findsNothing, reason: claim);
    }
  });

  // Medication name search sends the typed text to the U.S. National
  // Library of Medicine (RxNorm); "stays on this device" was only true of
  // the saved list.
  testWidgets('privacy dashboard discloses the RxNorm name lookup', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsV2Screen()));

    await tester.scrollUntilVisible(
      find.text('Privacy dashboard'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Privacy dashboard'));
    await tester.pumpAndSettle();

    expect(find.textContaining('National Library of Medicine'), findsOneWidget);
    // iOS now keeps local health data out of backups, like Android; say so,
    // because a new phone then starts fresh.
    expect(find.textContaining('not included in iCloud'), findsOneWidget);
  });

  // A signed-in supplement stack syncs to the account (see the privacy
  // dashboard), so the closing line may only claim what stays on the device.
  testWidgets('closing privacy line claims only what stays on device', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsV2Screen()));

    await tester.scrollUntilVisible(
      find.text('Your health profile and medication list stay on this device.'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.text('Your health profile and medication list stay on this device.'),
      findsOneWidget,
    );
    expect(find.text('Your health data stays on this device.'), findsNothing);
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
