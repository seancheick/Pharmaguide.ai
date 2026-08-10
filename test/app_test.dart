import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/app.dart';
import 'package:pharmaguide/core/widgets/pg_frosted_nav_bar.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/settings/providers/notification_settings_provider.dart';
import 'package:pharmaguide/services/notifications/notification_authorization_service.dart';

void main() {
  // DBs are created and closed inside each test body (not via setUp/tearDown).
  // Drift's close() hangs when called from tearDown after the fake-async
  // zone has drained — closing inside the body avoids the shutdown race.

  Widget buildApp(CoreDatabase coreDb, UserDatabase userDb) {
    return ProviderScope(
      overrides: [
        coreDatabaseProvider.overrideWithValue(coreDb),
        userDatabaseProvider.overrideWithValue(userDb),
        notificationAuthorizationServiceProvider.overrideWithValue(
          const _AllowedNotificationService(),
        ),
      ],
      // hasSeenOnboarding: true so splash ?next=/ → home shell.
      child: const PharmaGuideApp(hasSeenOnboarding: true),
    );
  }

  // Phase 11.11 hygiene (2026-05-17): staged route toggles were
  // removed after the route-coherence promotion. v2 is now the
  // unconditional production route; coherence is enforced by the
  // absence of v1 imports in `lib/app.dart`.

  /// Pump past the v2 animated splash so the shell (nav bar, tabs) is
  /// visible. Tests that interact with tabs must call this helper first.
  ///
  /// Uses explicit time-step pumps (not pumpAndSettle) because downstream
  /// screens may contain widgets that keep animations active indefinitely.
  ///
  /// v2 splash timing budget: 64ms native-handoff hold + 980ms entrance
  /// + 100ms composed hold + 160ms exit fade + post-frame navigation.
  /// Each timer boundary gets its own pump so the fake-async clock gives
  /// Flutter a frame to start the next animation/timer.
  Future<void> pumpPastSplash(WidgetTester tester) async {
    await tester.pump(); // initial frame
    await tester.pump(
      const Duration(milliseconds: 64),
    ); // start entrance after native-handoff hold
    await tester.pump(
      const Duration(milliseconds: 980),
    ); // complete entrance animation
    await tester.pump(); // schedule composed hold after entrance completion
    await tester.pump(
      const Duration(milliseconds: 100),
    ); // composed hold before exit fade
    await tester.pump(); // start exit fade
    await tester.pump(const Duration(milliseconds: 160)); // exit fade
    await tester.pump(); // process the GoRouter.go() navigation
    for (var i = 0; i < 40; i += 1) {
      if (find.byType(PGFrostedNavBar).evaluate().isNotEmpty) return;
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('App renders with 5 navigation tabs', (tester) async {
    final coreDb = CoreDatabase.memory();
    final userDb = UserDatabase.memory();

    await tester.pumpWidget(buildApp(coreDb, userDb));
    await pumpPastSplash(tester);

    expect(find.byType(PGFrostedNavBar), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Home'), findsWidgets);
    expect(find.text('Scan'), findsWidgets);
    expect(find.text('Stack'), findsWidgets);
    expect(find.text('Chat'), findsWidgets);
    expect(find.text('Profile'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    await coreDb.close();
    await userDb.close();
  });

  testWidgets('Home tab is selected by default', (tester) async {
    final coreDb = CoreDatabase.memory();
    final userDb = UserDatabase.memory();

    await tester.pumpWidget(buildApp(coreDb, userDb));
    await pumpPastSplash(tester);

    // Home screen content should be visible
    expect(find.text('Home'), findsWidgets); // nav + screen title

    await tester.pumpWidget(const SizedBox.shrink());
    await coreDb.close();
    await userDb.close();
  });

  testWidgets('Tapping Scan tab navigates to scan screen', (tester) async {
    final coreDb = CoreDatabase.memory();
    final userDb = UserDatabase.memory();

    await tester.pumpWidget(buildApp(coreDb, userDb));
    await pumpPastSplash(tester);

    await tester.tap(find.text('Scan'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Scan'), findsWidgets); // nav + screen title

    await tester.pumpWidget(const SizedBox.shrink());
    await coreDb.close();
    await userDb.close();
  });

  testWidgets('Tapping Stack tab navigates to stack screen', (tester) async {
    final coreDb = CoreDatabase.memory();
    final userDb = UserDatabase.memory();

    await tester.pumpWidget(buildApp(coreDb, userDb));
    await pumpPastSplash(tester);

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Stack'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('My stack'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    await coreDb.close();
    await userDb.close();
  });

  testWidgets('empty stack keeps Nutrients tab empty', (tester) async {
    final coreDb = CoreDatabase.memory();
    final userDb = UserDatabase.memory();

    await tester.pumpWidget(buildApp(coreDb, userDb));
    await pumpPastSplash(tester);

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Stack'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Nutrients'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('No nutrient totals yet'), findsOneWidget);
    expect(find.byKey(const Key('nutrient-accumulation-card')), findsNothing);
    expect(find.text('Stack Nutrient Totals'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await coreDb.close();
    await userDb.close();
  });

  testWidgets('Tapping Chat tab shows the v2 holding surface', (tester) async {
    final coreDb = CoreDatabase.memory();
    final userDb = UserDatabase.memory();

    await tester.pumpWidget(buildApp(coreDb, userDb));
    await pumpPastSplash(tester);

    await tester.tap(find.text('Chat'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Ask PharmaGuide'), findsOneWidget);
    expect(find.text('Search products'), findsOneWidget);
    expect(find.text('Quick Check'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await coreDb.close();
    await userDb.close();
  });

  testWidgets('Tapping Profile tab navigates to profile screen', (
    tester,
  ) async {
    final coreDb = CoreDatabase.memory();
    final userDb = UserDatabase.memory();

    await tester.pumpWidget(buildApp(coreDb, userDb));
    await pumpPastSplash(tester);

    await tester.tap(find.text('Profile'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Profile'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    await coreDb.close();
    await userDb.close();
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
