import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';
import 'package:pharmaguide/features/settings/settings_screen.dart';

void main() {
  // DBs are created and closed inside each test body (not via setUp/tearDown).
  // Drift's close() hangs when called from tearDown after the fake-async
  // zone has drained — closing inside the body avoids the shutdown race.

  Widget buildTestWidget(
    UserDatabase userDb, {
    List<Override> overrides = const [],
  }) {
    return ProviderScope(
      overrides: [userDatabaseProvider.overrideWithValue(userDb), ...overrides],
      child: const MaterialApp(home: SettingsScreen()),
    );
  }

  group('SettingsScreen', () {
    testWidgets('shows Profile title', (tester) async {
      final userDb = UserDatabase.memory();

      await tester.pumpWidget(buildTestWidget(userDb));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Profile'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await userDb.close();
    });

    testWidgets('shows active section headers and no dead account section', (
      tester,
    ) async {
      final userDb = UserDatabase.memory();

      await tester.pumpWidget(buildTestWidget(userDb));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify active headers exist by scrolling through the list.
      // Use skipOffstage: false to find text even if not yet visible.
      final headers = [
        'Health profile',
        'Privacy & data',
        'Analysis history',
        'Settings',
        'About',
      ];

      final scrollable = find.byType(Scrollable).first;

      for (final header in headers) {
        // Scroll until the header is visible, or rely on skipOffstage.
        while (find.text(header).evaluate().isEmpty) {
          await tester.drag(scrollable, const Offset(0, -200));
          await tester.pump();
        }
        expect(find.text(header), findsOneWidget);
      }

      expect(find.text('Account & security'), findsNothing);
      expect(find.text('Sign in / create account'), findsNothing);
      expect(find.text('Email'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await userDb.close();
    });

    testWidgets('shows profile summary card', (tester) async {
      final userDb = UserDatabase.memory();

      await tester.pumpWidget(buildTestWidget(userDb));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Your health settings'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await userDb.close();
    });

    testWidgets('shows Guest User when no nickname', (tester) async {
      final userDb = UserDatabase.memory();

      await tester.pumpWidget(buildTestWidget(userDb));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Guest'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await userDb.close();
    });

    testWidgets('does not flash Guest while profile is still loading', (
      tester,
    ) async {
      final userDb = UserDatabase.memory();
      final pendingProfile = Completer<ProfileState>();

      await tester.pumpWidget(
        buildTestWidget(
          userDb,
          overrides: [
            loadedProfileProvider.overrideWith((_) => pendingProfile.future),
          ],
        ),
      );
      await tester.pump();

      expect(find.text('Loading profile'), findsOneWidget);
      expect(find.text('Guest'), findsNothing);

      pendingProfile.complete(const ProfileState(nickname: 'Sean'));
      await tester.pump();

      expect(find.text('Sean'), findsOneWidget);
      expect(find.text('Loading profile'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await userDb.close();
    });

    testWidgets('shows privacy dashboard button', (tester) async {
      final userDb = UserDatabase.memory();

      await tester.pumpWidget(buildTestWidget(userDb));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Privacy dashboard'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await userDb.close();
    });

    testWidgets(
      'privacy dashboard does not claim health data syncs to the cloud',
      (tester) async {
        final userDb = UserDatabase.memory();

        await tester.pumpWidget(buildTestWidget(userDb));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        await tester.tap(find.text('Privacy dashboard'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(
          find.text('Scan history & stack data', skipOffstage: false),
          findsNothing,
        );
        expect(
          find.textContaining('Supplement stack entries', skipOffstage: false),
          findsWidgets,
        );
        expect(
          find.textContaining(
            'Conditions, allergies, and health profile',
            skipOffstage: false,
          ),
          findsWidgets,
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await userDb.close();
      },
    );
  });
}
