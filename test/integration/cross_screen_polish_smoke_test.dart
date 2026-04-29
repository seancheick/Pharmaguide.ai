// Cross-screen polish smoke test — apple-grade Sprint 27.21 E.1.
//
// Asserts the single most-visible artifact of the apple-grade migration —
// a frosted top-chrome surface — is present on every screen the sprint
// touched. The contract is intentionally loose: either PGFrostedAppBar
// (sliver path, used by every scrollable screen) OR PGFrostedHeader-inside-
// PreferredSize (the non-sliver fallback used by Profile Setup, where a
// CustomScrollView > SliverFillRemaining > PageView nesting causes Flutter
// null-geometry assertions). Both render the same visual surface, so the
// smoke test accepts either as proof the migration landed.
//
// Product Detail is intentionally OUT of scope here — it requires a full
// product fixture + detail-blob mock; its top-chrome assertion lives in
// the existing test/features/product_detail/ widget tests where the
// fixtures already exist.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/widgets/pg_frosted_app_bar.dart';
import 'package:pharmaguide/core/widgets/pg_frosted_header.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/profile/profile_setup_screen.dart';
import 'package:pharmaguide/features/quick_check/quick_check_screen.dart';
import 'package:pharmaguide/features/settings/settings_screen.dart';
import 'package:pharmaguide/features/stack/stack_screen.dart';

/// Returns true if a frosted-chrome surface (PGFrostedAppBar OR
/// PGFrostedHeader as a top-of-screen surface) is present in the
/// rendered tree. Both render identical visuals; either satisfies
/// the apple-grade migration contract.
bool _hasFrostedTopChrome(WidgetTester tester) {
  final hasAppBar = find.byType(PGFrostedAppBar).evaluate().isNotEmpty;
  final hasHeader = find.byType(PGFrostedHeader).evaluate().isNotEmpty;
  return hasAppBar || hasHeader;
}

void main() {
  group('cross-screen polish smoke (Sprint 27.21 E.1)', () {
    testWidgets('Stack tab renders a frosted top chrome', (tester) async {
      final coreDb = CoreDatabase.memory();
      final userDb = UserDatabase.memory();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            coreDatabaseProvider.overrideWithValue(coreDb),
            userDatabaseProvider.overrideWithValue(userDb),
          ],
          child: const MaterialApp(home: StackScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        _hasFrostedTopChrome(tester),
        isTrue,
        reason: 'Stack tab should mount PGFrostedAppBar (Sprint 27.21 A.1).',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await coreDb.close();
      await userDb.close();
    });

    testWidgets('Settings tab renders a frosted top chrome', (tester) async {
      final userDb = UserDatabase.memory();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userDatabaseProvider.overrideWithValue(userDb),
          ],
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        _hasFrostedTopChrome(tester),
        isTrue,
        reason: 'Settings tab should mount PGFrostedAppBar (Sprint 27.21 A.2).',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await userDb.close();
    });

    testWidgets('Profile Setup renders a frosted top chrome', (tester) async {
      // Profile Setup uses PreferredSize + PGFrostedHeader (non-sliver
      // body — PageView can't nest cleanly under SliverFillRemaining
      // without null-geometry assertions). Smoke test accepts either
      // PGFrostedAppBar or PGFrostedHeader as proof of migration.
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: ProfileSetupScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        _hasFrostedTopChrome(tester),
        isTrue,
        reason:
            'Profile Setup should mount PGFrostedHeader via PreferredSize '
            '(Sprint 27.21 B.1 — sliver-nested PageView fallback).',
      );

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('Quick Check renders a frosted top chrome', (tester) async {
      final coreDb = CoreDatabase.memory();
      final userDb = UserDatabase.memory();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            coreDatabaseProvider.overrideWithValue(coreDb),
            userDatabaseProvider.overrideWithValue(userDb),
          ],
          child: const MaterialApp(home: QuickCheckScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        _hasFrostedTopChrome(tester),
        isTrue,
        reason: 'Quick Check should mount PGFrostedAppBar (Sprint 27.21 B.2).',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await coreDb.close();
      await userDb.close();
    });
  });
}
