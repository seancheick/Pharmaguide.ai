// Spec: INITIATIVE_PRODUCT_DETAIL_CLEANUP.md, Sprint S2.1, T2.
//
// Regression test for the user-reported "Edit profile button does
// nothing / crashes" bug. Root cause: `_openProfile` was pushing
// `Routes.profile` (the SettingsScreen shell-tab path inside the
// bottom-nav `StatefulShellRoute`), not `Routes.profileSetup` (the
// `ProfileSetupScreen` non-shell route). Pushing a shell-tab path
// from a non-shell screen via `context.push` no-ops or throws.
//
// Both code paths in `ForYouSection` (the empty-state CTA and the
// loaded-state "Edit" chip) call the same `_openProfile`, so a single
// fix covers both. We test both paths to lock the contract.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/features/product_detail/widgets/for_you_section.dart';
import 'package:pharmaguide/features/product_detail/widgets/interaction_warnings.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';

/// Stub notifier that lets us inject a known [ProfileState] without
/// touching the user database. `state =` is StateNotifier's protected
/// setter — accessible from subclasses, which is the conventional way
/// to seed state in tests.
class _StubProfileNotifier extends ProfileNotifier {
  _StubProfileNotifier(ProfileState initial) : super() {
    state = initial;
  }
}

/// Minimal app harness: GoRouter with two routes — `/` mounts
/// [child] (the For You section), `/profile/setup` is a sentinel
/// page we can detect to confirm navigation actually landed there.
Widget _harness({required Widget child, ProfileState? profile}) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => Scaffold(body: child),
      ),
      GoRoute(
        path: Routes.profileSetup,
        builder: (_, __) =>
            const Scaffold(body: Center(child: Text('SETUP_REACHED'))),
      ),
      // The pre-fix code pushed this path. We register it so that if
      // the buggy push were re-introduced, the test would still
      // observe the navigation — but to a different sentinel — and
      // fail loudly rather than throwing an unrelated GoRouter error
      // that obscures the regression.
      GoRoute(
        path: Routes.profile,
        builder: (_, __) =>
            const Scaffold(body: Center(child: Text('SETTINGS_REACHED'))),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      if (profile != null)
        profileProvider.overrideWith((_) => _StubProfileNotifier(profile)),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  group('ForYouSection — edit-profile navigation (T2)', () {
    testWidgets('empty-profile CTA navigates to /profile/setup, not /profile', (
      tester,
    ) async {
      // Default empty profile → renders `_ForYouEmpty` with the
      // tappable PGCard. The unique copy "Add your profile to
      // personalize" is our handle for tapping the affordance.
      await tester.pumpWidget(
        _harness(
          child: const ForYouSection(
            fitResult: null,
            warnings: <InteractionWarning>[],
            maxSeverity: Severity.safe,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Add your profile to personalize'), findsOneWidget);

      await tester.tap(find.text('Add your profile to personalize'));
      await tester.pumpAndSettle();

      // The fix: we MUST land on the ProfileSetup sentinel.
      expect(find.text('SETUP_REACHED'), findsOneWidget);
      // And we MUST NOT have landed on the SettingsScreen sentinel —
      // that's the regression the dev review caught.
      expect(find.text('SETTINGS_REACHED'), findsNothing);
    });

    testWidgets(
      'loaded-profile Edit chip navigates to /profile/setup, not /profile',
      (tester) async {
        // Profile with at least one goal → renders the full card +
        // the `_SectionHeader` with the "Edit" chip.
        await tester.pumpWidget(
          _harness(
            profile: const ProfileState(goals: ['sleep']),
            child: const ForYouSection(
              fitResult: null,
              warnings: <InteractionWarning>[],
              maxSeverity: Severity.safe,
              topGoalLabel: 'sleep',
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Edit'), findsOneWidget);

        await tester.tap(find.text('Edit'));
        await tester.pumpAndSettle();

        expect(find.text('SETUP_REACHED'), findsOneWidget);
        expect(find.text('SETTINGS_REACHED'), findsNothing);
      },
    );
  });
}
